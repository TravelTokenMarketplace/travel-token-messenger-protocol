#!/bin/bash

# verify that all diagram links in the proto files are valid meaning that they
# follow the expected pattern. If the url is actually reachable is not checked.
# Also check if the url has the correct path in it based on the proto file path.
#
# Run this AFTER scripts/insert_diagram_link.sh has injected the per-branch
# links (i.e. on the throwaway push checkout), passing the same branch name.
# Usage: verify_diagram_links.sh <branch>
ERROR=0

BRANCH="${1:?Usage: verify_diagram_links.sh <branch>}"
BASEURL="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/${BRANCH}"

for file in $(find proto/ -name "*.proto"); do
	#echo "Checking file: $file"
	diagram_link_count=$(grep -Fc "(${BASEURL}/${file}.dot.xs.svg)" "$file")
	open_diagram_link_count=$(grep -Fc "(${BASEURL}/${file}.dot.svg)" "$file")

	if [ "$diagram_link_count" -ne 1 ] || [ "$open_diagram_link_count" -ne 1 ]; then
		echo "❌ Error: File '$file' does not contain the expected diagram links."
		echo "Found $diagram_link_count diagram link(s) and $open_diagram_link_count open diagram link(s)."
		ERROR=1
	fi
done

if [ "$ERROR" -ne 0 ]; then
	echo "❌ One or more files have invalid diagram links."
	exit 1
else
	echo "✅ All diagram links are valid."
	exit 0
fi
