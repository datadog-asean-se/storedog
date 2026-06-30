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
  [ "$DEBUG" -eq 0 ] && return
  local label="$1"; local body="${2:-}"
  printf '  [DEBUG] %s\n' "$label" >&2
  if [ -n "$body" ]; then
    printf '%s\n' "$body" | jq '.' 2>/dev/null >&2 || printf '%s\n' "$body" >&2
  else
    printf '  (empty response body)\n' >&2
  fi
  printf '\n' >&2
}

# api_get <label> <url> — returns body via stdout; debug prints body+code to stderr
api_get() {
  local label="$1" url="$2"
  local body code
  body=$(curl -s "${H[@]}" "$url" || true)
  code=$(curl -s -o /dev/null -w '%{http_code}' "${H[@]}" "$url" || true)
  dbg "$label (HTTP $code)" "$body"
  printf '%s' "$body"
}

# api_post <label> <url> <data> — returns body; also sets global API_LAST_CODE
api_post() {
  local label="$1" url="$2" data="$3"
  local body
  API_LAST_CODE=$(curl -s -o /tmp/ff_post_body.tmp -w '%{http_code}' "${H[@]}" -X POST "$url" -d "$data" || true)
  body=$(cat /tmp/ff_post_body.tmp 2>/dev/null || true)
  rm -f /tmp/ff_post_body.tmp
  dbg "$label request body" "$data"
  dbg "$label response (HTTP $API_LAST_CODE)" "$body"
  printf '%s' "$body"
}
API_LAST_CODE="000"

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

echo "=== Datadog Feature Flags — Workshop Setup ==="
echo "Site  : $SITE"
echo "Flag  : $FLAG_KEY"
echo "Debug : $([ "$DEBUG" -eq 1 ] && echo 'ON  (--debug)' || echo 'OFF (pass --debug for verbose output)')"
echo ""

# ── Step 1: Validate credentials ────────────────────────────────────────────
echo "[1/5] Validating credentials..."
VALIDATE_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "DD-API-KEY: $DD_API_KEY" "https://api.${SITE}/api/v1/validate" || true)
if [ "$DEBUG" -eq 1 ]; then
  VALIDATE_BODY=$(curl -s -H "DD-API-KEY: $DD_API_KEY" "https://api.${SITE}/api/v1/validate" || true)
  dbg "validate response (HTTP $VALIDATE_CODE)" "$VALIDATE_BODY"
fi
if [ "$VALIDATE_CODE" != "200" ]; then
  echo "ERROR: DD_API_KEY validation failed (HTTP $VALIDATE_CODE). Check your key and DD_SITE." >&2; exit 1
fi
echo "      OK (HTTP $VALIDATE_CODE)"

# ── Step 2: Resolve the flag environment ID ──────────────────────────────────
echo "[2/5] Resolving flag environments..."
ENVS=$(api_get "GET environments" "${API}/environments")

if [ "$DEBUG" -eq 1 ]; then
  printf '  [DEBUG] raw ENVS body: %s\n' "$ENVS" >&2
fi

# Parse: try non-production first, fall back to any environment
ENV_ID=$(printf '%s' "$ENVS" | jq -r '[.[] | select(.is_production == false)] | first | .id // empty' 2>/dev/null || true)
if [ -z "${ENV_ID:-}" ]; then
  ENV_ID=$(printf '%s' "$ENVS" | jq -r 'first | .id // empty' 2>/dev/null || true)
fi

if [ -z "${ENV_ID:-}" ]; then
  echo ""
  echo "NOTE: Could not find a flag environment automatically." >&2
  echo "      The Feature Flags environments endpoint returned: ${ENVS:-(empty)}" >&2
  echo "      Attempting to create the flag without an environment (flag only)..." >&2
  ENV_ID=""
  ENV_NAME="(none)"
else
  ENV_NAME=$(printf '%s' "$ENVS" | jq -r --arg id "$ENV_ID" '.[] | select(.id == $id) | .name' 2>/dev/null || true)
  echo "      Using environment: '${ENV_NAME:-unknown}' (${ENV_ID})"
fi

# ── Step 3: Check if flag already exists ────────────────────────────────────
echo "[3/5] Checking if '$FLAG_KEY' already exists..."
EXISTING=$(api_get "GET flags (filter key=$FLAG_KEY)" "${API}?filter[key]=${FLAG_KEY}")
EXISTING_ID=$(printf '%s' "$EXISTING" | jq -r '.data[]? | select(.attributes.key == "'"$FLAG_KEY"'") | .id // empty' 2>/dev/null | head -1 || true)

if [ -n "${EXISTING_ID:-}" ]; then
  echo "      Flag already exists (id=$EXISTING_ID). Skipping creation."
  FLAG_ID="$EXISTING_ID"
