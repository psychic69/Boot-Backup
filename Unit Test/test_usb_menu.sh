#!/bin/bash
# Tests for the USB drive menu in dr_usb_create.sh (scan_usb_disks / print_usb_menu / selection flow).
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/drives.sh"
echo "test_usb_menu"
LOG_FILE=""; DEBUG=false; USE_TEST_FILE=false
load_fns "$REPO_ROOT/dr_usb_create.sh" size_short scan_usb_disks print_usb_menu recheck_selected_device find_and_prepare_clone
log_message() { echo "$1"; }
lsblk()  { case "$*" in *MODEL*) echo "Fake Model";; *) return 0;; esac; }
fdisk()  { :; }
declare -a current_drive_state
while IFS= read -r l; do current_drive_state+=("$l"); done < "$TEST_DIR/fixtures/lsblk_usb_states.txt"
BOOT_SIZE=16007561216
MIN=$(awk "BEGIN {printf \"%.0f\", $BOOT_SIZE * 0.95}")

scan_usb_disks "$MIN"
assert_eq "selectable drives" "sdc sdd sdh sdaa" "${sel_dev[*]}"
assert_eq "not-available drives" "sdb sde sdf sdg" "${bad_dev[*]}"
assert_eq "blank stick has no *" "false" "${sel_star[0]}"
assert_eq "used stick has *" "true" "${sel_star[1]}"
assert_contains "used stick lists its labeled partition" "${sel_detail[1]}" 'label: "BACKUP"'
assert_contains "used stick lists its unlabeled partition" "${sel_detail[1]}" 'label: (none)'
assert_eq "no-partition-table filesystem has *" "true" "${sel_star[2]}"
assert_contains "no-partition-table filesystem is described" "${sel_detail[2]}" "(no partition table) filesystem: ntfs"
assert_contains "boot drive reason" "${bad_reason[0]}" "Unraid boot drive"
assert_contains "Ventoy reason" "${bad_reason[1]}" "Ventoy recovery USB"
assert_contains "too-small reason names the minimum" "${bad_reason[2]}" "too small: 7.45G, minimum is 14.16G"
assert_contains "mounted reason names the mountpoint" "${bad_reason[3]}" "/mnt/disks/photos"
# a USB disk named sdaa must not be confused with sda's partitions (sda is SATA and is not listed at all)
case " ${sel_dev[*]} ${bad_dev[*]} " in *" sda "*) fail "internal SATA disk is not listed" ;; *) pass "internal SATA disk is not listed" ;; esac

menu=$(print_usb_menu "14.91G")
assert_contains "menu has legend" "$menu" "* = this drive already contains data"
assert_contains "menu has not-available section" "$menu" "Not available (cannot be selected):"

# selection flow in debug mode: Ventoy stick refused, then a valid drive; nothing is changed
DEBUG=true
out=$(printf 'sde\nsdd\nFORMAT\n' | find_and_prepare_clone 2>&1); rc=$?
DEBUG=false
assert_eq "debug-mode flow returns 0" "0" "$rc"
assert_contains "excluded drive explained" "$out" "'sde' cannot be selected: Ventoy recovery USB"
assert_contains "valid drive accepted" "$out" "Device sdd selected."
assert_contains "confirmation lists what will be erased" "$out" 'label: "BACKUP"'
assert_contains "debug mode does not change the drive" "$out" "/dev/sdd was NOT changed"
finish
