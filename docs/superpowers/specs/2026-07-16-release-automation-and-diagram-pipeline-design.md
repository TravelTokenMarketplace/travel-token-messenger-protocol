# Release automation & diagram pipeline — design

**Date:** 2026-07-16
**Status:** Approved (design); implementation plan pending
**Repo:** `TravelTokenMarketplace/travel-token-messenger-protocol`
**Related:** `docs/superpowers/specs/2026-07-15-ttm-rebrand-design.md` (rebrand), `2026-07-15-ttm-rebrand.md` (plan)

## 1. Summary

Two tightly-coupled changes to the protocol repo's CI, sharing the same diagram +
BSR-publish pipeline, delivered as one spec:

- **A. Release/label automation** — publishing a GitHub Release (`release-N`) pushes
  the protocol to buf.build under a matching `release-N` label, with diagrams
  generated for that tag. Generalizes the existing per-ref pipeline so every push
  target (release, `main`, `dev`, and a manual preview slot) flows through one
  parameterized path.
- **B. Diagram pipeline changes** — drop the oversized `xs` SVG variant, serve
  gzipped `.svgz` diagrams (Pages size), and render each diagram as a collapsible
  `<details>` block with a clickable linked image.

## 2. Current state

- CI (`.github/workflows/ci.yaml`) triggers on `push` (branches `main`, `dev`),
  `pull_request`, and `workflow_dispatch`, all path-filtered to `proto/**`,
  `.github/workflows/**`, `scripts/**`, `buf.*`.
- BSR module: `buf.build/ttm/messenger-protocol`.
- Push jobs today:
  - `bsr-push-draft` — `bufbuild/buf-push-action@v1` with `draft: true`, on
    `refs/heads/draft || refs/heads/dev`, `needs: [buf-lint, sanity-checks]`.
  - `bsr-push-main` — non-draft push on `refs/heads/main`, `needs: [buf-lint]`,
    `environment: main` (added 2026-07-15; seeds/advances the `main` baseline label).
- `diagrams` job (currently `if: false`, pending GitHub Pages) generates diagrams
  with protodot + graphviz, produces a resized `xs` SVG via `rsvg-convert`, and
  publishes to `gh-pages/${github.ref_name}/` (`keep_files: true`).
- Diagram links are injected at push time (never committed) by
  `scripts/insert_diagram_link.sh <name>` and validated by
  `scripts/verify_diagram_links.sh <name>`, both keyed on a name (currently the ref
  name). Links point at `https://traveltokenmarketplace.github.io/travel-token-messenger-protocol/<name>/...`.
- `generate_protodot.sh` renders `<proto>.dot.svg` per proto and an
  `<proto>.dot.xs.svg` resized copy (`rsvg-convert -w 850 -f svg`).

## 3. Goals / non-goals

**Goals**
- Automate BSR publish + diagrams for `release-N` GitHub Releases.
- One parameterized publish path for all targets (release / main / dev / preview).
- A manual preview slot for arbitrary feature branches.
- Cut Pages footprint: remove `xs`, serve `.svgz`.
- Cleaner in-doc diagram presentation (collapsible, clickable).

**Non-goals**
- Enabling GitHub Pages or creating the BSR module (external prerequisites; see §9).
- Changing the breaking-change policy beyond scoping which events run it.
- Re-rendering / restyling the diagrams themselves (protodot output unchanged).

## 4. Design

### 4.1 Publish-name model

Every target computes a single **publish name** that drives all three of {gh-pages
directory, injected-link path, BSR label}. All pushes become
`buf push proto --label "<name>"` — no `--draft` anywhere.

| mode | trigger | checkout ref | publish name = BSR label = `gh-pages/<name>/` |
|------|---------|--------------|-----------------------------------------------|
| **release** | `release: published`, guard `startsWith(ref_name,'release-')` | the tag | `release-N` (`github.ref_name`) |
| **main** | push to `main` | `main` | `main` |
| **dev** | push to `dev` | `dev` | `dev` |
| **preview** | manual `workflow_dispatch` | selected branch (`github.ref_name`) | `draft` by default, or the branch name if `use_branch_name` is checked |

Notes:
- `--label main` is equivalent to buf's default label, so `main` mode stays the
  rolling breaking baseline. `release-N` labels are **immutable, pinnable
  snapshots** — additive, never a baseline move.
- The `draft` git-*branch* auto-trigger is **removed**; `draft` is now a BSR *label*
  fed only by the manual preview. `dev`/`main` auto-triggers stay.

### 4.2 Triggers

Add to `on:`:

```yaml
on:
  release:
    types: [published]          # release-N automation (incl. pre-releases)
  workflow_dispatch:
    inputs:
      use_branch_name:
        description: "Push to a BSR label named after the branch instead of 'draft'"
        type: boolean
        default: false
  # existing push (main, dev) / pull_request retained
```

Preview name expression: `${{ inputs.use_branch_name && github.ref_name || 'draft' }}`.
The native "Run workflow" branch selector chooses the branch (and the workflow file
used); no free-text branch input. (Caveat: the selected branch must contain this
workflow file — acceptable for branches cut from `dev`/`main`.)

### 4.3 Composite actions

Shared logic is extracted into two composite actions so all four modes stay DRY and
cannot drift. This replaces the two `bufbuild/buf-push-action@v1` usages with direct
`buf` CLI calls (the CLI is the modern path and the only clean way to pass `--label`).

- **`.github/actions/generate-diagrams`** — input `name`. Installs graphviz +
  protodot, runs `generate_protodot.sh`, stages output, publishes to
  `gh-pages/<name>/` (`peaceiris/actions-gh-pages`, `keep_files: true`). No
  `librsvg2-bin`.
- **`.github/actions/bsr-push`** — inputs `name`, `buf_token`. Installs buf (custom
  `scripts/buf-installer.sh` — see the buf-tooling note in the rebrand spec; do NOT
  switch to `buf-setup-action`), runs `insert_diagram_link.sh "<name>"` then
  `verify_diagram_links.sh "<name>"` on the throwaway checkout, then
  `buf push proto --label "<name>"`.

`actions/checkout` and secret plumbing stay in the calling job (so the correct ref is
checked out and `buf_token` is passed explicitly). Each mode is then a thin
`*-diagrams` job + `*-push` job.

### 4.4 Job graph & ordering

For **every** mode, the push is ordered behind its diagrams job, so injected `.svgz`
URLs are live before the label moves (no window where a label references a 404):

```
buf-lint ──▶ <mode>-diagrams (publish gh-pages/<name>/) ──▶ <mode>-push (buf push --label <name>)
```

`<mode>-push: needs: [buf-lint, <mode>-diagrams]`. If diagram generation fails, the
label is not pushed (correct — no broken immutable snapshot for releases).

### 4.5 sanity-checks scoping & breaking baseline

- `sanity-checks` (dependency check, `diff_against_branch.sh`, `buf-breaking.sh`) is
  scoped to `pull_request` and pushes to `dev`/`main` — the integration points where
  breaking checks belong. It does **not** run on release events or manual dispatch.
- The publish path (`*-diagrams` and `*-push`) depends on `buf-lint` only, never
  `sanity-checks`. Rationale:
  - A release can be *intentionally* breaking (new major); gating it on
    breaking-vs-`main` would wrongly block it.
  - `dev` previews should publish even mid-development with a breaking change in
    flight. (This intentionally supersedes the rebrand-era "keep needs intact"
    gating, which existed only to keep the job inert during the rebrand PR.)
- `diagrams`' dependency on `sanity-checks` is dropped (diagram generation is
  orthogonal to breaking checks).

### 4.6 Diagram pipeline changes

**Drop `xs`.** Remove the resize block in `generate_protodot.sh` (lines ~96–99,
`rsvg-convert ... -w 850 -f svg`). `rsvg-convert` re-emits absolute point
coordinates instead of preserving the vector graph, making `xs` ~30× the original.
Remove the `librsvg2-bin` install (rsvg-convert has no other use — confirmed by grep:
only `verify_diagram_links.sh`, `generate_protodot.sh`, `insert_diagram_link.sh`,
and the `librsvg2-bin` step referenced the `xs`/rsvg path).

**Gzip → `.svgz`, publish only that.** After protodot emits `<proto>.dot.svg`,
`gzip -c` it to `<proto>.dot.svgz` and delete the `.svg`. Pages stores only the
compressed copy. SVG is text and compresses well; combined with removing `xs`, this
is a large Pages-size reduction.

### 4.7 Injected diagram markdown

**Placement (service-preferred).** Diagrams are generated **per proto file**
(`protodot` emits one `<proto_file>.dot.svgz` covering the whole file), so each file
gets exactly one link, anchored where BSR surfaces the file best:

