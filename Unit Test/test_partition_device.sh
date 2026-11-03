#!/bin/bash
# Tests for partition_device_new (dr_usb_create.sh) using stubbed disk tools - nothing real is touched.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/drives.sh"
echo "test_partition_device"
LOG_FILE=""; DEBUG=false
# Load the function, neutralising the two "is it a block device" checks (no real /dev/sdz here)
eval "$(extract_fn "$REPO_ROOT/dr_usb_create.sh" partition_device_new | sed 's|\[ ! -b "\${partition}" \]|false|; s|\[ ! -b "\${device}" \]|false|')"

CALLS="$TMP_DIR/calls"
lsblk()    { case "$*" in *"-o SIZE"*) echo 8000000000;; *) printf '%s' "$MOUNTS";; esac; }
umount()   { echo "umount:$1" >> "$CALLS"; return "${UMOUNT_RC:-0}"; }
wipefs()   { echo wipefs >> "$CALLS"; return "${WIPE_RC:-0}"; }
sfdisk()   { echo sfdisk >> "$CALLS"; cat >/dev/null; return "${SF_RC:-0}"; }
partprobe(){ return 0; }
mkfs.vfat(){ echo mkfs >> "$CALLS"; return "${MKFS_RC:-0}"; }
sleep()    { :; }
run() { : > "$CALLS"; partition_device_new /dev/sdz >/dev/null 2>&1; RC=$?; CALLED=$(tr '\n' ' ' < "$CALLS"); }

MOUNTS=$'sdz \nsdz1 \n'; run
assert_eq "clean device: success" "0" "$RC"; assert_eq "clean device: steps" "wipefs sfdisk mkfs " "$CALLED"
MOUNTS=$'sdz \nsdz1 /mnt/disks/x\n'; run
assert_eq "mounted partition: success" "0" "$RC"; assert_eq "mounted partition: unmounted first" "umount:/dev/sdz1 wipefs sfdisk mkfs " "$CALLED"
MOUNTS=$'sdz1 /boot\n'; run
assert_eq "/boot mount: refused" "1" "$RC"; assert_eq "/boot mount: nothing run" "" "$CALLED"
MOUNTS=$'sdz1 /mnt/disks/x\n'; UMOUNT_RC=1 run; UMOUNT_RC=0
assert_eq "umount failure: stops" "1" "$RC"; assert_eq "umount failure: nothing wiped" "umount:/dev/sdz1 " "$CALLED"
MOUNTS=''; WIPE_RC=1 run; WIPE_RC=0
assert_eq "wipefs failure: stops" "1" "$RC"; assert_eq "wipefs failure: no sfdisk" "wipefs " "$CALLED"
MOUNTS=''; SF_RC=1 run; SF_RC=0
assert_eq "sfdisk failure: stops" "1" "$RC"; assert_eq "sfdisk failure: no mkfs" "wipefs sfdisk " "$CALLED"
MOUNTS=''; MKFS_RC=1 run; MKFS_RC=0
assert_eq "mkfs failure: stops" "1" "$RC"
finish
