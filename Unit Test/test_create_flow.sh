#!/bin/bash
# End-to-end run of dr_usb_create.sh in -lsblk -debug mode against sample drive data: the whole
# menu/confirm flow executes under a real terminal and must NOT change any drive.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "test_create_flow"
export DR_USB_INI="$TMP_DIR/dr_usb.ini"; printf 'LOG_DIR="%s/logs"\n' "$TMP_DIR" > "$DR_USB_INI"
cp "$TEST_DIR/fixtures/lsblk_usb_states.txt" "$TMP_DIR/test-lsblk"
cd "$TMP_DIR"

out=$(run_pty "sdd|FORMAT" bash "$REPO_ROOT/dr_usb_create.sh" -lsblk -debug)
assert_contains "menu shows a selectable used drive" "$out" "sdd"
assert_contains "menu shows not-available section" "$out" "Not available (cannot be selected):"
assert_contains "flow reaches the confirmation" "$out" "type FORMAT in all capitals"
assert_contains "no drive is changed" "$out" "was NOT changed"
assert_contains "script reports completion" "$out" "CREATE** script completed."
assert_contains "exit code 0" "$out" "rc=0"
logs=$(ls "$TMP_DIR/logs/logs" 2>/dev/null)
case "$logs" in *usb-create-*.log*) pass "a usb-create-*.log file was written" ;; *) fail "a usb-create-*.log file was written" "$logs" ;; esac

out=$(run_pty "sdd|FORMAT" bash "$REPO_ROOT/dr_usb_create.sh" -lsblk -debug)
assert_eq "second successful run leaves exactly one create log" "1" "$(ls "$TMP_DIR/logs/logs" | grep -c '^usb-create-')"

out=$(run_pty "sde|sde" bash "$REPO_ROOT/dr_usb_create.sh" -lsblk)
assert_contains "Ventoy stick cannot be chosen" "$out" "'sde' cannot be selected: Ventoy recovery USB"
assert_contains "refused run exits non-zero" "$out" "rc=1"
finish
