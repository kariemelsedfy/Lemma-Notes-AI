#!/usr/bin/env bash
set -euo pipefail

# PencilKit renders a *stored* stroke colour through the *current* appearance, lightening
# dark ink so it stays legible on a dark background. Margin's page is paper — fixed light in
# both appearances — so that inversion puts white ink on a white page. Pinning the ink token
# to a non-dynamic black does not help: it controls what gets saved, not what gets drawn.
#
# The opt-out is per-site and easy to forget on the next canvas, so it is checked here rather
# than left to review. `InkCore.InkAppearance` documents the whole thing.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
violations=0

while IFS= read -r source_file; do
    if grep -q 'PKCanvasView()' "$source_file" &&
        ! grep -q 'applyPaperAppearance' "$source_file"; then
        echo "$source_file: builds a PKCanvasView without InkAppearance.applyPaperAppearance(to:)" >&2
        echo "  Without it PencilKit inverts dark ink and the user writes in white on white." >&2
        violations=1
    fi

    if grep -q '\.image(from:' "$source_file" &&
        ! grep -qE 'onPaper|performAsCurrent' "$source_file"; then
        echo "$source_file: rasterises a PKDrawing outside a light trait environment" >&2
        echo "  Wrap it in InkAppearance.onPaper { } or the ink inverts with the appearance." >&2
        violations=1
    fi
done < <(
    find "$root_dir/Apps/Margin/Sources" "$root_dir/Packages" \
        -path '*/Sources/*' -type f -name '*.swift' -print | sort
)

if [[ "$violations" -ne 0 ]]; then
    exit 1
fi

echo "Ink appearance opt-outs are in place."
