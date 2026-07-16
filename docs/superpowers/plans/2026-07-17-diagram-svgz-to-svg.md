# Diagram `.svgz` → SVGO `.svg` + gh-pages size report — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve protodot diagrams as plain SVGO-optimized `.svg` (fixing the `.svgz` double-compression on GitHub Pages), and add a per-folder gh-pages size report against the 1 GB limit.

**Architecture:** GitHub Pages/Fastly already gzips `image/svg+xml` on the wire, so a stored `.svgz` double-compresses and renders as binary. Switch the generator to optimize each `.svg` in place with SVGO (via `npx`, not the snap binary) and keep the `.svg`; repoint the injected BSR diagram links to `.svg`. Add a script that reports gh-pages folder sizes into the Actions step summary and a committed `SIZES.md`, warning at 80 % of 1 GB.

**Tech Stack:** Bash scripts + bash test harness, GitHub Actions composite action, SVGO (`npx --yes svgo@3`), Node (mise locally / setup-node in CI).

## Global Constraints

- Diagram link base URL (verbatim): `https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/<name>` — one path segment per publish label.
- SVGO is invoked as `npx --yes svgo@3 --multipass` (NOT the snap `svgo`, which cannot read `/hgst`). Overridable in scripts via `SVGO_CMD` for testing.
- SVGO config lives at repo root `svgo.config.mjs`, `preset-default` with `removeViewBox: false`.
- Pages size limit constant = `1000000000` bytes (decimal GB); warn threshold 80 %.
- All scripts keep the existing `set -uo pipefail` / `set -euo pipefail` style already used in the repo; tests are bash and print `ALL PASS` / `FAILURES` and exit non-zero on failure.
- Commit style: conventional commits (`feat:`, `fix:`, `ci:`, `test:`, `docs:`), matching repo history.
- All work lands on `dev`. Do NOT fast-forward `main` or touch `PUBLISH_ENABLED` / `sanity-checks` until the Rollout task.

---

### Task 1: Replace gzip-to-`.svgz` with SVGO optimize (keep `.svg`)

**Files:**
- Create: `svgo.config.mjs`
- Rename+rewrite: `scripts/lib/svgz.sh` → `scripts/lib/svg.sh`
- Modify: `scripts/generate_protodot.sh` (lines 11-12 source; lines 99-102 convert block)
- Rename+rewrite: `scripts/tests/test_generate_svgz.sh` → `scripts/tests/test_generate_svg.sh`
- Modify: `.github/workflows/ci.yaml` (`script-tests` job, ~line 240)

**Interfaces:**
- Produces: `svg_optimize <path-to.svg>` (in `scripts/lib/svg.sh`) — optimizes the SVG in place with SVGO `--multipass`, leaves a `.svg` (never a `.svgz`); honors `SVGO_CMD` env override (default `npx --yes svgo@3`).

- [ ] **Step 1: Create the SVGO config**

Create `svgo.config.mjs`:

```js
// SVGO config for protodot/graphviz diagrams served from GitHub Pages.
// Conservative: keep viewBox (its removal breaks diagram scaling) and do not
// touch the <a xlink:href> links / text protodot emits.
export default {
  multipass: true,
  plugins: [
    {
      name: 'preset-default',
      params: {
        overrides: {
          removeViewBox: false,
        },
      },
    },
  ],
};
```

- [ ] **Step 2: Write the rewritten failing test**

`git mv scripts/tests/test_generate_svgz.sh scripts/tests/test_generate_svg.sh`, then replace its contents with:

```bash
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
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash scripts/tests/test_generate_svg.sh`
Expected: FAIL (`FAILURES`) — `scripts/lib/svg.sh` does not exist yet and `generate_protodot.sh` still calls `svgz_convert`.

- [ ] **Step 4: Create `scripts/lib/svg.sh` and remove `svgz.sh`**

`git rm scripts/lib/svgz.sh`, then create `scripts/lib/svg.sh`:

```bash
#!/bin/bash
# Optimize an SVG diagram in place with SVGO (multipass), keeping the .svg.
# GitHub Pages gzips image/svg+xml transparently on the wire, so a stored .svgz
# would double-compress and render as binary. We therefore serve plain .svg.
# SVGO runs via npx (mise/CI Node), NOT the snap `svgo` which is confined to
# $HOME and cannot read the repo under /hgst. Override SVGO_CMD in tests.
: "${SVGO_CMD:=npx --yes svgo@3}"
svg_optimize() {
    local svg="$1"
    local lib_dir cfg
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cfg="${lib_dir}/../../svgo.config.mjs"
    # shellcheck disable=SC2086  # SVGO_CMD is intentionally word-split (npx ... svgo)
    ${SVGO_CMD} --multipass --config "${cfg}" --input "${svg}" --output "${svg}"
}
```

- [ ] **Step 5: Switch the generator to `svg_optimize`**

In `scripts/generate_protodot.sh`, change the source line (line 12):

```bash
# shellcheck source=scripts/lib/svg.sh
source "$(dirname "$0")/lib/svg.sh"
```

and replace the convert block (lines 99-102):

```bash
    # Optimize the diagram in place with SVGO (kept as .svg). Pages gzips SVG on
    # the wire, so a stored .svgz would double-compress; serve plain .svg.
    svg_filename="${GENERATED_DIR}/${PROTODOT_DIR}/${protofile}.dot.svg"
    svg_optimize "${svg_filename}"
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash scripts/tests/test_generate_svg.sh`
Expected: PASS (`ALL PASS`).

- [ ] **Step 7: Update the CI `script-tests` job to the renamed test**

In `.github/workflows/ci.yaml`, in the `script-tests` job `run:` block, change `bash scripts/tests/test_generate_svgz.sh` to `bash scripts/tests/test_generate_svg.sh` (leave `test_diagram_links.sh` as-is for now).

- [ ] **Step 8: Commit**

```bash
git add svgo.config.mjs scripts/lib/svg.sh scripts/generate_protodot.sh \
        scripts/tests/test_generate_svg.sh .github/workflows/ci.yaml
git rm --cached scripts/lib/svgz.sh scripts/tests/test_generate_svgz.sh 2>/dev/null || true
git commit -m "feat: optimize diagrams with SVGO and serve plain .svg

Pages double-compresses stored .svgz (Fastly gzips image/svg+xml on the
wire). Optimize each .svg in place with SVGO --multipass via npx and keep
the .svg. Removes the gzip/.svgz helper."
```

---

### Task 2: Point injected BSR diagram links at `.svg`

**Files:**
- Modify: `scripts/insert_diagram_link.sh:27`
- Modify: `scripts/verify_diagram_links.sh:3,16`
- Modify: `scripts/tests/test_diagram_links.sh` (URLs, labels, tamper)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: injected diagram blocks whose image `src`/`href` end in `.dot.svg`; `verify_diagram_links.sh <name>` enforces the `.svg` URL twice per anchored proto.

- [ ] **Step 1: Update the round-trip test to expect `.svg` (failing)**

In `scripts/tests/test_diagram_links.sh`:
- lines 47-48: change `.dot.svgz` → `.dot.svg`:

```bash
svc_url="${BASE}/${svc}.dot.svg"
typ_url="${BASE}/${typ}.dot.svg"
```

- line 61 label and line 66 label: change `svgz url twice` → `svg url twice`.
- line 72 (tamper): break the `.svg` URL so verify must fail:

```bash
sed -i 's/\.dot\.svg/.dot.svgz/' "$typ"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test_diagram_links.sh`
Expected: FAIL — `insert_diagram_link.sh` still writes `.dot.svgz`, so `svc_url`/`typ_url` (now `.svg`) appear 0 times.

- [ ] **Step 3: Switch the injector to `.svg`**

In `scripts/insert_diagram_link.sh`, line 27:

```bash
        url=base "/" path ".dot.svg"
```

- [ ] **Step 4: Switch the verifier to `.svg`**

In `scripts/verify_diagram_links.sh`:
- line 3 comment: replace `.svgz` with `.svg`.
- line 16:

```bash
    url="${BASEURL}/${file}.dot.svg"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash scripts/tests/test_diagram_links.sh`
Expected: PASS (`ALL PASS`).

- [ ] **Step 6: Commit**

```bash
git add scripts/insert_diagram_link.sh scripts/verify_diagram_links.sh \
        scripts/tests/test_diagram_links.sh
git commit -m "fix: point BSR diagram links at .svg instead of .svgz"
```

