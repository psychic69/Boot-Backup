#!/bin/bash
# Tests for lib/drives.sh helpers.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/drives.sh"
echo "test_drives"
LOG_FILE=""; DEBUG=false
row='NAME="sdd1" UUID="u2" FSTYPE="vfat" SIZE="7730941132" MOUNTPOINT="" LABEL="BACKUP" TRAN=""'
assert_eq "get_column_value NAME" "sdd1" "$(get_column_value "$row" NAME)"
assert_eq "get_column_value LABEL" "BACKUP" "$(get_column_value "$row" LABEL)"
assert_eq "get_column_value empty field" "" "$(get_column_value "$row" MOUNTPOINT)"
assert_eq "get_column_value missing field" "" "$(get_column_value "$row" NOPE)"
assert_eq "convert_bytes_to_human" "1.00G (1073741824 bytes)" "$(convert_bytes_to_human 1073741824)"
assert_eq "convert_bytes_to_human rejects junk" "0.00G (0 bytes)" "$(convert_bytes_to_human abc)"
declare -a current_drive_state
USE_TEST_FILE=true
(cd "$TEST_DIR/fixtures" && cp lsblk_usb_states.txt "$TMP_DIR/test-lsblk")
cd "$TMP_DIR"; load_drive_state >/dev/null 2>&1; assert_eq "load_drive_state reads the test file" "0" "$?"
assert_eq "load_drive_state loads every row" "$(wc -l < "$TEST_DIR/fixtures/lsblk_usb_states.txt" | tr -d ' ')" "${#current_drive_state[@]}"
assert_eq "get_tran_type finds the parent's transport" "usb" "$(get_tran_type 3)"
finish
