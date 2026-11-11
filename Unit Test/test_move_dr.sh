#!/bin/bash
# Tests for Recovery-ISO/scripts/move_dr_to_unraid.sh. Every disk tool is stubbed and every "device"
# is a regular file under a temp folder, so no real drive is ever referenced or changed.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "test_move_dr"
source "$REPO_ROOT/Recovery-ISO/scripts/move_dr_to_unraid.sh"   # sourcing does not run it
source "$REPO_ROOT/lib/integrity.sh"      # used here to BUILD the fake backup's manifest (the restore script has its own checker)
log_message() { :; }

DEV="$TMP_DIR/dev"; mkdir -p "$DEV"
STATE="$TMP_DIR/label_state"
MP="$TMP_DIR/mnt"

# ---------------- stubs (functions override the real commands) ----------------
id()         { echo "${FAKE_UID:-0}"; }
mountpoint() { return 1; }
mount()      { return "${MOUNT_RC:-0}"; }
umount()     { return "${UMOUNT_RC:-0}"; }
findmnt()    {   # FINDMNT_ONCE=1 -> mounts are listed on the first call only (state kept in a file: calls run in subshells)
    if [ -n "${FINDMNT_ONCE:-}" ]; then
        [ -e "$TMP_DIR/findmnt_done" ] && return 0
        : > "$TMP_DIR/findmnt_done"
    fi
    printf '%b' "${FINDMNT_OUT:-}"
}
sync()       { :; }
is_interactive() { return 0; }
fatlabel() {   # fatlabel <part>  -> print label;  fatlabel <part> <new> -> set it
    if [ $# -ge 2 ]; then [ -n "${FATLABEL_FAIL:-}" ] && return 1; [ -n "${FATLABEL_IGNORE:-}" ] || echo "$2" > "$STATE"; return 0; fi
    cat "$STATE"
}
blkid()      {   # blkid -p -s LABEL -o value <part>: prints the label. BLKID_EMPTY=1 prints nothing; BLKID_FAILS=N fails the first N reads
    [ -n "${BLKID_EMPTY:-}" ] && return 2
    local n; n=$(cat "$TMP_DIR/blkid_fails" 2>/dev/null || echo 0)   # counter kept in a file: reads run in subshells
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$TMP_DIR/blkid_fails"; return 2; fi
    cat "$STATE"
}
blockdev()   { :; }
udevadm()    { :; }
sleep()      { :; }
LABEL_RETRY_DELAYS=(0 0 0 0)
DEVICE_WAIT_SECONDS=2
UDEV_LABEL_DIR="$TMP_DIR/by-label"
lsblk() {
    case "$*" in
        *"-no LABEL"*) [ -n "${LSBLK_EMPTY:-}" ] || cat "$STATE" ;;
        *"-P -b -o NAME,MOUNTPOINT,UUID,FSTYPE,LABEL,SIZE"*) printf '%b' "${LSBLK_FULL:-}" ;;
        *"-P -o NAME,LABEL"*)                                  printf '%b' "${LSBLK_LABELS:-}" ;;
        *"-P -o NAME,UUID"*)                                   printf '%b' "${LSBLK_UUIDS:-}" ;;
        *"-no UUID"*) echo "${FAKE_UUID:-}" ;;
        *PKNAME*)  local p="${*: -1}"; echo "${p%[0-9]}" ;;
        *"-o TRAN"*) local d="${*: -1}"; eval "echo \${TRAN_$(basename "$d"):-}" ;;
        *"-o MODEL"*) echo "Fake USB Stick" ;;
        *"-o SIZE"*)  echo 16008609792 ;;
    esac
}

