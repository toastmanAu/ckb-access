#!/usr/bin/env bash
# WyDash installer — browser-based CKB node management dashboard
# https://github.com/toastmanAu/ckb-access
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/wydash/install.sh | bash
#   bash install.sh [--port 9999] [--dir ~/wydash] [--no-service]

set -euo pipefail

WYDASH_REPO="https://raw.githubusercontent.com/toastmanAu/ckb-access/main/wydash"
DEFAULT_PORT=9999
SERVICE_NAME="wydash"

# ── Colours ────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; RED='\033[0;31m'; RESET='\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; CYAN=''; RED=''; RESET=''
fi

info()    { echo -e "${CYAN}▸${RESET} $*"; }
success() { echo -e "${GREEN}✅${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✖${RESET}  $*" >&2; exit 1; }

# ── Parse args ─────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/wydash"
PORT="$DEFAULT_PORT"
NO_SERVICE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)        INSTALL_DIR="$2"; shift 2 ;;
    --port)       PORT="$2";        shift 2 ;;
    --no-service) NO_SERVICE=true;  shift ;;
    *) shift ;;
  esac
done

# ── Banner ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║        WyDash Installer              ║${RESET}"
echo -e "${BOLD}${CYAN}║  Browser-based CKB node management   ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}"
echo ""

# ── Detect existing install ────────────────────────────────────────────────
for candidate in \
  "$HOME/wydash/wydash.conf" \
  "$HOME/.wydash/wydash.conf" \
  "/opt/wydash/wydash.conf"; do
  if [ -f "$candidate" ]; then
    EXISTING_DIR="$(dirname "$candidate")"
    warn "WyDash already installed at ${EXISTING_DIR}"
    INSTALL_DIR="$EXISTING_DIR"
    if [ -t 0 ]; then
      read -r -p "$(echo -e "${BOLD}Reinstall / update? [Y/n]:${RESET} ")" ans
      if [[ "${ans:-y}" == "n" || "${ans:-y}" == "N" ]]; then
        success "Nothing changed. WyDash is at ${EXISTING_DIR}"
        exit 0
      fi
    fi
    break
  fi
done

# Interactive prompts only when stdin is a terminal (not piped)
if [ -t 0 ]; then
  read -r -p "$(echo -e "${BOLD}Install directory [${INSTALL_DIR}]:${RESET} ")" _d
  INSTALL_DIR="${_d:-$INSTALL_DIR}"
  read -r -p "$(echo -e "${BOLD}Dashboard port [${PORT}]:${RESET} ")" _p
  PORT="${_p:-$PORT}"
fi

CONF="${INSTALL_DIR}/wydash.conf"

# ── Download files ─────────────────────────────────────────────────────────
mkdir -p "${INSTALL_DIR}"
info "Installing to ${INSTALL_DIR} ..."

for f in server.py index.html dob-burner.html; do
  curl -fsSL "${WYDASH_REPO}/${f}" -o "${INSTALL_DIR}/${f}" \
    || error "Failed to download ${f}"
done
success "Files downloaded."

# ── Write wydash.conf (only if missing) ───────────────────────────────────
if [ ! -f "$CONF" ]; then
  info "Writing default wydash.conf ..."
  cat > "$CONF" << 'CONF_EOF'
# WyDash configuration
# Enable the modules for the services you have installed.
# Changes take effect immediately — no restart needed.
# Disabled modules add zero overhead.

[modules]
ckb_node   = false
mining     = false
fiber      = false
dob_minter = false
dob_burner = false

# CKB full node monitor
[ckb_node]
rpc_url  = http://127.0.0.1:8114
dash_url = http://127.0.0.1:8080

# Stratum proxy / solo miner stats
[mining]
dash_url = http://127.0.0.1:8081

# Fiber payment channel node
[fiber]
rpc_url  = http://127.0.0.1:8227

# Spore/DOB minter
[dob_minter]
dash_url = http://127.0.0.1:5173
CONF_EOF
  success "wydash.conf created — all modules off by default."
else
  info "Keeping existing wydash.conf (modules preserved)."
fi

echo "$PORT" > "${INSTALL_DIR}/.port"

