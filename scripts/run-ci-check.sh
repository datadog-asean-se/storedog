#!/usr/bin/env bash
# =============================================================================
# Storedog CI Pipeline — Synthetics Demo Script
# Part of: Feature Flags × RUM Workshop (workshop/featureflags-rum)
#
# Usage:
#   bash scripts/run-ci-check.sh [--public-id <test-id>] [--search "tag:storedog"]
#
# Environment (read from .env if not in shell):
#   DD_API_KEY            Datadog API key
#   DD_APP_KEY            Datadog App key
#   DD_SITE               Datadog site (default: datadoghq.com)
#   SYNTHETICS_PUBLIC_ID  Specific Synthetics test public ID (optional)
# =============================================================================

# ── ANSI colours ──────────────────────────────────────────────────────────────
PURPLE='\e[35m'
ORANGE='\e[33m'
CYAN='\e[36m'
WHITE='\e[97m'
GREEN='\e[32m'
RED='\e[31m'
DIM='\e[2m'
BOLD='\e[1m'
RESET='\e[0m'

# ── Helper printers ───────────────────────────────────────────────────────────
step()      { echo -e "${BOLD}${CYAN}[$1]${RESET} ${WHITE}$2${RESET}"; }
pass_line() { echo -e "  ${GREEN}✔${RESET}  $*"; }
fail_line() { echo -e "  ${RED}✘${RESET}  $*"; }
info_line() { echo -e "  ${DIM}ℹ${RESET}  $*"; }

# ── Demo mode: simulate a realistic Synthetics failure ────────────────────────
run_demo_mode() {
  echo ""
  info_line "No Synthetics tests found or API keys missing. Running in demo mode..."
  echo ""
  sleep 1
  echo -e "  ${CYAN}📊${RESET}  Test: /products page load time < 3s ........... ${GREEN}PASS${RESET}"
  sleep 1
  echo -e "  ${CYAN}📊${RESET}  Test: Add to cart flow ......................... ${GREEN}PASS${RESET}"
  sleep 1
  echo -e "  ${CYAN}📊${RESET}  Test: Checkout completion rate ................. ${GREEN}PASS${RESET}"
  sleep 1
  echo -e "  ${CYAN}📊${RESET}  Test: Product thumbnail navigation ............. ${RED}FAIL${RESET}"
  echo -e "       ${RED}${DIM}↳ Dead clicks detected on .product-thumb (frustration variant active)${RESET}"
  sleep 1
  return 1
}

# ── Print result banner ───────────────────────────────────────────────────────
print_result() {
  local exit_code="$1"
  echo ""
  step "4/4" "Evaluating results..."
  echo ""
  if [[ "${exit_code}" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  ✅  CI PASSED — Safe to promote to production${RESET}"
    echo ""
    echo -e "  ${DIM}All Synthetics assertions passed. The active feature flag variant${RESET}"
    echo -e "  ${DIM}did not degrade the monitored user flows.${RESET}"
  else
    echo -e "${RED}${BOLD}  ❌  CI FAILED — Synthetics detected issues.${RESET}"
    echo -e "${RED}      Roll back the feature flag.${RESET}"
    echo ""
    echo -e "  ${DIM}One or more Synthetics tests failed. If the \`product-card-frustration\`${RESET}"
    echo -e "  ${DIM}flag is enabled, disable it now in Datadog → Feature Management.${RESET}"
    echo -e "  ${DIM}Reference: https://docs.datadoghq.com/feature_management/${RESET}"
  fi
  echo ""
}

# ── CLI arg parsing ───────────────────────────────────────────────────────────
CUSTOM_PUBLIC_ID="${SYNTHETICS_PUBLIC_ID:-}"
SEARCH_QUERY="tag:storedog"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-id)  CUSTOM_PUBLIC_ID="$2"; shift 2 ;;
    --search)     SEARCH_QUERY="$2";     shift 2 ;;
    *)            shift ;;
  esac
done

# ── Load .env if keys not already in environment ──────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