# ---------------- a fake backup drive tree and fake device files ----------------
make_backup_tree() {   # $1 = mbr size, $2 = EFI layout (EFI- | EFI | both | none)
    rm -rf "$MP"; mkdir -p "$MP/config" "$MP/syslinux"
    touch "$MP/syslinux/syslinux.cfg" "$MP/BACKUP-11-03-2026-03-00"
    mkdir -p "$MP/previous"
    local d f
    for d in "$MP" "$MP/previous"; do                       # Unraid-style bare-hash .sha256 files, root and previous/
        for f in bzimage bzroot bzmodules memtest; do head -c 1024 /dev/urandom > "$d/$f"; sha_of "$d/$f" > "$d/$f.sha256"; done
    done
    echo "license" > "$MP/config/Pro.key"; echo "disk" > "$MP/config/disk.cfg"
    cat > "$MP/syslinux/syslinux_linux" <<'SL'
#!/bin/bash
[ "$1" = "--version" ] && exit "${SYSLINUX_VERSION_RC:-0}"
echo "$@" > "${SYSLINUX_LOG:-/dev/null}"
exit "${SYSLINUX_RC:-0}"
SL
    local size="${1:-447}"
    head -c $((size - 1)) /dev/zero > "$MP/syslinux/mbr.bin"; printf '\x80' >> "$MP/syslinux/mbr.bin"
    case "${2:-EFI-}" in EFI-) mkdir "$MP/EFI-";; EFI) mkdir "$MP/EFI";; both) mkdir "$MP/EFI" "$MP/EFI-";; none) :;; esac
    if [ -z "${NO_MANIFEST:-}" ]; then write_backup_manifest "$MP" >/dev/null; fi
}
make_devices() {       # disk image (4 KB, sentinel at byte 600) and a partition image with a FAT-ish boot sector
    head -c 4096 /dev/zero > "$DEV/sdc"; printf 'S' | dd of="$DEV/sdc" bs=1 seek=600 conv=notrunc 2>/dev/null
    head -c 4096 /dev/zero > "$DEV/sdc1"; printf 'SYSLINUX' | dd of="$DEV/sdc1" bs=1 seek=3 conv=notrunc 2>/dev/null
    echo "UNRAID_DR" > "$STATE"
}
reset_state() {
    VERIFY_PROBLEMS=(); VERIFY_NOTES=(); NO_MANIFEST=""
    BACKUP_PART="$DEV/sdc1"; BACKUP_DISK="$DEV/sdc"; MOUNT_POINT="$MP"; WORK_DIR=""
    BACKUP_UUID=""; RESUME=false; FAKE_UUID=""; LSBLK_UUIDS=""
    BACKUP_MARKER=""; EFI_STATE=""; RELABELED=false; EFI_RENAMED=false
    FATLABEL_FAIL=""; FATLABEL_IGNORE=""; BLKID_EMPTY=""; LSBLK_EMPTY=""; echo 0 > "$TMP_DIR/blkid_fails"; rm -rf "$UDEV_LABEL_DIR"; UMOUNT_RC=0; MOUNT_RC=0; FINDMNT_OUT=""; FINDMNT_ONCE=""
    SYSLINUX_RC=0; SYSLINUX_VERSION_RC=0; SYSLINUX_LOG="$TMP_DIR/syslinux.log"; : > "$SYSLINUX_LOG"; rm -f "$TMP_DIR/findmnt_done"
    export SYSLINUX_RC SYSLINUX_VERSION_RC SYSLINUX_LOG
    make_devices
}
quiet() { "$@" >"$TMP_DIR/out" 2>&1; local rc=$?; OUT=$(cat "$TMP_DIR/out"); return $rc; }

