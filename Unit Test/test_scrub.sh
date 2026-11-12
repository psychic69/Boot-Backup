#!/bin/bash
# dr_usb_scrub.sh: live /boot check, the local UNRAID_DR check, and the failure report.
# Everything external is stubbed; the "drives" are folders under a temp directory.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
SCRIPT_DIR="$REPO_ROOT"
source "$REPO_ROOT/lib/logging.sh"; source "$REPO_ROOT/lib/drives.sh"; source "$REPO_ROOT/lib/integrity.sh"
source "$REPO_ROOT/lib/config.sh"
echo "test_scrub"
LOG_FILE=""; DEBUG=false
load_fns "$REPO_ROOT/dr_usb_scrub.sh" report_cache_bypass add_hash_findings scrub_live scrub_local_backup report_results main_scrub
log_message() { echo "$1"; }
declare -a current_drive_state FINDINGS WARNINGS

# ---- stubs ----
CALLS="$TMP_DIR/calls"
mountpoint() { return "${BOOT_MOUNTED_RC:-0}"; }
findmnt()    { return 0; }
mount()      { echo "mount $*" >> "$CALLS"; return "${MOUNT_RC:-0}"; }
umount()     { echo "umount $*" >> "$CALLS"; return 0; }
notify_failure() { echo "notify: $1" >> "$CALLS"; }
quiet() { "$@" >"$TMP_DIR/out" 2>&1; local rc=$?; OUT=$(cat "$TMP_DIR/out"); return $rc; }
calls() { cat "$CALLS" 2>/dev/null; }

# ---- fixtures ----
cat > "$TMP_DIR/test-lsblk" <<EOS
NAME="sdc" UUID="" FSTYPE="" SIZE="16008609792" MOUNTPOINT="" LABEL="" TRAN="usb"
NAME="sdc1" UUID="u" FSTYPE="vfat" SIZE="16007561216" MOUNTPOINT="" LABEL="UNRAID_DR" TRAN=""
EOS
setup() {
    make_boot "$TMP_DIR/boot"; mkdir -p "$TMP_DIR/boot/config"; echo live-config > "$TMP_DIR/boot/config/disk.cfg"
    BOOT_DIR="$TMP_DIR/boot"; CHECK_BACKUP=false; FINDINGS=(); WARNINGS=(); BOOT_MOUNTED_RC=0
    USE_TEST_FILE=true; NOTIFY_ON_FAILURE=true
    MOUNT_RC=0; : > "$CALLS"; current_drive_state=()
    # the local backup USB: a copy of the live tree plus its manifest, "mounted" at CLONE_MP
    CLONE_MP="$TMP_DIR/dr"; rm -rf "$CLONE_MP"; cp -R "$TMP_DIR/boot" "$CLONE_MP"; write_backup_manifest "$CLONE_MP" >/dev/null
}
cd "$TMP_DIR"

# ---------------- live /boot ----------------
# the scrub reports whether files were read from the drive (cache bypass)
setup; CACHE_BYPASS_FAILED=false; quiet scrub_live; assert_contains "bypass reported" "$OUT" "read from the drive itself"
setup; CACHE_BYPASS_FAILED=true; quiet report_cache_bypass; assert_contains "bypass failure warned" "$OUT" "Could not bypass the file cache"
setup; quiet scrub_live; assert_eq "healthy live /boot: ok" "0" "$?"; assert_eq "no findings" "0" "${#FINDINGS[@]}"
setup; echo bad >> "$BOOT_DIR/bzroot"; quiet scrub_live
assert_eq "corrupted live bzroot: fails" "1" "$?"; assert_eq "one finding" "1" "${#FINDINGS[@]}"
assert_contains "finding names the area and file" "${FINDINGS[0]}" "LIVE $BOOT_DIR|bzroot|HASH MISMATCH"
setup; echo bad >> "$BOOT_DIR/previous/bzmodules"; quiet scrub_live
assert_eq "corrupted live previous/bzmodules: fails" "1" "$?"; assert_contains "names the previous/ file" "${FINDINGS[0]}" "previous/bzmodules"
setup; BOOT_MOUNTED_RC=1; quiet scrub_live; assert_eq "/boot not mounted: fails" "1" "$?"; assert_contains "explained" "${FINDINGS[0]}" "IS NOT MOUNTED"

# ---------------- the report ----------------
setup; echo bad >> "$BOOT_DIR/bzroot"; quiet scrub_live; quiet report_results; rc=$?
assert_eq "report returns 1 when something is wrong" "1" "$rc"
assert_contains "harsh banner" "$OUT" "SCRUB FAILED - 1 PROBLEM(S) FOUND"
assert_contains "area and file" "$OUT" "[LIVE $BOOT_DIR]  bzroot"
assert_contains "problem" "$OUT" "problem : HASH MISMATCH"
exp=$(awk '{print $1}' "$BOOT_DIR/bzroot.sha256"); assert_contains "full expected hash printed" "$OUT" "expected: $exp"
act=$(sha_of "$BOOT_DIR/bzroot"); assert_contains "full actual hash printed" "$OUT" "actual  : $act"
assert_contains "size printed" "$OUT" "size    : $(wc -c < "$BOOT_DIR/bzroot" | tr -d ' ') bytes"
assert_contains "advice for the live drive" "$OUT" "your RUNNING Unraid flash drive has damaged"
assert_contains "notification sent" "$(calls)" "notify: Scrub found 1 problem(s)"
setup; quiet report_results; rc=$?
assert_eq "clean report returns 0" "0" "$rc"; assert_contains "clean message" "$OUT" "SCRUB CLEAN"; assert_not_contains "no notification when clean" "$(calls)" "notify"

