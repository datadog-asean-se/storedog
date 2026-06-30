#!/usr/bin/env bash
# setup-feature-flags.sh
# Creates the 'product-card-frustration' Datadog Feature Flag in the student's org.
# Idempotent: safe to run multiple times (skips creation if flag already exists).
#
# Requires: DD_API_KEY, DD_APP_KEY (from the lab .env), curl, jq
# Usage:    bash scripts/setup-feature-flags.sh           # normal
#           bash scripts/setup-feature-flags.sh --debug   # verbose (prints raw API responses)
#           DEBUG_FF=1 bash scripts/setup-feature-flags.sh
set -euo pipefail

# ── Debug mode ───────────────────────────────────────────────────────────────
DEBUG=0
for arg in "$@"; do [[ "$arg" == "--debug" || "$arg" == "-d" ]] && DEBUG=1; done
[[ "${DEBUG_FF:-0}" == "1" ]] && DEBUG=1

dbg() {
  # Always writes to stderr; safe to call anywhere including inside $(...)
  [ "$DEBUG" -eq 0 ] && return
  local label="${1:-}" body="${2:-}"
  printf '  [DEBUG] %s\n' "$label" >&2
  if [ -n "$body" ]; then
    printf '%s\n' "$body" | jq '.' 2>/dev/null >&2 || printf '%s\n' "$body" >&2
  else
    printf '  (empty response body)\n' >&2
  fi
  printf '\n' >&2
}

# ── Shared temp file for API responses ───────────────────────────────────────
# api_get / api_post write their response body here so callers avoid subshells
FF_TMP=/tmp/ff_api_resp.tmp
FF_HTTP_CODE="000"

# api_get <label> <url>
# Sets FF_HTTP_CODE; response body in FF_TMP; also echoes body (safe inside $(...))
api_get() {
  local label="$1" url="$2"
  FF_HTTP_CODE=$(curl -s -o "$FF_TMP" -w '%{http_code}' "${H[@]}" "$url" || true)
  dbg "$label (HTTP $FF_HTTP_CODE)" "$(cat "$FF_TMP" 2>/dev/null || true)"
}

# api_post <label> <url> <data_file>
# MUST be called directly, NOT inside $(...) — sets FF_HTTP_CODE and FF_TMP
# Pass data as a file path to avoid shell-quoting multi-line JSON issues
api_post() {
  local label="$1" url="$2" datafile="$3"
  dbg "$label request body" "$(cat "$datafile" 2>/dev/null || true)"
  FF_HTTP_CODE=$(curl -s -o "$FF_TMP" -w '%{http_code}' "${H[@]}" -X POST "$url" --data @"$datafile" || true)
  dbg "$label response (HTTP $FF_HTTP_CODE)" "$(cat "$FF_TMP" 2>/dev/null || true)"
}

# ── Credentials (read from environment or .env) ─────────────────────────────
if [ -z "${DD_API_KEY:-}" ] || [ -z "${DD_APP_KEY:-}" ]; then
  if [ -f .env ]; then
    set -o allexport; source .env; set +o allexport
  fi
fi
: "${DD_API_KEY:?DD_API_KEY is required. Set it in .env or export it.}"
: "${DD_APP_KEY:?DD_APP_KEY is required. Set it in .env or export it.}"
SITE="${DD_SITE:-datadoghq.com}"
API="https://api.${SITE}/api/v2/feature-flags"
H=(-H "DD-API-KEY: ${DD_API_KEY}" -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" -H "Content-Type: application/json")

FLAG_KEY="product-card-frustration"
FLAG_ID=""
ENV_ID=""
ENV_NAME=""

echo "=== Datadog Feature Flags — Workshop Setup ==="
echo "Site  : $SITE"
echo "Flag  : $FLAG_KEY"
echo "Debug : $([ "$DEBUG" -eq 1 ] && echo 'ON  (--debug)' || echo 'OFF (pass --debug for verbose output)')"
echo ""

# ── Step 1: Validate credentials ────────────────────────────────────────────
echo "[1/5] Validating credentials..."
FF_HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "DD-API-KEY: $DD_API_KEY" "https://api.${SITE}/api/v1/validate" || true)
if [ "$FF_HTTP_CODE" != "200" ]; then
  echo "ERROR: DD_API_KEY validation failed (HTTP $FF_HTTP_CODE). Check your key and DD_SITE." >&2; exit 1
