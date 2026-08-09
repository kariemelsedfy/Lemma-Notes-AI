#!/usr/bin/env bash
set -euo pipefail

# The glyph bank is biometric-adjacent data. AGENTS.md §7: it never leaves the device, and
# no upload path may exist in the code *even disabled*. A comment cannot enforce that, so
# this fails the build if the Handwriting module gains any way to send anything anywhere.

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sources_dir="${1:-$root_dir/Packages/Handwriting/Sources}"

if [[ ! -d "$sources_dir" ]]; then
    echo "Handwriting sources not found: $sources_dir" >&2
    exit 1
fi

# Symbols that would give this module the ability to transmit. Vision and CoreText are
# fine — they are on-device.
forbidden='URLSession|URLRequest|NSURLConnection|CFNetwork|import Network|NWConnection|Socket|CFSocket|CFStream|NSStream|WKWebView|CloudKit|NSUbiquitous|FileManager\.default\.url\(forUbiquityContainerIdentifier'

violations=0
while IFS= read -r source_file; do
    if matches=$(grep -nE "$forbidden" "$source_file"); then
        echo "$source_file: the glyph bank module must not be able to transmit data (AGENTS.md §7)" >&2
        echo "$matches" >&2
        violations=1
    fi
done < <(find "$sources_dir" -name '*.swift')

if [[ $violations -ne 0 ]]; then
    exit 1
fi

echo "Glyph bank privacy boundary is intact."