---

### Task 3: gh-pages size report script + test

**Files:**
- Create: `scripts/gh_pages_size_report.sh`
- Create: `scripts/tests/test_gh_pages_size_report.sh`
- Modify: `.github/workflows/ci.yaml` (`script-tests` job — add the new test)

**Interfaces:**
- Produces: `gh_pages_size_report.sh <gh-pages-dir> [--sizes-md <path>]` — prints a markdown table (folder | size | % of 1 GB, sorted desc, total row) to stdout; with `--sizes-md` also writes that table (with a heading) to the path; emits a `::warning::…` line when total ≥ 80 % of the limit; never exits non-zero on a large size. Limit/threshold overridable via `GH_PAGES_LIMIT_BYTES` / `GH_PAGES_WARN_PCT`.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_gh_pages_size_report.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/test_gh_pages_size_report.sh`
Expected: FAIL — `scripts/gh_pages_size_report.sh` does not exist.

- [ ] **Step 3: Write the size-report script**

Create `scripts/gh_pages_size_report.sh`:

```bash
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
```

- [ ] **Step 4: Make it executable and run the test to verify it passes**

Run: `chmod +x scripts/gh_pages_size_report.sh && bash scripts/tests/test_gh_pages_size_report.sh`
Expected: PASS (`ALL PASS`).

- [ ] **Step 5: Wire the new test into CI**

In `.github/workflows/ci.yaml`, `script-tests` job `run:` block, add a final line:

```bash
          bash scripts/tests/test_gh_pages_size_report.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts/gh_pages_size_report.sh scripts/tests/test_gh_pages_size_report.sh \
        .github/workflows/ci.yaml
git commit -m "feat: report gh-pages size per folder against the 1GB limit"
```

---

### Task 4: Wire SVGO + size report into the diagrams action

**Files:**
- Modify: `.github/actions/generate-diagrams/action.yml`

**Interfaces:**
- Consumes: `svg_optimize` (Task 1, runs inside `generate_protodot.sh`) and `gh_pages_size_report.sh` (Task 3).
- Produces: an action that installs Node before generation and, after publishing the label, updates `SIZES.md` at the gh-pages root and appends the size table to the run summary.

- [ ] **Step 1: Add Node setup before diagram generation**

In `.github/actions/generate-diagrams/action.yml`, insert as the FIRST step under `steps:` (before `Setup Graphviz`), so `npx svgo` is available when `generate_protodot.sh` runs:

```yaml
    - name: Setup Node (for SVGO)
      uses: actions/setup-node@v4
      with:
        node-version: "22"
```

- [ ] **Step 2: Add the post-publish size report + SIZES.md commit**

Append these steps AFTER the existing `Publish to gh-pages/<name>` step:

```yaml
    - name: Checkout gh-pages
      uses: actions/checkout@v4
      with:
        ref: gh-pages
        path: _ghpages
    - name: Size report + SIZES.md
      shell: bash
      run: |
        bash scripts/gh_pages_size_report.sh _ghpages --sizes-md _ghpages/SIZES.md \
          | tee -a "$GITHUB_STEP_SUMMARY"
    - name: Commit SIZES.md
      shell: bash
      working-directory: _ghpages
      run: |
        git config user.name  "github-actions[bot]"
        git config user.email "github-actions[bot]@users.noreply.github.com"
        git add SIZES.md
        if git diff --cached --quiet; then
          echo "SIZES.md unchanged; nothing to commit."
        else
          git commit -m "chore(pages): update SIZES.md [skip ci]"
          git push origin gh-pages
        fi
```

- [ ] **Step 3: Validate the action YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/actions/generate-diagrams/action.yml')); print('OK')"`
Expected: `OK`.

- [ ] **Step 4: Smoke-test the size script against the real seeded branch (optional but recommended)**

