#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

./scripts/test-module-dependencies.sh
./scripts/check-color-tokens.sh
./scripts/check-glyph-bank-privacy.sh

for package in Packages/*; do
    swift test --package-path "$package"
done

./scripts/generate.sh
xcodebuild build \
    -workspace Margin.xcworkspace \
    -scheme Margin \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO
