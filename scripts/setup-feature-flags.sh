#!/usr/bin/env bash
# setup-feature-flags.sh
# Creates the 'product-card-frustration' Datadog Feature Flag in the student's org.
# Idempotent: safe to run multiple times (skips creation if flag already exists).
#
# Requires: DD_API_KEY, DD_APP_KEY (from the lab .env), curl, jq
# Usage:    bash scripts/setup-feature-flags.sh           # normal
#           bash scripts/setup-feature-flags.sh --debug   # verbose (prints raw API responses)
#           DEBUG=1 bash scripts/setup-feature-flags.sh   # same via env var
set -euo pipefail

# ── Debug mode ───────────────────────────────────────────────────────────────
DEBUG=0
for arg in "$@"; do [[ "$arg" == "--debug" || "$arg" == "-d" ]] && DEBUG=1; done
[[ "${DEBUG_FF:-0}" == "1" ]] && DEBUG=1  # also honour env var DEBUG_FF=1

dbg() {
  # dbg <label> <json_or_string>  — prints only in debug mode, always to stderr
  # Must use stderr so output is visible even when the caller is inside $(...) capture
  [ "$DEBUG" -eq 0 ] && return
  local label="$1"; shift
  echo "  [DEBUG] ${label}:" >&2
  echo "$*" | jq '.' 2>/dev/null >&2 || echo "$*" >&2
  echo "" >&2
}

