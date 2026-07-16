# Diagram hosting: `.svgz` → SVGO-optimized `.svg`

**Date:** 2026-07-17
**Status:** Design — approved approach, pending spec review
**Supersedes:** the `.svgz` decision in
`2026-07-16-release-automation-and-diagram-pipeline-design.md` §5 (gzip→`.svgz`)
and enacts that spec's §6 fallback ("serve plain `.svg` for the inline image").

## Problem

Diagrams are published to GitHub Pages and embedded into BSR docs as
`<img src="…/<label>/proto/<file>.dot.svgz">` (injected into each proto's leading
comment by `insert_diagram_link.sh`). On the first real publish (the `dev` canary,
2026-07-16) the images render as broken/binary in the browser.

### Root cause (verified against live Pages)

`curl` against a published `.svgz` on Pages:

- **No `Accept-Encoding`:** body is raw gzip (`1f 8b …`), `content-type:
  image/svg+xml`, **no** `content-encoding`. A client that doesn't advertise gzip
  receives gzip bytes labelled as SVG → cannot render.
- **`Accept-Encoding: gzip`** (what browsers send): `content-encoding: gzip`,
  `content-type: image/svg+xml`. Fastly gzips the response — but the body is
  *already* a `.svgz` (gzip). The browser strips the transport gzip and is left
  holding the file's own gzip bytes, still labelled SVG → cannot render.

Either way the browser ends up with gzip bytes it won't decode as an image. This
is **double compression**, and GitHub Pages exposes no way to set response headers
to fix it. `.svgz` on Pages is a dead end.

### Key insight

The `Accept-Encoding: gzip` probe shows Fastly **already applies `content-encoding:
gzip` on the wire** for `image/svg+xml`. So a **plain `.svg`** is:

- served with `content-type: image/svg+xml` + transport `content-encoding: gzip`;
- decoded once by the browser → plain SVG → **renders**;
- transferred at ≈ the same size the `.svgz` was, because Fastly performs the
  identical gzip — just at the transport layer where the browser knows to undo it.

The manual `.svgz` step was therefore not only broken but **redundant** for wire
size. Its only real benefit was a smaller *stored* file in the throwaway `gh-pages`
branch — which SVGO recovers.

## Approach

Serve plain, SVGO-optimized `.svg`. Rejected alternatives:

- **Raster (PNG/WebP):** sacrifices vector zoom/crispness on large graph diagrams
  for no wire-size gain over gzipped SVG. No.
- **Custom hosting with correct headers:** infra overhead to solve a problem Pages
  already solves transparently on the wire. No.

SVGO is for **stored branch size + stripping protodot/graphviz cruft**, not wire
size (gzip already crushes SVG whitespace). It is cheap, so we keep it.

### SVGO invocation

- Invoked as **`npx --yes svgo@3 --multipass`** using **mise's Node**, *not* the
  local snap `svgo`. Rationale: the snap build is confined to `$HOME` and cannot
  read the repo under `/hgst`; `npx` via mise Node has no such confinement, so the
  same command works locally and in CI, and the version is pinned inline (no
  `package.json` added to this proto-only repo). `--multipass` runs plugins until
  the output stabilizes.
- Config: `svgo.config.mjs` at repo root, `preset-default` with **`removeViewBox:
  false`** (removing `viewBox` breaks diagram scaling). Kept minimal; protodot's
  graphviz output carries `<a xlink:href>` links and text that must not be mangled.
  Rendering is validated before we trust the config (see Verification).

## Changes

Pipeline (all on `dev`, published via the existing diagrams action):

- `scripts/lib/svgz.sh` → **`scripts/lib/svg.sh`**: `svgz_convert` (gzip + delete
  the `.svg`) becomes `svg_optimize` (run svgo in place, **keep** the `.svg`).
- `scripts/generate_protodot.sh`: source `svg.sh`; call `svg_optimize "$svg"`
  instead of `svgz_convert`. No `.svg` deletion.
- `scripts/insert_diagram_link.sh`: link URL `.dot.svgz` → `.dot.svg` (appears
  twice — image `src` and link `href`).
- `scripts/verify_diagram_links.sh`: expect `.svg`.
- `svgo.config.mjs`: new, repo root.
- `.github/actions/generate-diagrams/action.yml`: ensure Node is available and svgo
  is reachable (`npx --yes svgo@3`) before the generate step. (protodot download
  step unchanged.)
- Tests: `scripts/tests/test_generate_svgz.sh` → `test_generate_svg.sh` (asserts
  svgo ran and a `.svg` remains, no `.svgz`); update `test_diagram_links.sh` for
  `.svg`; update the `script-tests` job in `.github/workflows/ci.yaml` to call the
  renamed test.

One-time ops:

- **Purge `**/*.svgz`** from the `gh-pages` branch. peaceiris uses `keep_files:
  true` (required — it preserves other labels' subtrees), so the canary's
  `dev/**/*.svgz` would otherwise linger as orphans.

## Verification

1. **Wire/serving:** `curl -H 'Accept-Encoding: gzip'` a newly published `.svg` →
   expect `content-type: image/svg+xml`, `content-encoding: gzip`, and a decoded
   body beginning `<svg`.
2. **Inline on BSR:** open a symbol's docs on buf.build (a `dev`-label proto with an
   injected diagram) and confirm the diagram renders inline.
3. **SVGO safety:** spot-check a link-bearing diagram (a `service` proto) renders
   with links/text intact after `--multipass`.

## Rollout (resumes the paused sequence)

The wider rollout stopped just before `dev → main`. `PUBLISH_ENABLED` stays `true`
throughout (fix-forward):

1. Land this change on `dev` → the `dev` canary republishes `.svg` diagrams and
   `.svg` BSR links.
2. Run Verification (1–3 above).
3. Purge stale `.svgz` from `gh-pages`.
4. Resume `dev → main` fast-forward → seeds the BSR `main` breaking baseline.
5. Re-enable `sanity-checks` (drop `if: false`, apply the scoped `if:` recorded in
   the ci.yaml comment).

## Out of scope

- Any change to the publish-mode matrix, environments, or `PUBLISH_ENABLED` gating.
- `sanity-checks` content (only its re-enable, step 5, which is pre-existing rollout
  work).
