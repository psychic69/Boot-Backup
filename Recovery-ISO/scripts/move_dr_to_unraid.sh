#!/bin/bash

# move_dr_to_unraid.sh - EMERGENCY, ONE-WAY RESTORE
#
# Turns the UNRAID_DR backup USB into your main Unraid boot drive. Run it from the
# SystemRescue emergency environment, ONLY when the original Unraid USB is dead.
#
# What it does (the same result as Unraid's own make_bootable_linux, done here so every
# step is checked):
#   1. read-only checks of the system and of the backup USB, including SHA-256 checks of the boot
#      files (root and previous/) against Unraid's own .sha256 files, and of config/ etc. against
#      the DR_MANIFEST.sums that dr_usb_backup.sh wrote. Failures are listed and need a typed OVERRIDE
#   2. shows you the drive and the backup time, and asks you to type RESTORE
#   3. relabels the partition UNRAID_DR -> UNRAID
#   4. renames EFI- -> EFI (enables UEFI boot)
#   5. installs the syslinux boot loader and writes the MBR, using the binaries that
#      shipped on the backup itself (syslinux/syslinux_linux and syslinux/mbr.bin)
#   6. verifies the result
# If step 3-6 fail, the label and EFI folder are put back so the USB is exactly a backup
# again and you can retry. The point of no return is rebooting with this USB.
# If the USB drops off the system part-way (seen on real hardware), the script waits for it to come back and finds it
# again by its filesystem UUID. If it never returns, replug it and run the script again: a stick that is already labelled
# UNRAID but still carries its BACKUP-* marker is treated as an unfinished restore and is resumed.
#
# NOTE: this script is copied by itself onto the Ventoy recovery USB, so it cannot use lib/.
# NOTE: We do NOT use 'set -e' because several commands are expected to return non-zero
#       while searching for devices that may not exist; every important step is checked.

# --- Configuration ---
BACKUP_LABEL="UNRAID_DR"
FINAL_LABEL="UNRAID"
# Unraid's syslinux/mbr.bin is 447 bytes: boot code (0-439), disk signature area (440-445) and
# byte 446, the first partition's active/boot flag. Anything larger would overwrite the
# partition table, so it is refused.
MBR_MIN_BYTES=440
MBR_MAX_BYTES=447
# Written by dr_usb_backup.sh onto the backup USB (see lib/integrity.sh): hashes of config/, syslinux/, EFI-/ etc.
MANIFEST_NAME="DR_MANIFEST.sums"
MAX_PROBLEMS_SHOWN=20
# Unraid will not boot unless the flash drive is labelled exactly UNRAID, so the label is confirmed with retries.
# Seconds to wait before each retry if the first read does not show the label (2+4+8+16 = 30s in total).
LABEL_RETRY_DELAYS=(2 4 8 16)
DEVICE_WAIT_SECONDS=30                # how long to wait for a USB stick that vanished to reappear
UDEV_LABEL_DIR="/dev/disk/by-label"   # udev's label symlinks (a variable so the tests can point it elsewhere)

# --- State shared between steps ---
BACKUP_PART=""        # e.g. /dev/sdc1
BACKUP_DISK=""        # e.g. /dev/sdc
BACKUP_UUID=""        # filesystem UUID of the partition (it survives a relabel, so the stick can be found again if it re-attaches as another sdX)
RESUME=false          # true when the stick is already labelled UNRAID but the restore never finished
MOUNT_POINT=""
WORK_DIR=""
BACKUP_MARKER=""
EFI_STATE=""          # EFI | EFI- | both | none (as found on the backup)
VERIFY_PROBLEMS=()    # files that failed a hash check (restore needs an explicit OVERRIDE)
VERIFY_NOTES=()       # things that could not be checked (shown, but not blocking)
RELABELED=false
EFI_RENAMED=false

# --- Output helpers ---
err()  { echo "🛑 ERROR: $*" >&2; }
warn() { echo "⚠️  WARNING: $*" >&2; }

