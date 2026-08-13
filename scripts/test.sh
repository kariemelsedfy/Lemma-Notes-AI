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

# The tools have no tests of their own — their logic lives in `Intelligence` where it can be
# unit-tested — but they must keep building, and the eval run is a smoke test of the whole
# harness: cases load, requests build, specs validate, metrics compute, JSON writes.
for tool in Tools/*/Package.swift; do
    swift build --package-path "$(dirname "$tool")"
done
./scripts/eval.sh --provider mock > /dev/null

./scripts/generate.sh
xcodebuild build \
    -workspace Margin.xcworkspace \
    -scheme Margin \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO
