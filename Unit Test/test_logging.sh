#!/bin/bash
# Tests for lib/logging.sh: log file naming, rotation, and removal of earlier successful logs.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
echo "test_logging"

LOG_DIR="$TMP_DIR/logs_root"; SNAPSHOTS=2; RETENTION_DAYS=30; LOG_FILE=""; DEBUG=false

out=$(log_message "hello" 2>&1)
assert_contains "log_message before setup reports UNINITIALIZED_LOG" "$out" "UNINITIALIZED_LOG - hello"

setup_logging "usb-create" >/dev/null 2>&1
assert_eq "setup_logging returns 0" "0" "$?"
case "$(basename "$LOG_FILE")" in usb-create-*.log) pass "log file uses the given prefix" ;; *) fail "log file uses the given prefix" "$LOG_FILE" ;; esac
log_message "INFO: written" >/dev/null
assert_contains "log_message writes to the file" "$(cat "$LOG_FILE")" "INFO: written"

LOG_FILE=""; setup_logging >/dev/null 2>&1
case "$(basename "$LOG_FILE")" in boot-check-*.log) pass "default prefix is boot-check" ;; *) fail "default prefix is boot-check" "$LOG_FILE" ;; esac

# remove_old_successful_logs: keep current + failed, delete earlier successful
d="$TMP_DIR/rot"; mkdir -p "$d"
echo "x script completed." > "$d/usb-create-1-ok.log"
echo "x script ended WITH ERRORS (exit 1)." > "$d/usb-create-2-failed.log"
echo "x script completed." > "$d/usb-create-3-current.log"
echo "x script completed." > "$d/boot-check-other.log"
LOG_FILE="$d/usb-create-3-current.log"
remove_old_successful_logs "$d" "usb-create-*.log" "$LOG_FILE" "script completed." >/dev/null
[ ! -e "$d/usb-create-1-ok.log" ] && pass "earlier successful log removed" || fail "earlier successful log removed"
[ -e "$d/usb-create-2-failed.log" ] && pass "earlier failed log kept" || fail "earlier failed log kept"
[ -e "$d/usb-create-3-current.log" ] && pass "current log kept" || fail "current log kept"
[ -e "$d/boot-check-other.log" ] && pass "other log families untouched" || fail "other log families untouched"

# file_rotation by count (keeps the newest N). file_rotation uses GNU "find -printf" (Unraid has it).
if find "$TMP_DIR" -maxdepth 0 -printf '' >/dev/null 2>&1; then
    r="$TMP_DIR/count"; mkdir -p "$r"
    for i in 1 2 3 4 5; do echo x > "$r/boot-check-$i.log"; touch -t "20200101000$i" "$r/boot-check-$i.log"; done
    file_rotation "$r" "boot-check-*.log" 3 3650 >/dev/null
    assert_eq "file_rotation keeps max count" "3" "$(ls "$r" | wc -l | tr -d ' ')"
    if [ -e "$r/boot-check-5.log" ] && [ ! -e "$r/boot-check-1.log" ]; then pass "file_rotation removes the oldest"; else fail "file_rotation removes the oldest"; fi
else
    skip "file_rotation count rotation" "needs GNU find; runs on Linux/Unraid"
fi
finish
