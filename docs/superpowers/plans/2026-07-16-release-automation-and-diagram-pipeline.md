# Release Automation & Diagram Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate BSR publishing under per-target labels (release / main / dev / manual preview) with diagrams generated per target, and slim the diagram pipeline (drop the oversized `xs` SVG, serve `.svgz`, render diagrams as collapsible linked-image doc blocks anchored on services).

**Architecture:** All publish targets compute one **publish name** that drives the gh-pages diagram directory, the injected diagram-link path, and the BSR label — every push is `buf push proto --label "<name>"`. Shared work lives in two composite actions (`generate-diagrams`, `bsr-push`); `ci.yaml` has a thin diagrams+push job pair per target. The whole publish pipeline is gated behind one repo variable so it stays dormant until GitHub Pages + the BSR module are ready (keeps the in-flight rebrand PR green).

**Tech Stack:** GitHub Actions (composite actions, `workflow_dispatch`/`release` triggers), bash + awk tooling scripts, buf CLI (BSR labels), protodot + graphviz (diagram generation), gzip (`.svgz`), peaceiris/actions-gh-pages.

**Spec:** `docs/superpowers/specs/2026-07-16-release-automation-and-diagram-pipeline-design.md`

## Global Constraints

- BSR module name (from `buf.yaml`): **`buf.build/ttm/messenger-protocol`**. `buf push proto` reads it — do not hardcode elsewhere.
- Pages base URL: **`https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/<name>`** (note: the git-repo segment stays `travel-token-messenger-protocol`; only the BSR module differs).
- Buf install: **keep `scripts/buf-installer.sh`** (latest). Do NOT switch to `bufbuild/buf-setup-action` (token + rate limits).
- Publish name rule: `name = 'draft'` for a manual dispatch with the toggle off; otherwise `name = github.ref_name` (release tag `release-N`, or `main`/`dev`, or the branch when the toggle is on).
- Diagrams are **per proto file**; publish only `.svgz` (no `.svg`, no `.xs.svg`).
- Injected diagram block anchors on the `service` when the file has one, else the first `message`/`enum` (service-preferred, spec §4.7).
- Publish pipeline gate: repo variable **`PUBLISH_ENABLED`** must equal the string `'true'` for any diagrams/push job to run. Enable post-merge with `gh variable set PUBLISH_ENABLED --body true`.
- This work lands on branch **`rebranding`** (PR #1 → dev). It must not break that PR: it must not un-gate `sanity-checks`, and the new publish jobs must stay dormant (via `PUBLISH_ENABLED`) until enablement.

## File Structure

- `scripts/generate_protodot.sh` — **modify**: drop the `rsvg-convert` `xs` step; gzip each `<proto>.dot.svg` to `<proto>.dot.svgz` and delete the `.svg`.
- `scripts/insert_diagram_link.sh` — **modify**: emit the collapsible `<details>` linked-image block; service-preferred anchor; `.svgz` URL.
- `scripts/verify_diagram_links.sh` — **modify**: validate the new block shape / `.svgz` URL (URL appears twice; summary once) per anchored file.
- `scripts/tests/test_generate_svgz.sh` — **create**: guards the generator's svgz change.
- `scripts/tests/test_diagram_links.sh` — **create**: round-trips insert + verify (incl. service-anchor placement).
- `.github/actions/generate-diagrams/action.yml` — **create**: setup graphviz + protodot, run generator, stage, publish to `gh-pages/<name>`.
- `.github/actions/bsr-push/action.yml` — **create**: install buf, inject+verify links, `buf push --label <name>`.
- `.github/workflows/ci.yaml` — **modify**: add `release`/`workflow_dispatch` triggers; add `.github/actions/**` to path filters; replace the old `diagrams`/`bsr-push-draft`/`bsr-push-main` jobs with the four thin diagrams+push pairs (gated by `PUBLISH_ENABLED`); leave `sanity-checks` gated (record target scoping in a comment); add a `script-tests` job.

---

### Task 1: Generator — drop `xs`, emit `.svgz`

**Files:**
- Modify: `scripts/generate_protodot.sh:96-99`
- Test: `scripts/tests/test_generate_svgz.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `generate_protodot.sh` writes `gen/diagrams/<proto_file>.dot.svgz` per proto file and no `.svg`/`.xs.svg`; no dependency on `rsvg-convert`.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_generate_svgz.sh`:

```bash
#!/usr/bin/env bash
# Guards the generator's svgz behavior: no rsvg/xs, gzip to .svgz, drop .svg.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="${REPO_ROOT}/scripts/generate_protodot.sh"
fail=0
pass() { echo "✅ $1"; }
bad()  { echo "❌ $1"; fail=1; }

# --- Static assertions on the generator ---
grep -q 'gzip -c'        "$GEN" && pass "gzips to svgz"        || bad "gzips to svgz"
grep -q '\.svgz'         "$GEN" && pass "references .svgz"     || bad "references .svgz"
grep -q 'rsvg-convert'   "$GEN" && bad  "still has rsvg-convert" || pass "no rsvg-convert"
grep -q '\.xs\.svg'      "$GEN" && bad  "still has xs variant"   || pass "no xs variant"

# --- Behavioral: the transform the generator performs ---
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
printf '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>' > "$work/x.dot.svg"
orig="$(cat "$work/x.dot.svg")"
( cd "$work"; svg="x.dot.svg"; svgz="${svg%.svg}.svgz"; gzip -c "$svg" > "$svgz"; rm -f "$svg" )
[ -f "$work/x.dot.svgz" ]  && pass "svgz produced" || bad "svgz produced"
[ ! -f "$work/x.dot.svg" ] && pass "svg removed"   || bad "svg removed"
[ "$(gunzip -c "$work/x.dot.svgz")" = "$orig" ] && pass "svgz round-trips" || bad "svgz round-trips"
[ "$(head -c2 "$work/x.dot.svgz" | od -An -tx1 | tr -d ' ')" = "1f8b" ] && pass "gzip magic ok" || bad "gzip magic ok"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/tests/test_generate_svgz.sh && bash scripts/tests/test_generate_svgz.sh`
Expected: FAIL — "❌ still has rsvg-convert", "❌ still has xs variant" (the behavioral checks already pass).

- [ ] **Step 3: Edit the generator**

In `scripts/generate_protodot.sh`, replace the scaled-version block (lines ~96–99):

```bash
    # Create a scaled version of the diagram
    svg_filename="${GENERATED_DIR}/${PROTODOT_DIR}/${protofile}.dot.svg"
    xs_filename="${GENERATED_DIR}/${PROTODOT_DIR}/${protofile}.dot.xs.svg"
    rsvg-convert "${svg_filename}" -w 850 -f svg -o "${xs_filename}"
```

with:

```bash
    # Gzip the diagram to .svgz (smaller Pages footprint; browsers/BSR render it)
    # and drop the plain .svg so Pages only stores the compressed copy.
    svg_filename="${GENERATED_DIR}/${PROTODOT_DIR}/${protofile}.dot.svg"
    svgz_filename="${svg_filename%.svg}.svgz"
    gzip -c "${svg_filename}" > "${svgz_filename}"
    rm -f "${svg_filename}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test_generate_svgz.sh`
Expected: PASS — ends with `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate_protodot.sh scripts/tests/test_generate_svgz.sh
git commit -m "diagrams: drop oversized xs SVG, emit gzipped .svgz"
```

---

### Task 2: Diagram-link injection + verification (service-preferred `<details>` block)

**Files:**
- Modify: `scripts/insert_diagram_link.sh`
- Modify: `scripts/verify_diagram_links.sh`
- Test: `scripts/tests/test_diagram_links.sh`

**Interfaces:**
- Consumes: nothing (operates on `./proto/**.proto` in the checkout).
- Produces:
  - `insert_diagram_link.sh <name>` injects, before the anchor (`^service ` if present else first `^(message|enum) `), the block below. `<Anchor>` = anchor's `$2` sans `{`; `<URL>` = `https://…/<name>/<proto_file>.dot.svgz`.
  - `verify_diagram_links.sh <name>` exits 0 iff every anchored proto has exactly one `<summary>🗺️ Show Diagram</summary>` and its `<URL>` twice; exits 1 otherwise.

  Injected block:
  ```
  //
  // <details>
  // <summary>🗺️ Show Diagram</summary>
  //
  // [![<Anchor> Diagram](<URL>)](<URL>)
  //
  // _Click the image above holding CTRL to open the diagram in a new tab._
  // </details>
  //
  ```

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_diagram_links.sh`:

```bash
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
svc_url="${BASE}/${svc}.dot.svgz"
typ_url="${BASE}/${typ}.dot.svgz"

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
[ "$(grep -Fo "($svc_url)" "$svc" | wc -l)" -eq 2 ] && pass "svc: svgz url twice" || bad "svc: svgz url twice"

# Type file: summary once, alt = message name, url twice.
[ "$(grep -Fc '<summary>🗺️ Show Diagram</summary>' "$typ")" -eq 1 ] && pass "type: summary once" || bad "type: summary once"
grep -Fq '[![Bar Diagram]' "$typ" && pass "type: alt = message name" || bad "type: alt = message name"
[ "$(grep -Fo "($typ_url)" "$typ" | wc -l)" -eq 2 ] && pass "type: svgz url twice" || bad "type: svgz url twice"

# Verify passes on the injected tree.
"$VERIFY" "$NAME" >/dev/null 2>&1 && pass "verify passes on injected tree" || bad "verify passes on injected tree"

# Tamper one url; verify MUST fail.
sed -i 's/\.dot\.svgz/.dot.svg/' "$typ"
"$VERIFY" "$NAME" >/dev/null 2>&1 && bad "verify should fail on tampered tree" || pass "verify fails on tampered tree"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/tests/test_diagram_links.sh && bash scripts/tests/test_diagram_links.sh`
Expected: FAIL — the current script emits the old two-line `xs.svg`/`svg` block anchored on the first declaration, so "svc: summary once", "svc: anchored on the service", and the svgz checks fail.

- [ ] **Step 3: Rewrite `insert_diagram_link.sh`**

Replace the whole file with:

```bash
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
```

- [ ] **Step 4: Rewrite `verify_diagram_links.sh`**

Replace the whole file with:

```bash
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash scripts/tests/test_diagram_links.sh`
Expected: PASS — ends with `ALL PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/insert_diagram_link.sh scripts/verify_diagram_links.sh scripts/tests/test_diagram_links.sh
git commit -m "diagrams: collapsible service-anchored diagram block with .svgz links"
```

---

### Task 3: `generate-diagrams` composite action

**Files:**
- Create: `.github/actions/generate-diagrams/action.yml`

**Interfaces:**
- Consumes: `scripts/generate_protodot.sh` (Task 1); repo `assets/`.
- Produces: composite action with inputs `name` (gh-pages subdir) and `github_token`; publishes `gen/diagrams` + `assets` to `gh-pages/<name>/`.

- [ ] **Step 1: Create the action**

Create `.github/actions/generate-diagrams/action.yml`:

```yaml
name: "Generate and publish diagrams"
description: "Generate protodot diagrams and publish them to gh-pages/<name>."
inputs:
  name:
    description: "Publish name (the gh-pages subdirectory)."
    required: true
  github_token:
    description: "Token used to push to the gh-pages branch."
    required: true
runs:
  using: "composite"
  steps:
    - name: Setup Graphviz
      uses: ts-graphviz/setup-graphviz@v1
    - name: Generate diagrams
      shell: bash
      run: |
        wget https://github.com/seamia/protodot/raw/master/binaries/protodot-linux-amd64
        chmod +x protodot-linux-amd64
        mkdir -v -p gen/bin
        mv protodot-linux-amd64 gen/bin/protodot
        export PATH="${PWD}/gen/bin:${PATH}"
        bash scripts/generate_protodot.sh
        find gen/diagrams -type f -name "*.dot" -exec rm -f {} +
    - name: Stage diagrams and assets for Pages
      shell: bash
      run: |
        mkdir -p public
        cp -r gen/diagrams/. public/
        cp -r assets public/assets
    - name: Publish to gh-pages/<name>
      uses: peaceiris/actions-gh-pages@v4
      with:
        github_token: ${{ inputs.github_token }}
        publish_dir: ./public
        destination_dir: ${{ inputs.name }}
        keep_files: true
```

- [ ] **Step 2: Validate YAML + structure**

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/actions/generate-diagrams/action.yml')); assert d['runs']['using']=='composite'; print('composite ok')"
grep -q 'destination_dir: ${{ inputs.name }}' .github/actions/generate-diagrams/action.yml && echo "publishes to <name> ok"
grep -q 'bash scripts/generate_protodot.sh' .github/actions/generate-diagrams/action.yml && echo "runs generator ok"
! grep -q 'librsvg' .github/actions/generate-diagrams/action.yml && echo "no librsvg ok"
```
Expected: `composite ok`, `publishes to <name> ok`, `runs generator ok`, `no librsvg ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/actions/generate-diagrams/action.yml
git commit -m "ci: add generate-diagrams composite action"
```

---

### Task 4: `bsr-push` composite action

**Files:**
- Create: `.github/actions/bsr-push/action.yml`

**Interfaces:**
- Consumes: `scripts/buf-installer.sh`, `scripts/insert_diagram_link.sh`, `scripts/verify_diagram_links.sh` (Task 2); `buf.yaml` module name.
- Produces: composite action with inputs `name` (BSR label) and `buf_token`; runs `buf push proto --label "<name>"`.

- [ ] **Step 1: Create the action**

Create `.github/actions/bsr-push/action.yml`:

```yaml
name: "Push proto to buf.build"
description: "Inject diagram links then push proto to buf.build under a label."
inputs:
  name:
    description: "BSR label (and diagram-link subdirectory) to publish under."
    required: true
  buf_token:
    description: "buf.build API token."
    required: true
runs:
  using: "composite"
  steps:
    - name: Install buf
      shell: bash
      run: sudo ./scripts/buf-installer.sh
    - name: Inject and verify diagram links
      shell: bash
      run: |
        # Throwaway checkout; the injected links are NOT committed.
        scripts/insert_diagram_link.sh "${{ inputs.name }}"
        scripts/verify_diagram_links.sh "${{ inputs.name }}"
    - name: Push to buf.build
      shell: bash
      env:
        BUF_TOKEN: ${{ inputs.buf_token }}
      run: buf push proto --label "${{ inputs.name }}"
```

- [ ] **Step 2: Validate YAML + structure**

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/actions/bsr-push/action.yml')); assert d['runs']['using']=='composite'; print('composite ok')"
grep -q 'buf push proto --label "${{ inputs.name }}"' .github/actions/bsr-push/action.yml && echo "labeled push ok"
grep -q 'scripts/insert_diagram_link.sh "${{ inputs.name }}"' .github/actions/bsr-push/action.yml && echo "injects links ok"
grep -q 'BUF_TOKEN: ${{ inputs.buf_token }}' .github/actions/bsr-push/action.yml && echo "auth env ok"
```
Expected: `composite ok`, `labeled push ok`, `injects links ok`, `auth env ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/actions/bsr-push/action.yml
git commit -m "ci: add bsr-push composite action (labeled buf push)"
```

---

### Task 5: Rewire `ci.yaml` — triggers, gated publish pairs, retire old jobs

**Files:**
- Modify: `.github/workflows/ci.yaml`

**Interfaces:**
- Consumes: `.github/actions/generate-diagrams` (Task 3), `.github/actions/bsr-push` (Task 4); repo variable `PUBLISH_ENABLED`; secrets `GITHUB_TOKEN`, `BUF_BSR_TOKEN`.
- Produces: four diagrams+push job pairs (release/main/dev/preview) plus retained lint/format/check jobs.

- [ ] **Step 1: Update the `on:` block**

Replace the current `on:` block (lines 3–21) with:

```yaml
on:
  workflow_dispatch:
    inputs:
      use_branch_name:
        description: "Push to a BSR label named after the branch instead of 'draft'"
        type: boolean
        default: false
  release:
    types: [published]
  push:
    # Only run when there are changes under relevant dirs
    paths:
      - "proto/**"
      - ".github/workflows/**"
      - ".github/actions/**"
      - "scripts/**"
      - "buf.*"
    branches:
      - main
      - dev
  pull_request:
    # Only run when there are changes under relevant dirs
    paths:
      - "proto/**"
      - ".github/workflows/**"
      - ".github/actions/**"
      - "scripts/**"
      - "buf.*"
```

- [ ] **Step 2: Record the target scoping on `sanity-checks` (keep it gated)**

Do NOT un-gate `sanity-checks` (that would break the rebrand PR). Only update its comment. Replace:

```yaml
    # TODO(rebrand): re-enable post-merge once origin/main carries the ttm layout and the new BSR baseline exists.
    if: false
```

with:

```yaml
    # TODO(rebrand): re-enable post-merge (origin/main on ttm + BSR baseline exists).
    # When re-enabling, scope it to PRs + dev/main pushes (design §4.5):
    #   if: ${{ github.event_name == 'pull_request' || (github.event_name == 'push' && (github.ref == 'refs/heads/dev' || github.ref == 'refs/heads/main')) }}
    if: false
```

- [ ] **Step 3: Delete the old publish/diagram jobs**

Delete these three jobs entirely: `bsr-push-draft` (lines ~127–157), `bsr-push-main` (lines ~159–191), and `diagrams` (lines ~193–225). They are replaced in Step 4. (This removes the `librsvg2-bin` install and both `bufbuild/buf-push-action` usages.)

- [ ] **Step 4: Add the four gated diagrams+push pairs**

Append these jobs under `jobs:` (where the deleted jobs were):

```yaml
  # ---- Diagram + BSR publish pipeline ----
  # Gated by repo variable PUBLISH_ENABLED so the pipeline stays dormant until
  # GitHub Pages is enabled AND the BSR module buf.build/ttm/messenger-protocol
  # exists. Enable post-merge:  gh variable set PUBLISH_ENABLED --body true
  # Each push is ordered behind its diagrams job so injected .svgz links are live
  # before the label moves. Publish path depends on buf-lint only (not
  # sanity-checks): releases may be intentionally breaking.

  release-diagrams:
    runs-on: ubuntu-latest
    needs: [buf-lint]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'release' && startsWith(github.ref_name, 'release-') }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/generate-diagrams
        with:
          name: ${{ github.ref_name }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
  release-push:
    runs-on: ubuntu-latest
    needs: [buf-lint, release-diagrams]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'release' && startsWith(github.ref_name, 'release-') }}
    environment: release
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/bsr-push
        with:
          name: ${{ github.ref_name }}
          buf_token: ${{ secrets.BUF_BSR_TOKEN }}

  main-diagrams:
    runs-on: ubuntu-latest
    needs: [buf-lint]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'push' && github.ref == 'refs/heads/main' }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/generate-diagrams
        with:
          name: main
          github_token: ${{ secrets.GITHUB_TOKEN }}
  main-push:
    runs-on: ubuntu-latest
    needs: [buf-lint, main-diagrams]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'push' && github.ref == 'refs/heads/main' }}
    environment: main
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/bsr-push
        with:
          name: main
          buf_token: ${{ secrets.BUF_BSR_TOKEN }}

  dev-diagrams:
    runs-on: ubuntu-latest
    needs: [buf-lint]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'push' && github.ref == 'refs/heads/dev' }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/generate-diagrams
        with:
          name: dev
          github_token: ${{ secrets.GITHUB_TOKEN }}
  dev-push:
    runs-on: ubuntu-latest
    needs: [buf-lint, dev-diagrams]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'push' && github.ref == 'refs/heads/dev' }}
    environment: dev
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/bsr-push
        with:
          name: dev
          buf_token: ${{ secrets.BUF_BSR_TOKEN }}

  preview-diagrams:
    runs-on: ubuntu-latest
    needs: [buf-lint]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'workflow_dispatch' }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/generate-diagrams
        with:
          name: ${{ inputs.use_branch_name && github.ref_name || 'draft' }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
  preview-push:
    runs-on: ubuntu-latest
    needs: [buf-lint, preview-diagrams]
    if: ${{ vars.PUBLISH_ENABLED == 'true' && github.event_name == 'workflow_dispatch' }}
    environment: draft
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/bsr-push
        with:
          name: ${{ inputs.use_branch_name && github.ref_name || 'draft' }}
          buf_token: ${{ secrets.BUF_BSR_TOKEN }}
```

- [ ] **Step 5: Validate the workflow (YAML + structure)**

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/ci.yaml')); print('jobs:', sorted(d['jobs']))"
grep -q 'types: \[published\]' .github/workflows/ci.yaml && echo "release trigger ok"
grep -q 'use_branch_name' .github/workflows/ci.yaml && echo "dispatch input ok"
grep -c "PUBLISH_ENABLED == 'true'" .github/workflows/ci.yaml   # expect 8
grep -q 'bsr-push-draft' .github/workflows/ci.yaml && echo "OLD draft job still present (FIX)" || echo "old draft job removed ok"
grep -q 'librsvg2-bin' .github/workflows/ci.yaml && echo "librsvg still present (FIX)" || echo "librsvg removed ok"
grep -q 'buf-push-action' .github/workflows/ci.yaml && echo "old push action still present (FIX)" || echo "old push action removed ok"
```
Expected: `jobs:` lists `buf-lint, buf-format, diff-dev, sanity-checks, analyze-service-tags, fqpn-check, release-diagrams, release-push, main-diagrams, main-push, dev-diagrams, dev-push, preview-diagrams, preview-push` (and, after Task 6, `script-tests`); `release trigger ok`; `dispatch input ok`; count `8`; `old draft job removed ok`; `librsvg removed ok`; `old push action removed ok`.

- [ ] **Step 6: Confirm proto config still lints (unaffected)**

Run: `buf lint`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci: release/dev/main/preview publish pipeline via composite actions (gated by PUBLISH_ENABLED)"
```

---

### Task 6: Add `script-tests` CI job

**Files:**
- Modify: `.github/workflows/ci.yaml`

**Interfaces:**
- Consumes: `scripts/tests/test_generate_svgz.sh`, `scripts/tests/test_diagram_links.sh` (Tasks 1–2).
- Produces: a `script-tests` job running both bash tests on every trigger.

- [ ] **Step 1: Add the job**

Append under `jobs:`:

```yaml
  # Run the diagram-script unit tests (no buf/graphviz needed).
  script-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run diagram script tests
        run: |
          bash scripts/tests/test_generate_svgz.sh
          bash scripts/tests/test_diagram_links.sh
```

- [ ] **Step 2: Validate + run the tests locally**

Run:
```bash
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/ci.yaml')); assert 'script-tests' in d['jobs']; print('script-tests job ok')"
bash scripts/tests/test_generate_svgz.sh
bash scripts/tests/test_diagram_links.sh
```
Expected: `script-tests job ok`, then each test ends with `ALL PASS`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci: run diagram-script tests in CI"
```

---

## Rollout / enablement (post-merge, external)

This plan lands dormant. To go live (updates the go-live steps tracked in the rebrand memory; the old standalone `bsr-push-main` behavior is now `main-diagrams`+`main-push`):

1. Merge PR #1 (`rebranding → dev`), then `dev → main` (so `origin/main` carries the `ttm` layout).
2. Ensure the BSR module `buf.build/ttm/messenger-protocol` exists (create the empty repo on buf.build if needed — a non-draft push can't create it).
3. Enable GitHub Pages (source: `gh-pages` branch).
4. Flip the single switch: `gh variable set PUBLISH_ENABLED --body true`. The next push to `main`/`dev`, release publish, or manual dispatch then generates diagrams and pushes the matching label; the first `main` push seeds the baseline label.
5. **Verify the `.svgz`-inline-on-BSR path** (spec §6): open a symbol's rendered docs on buf.build and confirm the collapsed diagram image renders. If it does not, apply the fallback (serve plain `.svg` for the inline image; keep `.svgz` for the link) — a follow-up change to `generate_protodot.sh` + `insert_diagram_link.sh`.
6. Re-enable `sanity-checks` with the scoped `if:` recorded in its comment (separate rebrand-track step).

## Self-review notes

- **Spec coverage:** triggers (§4.2 → T5.1); publish-name model (§4.1 → T5.4 name exprs); composite actions (§4.3 → T3/T4); ordering (§4.4 → push `needs` its diagrams, T5.4); sanity-checks scoping + off publish path (§4.5 → T5.2 comment + publish jobs need only buf-lint); drop `xs`/`librsvg` + `.svgz` (§4.6 → T1, T3, T5.3); `<details>` service-anchored block (§4.7 → T2); risks/rollout (§6/§7 → Rollout section). Deviation from spec text: publish pipeline is gated by `PUBLISH_ENABLED` (not in the spec) so it lands dormant on `rebranding` without breaking the PR — a safety mechanism, flagged here.
- **Type/name consistency:** action inputs `name`/`github_token`/`buf_token` match between T3/T4 definitions and T5 call sites; the preview `name` expression is identical in `preview-diagrams` and `preview-push`; the injected block strings (`<summary>🗺️ Show Diagram</summary>`, `.dot.svgz`) match between `insert_diagram_link.sh` (T2.3), `verify_diagram_links.sh` (T2.4), and both tests.
- **No placeholders:** every code/step block is concrete.