# ---------------- main without -backup never touches the backup ----------------
setup; quiet main_scrub; assert_eq "live-only scrub: clean" "0" "$?"; assert_contains "mode logged" "$OUT" "live /boot only"
assert_eq "live-only scrub: no mounts, ssh or rsync" "" "$(calls)"

# ---------------- local UNRAID_DR ----------------
setup; CHECK_BACKUP=true; quiet main_scrub
assert_eq "local backup, all healthy: clean" "0" "$?"; assert_contains "chose the local check" "$OUT" "LOCAL UNRAID_DR USB"
assert_contains "mounted read-only" "$(calls)" "mount -o ro /dev/sdc1"; assert_contains "unmounted again" "$(calls)" "umount $CLONE_MP"
setup; CHECK_BACKUP=true; echo live-changed >> "$BOOT_DIR/config/disk.cfg"; echo newer > "$BOOT_DIR/config/extra.cfg"; quiet main_scrub
assert_eq "config changes since the last backup are NOT a problem" "0" "$?"
setup; CHECK_BACKUP=true; echo bad >> "$CLONE_MP/bzroot"; quiet main_scrub
assert_eq "damaged backup bzroot: fails" "1" "$?"; assert_contains "reported against the backup USB" "$OUT" "[BACKUP USB]  bzroot"
assert_contains "advice for the backup USB" "$OUT" "the UNRAID_DR copy is damaged"
setup; CHECK_BACKUP=true; echo bad >> "$CLONE_MP/previous/bzimage"; quiet main_scrub
assert_eq "damaged backup previous/bzimage: fails" "1" "$?"; assert_contains "names it" "$OUT" "previous/bzimage"
setup; CHECK_BACKUP=true; echo bad >> "$CLONE_MP/config/Pro.key"; quiet main_scrub
assert_eq "damaged backup config file (manifest): fails" "1" "$?"; assert_contains "named" "$OUT" "config/Pro.key"; assert_contains "manifest problem described" "$OUT" "DOES NOT MATCH THE MANIFEST"
setup; CHECK_BACKUP=true; rm "$CLONE_MP/config/Pro.key"; quiet main_scrub; assert_eq "missing backup config file: fails" "1" "$?"; assert_contains "reported missing" "$OUT" "MISSING"
setup; CHECK_BACKUP=true; rm "$CLONE_MP/DR_MANIFEST.sums"; quiet main_scrub
assert_eq "no manifest: only a warning" "0" "$?"; assert_contains "warning shown" "$OUT" "no DR_MANIFEST.sums"
setup; CHECK_BACKUP=true; : > "$TMP_DIR/test-lsblk.empty"; cp "$TMP_DIR/test-lsblk" "$TMP_DIR/test-lsblk.bak"; echo 'NAME="sdc1" UUID="u" FSTYPE="vfat" SIZE="1" MOUNTPOINT="" LABEL="OTHER" TRAN=""' > "$TMP_DIR/test-lsblk"
quiet main_scrub; assert_eq "no UNRAID_DR USB: fails" "1" "$?"; assert_contains "explained" "$OUT" "FOUND 0"; cp "$TMP_DIR/test-lsblk.bak" "$TMP_DIR/test-lsblk"
setup; CHECK_BACKUP=true; MOUNT_RC=1; quiet main_scrub; assert_eq "backup USB will not mount: fails" "1" "$?"; assert_contains "explained" "$OUT" "COULD NOT BE MOUNTED"

# ---------------- the remote mirror check was removed in 1.3.0: -backup always checks the local USB ----------------
setup; CHECK_BACKUP=true; : > "$TMP_DIR/remote.ini"; quiet main_scrub
assert_eq "a leftover remote.ini changes nothing: clean" "0" "$?"; assert_contains "-backup checks the LOCAL UNRAID_DR USB" "$OUT" "LOCAL UNRAID_DR USB"
assert_not_contains "no remote check is mentioned" "$OUT" "REMOTE"
assert_contains "the local USB was mounted read-only" "$(calls)" "mount -o ro"

# ---------------- the script itself: options and missing modules ----------------
out=$(bash "$REPO_ROOT/dr_usb_scrub.sh" -bogus 2>&1); rc=$?
assert_eq "unknown option rejected" "1" "$rc"; assert_contains "usage shown" "$out" "Usage:"; assert_contains "usage lists -backup" "$out" "[-backup]"
cp -R "$REPO_ROOT" "$TMP_DIR/copy" 2>/dev/null; rm -rf "$TMP_DIR/copy/dist" "$TMP_DIR/copy/lib"
out=$(bash "$TMP_DIR/copy/dr_usb_scrub.sh" 2>&1); rc=$?
assert_eq "missing lib/ is fatal" "1" "$rc"; assert_contains "missing lib/ is explained" "$out" "Missing module"
finish
