#!/bin/bash
# run_tests.sh - run every test_*.sh in this folder and summarize.
# Usage:  bash "Unit Test/run_tests.sh"            (run all)
#         bash "Unit Test/run_tests.sh" config     (run only tests whose name contains "config")
# Needs bash, python3 (pseudo-terminal tests) and ssh-keygen. Tests never touch real drives.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"
total=0; failed=0; failed_names=()

for t in "$DIR"/test_*.sh; do
    name=$(basename "$t" .sh)
    [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue
    total=$((total + 1))
    if ! bash "$t"; then
        failed=$((failed + 1)); failed_names+=("$name")
    fi
    echo
done

echo "=============================================="
echo "Test files run: $total   failed: $failed"
if [ "$failed" -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed_names[@]}"
    exit 1
fi
echo "ALL TESTS PASSED"
