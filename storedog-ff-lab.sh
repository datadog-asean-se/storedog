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
echo "[1/6] Stopping any running storedog stacks..."

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
echo "[2/6] Setting up workshop repo at ${FF_DIR}..."
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
echo "[3/6] Copying lab credentials..."
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
echo "[4/6] Creating Datadog Feature Flags in your lab org..."
cd "$FF_DIR"
# Source credentials for the setup script
set -o allexport; source .env; set +o allexport
bash scripts/setup-feature-flags.sh

# ── Step 5: Start the Feature Flags stack ────────────────────────────────────
echo "[5/6] Starting Feature Flags × RUM storedog stack..."
cd "$FF_DIR"

# Default to the pre-built workshop compose; fall back to dev only if pull fails.
WORKSHOP_COMPOSE="docker-compose.workshop.yml"
COMPOSE_FILE="$WORKSHOP_COMPOSE"

echo "      Pulling pre-built workshop images..."
if docker compose -f "$WORKSHOP_COMPOSE" pull --quiet 2>/dev/null; then
  echo "      Pull successful — using pre-built images (fast path)."
  docker compose -f "$COMPOSE_FILE" up -d
else
  echo "      Pre-built image unavailable — building frontend from source (~2 min)."
  COMPOSE_FILE="docker-compose.dev.yml"
  docker compose -f "$COMPOSE_FILE" up -d --build frontend
fi

# ── Step 6: nginx injection + frontend readiness ─────────────────────────────
# The ECR nginx image ignores volume-mounted templates; we copy and re-render
# inside the running container.  Only attempt after nginx is confirmed running,
# with up to 3 retries (5 s apart) before giving up.
echo ""
echo "[6/6] Waiting for nginx and frontend to be ready..."

NGINX_INJECTED=0
for _attempt in 1 2 3; do
  NGINX_RUNNING=$(docker inspect --format '{{.State.Running}}' storedog-ff-service-proxy-1 2>/dev/null || echo "false")
  if [ "$NGINX_RUNNING" != "true" ]; then
    echo "      nginx not yet running — waiting 5s (attempt ${_attempt}/3)..."
    sleep 5
    continue
  fi
  echo "      nginx running — injecting routing config (attempt ${_attempt}/3)..."
  if docker cp "$FF_DIR/services/nginx/default.conf.template" \
        storedog-ff-service-proxy-1:/etc/nginx/conf.d/default.conf.template 2>/dev/null \
  && docker exec storedog-ff-service-proxy-1 sh -c "
       export NGINX_RESOLVER=127.0.0.11
       export ADS_A_UPSTREAM=ads-java:8080
       export ADS_SERVICE_B_BLOCK=''
       export UPSTREAM_CONFIG='server ads-java:8080;'
       envsubst '\$NGINX_RESOLVER \$ADS_A_UPSTREAM \$ADS_B_UPSTREAM \$UPSTREAM_CONFIG \$ADS_SERVICE_B_BLOCK' \
         < /etc/nginx/conf.d/default.conf.template \
         > /etc/nginx/conf.d/default.conf
     " 2>/dev/null \
  && docker exec storedog-ff-service-proxy-1 nginx -s reload 2>/dev/null; then
    echo "      ✓ nginx routing config injected and reloaded."
    NGINX_INJECTED=1
    break
  fi
  echo "      Inject attempt ${_attempt}/3 failed — retrying in 5s..."
  sleep 5
done
[ "$NGINX_INJECTED" -eq 0 ] && echo "      ⚠ nginx config injection failed after 3 attempts — check: docker logs storedog-ff-service-proxy-1"

MAX_WAIT=120
ELAPSED=0
INTERVAL=5
READY=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost 2>/dev/null || true)
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    READY=1; break
  fi
  printf "      Waiting for frontend... HTTP %s (%ss elapsed)\r" "$HTTP_CODE" "$ELAPSED"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "$READY" -eq 1 ]; then
  echo "      ✓ Frontend is up and serving traffic (HTTP $HTTP_CODE)"
else
  echo "      ⚠ Frontend did not respond within ${MAX_WAIT}s."
  echo "      Check: docker compose -f $FF_DIR/$COMPOSE_FILE logs frontend"
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
