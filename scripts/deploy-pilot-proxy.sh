#!/usr/bin/env bash
# Deploys Tools/pilot-proxy to Google Cloud Run (ADR-028). Run it yourself in your own terminal after
# `gcloud auth login`; it reads the Gemini key from the macOS Keychain and pipes it straight into Secret
# Manager, so the key is never printed, written to a file or passed on a command line.
#
#   scripts/deploy-pilot-proxy.sh PROJECT_ID [REGION]      # default region: us-central1
#   DRY_RUN=1 scripts/deploy-pilot-proxy.sh PROJECT_ID     # print the plan, change nothing
#   ROTATE_TOKEN=1 scripts/deploy-pilot-proxy.sh PROJECT_ID  # issue a new iPad bearer token
#
# Expected cost: inside the free tier for a one-device pilot (one instance, scale to zero). The $10 total
# ceiling (ADR-021/027) is still enforced by the proxy's Firestore ledger, not by Google.
set -euo pipefail

PROJECT="${1:?usage: deploy-pilot-proxy.sh PROJECT_ID [REGION]}"
REGION="${2:-us-central1}"
SERVICE="pilot-proxy"
ACCOUNT_NAME="pilot-proxy"
ACCOUNT="${ACCOUNT_NAME}@${PROJECT}.iam.gserviceaccount.com"
KEYCHAIN_ACCOUNT="margin-pilot"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY="${DRY_RUN:-0}"

run() {
    if [ "$DRY" = "1" ]; then printf 'DRY RUN: %s\n' "$*"; else "$@"; fi
}

# IAM changes can briefly conflict right after a service account is created; retry with backoff.
retry() {
    local attempt=1
    until "$@"; do
        [ "$attempt" -ge 6 ] && { echo "Failed after $attempt attempts: $1 $2 $3" >&2; return 1; }
        sleep $((attempt * 5))
        attempt=$((attempt + 1))
    done
}

run_retry() {
    if [ "$DRY" = "1" ]; then printf 'DRY RUN: %s\n' "$*"; else retry "$@"; fi
}

secret_exists() { gcloud secrets describe "$1" --project "$PROJECT" >/dev/null 2>&1; }

if [ "$DRY" != "1" ]; then
    command -v gcloud >/dev/null || { echo "gcloud is not installed" >&2; exit 1; }
    gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q . \
        || { echo "Run 'gcloud auth login' first." >&2; exit 1; }
fi

echo "== Enabling APIs"
run gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
    firestore.googleapis.com secretmanager.googleapis.com --project "$PROJECT"

echo "== Firestore database (Native mode)"
if [ "$DRY" = "1" ] || ! gcloud firestore databases describe --project "$PROJECT" >/dev/null 2>&1; then
    run gcloud firestore databases create --project "$PROJECT" --location "$REGION" --type firestore-native
fi

echo "== Service account with only Firestore access"
if [ "$DRY" = "1" ] || ! gcloud iam service-accounts describe "$ACCOUNT" --project "$PROJECT" >/dev/null 2>&1; then
    run gcloud iam service-accounts create "$ACCOUNT_NAME" --project "$PROJECT" \
        --display-name "Margin pilot proxy"
fi
run_retry gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$ACCOUNT" \
    --role roles/datastore.user --condition=None >/dev/null

echo "== Secrets (values are never printed)"
if [ "$DRY" = "1" ]; then
    echo "DRY RUN: gemini-api-key <- Keychain ($KEYCHAIN_ACCOUNT / gemini-api-key)"
    echo "DRY RUN: pilot-token <- openssl rand, copy kept in Keychain ($KEYCHAIN_ACCOUNT / pilot-proxy-token)"
else
    if ! secret_exists gemini-api-key; then
        security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s gemini-api-key -w \
            | tr -d '\n' | gcloud secrets create gemini-api-key --project "$PROJECT" \
                --replication-policy automatic --data-file=-
    fi
    if ! secret_exists pilot-token || [ "${ROTATE_TOKEN:-0}" = "1" ]; then
        TOKEN="$(openssl rand -base64 36 | tr -d '\n=+/')"
        if secret_exists pilot-token; then
            printf '%s' "$TOKEN" | gcloud secrets versions add pilot-token --project "$PROJECT" --data-file=-
        else
            printf '%s' "$TOKEN" | gcloud secrets create pilot-token --project "$PROJECT" \
                --replication-policy automatic --data-file=-
        fi
        security add-generic-password -U -a "$KEYCHAIN_ACCOUNT" -s pilot-proxy-token -w "$TOKEN"
        unset TOKEN
        echo "New iPad token stored in Keychain (service pilot-proxy-token). It was not printed."
    fi
fi
for name in gemini-api-key pilot-token; do
    run_retry gcloud secrets add-iam-policy-binding "$name" --project "$PROJECT" \
        --member "serviceAccount:$ACCOUNT" --role roles/secretmanager.secretAccessor >/dev/null
done

# The subject id is not secret; one fixed id per deployment keeps the ledger's per-pilot rate limit stable.
SUBJECT="$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s pilot-proxy-subject -w 2>/dev/null || true)"
if [ -z "$SUBJECT" ]; then
    SUBJECT="$(uuidgen)"
    [ "$DRY" = "1" ] || security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s pilot-proxy-subject -w "$SUBJECT"
fi

echo "== Build and deploy (Cloud Build; the first Swift build takes several minutes)"
run gcloud run deploy "$SERVICE" --project "$PROJECT" --region "$REGION" \
    --source "$ROOT/Tools/pilot-proxy" --service-account "$ACCOUNT" \
    --max-instances 1 --concurrency 4 --cpu 1 --memory 512Mi --timeout 60 \
    --allow-unauthenticated \
    --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT,PILOT_SUBJECT=$SUBJECT" \
    --set-secrets "GEMINI_API_KEY=gemini-api-key:latest,PILOT_TOKEN=pilot-token:latest"

if [ "$DRY" != "1" ]; then
    URL="$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)')"
    echo "== Health check: $URL/healthz"
    curl -fsS "$URL/healthz" && echo
    echo "Service URL: $URL"
fi
