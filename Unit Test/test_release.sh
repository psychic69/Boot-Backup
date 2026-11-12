#!/bin/bash
# Tests for the single-VERSION layout, setup_ventoy_usb.sh's version loading, and build_release.sh.
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "test_release"

VER=$(sed -n 's/^SCRIPT_VERSION=//p' "$REPO_ROOT/VERSION" | tr -d '[:space:]"')
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && pass "root VERSION is x.y.z ($VER)" || fail "root VERSION is x.y.z" "$VER"
[ ! -e "$REPO_ROOT/Recovery-ISO/scripts/VERSION" ] && pass "no second VERSION file in Recovery-ISO/scripts" || fail "no second VERSION file in Recovery-ISO/scripts"
[ -n "$(tail -c1 "$REPO_ROOT/VERSION")" ] && fail "VERSION ends with a newline" || pass "VERSION ends with a newline"

# the version-loading block of setup_ventoy_usb.sh, run in a sandbox that has the same two-level layout
sb="$TMP_DIR/sb"; mkdir -p "$sb/Recovery-ISO/scripts"
sed -n '/^SCRIPT_DIR=/,/^# Source configuration file/p' "$REPO_ROOT/Recovery-ISO/scripts/setup_ventoy_usb.sh" | sed '$d' > "$sb/Recovery-ISO/scripts/block.sh"
echo 'echo "VERSION=$VERSION"' >> "$sb/Recovery-ISO/scripts/block.sh"
printf 'SCRIPT_VERSION=9.8.7\n' > "$sb/VERSION"
out=$(bash "$sb/Recovery-ISO/scripts/block.sh" 2>&1); assert_eq "setup_ventoy reads ../../VERSION" "VERSION=9.8.7" "$out"
printf 'SCRIPT_VERSION=oops\n' > "$sb/VERSION"
out=$(bash "$sb/Recovery-ISO/scripts/block.sh" 2>&1); assert_contains "invalid version rejected" "$out" "invalid or missing SCRIPT_VERSION"
rm "$sb/VERSION"
out=$(bash "$sb/Recovery-ISO/scripts/block.sh" 2>&1); assert_contains "missing VERSION explained" "$out" "VERSION file not found"

# build the real archive and inspect it
(cd "$REPO_ROOT" && bash build_release.sh >/dev/null 2>&1); assert_eq "build_release.sh succeeds" "0" "$?"
ar="$REPO_ROOT/dist/Boot-Backup-$VER.tar.gz"
[ -f "$ar" ] && pass "archive named after VERSION" || fail "archive named after VERSION" "$ar"
[ -f "$ar.sha256" ] && pass "sha256 file written" || fail "sha256 file written"
list=$(tar -tzf "$ar")
for f in dr_usb/VERSION dr_usb/dr_usb_backup.sh dr_usb/dr_usb_create.sh dr_usb/dr_usb_scrub.sh dr_usb/dr_usb.ini.example \
         dr_usb/lib/logging.sh dr_usb/lib/drives.sh dr_usb/lib/integrity.sh dr_usb/lib/clone.sh dr_usb/lib/config.sh \
         dr_usb/Recovery-ISO/scripts/setup_ventoy_usb.sh dr_usb/Recovery-ISO/scripts/setup_ventoy.ini dr_usb/Recovery-ISO/scripts/move_dr_to_unraid.sh; do
    assert_contains "archive contains $f" "$list" "$f"
done
for f in "dr_usb/dr_usb.ini"; do
    if printf '%s\n' "$list" | grep -qx "$f"; then fail "archive excludes your settings file $f"; else pass "archive excludes your settings file $f"; fi
done
for f in "id_ed25519" "known_hosts" "dist/" "Unit Test" "Docs/"; do
    assert_not_contains "archive excludes $f" "$list" "$f"
done
assert_not_contains "no remote code (removed in 1.3.0)" "$list" "remote"
assert_not_contains "no macOS ._ metadata files" "$list" "._"
mkdir -p "$TMP_DIR/ex"; tar -xzf "$ar" -C "$TMP_DIR/ex" --no-same-owner --no-same-permissions
ok=true; for f in $(cd "$TMP_DIR/ex/dr_usb" && find . -name '*.sh'); do bash -n "$TMP_DIR/ex/dr_usb/$f" || ok=false; done
$ok && pass "every extracted script passes bash -n" || fail "every extracted script passes bash -n"

# the extracted copy finds its modules and settings (flat run, no real drives needed)
out=$(bash "$TMP_DIR/ex/dr_usb/dr_usb_backup.sh" -bogus 2>&1)
assert_contains "extracted backup script runs and parses options" "$out" 'Unknown option: "-bogus"'
mv "$TMP_DIR/ex/dr_usb/lib" "$TMP_DIR/ex/dr_usb/lib.gone"
out=$(bash "$TMP_DIR/ex/dr_usb/dr_usb_backup.sh" 2>&1)
assert_contains "missing lib/ is reported clearly" "$out" "Missing module"
finish
