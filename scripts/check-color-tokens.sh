#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
violations=0

while IFS= read -r source_file; do
    if awk '/(^|[^[:alnum:]_])Color[[:space:]]*(\.|\()/' "$source_file" | grep -q .; then
        echo "$source_file: use MarginColor tokens instead of constructing Color directly" >&2
        violations=1
    fi
done < <(
    find "$root_dir/Apps/Margin/Sources" "$root_dir/Packages" \
        -path '*/DesignSystem/Sources/*' -prune -o \
        -path '*/Sources/*' -type f -name '*.swift' -print | sort
)

if [[ "$violations" -ne 0 ]]; then
    exit 1
fi

echo "Color token usage is valid."
