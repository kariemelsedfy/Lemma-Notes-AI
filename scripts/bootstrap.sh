#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to install development tools: https://brew.sh" >&2
    exit 1
fi

if ! command -v tuist >/dev/null 2>&1; then
    brew install tuist
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    brew install swiftlint
fi

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "swift-format is required. Install a current Xcode toolchain." >&2
    exit 1
fi

tuist version
swiftlint version
xcrun swift-format --version