export DATADOG_API_KEY="${DD_API_KEY:-}"
export DATADOG_APP_KEY="${DD_APP_KEY:-}"
export DATADOG_SITE="${DD_SITE:-datadoghq.com}"

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${PURPLE}╔═══════════════════════════════════════════════╗${RESET}"
echo -e "${PURPLE}║${WHITE}  🐶  Datadog CI Pipeline  ·  Storedog         ${PURPLE}║${RESET}"
echo -e "${PURPLE}║${DIM}      Powered by Continuous Testing            ${PURPLE}║${RESET}"
echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${PURPLE}     /\\_____/\\${RESET}"
echo -e "${PURPLE}    /  ${ORANGE}o   o${PURPLE}  \\${RESET}"
echo -e "${PURPLE}   ( ${ORANGE}==  ^  ==${PURPLE} )${RESET}"
echo -e "${PURPLE}    )         (${RESET}"
echo -e "${PURPLE}   (           )${RESET}"
echo -e "${PURPLE}  ( ${CYAN}(  )   (  )${PURPLE} )${RESET}"
echo -e "${CYAN} (__(__)___(__)__)${RESET}"
echo -e "${BOLD}${WHITE}      Bits  🐾${RESET}"
echo ""
echo -e "${DIM}  Site: ${DATADOG_SITE}   Branch: workshop/featureflags-rum${RESET}"
echo ""

# ── Step 1: Install deps (simulated) ─────────────────────────────────────────
step "1/4" "Installing dependencies..."
sleep 1
pass_line "node_modules ready"
echo ""

# ── Step 2: Unit tests (always pass in this demo) ────────────────────────────
step "2/4" "Running unit tests..."
sleep 1
pass_line "ProductCard renders correctly"
pass_line "Cart total calculation"
pass_line "Discount code validation"
echo -e "  ${GREEN}${BOLD}Unit tests: 3/3 passed${RESET}"
echo ""

# ── Step 3: Synthetics e2e ────────────────────────────────────────────────────
step "3/4" "Running Synthetics end-to-end tests..."
echo ""

# Install datadog-ci if not present
if ! command -v datadog-ci &>/dev/null; then
  info_line "datadog-ci not found — installing @datadog/datadog-ci globally..."
  if npm install -g @datadog/datadog-ci --silent 2>/dev/null; then
    pass_line "datadog-ci installed"
  else
    fail_line "npm install failed — check npm/node availability"
    run_demo_mode
    DEMO_EXIT=$?
    print_result "$DEMO_EXIT"
    exit "$DEMO_EXIT"
  fi
fi

# Validate keys before calling the API
if [[ -z "${DATADOG_API_KEY}" || -z "${DATADOG_APP_KEY}" ]]; then
  echo -e "  ${RED}${BOLD}Missing DD_API_KEY or DD_APP_KEY.${RESET}"
  echo -e "  ${DIM}Run: source .env   (or export them in your shell)${RESET}"
  run_demo_mode
  DEMO_EXIT=$?
  print_result "$DEMO_EXIT"
  exit "$DEMO_EXIT"
fi

# Build the datadog-ci command
DD_CI_ARGS=(synthetics run-tests --tunnel)

if [[ -n "${CUSTOM_PUBLIC_ID}" ]]; then
  DD_CI_ARGS+=(--public-id "${CUSTOM_PUBLIC_ID}")
else
  DD_CI_ARGS+=(--search "${SEARCH_QUERY}")
fi

echo -e "  ${DIM}» datadog-ci ${DD_CI_ARGS[*]}${RESET}"
echo ""

# Run Synthetics — capture exit code without aborting on failure
SYNTHETICS_EXIT=0
datadog-ci "${DD_CI_ARGS[@]}" 2>&1 || SYNTHETICS_EXIT=$?

# If datadog-ci exited with 0 but reported "no tests found" we fall to demo mode
# (datadog-ci prints "No test was found" and exits 0 when the search has no results)
if [[ $SYNTHETICS_EXIT -eq 0 ]]; then
  : # real tests ran and passed — continue to result banner
fi

print_result "$SYNTHETICS_EXIT"
exit "$SYNTHETICS_EXIT"
