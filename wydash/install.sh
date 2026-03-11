#!/usr/bin/env bash
# WyDash installer — browser-based CKB node management dashboard
# https://github.com/toastmanAu/ckb-access
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/wydash/install.sh | bash
#   bash install.sh [--port 9999] [--dir ~/wydash] [--no-service]
#
# Installs WyDash to $HOME/wydash/ and registers a systemd user service.
# Zero dependencies beyond Python 3 (stdlib only).

set -euo pipefail

WYDASH_REPO="https://raw.githubusercontent.com/toastmanAu/ckb-access/main/wydash"
DEFAULT_DIR="$HOME/wydash"
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
error()   { echo -e "${RED}✖${RESET}  $*" >&2; }
ask()     { local _var="$1" _prompt="$2" _default="$3"
            read -r -p "$(echo -e "${BOLD}${_prompt}${RESET} [${_default}]: ")" _val
            printf -v "$_var" '%s' "${_val:-$_default}"; }

banner() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        WyDash Installer              ║${RESET}"
  echo -e "${BOLD}${CYAN}║  Browser-based CKB node management   ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}"
  echo ""
}

# ── Parse args ─────────────────────────────────────────────────────────────
INSTALL_DIR="$DEFAULT_DIR"
PORT="$DEFAULT_PORT"
NO_SERVICE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)    INSTALL_DIR="$2"; shift 2 ;;
    --port)   PORT="$2";        shift 2 ;;
    --no-service) NO_SERVICE=true; shift ;;
    *) shift ;;
  esac
done

# ── Detect existing install ────────────────────────────────────────────────
detect_existing() {
  # Check all common locations (covers manual moves and different base dirs)
  for candidate in \
    "$HOME/wydash/wydash.conf" \
    "$HOME/.wydash/wydash.conf" \
    "/opt/wydash/wydash.conf"; do
    if [ -f "$candidate" ]; then
      echo "$(dirname "$candidate")"
      return
    fi
  done
  echo ""
}

EXISTING_DIR=$(detect_existing)

if [ -n "$EXISTING_DIR" ]; then
  warn "WyDash already installed at ${EXISTING_DIR}"
  ask REINSTALL "Reinstall / update? (yes/no)" "yes"
  if [[ "$REINSTALL" != "yes" && "$REINSTALL" != "y" ]]; then
    success "Nothing changed. WyDash is at ${EXISTING_DIR}"
    exit 0
  fi
  INSTALL_DIR="$EXISTING_DIR"
fi

# ── Collect config ─────────────────────────────────────────────────────────
banner

info "WyDash will be installed to: ${BOLD}${INSTALL_DIR}${RESET}"
ask INSTALL_DIR "Install directory" "$INSTALL_DIR"
ask PORT        "Dashboard port"    "$PORT"

