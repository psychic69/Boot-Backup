#!/bin/bash
# Tests for remote-backup config loading and SSH key staging in dr_usb_backup.sh.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
echo "test_remote_config"
LOG_FILE=""; DEBUG=false; SSH_KEY_TMP=""; NOTIFY_ON_FAILURE=true
source "$REPO_ROOT/lib/remote.sh"
log_message() { echo "$1"; }

ssh-keygen -q -t ed25519 -N "" -f "$TMP_DIR/key" -C test || { echo "ssh-keygen unavailable"; exit 1; }
echo "backup.lan ssh-ed25519 AAAA" > "$TMP_DIR/kh"
cat > "$TMP_DIR/good.ini" <<INI
REMOTE_HOST="backup.lan"
REMOTE_USER="unraidbackup"
SSH_KEY_FILE="$TMP_DIR/key"
SSH_KNOWN_HOSTS="$TMP_DIR/kh"
RSYNC_EXCLUDES="/logs/ *.tmp"
INI
REMOTE_INI="$TMP_DIR/good.ini"; out=$(load_remote_config 2>&1); rc=$?
assert_eq "valid remote.ini loads" "0" "$rc"
REMOTE_INI="$TMP_DIR/good.ini"; load_remote_config >/dev/null 2>&1
assert_eq "REMOTE_PORT default" "22" "$REMOTE_PORT"
assert_eq "RSYNC_TIMEOUT default" "120" "$RSYNC_TIMEOUT"

bad() { sed "$1" "$TMP_DIR/good.ini" > "$TMP_DIR/bad.ini"; REMOTE_INI="$TMP_DIR/bad.ini"; load_remote_config 2>&1; echo "rc=$?"; }
out=$(bad 's|backup.lan|bad host;x|');            assert_contains "bad host rejected" "$out" "REMOTE_HOST is missing or invalid"; assert_contains "bad host rc" "$out" "rc=1"
{ cat "$TMP_DIR/good.ini"; echo 'REMOTE_DIR="/srv/old/path"'; } > "$TMP_DIR/bad.ini"; REMOTE_INI="$TMP_DIR/bad.ini"; out=$(load_remote_config 2>&1); rc=$?
assert_eq "a leftover REMOTE_DIR does not break loading" "0" "$rc"; assert_contains "a leftover REMOTE_DIR is warned about" "$out" "REMOTE_DIR in"
assert_not_contains "REMOTE_DIR is no longer logged as a setting" "$(REMOTE_INI="$TMP_DIR/good.ini"; load_remote_config 2>&1)" "REMOTE_DIR="
out=$(bad "s|^SSH_KEY_FILE=.*|SSH_KEY_FILE=\"$TMP_DIR/nokey\"|"); assert_contains "missing key rejected" "$out" "SSH_KEY_FILE is missing"
out=$(bad "s|^SSH_KNOWN_HOSTS=.*|SSH_KNOWN_HOSTS=\"$TMP_DIR/nokh\"|"); assert_contains "missing known_hosts rejected" "$out" "SSH_KNOWN_HOSTS is missing or empty"
{ cat "$TMP_DIR/good.ini"; echo 'RSYNC_BWLIMIT_KBPS=fast'; } > "$TMP_DIR/bad.ini"; REMOTE_INI="$TMP_DIR/bad.ini"; out=$(load_remote_config 2>&1)
assert_contains "non-numeric bandwidth rejected" "$out" "RSYNC_BWLIMIT_KBPS must be a non-negative number"
REMOTE_INI="$TMP_DIR/missing.ini"; out=$(load_remote_config 2>&1); assert_contains "missing remote.ini explained" "$out" "Remote config file not found"

SSH_KEY_FILE="$TMP_DIR/key"; stage_ssh_key >/dev/null 2>&1; assert_eq "stage_ssh_key succeeds" "0" "$?"
perm=$(ls -l "$SSH_KEY_TMP" | cut -c1-10); assert_eq "staged key is private (600)" "-rw-------" "$perm"
tmpcopy="$SSH_KEY_TMP"; cleanup_remote
[ ! -e "$tmpcopy" ] && pass "staged key removed on cleanup" || fail "staged key removed on cleanup"
echo "not a key" > "$TMP_DIR/junk"; SSH_KEY_FILE="$TMP_DIR/junk"; stage_ssh_key >/dev/null 2>&1; assert_eq "invalid key rejected" "1" "$?"; cleanup_remote
NOTIFY_ON_FAILURE=false; notify_failure "x"; assert_eq "notify_failure honors NOTIFY_ON_FAILURE=false" "0" "$?"
finish
