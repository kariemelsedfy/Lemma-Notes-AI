#!/usr/bin/env bash
# Runs Tools/evalrunner against Fixtures/golden (ARCHITECTURE §7.1, AI_PIPELINE §9).
#
#     ./scripts/eval.sh --provider mock
#
# Only `mock` exists until M4-02 lands a real provider. The runner refuses an unknown provider
# rather than substituting one, because a metrics file attributed to the wrong tier is worse
# than no metrics file.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

swift run --package-path Tools/evalrunner evalrunner --cases "$root_dir/Fixtures/golden" "$@"
