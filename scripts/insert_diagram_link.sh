#!/bin/bash
# Injects per-branch GitHub Pages diagram links into proto files.
# Run on a throwaway checkout right before `buf push` — do NOT commit the result.
set -euo pipefail

branch="${1:?Usage: insert_diagram_link.sh <branch>}"
base="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/${branch}"
directory="proto"

find "$directory" -type f -name "*.proto" | while read -r proto_file; do
    awk -v base="$base" -v path="$proto_file" '
    !inserted && /^enum|^message|^service/ {
        print "// ![Diagram](" base "/" path ".dot.xs.svg)"
        print "// [Open Message Diagram](" base "/" path ".dot.svg)"
        inserted=1
    }
    { print }
    ' "$proto_file" > temp_file && mv temp_file "$proto_file"
done
