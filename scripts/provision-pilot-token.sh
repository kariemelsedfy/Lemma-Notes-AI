#!/usr/bin/env bash
# Copies the pilot bearer token from this Mac's Keychain into a gitignored file that the next build bundles,
# so the app needs no token setup. The token is never printed. Run before ./scripts/generate.sh.
# A bundled token can be extracted from the app: use only for builds installed on your own iPad.
set -euo pipefail
dest="$(cd "$(dirname "$0")/.." && pwd)/Apps/Margin/Resources/PilotToken.local"
umask 077
security find-generic-password -s pilot-proxy-token -w > "$dest"
[[ -s "$dest" ]] || { rm -f "$dest"; echo "No token found in the Keychain (service pilot-proxy-token)." >&2; exit 1; }
# Optionally bundle the proxy address too, so it is not in the (public) source: PILOT_PROXY_URL=https://... ./scripts/...
if [[ -n "${PILOT_PROXY_URL:-}" ]]; then
    printf '%s' "$PILOT_PROXY_URL" > "$(dirname "$dest")/PilotServer.local"
    echo "Wrote PilotServer.local."
fi
echo "Wrote $(basename "$dest") ($(wc -c < "$dest" | tr -d ' ') bytes). Now run ./scripts/generate.sh and build."
