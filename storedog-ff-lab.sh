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

# ── Step 1: Stop any existing storedog stack + free port 80 ─────────────────
echo "[1/5] Stopping any running storedog stacks..."

# Try the detected base dir first
if [ -f "${LAB_BASE_DIR}/docker-compose.dev.yml" ]; then
  echo "      Found compose at ${LAB_BASE_DIR} — stopping..."
  docker compose -f "${LAB_BASE_DIR}/docker-compose.dev.yml" down 2>/dev/null || true
fi

# Also scan all running docker-compose projects for anything using port 80
for project_dir in $(docker inspect $(docker ps -q) 2>/dev/null \
    | jq -r '.[].Config.Labels["com.docker.compose.project.working_dir"] // empty' 2>/dev/null \
    | sort -u); do
  if [ -n "$project_dir" ] && [ "$project_dir" != "$FF_DIR" ]; then
    for cf in docker-compose.dev.yml docker-compose.yml; do
      if [ -f "${project_dir}/${cf}" ]; then
        echo "      Stopping compose project at ${project_dir}..."
        docker compose -f "${project_dir}/${cf}" down 2>/dev/null || true
        break
      fi
    done
  fi
done

# Last resort: kill any container bound to port 80
PORT80=$(docker ps --filter "publish=80" -q 2>/dev/null)
if [ -n "$PORT80" ]; then
  echo "      Stopping container(s) still on port 80: $PORT80"
  docker stop $PORT80 2>/dev/null || true
fi
echo "      Done."

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

# Always use docker-compose.dev.yml — it mounts the source from disk so
# code fixes take effect without rebuilding the image. The workshop compose
# (docker-compose.workshop.yml) requires the GHCR frontend image to be public.
COMPOSE_FILE="docker-compose.dev.yml"

# Try the pre-built workshop compose first (fast pull, no build needed).
# Falls back to dev compose (build from source) if the image isn't available.
WORKSHOP_COMPOSE="docker-compose.workshop.yml"
echo "      Pulling pre-built workshop images..."
if docker compose -f "$WORKSHOP_COMPOSE" pull --quiet 2>/dev/null; then
  echo "      Pull successful — using pre-built images (fast path)."
  COMPOSE_FILE="$WORKSHOP_COMPOSE"
  docker compose -f "$COMPOSE_FILE" up -d
else
  echo "      Pre-built image unavailable — building frontend from source (~2 min)."
  docker compose -f "$COMPOSE_FILE" up -d --build frontend
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  All done! Your Feature Flags × RUM lab is running.          ║"
echo "║                                                               ║"
echo "║  App:          http://localhost (or your Instruqt lab URL)    ║"
echo "║  Homepage:     /     — promo banner + hero style flags        ║"
echo "║  Products:     /products  — card frustration + grid columns   ║"
echo "║  RUM Explorer: Filter @feature_flags.*                        ║"
echo "║                                                               ║"
echo "║  To update:  git -C ${FF_DIR} pull origin workshop/featureflags-rum ║"
echo "║              docker restart storedog-ff-frontend-1            ║"
echo "║  To stop:    docker compose -f ${FF_DIR}/\${COMPOSE_FILE} down ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
