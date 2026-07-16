#!/usr/bin/env bash
# Round-trips insert_diagram_link.sh + verify_diagram_links.sh, including the
# service-preferred anchor placement.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSERT="${REPO_ROOT}/scripts/insert_diagram_link.sh"
VERIFY="${REPO_ROOT}/scripts/verify_diagram_links.sh"
NAME="testlabel"
BASE="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/${NAME}"
fail=0
pass() { echo "✅ $1"; }
bad()  { echo "❌ $1"; fail=1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
mkdir -p proto/ttm/services/foo/v1 proto/ttm/types/bar/v1

# Service file: messages first, service LAST — proves the anchor is the service.
cat > proto/ttm/services/foo/v1/foo.proto <<'EOF'
syntax = "proto3";
package ttm.services.foo.v1;

message FooRequest {
  string id = 1;
}
message FooResponse {
  string ok = 1;
}
service FooService {
  rpc Get(FooRequest) returns (FooResponse);
}
EOF
# Type file: only a message.
cat > proto/ttm/types/bar/v1/bar.proto <<'EOF'
syntax = "proto3";
package ttm.types.bar.v1;

message Bar {
  string name = 1;
}
EOF

"$INSERT" "$NAME"

svc="proto/ttm/services/foo/v1/foo.proto"
typ="proto/ttm/types/bar/v1/bar.proto"
svc_url="${BASE}/${svc}.dot.svg"
typ_url="${BASE}/${typ}.dot.svg"

# Service file: summary once, anchored ABOVE the service but BELOW the first message.
summary_line=$(grep -n '<summary>🗺️ Show Diagram</summary>' "$svc" | head -1 | cut -d: -f1)
service_line=$(grep -n '^service ' "$svc" | head -1 | cut -d: -f1)
firstmsg_line=$(grep -n '^message ' "$svc" | head -1 | cut -d: -f1)
[ "$(grep -Fc '<summary>🗺️ Show Diagram</summary>' "$svc")" -eq 1 ] && pass "svc: summary once" || bad "svc: summary once"
if [ -n "$summary_line" ] && [ "$summary_line" -lt "$service_line" ] && [ "$summary_line" -gt "$firstmsg_line" ]; then
  pass "svc: anchored on the service (below messages)"
else
  bad "svc: anchored on the service (below messages) [summary=$summary_line service=$service_line firstmsg=$firstmsg_line]"
fi
grep -Fq '[![FooService Diagram]' "$svc" && pass "svc: alt = service name" || bad "svc: alt = service name"
[ "$(grep -Fo "($svc_url)" "$svc" | wc -l)" -eq 2 ] && pass "svc: svg url twice" || bad "svc: svg url twice"

# Type file: summary once, alt = message name, url twice.
[ "$(grep -Fc '<summary>🗺️ Show Diagram</summary>' "$typ")" -eq 1 ] && pass "type: summary once" || bad "type: summary once"
grep -Fq '[![Bar Diagram]' "$typ" && pass "type: alt = message name" || bad "type: alt = message name"
[ "$(grep -Fo "($typ_url)" "$typ" | wc -l)" -eq 2 ] && pass "type: svg url twice" || bad "type: svg url twice"

# Verify passes on the injected tree.
"$VERIFY" "$NAME" >/dev/null 2>&1 && pass "verify passes on injected tree" || bad "verify passes on injected tree"

# Tamper one url; verify MUST fail.
sed -i 's/\.dot\.svg/.dot.svgz/' "$typ"
"$VERIFY" "$NAME" >/dev/null 2>&1 && bad "verify should fail on tampered tree" || pass "verify fails on tampered tree"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
