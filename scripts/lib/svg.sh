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
