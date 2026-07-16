#!/bin/bash
# Gzip a generated .svg diagram to .svgz and drop the plain .svg.
# Only removes the source once gzip succeeds (no silent data loss).
svgz_convert() {
    local svg="$1"
    local svgz="${svg%.svg}.svgz"
    gzip -c "$svg" > "$svgz" && rm -f "$svg"
}
