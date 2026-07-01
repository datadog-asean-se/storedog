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
# Response format: {"data":[{"id":"...","type":"environments","attributes":{"name":"...","is_production":bool,"queries":[...]}}]}
echo "[2/5] Resolving flag environments..."
api_get "GET environments" "${API}/environments"
ENVS=$(cat "$FF_TMP" 2>/dev/null || true)

# Prefer the environment whose queries include "dev"; fall back to any non-production
ENV_ID=$(printf '%s' "$ENVS" | jq -r '
  [.data[]? | select(.attributes.queries[]? == "dev")] | first | .id // empty
' 2>/dev/null || true)
if [ -z "${ENV_ID:-}" ]; then
  ENV_ID=$(printf '%s' "$ENVS" | jq -r '
    [.data[]? | select(.attributes.is_production == false)] | first | .id // empty
  ' 2>/dev/null || true)
fi
if [ -z "${ENV_ID:-}" ]; then
  ENV_ID=$(printf '%s' "$ENVS" | jq -r '.data[0]?.id // empty' 2>/dev/null || true)
fi
if [ -z "${ENV_ID:-}" ]; then
  echo "      NOTE: No flag environments found. Will resolve from flag detail after creation."
else
  ENV_NAME=$(printf '%s' "$ENVS" | jq -r --arg id "$ENV_ID" '
    .data[]? | select(.id == $id) | .attributes.name // empty
  ' 2>/dev/null || true)
  echo "      Using environment: '${ENV_NAME:-unknown}' ($ENV_ID)"
fi

# ── Step 3: Check if flag already exists ────────────────────────────────────
# Note: filter[key] query param is NOT used — curl interprets [...] as a glob
# and silently fails. Fetch all flags and search client-side instead.
echo "[3/5] Checking if '$FLAG_KEY' already exists..."
api_get "GET all flags" "${API}"
EXISTING=$(cat "$FF_TMP" 2>/dev/null || true)

EXISTING_ID=$(printf '%s' "$EXISTING" | jq -r '
  .data[]? | select(.attributes.key == "'"$FLAG_KEY"'") | .id // empty
' 2>/dev/null | head -1 || true)

if [ -n "${EXISTING_ID:-}" ]; then
  echo "      Flag already exists (id=$EXISTING_ID). Skipping creation."
  FLAG_ID="$EXISTING_ID"
else
  # ── Step 4a: Create the flag ───────────────────────────────────────────────
  echo "[4/5] Creating flag '$FLAG_KEY'..."
  FF_DATA_FILE=$(mktemp)
  # JSON:API format — type must be "feature-flags" (hyphenated, matching the URL path)
  cat > "$FF_DATA_FILE" <<JSON
{
  "data": {
    "type": "feature-flags",
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

  if [ "$FF_HTTP_CODE" = "409" ]; then
    # Conflict: flag already exists but was missed by step 3 (e.g. on re-run).
    # Fetch the flag list to recover the ID.
    echo "      Flag already exists (409 Conflict). Recovering ID from flag list..."
    api_get "GET all flags (recover id)" "${API}"
    FLAG_ID=$(cat "$FF_TMP" | jq -r '
      .data[]? | select(.attributes.key == "'"$FLAG_KEY"'") | .id // empty
    ' 2>/dev/null | head -1 || true)
    if [ -z "${FLAG_ID:-}" ]; then
      echo "ERROR: Flag exists but could not retrieve its ID. Delete it manually and retry." >&2; exit 1
    fi
    echo "      Recovered existing flag (id=$FLAG_ID)"
  elif [ "$FF_HTTP_CODE" != "200" ] && [ "$FF_HTTP_CODE" != "201" ]; then
    echo "ERROR: Flag creation failed (HTTP $FF_HTTP_CODE):" >&2
    ERRBODY=$(cat "$FF_TMP" 2>/dev/null || true)
    if [ -n "$ERRBODY" ]; then
      printf '%s\n' "$ERRBODY" | jq '.' 2>&1 >&2 || printf '%s\n' "$ERRBODY" >&2
    else
      printf '  (empty response body — run with DEBUG_FF=1 for verbose output)\n' >&2
    fi
    echo "  Hint: run:  DEBUG_FF=1 bash scripts/setup-feature-flags.sh" >&2
    exit 1
  fi

  # Response: {"data":{"id":"...","type":"feature-flags","attributes":{...}}}
  if [ -z "${FLAG_ID:-}" ]; then
    FLAG_ID=$(jq -r '.data.id // empty' "$FF_TMP" 2>/dev/null || true)
  fi
  if [ -z "${FLAG_ID:-}" ]; then
    echo "ERROR: Could not extract flag ID from creation response:" >&2
    cat "$FF_TMP" >&2; exit 1
  fi
  echo "      Created (id=$FLAG_ID)"
fi

# ── Step 4b: Get variant IDs and resolve ENV_ID if still missing ─────────────
api_get "GET flag detail" "${API}/${FLAG_ID}"
FLAG_DETAIL=$(cat "$FF_TMP" 2>/dev/null || true)

# Response: {"data":{"attributes":{"variants":[...],"feature_flag_environments":[...]}}}
CONTROL_VID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
  .data.attributes.variants[]? | select(.key=="control") | .id // empty
' 2>/dev/null | head -1 || true)

FRUSTRATION_VID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
  .data.attributes.variants[]? | select(.key=="frustration") | .id // empty
' 2>/dev/null | head -1 || true)

if [ -z "${ENV_ID:-}" ]; then
  # Prefer environment whose queries include "dev"
  ENV_ID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
    [.data.attributes.feature_flag_environments[]?
     | select(.environment_queries[]? == "dev")] | first | .environment_id // empty
  ' 2>/dev/null | head -1 || true)
  if [ -z "${ENV_ID:-}" ]; then
    ENV_ID=$(printf '%s' "$FLAG_DETAIL" | jq -r '
      [.data.attributes.feature_flag_environments[]?
       | select(.is_production == false)] | first | .environment_id // empty
    ' 2>/dev/null | head -1 || true)
  fi
  if [ -n "${ENV_ID:-}" ]; then
    ENV_NAME=$(printf '%s' "$FLAG_DETAIL" | jq -r --arg id "$ENV_ID" '
      .data.attributes.feature_flag_environments[]?
      | select(.environment_id == $id) | .environment_name // empty
    ' 2>/dev/null || true)
    echo "      Resolved environment from flag: '${ENV_NAME:-unknown}' ($ENV_ID)"
  fi
fi

# ── Step 5: Allocation + enable ──────────────────────────────────────────────
if [ -n "${ENV_ID:-}" ]; then
  echo "[5/5] Setting up 50/50 allocation in '${ENV_NAME:-unknown}'..."
  ALLOC_URL="${API}/${FLAG_ID}/environments/${ENV_ID}/allocations"

  # Note: GET /allocations returns 405 (not supported) — always attempt to create.
  # The API is idempotent on key collision (will update existing allocation with same key).
  if [ -n "${CONTROL_VID:-}" ] && [ -n "${FRUSTRATION_VID:-}" ]; then
    FF_ALLOC_FILE=$(mktemp)
    # Correct format: name/key/type/variant_weights at data.attributes level (NOT nested in allocations[])
    cat > "$FF_ALLOC_FILE" <<JSON
{
  "data": {
    "type": "allocations",
    "attributes": {
      "name": "Workshop 50/50",
      "key": "workshop-5050",
      "type": "FEATURE_GATE",
      "variant_weights": [
        {"variant_id": "${CONTROL_VID}",     "value": 50},
        {"variant_id": "${FRUSTRATION_VID}", "value": 50}
      ],
      "targeting_rules": []
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

# ════════════════════════════════════════════════════════════════════════════
# Helper: create, 50/50-allocate, and enable an additional demo flag
# Usage: setup_extra_flag <flag_key> <flag_name> <desc> <value_type> \
#                         <v1_key> <v1_name> <v1_value> \
#                         <v2_key> <v2_name> <v2_value>
# ════════════════════════════════════════════════════════════════════════════
setup_extra_flag() {
  local fkey="$1" fname="$2" fdesc="$3" vtype="$4"
  local v1key="$5" v1name="$6" v1val="$7"
  local v2key="$8" v2name="$9" v2val="${10}"
  local fid="" v1id="" v2id=""

  echo ""
  echo "--- Flag: ${fkey} (${vtype}) ---"

  # Check if the flag already exists
  api_get "GET all flags (${fkey})" "${API}"
  fid=$(cat "$FF_TMP" | jq -r '.data[]? | select(.attributes.key == "'"$fkey"'") | .id // empty' 2>/dev/null | head -1 || true)

  if [ -n "$fid" ]; then
    echo "      Already exists (id=$fid). Skipping creation."
  else
    local fdata; fdata=$(mktemp)
    # Use jq --arg so all values (including JSON strings) are properly escaped
    jq -n \
      --arg fkey  "$fkey"  \
      --arg fname "$fname" \
      --arg fdesc "$fdesc" \
      --arg vtype "$vtype" \
      --arg v1key "$v1key" --arg v1name "$v1name" --arg v1val "$v1val" \
      --arg v2key "$v2key" --arg v2name "$v2name" --arg v2val "$v2val" \
      '{data:{type:"feature-flags",attributes:{key:$fkey,name:$fname,description:$fdesc,value_type:$vtype,variants:[{key:$v1key,name:$v1name,value:$v1val},{key:$v2key,name:$v2name,value:$v2val}]}}}' \
      > "$fdata"
    api_post "POST create ${fkey}" "${API}" "$fdata"
    rm -f "$fdata"

    if [ "$FF_HTTP_CODE" = "409" ]; then
      echo "      Flag already exists (409). Recovering ID..."
      api_get "GET all flags (recover ${fkey})" "${API}"
      fid=$(cat "$FF_TMP" | jq -r '.data[]? | select(.attributes.key == "'"$fkey"'") | .id // empty' 2>/dev/null | head -1 || true)
    elif [ "$FF_HTTP_CODE" = "200" ] || [ "$FF_HTTP_CODE" = "201" ]; then
      fid=$(jq -r '.data.id // empty' "$FF_TMP" 2>/dev/null || true)
      echo "      Created (id=${fid:-unknown})"
    else
      echo "WARNING: Could not create '${fkey}' (HTTP $FF_HTTP_CODE). Configure it manually in the UI." >&2
      return 0
    fi
  fi

  [ -z "$fid" ] && echo "WARNING: No ID resolved for '${fkey}'. Skipping allocation." >&2 && return 0

  # Resolve variant IDs from flag detail
  api_get "GET detail ${fkey}" "${API}/${fid}"
  v1id=$(cat "$FF_TMP" | jq -r '.data.attributes.variants[]? | select(.key=="'"$v1key"'") | .id // empty' 2>/dev/null | head -1 || true)
  v2id=$(cat "$FF_TMP" | jq -r '.data.attributes.variants[]? | select(.key=="'"$v2key"'") | .id // empty' 2>/dev/null | head -1 || true)

  # Create 50/50 allocation and enable in the resolved environment
  if [ -n "${ENV_ID:-}" ] && [ -n "$v1id" ] && [ -n "$v2id" ]; then
    local afile; afile=$(mktemp)
    cat > "$afile" <<JSON
{
  "data": {
    "type": "allocations",
    "attributes": {
      "name": "Workshop 50/50",
      "key": "workshop-5050-${fkey}",
      "type": "FEATURE_GATE",
      "variant_weights": [
        {"variant_id": "${v1id}", "value": 50},
        {"variant_id": "${v2id}", "value": 50}
      ],
      "targeting_rules": []
    }
  }
}
JSON
    api_post "POST allocation ${fkey}" "${API}/${fid}/environments/${ENV_ID}/allocations" "$afile"
    rm -f "$afile"
    if [ "$FF_HTTP_CODE" = "200" ] || [ "$FF_HTTP_CODE" = "201" ]; then
      echo "      Allocation created (50/50)."
    else
      echo "      NOTE: Allocation returned HTTP $FF_HTTP_CODE — configure manually in the UI."
    fi

    local efile; efile=$(mktemp); echo '{}' > "$efile"
    api_post "POST enable ${fkey}" "${API}/${fid}/environments/${ENV_ID}/enable" "$efile"
    rm -f "$efile"
    echo "      Enabled (HTTP $FF_HTTP_CODE)."
  else
    echo "      Skipping allocation (ENV_ID or variant IDs not resolved). Configure manually:"
  fi

  echo "      URL: https://app.${SITE}/feature-flags/${fid}"
}

# ════════════════════════════════════════════════════════════════════════════
# Demo flags — STRING, NUMBER, and JSON types for workshop type-diversity demo
# ════════════════════════════════════════════════════════════════════════════

# Flag 2: promo-banner-message (STRING)
# Controls the top-of-page promotional banner text on the homepage.
setup_extra_flag \
  "promo-banner-message" \
  "Promo Banner Message (Storedog workshop)" \
  "Workshop demo: STRING flag — controls the homepage promotional banner copy." \
  "STRING" \
  "control"      "Control (shipping promo)"  "GET FREE SHIPPING WITH CODE SAGE" \
  "summer-sale"  "Summer Sale variant"       "🔥 SUMMER SALE: 30% OFF EVERYTHING — USE CODE SUMMER30"

# Flag 3: product-grid-columns (INTEGER)
# Controls the number of columns in the /products page grid.
setup_extra_flag \
  "product-grid-columns" \
  "Product Grid Columns (Storedog workshop)" \
  "Workshop demo: INTEGER flag — switches the product grid between 3 and 4 columns." \
  "INTEGER" \
  "standard"  "Standard (3 columns)"  "3" \
  "compact"   "Compact (4 columns)"   "4"

# Flag 4: homepage-hero-style (JSON)
# Controls the homepage hero banner background colour, text colour, and badge text.
# The JSON value is parsed by the frontend and applied via inline styles.
setup_extra_flag \
  "homepage-hero-style" \
  "Homepage Hero Style (Storedog workshop)" \
  "Workshop demo: JSON flag — drives hero bgColor, textColor, and badge via object value." \
  "JSON" \
  "control"  "Control (Datadog purple)"  '{"bgColor":"#632CA6","textColor":"#FFFFFF","badge":""}' \
  "vibrant"  "Vibrant (orange + badge)"  '{"bgColor":"#FF6B35","textColor":"#FFFFFF","badge":"NEW"}'

# ── Cleanup and summary ───────────────────────────────────────────────────────
rm -f "$FF_TMP"
echo ""
echo "=== Done ==="
echo "All 4 workshop flags processed:"
echo "  Boolean : product-card-frustration   (id=$FLAG_ID)"
echo "  String  : promo-banner-message"
echo "  Number  : product-grid-columns"
echo "  JSON    : homepage-hero-style"
echo ""
echo "Datadog Feature Flags dashboard:"
echo "  https://app.${SITE}/feature-flags"
echo ""
echo "Next steps:"
echo "  docker compose -f docker-compose.dev.yml up -d --build"
echo "  Homepage  : promo banner + hero style change on flag flip"
echo "  /products : grid column density changes on flag flip"
echo "  RUM Explorer: filter @feature_flags.<flag_key> to see variant split"