fi
echo "      OK (HTTP $FF_HTTP_CODE)"

# ── Step 2: Resolve the flag environment ID ──────────────────────────────────
echo "[2/5] Resolving flag environments..."
api_get "GET environments" "${API}/environments"
ENVS=$(cat "$FF_TMP" 2>/dev/null || true)

# API returns JSON:API format {"data":[...]} — use .data[]
ENV_ID=$(printf '%s' "$ENVS" | jq -r '[.data[]? | select(.is_production == false)] | first | .id // empty' 2>/dev/null || true)
if [ -z "${ENV_ID:-}" ]; then
  # Fallback: any environment
  ENV_ID=$(printf '%s' "$ENVS" | jq -r '.data[0]?.id // empty' 2>/dev/null || true)
fi
if [ -z "${ENV_ID:-}" ]; then
  echo "      NOTE: No flag environments found (endpoint returned: ${ENVS:-(empty)})."
  echo "      Will attempt to create the flag; environment will be resolved from flag detail."
else
  ENV_NAME=$(printf '%s' "$ENVS" | jq -r --arg id "$ENV_ID" '.data[]? | select(.id == $id) | .name // empty' 2>/dev/null || true)
  echo "      Using environment: '${ENV_NAME:-unknown}' ($ENV_ID)"
fi

# ── Step 3: Check if flag already exists ────────────────────────────────────
echo "[3/5] Checking if '$FLAG_KEY' already exists..."
api_get "GET flags" "${API}?filter[key]=${FLAG_KEY}"
EXISTING=$(cat "$FF_TMP" 2>/dev/null || true)

