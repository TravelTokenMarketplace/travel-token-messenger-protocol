#!/usr/bin/env bash
# Exercises gh_pages_size_report.sh against a fixture tree.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/gh_pages_size_report.sh"
fail=0
pass() { echo "✅ $1"; }
bad()  { echo "❌ $1"; fail=1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
site="$work/site"
mkdir -p "$site/dev/proto" "$site/main/proto"
# Known sizes: dev = 3000B, main = 1000B, root = 100B -> total 4100B
head -c 2000 /dev/zero > "$site/dev/proto/a.svg"
head -c 1000 /dev/zero > "$site/dev/proto/b.svg"
head -c 1000 /dev/zero > "$site/main/proto/a.svg"
head -c  100 /dev/zero > "$site/index.html"

out="$("$SCRIPT" "$site")"
echo "$out" | grep -Eq '^\| dev \|'          && pass "lists dev folder"   || bad "lists dev folder"
echo "$out" | grep -Eq '^\| main \|'         && pass "lists main folder"  || bad "lists main folder"
echo "$out" | grep -Eq '^\| \(root\) \|'     && pass "lists (root)"       || bad "lists (root)"
echo "$out" | grep -Eq '\*\*total\*\*.*4\.0 KB' && pass "total 4.0 KB"    || bad "total 4.0 KB ($out)"
# dev (3000) must sort above main (1000)
dev_ln=$(echo "$out" | grep -n '^| dev |'  | cut -d: -f1)
main_ln=$(echo "$out" | grep -n '^| main |' | cut -d: -f1)
[ "$dev_ln" -lt "$main_ln" ] && pass "sorted desc" || bad "sorted desc"

# --sizes-md writes the table to a file
"$SCRIPT" "$site" --sizes-md "$work/SIZES.md" >/dev/null
grep -q '| dev |' "$work/SIZES.md" && pass "SIZES.md written" || bad "SIZES.md written"

# No warning under the limit; warning when the limit is tiny.
"$SCRIPT" "$site" 2>&1 | grep -q '::warning::' && bad "no warning under limit" || pass "no warning under limit"
GH_PAGES_LIMIT_BYTES=1000 "$SCRIPT" "$site" 2>&1 | grep -q '::warning::' && pass "warns over limit" || bad "warns over limit"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
