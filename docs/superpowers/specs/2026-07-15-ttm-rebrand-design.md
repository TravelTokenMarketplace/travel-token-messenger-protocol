# Rebrand: Camino Messenger → Travel Token Messenger (protocol repo)

**Date:** 2026-07-15
**Status:** Approved
**Scope:** This repository (`travel-token-messenger-protocol`) only. The
contracts repo is already rebranded (2026-07-14); bot and matrix-app-service
follow separately.

## Context

The ecosystem is rebranding "Camino Messenger" → "Travel Token Messenger".
This repo owns the protobuf **`ttm.` namespace** (`cmp.` today) that the
contracts' `ServiceRegistry` and the bot both key off of — the package names
here must match the on-chain registered service names exactly
(`ttm.services.<pkg>.<version>.<Name>`). The contracts repo already registers
the `ttm.` names, so this rename closes that loop.

Naming decisions are fixed by the ecosystem-wide REBRANDING playbook and the
finished contracts rebrand; they are not re-litigated here:

- Brand: **"Travel Token Messenger"**; one-word `TravelTokenMessenger`.
- Protobuf/service namespace: **`ttm.`** replaces `cmp.` (`cmp.services.*`,
  `cmp.types.*` → `ttm.*`).
- Custom service annotation: `@custom:cmp-service` → `@custom:ttm-service`.
- Repo: `travel-token-messenger-protocol` under `TravelTokenMarketplace`.
- Full git history pushed to a new repo; old repo becomes an archive.
- Execution: **phased commits, each one lint/format-clean and passing the
  sanity checks.**

Brainstorming decisions specific to this repo:

- **Delete `DATA_PROTECTION.md`** — it names legal entities (Chain4Travel AG,
  Camino Network Foundation) we won't reword or re-attribute; the finished
  contracts repo carries no such file. Drop the README link to it.
- **`c4t` → `main`** — the `c4t` (chain4travel) branch does not exist on
  origin (only `main` + `dev`); this is purely a string rename of the `c4t`
  breaking-change baseline references in CI/scripts to `main`.
- **New repo default branch: `dev`**; rebrand lands via PR `rebranding → dev`.
- **Diagram hosting moves off GCP to GitHub Pages** with **CI-injected,
  clean-source** links (see §5). The repo is public, so Pages is free.
- **Workflows that push to external services stay paused** (buf.build BSR
  push, diagram publish) until the new BSR org and the Pages site are ready.
  The new buf.build org/repo path is a **placeholder** until then — the user
  provides it at push time.

## 1. Rename map

Namespace / identifier renames (case-aware; ~239 `cmp` occurrences under
`proto/`, plus scripts and config):

| Old | New |
|---|---|
| `proto/cmp/` (directory) | `proto/ttm/` (via `git mv`) |
| `package cmp.services.<x>.<v>;` / `package cmp.types.<v>;` | `package ttm.services.<x>.<v>;` / `package ttm.types.<v>;` |
| `import "cmp/types/<v>/<f>.proto";` | `import "ttm/types/<v>/<f>.proto";` |
| Message refs `cmp.types.v1.RequestHeader`, `cmp.types.*`, `cmp.services.*` | `ttm.types.*`, `ttm.services.*` |
| `@custom:cmp-service` (proto annotations **and** the 3 regexes in `analyze-service-tags.sh`) | `@custom:ttm-service` |
| `buf.build/chain4travel/camino-messenger-protocol` (buf.yaml module name, buf.gen.yaml `go_package_prefix`, `buf-breaking.sh` baseline) | `buf.build/<NEW_BSR_ORG>/travel-token-messenger-protocol` — **placeholder, TODO** |
| `c4t` (branch refs in `ci.yaml`, `buf-breaking.sh`, `create_c4t_file_listing.sh`) | `main` |
| "Camino Messenger Protocol" / "CMP" (prose) | "Travel Token Messenger Protocol" |
| "Camino Messenger" / "Camino Network" (prose in ~36 proto comment lines, README, buf.md) | "Travel Token Messenger" / generic |
| `chain4travel` GitHub links | `TravelTokenMarketplace` |

Script path/pattern updates:

- `generate_protodot.sh`: default `PROTO_DIR` `proto/cmp` → `proto/ttm`.
- `fqpn_check.sh`: `grep -v "cmp\."` → `ttm\.`.
- `dependency_checker.py`: `cmp/` include prefix and `cmp.types` examples → `ttm`.
- `list_services.sh`: comment examples `cmp/...` → `ttm/...`.
- `create_c4t_file_listing.sh`: `proto/cmp` → `proto/ttm`; `origin/c4t` → `origin/main`; rename script → `create_baseline_file_listing.sh`.

Deletions:

- `DATA_PROTECTION.md` and its README reference.

Left untouched:

- Dated design docs under `docs/superpowers/specs/` (historical records).
- `LICENSE.md` (already relicensed to LGPL v3; contains no Camino strings).
- Git history (pushed as-is).

## 2. Repo & remote setup (before any rebrand commits)

1. `gh repo create TravelTokenMarketplace/travel-token-messenger-protocol --public`.
2. `git remote rename origin old`;
   `git remote add origin git@github.com:TravelTokenMarketplace/travel-token-messenger-protocol.git`.
3. `git push origin --all && git push origin --tags`. Set the new repo's
   default branch to **`dev`** on GitHub. `old` stays as archive/reference.
4. Work on branch `rebranding` (off `dev`).

## 3. Pause external-push workflows (first rebrand commit)

Before other changes, neutralize the CI jobs that talk to external services
so nothing publishes to a not-yet-ready BSR org or diagram host:

- `bsr-push-draft` job (pushes to buf.build) — gate off (add
  `if: false` with a `# TODO: re-enable when BSR org ready` note, keeping the
  YAML intact for easy re-enable).