Run:
```bash
tmp=$(mktemp -d); git -C "$tmp" clone --branch gh-pages --depth 1 \
  "$(git config --get remote.origin.url)" site >/dev/null 2>&1 \
  || git clone --branch gh-pages --depth 1 "$(git remote get-url origin)" "$tmp/site"
bash scripts/gh_pages_size_report.sh "$tmp/site"; rm -rf "$tmp"
```
Expected: a table listing the `dev` folder and a total (the canary's current `.svgz` content — proves the script runs on real data).

- [ ] **Step 5: Commit**

```bash
git add .github/actions/generate-diagrams/action.yml
git commit -m "ci: install Node for SVGO and publish gh-pages SIZES.md size report"
```

---

### Task 5: Rollout (resume the paused sequence)

> Operational, not TDD. `PUBLISH_ENABLED` stays `true` throughout (fix-forward). Run these in order only after Tasks 1-4 are committed on `dev`.

- [ ] **Step 1: Push the pipeline changes to `dev`**

```bash
git push origin dev
```

- [ ] **Step 2: Watch the `dev` CI run go green**

Run: `gh run list -R TravelTokenMarketplace/travel-token-messenger-protocol -L 3`
Then: `gh run view <id> --json jobs --jq '.jobs[] | "\(.conclusion // .status)\t\(.name)"'`
Expected: `buf-lint`, `dev-diagrams`, `dev-push`, `script-tests` all `success`; `sanity-checks` still `skipped`.

- [ ] **Step 3: Verify SVG serving on Pages**

```bash
U=https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/dev/proto/ttm/types/v5/total_price.proto.dot.svg
curl -s -H 'Accept-Encoding: gzip' "$U" -D - -o /tmp/d.out | grep -iE 'content-type|content-encoding'
gunzip -c /tmp/d.out 2>/dev/null | head -c 5   # expect: <svg (or <?xml)
```
Expected headers: `content-type: image/svg+xml`, `content-encoding: gzip`; decoded body starts with `<svg`/`<?xml`.

- [ ] **Step 4: Verify inline render on BSR**

Open a `dev`-label proto with a diagram on buf.build (e.g. a `service`) and confirm the diagram renders inline (not a broken image / download). Confirm `SIZES.md` exists at `https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/SIZES.md`.

- [ ] **Step 5: Purge stale `.svgz` from gh-pages**

```bash
tmp=$(mktemp -d)
git clone --branch gh-pages "$(git remote get-url origin)" "$tmp/gp"
cd "$tmp/gp"
git rm -q $(git ls-files '*.svgz')
git commit -m "chore(pages): remove stale .svgz (served plain .svg now)"
git push origin gh-pages
cd - >/dev/null && rm -rf "$tmp"
```
Expected: only `.svg` diagrams remain under each label.

- [ ] **Step 6: Fast-forward `dev → main` (seeds the BSR `main` baseline)**

```bash
git push origin dev:main
```
Then verify `main-diagrams` + `main-push` succeed (same `gh run view` check as Step 2, for the `main` push run).

- [ ] **Step 7: Re-enable `sanity-checks`** (pre-existing rollout step, only now that the `main` BSR baseline exists)

In `.github/workflows/ci.yaml`, in the `sanity-checks` job, remove `if: false` and replace with the scoped condition recorded in its own comment:

```yaml
    if: ${{ github.event_name == 'pull_request' || (github.event_name == 'push' && (github.ref == 'refs/heads/dev' || github.ref == 'refs/heads/main')) }}
```

```bash
git add .github/workflows/ci.yaml
git commit -m "ci: re-enable sanity-checks now that the main BSR baseline exists"
git push origin dev
git push origin dev:main
```
Expected: `sanity-checks` runs (no longer skipped) and passes on `dev`/`main`.

---

## Self-Review

- **Spec coverage:** SVGO/`.svg` switch (Tasks 1-2, 4); `npx`/snap avoidance (Task 1 constraint + `svg.sh`); `svgo.config.mjs` + `removeViewBox:false` (Task 1); link repoint + verify (Task 2); size report script + SIZES.md + step summary + 80 % warn (Tasks 3-4); one-time `.svgz` purge (Task 5.5); verification curl + BSR (Task 5.3-5.4); resume rollout incl. sanity-checks (Task 5). All spec sections mapped.
- **Placeholder scan:** none — every code/step is concrete.
- **Type/name consistency:** `svg_optimize`, `SVGO_CMD`, `gh_pages_size_report.sh` args (`--sizes-md`, `GH_PAGES_LIMIT_BYTES`, `GH_PAGES_WARN_PCT`), and the `_ghpages` path are used identically across tasks.
