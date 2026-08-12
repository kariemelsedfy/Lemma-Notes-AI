#!/usr/bin/env bash
# Verifies the Foundation Models API M4 is built on, against the installed SDK (M4-01).
#
# Two assertions, and the second matters as much as the first:
#   1. The symbols a T0 provider needs still type-check.
#   2. The symbols `AI_PIPELINE.md` §5 assumed — `LanguageModel`, `PrivateCloudComputeLanguageModel`
#      — still do not exist. When that stops being true, T1 becomes possible and §5's original
#      description becomes correct rather than aspirational.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
target="arm64-apple-ios26.0-simulator"

echo "Foundation Models probe against $(basename "$sdk")"

if ! xcrun swiftc -typecheck -target "$target" -sdk "$sdk" -swift-version 6 \
    Tools/api-probes/foundation-models.swift; then
    echo "error: the API M4-02 is built on no longer type-checks. Read the errors before assuming a regression." >&2
    exit 1
fi
echo "  ok: the T0 surface is present"

# Deliberately does not fail the build. An SDK that grows these symbols is good news, and
# breaking every unrelated PR to announce it would be a poor way to deliver good news.
if xcrun swiftc -typecheck -target "$target" -sdk "$sdk" -swift-version 6 \
    Tools/api-probes/foundation-models-absent.swift 2>/dev/null; then
    echo "  NOTE: LanguageModel and PrivateCloudComputeLanguageModel now EXIST on this SDK."
    echo "        M4-07 (Apple PCC) is unblocked and AI_PIPELINE.md §5.1 is out of date."
    echo "        Q12 (iPadOS 26 vs 27) may no longer need answering."
else
    echo "  ok: the iOS 27 surface is still absent, as recorded in AI_PIPELINE.md §5.1"
fi
