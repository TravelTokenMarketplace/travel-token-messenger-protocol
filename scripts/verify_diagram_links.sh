#!/bin/bash
# Verify the diagram <details> block was injected into every anchored proto file
# with the expected per-name .svgz URL. URL reachability is NOT checked.
# Run AFTER insert_diagram_link.sh, passing the same <name>.
# Usage: verify_diagram_links.sh <name>
set -uo pipefail
ERROR=0

NAME="${1:?Usage: verify_diagram_links.sh <name>}"
BASEURL="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/${NAME}"

while IFS= read -r file; do
    # Only files with an anchor (service/message/enum) get a block.
    grep -qE '^(service|message|enum) ' "$file" || continue

    url="${BASEURL}/${file}.dot.svgz"
    summary_count=$(grep -Fc "<summary>🗺️ Show Diagram</summary>" "$file")
    # The linked image "[![alt](url)](url)" references the url twice (src + href).
    url_count=$(grep -Fo "(${url})" "$file" | wc -l)

    if [ "$summary_count" -ne 1 ] || [ "$url_count" -ne 2 ]; then
        echo "❌ Error: '$file' missing expected diagram block (summary=$summary_count want 1, url=$url_count want 2)."
        ERROR=1
    fi
done < <(find proto/ -type f -name "*.proto")

if [ "$ERROR" -ne 0 ]; then
    echo "❌ One or more files have invalid diagram links."
    exit 1
fi
echo "✅ All diagram blocks are valid."