else
  # ── Step 4a: Create the flag ───────────────────────────────────────────────
  echo "[4/5] Creating flag '$FLAG_KEY'..."
  CREATE_BODY=$(cat <<JSON
{
  "data": {
    "type": "feature_flags",
    "attributes": {
      "key": "${FLAG_KEY}",
      "name": "Product Card Frustration (Storedog workshop)",
      "description": "Workshop demo: broken product thumbnails to show RUM Frustration Signals. Variant 'frustration' drives rage clicks visible in RUM Explorer.",
      "value_type": "BOOLEAN",
      "variants": [
        {"key": "control",     "name": "Control (good cards)",       "value": "false"},
        {"key": "frustration", "name": "Frustration (broken cards)", "value": "true"}
      ]
    }
  }
}
JSON
)
  CREATE_RESP=$(api_post "POST create-flag" "${API}" "$CREATE_BODY")
  if [ "$API_LAST_CODE" != "200" ] && [ "$API_LAST_CODE" != "201" ]; then
    echo "ERROR: Flag creation failed (HTTP $API_LAST_CODE):" >&2
    printf '%s\n' "$CREATE_RESP" | jq '.' 2>/dev/null >&2 || printf '%s\n' "$CREATE_RESP" >&2
    exit 1
  fi
  FLAG_ID=$(printf '%s' "$CREATE_RESP" | jq -r '.data.id // .id // empty' 2>/dev/null || true)
  if [ -z "${FLAG_ID:-}" ]; then
    echo "ERROR: Could not extract flag ID from creation response." >&2
    printf '%s\n' "$CREATE_RESP" >&2; exit 1
  fi
  echo "      Created (id=$FLAG_ID)"
fi

# ── Step 4b: Get variant IDs from flag detail ────────────────────────────────
FLAG_DETAIL=$(api_get "GET flag detail" "${API}/${FLAG_ID}")
CONTROL_VID=$(printf '%s' "$FLAG_DETAIL" | jq -r '.data.attributes.variants[]? | select(.key=="control") | .id // empty' 2>/dev/null | head -1 || true)
FRUSTRATION_VID=$(printf '%s' "$FLAG_DETAIL" | jq -r '.data.attributes.variants[]? | select(.key=="frustration") | .id // empty' 2>/dev/null | head -1 || true)

# Also resolve ENV_ID from flag detail if step 2 couldn't get it
if [ -z "${ENV_ID:-}" ]; then
  ENV_ID=$(printf '%s' "$FLAG_DETAIL" | jq -r '.data.attributes.feature_flag_environments[]? | select(.is_production == false) | .environment_id // empty' 2>/dev/null | head -1 || true)
  if [ -z "${ENV_ID:-}" ]; then
    ENV_ID=$(printf '%s' "$FLAG_DETAIL" | jq -r '.data.attributes.feature_flag_environments[0]?.environment_id // empty' 2>/dev/null || true)
  fi
  ENV_NAME=$(printf '%s' "$FLAG_DETAIL" | jq -r --arg id "$ENV_ID" '.data.attributes.feature_flag_environments[]? | select(.environment_id == $id) | .environment_name // empty' 2>/dev/null || true)
  [ -n "${ENV_ID:-}" ] && echo "      Resolved environment from flag detail: '${ENV_NAME:-unknown}' ($ENV_ID)"
fi

# ── Step 5: Create or verify allocation (FEATURE_GATE 50/50) ────────────────
if [ -n "${ENV_ID:-}" ]; then
  echo "[5/5] Setting up 50/50 allocation in environment '${ENV_NAME:-unknown}'..."
  ALLOC_URL="${API}/${FLAG_ID}/environments/${ENV_ID}/allocations"
  EXISTING_ALLOC=$(api_get "GET existing allocations" "${ALLOC_URL}")
  ALLOC_COUNT=$(printf '%s' "$EXISTING_ALLOC" | jq '[.data // [] | .[]] | length' 2>/dev/null || echo "0")

  if [ "${ALLOC_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo "      Allocation already exists ($ALLOC_COUNT rule(s)). Skipping."
  else
    ALLOC_DATA=$(cat <<JSON
{
  "data": {
    "type": "allocations",
    "attributes": {
      "allocations": [
        {
          "name": "Workshop 50/50 rollout",
          "key": "workshop-rollout",
          "type": "FEATURE_GATE",
          "variant_weights": [
            {"variant_id": "${CONTROL_VID:-}",     "value": 50},
            {"variant_id": "${FRUSTRATION_VID:-}", "value": 50}
          ],
          "targeting_rules": []
        }
      ]
    }
  }
}
JSON
)
    api_post "POST allocation" "${ALLOC_URL}" "$ALLOC_DATA" > /dev/null
    if [ "$API_LAST_CODE" = "200" ] || [ "$API_LAST_CODE" = "201" ]; then
      echo "      Allocation created."
    else
      echo "      NOTE: Allocation returned HTTP $API_LAST_CODE — set targeting rules manually in the UI."
    fi
  fi

  # Enable the flag in the environment
  echo "      Enabling flag in environment '${ENV_NAME:-unknown}'..."
  api_post "POST enable" "${API}/${FLAG_ID}/environments/${ENV_ID}/enable" "{}" > /dev/null || true
else
  echo "[5/5] No environment resolved — skipping allocation and enable."
  echo "      Open https://app.${SITE}/feature-flags/${FLAG_ID} to configure manually."
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Done ==="
echo "Flag '$FLAG_KEY' is ready in your Datadog org."
echo "View it at: https://app.${SITE}/feature-flags/${FLAG_ID}"
echo ""
echo "Next: docker compose -f docker-compose.dev.yml up -d --build"
echo "Then open /products and check RUM Explorer for @feature_flags.${FLAG_KEY}"