- If the file contains a `service` declaration → anchor on the `service` (BSR renders
  services on top of the package; matches the maintainer's manual practice). Repo
  reality (2026-07-16): 63/239 files have a service, **0** have more than one, and the
  `service` is conventionally declared *after* its request/response messages — so the
  previous "first `enum|message|service`" rule mis-placed the link on the first
  request message. `grep -qE '^service ' <file>` selects this branch.
- Otherwise (service-less type file; 176/239) → anchor on the first `message`/`enum`.

Anchoring on **every** message was considered and rejected: the diagram is per-file,
so it would repeat the identical image under every symbol (noise, not information).

`insert_diagram_link.sh` inserts, before the chosen anchor declaration, a collapsible
block (all lines `//`-prefixed so the block stays a *leading* doc comment attached to
the symbol). `<Anchor>` is the anchor declaration's name (`$2`, stripped of a trailing
`{`) — the service name for service files, the first type name otherwise; `<URL>` is
`<base>/<proto_file>.dot.svgz`:

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

- Blank lines emitted as `//` (no trailing space).
- The `.svgz` URL appears twice (image `src` + link `href`).
- The hint wording is verbatim from the request; "holding CTRL" is macOS-inaccurate
  (⌘) — a wording-only tweak (e.g. "Ctrl/Cmd+click") deferred to the author.

`verify_diagram_links.sh` is rewritten to assert, per proto file: exactly one
`<summary>🗺️ Show Diagram</summary>` line, and the file's `<URL>` present (two
occurrences). It replaces the current one-`xs.svg` + one-`svg` count check.

## 5. File-by-file changes

- `.github/workflows/ci.yaml` — add `release`/`workflow_dispatch` inputs to `on:`;
  scope `sanity-checks`; drop `sanity-checks` from `diagrams`' needs; remove
  `librsvg2-bin`. Replace the current single `diagrams` job and the
  `bsr-push-draft`/`bsr-push-main` jobs with four thin `<mode>-diagrams` +
  `<mode>-push` pairs (release / main / dev / preview), each calling the composite
  actions. `bsr-push-draft` (draft-branch, `draft: true`) is retired in favor of the
  `dev` pair (auto) + `preview` pair (manual).
- `.github/actions/generate-diagrams/action.yml` — new composite action.
- `.github/actions/bsr-push/action.yml` — new composite action.
- `scripts/generate_protodot.sh` — remove `xs` block; add gzip→`.svgz`, delete `.svg`.
- `scripts/insert_diagram_link.sh` — emit the `<details>` block; anchor on the
  `service` if present else the first `message`/`enum` (service-preferred, §4.7); alt
  from the anchor's `$2`; URL → `.dot.svgz`.
- `scripts/verify_diagram_links.sh` — validate the new block shape / `.svgz` URL,
  one block per file at its service-preferred anchor.

## 6. Risks & must-verify

- **`.svgz` inline on BSR (highest risk).** Direct-open in a browser works natively;
  the untested path is `<img src="…​.svgz">` embedded in BSR's rendered docs, which
  needs GitHub Pages to serve `.svgz` with `Content-Encoding: gzip` *and* BSR to
  embed the Pages URL directly (not a proxy that strips the header). **Must verify on
  a real preview push.** Fallback if it fails: serve plain `.svg` for the inline
  image (still far smaller than today without `xs`) and/or reserve `.svgz` for the
  link target. Removing `xs` is the dominant size win regardless, so the design is
  safe either way.
- **`buf push --label` availability** in the pinned buf (`latest`) — confirm during
  implementation; unified `--label` removes the earlier `--draft` deprecation risk.
- **`workflow_dispatch` branch must contain this workflow file** — inherent to the
  native selector; documented for users.

## 7. Prerequisites / rollout ordering (unchanged track)

Release automation is fully functional only once (external, per the rebrand plan):
1. The BSR module `buf.build/ttm/messenger-protocol` exists.
2. GitHub Pages is enabled (source `gh-pages`), so the diagrams half serves.

This slots into the existing post-merge enablement track; nothing here forces earlier
enablement. Verify the `.svgz`-on-BSR path (§6) as soon as a preview push is possible.

## 8. Testing

- Lint/format: `buf lint`, `buf format` clean; `bash -n` the changed scripts.
- `insert_diagram_link.sh` + `verify_diagram_links.sh` round-trip on a throwaway
  proto tree (assert verify passes on injected output, fails on tampered input).
- `generate_protodot.sh` produces only `.svgz` (no `.svg`/`.xs.svg`) for a sample.
- End-to-end: a manual preview dispatch pushes `draft` (and, with the toggle, a
  branch-named label) with live diagram links; a `release-N` publish produces the
  `release-N` label after its diagrams. Confirm rendering on BSR (§6).

## 9. Open questions / deferred

- Final decision on the `.svgz`-inline fallback pending the BSR verification (§6).
- Hint wording ("holding CTRL" vs "Ctrl/Cmd+click") — author's call (§4.7).
- Accumulation of per-branch preview labels/dirs when `use_branch_name` is used —
  cleanup policy not in scope; revisit if it becomes noisy.
