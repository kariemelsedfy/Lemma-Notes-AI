#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

./scripts/test-module-dependencies.sh
./scripts/check-color-tokens.sh
./scripts/check-glyph-bank-privacy.sh
./scripts/check-ink-appearance.sh
./scripts/check-foundation-models-api.sh

for package in Packages/*; do
    swift test --package-path "$package"
done

# Keep tool targets building; the proxy also has independent security tests. The eval run
# smoke-tests the full harness: cases load, requests build, specs validate and metrics write.
for tool in Tools/*/Package.swift; do
    swift build --package-path "$(dirname "$tool")"
done
swift test --package-path Tools/bedrock-proxy
./scripts/eval.sh --provider mock > /dev/null

./scripts/generate.sh
xcodebuild build \
    -workspace Margin.xcworkspace \
    -scheme Margin \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO
