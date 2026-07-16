#!/usr/bin/env bash
# Summarize the published gh-pages size per top-level folder + total against the
# GitHub Pages 1 GB site limit. Prints a markdown table to stdout; with
# --sizes-md also writes it to a file; emits a GitHub ::warning:: (never fails)
# when the total reaches the warn threshold.
# Usage: gh_pages_size_report.sh <gh-pages-dir> [--sizes-md <path>]
set -euo pipefail

LIMIT="${GH_PAGES_LIMIT_BYTES:-1000000000}"   # 1 GB decimal, matches GitHub wording
WARN_PCT="${GH_PAGES_WARN_PCT:-80}"

dir="${1:?Usage: gh_pages_size_report.sh <gh-pages-dir> [--sizes-md <path>]}"
shift || true
sizes_md=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sizes-md) sizes_md="${2:?--sizes-md needs a path}"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -d "$dir" ] || { echo "not a directory: $dir" >&2; exit 2; }

human() {  # bytes -> human string
  awk -v b="$1" 'BEGIN{
    split("B KB MB GB TB", u, " "); i=1; s=b;
    while (s>=1024 && i<5){ s/=1024; i++ }
    printf (i==1 ? "%d %s" : "%.1f %s"), s, u[i]
  }'
}
pct() { awk -v n="$1" -v d="$LIMIT" 'BEGIN{ printf "%.1f%%", (d? n*100/d : 0) }'; }

declare -A folder_bytes
root_bytes=0
while IFS= read -r -d '' f; do
  rel="${f#"$dir"/}"
  top="${rel%%/*}"
  sz=$(stat -c '%s' "$f")
  if [ "$top" = "$rel" ]; then
    root_bytes=$(( root_bytes + sz ))
  else
    folder_bytes["$top"]=$(( ${folder_bytes["$top"]:-0} + sz ))
  fi
done < <(find "$dir" -type f -not -path '*/.git/*' -print0)

total=$root_bytes
for k in "${!folder_bytes[@]}"; do total=$(( total + folder_bytes[$k] )); done

table="$(
  echo "| folder | size | % of 1 GB |"
  echo "|---|---:|---:|"
  {
    for k in "${!folder_bytes[@]}"; do printf '%s\t%s\n' "${folder_bytes[$k]}" "$k"; done
    printf '%s\t%s\n' "$root_bytes" "(root)"
  } | sort -rn | while IFS=$'\t' read -r b name; do
    printf '| %s | %s | %s |\n' "$name" "$(human "$b")" "$(pct "$b")"
  done
  printf '| **total** | **%s** | **%s** |\n' "$(human "$total")" "$(pct "$total")"
)"

echo "$table"

if [ -n "$sizes_md" ]; then
  {
    echo "# gh-pages published size"
    echo
    echo "_Updated by CI on each diagram publish. Limit: 1 GB per GitHub Pages site._"
    echo
    echo "$table"
  } > "$sizes_md"
fi

if [ "$(( total * 100 / LIMIT ))" -ge "$WARN_PCT" ]; then
  echo "::warning::gh-pages site is $(human "$total") / 1 GB ($(pct "$total")) — approaching the GitHub Pages limit"
fi