# safety net: nothing in this file may point at a real device
case "$DEV" in "$TMP_DIR"/*) pass "test devices are plain files under the temp folder" ;; *) fail "test devices are plain files"; exit 1 ;; esac

# ---------------- get_column_value ----------------
row='NAME="/dev/sdc1" LABEL="UNRAID_DR" MOUNTPOINT=""'
assert_eq "get_column_value LABEL" "UNRAID_DR" "$(get_column_value "$row" LABEL)"
assert_eq "get_column_value empty" "" "$(get_column_value "$row" MOUNTPOINT)"
assert_eq "get_column_value missing" "" "$(get_column_value "$row" UUID)"
evil='LABEL="x$(touch '"$TMP_DIR"'/PWNED)y" NAME="/dev/sdc1"'
get_column_value "$evil" LABEL >/dev/null
[ ! -e "$TMP_DIR/PWNED" ] && pass "a label containing \$(...) is never executed" || fail "a label containing \$(...) is never executed"

# ---------------- require_environment ----------------
reset_state
FAKE_UID=1000 quiet require_environment; assert_eq "non-root refused" "1" "$?"; assert_contains "non-root message" "$OUT" "must be run as root"
FAKE_UID=0 quiet require_environment; assert_eq "root with all tools accepted" "0" "$?"
out=$( unset -f lsblk fatlabel mount umount mountpoint findmnt; PATH=/nonexistent; require_environment 2>&1 )
assert_contains "missing tools are reported" "$out" "Required tool(s) not found"

# ---------------- check_no_unraid_drive ----------------
reset_state
LSBLK_FULL='NAME="/dev/sdb1" MOUNTPOINT="" UUID="u" FSTYPE="vfat" LABEL="UNRAID" SIZE="16007561216"\n'
quiet check_no_unraid_drive; assert_eq "existing UNRAID drive blocks the restore" "1" "$?"; assert_contains "conflict explained" "$OUT" "already exists"
LSBLK_FULL='NAME="/dev/sdc1" MOUNTPOINT="" UUID="u" FSTYPE="vfat" LABEL="UNRAID_DR" SIZE="16007561216"\n'
quiet check_no_unraid_drive; assert_eq "UNRAID_DR is not a conflict" "0" "$?"
LSBLK_FULL=''; quiet check_no_unraid_drive; assert_eq "no drives is fine" "0" "$?"

# ---------------- find_backup_usb ----------------
reset_state; TRAN_sdc=usb; TRAN_sdd=usb; TRAN_sda=sata
LSBLK_LABELS=''; quiet find_backup_usb; assert_eq "no UNRAID_DR: fails" "1" "$?"; assert_contains "no UNRAID_DR: message" "$OUT" "No drive with the label"
LSBLK_LABELS="NAME=\"$DEV/sda1\" LABEL=\"UNRAID_DR\"\n"; quiet find_backup_usb
assert_eq "non-USB UNRAID_DR: fails" "1" "$?"; assert_contains "non-USB UNRAID_DR: message" "$OUT" "not on USB drives"
LSBLK_LABELS="NAME=\"$DEV/sdc1\" LABEL=\"UNRAID_DR\"\nNAME=\"$DEV/sdd1\" LABEL=\"UNRAID_DR\"\n"; quiet find_backup_usb
assert_eq "two USB UNRAID_DR: fails" "1" "$?"; assert_contains "two USB UNRAID_DR: message" "$OUT" "multiple"
LSBLK_LABELS="NAME=\"$DEV/sdc2\" LABEL=\"UNRAID_DR\"\n"; quiet find_backup_usb
assert_eq "UNRAID_DR on partition 2: fails" "1" "$?"; assert_contains "partition 2 message" "$OUT" "not the first partition"
LSBLK_LABELS="NAME=\"$DEV/sdc1\" LABEL=\"UNRAID_DR\"\nNAME=\"$DEV/sda1\" LABEL=\"\"\n"; quiet find_backup_usb
assert_eq "exactly one USB UNRAID_DR: ok" "0" "$?"
assert_eq "partition recorded" "$DEV/sdc1" "$BACKUP_PART"; assert_eq "disk recorded" "$DEV/sdc" "$BACKUP_DISK"

# ---------------- unmount_all ----------------
reset_state
FINDMNT_OUT='/media/a\n/media/b\n' FINDMNT_ONCE=1 quiet unmount_all "$BACKUP_PART"; assert_eq "mounted partition is unmounted" "0" "$?"
FINDMNT_OUT='/media/a\n' UMOUNT_RC=1 quiet unmount_all "$BACKUP_PART"; assert_eq "umount failure aborts" "1" "$?"
FINDMNT_OUT='/media/a\n' quiet unmount_all "$BACKUP_PART"; assert_eq "still mounted afterwards aborts" "1" "$?"
FINDMNT_OUT='' quiet unmount_all "$BACKUP_PART"; assert_eq "not mounted: nothing to do" "0" "$?"

# ---------------- check_backup_contents ----------------
reset_state; make_backup_tree 447 "EFI-"
quiet check_backup_contents; assert_eq "complete backup accepted" "0" "$?"
assert_eq "EFI- state detected" "EFI-" "$EFI_STATE"; assert_eq "BACKUP marker found" "BACKUP-11-03-2026-03-00" "$BACKUP_MARKER"
[ -x "$WORK_DIR/syslinux_linux" ] && [ -f "$WORK_DIR/mbr.bin" ] && pass "boot-loader tools staged" || fail "boot-loader tools staged"
rm -rf "$WORK_DIR"
reset_state; make_backup_tree 447 EFI-; rm "$MP/bzroot"; quiet check_backup_contents
assert_eq "missing bzroot rejected" "1" "$?"; assert_contains "missing file named" "$OUT" "bzroot"
reset_state; make_backup_tree 448 EFI-; quiet check_backup_contents
assert_eq "448-byte mbr.bin rejected" "1" "$?"; assert_contains "mbr size explained" "$OUT" "448 bytes"
reset_state; make_backup_tree 439 EFI-; quiet check_backup_contents; assert_eq "439-byte mbr.bin rejected" "1" "$?"
reset_state; make_backup_tree 440 EFI-; quiet check_backup_contents; assert_eq "440-byte mbr.bin accepted" "0" "$?"; rm -rf "$WORK_DIR"
reset_state; make_backup_tree 447 both; quiet check_backup_contents; assert_eq "both EFI folders: state" "both" "$EFI_STATE"; assert_contains "both EFI folders: warned" "$OUT" "both EFI and EFI-"; rm -rf "$WORK_DIR"
reset_state; make_backup_tree 447 none; quiet check_backup_contents; assert_eq "no EFI folder: state" "none" "$EFI_STATE"; assert_contains "no EFI folder: warned" "$OUT" "no EFI folder"; rm -rf "$WORK_DIR"
reset_state; make_backup_tree 447 EFI-; rm "$MP/BACKUP-11-03-2026-03-00"; quiet check_backup_contents; assert_eq "no marker: still accepted" "0" "$?"; assert_eq "no marker: empty" "" "$BACKUP_MARKER"; rm -rf "$WORK_DIR"
reset_state; make_backup_tree 447 EFI-; SYSLINUX_VERSION_RC=127 quiet check_backup_contents; assert_eq "unrunnable syslinux_linux rejected" "1" "$?"; rm -rf "$WORK_DIR"

# ---------------- show_summary / confirm_restore ----------------
reset_state; BACKUP_MARKER="BACKUP-11-03-2026-03-00"; quiet show_summary
assert_contains "summary shows the drive" "$OUT" "Fake USB Stick"; assert_contains "summary shows backup time" "$OUT" "11-03-2026 at 03:00"
assert_contains "summary warns it is final" "$OUT" "CANNOT BE UNDONE"
BACKUP_MARKER=""; quiet show_summary; assert_contains "summary flags a missing marker" "$OUT" "UNKNOWN"
confirm_restore <<< "RESTORE" >/dev/null 2>&1; assert_eq "RESTORE accepted" "0" "$?"
confirm_restore <<< "" >/dev/null 2>&1; assert_eq "empty input cancels" "1" "$?"
confirm_restore <<< "restore" >/dev/null 2>&1; assert_eq "lowercase then EOF cancels" "1" "$?"
confirm_restore <<< $'yes\nRESTORE' >/dev/null 2>&1; assert_eq "second attempt accepted" "0" "$?"
confirm_restore <<< $'yes\nno' >/dev/null 2>&1; assert_eq "two wrong answers cancel" "1" "$?"

# ---------------- relabel_backup ----------------
reset_state; quiet relabel_backup; assert_eq "relabel succeeds" "0" "$?"; assert_eq "label is UNRAID" "UNRAID" "$(cat "$STATE")"; assert_eq "RELABELED recorded" "true" "$RELABELED"
reset_state; FATLABEL_FAIL=1 quiet relabel_backup; assert_eq "fatlabel failure reported" "1" "$?"; assert_eq "RELABELED stays false" "false" "$RELABELED"
reset_state; FATLABEL_IGNORE=1 quiet relabel_backup; assert_eq "label that did not take is caught" "1" "$?"

# FAT labels are stored space-padded: a padded read-back must still count as a match
fatlabel_padded() { if [ $# -ge 2 ]; then echo "$2" > "$STATE"; else printf '%s   \n' "$(cat "$STATE")"; fi; }
reset_state; eval "$(declare -f fatlabel | sed 's/^fatlabel ()/fatlabel_plain ()/')"; fatlabel() { fatlabel_padded "$@"; }
quiet relabel_backup; assert_eq "padded label read-back still matches" "0" "$?"
echo UNRAID > "$STATE"; make_backup_tree 447 EFI; EFI_STATE="EFI"; printf '\x80' | dd of="$DEV/sdc" bs=1 seek=446 conv=notrunc 2>/dev/null
quiet verify_result; assert_eq "padded label passes final verification" "0" "$?"
eval "$(declare -f fatlabel_plain | sed 's/^fatlabel_plain ()/fatlabel ()/')"

# ---------------- get_label / confirm_label (the label is boot-critical: Unraid will not boot without 'UNRAID') ----------------
# fatlabel prints "There are differences between boot sector and its backup." on STDOUT after the syslinux install.
fatlabel_warns() { if [ $# -ge 2 ]; then echo "$2" > "$STATE"; else echo "There are differences between boot sector and its backup."; echo "  282:40/80"; cat "$STATE"; fi; }
eval "$(declare -f fatlabel | sed 's/^fatlabel ()/fatlabel_plain2 ()/')"
reset_state; echo UNRAID > "$STATE"
assert_eq "get_label uses blkid" "UNRAID" "$(get_label "$BACKUP_PART")"
fatlabel() { fatlabel_warns "$@"; }
assert_eq "get_label ignores the fatlabel boot-sector warning" "UNRAID" "$(get_label "$BACKUP_PART")"
BLKID_EMPTY=1; assert_eq "blkid empty: falls back to lsblk" "UNRAID" "$(get_label "$BACKUP_PART")"
LSBLK_EMPTY=1; assert_eq "blkid and lsblk empty: fatlabel's LAST line is the label, not the warning" "UNRAID" "$(get_label "$BACKUP_PART")"
out=$( unset -f blkid; LSBLK_EMPTY=1; get_label "$BACKUP_PART" ); assert_eq "blkid not installed: still reads the label" "UNRAID" "$out"
# the exact failure seen on real hardware: warning on stdout while verifying after the syslinux install
reset_state; echo UNRAID > "$STATE"; BLKID_EMPTY=1; LSBLK_EMPTY=1; make_backup_tree 447 EFI; EFI_STATE="EFI"
printf '\x80' | dd of="$DEV/sdc" bs=1 seek=446 conv=notrunc 2>/dev/null
quiet verify_result; assert_eq "verification passes despite the fatlabel warning" "0" "$?"
reset_state; echo UNRAID > "$STATE"; make_backup_tree 447 EFI; EFI_STATE="EFI"; printf '\x80' | dd of="$DEV/sdc" bs=1 seek=446 conv=notrunc 2>/dev/null
echo 2 > "$TMP_DIR/blkid_fails"; LSBLK_EMPTY=1; fatlabel() { return 1; }; quiet confirm_label; LSBLK_EMPTY=""; fatlabel() { fatlabel_warns "$@"; }; assert_eq "label unreadable at first, then read: retried and confirmed" "0" "$?"; assert_contains "retry is announced" "$OUT" "retrying in"
reset_state; echo UNRAID_DR > "$STATE"; quiet confirm_label; assert_eq "wrong label: fails" "1" "$?"; assert_eq "wrong label: reported" "UNRAID_DR" "$LABEL_READ"
reset_state; echo UNRAID > "$STATE"; BLKID_EMPTY=1; LSBLK_EMPTY=1; fatlabel() { return 1; }
quiet confirm_label; assert_eq "unreadable by every method and no udev link: fails (no skipping)" "1" "$?"
quiet label_report; assert_contains "failure report lists each method" "$OUT" "blkid:"; assert_contains "failure report shows the by-label link" "$OUT" "by-label"
# last resort: /dev/disk/by-label/UNRAID must resolve to THIS partition
mkdir -p "$UDEV_LABEL_DIR"; ln -s "$BACKUP_PART" "$UDEV_LABEL_DIR/UNRAID"
quiet confirm_label; assert_eq "udev link points at our partition: accepted with a warning" "0" "$?"; assert_contains "udev fallback warns" "$OUT" "udev reports"
rm -f "$UDEV_LABEL_DIR/UNRAID"; ln -s "$DEV/sdz1" "$UDEV_LABEL_DIR/UNRAID"; touch "$DEV/sdz1"
quiet confirm_label; assert_eq "udev link points at ANOTHER drive: refused" "1" "$?"
rm -f "$UDEV_LABEL_DIR/UNRAID"; ln -s "$DEV/does_not_exist" "$UDEV_LABEL_DIR/UNRAID"
quiet confirm_label; assert_eq "dangling udev link: refused" "1" "$?"
out=$( unset -f udevadm; mkdir -p "$UDEV_LABEL_DIR"; rm -f "$UDEV_LABEL_DIR/UNRAID"; ln -s "$BACKUP_PART" "$UDEV_LABEL_DIR/UNRAID"; PATH=/nonexistent; confirm_label >/dev/null 2>&1; echo $? )
assert_eq "no udevadm: the udev fallback is skipped and it fails" "1" "$out"
fatlabel() { fatlabel_plain2 "$@"; }
eval "$(declare -f fatlabel_plain2 | sed 's/^fatlabel_plain2 ()/fatlabel ()/')"
BLKID_EMPTY=""; LSBLK_EMPTY=""; rm -rf "$UDEV_LABEL_DIR"

# ---------------- enable_uefi ----------------
reset_state; make_backup_tree 447 EFI-; quiet enable_uefi
assert_eq "enable_uefi succeeds" "0" "$?"; [ -d "$MP/EFI" ] && [ ! -d "$MP/EFI-" ] && pass "EFI- renamed to EFI" || fail "EFI- renamed to EFI"; assert_eq "rename recorded" "true" "$EFI_RENAMED"
reset_state; make_backup_tree 447 EFI; quiet enable_uefi; [ -d "$MP/EFI" ] && assert_eq "existing EFI left alone" "false" "$EFI_RENAMED"
reset_state; make_backup_tree 447 both; quiet enable_uefi; [ -d "$MP/EFI" ] && [ -d "$MP/EFI-" ] && pass "both folders left as found" || fail "both folders left as found"
reset_state; make_backup_tree 447 none; quiet enable_uefi; assert_eq "no EFI folder is only a warning" "0" "$?"

# ---------------- install_bootloader / write_mbr ----------------
reset_state; make_backup_tree 447 EFI-; quiet check_backup_contents
quiet install_bootloader; assert_eq "install_bootloader succeeds" "0" "$?"; assert_contains "installs on the partition with -f --install" "$(cat "$SYSLINUX_LOG")" "-f --install $DEV/sdc1"
SYSLINUX_RC=1 quiet install_bootloader; assert_eq "syslinux failure is detected" "1" "$?"
quiet write_mbr; assert_eq "write_mbr succeeds" "0" "$?"
first=$(dd if="$DEV/sdc" bs=1 skip=446 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'); assert_eq "active flag byte written" "80" "$first"
assert_eq "bytes after the MBR are untouched" "S" "$(dd if="$DEV/sdc" bs=1 skip=600 count=1 2>/dev/null)"
cmp() { return 1; }; quiet write_mbr; assert_eq "read-back mismatch is detected" "1" "$?"; unset -f cmp
head -c 448 /dev/zero > "$WORK_DIR/mbr.bin"; head -c 4096 /dev/zero > "$DEV/sdc"; quiet write_mbr
assert_eq "oversize mbr.bin is refused" "1" "$?"; assert_eq "disk untouched when refused" "0" "$(cmp -s "$DEV/sdc" <(head -c 4096 /dev/zero); echo $?)"
rm -rf "$WORK_DIR"

# ---------------- verify_result ----------------
reset_state; make_backup_tree 447 EFI; EFI_STATE="EFI-"; echo UNRAID > "$STATE"
printf '\x80' | dd of="$DEV/sdc" bs=1 seek=446 conv=notrunc 2>/dev/null
quiet verify_result; assert_eq "good result verifies" "0" "$?"; assert_contains "reports active partition" "$OUT" "marked active"
echo UNRAID_DR > "$STATE"; quiet verify_result; assert_eq "wrong label fails verification" "1" "$?"; echo UNRAID > "$STATE"
rmdir "$MP/EFI"; quiet verify_result; assert_eq "missing EFI fails verification" "1" "$?"; mkdir "$MP/EFI"
head -c 4096 /dev/zero > "$DEV/sdc"; quiet verify_result
assert_eq "missing active flag is only a warning" "0" "$?"; assert_contains "warns about the flag" "$OUT" "not marked active"

# ---------------- both sides agree on the manifest name ----------------
assert_eq "restore script and backup library use the same manifest name" "$BACKUP_MANIFEST_NAME" "$MANIFEST_NAME"

# ---------------- verify_backup_hashes (root AND previous/) ----------------
reset_state; make_backup_tree 447 EFI-; quiet verify_backup_hashes
assert_eq "healthy backup: no problems" "0" "${#VERIFY_PROBLEMS[@]}"; assert_contains "healthy backup: all matched" "$OUT" "8 file(s) match"
reset_state; make_backup_tree 447 EFI-; echo bad >> "$MP/bzroot"; quiet verify_backup_hashes
assert_eq "tampered root bzroot: one problem" "1" "${#VERIFY_PROBLEMS[@]}"; assert_contains "names bzroot" "${VERIFY_PROBLEMS[0]}" "bzroot"
reset_state; make_backup_tree 447 EFI-; echo bad >> "$MP/previous/bzmodules"; quiet verify_backup_hashes
assert_eq "tampered previous/bzmodules: one problem" "1" "${#VERIFY_PROBLEMS[@]}"; assert_contains "names previous/bzmodules" "${VERIFY_PROBLEMS[0]}" "previous/bzmodules"
reset_state; make_backup_tree 447 EFI-; rm "$MP/previous/memtest"; quiet verify_backup_hashes
assert_eq "file missing but .sha256 present: a problem" "1" "${#VERIFY_PROBLEMS[@]}"
reset_state; make_backup_tree 447 EFI-; echo "nonsense" > "$MP/bzimage.sha256"; quiet verify_backup_hashes
assert_eq "invalid .sha256: not a problem" "0" "${#VERIFY_PROBLEMS[@]}"; assert_eq "invalid .sha256: a note" "1" "${#VERIFY_NOTES[@]}"
reset_state; make_backup_tree 447 EFI-; rm -rf "$MP/previous"; quiet verify_backup_hashes; assert_eq "no previous/ folder is fine" "0" "${#VERIFY_PROBLEMS[@]}"

# ---------------- verify_backup_manifest ----------------
reset_state; make_backup_tree 447 EFI-; quiet verify_backup_manifest
assert_eq "healthy manifest: no problems" "0" "${#VERIFY_PROBLEMS[@]}"; assert_contains "reports the match count" "$OUT" "match the manifest"
reset_state; make_backup_tree 447 EFI-; echo changed >> "$MP/config/Pro.key"; quiet verify_backup_manifest
assert_eq "changed config file: one problem" "1" "${#VERIFY_PROBLEMS[@]}"; assert_contains "names the config file" "${VERIFY_PROBLEMS[0]}" "config/Pro.key"
reset_state; make_backup_tree 447 EFI-; rm "$MP/config/disk.cfg"; quiet verify_backup_manifest
assert_eq "deleted config file: one problem" "1" "${#VERIFY_PROBLEMS[@]}"
reset_state; NO_MANIFEST=1 make_backup_tree 447 EFI-; NO_MANIFEST=1; quiet verify_backup_manifest
assert_eq "no manifest: not a problem" "0" "${#VERIFY_PROBLEMS[@]}"; assert_eq "no manifest: a note" "1" "${#VERIFY_NOTES[@]}"
reset_state; make_backup_tree 447 EFI-; echo more >> "$MP/ldlinux.sys" 2>/dev/null; echo sys > "$MP/ldlinux.sys"; echo c32 > "$MP/ldlinux.c32"; quiet verify_backup_manifest
assert_eq "ldlinux.* are not in the manifest (the syslinux install rewrites them)" "0" "${#VERIFY_PROBLEMS[@]}"

# ---------------- confirm_override / summary ----------------
reset_state; confirm_override <<< "" >/dev/null 2>&1; assert_eq "no problems: no override needed" "0" "$?"
VERIFY_PROBLEMS=("bzroot: does not match"); confirm_override <<< "OVERRIDE" >/dev/null 2>&1; assert_eq "OVERRIDE accepted" "0" "$?"
confirm_override <<< "" >/dev/null 2>&1; assert_eq "Enter cancels the override" "1" "$?"
confirm_override <<< "RESTORE" >/dev/null 2>&1; assert_eq "RESTORE is not an override" "1" "$?"
confirm_override <<< $'override\nOVERRIDE' >/dev/null 2>&1; assert_eq "second attempt accepted" "0" "$?"
VERIFY_PROBLEMS=(); for i in $(seq 1 25); do VERIFY_PROBLEMS+=("file$i: does not match"); done; BACKUP_MARKER=""; quiet show_summary
assert_contains "summary shows the problem count" "$OUT" "25 file(s) on the backup FAILED verification"
assert_contains "summary caps the list" "$OUT" "and 5 more"
VERIFY_PROBLEMS=(); VERIFY_NOTES=("a note"); quiet show_summary; assert_contains "summary shows the all-clear" "$OUT" "All checked files match"; assert_contains "summary shows notes" "$OUT" "a note"

# ---------------- ensure_backup_part (the stick vanished and came back) ----------------
reset_state; quiet ensure_backup_part; assert_eq "present device: nothing to do" "0" "$?"
reset_state; BACKUP_PART="$DEV/gone1"; quiet ensure_backup_part; assert_eq "device never returns: fails" "1" "$?"; assert_contains "…and says to replug and rerun" "$OUT" "run this script again"
reset_state; BACKUP_PART="$DEV/gone1"; BACKUP_DISK="$DEV/gone"; BACKUP_UUID="AAAA-1111"
LSBLK_UUIDS="NAME=\"$DEV/sdc1\" UUID=\"AAAA-1111\"\n"
quiet ensure_backup_part; assert_eq "re-attached under another name: found by UUID" "0" "$?"
assert_eq "…BACKUP_PART updated" "$DEV/sdc1" "$BACKUP_PART"; assert_eq "…BACKUP_DISK updated" "$DEV/sdc" "$BACKUP_DISK"
reset_state; BACKUP_PART="$DEV/gone1"; BACKUP_UUID="AAAA-1111"; LSBLK_UUIDS="NAME=\"$DEV/sdc1\" UUID=\"BBBB-2222\"\n"
quiet ensure_backup_part; assert_eq "a different drive's UUID is not accepted" "1" "$?"
reset_state; BACKUP_PART="$DEV/gone1"; quiet relabel_backup; assert_eq "relabel on a vanished stick fails cleanly" "1" "$?"; assert_eq "…and does not change any label" "UNRAID_DR" "$(cat "$STATE")"
reset_state; BACKUP_PART="$DEV/gone1"; RELABELED=true; quiet rollback; assert_contains "rollback on a vanished stick explains how to resume" "$OUT" "resumes an"

# ---------------- resuming an unfinished restore ----------------
resume_setup() {   # a USB partition already labelled UNRAID that still carries its BACKUP-* marker
    reset_state; make_backup_tree 447 EFI-; TRAN_sdc=usb
    LSBLK_FULL="NAME=\"$DEV/sdc1\" MOUNTPOINT=\"\" UUID=\"u\" FSTYPE=\"vfat\" LABEL=\"UNRAID\" SIZE=\"16007561216\"\n"
    FINDMNT_OUT="$MP\n"; echo UNRAID > "$STATE"
}
resume_setup; quiet check_no_unraid_drive; assert_eq "UNRAID + BACKUP marker on USB: resumed, not refused" "0" "$?"; assert_eq "…RESUME set" "true" "$RESUME"
resume_setup; rm -f "$MP"/BACKUP-*; quiet check_no_unraid_drive; assert_eq "UNRAID without a BACKUP marker (a real Unraid flash): refused" "1" "$?"; assert_eq "…RESUME not set" "false" "$RESUME"
resume_setup; TRAN_sdc=sata; quiet check_no_unraid_drive; assert_eq "UNRAID with a marker but not on USB: refused" "1" "$?"; TRAN_sdc=usb
resume_setup; LSBLK_FULL="NAME=\"$DEV/sdc1\" MOUNTPOINT=\"\" UUID=\"u\" FSTYPE=\"vfat\" LABEL=\"UNRAID\" SIZE=1\nNAME=\"/dev/sdb1\" MOUNTPOINT=\"\" UUID=\"v\" FSTYPE=\"vfat\" LABEL=\"UNRAID\" SIZE=1\n"
quiet check_no_unraid_drive; assert_eq "a real UNRAID drive next to the half-restored stick: still refused" "1" "$?"
resume_setup; LSBLK_LABELS="NAME=\"$DEV/sdc1\" LABEL=\"UNRAID\"\n"; RESUME=true; BACKUP_PART=""; BACKUP_DISK=""
quiet find_backup_usb; assert_eq "resume: the UNRAID stick is found" "0" "$?"; assert_eq "…as the backup partition" "$DEV/sdc1" "$BACKUP_PART"
resume_setup; RESUME=true; quiet relabel_backup; assert_eq "resume: relabel step only checks the label" "0" "$?"; assert_eq "…RELABELED stays false (rollback must not flip it back)" "false" "$RELABELED"

flow_resume() { resume_setup; FINDMNT_OUT="$MP\n"; FINDMNT_ONCE=1; LSBLK_LABELS="NAME=\"$DEV/sdc1\" LABEL=\"UNRAID\"\n"; BACKUP_PART=""; BACKUP_DISK=""; }
flow_resume
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "RESUME flow: exit 0" "0" "$rc"; assert_contains "RESUME flow: says it is resuming" "$OUT" "will be resumed"; assert_contains "RESUME flow: final message" "$OUT" "All done!"
[ -d "$MP/EFI" ] && [ ! -d "$MP/EFI-" ] && pass "RESUME flow: UEFI enabled" || fail "RESUME flow: UEFI enabled"
assert_eq "RESUME flow: label still UNRAID" "UNRAID" "$(cat "$STATE")"
cleanup

# ---------------- main: whole flows ----------------
flow_setup() {
    reset_state; make_backup_tree 447 EFI-; TRAN_sdc=usb
    LSBLK_FULL="NAME=\"$DEV/sdc1\" MOUNTPOINT=\"\" UUID=\"u\" FSTYPE=\"vfat\" LABEL=\"UNRAID_DR\" SIZE=\"16007561216\"\n"
    LSBLK_LABELS="NAME=\"$DEV/sdc1\" LABEL=\"UNRAID_DR\"\n"
    BACKUP_PART=""; BACKUP_DISK=""     # main() finds these itself
}
flow_setup
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "SUCCESS flow: exit 0" "0" "$rc"; assert_contains "SUCCESS flow: final message" "$OUT" "All done!"
assert_contains "SUCCESS flow: re-license reminder" "$OUT" "replace your license key"
assert_eq "SUCCESS flow: label is UNRAID" "UNRAID" "$(cat "$STATE")"
[ -d "$MP/EFI" ] && [ ! -d "$MP/EFI-" ] && pass "SUCCESS flow: UEFI enabled" || fail "SUCCESS flow: UEFI enabled"
assert_eq "SUCCESS flow: MBR active flag written" "80" "$(dd if="$DEV/sdc" bs=1 skip=446 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
cleanup

flow_setup; SYSLINUX_RC=1
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "FAILURE flow: exit 1" "1" "$rc"; assert_contains "FAILURE flow: says it did not complete" "$OUT" "did NOT complete"
assert_eq "FAILURE flow: label rolled back" "UNRAID_DR" "$(cat "$STATE")"
[ -d "$MP/EFI-" ] && [ ! -d "$MP/EFI" ] && pass "FAILURE flow: EFI- restored" || fail "FAILURE flow: EFI- restored"
assert_contains "FAILURE flow: tells you it is safe to retry" "$OUT" "safe to run this script again"
cleanup

flow_setup; FATLABEL_FAIL=1
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "RELABEL-FAILURE flow: exit 1" "1" "$rc"; assert_eq "RELABEL-FAILURE flow: label unchanged" "UNRAID_DR" "$(cat "$STATE")"
[ -d "$MP/EFI-" ] && pass "RELABEL-FAILURE flow: EFI- untouched" || fail "RELABEL-FAILURE flow: EFI- untouched"
cleanup

flow_setup
OUT=$(main <<< "" 2>&1); rc=$?
assert_eq "CANCEL flow: exit 1" "1" "$rc"; assert_contains "CANCEL flow: nothing changed" "$OUT" "Nothing was changed"
assert_eq "CANCEL flow: label unchanged" "UNRAID_DR" "$(cat "$STATE")"; [ -d "$MP/EFI-" ] && pass "CANCEL flow: EFI- untouched" || fail "CANCEL flow: EFI- untouched"
assert_eq "CANCEL flow: MBR untouched" "0" "$(dd if="$DEV/sdc" bs=1 skip=446 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | sed 's/^00$/0/')"
cleanup

flow_setup; LSBLK_FULL='NAME="/dev/sdb1" MOUNTPOINT="" UUID="u" FSTYPE="vfat" LABEL="UNRAID" SIZE="1"\n'
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "CONFLICT flow: exit 1" "1" "$rc"; assert_eq "CONFLICT flow: label unchanged" "UNRAID_DR" "$(cat "$STATE")"
cleanup

flow_setup; FINDMNT_OUT="/media/x\n" UMOUNT_RC=1
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "UNMOUNT-FAILURE flow: exit 1" "1" "$rc"; assert_eq "UNMOUNT-FAILURE flow: nothing changed" "UNRAID_DR" "$(cat "$STATE")"
cleanup

# --- verification failures: OVERRIDE needed, then RESTORE ---
flow_setup; echo bad >> "$MP/bzroot"
OUT=$(main <<< $'OVERRIDE\nRESTORE' 2>&1); rc=$?
assert_eq "OVERRIDE flow (corrupt bzroot): restores" "0" "$rc"; assert_contains "OVERRIDE flow: failure was listed" "$OUT" "FAILED verification"
assert_eq "OVERRIDE flow: label changed" "UNRAID" "$(cat "$STATE")"; cleanup
flow_setup; echo bad >> "$MP/bzroot"
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "corrupt bzroot, RESTORE typed at the OVERRIDE prompt: cancelled" "1" "$rc"; assert_eq "…and nothing changed" "UNRAID_DR" "$(cat "$STATE")"; cleanup
flow_setup; echo bad >> "$MP/previous/bzimage"
OUT=$(main <<< "" 2>&1); rc=$?
assert_eq "corrupt previous/bzimage, Enter: cancelled" "1" "$rc"; assert_contains "…says nothing was changed" "$OUT" "Nothing was changed"
assert_contains "…and named the previous/ file" "$OUT" "previous/bzimage"; cleanup
flow_setup; echo bad >> "$MP/config/Pro.key"
OUT=$(main <<< $'OVERRIDE\nRESTORE' 2>&1); rc=$?
assert_eq "tampered config + OVERRIDE: restores" "0" "$rc"; assert_contains "…and the config file was named" "$OUT" "config/Pro.key"; cleanup
flow_setup; rm "$MP/DR_MANIFEST.sums"
OUT=$(main <<< "RESTORE" 2>&1); rc=$?
assert_eq "no manifest: RESTORE alone is enough" "0" "$rc"; assert_contains "no manifest: user is told" "$OUT" "has no DR_MANIFEST.sums"; cleanup

OUT=$(main --bogus 2>&1); assert_contains "arguments are rejected" "$OUT" "takes no options"
is_interactive() { return 1; }; flow_setup; OUT=$(main <<< "RESTORE" 2>&1); assert_contains "non-terminal refused" "$OUT" "must be run from a terminal"
finish
