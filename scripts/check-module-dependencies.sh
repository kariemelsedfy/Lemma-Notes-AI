#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packages_dir="${1:-$root_dir/Packages}"

if [[ ! -d "$packages_dir" ]]; then
    echo "Package directory does not exist: $packages_dir" >&2
    exit 1
fi

internal_modules=(Analytics DesignSystem DocumentStore Handwriting InkCore Intelligence)

allowed_imports_for() {
    case "$1" in
    Intelligence)
        echo "Handwriting InkCore"
        ;;
    Handwriting)
        echo "InkCore"
        ;;
    Analytics | DesignSystem | DocumentStore | InkCore)
        echo ""
        ;;
    *)
        echo "Unknown internal module: $1" >&2
        exit 1
        ;;
    esac
}

has_allowed_import() {
    local allowed_imports="$1"
    local imported_module="$2"

    [[ " $allowed_imports " == *" $imported_module "* ]]
}

violations=0

for module_dir in "$packages_dir"/*; do
    [[ -d "$module_dir/Sources" ]] || continue

    module_name="$(basename "$module_dir")"
    allowed_imports="$(allowed_imports_for "$module_name")"

    while IFS= read -r source_file; do
        while IFS= read -r imported_module; do
            [[ -n "$imported_module" ]] || continue

            if ! has_allowed_import "$allowed_imports" "$imported_module"; then
                echo "$source_file: $module_name must not import $imported_module" >&2
                violations=1
            fi
        done < <(
            awk '
                /^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+(Analytics|DesignSystem|DocumentStore|Handwriting|InkCore|Intelligence)[[:space:]]*$/ {
                    print $NF
                }
            ' "$source_file"
        )
    done < <(find "$module_dir/Sources" -type f -name '*.swift' | sort)
done

if [[ "$violations" -ne 0 ]]; then
    exit 1
fi

echo "Module dependency boundaries are valid."
