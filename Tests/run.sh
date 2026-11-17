#!/bin/bash
# Snapshot tests: renders every Tests/cases/*.md and diffs it against the .html next to it.
# Run with UPDATE=1 to rewrite the snapshots after an intended change.
set -u
bin="$1"
dir="$(cd "$(dirname "$0")" && pwd)/cases"
fail=0
for md in "$dir"/*.md; do
    expected="${md%.md}.html"
    actual="$("$bin" --fragment --mark-images "$md")"
    if [ "${UPDATE:-0}" = 1 ]; then
        printf '%s' "$actual" > "$expected"
        echo "updated $(basename "$expected")"
    elif diff -u "$expected" <(printf '%s' "$actual") > /dev/null; then
        echo "✓ $(basename "$md")"
    else
        echo "✗ $(basename "$md")"
        diff -u "$expected" <(printf '%s' "$actual")
        fail=1
    fi
done
exit $fail