# ── Detect installed components and offer to enable their modules ──────────
detect_and_offer_modules() {
  local CONF="$1"
  echo ""
  echo -e "${B}── Detected Components ──────────────────────────────────────────${R}"

  local any_found=0

  # CKB full node — check RPC
  if curl -sf -X POST http://127.0.0.1:8114 \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"local_node_info","params":[],"id":1}' \
      >/dev/null 2>&1; then
    echo -e "  ${G}✓${R} CKB full node (port 8114)"
    any_found=1
    if ! grep -q "^ckb_node\s*=\s*true" "$CONF"; then
      echo -n "    Enable ckb_node module? [Y/n] "
      read -r ans </dev/tty
      [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]] && \
        _enable_module "$CONF" "ckb_node" && echo -e "    ${G}✅ ckb_node enabled${R}"
    else
      echo -e "    ${G}already enabled${R}"
    fi
  fi

  # Stratum proxy — check stats HTTP
  if curl -sf http://127.0.0.1:8081/health >/dev/null 2>&1 || \
     curl -sf http://127.0.0.1:8081/ >/dev/null 2>&1; then
    echo -e "  ${G}✓${R} Stratum proxy (port 8081)"
    any_found=1
    if ! grep -q "^mining\s*=\s*true" "$CONF"; then
      echo -n "    Enable mining module? [Y/n] "
      read -r ans </dev/tty
      [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]] && \
        _enable_module "$CONF" "mining" && echo -e "    ${G}✅ mining enabled${R}"
    else
      echo -e "    ${G}already enabled${R}"
    fi
  fi

  # Fiber node — check RPC
  for port in 8227 8226; do
    if curl -sf -X POST http://127.0.0.1:${port} \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"local_node_info","params":[],"id":1}' \
        >/dev/null 2>&1; then
      echo -e "  ${G}✓${R} Fiber node (port ${port})"
      any_found=1
      if ! grep -q "^fiber\s*=\s*true" "$CONF"; then
        echo -n "    Enable fiber module? [Y/n] "
        read -r ans </dev/tty
        if [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]]; then
          _enable_module "$CONF" "fiber"
          # Update RPC port if non-default
          if [ "$port" != "8227" ]; then
            sed -i "s|rpc_url\s*=\s*http://127.0.0.1:8227|rpc_url = http://127.0.0.1:${port}|" "$CONF"
          fi
          echo -e "    ${G}✅ fiber enabled${R}"
        fi
      else
        echo -e "    ${G}already enabled${R}"
      fi
      break
    fi
  done

  # DOB minter dev server
  if curl -sf http://127.0.0.1:5173/ >/dev/null 2>&1; then
    echo -e "  ${G}✓${R} DOB Minter dev server (port 5173)"
    any_found=1
    if ! grep -q "^dob_minter\s*=\s*true" "$CONF"; then
      echo -n "    Enable dob_minter module? [Y/n] "
      read -r ans </dev/tty
      [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]] && \
        _enable_module "$CONF" "dob_minter" && echo -e "    ${G}✅ dob_minter enabled${R}"
    else
      echo -e "    ${G}already enabled${R}"
    fi
  fi

  if [ "$any_found" = "0" ]; then
    echo -e "  No running CKB components detected."
    echo -e "  Edit ${B}${CONF}${R} to enable modules after installing other components."
  fi

  echo -e "─────────────────────────────────────────────────────────────────"
}

_enable_module() {
  local conf="$1" module="$2"
  if grep -q "^${module}\s*=" "$conf"; then
    sed -i "s/^${module}\s*=\s*false/${module} = true/" "$conf"
  else
    sed -i "/^\[modules\]/a ${module} = true" "$conf"
  fi
}

# ── Install files ──────────────────────────────────────────────────────────
mkdir -p "${INSTALL_DIR}"

info "Downloading WyDash files..."

# server.py
curl -fsSL "${WYDASH_REPO}/server.py" -o "${INSTALL_DIR}/server.py"

# index.html
curl -fsSL "${WYDASH_REPO}/index.html" -o "${INSTALL_DIR}/index.html"

# dob-burner.html
curl -fsSL "${WYDASH_REPO}/dob-burner.html" -o "${INSTALL_DIR}/dob-burner.html"

success "Files downloaded."

# ── Write wydash.conf if not present ──────────────────────────────────────
CONF="${INSTALL_DIR}/wydash.conf"
if [ ! -f "$CONF" ]; then
  info "Writing default wydash.conf..."
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

# ── Write port file (used by service and detection) ───────────────────────
echo "$PORT" > "${INSTALL_DIR}/.port"

# ── systemd user service ───────────────────────────────────────────────────
if [ "$NO_SERVICE" = false ] && command -v systemctl >/dev/null 2>&1; then
  SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
  mkdir -p "$(dirname "$SERVICE_FILE")"
  cat > "$SERVICE_FILE" << EOF
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
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now "${SERVICE_NAME}" 2>/dev/null || true
  sleep 1

  if systemctl --user is-active --quiet "${SERVICE_NAME}"; then
    success "WyDash service running."
  else
    warn "Service didn't start — check: journalctl --user -u ${SERVICE_NAME} -n 20"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}WyDash installed!${RESET}"
echo ""
local_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR-IP")
echo -e "  ${BOLD}Local:${RESET}   http://localhost:${PORT}"
echo -e "  ${BOLD}Network:${RESET} http://${local_ip}:${PORT}"
echo ""
echo -e "  Edit ${BOLD}${CONF}${RESET} to enable modules."
echo -e "  Changes reload on browser refresh — no restart needed."
echo ""
echo -e "  Enable a module manually:"
echo -e "    ${CYAN}sed -i 's/^ckb_node = false/ckb_node = true/' ${CONF}${RESET}"
echo ""

# Auto-detect any already-running components and offer to enable them
detect_and_offer_modules "$CONF"
