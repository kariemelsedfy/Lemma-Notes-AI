#!/usr/bin/env bash
set -euo pipefail

if ! command -v tuist >/dev/null 2>&1; then
    echo "Tuist is not installed. Run ./scripts/bootstrap.sh first." >&2
    exit 1
fi

tuist generate
