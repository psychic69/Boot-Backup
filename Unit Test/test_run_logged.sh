#!/bin/bash
# Tests for run_logged: it must return the COMMAND's status and show failure output without -debug.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
echo "test_run_logged"
LOG_FILE=""; DEBUG=false

out=$(run_logged "ok" true 2>&1); assert_eq "success returns 0" "0" "$?"
assert_eq "success is silent without -debug" "" "$out"
run_logged "bad" false >/dev/null 2>&1; assert_eq "failure returns non-zero" "1" "$?"
out=$(run_logged "bad" bash -c 'echo reason-text; exit 3' 2>&1); rc=$?
assert_eq "exit status is the command's" "3" "$rc"
assert_contains "failure output is logged as ERROR" "$out" "ERROR: bad: reason-text"
DEBUG=true
out=$(run_logged "ok" bash -c 'echo chatter' 2>&1)
assert_contains "success output appears with -debug" "$out" "DEBUG: ok: chatter"
finish
