#!/bin/bash

echo "Starting buf breaking check..."

AGAINST=${1:-buf.build/ttm/messenger-protocol}
EXCLUDE_FILE="missing_files.txt"
EXCLUDE=""

echo "AGAINST: ${AGAINST}"

if [ -f "${EXCLUDE_FILE}" ] ; then
        echo "Exclude file '${EXCLUDE_FILE}' found in current dir, building exclude list..."
        EXCLUDE="--exclude-path $(cat "${EXCLUDE_FILE}" | sed -e's#proto/##g' | tr "\n" "," | head -c -1)"
fi

if [ -z "$EXCLUDE" ]; then
	echo "No excludes defined, running buf breaking without exclude paths."
else
	echo "Running buf breaking with exclude parameter: '${EXCLUDE}'"
fi

echo "Running buf breaking..."
output="$(buf breaking $EXCLUDE --against "$AGAINST" 2>&1)"
status=$?
echo "${output}"

# Bootstrap guard: a freshly-created BSR module has no `main` commit to compare
# against, and `buf breaking` fails hard in that case. Treat only that specific
# "empty baseline" failure as a pass so the first CI run after the module is
# created doesn't block — real breaking changes still fail normally. Remove this
# guard once the `main` label is seeded, if you prefer a strict check.
if [ "${status}" -ne 0 ] && printf '%s\n' "${output}" | grep -qiE 'does not have any commits|has no commits|has no history|no such (module|commit|label)|(module|reference|label).*(does not exist|not found)'; then
	echo "buf-breaking: baseline '${AGAINST}' has no commits yet (new BSR module) — skipping breaking check. Seed the 'main' label with an initial non-draft push to activate it."
	exit 0
fi

exit "${status}"
