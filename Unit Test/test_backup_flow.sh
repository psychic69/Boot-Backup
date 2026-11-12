#!/bin/bash
# End-to-end runs of dr_usb_backup.sh against sample drive data (-lsblk): module loading, dr_usb.ini,
# logging, and error exit codes. No drive is touched.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "test_backup_flow"
SCRIPT="$REPO_ROOT/dr_usb_backup.sh"
export DR_USB_INI="$TMP_DIR/dr_usb.ini"; printf 'LOG_DIR="%s/logs"\nSNAPSHOTS=3\n' "$TMP_DIR" > "$DR_USB_INI"
cp "$TEST_DIR/fixtures/lsblk_usb_states.txt" "$TMP_DIR/test-lsblk"
cd "$TMP_DIR"

# the sample data has an UNRAID boot partition but no UNRAID_DR USB
out=$(bash "$SCRIPT" -lsblk 2>&1); rc=$?
assert_eq "no UNRAID_DR: exits 1" "1" "$rc"
assert_contains "no UNRAID_DR: explained" "$out" "No 'UNRAID_DR' backup partition was found"
assert_contains "dr_usb.ini is used" "$out" "SNAPSHOTS=3"
assert_contains "settings file is logged" "$out" "Settings file: $DR_USB_INI"
logs=$(ls "$TMP_DIR/logs/logs" 2>/dev/null)
case "$logs" in boot-check-*.log*) pass "backup log uses the boot-check prefix" ;; *) fail "backup log uses the boot-check prefix" "$logs" ;; esac

# a bad setting stops the script before anything runs
printf 'SNAPSHOTS=0\n' > "$DR_USB_INI"
out=$(bash "$SCRIPT" -lsblk 2>&1); rc=$?
assert_eq "invalid dr_usb.ini: exits 1" "1" "$rc"
assert_contains "invalid dr_usb.ini: explained" "$out" "SNAPSHOTS must be greater than or equal to 1"

# -remote was removed in 1.3.0: it is an unknown option now
printf 'LOG_DIR="%s/logs"\n' "$TMP_DIR" > "$DR_USB_INI"
out=$(bash "$SCRIPT" -remote 2>&1); rc=$?
assert_eq "-remote is gone: exits 1" "1" "$rc"
assert_contains "-remote is gone: unknown option" "$out" "Unknown option"
assert_not_contains "-remote is gone: not in the usage line" "$out" "[-remote]"
finish
