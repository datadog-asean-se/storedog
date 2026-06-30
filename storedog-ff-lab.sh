#!/usr/bin/env bash
# storedog-ff-lab.sh
# Switches the lab from the base Storedog stack to the Feature Flags × RUM workshop branch.
# Run this from /root (the lab home directory).
#
# What it does:
#   1. Stops the running base-workshop storedog stack
#   2. Clones the workshop branch (or updates it if already cloned)
#   3. Copies your existing lab credentials (.env) into the new directory
#   4. Creates the Datadog Feature Flag in your lab org
#   5. Starts the feature-flag-enabled stack
set -euo pipefail

REPO="https://github.com/datadog-asean-se/storedog.git"
BRANCH="workshop/featureflags-rum"
FF_DIR="/root/storedog-ff"

# ── Auto-detect base storedog dir ────────────────────────────────────────────
if [ -n "${LAB_BASE_DIR:-}" ]; then
  : # honour explicit override
else
  LAB_BASE_DIR=""
  for candidate in /root/storedog /root/lab /home/lab /workspace /opt/storedog; do
    if [ -f "${candidate}/docker-compose.dev.yml" ] || [ -f "${candidate}/.env" ]; then
      LAB_BASE_DIR="$candidate"; break
    fi
  done
  LAB_BASE_DIR="${LAB_BASE_DIR:-/root/storedog}"  # last-resort default
fi

# ── Auto-detect the lab .env file ────────────────────────────────────────────
LAB_ENV=""
for candidate in \
    "${LAB_BASE_DIR}/.env" \
    "/root/lab/.env" \
    "/root/.env" \
    "/home/lab/.env" \
    "/workspace/.env"; do
  if [ -f "$candidate" ]; then LAB_ENV="$candidate"; break; fi
done

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Storedog — Feature Flags × RUM Workshop Lab Setup  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Stop the base workshop stack ────────────────────────────────────
if [ -f "${LAB_BASE_DIR}/docker-compose.dev.yml" ]; then
  echo "[1/5] Stopping base storedog stack at ${LAB_BASE_DIR}..."
  docker compose -f "${LAB_BASE_DIR}/docker-compose.dev.yml" down 2>/dev/null || true
  echo "      Stopped."
else
  echo "[1/5] Base storedog compose not found at ${LAB_BASE_DIR} — skipping stop."
  echo "      (Set LAB_BASE_DIR=/path/to/storedog to override)"
fi

# ── Step 2: Clone or update the workshop branch ──────────────────────────────
echo "[2/5] Setting up workshop repo at ${FF_DIR}..."
if [ -d "${FF_DIR}/.git" ]; then
  echo "      Directory exists — pulling latest..."
  git -C "$FF_DIR" fetch origin "$BRANCH"
  git -C "$FF_DIR" checkout "$BRANCH"
  git -C "$FF_DIR" reset --hard "origin/$BRANCH"
else
  git clone --branch "$BRANCH" --single-branch "$REPO" "$FF_DIR"
fi
echo "      Branch: $(git -C "$FF_DIR" rev-parse --abbrev-ref HEAD)"
echo "      Commit: $(git -C "$FF_DIR" log -1 --oneline)"

# ── Step 3: Copy lab credentials ────────────────────────────────────────────
echo "[3/5] Copying lab credentials..."
if [ -n "$LAB_ENV" ]; then
  cp "$LAB_ENV" "${FF_DIR}/.env"
  echo "      Copied from ${LAB_ENV}"
elif [ -f "${FF_DIR}/.env" ]; then
  echo "      No source .env found — using existing ${FF_DIR}/.env"
else
  echo "      WARNING: could not find a lab .env file."
  echo "      Searched: \${LAB_BASE_DIR}/.env, /root/lab/.env, /root/.env, /workspace/.env"
  echo "      Ensure ${FF_DIR}/.env contains DD_API_KEY, DD_APP_KEY,"
  echo "      DD_APPLICATION_ID, DD_CLIENT_TOKEN, and STOREDOG_URL."
  echo "      Set LAB_ENV=/path/to/.env to point directly to your env file."
  read -rp "      Press Enter once ${FF_DIR}/.env is filled in, or Ctrl-C to abort..."
fi

# Expose DD_APPLICATION_ID / DD_CLIENT_TOKEN as NEXT_PUBLIC_* if they are not already set
# (the lab .env uses the non-prefixed names; Next.js needs NEXT_PUBLIC_* in the browser)
# Note: grep || true is intentional — grep exits 1 when no match, which would abort under set -e
if [ -f "${FF_DIR}/.env" ]; then
  APP_ID=$(grep '^DD_APPLICATION_ID=' "${FF_DIR}/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1 || true)
  CLIENT_TOK=$(grep '^DD_CLIENT_TOKEN=' "${FF_DIR}/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1 || true)
  if [ -n "$APP_ID" ] && ! grep -q '^NEXT_PUBLIC_DD_APPLICATION_ID=' "${FF_DIR}/.env" 2>/dev/null; then
    echo "NEXT_PUBLIC_DD_APPLICATION_ID=${APP_ID}" >> "${FF_DIR}/.env"
    echo "      Added NEXT_PUBLIC_DD_APPLICATION_ID to .env"
  fi
  if [ -n "$CLIENT_TOK" ] && ! grep -q '^NEXT_PUBLIC_DD_CLIENT_TOKEN=' "${FF_DIR}/.env" 2>/dev/null; then
    echo "NEXT_PUBLIC_DD_CLIENT_TOKEN=${CLIENT_TOK}" >> "${FF_DIR}/.env"
    echo "      Added NEXT_PUBLIC_DD_CLIENT_TOKEN to .env"
  fi
fi

# ── Step 4: Create Datadog Feature Flag ─────────────────────────────────────
echo "[4/5] Creating Datadog Feature Flag in your lab org..."
cd "$FF_DIR"
# Source credentials for the setup script
set -o allexport; source .env; set +o allexport
bash scripts/setup-feature-flags.sh

# ── Step 5: Start the Feature Flags stack ────────────────────────────────────
echo "[5/5] Starting Feature Flags × RUM storedog stack..."
cd "$FF_DIR"
docker compose -f docker-compose.dev.yml up -d --build

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  All done! Your Feature Flags × RUM lab is running.          ║"
echo "║                                                               ║"
echo "║  App:          http://localhost (or your lab URL)             ║"
echo "║  Products:     /products  — flag switches card variant        ║"
echo "║  RUM Explorer: Filter @feature_flags.product-card-frustration ║"
echo "║                                                               ║"
echo "║  To stop:  docker compose -f ${FF_DIR}/docker-compose.dev.yml down  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
