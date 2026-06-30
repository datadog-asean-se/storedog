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

LAB_BASE_DIR="${LAB_BASE_DIR:-/root/storedog}"
REPO="https://github.com/datadog-asean-se/storedog.git"
BRANCH="workshop/featureflags-rum"
FF_DIR="/root/storedog-ff"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Storedog — Feature Flags × RUM Workshop Lab Setup  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Stop the base workshop stack ────────────────────────────────────
if [ -f "${LAB_BASE_DIR}/docker-compose.dev.yml" ]; then
  echo "[1/5] Stopping base storedog stack..."
  docker compose -f "${LAB_BASE_DIR}/docker-compose.dev.yml" down 2>/dev/null || true
  echo "      Stopped."
else
  echo "[1/5] Base storedog not found at ${LAB_BASE_DIR} — skipping stop."
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
if [ -f "${LAB_BASE_DIR}/.env" ]; then
  cp "${LAB_BASE_DIR}/.env" "${FF_DIR}/.env"
  echo "      Copied from ${LAB_BASE_DIR}/.env"
else
  echo "      WARNING: ${LAB_BASE_DIR}/.env not found."
  echo "      Ensure ${FF_DIR}/.env contains DD_API_KEY, DD_APP_KEY,"
  echo "      DD_APPLICATION_ID, DD_CLIENT_TOKEN, and STOREDOG_URL before continuing."
  read -rp "      Press Enter once ${FF_DIR}/.env is filled in, or Ctrl-C to abort..."
fi

# Expose DD_APPLICATION_ID / DD_CLIENT_TOKEN as NEXT_PUBLIC_* if they are not already set
# (the lab .env uses the non-prefixed names; Next.js needs NEXT_PUBLIC_* in the browser)
if [ -f "${FF_DIR}/.env" ]; then
  APP_ID=$(grep '^DD_APPLICATION_ID=' "${FF_DIR}/.env" | cut -d= -f2- | tr -d '"' | head -1)
  CLIENT_TOK=$(grep '^DD_CLIENT_TOKEN=' "${FF_DIR}/.env" | cut -d= -f2- | tr -d '"' | head -1)
  if [ -n "$APP_ID" ] && ! grep -q '^NEXT_PUBLIC_DD_APPLICATION_ID=' "${FF_DIR}/.env"; then
    echo "NEXT_PUBLIC_DD_APPLICATION_ID=${APP_ID}" >> "${FF_DIR}/.env"
    echo "      Added NEXT_PUBLIC_DD_APPLICATION_ID to .env"
  fi
  if [ -n "$CLIENT_TOK" ] && ! grep -q '^NEXT_PUBLIC_DD_CLIENT_TOKEN=' "${FF_DIR}/.env"; then
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