- `diagrams` job — replaced wholesale in §5; the new Pages job also starts
  gated off until the site is provisioned.

Lint/format jobs (`buf-lint`, `buf-format`, `analyze-service-tags`,
`fqpn-check`) stay active. The `diff-dev` job is informational (`|| true`)
and stays.

`sanity-checks` is **also gated off** (decided 2026-07-15): its steps
(`dependency_checker.py`, `diff_against_branch.sh`, `buf-breaking.sh`)
compare the branch against a released baseline (`origin/main` /
`buf.build/.../main`). A full `cmp`→`ttm` namespace move makes every symbol
"break" relative to that baseline, and the new baseline only exists after
this rebrand merges (and the new BSR org exists). Re-enabled post-merge.

## 4. Phased commits on `rebranding`

Ordered by dependency; each commit is `buf lint` + `buf format
--diff --exit-code` clean and passes the sanity scripts.

1. **Pause workflows** (§3).
2. **Proto namespace** — `git mv proto/cmp proto/ttm`; rewrite package
   decls, imports, cross-message references, and `@custom:cmp-service` →
   `@custom:ttm-service` across all `.proto`. Update
   `analyze-service-tags.sh` regexes to the new tag. Verify: `buf lint`,
   `buf format --diff --exit-code`, `scripts/dependency_checker.py
   --print-graph`, `scripts/analyze-service-tags.sh proto`,
   `scripts/fqpn_check.sh`.
3. **Scripts & buf config** — `buf.yaml` module name + `buf.gen.yaml`
   `go_package_prefix` + `buf-breaking.sh` baseline to the placeholder BSR
   path; `c4t` → `main` refs; script path/pattern updates from §1;
   `allowed_existing_folders.txt` / `missing_files.txt` path prefixes
   (`cmp/...` → `ttm/...`) if present.
4. **Diagram pipeline** (§5) — strip committed diagram URLs from protos,
   rework the CI job for GitHub Pages, repurpose the injector, delete
   `replace_url.sh`, adapt `verify_diagram_links.sh`.
5. **Prose & docs** — rewrite `README.md` and `proto/buf.md` (drop Camino
   Network badge, repoint camino.network / docs.camino.network / discord /
   `chain4travel` GitHub links to the new equivalents or remove), fix the
   `[Camino Docs]` links in the 3 `cancellation/*/services.proto`, sweep the
   ~36 "Camino" prose lines in proto comments, delete `DATA_PROTECTION.md`
   and its README link.

## 5. Diagram hosting: GitHub Pages + CI-injected links

**Goal:** remove the GCP (`gs://docs-cmp-files`) dependency, keep per-branch
versioned diagrams surfaced in buf.build's rendered docs, and stop committing
brittle host URLs into proto source.

**Host — GitHub Pages (`gh-pages` branch), per-branch subdirectories:**

- A workflow (on push to `main` / `dev` / draft branches, gated off until the
  site exists) generates diagrams via `generate_protodot.sh`, then publishes
  `gen/diagrams` **and** `assets/` into `gh-pages/<ref_name>/...`
  (`keep_files: true` so other branches' trees survive).
- Base URL becomes
  `https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/<branch>/proto/ttm/.../<file>.proto.dot.svg`
  (and `.dot.xs.svg`), assets under `.../<branch>/assets/...`.

**Links — CI-injected, clean source:**

- **Remove** the committed `// ![Diagram](...)` / `// [Open Message
  Diagram](...)` comment pairs from all protos; proto source becomes
  host-agnostic.
- Repurpose `insert_diagram_link.sh` into the single **injector**: run on a
  throwaway checkout in the BSR-push job (after diagrams publish, before `buf
  push`), computing the full per-branch Pages URL per file and inserting the
  comment pair. This replaces both the old committed-URL scheme and
  `replace_url.sh` (**deleted**).
- `verify_diagram_links.sh` — repoint `BASEURL` to Pages and move it to run
  **after** publish (against the injected/published set), or drop it from
  `sanity-checks` / `pre_commit_checks.sh` since there are no committed URLs
  to verify pre-push. Chosen: repoint + run post-publish in the diagram
  workflow; remove from `sanity-checks` and `pre_commit_checks.sh`.

This whole pipeline is wired but **gated off** until the Pages site is
provisioned and the BSR org exists.

## 6. Verification & landing

- `buf lint` + `buf format --diff --exit-code`.
- `scripts/dependency_checker.py --print-graph`,
  `scripts/analyze-service-tags.sh proto`, `scripts/fqpn_check.sh`,
  `scripts/list_services.sh` (spot-check output).
- Local diagram generation smoke test: `scripts/generate_protodot.sh gen
  proto/ttm diagrams` builds without path errors.
- Final sweep: `grep -ri camino --exclude-dir=.git .` — expected hits only in
  `docs/superpowers/specs/` (this doc + historical records) and nowhere else;
  `grep -rn "cmp\b\|cmp\." proto` returns nothing.
- PR `rebranding → dev` on the new repo. Update the REBRANDING.md status
  table.

## 7. Deferred (needs user / infra, tracked in TODOS.md)

- **buf.build BSR org/repo** — real path replaces the placeholder; re-enable
  `bsr-push-draft`. User provides at push time.
- **GitHub Pages site** — enable Pages on the new repo (source: `gh-pages`),
  first publish, then re-enable the diagram workflow.
- **`sanity-checks` CI job** — re-enable once `origin/main` carries the `ttm`
  layout (post-merge) and the new BSR `main` baseline exists.
- Post-migration: confirm buf.build docs render the injected Pages diagram
  links.

## 8. Out of scope

- Bot and matrix-app-service rebrands (separate projects).
- Any change to protobuf message *semantics* — this is a rename/rehost only.