curl_dbg() {
  # Wrapper: in debug mode prints full response body + HTTP code; in normal mode silent.
  local label="$1"; shift
  if [ "$DEBUG" -eq 1 ]; then
    local out
    out=$(curl -s -w '\n__HTTP__%{http_code}' "$@")
    local body code
    body=$(echo "$out" | sed '$d')
    code=$(echo "$out" | tail -1 | sed 's/__HTTP__//')
    dbg "$label (HTTP $code)" "$body"
    echo "$body"
  else
    curl -s "$@"
  fi
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

echo "=== Datadog Feature Flags — Workshop Setup ==="
echo "Site  : $SITE"
echo "Flag  : $FLAG_KEY"
echo "Debug : $([ "$DEBUG" -eq 1 ] && echo 'ON  (--debug)' || echo 'OFF (pass --debug for verbose output)')"
echo ""

# ── Step 1: Validate credentials ────────────────────────────────────────────
echo "[1/5] Validating credentials..."
VALIDATE_RESP=$(curl -s -w '\n__HTTP__%{http_code}' -H "DD-API-KEY: $DD_API_KEY" "https://api.${SITE}/api/v1/validate")
code=$(echo "$VALIDATE_RESP" | tail -1 | sed 's/__HTTP__//')
dbg "validate response" "$(echo "$VALIDATE_RESP" | sed '$d')"
if [ "$code" != "200" ]; then
  echo "ERROR: DD_API_KEY validation failed (HTTP $code). Check your key and DD_SITE." >&2; exit 1
fi
echo "      OK"

# ── Step 2: Resolve the 'dev' flag environment ID ───────────────────────────
echo "[2/5] Resolving flag environments..."
ENVS=$(curl_dbg "GET environments" "${H[@]}" "${API}/environments")
ENV_ID=$(echo "$ENVS" | jq -r '[.[] | select(.is_production == false)] | first | .id // empty' 2>/dev/null)
if [ -z "$ENV_ID" ]; then
  # Fallback: first environment regardless of type
  ENV_ID=$(echo "$ENVS" | jq -r 'first | .id // empty' 2>/dev/null)
fi
if [ -z "$ENV_ID" ]; then
  echo "ERROR: Could not resolve a flag environment. Does this org have Feature Flags enabled?" >&2; exit 1
fi
ENV_NAME=$(echo "$ENVS" | jq -r --arg id "$ENV_ID" '.[] | select(.id == $id) | .name' 2>/dev/null)
echo "      Using environment: '$ENV_NAME' ($ENV_ID)"

# ── Step 3: Check if flag already exists ────────────────────────────────────
echo "[3/5] Checking if '$FLAG_KEY' already exists..."
EXISTING=$(curl_dbg "GET flags list (filter key=$FLAG_KEY)" "${H[@]}" "${API}?filter[key]=${FLAG_KEY}")
EXISTING_ID=$(echo "$EXISTING" | jq -r '.data[]? | select(.attributes.key == "'"$FLAG_KEY"'") | .id // empty' 2>/dev/null | head -1)

if [ -n "$EXISTING_ID" ]; then
  echo "      Flag already exists (id=$EXISTING_ID). Skipping creation."
  FLAG_ID="$EXISTING_ID"
else
  # ── Step 4a: Create the flag ───────────────────────────────────────────────
  echo "[4/5] Creating flag '$FLAG_KEY'..."
  BODY=$(cat <<JSON
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
  dbg "POST create-flag request body" "$BODY"
  RESP=$(curl -s -w '\n__HTTP__%{http_code}' "${H[@]}" -X POST "${API}" -d "$BODY")
  HTTP_CODE=$(echo "$RESP" | tail -1 | sed 's/__HTTP__//')
  BODY_RESP=$(echo "$RESP" | sed '$d')
  dbg "POST create-flag response (HTTP $HTTP_CODE)" "$BODY_RESP"
  if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "ERROR: Flag creation failed (HTTP $HTTP_CODE):" >&2
    echo "$BODY_RESP" | jq '.' 2>/dev/null || echo "$BODY_RESP" >&2; exit 1
  fi
  FLAG_ID=$(echo "$BODY_RESP" | jq -r '.data.id // .id // empty' 2>/dev/null)
  echo "      Created (id=$FLAG_ID)"
fi

# ── Step 4b: Get variant IDs ────────────────────────────────────────────────
FLAG_DETAIL=$(curl_dbg "GET flag detail (id=$FLAG_ID)" "${H[@]}" "${API}/${FLAG_ID}")
CONTROL_VID=$(echo "$FLAG_DETAIL" | jq -r '.data.attributes.variants[]? | select(.key=="control") | .id // empty' 2>/dev/null | head -1)
FRUSTRATION_VID=$(echo "$FLAG_DETAIL" | jq -r '.data.attributes.variants[]? | select(.key=="frustration") | .id // empty' 2>/dev/null | head -1)

# ── Step 5: Create or verify allocation (FEATURE_GATE 50/50) ────────────────
echo "[5/5] Setting up 50/50 allocation in environment '$ENV_NAME'..."
ALLOC_URL="${API}/${FLAG_ID}/environments/${ENV_ID}/allocations"
EXISTING_ALLOC=$(curl_dbg "GET existing allocations" "${H[@]}" "${ALLOC_URL}")
ALLOC_COUNT=$(echo "$EXISTING_ALLOC" | jq '[.data // [] | .[]] | length' 2>/dev/null || echo "0")

if [ "${ALLOC_COUNT:-0}" -gt 0 ]; then
  echo "      Allocation already exists ($ALLOC_COUNT rule(s)). Skipping."
else
  ALLOC_BODY=$(cat <<JSON
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
            {"variant_id": "${CONTROL_VID}",     "value": 50},
            {"variant_id": "${FRUSTRATION_VID}", "value": 50}
          ],
          "targeting_rules": []
        }
      ]
    }
  }
}
JSON
)
  dbg "POST allocation request body" "$ALLOC_BODY"
  ARESP=$(curl -s -w '\n__HTTP__%{http_code}' "${H[@]}" -X POST "${ALLOC_URL}" -d "$ALLOC_BODY")
  ACODE=$(echo "$ARESP" | tail -1 | sed 's/__HTTP__//')
  dbg "POST allocation response (HTTP $ACODE)" "$(echo "$ARESP" | sed '$d')"
  if [ "$ACODE" != "200" ] && [ "$ACODE" != "201" ]; then
    echo "      NOTE: Allocation via POST returned HTTP $ACODE — may need to be set manually in the UI."
    echo "      Flag is created. Open https://app.datadoghq.com/feature-flags and add targeting rules manually."
  else
    echo "      Allocation created."
  fi
fi

# ── Enable flag in the target environment ────────────────────────────────────
echo "      Enabling flag in environment '$ENV_NAME'..."
ENABLE_RESP=$(curl -s -w '\n__HTTP__%{http_code}' "${H[@]}" -X POST "${API}/${FLAG_ID}/environments/${ENV_ID}/enable")
ENABLE_CODE=$(echo "$ENABLE_RESP" | tail -1 | sed 's/__HTTP__//')
dbg "POST enable response (HTTP $ENABLE_CODE)" "$(echo "$ENABLE_RESP" | sed '$d')"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Done ==="
echo "Flag '$FLAG_KEY' is ready in your Datadog org."
echo "View it at: https://app.${SITE}/feature-flags/${FLAG_ID}"
echo ""
echo "Next: docker compose -f docker-compose.dev.yml up -d --build"
echo "Then open /products and check RUM Explorer for @feature_flags.${FLAG_KEY}"
