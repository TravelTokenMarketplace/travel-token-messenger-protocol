#!/usr/bin/env bash
# Guards the generator's svgz behavior: no rsvg/xs, gzip to .svgz, drop .svg.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="${REPO_ROOT}/scripts/generate_protodot.sh"
HELPER="${REPO_ROOT}/scripts/lib/svgz.sh"
fail=0
pass() { echo "✅ $1"; }
bad()  { echo "❌ $1"; fail=1; }

# --- Static assertions on the generator ---
grep -q 'svgz_convert'   "$GEN" && pass "calls svgz_convert"    || bad "calls svgz_convert"
grep -q 'gzip -c'        "$HELPER" && pass "gzips to svgz"        || bad "gzips to svgz"
grep -q '\.svgz'         "$GEN" && pass "references .svgz"     || bad "references .svgz"
grep -q 'rsvg-convert'   "$GEN" && bad  "still has rsvg-convert" || pass "no rsvg-convert"
grep -q '\.xs\.svg'      "$GEN" && bad  "still has xs variant"   || pass "no xs variant"

# --- Behavioral: the transform the generator performs ---
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' > "$work/x.dot.svg"
orig="$(cat "$work/x.dot.svg")"
source "${REPO_ROOT}/scripts/lib/svgz.sh"
( cd "$work" && svgz_convert "x.dot.svg" )
[ -f "$work/x.dot.svgz" ]  && pass "svgz produced" || bad "svgz produced"
[ ! -f "$work/x.dot.svg" ] && pass "svg removed"   || bad "svg removed"
[ "$(gunzip -c "$work/x.dot.svgz")" = "$orig" ] && pass "svgz round-trips" || bad "svgz round-trips"
[ "$(head -c2 "$work/x.dot.svgz" | od -An -tx1 | tr -d ' ')" = "1f8b" ] && pass "gzip magic ok" || bad "gzip magic ok"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
