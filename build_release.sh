#!/bin/bash
# build_release.sh - package the Boot-Backup release archive for GitHub Releases.
#
# Usage:  bash build_release.sh
# Output: dist/Boot-Backup-<version>.tar.gz and dist/Boot-Backup-<version>.tar.gz.sha256
#
# The version comes from the VERSION file (SCRIPT_VERSION=x.y.z). The archive contains a single
# top-level folder, dr_usb/, which is extracted to /boot/config/plugins/ on the Unraid server.
# User settings (dr_usb.ini) are never in the archive, so upgrading
# by extracting over an existing install does not overwrite them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# --- Version ---
if [ ! -f VERSION ]; then
    echo "ERROR: VERSION file not found in $ROOT" >&2
    exit 1
fi
VERSION=$(sed -n 's/^SCRIPT_VERSION=//p' VERSION | tr -d '[:space:]"')
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: VERSION must contain SCRIPT_VERSION=x.y.z (got '$VERSION')" >&2
    exit 1
fi

# --- Files that go into the release (paths relative to the repo root) ---
FILES=(
    VERSION
    LICENSE
    dr_usb_backup.sh
    dr_usb_create.sh
    dr_usb_scrub.sh
    dr_usb.ini.example
    lib/logging.sh
    lib/drives.sh
    lib/integrity.sh
    lib/clone.sh
    lib/config.sh
    Recovery-ISO/scripts/setup_ventoy_usb.sh
    Recovery-ISO/scripts/setup_ventoy.ini
    Recovery-ISO/scripts/move_dr_to_unraid.sh
)

# --- Checks ---
for f in "${FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: required file missing: $f" >&2
        exit 1
    fi
    case "$f" in
        *.sh)
            if ! bash -n "$f"; then
                echo "ERROR: syntax check failed: $f" >&2
                exit 1
            fi
            ;;
    esac
done

# --- Stage and package ---
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
for f in "${FILES[@]}"; do
    mkdir -p "$STAGE/dr_usb/$(dirname "$f")"
    cp "$f" "$STAGE/dr_usb/$f"
done

mkdir -p dist
OUT="dist/Boot-Backup-${VERSION}.tar.gz"
rm -f "$OUT" "$OUT.sha256"
# COPYFILE_DISABLE stops macOS tar from adding ._ metadata files
(cd "$STAGE" && find dr_usb -type f | LC_ALL=C sort) > "$STAGE/filelist.txt"
COPYFILE_DISABLE=1 tar -czf "$OUT" -C "$STAGE" -T "$STAGE/filelist.txt"

if command -v sha256sum >/dev/null 2>&1; then
    (cd dist && sha256sum "Boot-Backup-${VERSION}.tar.gz" > "Boot-Backup-${VERSION}.tar.gz.sha256")
else
    (cd dist && shasum -a 256 "Boot-Backup-${VERSION}.tar.gz" > "Boot-Backup-${VERSION}.tar.gz.sha256")
fi

# --- Verify the archive contains exactly what we staged ---
LISTED=$(tar -tzf "$OUT" | grep -v '/$' | LC_ALL=C sort)
EXPECTED=$(cat "$STAGE/filelist.txt")
if [ "$LISTED" != "$EXPECTED" ]; then
    echo "ERROR: archive contents do not match the expected file list" >&2
    exit 1
fi

echo "Built $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes, ${#FILES[@]} files)"
cat "$OUT.sha256"
echo
echo "Next steps:"
echo "  1. Commit and tag:   git tag v${VERSION} && git push origin v${VERSION}"
echo "  2. Create a GitHub Release for v${VERSION} and attach:"
echo "       $OUT"
echo "       $OUT.sha256"
echo "  3. Install on Unraid:"
echo "       tar -xzf Boot-Backup-${VERSION}.tar.gz -C /boot/config/plugins/ --no-same-owner --no-same-permissions"