# --- Get one value from an lsblk -P (KEY="value") line, without using eval ---
get_column_value() {
    local row="$1"
    local column_name="$2"
    local pattern="${column_name}=\"([^\"]*)\""
    if [[ $row =~ $pattern ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# --- Remove temporary mounts and files on exit ---
cleanup() {
    if [ -n "$MOUNT_POINT" ]; then
        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            umount "$MOUNT_POINT" 2>/dev/null
        fi
        rmdir "$MOUNT_POINT" 2>/dev/null
    fi
    if [ -n "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# --- True when input comes from a terminal (a function so the tests can override it) ---
is_interactive() { [ -t 0 ]; }

# --- Must be root and have the tools this script uses ---
require_environment() {
    if [ "$(id -u)" -ne 0 ]; then
        err "This script must be run as root (SystemRescue logs in as root by default)."
        return 1
    fi
    local missing=() cmd
    # (blkid, blockdev and udevadm are used when present but are not required: get_label falls back to lsblk / fatlabel)
    for cmd in lsblk fatlabel mount umount mountpoint findmnt dd cmp od wc mktemp awk; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        err "Required tool(s) not found: ${missing[*]}"
        return 1
    fi
    return 0
}

# --- True when a partition labelled UNRAID is really an unfinished restore, not a working Unraid flash drive:
# a USB drive, first partition, that still has the BACKUP-* marker file only a backup stick carries ---
is_unfinished_restore() {
    local part="$1" parent tran dir tmp="" found=1
    parent=$(lsblk -p -n -o PKNAME "$part" 2>/dev/null | head -n 1)
    [ -n "$parent" ] || return 1
    tran=$(lsblk -n -d -o TRAN "$parent" 2>/dev/null | head -n 1 | tr -d ' ')
    [ "$tran" = "usb" ] || return 1
    [ "$part" = "${parent}1" ] || return 1
    dir=$(findmnt -rn -S "$part" -o TARGET 2>/dev/null | head -n 1)
    if [ -z "$dir" ]; then
        tmp=$(mktemp -d /mnt/unraid_check.XXXXXX) || return 1
        if ! mount -o ro "$part" "$tmp" 2>/dev/null; then
            rmdir "$tmp" 2>/dev/null
            return 1
        fi
        dir="$tmp"
    fi
    [ -n "$(find "$dir" -maxdepth 1 -type f -name 'BACKUP-*' 2>/dev/null | head -n 1)" ] && found=0
    if [ -n "$tmp" ]; then
        umount "$tmp" 2>/dev/null
        rmdir "$tmp" 2>/dev/null
    fi
    return $found
}

# --- 1a. Refuse to run if a drive labelled UNRAID already exists ---
check_no_unraid_drive() {
    echo "Checking for existing '$FINAL_LABEL' drive..."
    local line label found="" cand
    local -a resumable=()
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        label=$(get_column_value "$line" "LABEL")
        [ "$label" = "$FINAL_LABEL" ] || continue
        cand=$(get_column_value "$line" "NAME")
        if is_unfinished_restore "$cand"; then
            resumable+=("$cand")
            continue
        fi
        found="$line"
        break
    done < <(lsblk -p -n -P -b -o NAME,MOUNTPOINT,UUID,FSTYPE,LABEL,SIZE 2>/dev/null)

    if [ -z "$found" ] && [ ${#resumable[@]} -gt 1 ]; then
        err "More than one USB drive labelled '$FINAL_LABEL' looks like an unfinished restore: ${resumable[*]}"
        echo "   Please leave only one of them plugged in and try again." >&2
        return 1
    fi
    if [ -z "$found" ] && [ ${#resumable[@]} -eq 1 ]; then
        RESUME=true
        echo "↪️  ${resumable[0]} is already labelled '$FINAL_LABEL' but still carries its backup marker:"
        echo "   an earlier restore did not finish. It will be resumed from where it stopped."
        echo "---"
        return 0
    fi
    if [ -z "$found" ]; then
        echo "No conflicting '$FINAL_LABEL' drive found. Proceeding..."
        echo "---"
        return 0
    fi

    local name mountpoint uuid fstype size parent tran size_human
    name=$(get_column_value "$found" "NAME")
    mountpoint=$(get_column_value "$found" "MOUNTPOINT")
    uuid=$(get_column_value "$found" "UUID")
    fstype=$(get_column_value "$found" "FSTYPE")
    size=$(get_column_value "$found" "SIZE")
    parent=$(lsblk -p -n -o PKNAME "$name" 2>/dev/null | head -n 1)
    tran=""
    [ -n "$parent" ] && tran=$(lsblk -n -d -o TRAN "$parent" 2>/dev/null | head -n 1 | tr -d ' ')
    [ -n "$mountpoint" ] || mountpoint="[none]"
    size_human="$size bytes"
    if command -v numfmt >/dev/null 2>&1 && [[ "$size" =~ ^[0-9]+$ ]]; then
        size_human="$(numfmt --to=iec-i --suffix=B --format="%.2f" "$size") ($size bytes)"
    fi

    err "A drive with the label '$FINAL_LABEL' already exists."
    echo "   This script is for emergencies where the '$FINAL_LABEL' drive is *missing* or *dead*." >&2
    echo "   Please remove the conflicting drive and try again." >&2
    echo >&2
    echo "   Detailed information on conflicting drive:" >&2
    echo "   -------------------------------------------" >&2
    echo "   Drive location:   $name" >&2
    echo "   Current Mountpoint: $mountpoint" >&2
    echo "   UUID:             $uuid" >&2
    echo "   File type:        $fstype" >&2
    echo "   Current Label:    $FINAL_LABEL" >&2
    echo "   Drive Size:       $size_human" >&2
    echo "   Transport Type:   $tran" >&2
    return 1
}

# --- 1b. Find ONE and ONLY ONE USB drive labelled UNRAID_DR, on its first partition ---
find_backup_usb() {
    local want="$BACKUP_LABEL"
    [ "$RESUME" = true ] && want="$FINAL_LABEL"
    echo "Searching for a *single* USB drive with label '$want'..."
    local -a usb_parts=() usb_disks=() other_parts=()
    local line label name parent tran
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        label=$(get_column_value "$line" "LABEL")
        [ "$label" = "$want" ] || continue
        name=$(get_column_value "$line" "NAME")
        parent=$(lsblk -p -n -o PKNAME "$name" 2>/dev/null | head -n 1)
        tran=""
        [ -n "$parent" ] && tran=$(lsblk -n -d -o TRAN "$parent" 2>/dev/null | head -n 1 | tr -d ' ')
        if [ "$tran" = "usb" ]; then
            usb_parts+=("$name")
            usb_disks+=("$parent")
        else
            other_parts+=("$name")
        fi
    done < <(lsblk -p -n -P -o NAME,LABEL 2>/dev/null)

    if [ ${#usb_parts[@]} -eq 0 ] && [ ${#other_parts[@]} -eq 0 ]; then
        err "No drive with the label '$want' was found."
        echo "   Please plug in the correct backup USB drive and try again." >&2
        return 1
    fi
    if [ ${#usb_parts[@]} -eq 0 ]; then
        err "No *USB* drive with the label '$want' was found."
        echo "   Found partition(s) with that label, but they are not on USB drives:" >&2
        printf '   - %s\n' "${other_parts[@]}" >&2
        echo "   Please plug in the correct backup USB drive and try again." >&2
        return 1
    fi
    if [ ${#usb_parts[@]} -gt 1 ]; then
        err "Found *multiple* USB drives with the label '$want'."
        echo "   This is ambiguous. Please remove the extra drive(s) and leave only the one you wish to use." >&2
        local i
        for i in "${!usb_parts[@]}"; do
            echo "   - ${usb_parts[$i]} (device: ${usb_disks[$i]})" >&2
        done
        return 1
    fi

    BACKUP_PART="${usb_parts[0]}"
    BACKUP_DISK="${usb_disks[0]}"
    # Unraid (and its boot-loader tools) require the flash drive on the FIRST partition
    if [ "$BACKUP_PART" != "${BACKUP_DISK}1" ]; then
        err "'$want' is on $BACKUP_PART, not the first partition of $BACKUP_DISK."
        echo "   Unraid must boot from the first partition. This drive cannot be restored with this script." >&2
        return 1
    fi
    BACKUP_UUID=$(lsblk -no UUID "$BACKUP_PART" 2>/dev/null | head -n 1 | tr -d ' ')
    echo "✅ Found one and only one matching USB drive."
    echo "   Partition: $BACKUP_PART"
    echo "   Device:    $BACKUP_DISK"
    return 0
}

# --- If the stick dropped off the system (USB reset or re-attach), wait for it and find it again by its filesystem UUID.
# Updates BACKUP_PART / BACKUP_DISK if it came back under another name. Returns 1 if it never returned. ---
ensure_backup_part() {
    [ -e "$BACKUP_PART" ] && return 0
    echo "   ⚠️  $BACKUP_PART has disappeared (the USB stick reset or re-attached). Waiting up to ${DEVICE_WAIT_SECONDS}s for it to come back..." >&2
    local waited=0 line name parent
    while :; do
        [ -e "$BACKUP_PART" ] && return 0
        if [ -n "$BACKUP_UUID" ]; then
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                [ "$(get_column_value "$line" "UUID")" = "$BACKUP_UUID" ] || continue
                name=$(get_column_value "$line" "NAME")
                parent=$(lsblk -p -n -o PKNAME "$name" 2>/dev/null | head -n 1)
                [ -n "$parent" ] && [ "$name" = "${parent}1" ] || continue
                BACKUP_PART="$name"
                BACKUP_DISK="$parent"
                echo "   The drive is back as $BACKUP_PART." >&2
                return 0
            done < <(lsblk -p -n -P -o NAME,UUID 2>/dev/null)
        fi
        [ "$waited" -ge "$DEVICE_WAIT_SECONDS" ] && break
        sleep 1
        waited=$((waited + 1))
    done
    err "The USB drive did not come back. Unplug it, plug it in again, run mountall, then run this script again:"
    echo "   if the label was already changed to '$FINAL_LABEL', the script resumes the restore from where it stopped." >&2
    return 1
}

# --- Unmount every mount of a partition (SystemRescue's 'mountall' mounts everything) ---
unmount_all() {
    local part="$1" target
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        if ! umount "$target" 2>/dev/null; then
            err "Could not unmount $target. Close anything using it and try again."
            return 1
        fi
    done < <(findmnt -rn -S "$part" -o TARGET 2>/dev/null)
    if [ -n "$(findmnt -rn -S "$part" -o TARGET 2>/dev/null)" ]; then
        err "$part is still mounted after the unmount attempt."
        return 1
    fi
    return 0
}

# --- Mount / unmount the backup partition at our own temporary mount point ---
mount_backup() {
    local mode="$1"
    ensure_backup_part || return 1
    if [ -z "$MOUNT_POINT" ]; then
        if ! MOUNT_POINT=$(mktemp -d /mnt/unraid_restore.XXXXXX); then
            err "Could not create a temporary mount point."
            MOUNT_POINT=""
            return 1
        fi
    fi
    if ! mount -o "$mode" "$BACKUP_PART" "$MOUNT_POINT"; then
        err "Failed to mount $BACKUP_PART ($mode)."
        return 1
    fi
    return 0
}

unmount_backup() {
    sync
    if ! umount "$MOUNT_POINT"; then
        err "Failed to unmount $MOUNT_POINT."
        return 1
    fi
    return 0
}

# --- 1c. Check that the backup looks like a complete Unraid flash (backup must be mounted) ---
check_backup_contents() {
    echo "Checking that the backup is a complete Unraid flash drive..."
    local f missing=()
    for f in bzimage bzroot bzmodules config syslinux/syslinux.cfg syslinux/syslinux_linux syslinux/mbr.bin; do
        [ -e "$MOUNT_POINT/$f" ] || missing+=("$f")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        err "The backup is missing: ${missing[*]}"
        echo "   This does not look like a complete Unraid flash backup, so it will not be used." >&2
        return 1
    fi

    local mbr_size
    mbr_size=$(wc -c < "$MOUNT_POINT/syslinux/mbr.bin" | tr -d ' ')
    if [ "$mbr_size" -lt "$MBR_MIN_BYTES" ] || [ "$mbr_size" -gt "$MBR_MAX_BYTES" ]; then
        err "syslinux/mbr.bin is $mbr_size bytes; expected $MBR_MIN_BYTES-$MBR_MAX_BYTES. Refusing to write it to the disk."
        return 1
    fi

    if [ -d "$MOUNT_POINT/EFI" ] && [ -d "$MOUNT_POINT/EFI-" ]; then
        EFI_STATE="both"
    elif [ -d "$MOUNT_POINT/EFI" ]; then
        EFI_STATE="EFI"
    elif [ -d "$MOUNT_POINT/EFI-" ]; then
        EFI_STATE="EFI-"
    else
        EFI_STATE="none"
        warn "The backup has no EFI folder, so UEFI boot will not be available."
    fi
    [ "$EFI_STATE" = "both" ] && warn "The backup has both EFI and EFI- folders; they will be left as they are."

    BACKUP_MARKER=$(find "$MOUNT_POINT" -maxdepth 1 -type f -name 'BACKUP-*' 2>/dev/null | sort | tail -n 1)
    BACKUP_MARKER=$(basename "$BACKUP_MARKER" 2>/dev/null)
    [ "$BACKUP_MARKER" = "." ] && BACKUP_MARKER=""

    # Copy the boot-loader tools off the USB: the USB is unmounted while they run
    if ! WORK_DIR=$(mktemp -d /tmp/unraid_restore.XXXXXX); then
        err "Could not create a temporary work folder."
        WORK_DIR=""
        return 1
    fi
    if ! cp "$MOUNT_POINT/syslinux/syslinux_linux" "$MOUNT_POINT/syslinux/mbr.bin" "$WORK_DIR/"; then
        err "Could not copy the boot-loader tools from the backup."
        return 1
    fi
    chmod +x "$WORK_DIR/syslinux_linux"
    "$WORK_DIR/syslinux_linux" --version >/dev/null 2>&1
    local rc=$?
    if [ $rc -eq 126 ] || [ $rc -eq 127 ]; then
        err "The backup's syslinux_linux cannot run on this system (exit $rc)."
        return 1
    fi
    echo "✅ Backup contents look complete."
    return 0
}

# --- SHA-256 of one file (hash only) ---
sha256_of() {
    sha256sum -- "$1" 2>/dev/null | awk '{print $1}'
}

# --- 1d. Check the boot files against the .sha256 files Unraid ships (backup must be mounted) ---
# Covers the backup root AND previous/. A mismatch is recorded in VERIFY_PROBLEMS, not fatal by itself.
verify_backup_hashes() {
    echo "Verifying the boot files against Unraid's own .sha256 files (root and previous/; this can take a minute or two)..."
    local dir hash_file target name stored actual size_mb checked=0
    for dir in "$MOUNT_POINT" "$MOUNT_POINT/previous"; do
        [ -d "$dir" ] || continue
        for hash_file in "$dir"/*.sha256; do
            [ -e "$hash_file" ] || continue
            target="${hash_file%.sha256}"
            name="${target#"$MOUNT_POINT"/}"
            if [ ! -f "$target" ]; then
                VERIFY_PROBLEMS+=("$name: missing (its .sha256 file is present)")
                continue
            fi
            stored=$(awk 'NR==1 {print tolower($1)}' "$hash_file")
            if [[ ! "$stored" =~ ^[0-9a-f]{64}$ ]]; then
                VERIFY_NOTES+=("$name: ${name}.sha256 is not a valid SHA-256, so it was not verified")
                continue
            fi
            size_mb=$(( $(wc -c < "$target" | tr -d ' ') / 1048576 ))
            echo "   Checking $name (${size_mb} MB)..."
            actual=$(sha256_of "$target")
            if [ "$actual" = "$stored" ]; then
                checked=$((checked + 1))
            else
                VERIFY_PROBLEMS+=("$name: does not match Unraid's ${name}.sha256")
            fi
        done
    done
    echo "   $checked file(s) match Unraid's hashes."
    return 0
}

# --- 1e. Check config/, syslinux/, EFI-/ etc. against the manifest dr_usb_backup.sh wrote (backup must be mounted) ---
verify_backup_manifest() {
    local manifest="$MOUNT_POINT/$MANIFEST_NAME"
    if [ ! -f "$manifest" ]; then
        VERIFY_NOTES+=("The backup has no $MANIFEST_NAME (made before this feature, or the manifest step failed): config/ and the other small files could not be checked")
        echo "   No $MANIFEST_NAME on the backup; skipping the config check."
        return 0
    fi
    echo "Checking config and the other files against the backup manifest..."
    local line expected path actual total=0 bad=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        total=$((total + 1))
        expected="${line%% *}"
        path="${line#*  }"
        if [[ "$expected" == \\* ]]; then
            VERIFY_NOTES+=("a file whose name has special characters was not checked: ${path#./}")
            continue
        fi
        if [ ! -f "$MOUNT_POINT/$path" ]; then
            VERIFY_PROBLEMS+=("${path#./}: missing (the backup manifest lists it)")
            bad=$((bad + 1))
            continue
        fi
        actual=$(sha256_of "$MOUNT_POINT/$path")
        if [ "$actual" != "$expected" ]; then
            VERIFY_PROBLEMS+=("${path#./}: does not match the backup manifest")
            bad=$((bad + 1))
        fi
    done < "$manifest"
    echo "   $((total - bad)) of $total file(s) match the manifest."
    return 0
}

# --- Show what is about to happen ---
show_summary() {
    local model size_human size marker_text
    model=$(lsblk -n -d -o MODEL "$BACKUP_DISK" 2>/dev/null | xargs)
    [ -n "$model" ] || model="Unknown"
    size=$(lsblk -b -n -d -o SIZE "$BACKUP_DISK" 2>/dev/null | head -n 1 | tr -d ' ')
    size_human="$size bytes"
    if command -v numfmt >/dev/null 2>&1 && [[ "$size" =~ ^[0-9]+$ ]]; then
        size_human="$(numfmt --to=iec-i --suffix=B --format="%.2f" "$size")"
    fi
    if [ -n "$BACKUP_MARKER" ]; then
        # BACKUP-MM-DD-YYYY-HH-MM
        marker_text=$(echo "${BACKUP_MARKER#BACKUP-}" | awk -F- 'NF==5 {printf "%s-%s-%s at %s:%s", $1,$2,$3,$4,$5; next} {print}')
    else
        marker_text="UNKNOWN (no BACKUP-* marker file found; the backup may never have completed)"
    fi
    echo
    echo "=============================================================="
    echo "  EMERGENCY RESTORE - THIS CANNOT BE UNDONE ONCE YOU REBOOT"
    echo "=============================================================="
    echo "  Backup drive:    $BACKUP_DISK ($model, $size_human)"
    echo "  Partition:       $BACKUP_PART"
    echo "  Last backup:     $marker_text"
    echo
    echo "  This will make that drive your main Unraid boot drive:"
    if [ "$RESUME" = true ]; then
        echo "    - (its label is already '$FINAL_LABEL': an earlier restore did not finish)"
    else
        echo "    - change its label from '$BACKUP_LABEL' to '$FINAL_LABEL'"
    fi
    echo "    - enable UEFI boot (EFI- -> EFI) and install the boot loader"
    echo
    echo "  Only continue if the original Unraid USB is dead or missing."
    echo "=============================================================="
    local item shown=0
    for item in "${VERIFY_NOTES[@]}"; do
        warn "$item"
    done
    if [ ${#VERIFY_PROBLEMS[@]} -gt 0 ]; then
        echo
        echo "🛑 ${#VERIFY_PROBLEMS[@]} file(s) on the backup FAILED verification:"
        for item in "${VERIFY_PROBLEMS[@]}"; do
            echo "     - $item"
            shown=$((shown + 1))
            if [ $shown -ge "$MAX_PROBLEMS_SHOWN" ] && [ ${#VERIFY_PROBLEMS[@]} -gt $shown ]; then
                echo "     ... and $(( ${#VERIFY_PROBLEMS[@]} - shown )) more"
                break
            fi
        done
        echo "   The backup may be damaged or incomplete."
    else
        echo "  ✅ All checked files match their hashes."
    fi
}

# --- Ask the user to type a word. Empty input cancels; one retry for a wrong word ---
# Usage: confirm_word <WORD> <prompt text>
confirm_word() {
    local word="$1" prompt="$2" attempt=0 reply
    while [ $attempt -lt 2 ]; do
        read -rp "$prompt" reply
        if [ "$reply" = "$word" ]; then
            return 0
        fi
        [ -z "$reply" ] && return 1
        attempt=$((attempt + 1))
        [ $attempt -lt 2 ] && echo "Please type $word in capital letters, or press Enter to cancel."
    done
    return 1
}

# --- Require the user to type RESTORE (empty input cancels) ---
confirm_restore() {
    confirm_word "RESTORE" "Type RESTORE to continue (press Enter to cancel): "
}

# --- If anything failed verification, require a separate OVERRIDE before RESTORE ---
confirm_override() {
    [ ${#VERIFY_PROBLEMS[@]} -eq 0 ] && return 0
    echo
    echo "Restoring a backup that failed verification can give a drive that does not boot,"
    echo "or one with missing or wrong settings. Only do this if you have no better option."
    confirm_word "OVERRIDE" "Type OVERRIDE to restore anyway (press Enter to cancel): "
}

# --- Label reading (the label is what makes Unraid boot, so it is read carefully) ---
# Make sure what is on the stick is what we read back: flush writes and cached blocks, let udev finish.
flush_device() {
    sync
    command -v blockdev >/dev/null 2>&1 && blockdev --flushbufs "$BACKUP_PART" 2>/dev/null
    command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=10 2>/dev/null
    return 0
}

# Print the trimmed label of a partition. fatlabel can print a warning on stdout ("There are differences between
# boot sector and its backup", normal after the syslinux install), so it is the last resort and only its last line is used.
get_label() {
    local part="${1:-$BACKUP_PART}" out=""
    if command -v blkid >/dev/null 2>&1; then   # -p probes the device itself, bypassing udev's cache
        out=$(blkid -p -s LABEL -o value "$part" 2>/dev/null | head -n 1 | sed 's/[[:space:]]*$//')
    fi
    if [ -z "$out" ]; then
        out=$(lsblk -no LABEL "$part" 2>/dev/null | head -n 1 | sed 's/[[:space:]]*$//')
    fi
    if [ -z "$out" ]; then
        out=$(fatlabel "$part" 2>/dev/null | tail -n 1 | sed 's/[[:space:]]*$//')
    fi
    printf '%s\n' "$out"
}

# Last resort: after udev re-reads the partition, does /dev/disk/by-label/UNRAID (what Unraid looks up at boot)
# point at THIS partition? It must resolve to our partition: another drive labelled UNRAID does not count.
udev_sees_label() {
    command -v udevadm >/dev/null 2>&1 || return 1
    udevadm trigger --action=change "$BACKUP_PART" 2>/dev/null
    udevadm settle --timeout=10 2>/dev/null
    local link="$UDEV_LABEL_DIR/$FINAL_LABEL" target part
    [ -e "$link" ] || return 1
    target=$(readlink -f "$link" 2>/dev/null)
    part=$(readlink -f "$BACKUP_PART" 2>/dev/null)
    [ -n "$target" ] && [ "$target" = "$part" ]
}

# Confirm the partition is labelled exactly FINAL_LABEL. Reads it, then retries with a growing wait (about 30s in
# total), then asks udev as a final check. Sets LABEL_READ to the last label read. Returns 1 if it cannot be confirmed.
LABEL_READ=""
confirm_label() {
    local delay n=0 total=${#LABEL_RETRY_DELAYS[@]}
    LABEL_READ=""
    ensure_backup_part || return 1
    flush_device
    LABEL_READ=$(get_label "$BACKUP_PART")
    [ "$LABEL_READ" = "$FINAL_LABEL" ] && return 0
    for delay in "${LABEL_RETRY_DELAYS[@]}"; do
        n=$((n + 1))
        echo "   Label not confirmed yet (read '${LABEL_READ:-nothing}'); retrying in ${delay}s (retry $n of $total)..."
        sleep "$delay"
        ensure_backup_part || return 1
        flush_device
        LABEL_READ=$(get_label "$BACKUP_PART")
        [ "$LABEL_READ" = "$FINAL_LABEL" ] && return 0
    done
    if udev_sees_label; then
        warn "Reading the label directly failed, but udev reports '$FINAL_LABEL' on $BACKUP_PART. Continuing."
        LABEL_READ="$FINAL_LABEL"
        return 0
    fi
    return 1
}

# What every method reports, shown when the label cannot be confirmed
label_report() {
    local link="$UDEV_LABEL_DIR/$FINAL_LABEL" tgt="(none)"
    [ -e "$link" ] && tgt=$(readlink -f "$link" 2>/dev/null)
    echo "   Label as read by each method (expected '$FINAL_LABEL'):"
    if command -v blkid >/dev/null 2>&1; then
        echo "     blkid:    '$(blkid -p -s LABEL -o value "$BACKUP_PART" 2>/dev/null | head -n 1)'"
    else
        echo "     blkid:    (not installed)"
    fi
    echo "     lsblk:    '$(lsblk -no LABEL "$BACKUP_PART" 2>/dev/null | head -n 1)'"
    echo "     fatlabel: '$(fatlabel "$BACKUP_PART" 2>/dev/null | tail -n 1)'"
    echo "     $link -> $tgt (this partition is $BACKUP_PART)"
}

# --- 3. Change the label ---
relabel_backup() {
    if [ "$RESUME" = true ]; then
        echo "Label is already '$FINAL_LABEL' (resuming); checking it..."
    else
        echo "Changing label from '$BACKUP_LABEL' to '$FINAL_LABEL'..."
        ensure_backup_part || return 1
    fi
    if [ "$RESUME" != true ] && ! fatlabel "$BACKUP_PART" "$FINAL_LABEL"; then
        err "Failed to change the label. The partition may not be FAT32."
        return 1
    fi
    [ "$RESUME" = true ] || RELABELED=true
    if ! confirm_label; then
        err "Label check failed: the partition is labelled '$LABEL_READ' (expected '$FINAL_LABEL')."
        label_report >&2
        return 1
    fi
    echo "✅ Label is now '$FINAL_LABEL'."
    return 0
}

# --- 4. Enable UEFI boot: EFI- -> EFI ---
enable_uefi() {
    echo "Enabling UEFI boot..."
    mount_backup rw || return 1
    if [ -d "$MOUNT_POINT/EFI-" ] && [ ! -d "$MOUNT_POINT/EFI" ]; then
        if ! mv "$MOUNT_POINT/EFI-" "$MOUNT_POINT/EFI"; then
            err "Failed to rename EFI- to EFI."
            unmount_backup
            return 1
        fi
        EFI_RENAMED=true
        echo "✅ Renamed EFI- to EFI."
    elif [ -d "$MOUNT_POINT/EFI" ]; then
        echo "✅ EFI folder already present."
    else
        warn "No EFI folder found; UEFI boot will not be available."
    fi
    unmount_backup || return 1
    return 0
}

# --- 5a. Install the syslinux boot loader on the partition (USB must be unmounted) ---
install_bootloader() {
    ensure_backup_part || return 1
    echo "Installing the syslinux boot loader on $BACKUP_PART..."
    if ! "$WORK_DIR/syslinux_linux" -f --install "$BACKUP_PART"; then
        err "syslinux_linux failed to install the boot loader."
        return 1
    fi
    echo "✅ Boot loader installed."
    return 0
}

# --- 5b. Write Unraid's MBR (boot code plus the active-partition flag) and read it back ---
write_mbr() {
    ensure_backup_part || return 1
    echo "Writing the MBR to $BACKUP_DISK..."
    local size
    size=$(wc -c < "$WORK_DIR/mbr.bin" | tr -d ' ')
    if [ "$size" -lt "$MBR_MIN_BYTES" ] || [ "$size" -gt "$MBR_MAX_BYTES" ]; then
        err "mbr.bin is $size bytes; refusing to write it."
        return 1
    fi
    if ! dd if="$WORK_DIR/mbr.bin" of="$BACKUP_DISK" bs="$size" count=1 conv=notrunc 2>/dev/null; then
        err "Failed to write the MBR to $BACKUP_DISK."
        return 1
    fi
    sync
    # Read exactly those bytes back from the disk and compare with the file
    if ! cmp -s <(dd if="$BACKUP_DISK" bs="$size" count=1 2>/dev/null) "$WORK_DIR/mbr.bin"; then
        err "The MBR written to $BACKUP_DISK does not match mbr.bin."
        return 1
    fi
    echo "✅ MBR written and verified ($size bytes)."
    return 0
}

# --- 6. Check the finished drive ---
verify_result() {
    echo "Verifying the restored drive..."
    if ! confirm_label; then
        err "Verification failed: label is '$LABEL_READ', expected '$FINAL_LABEL'. Unraid will not boot without it."
        label_report >&2
        return 1
    fi
    mount_backup ro || return 1
    local f bad=""
    for f in bzimage bzroot config syslinux/syslinux.cfg; do
        [ -e "$MOUNT_POINT/$f" ] || bad="$bad $f"
    done
    if [ "$EFI_STATE" != "none" ] && [ ! -d "$MOUNT_POINT/EFI" ]; then
        bad="$bad EFI"
    fi
    unmount_backup || return 1
    if [ -n "$bad" ]; then
        err "Verification failed; missing:$bad"
        return 1
    fi

    # Informational checks (not failures): confirm the boot sectors look right
    local flag oem
    flag=$(dd if="$BACKUP_DISK" bs=1 skip=446 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$flag" = "80" ]; then
        echo "   MBR: partition 1 is marked active (bootable)."
    else
        warn "MBR: partition 1 is not marked active (flag byte is '$flag'). Legacy BIOS boot may not work; UEFI is unaffected."
    fi
    oem=$(dd if="$BACKUP_PART" bs=1 skip=3 count=8 2>/dev/null)
    if [ "$oem" = "SYSLINUX" ]; then
        echo "   Partition boot sector: SYSLINUX boot loader present."
    else
        warn "Partition boot sector does not report SYSLINUX (found '$oem'). Please test-boot this drive."
    fi
    echo "✅ Verification passed."
    return 0
}

# --- Put the USB back to being a backup if something failed after we changed it ---
rollback() {
    echo
    echo "↩️  Something went wrong. Restoring the USB to its original state so you can try again..."
    local ok=true
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        umount "$MOUNT_POINT" 2>/dev/null
    fi
    ensure_backup_part || ok=false
    unmount_all "$BACKUP_PART" || ok=false
    if [ "$ok" = true ] && [ "$EFI_RENAMED" = true ]; then
        if mount_backup rw && mv "$MOUNT_POINT/EFI" "$MOUNT_POINT/EFI-"; then
            EFI_RENAMED=false
        else
            ok=false
        fi
        mountpoint -q "$MOUNT_POINT" 2>/dev/null && { sync; umount "$MOUNT_POINT" 2>/dev/null; }
    fi
    if [ "$ok" = true ] && [ "$RELABELED" = true ]; then
        if fatlabel "$BACKUP_PART" "$BACKUP_LABEL"; then
            RELABELED=false
        else
            ok=false
        fi
    fi
    if [ "$ok" = true ]; then
        echo "✅ The drive is a '$BACKUP_LABEL' backup again. It is safe to run this script again."
        echo "   (Boot-loader files written during the attempt are harmless and will be rewritten.)"
    else
        err "Could not fully restore the original state automatically."
        echo "   If the stick vanished: unplug it, plug it in again, run mountall, then run this script again. It resumes an" >&2
        echo "   unfinished restore on its own (a stick already labelled $FINAL_LABEL that still has its BACKUP-* marker)." >&2
        echo "   Check the drive by hand:" >&2
        echo "     fatlabel $BACKUP_PART            (should print $BACKUP_LABEL)" >&2
        echo "     fatlabel $BACKUP_PART $BACKUP_LABEL    (to set it back)" >&2
    fi
}

main() {
    if [ $# -gt 0 ]; then
        echo "Usage: $0   (this script takes no options)" >&2
        return 1
    fi
    echo "=== Unraid emergency restore: UNRAID_DR -> UNRAID ==="
    require_environment || return 1
    if ! is_interactive; then
        err "This script is interactive and must be run from a terminal."
        return 1
    fi

    # Step 1: read-only checks - nothing is changed here
    check_no_unraid_drive || return 1
    find_backup_usb || return 1
    unmount_all "$BACKUP_PART" || return 1
    mount_backup ro || return 1
    if ! check_backup_contents; then
        unmount_backup
        return 1
    fi
    verify_backup_hashes
    verify_backup_manifest
    unmount_backup || return 1

    # Step 2: show and confirm
    show_summary
    if ! confirm_override; then
        echo "Cancelled. Nothing was changed."
        return 1
    fi
    if ! confirm_restore; then
        echo "Cancelled. Nothing was changed."
        return 1
    fi

    # Steps 3-6: change, then verify; undo on any failure
    echo
    if ! { relabel_backup && enable_uefi && install_bootloader && write_mbr && verify_result; }; then
        rollback
        err "The restore did NOT complete."
        return 1
    fi

    echo "---"
    echo "✅ All done! The USB drive at '$BACKUP_DISK' is now ready to boot as your main Unraid drive."
    echo
    echo "Next: shut down (type poweroff), remove this recovery USB, and boot from the restored drive."
    echo "Because this is a different flash drive, Unraid will ask you to replace your license key."
    echo "Replacing it permanently blacklists the OLD drive, so only do that if it is truly dead."
    return 0
}

# Run only when executed directly (lets the test suite source this file safely)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap cleanup EXIT
    main "$@"
    exit $?
fi