# Try JSON:API format first (.data[]), fall back to bare array (.[]?)
EXISTING_ID=$(printf '%s' "$EXISTING" | jq -r '
  if .data then .data[]? else .[]? end
  | select(.attributes.key == "'"$FLAG_KEY"'" or .key == "'"$FLAG_KEY"'")
  | .id // empty
' 2>/dev/null | head -1 || true)

if [ -n "${EXISTING_ID:-}" ]; then
  echo "      Flag already exists (id=$EXISTING_ID). Skipping creation."
  FLAG_ID="$EXISTING_ID"
else
  # ── Step 4a: Create the flag ───────────────────────────────────────────────
  echo "[4/5] Creating flag '$FLAG_KEY'..."
  FF_DATA_FILE=$(mktemp)
  cat > "$FF_DATA_FILE" <<JSON
{
  "data": {
    "type": "feature_flags",
    "attributes": {
      "key": "${FLAG_KEY}",
      "name": "Product Card Frustration (Storedog workshop)",
      "description": "Workshop demo: broken product thumbnails to show RUM Frustration Signals.",
      "value_type": "BOOLEAN",
      "variants": [
        {"key": "control",     "name": "Control (good cards)",       "value": "false"},
        {"key": "frustration", "name": "Frustration (broken cards)", "value": "true"}
      ]
    }
  }
}
JSON
  # Call directly (NOT inside $(...)) so FF_HTTP_CODE is set in the current shell
  api_post "POST create-flag" "${API}" "$FF_DATA_FILE"
  rm -f "$FF_DATA_FILE"

  if [ "$FF_HTTP_CODE" != "200" ] && [ "$FF_HTTP_CODE" != "201" ]; then
    echo "ERROR: Flag creation failed (HTTP $FF_HTTP_CODE):" >&2
    cat "$FF_TMP" >&2; exit 1
  fi

  FLAG_ID=$(jq -r '.data.id // .id // empty' "$FF_TMP" 2>/dev/null || true)
  if [ -z "${FLAG_ID:-}" ]; then
    echo "ERROR: Could not extract flag ID from creation response:" >&2
    cat "$FF_TMP" >&2; exit 1
  fi
  echo "      Created (id=$FLAG_ID)"
fi

# ── Step 4b: Get variant IDs and resolve ENV_ID if still missing ─────────────
api_get "GET flag detail" "${API}/${FLAG_ID}"
FLAG_DETAIL=$(cat "$FF_TMP" 2>/dev/null || true)

CONTROL_VID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
  (.data.attributes.variants // .variants // [])[]?
  | select(.key=="control") | .id // empty
' 2>/dev/null | head -1 || true)

FRUSTRATION_VID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
  (.data.attributes.variants // .variants // [])[]?
  | select(.key=="frustration") | .id // empty
' 2>/dev/null | head -1 || true)

if [ -z "${ENV_ID:-}" ]; then
  ENV_ID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
    (.data.attributes.feature_flag_environments // [])[]?
    | select(.is_production == false) | .environment_id // empty
  ' 2>/dev/null | head -1 || true)
  if [ -z "${ENV_ID:-}" ]; then
    ENV_ID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
      (.data.attributes.feature_flag_environments // [])[0]?.environment_id // empty
    ' 2>/dev/null || true)
  fi
  if [ -n "${ENV_ID:-}" ]; then
    ENV_NAME=$(printf '%s' "$FLAG_DETAIL" | jq -r --arg id "$ENV_ID" '
      (.data.attributes.feature_flag_environments // [])[]?
      | select(.environment_id == $id) | .environment_name // empty
    ' 2>/dev/null || true)
    echo "      Resolved environment from flag: '${ENV_NAME:-unknown}' ($ENV_ID)"
  fi
fi

# ── Step 5: Allocation + enable ──────────────────────────────────────────────
if [ -n "${ENV_ID:-}" ]; then
  echo "[5/5] Setting up 50/50 allocation in '${ENV_NAME:-unknown}'..."
  ALLOC_URL="${API}/${FLAG_ID}/environments/${ENV_ID}/allocations"
  api_get "GET existing allocations" "${ALLOC_URL}"
  EXISTING_ALLOC=$(cat "$FF_TMP" 2>/dev/null || true)
  ALLOC_COUNT=$(printf '%s' "$EXISTING_ALLOC" | jq '([.data // .] | flatten) | length' 2>/dev/null || echo "0")

  if [ "${ALLOC_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo "      Allocation already exists. Skipping."
  elif [ -n "${CONTROL_VID:-}" ] && [ -n "${FRUSTRATION_VID:-}" ]; then
    FF_ALLOC_FILE=$(mktemp)
    cat > "$FF_ALLOC_FILE" <<JSON
{
  "data": {
    "type": "allocations",
    "attributes": {
      "allocations": [{
        "name": "Workshop 50/50 rollout",
        "key": "workshop-rollout",
        "type": "FEATURE_GATE",
        "variant_weights": [
          {"variant_id": "${CONTROL_VID}",     "value": 50},
          {"variant_id": "${FRUSTRATION_VID}", "value": 50}
        ],
        "targeting_rules": []
      }]
    }
  }
}
JSON
    api_post "POST allocation" "${ALLOC_URL}" "$FF_ALLOC_FILE"
    rm -f "$FF_ALLOC_FILE"
    if [ "$FF_HTTP_CODE" = "200" ] || [ "$FF_HTTP_CODE" = "201" ]; then
      echo "      Allocation created."
    else
      echo "      NOTE: Allocation returned HTTP $FF_HTTP_CODE — configure targeting rules manually in the UI."
    fi
  else
    echo "      Skipping allocation (variant IDs not resolved). Configure manually in the UI."
  fi

  echo "      Enabling flag in '${ENV_NAME:-unknown}'..."
  FF_ENABLE_FILE=$(mktemp); echo '{}' > "$FF_ENABLE_FILE"
  api_post "POST enable" "${API}/${FLAG_ID}/environments/${ENV_ID}/enable" "$FF_ENABLE_FILE"
  rm -f "$FF_ENABLE_FILE"
  echo "      Enabled (HTTP $FF_HTTP_CODE)."
else
  echo "[5/5] No environment resolved — open the Datadog UI to enable and configure targeting."
  echo "      https://app.${SITE}/feature-flags/${FLAG_ID}"
fi

# ── Cleanup and summary ───────────────────────────────────────────────────────
rm -f "$FF_TMP"
echo ""
echo "=== Done ==="
echo "Flag : $FLAG_KEY  (id=$FLAG_ID)"
echo "URL  : https://app.${SITE}/feature-flags/${FLAG_ID}"
echo ""
echo "Next steps:"
echo "  docker compose -f docker-compose.dev.yml up -d --build"
echo "  Open /products — the flag now drives the product card variant"
echo "  RUM Explorer: filter @feature_flags.${FLAG_KEY}"
