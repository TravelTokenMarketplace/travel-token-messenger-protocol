# Travel Token Messenger Protocol Rebrand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand the protocol repo from "Camino Messenger" (`cmp.` protobuf namespace, GCP-hosted diagrams) to "Travel Token Messenger" (`ttm.` namespace, GitHub Pages diagrams), on a new GitHub repo, landing via PR `rebranding → dev`.

**Architecture:** Phased commits on a `rebranding` branch, each one `buf lint` + `buf format`-clean and passing the sanity scripts. Ordered core → tooling → diagram pipeline → prose. External-push CI jobs (buf.build BSR push, diagram publish) are gated off until the new BSR org + Pages site exist.

**Tech Stack:** Protocol Buffers, [buf](https://buf.build) (v2 config), bash/python tooling scripts, GitHub Actions, protodot + graphviz + rsvg (diagram generation), GitHub Pages.

## Global Constraints

- Protobuf/service namespace: **`ttm.`** replaces `cmp.` — must match on-chain registered names `ttm.services.<pkg>.<version>.<Name>` and `ttm.types.<version>.<Name>` exactly.
- Custom annotation: `@custom:cmp-service` → `@custom:ttm-service`.
- Brand prose: "Camino Messenger" → "Travel Token Messenger"; "Camino Messenger Protocol"/"CMP" → "Travel Token Messenger Protocol"; one-word `TravelTokenMessenger`.
- New repo: `TravelTokenMarketplace/travel-token-messenger-protocol`, **public**, default branch **`dev`**.
- buf.build BSR path is a **placeholder** `buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol` until the user provides the real org at push time. Do not enable the BSR push.
- `c4t` branch references → `main` (the branch does not exist on origin; string rename only).
- Each commit must keep `buf lint` and `buf format --diff --exit-code` clean.
- Every rebrand commit lands on the `rebranding` branch (never on `main`/`dev` directly).

---

### Task 1: Create the new repo and rewire remotes

**Files:** none (git/GitHub operations only).

**Interfaces:**
- Produces: a `rebranding` branch (off `dev`) on the new `origin` where all later tasks commit; `old` remote pointing at the archived repo.

- [ ] **Step 1: Create the new GitHub repo (public, matching the old one)**

Run from inside `travel-token-messenger-protocol/`:
```bash
gh repo create TravelTokenMarketplace/travel-token-messenger-protocol --public
```
Expected: `✓ Created repository TravelTokenMarketplace/travel-token-messenger-protocol on GitHub`.

- [ ] **Step 2: Rewire remotes, keeping the old repo as `old`**

```bash
git remote rename origin old
git remote add origin git@github.com:TravelTokenMarketplace/travel-token-messenger-protocol.git
```

- [ ] **Step 3: Push all history and tags to the new origin**

```bash
git push origin --all && git push origin --tags
```
Expected: `dev` and `main` branches plus tags appear on the new repo.

- [ ] **Step 4: Set the new repo default branch to `dev`**

```bash
gh repo edit TravelTokenMarketplace/travel-token-messenger-protocol --default-branch dev
```
Expected: no error.

- [ ] **Step 5: Create the working branch off `dev`**

```bash
git checkout dev && git checkout -b rebranding
```
Expected: `Switched to a new branch 'rebranding'`.

---

### Task 2: Commit the design spec and pause external-push CI jobs

Land the already-written spec on `rebranding` and gate off the two CI jobs that publish to external services, so nothing pushes to a not-yet-ready BSR org or diagram host.

**Files:**
- Add: `docs/superpowers/specs/2026-07-15-ttm-rebrand-design.md` (already written; commit it here)
- Add: `docs/superpowers/plans/2026-07-15-ttm-rebrand.md` (this plan)
- Modify: `.github/workflows/ci.yaml` (`bsr-push-draft` and `diagrams` jobs)

**Interfaces:**
- Produces: `bsr-push-draft` and `diagrams` jobs disabled via `if: false`, ready to re-enable later.

- [ ] **Step 1: Gate off the `bsr-push-draft` job**

In `.github/workflows/ci.yaml`, replace the `bsr-push-draft` job's condition:
```yaml
  bsr-push-draft:
    runs-on: ubuntu-latest
    needs: [buf-lint, sanity-checks]
    # TODO(rebrand): re-enable once the buf.build BSR org/repo exists.
    if: false
    environment: draft
```
(Removing the old `if: ${{ (github.ref == 'refs/heads/draft') || (github.ref == 'refs/heads/dev') }}`.)

- [ ] **Step 2: Gate off the `diagrams` job**

The `diagrams` job is fully replaced in Task 8; for now gate it off:
```yaml
  diagrams:
    runs-on: ubuntu-latest
    needs: [buf-lint, sanity-checks]
    # TODO(rebrand): replaced by GitHub Pages publish; re-enable when the Pages site exists.
    if: false
```

- [ ] **Step 3: Verify the workflow YAML still parses**

Run:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yaml')); print('ok')"
```
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-15-ttm-rebrand-design.md docs/superpowers/plans/2026-07-15-ttm-rebrand.md .github/workflows/ci.yaml
git commit -m "chore(rebrand): add rebrand spec+plan, pause BSR push and diagrams CI"
```

---

### Task 3: Rename the proto namespace `cmp` → `ttm`

Move the proto tree and rewrite every package declaration, import, cross-message reference, and custom service annotation. This is the core change the rest of the ecosystem keys off of.

**Files:**
- Rename: `proto/cmp/` → `proto/ttm/` (via `git mv`)
- Modify: every `proto/ttm/**/*.proto` (packages, imports, refs, `@custom:` tag)
- Modify: `scripts/analyze-service-tags.sh` (the 3 `@custom:cmp-service` regexes → `@custom:ttm-service`)

**Interfaces:**
- Produces: `ttm.services.*` / `ttm.types.*` packages; `proto/ttm/` layout that Tasks 4–8 reference.

- [ ] **Step 1: Move the proto directory (history follows)**

```bash
git mv proto/cmp proto/ttm
```
Expected: `proto/ttm/` now holds `services/` and `types/`.

- [ ] **Step 2: Rewrite package decls, imports, and message references**

Case-sensitive replace of `cmp.` → `ttm.` and `cmp/` → `ttm/` inside proto files only:
```bash
grep -rl -e 'cmp\.' -e 'cmp/' proto/ttm --include='*.proto' \
  | xargs sed -i -e 's/\bcmp\./ttm./g' -e 's#"cmp/#"ttm/#g'
```
This covers `package cmp.services.…;` → `package ttm.services.…;`, `import "cmp/types/…"` → `"ttm/types/…"`, and refs like `cmp.types.v1.RequestHeader` → `ttm.types.v1.RequestHeader`.

- [ ] **Step 3: Rename the custom service annotation in protos**

```bash
grep -rl '@custom:cmp-service' proto/ttm --include='*.proto' \
  | xargs sed -i 's/@custom:cmp-service/@custom:ttm-service/g'
```

- [ ] **Step 4: Update the annotation regexes in the analyzer script**

In `scripts/analyze-service-tags.sh`, replace all `@custom:cmp-service` with `@custom:ttm-service` (lines ~50, 51, 99, 126, 226, 236, 249):
```bash
sed -i 's/@custom:cmp-service/@custom:ttm-service/g' scripts/analyze-service-tags.sh
```

- [ ] **Step 5: Verify no `cmp` namespace tokens remain in protos**

```bash
grep -rn -e '\bcmp\.' -e '"cmp/' -e '@custom:cmp-service' proto/ttm && echo "LEFTOVERS" || echo "clean"
```
Expected: `clean`.

- [ ] **Step 6: Verify buf lint and format**

```bash
buf lint && buf format proto --diff --exit-code && echo "buf ok"
```
Expected: `buf ok` (no lint errors, no format diff). If `buf.yaml` lint `ignore_only` still lists `proto/cmp/services/notification/...` paths, update those to `proto/ttm/...` — this is done in Task 5, so a lint path warning here is acceptable and resolved there.

- [ ] **Step 7: Verify the analyzer and dependency graph still run**

```bash
scripts/analyze-service-tags.sh proto/ttm
scripts/dependency_checker.py --print-graph || true
```
Expected: analyzer reports services with **valid** `@custom:ttm-service` tags (dependency_checker fully passes after Task 4, which fixes its `cmp/` prefix — non-fatal here).

- [ ] **Step 8: Commit**

```bash
git add proto scripts/analyze-service-tags.sh
git commit -m "refactor(proto): rename cmp namespace to ttm (packages, imports, service tags)"
```

---

### Task 4: Update tooling scripts and dependency checker for the `ttm` path

Repoint the scripts that hardcode `proto/cmp`, the `cmp/` include prefix, and `cmp.` FQPN filtering.

**Files:**
- Modify: `scripts/generate_protodot.sh` (default `PROTO_DIR`)
- Modify: `scripts/fqpn_check.sh` (`cmp\.` grep filter)
- Modify: `scripts/dependency_checker.py` (`cmp/` include prefix, `cmp.types` comment/examples)
- Modify: `scripts/list_services.sh` (comment examples)

**Interfaces:**
- Consumes: `proto/ttm/` layout from Task 3.
- Produces: sanity scripts that pass against the `ttm` tree.

- [ ] **Step 1: Repoint the protodot default proto dir**

In `scripts/generate_protodot.sh`, change:
```bash
PROTO_DIR="${2:-proto/ttm}"
```

- [ ] **Step 2: Fix the FQPN filter**

In `scripts/fqpn_check.sh`, change `grep -v "cmp\."` to `grep -v "ttm\."`:
```bash
sed -i 's/grep -v "cmp\\\\."/grep -v "ttm\\\\."/' scripts/fqpn_check.sh
```
Verify the line now filters `ttm\.`:
```bash
grep -n 'ttm\\.' scripts/fqpn_check.sh
```
Expected: the FQPN grep line shows `grep -v "ttm\."`.

- [ ] **Step 3: Fix the dependency checker include prefix and examples**

In `scripts/dependency_checker.py`, replace the two `include.startswith("cmp/")` checks with `"ttm/"` and update the `cmp/types` / `cmp.types.v1` comment examples to `ttm`:
```bash
sed -i -e 's#startswith("cmp/")#startswith("ttm/")#g' \
       -e 's#cmp/types#ttm/types#g' \
       -e 's#cmp\.types#ttm.types#g' scripts/dependency_checker.py
```

- [ ] **Step 4: Fix the list_services comment examples**

In `scripts/list_services.sh`, update the `cmp/...` example comment lines to `ttm/...`:
```bash
sed -i 's#cmp/#ttm/#g' scripts/list_services.sh
```

- [ ] **Step 5: Verify the sanity scripts pass end-to-end**

```bash
scripts/dependency_checker.py --print-graph && echo "deps ok"
scripts/fqpn_check.sh && echo "fqpn ok"
scripts/list_services.sh | head
```
Expected: `deps ok`, `fqpn ok`, and `list_services.sh` prints `ttm/...` service paths with no `cmp` references.

- [ ] **Step 6: Commit**

```bash
git add scripts/generate_protodot.sh scripts/fqpn_check.sh scripts/dependency_checker.py scripts/list_services.sh
git commit -m "chore(scripts): repoint tooling from proto/cmp to proto/ttm"
```

---

### Task 5: Update buf config, breaking baseline, and `c4t` → `main`

Point buf's module name / go package prefix / breaking baseline at the placeholder BSR path, fix the lint ignore paths, and rename all `c4t` branch references to `main`.

**Files:**
- Modify: `buf.yaml` (module `name`, `lint.ignore_only` paths)
- Modify: `buf.gen.yaml` (`go_package_prefix` value)
- Modify: `scripts/buf-breaking.sh` (`AGAINST` default)
- Modify: `scripts/create_c4t_file_listing.sh` → rename to `scripts/create_baseline_file_listing.sh` (path prefix + `origin/c4t`)
- Modify: `.github/workflows/ci.yaml` (any `c4t` refs) and `scripts/analyze-service-tags.sh` callers if they reference the renamed script

**Interfaces:**
- Consumes: `proto/ttm/` layout.
- Produces: buf config referencing `buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol`; breaking baseline `main`.

- [ ] **Step 1: Update the buf module name and lint ignore paths**

In `buf.yaml`: set `modules[0].name` to `buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol`, and change the three `lint.ignore_only.RPC_REQUEST_STANDARD_NAME` paths from `proto/cmp/services/notification/...` to `proto/ttm/services/notification/...`:
```bash
sed -i -e 's#buf.build/chain4travel/camino-messenger-protocol#buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol#g' \
       -e 's#proto/cmp/#proto/ttm/#g' buf.yaml
```

- [ ] **Step 2: Update the go_package_prefix in buf.gen.yaml**

```bash
sed -i 's#buf.build/chain4travel/camino-messenger-protocol#buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol#g' buf.gen.yaml
```

- [ ] **Step 3: Update the breaking-check baseline default**

In `scripts/buf-breaking.sh`, change the `AGAINST` default:
```bash
sed -i 's#buf.build/chain4travel/camino-messenger-protocol#buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol#g' scripts/buf-breaking.sh
```

- [ ] **Step 4: Rename the baseline-listing script and fix its refs**

```bash
git mv scripts/create_c4t_file_listing.sh scripts/create_baseline_file_listing.sh
sed -i -e 's#origin/c4t#origin/main#g' -e 's#proto/cmp#proto/ttm#g' -e 's#\bcmp/#ttm/#g' scripts/create_baseline_file_listing.sh
```

- [ ] **Step 5: Replace remaining `c4t` references in CI**

In `.github/workflows/ci.yaml`, the `diagrams` job's `if:` lists `refs/heads/c4t`; since that job is already gated off (Task 2) and rebuilt in Task 8, replace `c4t` → `main` for consistency anywhere it appears:
```bash
sed -i 's#refs/heads/c4t#refs/heads/main#g; s#create_c4t_file_listing#create_baseline_file_listing#g' .github/workflows/ci.yaml
grep -rn 'c4t' .github scripts && echo "LEFTOVER c4t" || echo "no c4t"
```
Expected: `no c4t`.

- [ ] **Step 6: Verify buf still lints and the breaking baseline reference is consistent**

```bash
buf lint && echo "lint ok"
grep -rn 'camino-messenger-protocol\|chain4travel' buf.yaml buf.gen.yaml scripts/buf-breaking.sh && echo "LEFTOVER" || echo "clean"
```
Expected: `lint ok` and `clean` (only the `<NEW_BSR_ORG>` placeholder remains, which is intended).

- [ ] **Step 7: Commit**

```bash
git add buf.yaml buf.gen.yaml scripts/buf-breaking.sh scripts/create_baseline_file_listing.sh .github/workflows/ci.yaml
git commit -m "chore(buf): repoint module to new BSR placeholder, rename c4t baseline to main"
```

---

### Task 6: Strip committed diagram URLs from protos and rework the injector

Remove the hardcoded GCS diagram-link comment pairs from proto source (making it host-agnostic), and rewrite `insert_diagram_link.sh` into the single per-branch Pages injector used before the buf push.

**Files:**
- Modify: every `proto/ttm/**/*.proto` containing `docs-cmp-files` link comments (strip them)
- Rewrite: `scripts/insert_diagram_link.sh` (GCS committed-URL inserter → per-branch GitHub Pages injector)
- Delete: `scripts/replace_url.sh`

**Interfaces:**
- Consumes: `proto/ttm/` layout.
- Produces: `scripts/insert_diagram_link.sh <branch>` that injects Pages URLs into the working tree; consumed by the CI push job in Task 8.

- [ ] **Step 1: Strip the committed diagram-link comment pairs from protos**

Remove the two comment lines (`// ![Diagram](...docs-cmp-files...)` and `// [Open Message Diagram](...docs-cmp-files...)`):
```bash
grep -rl 'docs-cmp-files' proto/ttm --include='*.proto' \
  | xargs sed -i '/storage\.googleapis\.com\/docs-cmp-files\/diagrams/d'
```

- [ ] **Step 2: Verify no diagram GCS URLs remain in protos**

```bash
grep -rn 'docs-cmp-files' proto/ttm && echo "LEFTOVER" || echo "clean"
```
Expected: `clean`.

- [ ] **Step 3: Verify buf format is still clean (no dangling blank comment blocks)**

```bash
buf format proto --diff --exit-code && echo "format ok"
```
Expected: `format ok`. If a diff appears, run `buf format proto -w` and re-check.

- [ ] **Step 4: Rewrite the injector script**

Replace `scripts/insert_diagram_link.sh` with a per-branch GitHub Pages injector. It takes the branch name, and for each proto inserts the link pair pointing at `https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/<branch>/<protopath>.dot[.xs].svg`:
```bash
#!/bin/bash
# Injects per-branch GitHub Pages diagram links into proto files.
# Run on a throwaway checkout right before `buf push` — do NOT commit the result.
set -euo pipefail

branch="${1:?Usage: insert_diagram_link.sh <branch>}"
base="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/${branch}"
directory="proto"

find "$directory" -type f -name "*.proto" | while read -r proto_file; do
    awk -v base="$base" -v path="$proto_file" '
    !inserted && /^enum|^message/ {
        print "// ![Diagram](" base "/" path ".dot.xs.svg)"
        print "// [Open Message Diagram](" base "/" path ".dot.svg)"
        inserted=1
    }
    { print }
    ' "$proto_file" > temp_file && mv temp_file "$proto_file"
done
```

- [ ] **Step 5: Smoke-test the injector on a throwaway copy**

```bash
tmp=$(mktemp -d); cp -r proto "$tmp/"; ( cd "$tmp" && bash "$OLDPWD/scripts/insert_diagram_link.sh" dev )
grep -rm1 'github.io/travel-token-messenger-protocol/dev' "$tmp/proto" && echo "inject ok"
rm -rf "$tmp"
```
Expected: `inject ok` and the URL contains `proto/ttm/...dot.xs.svg`.

- [ ] **Step 6: Delete the obsolete replace_url script**

```bash
git rm scripts/replace_url.sh
```

- [ ] **Step 7: Commit**

```bash
git add proto scripts/insert_diagram_link.sh
git commit -m "refactor(diagrams): strip GCS URLs from protos, inject GitHub Pages links pre-push"
```

---

### Task 7: Repoint the diagram-link verifier

Move link verification off the committed-URL / GCS model. Repoint `verify_diagram_links.sh` at the Pages base and remove it from the pre-push sanity gates (there are no committed URLs to verify before publish).

**Files:**
- Modify: `scripts/verify_diagram_links.sh` (`BASEURL`)
- Modify: `scripts/pre_commit_checks.sh` (remove the `verify_diagram_links.sh` call)
- Modify: `.github/workflows/ci.yaml` (remove `Verify diagrams` step from `sanity-checks`)

**Interfaces:**
- Produces: a verifier that checks the published Pages set (used post-publish in Task 8's workflow).

- [ ] **Step 1: Repoint the verifier base URL**

In `scripts/verify_diagram_links.sh`, change:
```bash
BASEURL="https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/"
```

- [ ] **Step 2: Remove the verifier from pre-commit checks**

In `scripts/pre_commit_checks.sh`, delete the `scripts/verify_diagram_links.sh` line:
```bash
sed -i '\#scripts/verify_diagram_links.sh#d' scripts/pre_commit_checks.sh
```

- [ ] **Step 3: Remove the `Verify diagrams` step from the sanity-checks CI job**

In `.github/workflows/ci.yaml`, delete the two lines of the `sanity-checks` job step:
```yaml
      - name: Verify diagrams
        run: scripts/verify_diagram_links.sh
```

- [ ] **Step 4: Verify YAML parses and no committed-URL verification remains in gates**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yaml')); print('ok')"
grep -n 'verify_diagram_links' scripts/pre_commit_checks.sh && echo "LEFTOVER" || echo "clean"
```
Expected: `ok` and `clean`.

- [ ] **Step 5: Commit**

```bash
git add scripts/verify_diagram_links.sh scripts/pre_commit_checks.sh .github/workflows/ci.yaml
git commit -m "chore(diagrams): repoint verifier to Pages, drop pre-push link verification"
```

---

### Task 8: Rebuild the diagram CI job to publish to GitHub Pages

Replace the GCS `diagrams` job with one that generates diagrams and publishes them (plus `assets/`) into a `gh-pages` branch under `/<branch>/`, then runs the injector + verifier. Keep it gated off until the Pages site is provisioned.

**Files:**
- Modify: `.github/workflows/ci.yaml` (`diagrams` job body)

**Interfaces:**
- Consumes: `scripts/generate_protodot.sh` (Task 4), `scripts/insert_diagram_link.sh` (Task 6), `scripts/verify_diagram_links.sh` (Task 7).

- [ ] **Step 1: Replace the `diagrams` job body with a Pages publish**

In `.github/workflows/ci.yaml`, replace the whole `diagrams` job with (keeping it gated off):
```yaml
  diagrams:
    runs-on: ubuntu-latest
    needs: [buf-lint, sanity-checks]
    # TODO(rebrand): re-enable once GitHub Pages is enabled (source: gh-pages branch).
    if: false
    steps:
      - name: Checkout the repo
        uses: actions/checkout@v4
      - name: Setup Graphviz
        uses: ts-graphviz/setup-graphviz@v1
      - name: Install librsvg2-bin
        run: sudo apt-get install -y librsvg2-bin
      - name: Generate Diagrams
        run: |
          wget https://github.com/seamia/protodot/raw/master/binaries/protodot-linux-amd64
          chmod +x protodot-linux-amd64
          mkdir -v -p gen/bin
          mv protodot-linux-amd64 gen/bin/protodot
          export PATH=${PWD}/gen/bin:${PATH}
          bash scripts/generate_protodot.sh
          find gen/diagrams -type f -name "*.dot" -exec rm -f {} +
      - name: Stage diagrams and assets for Pages
        run: |
          mkdir -p public
          cp -r gen/diagrams/. public/
          cp -r assets public/assets
      - name: Publish to gh-pages/<branch>
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./public
          destination_dir: ${{ github.ref_name }}
          keep_files: true
      - name: Verify published diagram links
        run: scripts/verify_diagram_links.sh
```

- [ ] **Step 2: Verify the workflow YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yaml')); print('ok')"
```
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci(diagrams): publish per-branch diagrams to GitHub Pages (gated off)"
```

---

### Task 9: Rebrand prose — README, buf.md, cancellation links, proto comments

Rewrite the human-facing text: drop Camino Network badges/links, repoint to the new brand/org, fix the `[Camino Docs]` links, sweep remaining "Camino" prose in proto comments, and delete `DATA_PROTECTION.md`.

**Files:**
- Modify: `README.md`
- Modify: `proto/buf.md`
- Modify: `proto/ttm/services/cancellation/{v1,v2,v3}/services.proto` (`[Camino Docs]` links)
- Modify: proto comment prose across `proto/ttm/**/*.proto` (~36 "Camino" lines)
- Delete: `DATA_PROTECTION.md`

**Interfaces:** none downstream.

- [ ] **Step 1: Rewrite README.md**

Replace title, intro, badges, and links. New `README.md`:
```markdown
# Travel Token Messenger Protocol

[![BUF BUILD](https://img.shields.io/badge/BUF-BUILD-72a1ed?style=for-the-badge&logoColor=white&labelColor=0C65EC)](https://buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol/)

---

> 🚧 **EARLY DAYS NOTICE** 🚧:
> ⚠️ Although we released our first productive Message Types version, it is still early days and partners make substantial and frequent contributions to the Travel Token Message Types. Please be aware that the Travel Token Messenger Protocol is still undergoing active development. The code, guidelines, and instructions may be subject to change.

---

The Travel Token Messenger Protocol is created together with Partners from each vertical (flights, hotels, holiday homes, transfers, car rental, cruise, …). The objective is to create a message standard for the Travel Token Messenger that is simple, efficient, complete, robust, and easy to integrate by all partners. The Travel Token Messenger Protocol is open source — free to be used anywhere, but of course targeted to be used with the Travel Token Messenger.

Please do not hesitate to communicate your observations on this documentation — uncertainties, mistakes, or missing explanations — so that we can continuously improve it.

## License

The Travel Token Messenger Protocol is licensed under the terms of the [GNU Lesser General Public License v3](LICENSE.md).
```
(The Discord/docs links and the DATA_PROTECTION link are intentionally removed — no live Travel Token equivalents yet.)

- [ ] **Step 2: Rewrite proto/buf.md**

New `proto/buf.md`:
```markdown
# Travel Token Messenger Protocol

---

> 🚧 **ALPHA CODE NOTICE** 🚧:
> ⚠️ This protocol definition is in the alpha phase of development. During this stage, breaking changes may occur without advance notice. Users should proceed with caution.

---

[![GITHUB](https://img.shields.io/badge/GITHUB-black?style=for-the-badge&logo=github&logoColor=white)](https://github.com/TravelTokenMarketplace/travel-token-messenger-protocol/)

The Travel Token Messenger Protocol is created together with Partners from each vertical (flights, hotels, holiday homes, transfers, car rental, cruise, …). The objective is to create a message standard for the Travel Token Messenger that is simple, efficient, complete, robust, and easy to integrate by all partners. The Travel Token Messenger Protocol is open source — free to be used anywhere, but of course targeted to be used with the Travel Token Messenger.

Please do not hesitate to communicate your observations on this documentation so that we can continuously improve it.
```

- [ ] **Step 3: Fix the `[Camino Docs]` links in the cancellation protos**

These currently point at `https://docs.camino.network/camino-messenger/cancellation`. Since there is no Travel Token docs site yet, drop the external link but keep the sentence:
```bash
for v in v1 v2 v3; do
  sed -i 's#There is a detailed explanation on \[Camino Docs\](https://docs.camino.network/camino-messenger/cancellation)#See the service documentation for a detailed explanation#' \
    proto/ttm/services/cancellation/$v/services.proto
done
```

- [ ] **Step 4: Sweep remaining "Camino" prose in proto comments**

Replace brand prose in proto comment lines (comments only — verified by the format check afterward):
```bash
grep -rl -i 'camino' proto/ttm --include='*.proto' | xargs sed -i \
  -e 's/Camino Messenger Protocol/Travel Token Messenger Protocol/g' \
  -e 's/Camino Messenger/Travel Token Messenger/g' \
  -e 's/Camino Network/Travel Token Messenger/g' \
  -e 's/\bCMP\b/Travel Token Messenger Protocol/g' \
  -e 's/\bCamino\b/Travel Token Messenger/g'
```

- [ ] **Step 5: Delete DATA_PROTECTION.md**

```bash
git rm DATA_PROTECTION.md
```
(The README no longer links to it after Step 1.)

- [ ] **Step 6: Verify buf format + no Camino prose remains**

```bash
buf format proto --diff --exit-code && echo "format ok"
grep -rn -i 'camino' proto README.md proto/buf.md && echo "LEFTOVER" || echo "clean"
```
Expected: `format ok` and `clean`. If format shows a diff, run `buf format proto -w`.

- [ ] **Step 7: Commit**

```bash
git add README.md proto DATA_PROTECTION.md
git commit -m "docs(rebrand): rewrite README/buf.md, sweep Camino prose, delete DATA_PROTECTION"
```

---

### Task 10: Final verification sweep and PR

Full repo-wide check, then open the rebranding PR against `dev` on the new repo.

**Files:** none (verification + PR).

- [ ] **Step 1: Repo-wide Camino/cmp sweep**

```bash
grep -ri camino --exclude-dir=.git --exclude-dir=gen . ; echo "---"; grep -rn -e '\bcmp\.' -e '"cmp/' proto
```
Expected: the only `camino` hits are inside `docs/superpowers/specs/` (this design doc + any historical records); `proto` grep returns nothing. Any other hit must be fixed before proceeding.

- [ ] **Step 2: Run the full local sanity suite**

```bash
buf lint && buf format proto --diff --exit-code \
  && scripts/dependency_checker.py --print-graph \
  && scripts/analyze-service-tags.sh proto \
  && scripts/fqpn_check.sh \
  && echo "ALL SANITY OK"
```
Expected: `ALL SANITY OK`.

- [ ] **Step 3: Diagram generation smoke test**

```bash
command -v protodot >/dev/null && scripts/generate_protodot.sh gen proto/ttm diagrams >/dev/null 2>&1 && echo "diagrams gen ok" || echo "SKIP (protodot not installed locally)"
```
Expected: `diagrams gen ok`, or `SKIP` if protodot isn't installed locally (CI covers it).

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin rebranding
gh pr create --repo TravelTokenMarketplace/travel-token-messenger-protocol \
  --base dev --head rebranding \
  --title "Rebrand: Camino Messenger → Travel Token Messenger" \
  --body "Rebrands the protocol repo to Travel Token Messenger: cmp→ttm protobuf namespace, GCS→GitHub Pages diagrams (CI-injected links), c4t→main baseline, prose/branding. buf.build BSR push and diagram publish jobs are gated off pending the new BSR org and Pages site (see docs/superpowers/specs/2026-07-15-ttm-rebrand-design.md §7)."
```
Expected: PR URL printed.

- [ ] **Step 5: Update the REBRANDING status table**

In the workspace-parent `REBRANDING.md` (NOT committed to any repo), set the `protocol` row to `✅ done (PR #N open)` with the PR URL and today's date.

---

## Deferred (post-merge, tracked in TODOS.md — needs user/infra)

- **buf.build BSR org/repo:** user provides the real org; replace `<NEW_BSR_ORG>` in `buf.yaml`, `buf.gen.yaml`, `scripts/buf-breaking.sh`, `README.md`; re-enable the `bsr-push-draft` job (`if:` back to the branch condition).
- **GitHub Pages:** enable Pages on the new repo (source: `gh-pages` branch), let the `diagrams` job run once to seed it, then re-enable the job (`if:` back to the branch condition) and confirm buf.build docs render the injected Pages links.
