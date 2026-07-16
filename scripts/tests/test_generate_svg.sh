#!/usr/bin/env bash
# Guards the generator's SVG behavior: optimize in place with SVGO, keep .svg,
# no gzip/.svgz, no rsvg/xs.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="${REPO_ROOT}/scripts/generate_protodot.sh"
HELPER="${REPO_ROOT}/scripts/lib/svg.sh"
fail=0
pass() { echo "✅ $1"; }
bad()  { echo "❌ $1"; fail=1; }

# --- Static assertions on the generator + helper ---
grep -q 'svg_optimize'   "$GEN"    && pass "calls svg_optimize"     || bad "calls svg_optimize"
grep -q 'lib/svg.sh'     "$GEN"    && pass "sources lib/svg.sh"     || bad "sources lib/svg.sh"
grep -q -- '--multipass' "$HELPER" && pass "svgo multipass"         || bad "svgo multipass"
grep -q 'svgo'           "$HELPER" && pass "helper uses svgo"       || bad "helper uses svgo"
grep -q 'gzip -c'        "$GEN"    && bad  "still gzips"             || pass "no gzip in generator"
grep -q '\.svgz'         "$GEN"    && bad  "still references .svgz"  || pass "no .svgz in generator"
grep -q 'rsvg-convert'   "$GEN"    && bad  "still has rsvg-convert"  || pass "no rsvg-convert"
grep -q '\.xs\.svg'      "$GEN"    && bad  "still has xs variant"    || pass "no xs variant"

# --- Behavioral: svg_optimize keeps .svg, makes no .svgz, passes --multipass ---
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><rect/></svg>' > "$work/x.dot.svg"
cat > "$work/fakesvgo" <<'STUB'
#!/bin/bash
# Fake SVGO: record args, leave the file in place (no-op optimize).
echo "$*" >> "$FAKE_LOG"
STUB
chmod +x "$work/fakesvgo"
export FAKE_LOG="$work/log"
export SVGO_CMD="$work/fakesvgo"
source "${REPO_ROOT}/scripts/lib/svg.sh"
svg_optimize "$work/x.dot.svg"
[ -f "$work/x.dot.svg" ]  && pass "svg kept"          || bad "svg kept"
[ ! -f "$work/x.dot.svgz" ] && pass "no svgz created" || bad "no svgz created"
grep -q -- '--multipass' "$work/log" && pass "invoked with --multipass" || bad "invoked with --multipass"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
