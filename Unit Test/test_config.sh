#!/bin/bash
# Tests for lib/config.sh: built-in defaults, dr_usb.ini overrides, and parameter validation.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/config.sh"
echo "test_config"
SCRIPT_DIR="$TMP_DIR/install"; mkdir -p "$SCRIPT_DIR"

unset DR_USB_INI; load_config
assert_eq "default LOG_DIR" "/boot/logs/unraid-dr" "$LOG_DIR"
assert_eq "default SNAPSHOTS" "10" "$SNAPSHOTS"
assert_eq "default RETENTION_DAYS" "30" "$RETENTION_DAYS"
assert_eq "default CLONE_MP" "/mnt/disks/usb-backup-temp" "$CLONE_MP"
assert_eq "default REMOTE_INI is beside the scripts" "$SCRIPT_DIR/remote.ini" "$REMOTE_INI"
assert_eq "no ini -> not loaded" "false" "$DR_USB_INI_LOADED"
validate_parameters >/dev/null 2>&1; assert_eq "defaults validate" "0" "$?"

printf 'SNAPSHOTS=5\nCLONE_MP="/mnt/x"\n' > "$SCRIPT_DIR/dr_usb.ini"
load_config
assert_eq "ini overrides SNAPSHOTS" "5" "$SNAPSHOTS"
assert_eq "ini overrides CLONE_MP" "/mnt/x" "$CLONE_MP"
assert_eq "ini leaves other defaults" "30" "$RETENTION_DAYS"
assert_eq "ini flagged as loaded" "true" "$DR_USB_INI_LOADED"

printf 'SNAPSHOTS=0\nLOG_DIR="relative"\nRETENTION_DAYS=abc\n' > "$SCRIPT_DIR/dr_usb.ini"
load_config
out=$(validate_parameters 2>&1); rc=$?
assert_eq "bad values fail validation" "1" "$rc"
assert_contains "reports SNAPSHOTS" "$out" "SNAPSHOTS must be greater than or equal to 1"
assert_contains "reports LOG_DIR" "$out" "LOG_DIR must be an absolute path"
assert_contains "reports RETENTION_DAYS" "$out" "RETENTION_DAYS must be a number"

DR_USB_INI="$TMP_DIR/elsewhere.ini"; printf 'SNAPSHOTS=7\n' > "$DR_USB_INI"
load_config; assert_eq "DR_USB_INI env override is honored" "7" "$SNAPSHOTS"
finish
