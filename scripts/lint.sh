#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint is not installed. Run ./scripts/bootstrap.sh first." >&2
    exit 1
fi

if [[ "${1:-}" == "--fix" ]]; then
    swiftlint --fix --config .swiftlint.yml
    xcrun swift-format format --in-place --recursive Apps/Margin/Sources Packages/*/Sources Packages/*/Tests \
        Packages/*/Package.swift Project.swift Tuist.swift
fi

swiftlint lint --strict --config .swiftlint.yml Apps/Margin/Sources Packages/*/Sources Packages/*/Tests \
    Packages/*/Package.swift Project.swift Tuist.swift
xcrun swift-format lint --strict --recursive --parallel Apps/Margin/Sources Packages/*/Sources Packages/*/Tests \
    Packages/*/Package.swift Project.swift Tuist.swift
