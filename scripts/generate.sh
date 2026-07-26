#!/usr/bin/env bash
set -euo pipefail

mise_bin="$(command -v mise || true)"
if [[ -z "$mise_bin" && -x "${HOME}/.local/bin/mise" ]]; then
    mise_bin="${HOME}/.local/bin/mise"
fi

if [[ -z "$mise_bin" ]]; then
    echo "Mise is not installed. Run ./scripts/bootstrap.sh first." >&2
    exit 1
fi

"$mise_bin" exec -- tuist generate
