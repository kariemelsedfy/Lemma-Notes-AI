#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root_dir/scripts/check-module-dependencies.sh"
fixtures_dir="$root_dir/scripts/fixtures/module-dependencies"

"$checker" "$root_dir/Packages"
"$checker" "$fixtures_dir/valid/Packages"

if "$checker" "$fixtures_dir/invalid/Packages"; then
    echo "The module dependency checker accepted a forbidden import." >&2
    exit 1
fi

echo "Module dependency checker fixtures passed."
