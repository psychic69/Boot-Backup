#!/bin/bash
# Startup behavior of dr_usb_create.sh: terminal check, Unraid-server check, -lsblk bypass.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "test_create_startup"
SCRIPT="$REPO_ROOT/dr_usb_create.sh"
export DR_USB_INI="$TMP_DIR/dr_usb.ini"; printf 'LOG_DIR="%s/logs"\n' "$TMP_DIR" > "$DR_USB_INI"

out=$(bash "$SCRIPT" </dev/null 2>&1); rc=$?
assert_eq "no terminal: refused" "1" "$rc"; assert_contains "no terminal: message" "$out" "interactive and must be run from an SSH terminal"

out=$(run_pty "" bash "$SCRIPT" -remote)
assert_contains "-remote was removed: unknown option" "$out" "Unknown option"
assert_contains "-remote exit code" "$out" "rc=1"

if [ ! -f /etc/unraid-version ] && ! uname -a | grep -q Unraid; then
    out=$(run_pty "" bash "$SCRIPT")
    assert_contains "non-Unraid machine refused" "$out" "does not look like an Unraid server"
    assert_contains "non-Unraid exit code" "$out" "rc=1"
else
    skip "non-Unraid refusal" "running on an Unraid server"
fi

out=$(run_pty "" bash "$SCRIPT" -bogus)
assert_contains "unknown option still rejected" "$out" 'Unknown option: "-bogus"'
finish
