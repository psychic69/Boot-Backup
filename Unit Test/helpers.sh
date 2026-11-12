#!/bin/bash
# helpers.sh - tiny assertion helpers shared by the test_*.sh files.
# Source it from a test:   source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
PASS=0
FAIL=0
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; [ -n "${2:-}" ] && echo "         $2"; }

skip() { echo "  skip - $1 ($2)"; }

# assert_eq <description> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}
# assert_contains <description> <haystack> <needle>
assert_contains() {
    if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "missing '$3' in: $2"; fi
}
# assert_not_contains <description> <haystack> <needle>
assert_not_contains() {
    if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "unexpected '$3' in: $2"; fi
}

# extract_fn <file> <function-name>  - print one function (from "name() {" to the first "}" at column 0)
extract_fn() { sed -n "/^$2()/,/^}/p" "$1"; }

# load_fns <file> <fn...>  - define functions from a script without running the script
load_fns() {
    local file="$1"; shift
    local fn
    for fn in "$@"; do
        eval "$(extract_fn "$file" "$fn")"
    done
}

# Run a command under a pseudo-terminal (the create script requires one). Extra stdin lines are
# sent whenever a prompt ending in ": " appears.  Usage: run_pty "input1|input2" cmd args...
run_pty() {
    local inputs="$1"; shift
    python3 -I "$TEST_DIR/pty_drive.py" "$inputs" "$@"
}

# ---- fake Unraid flash drive for the integrity tests ----
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
make_boot() {   # $1 = dir ; builds a healthy fake /boot with Unraid-style bare-hash .sha256 files, in root and previous/
    rm -rf "$1"; mkdir -p "$1/previous" "$1/config/plugins" "$1/syslinux" "$1/EFI-/boot" "$1/logs" "$1/.git"
    local f d
    for d in "$1" "$1/previous"; do
        for f in bzimage bzroot bzmodules bzfirmware memtest bzroot-gui; do
            head -c 2048 /dev/urandom > "$d/$f"
            sha_of "$d/$f" > "$d/$f.sha256"
        done
    done
    echo "key" > "$1/config/Pro.key"; echo "cfg" > "$1/config/plugins/a.plg"; echo cfg > "$1/syslinux/syslinux.cfg"
    echo x > "$1/EFI-/boot/bootx64.efi"; echo log > "$1/logs/a.log"; echo g > "$1/.git/HEAD"
    echo sys > "$1/ldlinux.sys"; echo c32 > "$1/ldlinux.c32"; : > "$1/BACKUP-11-03-2026-03-00"
}

finish() {
    echo "  -- $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
}