# ── systemd service ────────────────────────────────────────────────────────
install_service() {
  local unit_dir use_user=false

  if [ "$NO_SERVICE" = "true" ]; then return; fi
  command -v systemctl >/dev/null 2>&1 || return

  # Root gets system service; regular user gets --user service
  if [ "$(id -u)" = "0" ]; then
    unit_dir="/etc/systemd/system"
  else
    unit_dir="$HOME/.config/systemd/user"
    use_user=true
  fi

  mkdir -p "$unit_dir"
  cat > "${unit_dir}/${SERVICE_NAME}.service" << EOF
[Unit]
Description=WyDash — CKB Node Management Dashboard
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=$(command -v python3) ${INSTALL_DIR}/server.py --port ${PORT} --config ${INSTALL_DIR}/wydash.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=$( [ "$use_user" = "true" ] && echo "default.target" || echo "multi-user.target" )
EOF

  if [ "$use_user" = "true" ]; then
    systemctl --user daemon-reload
    systemctl --user enable --now "${SERVICE_NAME}" 2>/dev/null || true
    sleep 1
    systemctl --user is-active --quiet "${SERVICE_NAME}" \
      && success "WyDash service running." \
      || warn "Service didn't start — check: journalctl --user -u ${SERVICE_NAME} -n 20"
  else
    systemctl daemon-reload
    systemctl enable --now "${SERVICE_NAME}" 2>/dev/null || true
    sleep 1
    systemctl is-active --quiet "${SERVICE_NAME}" \
      && success "WyDash service running." \
      || warn "Service didn't start — check: journalctl -u ${SERVICE_NAME} -n 20"
  fi
}

install_service

# ── Auto-detect running components and offer to enable modules ─────────────
offer_modules() {
  local any=0

  echo ""
  echo -e "${BOLD}── Detected Components ─────────────────────────────────────────${RESET}"

  _check_and_offer() {
    local label="$1" module="$2" port_check_cmd="$3"
    if eval "$port_check_cmd" >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${RESET} ${label}"
      any=1
      if grep -q "^${module}\s*=\s*true" "$CONF" 2>/dev/null; then
        echo -e "    already enabled"
      else
        if [ -t 0 ]; then
          read -r -p "    Enable ${module} module? [Y/n] " ans
        else
          ans="y"
        fi
        if [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]]; then
          if grep -q "^${module}\s*=" "$CONF"; then
            sed -i "s/^${module}\s*=\s*false/${module} = true/" "$CONF"
          else
            sed -i "/^\[modules\]/a ${module} = true" "$CONF"
          fi
          echo -e "    ${GREEN}✅ ${module} enabled${RESET}"
        fi
      fi
    fi
  }

  _check_and_offer "CKB full node (8114)" "ckb_node" \
    "curl -sf -X POST http://127.0.0.1:8114 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"local_node_info\",\"params\":[],\"id\":1}'"

  _check_and_offer "Stratum proxy (8081)" "mining" \
    "curl -sf http://127.0.0.1:8081/"

  for fp in 8227 8226; do
    if curl -sf -X POST "http://127.0.0.1:${fp}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"local_node_info","params":[],"id":1}' \
        >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${RESET} Fiber node (${fp})"
      any=1
      if grep -q "^fiber\s*=\s*true" "$CONF" 2>/dev/null; then
        echo -e "    already enabled"
      else
        if [ -t 0 ]; then
          read -r -p "    Enable fiber module? [Y/n] " ans
        else
          ans="y"
        fi
        if [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]]; then
          if grep -q "^fiber\s*=" "$CONF"; then
            sed -i "s/^fiber\s*=\s*false/fiber = true/" "$CONF"
          else
            sed -i "/^\[modules\]/a fiber = true" "$CONF"
          fi
          [ "$fp" != "8227" ] && sed -i "s|rpc_url.*8227|rpc_url = http://127.0.0.1:${fp}|" "$CONF"
          echo -e "    ${GREEN}✅ fiber enabled${RESET}"
        fi
      fi
      break
    fi
  done

  _check_and_offer "DOB Minter (5173)" "dob_minter" \
    "curl -sf http://127.0.0.1:5173/"

  if [ "$any" = "0" ]; then
    echo -e "  No running CKB components detected yet."
    echo -e "  Install other components and re-run WyDash, or edit ${BOLD}${CONF}${RESET} manually."
  fi

  echo -e "────────────────────────────────────────────────────────────────"
}

offer_modules

# ── Summary ────────────────────────────────────────────────────────────────
local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR-IP")
echo ""
echo -e "${BOLD}${GREEN}Done!${RESET}"
echo -e "  ${BOLD}Local:${RESET}   http://localhost:${PORT}"
echo -e "  ${BOLD}Network:${RESET} http://${local_ip}:${PORT}"
echo ""
