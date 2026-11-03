#!/bin/bash
# remote_backup end to end with stubbed ssh / rsync / flock: source hash gate, the rrsync destination checks,
# and the exact rsync commands. No network, no real /boot.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/integrity.sh"
echo "test_remote_flow"
LOG_FILE=""; DEBUG=false; SSH_KEY_TMP=""; NOTIFY_ON_FAILURE=true
source "$REPO_ROOT/lib/remote.sh"
load_fns "$REPO_ROOT/dr_usb_backup.sh" remote_backup
log_message() { echo "$1"; }

# ---- stubs ----
CALLS="$TMP_DIR/calls"
flock()      { return 0; }
mountpoint() { return 0; }
ssh() {   # the "run a command" restriction check is: ssh <opts> target true
    echo "ssh $*" >> "$CALLS"
    case "${*: -1}" in true) return "${SSH_TRUE_RC:-1}" ;; esac
    return 0
}
rsync() {
    echo "rsync $*" >> "$CALLS"
    case "$*" in
        *.dr_usb_probe*) [ -n "${PROBE_OUT:-}" ] && echo "$PROBE_OUT"; return "${PROBE_RC:-0}" ;;
        *) echo "sent 1 file"; return "${MIRROR_RC:-0}" ;;
    esac
}

# ---- fixtures ----
ssh-keygen -q -t ed25519 -N "" -f "$TMP_DIR/key" -C test || { echo "ssh-keygen unavailable"; exit 1; }
echo "backup.lan ssh-ed25519 AAAA" > "$TMP_DIR/kh"
write_ini() {
    cat > "$TMP_DIR/remote.ini" <<INI
REMOTE_HOST="backup.lan"
REMOTE_USER="unraidbackup"
SSH_KEY_FILE="$TMP_DIR/key"
SSH_KNOWN_HOSTS="$TMP_DIR/kh"
$1
INI
}
setup() {
    make_boot "$TMP_DIR/boot"; mkdir -p "$TMP_DIR/boot/config"
    BOOT_DIR="$TMP_DIR/boot"; REMOTE_INI="$TMP_DIR/remote.ini"; DEBUG=false
    SSH_TRUE_RC=1; PROBE_RC=0; PROBE_OUT=""; MIRROR_RC=0; : > "$CALLS"; write_ini ""
}
run() { OUT=$(remote_backup 2>&1); RC=$?; cleanup_remote; }
calls() { cat "$CALLS"; }

# ---- 1. healthy run ----
setup; run
assert_eq "healthy run succeeds" "0" "$RC"
assert_contains "destination checked" "$OUT" "Destination OK: writable, and the key is restricted to rrsync."
assert_contains "mirror finished" "$OUT" "Remote mirror completed successfully"
probe_n=$(calls | grep -n '\.dr_usb_probe' | head -1 | cut -d: -f1); ssh_n=$(calls | grep -n ' true$' | head -1 | cut -d: -f1); mirror_n=$(calls | grep -n -- '--delete-after' | head -1 | cut -d: -f1)
[ -n "$probe_n" ] && [ -n "$ssh_n" ] && [ -n "$mirror_n" ] && [ "$probe_n" -lt "$ssh_n" ] && [ "$ssh_n" -lt "$mirror_n" ] && pass "order: probe, then restriction check, then mirror" || fail "order: probe, restriction check, mirror" "$(calls)"
mirror=$(calls | grep -- '--delete-after')
assert_contains "mirror source is the boot folder" "$mirror" "$TMP_DIR/boot/ "
assert_contains "mirror destination is the rrsync root" "$mirror" "unraidbackup@backup.lan:./"
assert_not_contains "mirror is not a dry run" "$mirror" "--dry-run"
assert_contains "probe goes to the rrsync root" "$(calls | grep '\.dr_usb_probe')" "unraidbackup@backup.lan:./"
assert_contains "ssh uses a pinned known_hosts" "$(calls | grep ' true$')" "StrictHostKeyChecking=yes"
assert_contains "ssh is non-interactive" "$(calls | grep ' true$')" "BatchMode=yes"
[ -z "$(ls /tmp/dr_usb_probe.* 2>/dev/null)" ] && pass "probe temp folder removed" || fail "probe temp folder removed"
[ -z "$SSH_KEY_TMP" ] && pass "private key copy removed" || fail "private key copy removed"

# ---- 2. a key that can run commands is refused ----
setup; SSH_TRUE_RC=0; run
assert_eq "unrestricted key: refused" "1" "$RC"; assert_contains "unrestricted key: explained" "$OUT" "SECURITY CHECK FAILED"
assert_contains "unrestricted key: shows the fix" "$OUT" 'command="rrsync -wo'
assert_not_contains "unrestricted key: nothing mirrored" "$(calls)" "--delete-after"

# ---- 3. probe failures ----
setup; PROBE_RC=255; PROBE_OUT="Permission denied (publickey)"; run
assert_eq "cannot connect: fails" "1" "$RC"; assert_contains "cannot connect: shows rsync's message" "$OUT" "Permission denied (publickey)"
assert_not_contains "cannot connect: nothing mirrored" "$(calls)" "--delete-after"
assert_not_contains "cannot connect: no restriction check attempted" "$(calls)" " true"

# ---- 4. corrupted source /boot is a hard stop BEFORE any network use ----
setup; echo corrupt >> "$TMP_DIR/boot/bzroot"; run
assert_eq "corrupted source: fails" "1" "$RC"; assert_contains "corrupted source: clear message" "$OUT" "SOURCE /boot FAILED THE HASH CHECK"
assert_eq "corrupted source: no ssh or rsync call at all" "" "$(calls)"
setup; echo corrupt >> "$TMP_DIR/boot/previous/bzmodules"; run
assert_eq "corrupted previous/: fails too" "1" "$RC"; assert_eq "corrupted previous/: nothing sent" "" "$(calls)"

# ---- 5. dry run ----
setup; DEBUG=true; run
assert_eq "dry run succeeds" "0" "$RC"; assert_contains "probe is a dry run" "$(calls | grep '\.dr_usb_probe')" "--dry-run"
assert_contains "mirror is a dry run" "$(calls | grep -- '--delete-after')" "--dry-run"

# ---- 6. rsync exit codes ----
setup; MIRROR_RC=24; run; assert_eq "exit 24 (vanished files) is success" "0" "$RC"; assert_contains "exit 24 warned" "$OUT" "exit 24"
setup; MIRROR_RC=23; run; assert_eq "exit 23 is a failure" "1" "$RC"; assert_contains "failure names the code" "$OUT" "rsync exit code 23"

# ---- 7. options from remote.ini ----
setup; write_ini 'RSYNC_BWLIMIT_KBPS=500
RSYNC_EXCLUDES="/logs/ *.tmp"
REMOTE_PORT=2222'; run
m=$(calls | grep -- '--delete-after')
assert_contains "bandwidth limit passed" "$m" "--bwlimit=500"; assert_contains "excludes passed" "$m" "--exclude=/logs/"; assert_contains "second exclude passed" "$m" "--exclude=*.tmp"
assert_contains "custom port used" "$(calls | head -1)" "-p 2222"

# ---- 8. a leftover REMOTE_DIR in the ini is ignored ----
setup; write_ini 'REMOTE_DIR="/srv/old/path"'; run
assert_eq "leftover REMOTE_DIR: still works" "0" "$RC"; assert_contains "leftover REMOTE_DIR: warned" "$OUT" "no longer used"
assert_not_contains "leftover REMOTE_DIR: never used as a path" "$(calls)" "/srv/old/path"
finish
