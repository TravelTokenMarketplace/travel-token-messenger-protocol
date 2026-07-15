#!/bin/bash
# Injects per-name GitHub Pages diagram links into proto files.
# Run on a throwaway checkout right before `buf push` — do NOT commit the result.
set -euo pipefail

name="${1:?Usage: insert_diagram_link.sh <name>}"
base="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/${name}"
directory="proto"

find "$directory" -type f -name "*.proto" | while read -r proto_file; do
    # Service-preferred anchor: attach to the `service` if the file has one (BSR
    # renders services on top of the package), else the first message/enum.
    if grep -qE '^service ' "$proto_file"; then
        anchor='^service '
    else
        anchor='^(message|enum) '
    fi

    awk -v base="$base" -v path="$proto_file" -v anchor="$anchor" '
    !inserted && $0 ~ anchor {
        name=$2
        sub(/\{.*/, "", name)          # strip trailing "{" if attached
        url=base "/" path ".dot.svgz"
        print "//"
        print "// <details>"
        print "// <summary>🗺️ Show Diagram</summary>"
        print "//"
        print "// [![" name " Diagram](" url ")](" url ")"
        print "//"
        print "// _Click the image above holding CTRL to open the diagram in a new tab._"
        print "// </details>"
        print "//"
        inserted=1
    }
    { print }
    ' "$proto_file" > temp_file && mv temp_file "$proto_file"
done
