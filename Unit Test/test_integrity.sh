#!/bin/bash
# Tests for lib/integrity.sh: Unraid .sha256 verification (root and previous/) and the backup manifest.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$REPO_ROOT/lib/logging.sh"
source "$REPO_ROOT/lib/integrity.sh"
echo "test_integrity"
LOG_FILE=""; DEBUG=false
log_message() { echo "$1"; }
quiet() { "$@" >"$TMP_DIR/out" 2>&1; local rc=$?; OUT=$(cat "$TMP_DIR/out"); return $rc; }

B="$TMP_DIR/boot"

# ---------------- verify_boot_hashes ----------------
make_boot "$B"; quiet verify_boot_hashes "$B"
assert_eq "healthy /boot passes" "0" "$?"; assert_contains "reports verified count" "$OUT" "12 verified"
make_boot "$B"; echo corrupt >> "$B/bzroot"; quiet verify_boot_hashes "$B"
assert_eq "corrupted root bzroot fails" "1" "$?"; assert_contains "names the file" "$OUT" "bzroot: HASH MISMATCH"
make_boot "$B"; echo corrupt >> "$B/previous/bzmodules"; quiet verify_boot_hashes "$B"
assert_eq "corrupted previous/bzmodules fails (previous is checked 100%)" "1" "$?"; assert_contains "names the previous/ file" "$OUT" "previous/bzmodules: HASH MISMATCH"
make_boot "$B"; echo corrupt >> "$B/memtest"; quiet verify_boot_hashes "$B"; assert_eq "memtest is checked too" "1" "$?"
make_boot "$B"; echo corrupt >> "$B/bzroot-gui"; quiet verify_boot_hashes "$B"; assert_eq "bzroot-gui is checked too" "1" "$?"
make_boot "$B"; rm "$B/bzimage"; quiet verify_boot_hashes "$B"
assert_eq "missing required bzimage fails" "1" "$?"; assert_contains "reported as missing" "$OUT" "Required boot file is missing: bzimage"
make_boot "$B"; rm "$B/previous/bzroot"; quiet verify_boot_hashes "$B"
assert_eq ".sha256 without its file fails" "1" "$?"; assert_contains "explains" "$OUT" "exists but the file itself is missing"
make_boot "$B"; rm "$B/bzfirmware.sha256"; quiet verify_boot_hashes "$B"; assert_eq "file with no .sha256 is not an error" "0" "$?"
make_boot "$B"; rm "$B/bzroot.sha256"; quiet verify_boot_hashes "$B"
assert_eq "required file without .sha256 only warns" "0" "$?"; assert_contains "warning shown" "$OUT" "bzroot has no bzroot.sha256"
make_boot "$B"; echo "not a hash" > "$B/bzimage.sha256"; quiet verify_boot_hashes "$B"
assert_eq "unreadable .sha256 only warns" "0" "$?"; assert_contains "warning shown" "$OUT" "does not contain a valid SHA-256"
make_boot "$B"; echo "$(sha_of "$B/bzroot")  bzroot" > "$B/bzroot.sha256"; quiet verify_boot_hashes "$B"; assert_eq "'hash  filename' format also accepted" "0" "$?"
make_boot "$B"; tr 'a-f' 'A-F' < "$B/bzroot.sha256" > "$TMP_DIR/up"; cp "$TMP_DIR/up" "$B/bzroot.sha256"; quiet verify_boot_hashes "$B"; assert_eq "uppercase hash accepted" "0" "$?"
make_boot "$B"; rm -rf "$B/previous"; quiet verify_boot_hashes "$B"; assert_eq "no previous/ folder is fine" "0" "$?"

