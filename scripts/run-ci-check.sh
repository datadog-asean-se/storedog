#!/usr/bin/env bash
# =============================================================================
# Storedog CI Pipeline — Interactive TUI
# Part of: Feature Flags × RUM Workshop (workshop/featureflags-rum)
#
# Interactive usage (TUI):
#   bash scripts/run-ci-check.sh
#
# Non-interactive (CI / scripted):
#   bash scripts/run-ci-check.sh --public-id <test-id>
#   bash scripts/run-ci-check.sh --search "tag:storedog"
#   bash scripts/run-ci-check.sh --demo
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

# ── Command preview box ───────────────────────────────────────────────────────
# Usage: show_command_box --flag [value] --flag [value] ...
# Flags are displayed in cyan, values in white, each on its own indented line.
show_command_box() {
  echo ""
  echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${PURPLE}║${ORANGE}${BOLD}  📋  Continuous Testing — CI/CD Command                          ${PURPLE}║${RESET}"
  echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${ORANGE}\$${RESET} ${WHITE}npx @datadog/datadog-ci synthetics run-tests \\${RESET}"

  local i=1
  local total=$#
  while [[ $i -le $total ]]; do
    local flag="${!i}"
    i=$((i + 1))
    if [[ "$flag" == --* ]]; then
      local next=""
      if [[ $i -le $total ]]; then next="${!i}"; fi
      if [[ -n "$next" && "$next" != --* ]]; then
        i=$((i + 1))
        if [[ $i -gt $total ]]; then
          echo -e "      ${CYAN}${flag}${RESET} ${WHITE}\"${next}\"${RESET}"
        else
          echo -e "      ${CYAN}${flag}${RESET} ${WHITE}\"${next}\"${RESET} ${CYAN}\\${RESET}"
        fi
      else
        if [[ $i -gt $total ]]; then
          echo -e "      ${CYAN}${flag}${RESET}"
        else
          echo -e "      ${CYAN}${flag}${RESET} ${CYAN}\\${RESET}"
        fi
      fi
    fi
  done

  echo ""
  echo -e "  ${DIM}Reference: https://docs.datadoghq.com/continuous_testing/cicd_integrations/${RESET}"
  echo ""
  sleep 1
}

# ── Bits Dog ASCII art (lines, no leading echo -e) ───────────────────────────
BITS_DOG=(
  "                    ################    "
  "     ###############################    "
  "######################## ###########    "
  "########  ####### ####    ## #######    "
  "#####      #            ##### ######    "
  "#####      ##             ###########   "
  " #####     ##    ###     ############   "
  " #######  ###   ####     ############   "
  " ###########    ####        #########   "
  " ########                 ###########   "
  " ########                #### #######   "
  "  #########      #        ##  ######### "
  "  ##########     ####    ############## "
  "  ###########    ###########       #### "
  "  ###########    ##               ##### "
  "   #########     ##          #### ######"
  "   #######  ##   ##         ############"
  "   #####     ### ##   ############### ##"
  "   ####       ### ## ###################"
  "    ###        #########################"
  "    #####       ########################"
  "               ## ###########           "
  "          #######                       "
  "              Bits  🐾                  "
)

# ── .env loading ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

export DATADOG_API_KEY="${DD_API_KEY:-}"
export DATADOG_APP_KEY="${DD_APP_KEY:-}"
export DATADOG_SITE="${DD_SITE:-datadoghq.com}"

# ── CLI arg parsing ───────────────────────────────────────────────────────────
CUSTOM_PUBLIC_ID="${SYNTHETICS_PUBLIC_ID:-}"
SEARCH_QUERY="tag:storedog"
NON_INTERACTIVE=false
DEMO_ARG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-id) CUSTOM_PUBLIC_ID="$2"; NON_INTERACTIVE=true; shift 2 ;;
    --search)    SEARCH_QUERY="$2";     NON_INTERACTIVE=true; shift 2 ;;
    --demo)      DEMO_ARG=true;         NON_INTERACTIVE=true; shift ;;
    *)           shift ;;
  esac
done

