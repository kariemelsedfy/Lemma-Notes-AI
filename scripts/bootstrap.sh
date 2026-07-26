#!/usr/bin/env bash
set -euo pipefail

mise_bin="$(command -v mise || true)"
if [[ -z "$mise_bin" ]]; then
    curl https://mise.jdx.dev/install.sh | sh
    mise_bin="${HOME}/.local/bin/mise"
fi

"$mise_bin" install

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required to install SwiftLint: https://brew.sh" >&2
    exit 1
fi

if ! command -v swiftlint >/dev/null 2>&1; then
    brew install swiftlint
fi

if ! xcrun --find swift-format >/dev/null 2>&1; then
    echo "swift-format is required. Install a current Xcode toolchain." >&2
    exit 1
fi

"$mise_bin" exec -- tuist version
swiftlint version
xcrun swift-format --version