# ---------------- write_backup_manifest ----------------
make_boot "$B"; quiet write_backup_manifest "$B"
assert_eq "manifest written" "0" "$?"; M="$B/$BACKUP_MANIFEST_NAME"
[ -f "$M" ] && pass "manifest file exists" || fail "manifest file exists"
assert_not_contains "manifest is not named BACKUP-*" "$BACKUP_MANIFEST_NAME" "BACKUP-"
list=$(cat "$M")
assert_contains "covers config/" "$list" "./config/Pro.key"
assert_contains "covers plugin files" "$list" "./config/plugins/a.plg"
assert_contains "covers syslinux/" "$list" "./syslinux/syslinux.cfg"
assert_contains "covers the (renamed) EFI- folder" "$list" "./EFI-/boot/bootx64.efi"
assert_contains "covers the .sha256 files themselves" "$list" "./bzroot.sha256"
paths=$(printf '%s\n' "$list" | awk '{ sub(/^[0-9a-f]+  /, ""); print }')
for ex in ./bzroot ./bzimage ./bzmodules ./bzfirmware ./memtest ./bzroot-gui ./previous/bzroot ./previous/bzmodules \
          ./ldlinux.sys ./ldlinux.c32 ./BACKUP-11-03-2026-03-00 ./logs/a.log ./.git/HEAD ./$BACKUP_MANIFEST_NAME; do
    if printf '%s\n' "$paths" | grep -qxF -- "$ex"; then fail "manifest excludes $ex"; else pass "manifest excludes $ex"; fi
done
(cd "$B" && sha256sum -c "$BACKUP_MANIFEST_NAME" >/dev/null 2>&1) && pass "manifest verifies against the folder it describes" || fail "manifest verifies"
echo changed >> "$B/config/Pro.key"
bad=$(cd "$B" && sha256sum -c "$BACKUP_MANIFEST_NAME" 2>/dev/null | grep -v ': OK$')
assert_contains "a changed config file is detected" "$bad" "./config/Pro.key: FAILED"
quiet write_backup_manifest "$B"; assert_eq "re-running replaces the manifest" "0" "$?"
(cd "$B" && sha256sum -c "$BACKUP_MANIFEST_NAME" >/dev/null 2>&1) && pass "new manifest matches the changed file" || fail "new manifest matches"
[ ! -e "$M.tmp" ] && pass "no temp file left behind" || fail "no temp file left behind"
mkdir -p "$B/dir with space"; echo s > "$B/dir with space/a b.txt"; quiet write_backup_manifest "$B"
(cd "$B" && sha256sum -c "$BACKUP_MANIFEST_NAME" >/dev/null 2>&1) && pass "paths with spaces round-trip" || fail "paths with spaces round-trip"
quiet write_backup_manifest "$TMP_DIR/does-not-exist"; assert_eq "missing directory fails cleanly" "1" "$?"

# ---------------- the checks are wired in, and run before anything is copied ----------------
clone_gate=$(grep -n 'verify_boot_hashes /boot' "$REPO_ROOT/lib/clone.sh" | head -1 | cut -d: -f1)
clone_copy=$(grep -n 'rsync "${rsync_args\[@\]}"' "$REPO_ROOT/lib/clone.sh" | head -1 | cut -d: -f1)
[ -n "$clone_gate" ] && [ -n "$clone_copy" ] && [ "$clone_gate" -lt "$clone_copy" ] && pass "clone_backup verifies the source before rsync" || fail "clone_backup verifies the source before rsync"
man_line=$(grep -n 'write_backup_manifest "\$CLONE_MP"' "$REPO_ROOT/lib/clone.sh" | head -1 | cut -d: -f1)
unm_line=$(grep -n 'Unmounting \$clone_source from' "$REPO_ROOT/lib/clone.sh" | head -1 | cut -d: -f1)
[ -n "$man_line" ] && [ -n "$unm_line" ] && [ "$man_line" -lt "$unm_line" ] && pass "manifest is written before the USB is unmounted" || fail "manifest is written before the USB is unmounted"

# ---- optional per-file cache bypass (used by the scrub) ----
bf="$TMP_DIR/bypass_file"; echo data > "$bf"
DD_LOG="$TMP_DIR/dd_log"; : > "$DD_LOG"
dd() { echo "dd $*" >> "$DD_LOG"; return "${DD_RC:-0}"; }
HASH_BYPASS_CACHE=false; CACHE_BYPASS_FAILED=false
sha256_of "$bf" >/dev/null; assert_eq "bypass off: dd not called" "0" "$(wc -l < "$DD_LOG" | tr -d ' ')"
HASH_BYPASS_CACHE=true
h=$(sha256_of "$bf"); assert_eq "bypass on: hash still correct" "$(sha_of "$bf")" "$h"
assert_contains "bypass on: dd evicts this file only" "$(cat "$DD_LOG")" "if=$bf iflag=nocache count=0"
DD_RC=1; sha256_of "$bf" >/dev/null; assert_eq "dd failure is flagged" "true" "$CACHE_BYPASS_FAILED"
unset -f dd; HASH_BYPASS_CACHE=false
finish