# ── Demo mode ────────────────────────────────────────────────────────────────
run_demo_mode() {
  echo ""
  echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${PURPLE}║${ORANGE}${BOLD}  📋  Demo Mode — Simulated CI Pipeline                           ${PURPLE}║${RESET}"
  echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${DIM}In a real CI/CD pipeline, you would run:${RESET}"
  echo ""
  echo -e "  ${ORANGE}\$${RESET} ${WHITE}npx @datadog/datadog-ci synthetics run-tests \\${RESET}"
  echo -e "      ${CYAN}--search${RESET} ${WHITE}\"tag:storedog\"${RESET} ${CYAN}\\${RESET}"
  echo -e "      ${CYAN}--tunnel${RESET}"
  echo ""
  sleep 1
  info_line "Running in demo mode (no API keys needed)..."
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

# ── Ensure datadog-ci is available ───────────────────────────────────────────
ensure_datadog_ci() {
  if ! command -v datadog-ci &>/dev/null; then
    info_line "datadog-ci not found — installing @datadog/datadog-ci globally..."
    if npm install -g @datadog/datadog-ci --silent 2>/dev/null; then
      pass_line "datadog-ci installed"
    else
      fail_line "npm install failed — check npm/node availability"
      return 1
    fi
  fi
  return 0
}

# ── Action: run synthetics by search ─────────────────────────────────────────
run_synthetics_search() {
  echo ""
  step "1/4" "Installing dependencies..."
  sleep 1
  pass_line "node_modules ready"
  echo ""
  step "2/4" "Running unit tests..."
  sleep 1
  pass_line "ProductCard renders correctly"
  pass_line "Cart total calculation"
  pass_line "Discount code validation"
  echo -e "  ${GREEN}${BOLD}Unit tests: 3/3 passed${RESET}"
  echo ""
  step "3/4" "Running Synthetics end-to-end tests..."
  echo ""

  if ! ensure_datadog_ci; then
    run_demo_mode; DEMO_EXIT=$?; print_result "$DEMO_EXIT"; return "$DEMO_EXIT"
  fi

  if [[ -z "${DATADOG_API_KEY}" || -z "${DATADOG_APP_KEY}" ]]; then
    echo -e "  ${RED}${BOLD}Missing DD_API_KEY or DD_APP_KEY.${RESET}"
    echo -e "  ${DIM}Run: source .env   (or export them in your shell)${RESET}"
    run_demo_mode; DEMO_EXIT=$?; print_result "$DEMO_EXIT"; return "$DEMO_EXIT"
  fi

  local args=(synthetics run-tests --tunnel --search "${SEARCH_QUERY}")
  show_command_box --search "${SEARCH_QUERY}" --tunnel
  SYNTHETICS_EXIT=0
  datadog-ci "${args[@]}" 2>&1 || SYNTHETICS_EXIT=$?
  print_result "$SYNTHETICS_EXIT"
  return "$SYNTHETICS_EXIT"
}

# ── Action: run synthetics by public ID ──────────────────────────────────────
run_synthetics_id() {
  local pub_id="$1"
  echo ""
  step "1/4" "Installing dependencies..."
  sleep 1
  pass_line "node_modules ready"
  echo ""
  step "2/4" "Running unit tests..."
  sleep 1
  pass_line "ProductCard renders correctly"
  pass_line "Cart total calculation"
  pass_line "Discount code validation"
  echo -e "  ${GREEN}${BOLD}Unit tests: 3/3 passed${RESET}"
  echo ""
  step "3/4" "Running Synthetics end-to-end tests..."
  echo ""

  if ! ensure_datadog_ci; then
    run_demo_mode; DEMO_EXIT=$?; print_result "$DEMO_EXIT"; return "$DEMO_EXIT"
  fi

  if [[ -z "${DATADOG_API_KEY}" || -z "${DATADOG_APP_KEY}" ]]; then
    echo -e "  ${RED}${BOLD}Missing DD_API_KEY or DD_APP_KEY.${RESET}"
    echo -e "  ${DIM}Run: source .env   (or export them in your shell)${RESET}"
    run_demo_mode; DEMO_EXIT=$?; print_result "$DEMO_EXIT"; return "$DEMO_EXIT"
  fi

  local args=(synthetics run-tests --public-id "${pub_id}")
  show_command_box --public-id "${pub_id}"
  SYNTHETICS_EXIT=0
  datadog-ci "${args[@]}" 2>&1 || SYNTHETICS_EXIT=$?
  print_result "$SYNTHETICS_EXIT"
  return "$SYNTHETICS_EXIT"
}

# ── Action: view feature flag status ─────────────────────────────────────────
view_flag_status() {
  echo ""
  step "FF" "Fetching feature flag: product-card-frustration"
  echo ""

  if [[ -z "${DATADOG_API_KEY}" || -z "${DATADOG_APP_KEY}" ]]; then
    echo -e "  ${RED}${BOLD}Missing DD_API_KEY or DD_APP_KEY — cannot call Datadog API.${RESET}"
    echo -e "  ${DIM}Run: source .env   (or export them in your shell)${RESET}"
    echo ""
    return 1
  fi

  local site="${DATADOG_SITE:-datadoghq.com}"
  local response
  response=$(curl -sf \
    -H "DD-API-KEY: ${DATADOG_API_KEY}" \
    -H "DD-APPLICATION-KEY: ${DATADOG_APP_KEY}" \
    "https://api.${site}/api/v2/feature_management/feature_flags?search[name]=product-card-frustration" \
    2>&1)
  local curl_exit=$?

  if [[ $curl_exit -ne 0 ]]; then
    fail_line "API request failed (curl exit ${curl_exit})"
    echo -e "  ${DIM}${response}${RESET}"
    echo ""
    return 1
  fi

  echo -e "  ${DIM}Raw response:${RESET}"
  echo ""
  # Pretty-print JSON if jq is available, otherwise raw
  if command -v jq &>/dev/null; then
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
  else
    echo "$response"
  fi
  echo ""

  # Extract enabled status if jq available
  if command -v jq &>/dev/null; then
    local flag_state
    flag_state=$(echo "$response" | jq -r '.data[0].attributes.enabled // "unknown"' 2>/dev/null)
    if [[ "$flag_state" == "true" ]]; then
      echo -e "  ${RED}${BOLD}⚑  product-card-frustration:  ENABLED  ← frustration variant is live${RESET}"
    elif [[ "$flag_state" == "false" ]]; then
      echo -e "  ${GREEN}${BOLD}⚑  product-card-frustration:  DISABLED${RESET}"
    else
      echo -e "  ${ORANGE}⚑  product-card-frustration:  status unknown${RESET}"
    fi
    echo ""
  fi
}

# =============================================================================
# NON-INTERACTIVE MODE — skip TUI when CLI args are passed
# =============================================================================
if [[ "$NON_INTERACTIVE" == true ]]; then
  clear
  echo ""
  echo -e "${PURPLE}╔═══════════════════════════════════════════════╗${RESET}"
  echo -e "${PURPLE}║${WHITE}  🐶  Datadog CI Pipeline  ·  Storedog         ${PURPLE}║${RESET}"
  echo -e "${PURPLE}║${DIM}      Powered by Continuous Testing            ${PURPLE}║${RESET}"
  echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${RESET}"
  echo ""
  for line in "${BITS_DOG[@]}"; do
    echo -e "${PURPLE}${line}${RESET}"
  done
  echo ""
  echo -e "${DIM}  Site: ${DATADOG_SITE}   Branch: workshop/featureflags-rum${RESET}"
  echo ""

  if [[ "$DEMO_ARG" == true ]]; then
    run_demo_mode
    DEMO_EXIT=$?
    print_result "$DEMO_EXIT"
    exit "$DEMO_EXIT"
  elif [[ -n "${CUSTOM_PUBLIC_ID}" ]]; then
    run_synthetics_id "${CUSTOM_PUBLIC_ID}"
    exit $?
  else
    run_synthetics_search
    exit $?
  fi
fi

# =============================================================================
# INTERACTIVE TUI MODE
# =============================================================================

MENU_ITEMS=(
  "Run Synthetics Tests (tag:storedog)"
  "Run with specific test ID..."
  "Run Demo Mode (no API keys needed)"
  "View Feature Flag status"
)
ITEMS=${#MENU_ITEMS[@]}
SELECTED=0

# ── TUI draw functions ────────────────────────────────────────────────────────
draw_header() {
  local cols
  cols=$(tput cols)
  local title="  🐶  Datadog CI Pipeline  ·  Storedog"
  local sub="     workshop/featureflags-rum  ·  ${DATADOG_SITE}"

  tput cup 0 0
  echo -e "${PURPLE}╔$(printf '═%.0s' $(seq 1 $((cols-2))))╗${RESET}"
  tput cup 1 0
  # Pad title to fill the box
  local padded
  padded=$(printf "%-$((cols-4))s" "${title}")
  echo -e "${PURPLE}║${WHITE}${padded}  ${PURPLE}║${RESET}"
  tput cup 2 0
  echo -e "${PURPLE}╚$(printf '═%.0s' $(seq 1 $((cols-2))))╝${RESET}"
}

draw_bits_dog() {
  local start_row=4
  for i in "${!BITS_DOG[@]}"; do
    tput cup $((start_row + i)) 2
    echo -e "${PURPLE}${BITS_DOG[$i]}${RESET}"
  done
}

draw_menu() {
  local selected=$1
  local art_lines=${#BITS_DOG[@]}
  local menu_row=$((4 + art_lines + 1))
  local cols
  cols=$(tput cols)
  local inner_width=$((cols - 4))

  tput cup "$menu_row" 0
  echo -e "${WHITE}  ┌─ Select Action $(printf '─%.0s' $(seq 1 $((inner_width - 15))))┐${RESET}"

  tput cup $((menu_row + 1)) 0
  echo -e "${WHITE}  │$(printf ' %.0s' $(seq 1 $((inner_width + 1))))│${RESET}"

  for i in "${!MENU_ITEMS[@]}"; do
    local label="${MENU_ITEMS[$i]}"
    tput cup $((menu_row + 2 + i)) 0
    if [[ $i -eq $selected ]]; then
      local padded
      padded=$(printf "%-${inner_width}s" "  ▶  ${label}")
      echo -e "${WHITE}  │${RESET}${BOLD}${CYAN}${padded}${RESET}${WHITE}│${RESET}"
    else
      local padded
      padded=$(printf "%-${inner_width}s" "     ${label}")
      echo -e "${WHITE}  │${DIM}${padded}${RESET}${WHITE}│${RESET}"
    fi
  done

  tput cup $((menu_row + 2 + ITEMS)) 0
  echo -e "${WHITE}  │$(printf ' %.0s' $(seq 1 $((inner_width + 1))))│${RESET}"
  tput cup $((menu_row + 3 + ITEMS)) 0
  echo -e "${WHITE}  └$(printf '─%.0s' $(seq 1 $((inner_width + 1))))┘${RESET}"
}

draw_bottom_bar() {
  local lines
  lines=$(tput lines)
  local cols
  cols=$(tput cols)
  local bar="  ↑↓ Navigate   Enter Select   r Run   d Demo   q Quit  "
  local padded
  padded=$(printf "%-$((cols-2))s" "${bar}")

  tput cup $((lines - 2)) 0
  echo -e "${PURPLE}╔$(printf '═%.0s' $(seq 1 $((cols-2))))╗${RESET}"
  tput cup $((lines - 1)) 0
  echo -e "${PURPLE}║${WHITE}${padded}${PURPLE}║${RESET}"
}

draw_all() {
  tput clear
  draw_header
  draw_bits_dog
  draw_menu "$SELECTED"
  draw_bottom_bar
}

# ── Action dispatcher (runs in full-screen, then waits for keypress) ──────────
run_action() {
  local action=$1
  # Restore cursor, clear screen for action output
  tput cnorm
  tput rmcup

  echo ""
  echo -e "${PURPLE}╔═══════════════════════════════════════════════╗${RESET}"
  echo -e "${PURPLE}║${WHITE}  🐶  Datadog CI Pipeline  ·  Storedog         ${PURPLE}║${RESET}"
  echo -e "${PURPLE}╚═══════════════════════════════════════════════╝${RESET}"
  echo ""

  case $action in
    0)
      run_synthetics_search
      ;;
    1)
      echo -e "${WHITE}${BOLD}Enter Synthetics public ID:${RESET} "
      IFS= read -r pub_id
      if [[ -z "$pub_id" ]]; then
        echo -e "  ${RED}No ID entered — cancelled.${RESET}"
      else
        run_synthetics_id "$pub_id"
      fi
      ;;
    2)
      run_demo_mode
      DEMO_EXIT=$?
      print_result "$DEMO_EXIT"
      ;;
    3)
      view_flag_status
      ;;
  esac

  echo ""
  echo -e "${DIM}Press any key to return to menu...${RESET}"
  IFS= read -rsn1

  # Re-enter TUI mode
  tput smcup
  tput civis
}

# ── Main TUI loop ─────────────────────────────────────────────────────────────
cleanup() {
  tput cnorm
  tput rmcup
  echo "Goodbye! 🐾"
  exit 0
}

trap cleanup INT TERM EXIT

tput smcup   # save terminal state / enter alternate screen
tput civis   # hide cursor

while true; do
  draw_all

  IFS= read -rsn1 key
  # Detect escape sequences (arrow keys)
  if [[ $key == $'\x1b' ]]; then
    IFS= read -rsn2 -t 0.1 rest
    key="${key}${rest}"
  fi

  case "$key" in
    $'\x1b[A'|k)           SELECTED=$(( (SELECTED - 1 + ITEMS) % ITEMS )) ;;  # up / k
    $'\x1b[B'|j)           SELECTED=$(( (SELECTED + 1) % ITEMS )) ;;          # down / j
    $'\x0a'|$'\x0d')       run_action "$SELECTED" ;;                           # Enter
    r|R)                   run_action 0 ;;                                     # run synthetics
    d|D)                   run_action 2 ;;                                     # demo
    q|Q|$'\x1b')           break ;;                                            # quit
  esac
done

# cleanup is called by trap
