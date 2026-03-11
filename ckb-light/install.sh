#!/usr/bin/env bash
# ckb-light-client installer — Linux & macOS
# One command: curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-light/install.sh | bash
set -euo pipefail

VERSION="0.5.4"
BINARY="ckb-light-client"
SERVICE_NAME="ckb-light"
REPO="nervosnetwork/ckb-light-client"
CONFIG_BASE="https://raw.githubusercontent.com/nervosnetwork/ckb-light-client/main/config"

# ── Colours ──────────────────────────────────────────────
BOLD="\033[1m"; RESET="\033[0m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"
write_step()  { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }
write_ok()    { echo -e "  ${GREEN}✓${RESET} $*"; }
write_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
write_error() { echo -e "  ${RED}✗${RESET} $*"; }
ask() { local var="$1" prompt="$2" default="$3"; read -rp "  ${prompt} [${default}]: " val; eval "$var=\"${val:-$default}\""; }

# ── Platform detect ───────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"
BUILD_FROM_SOURCE=0

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64)  TARBALL="ckb-light-client_v${VERSION}-x86_64-linux.tar.gz" ;;
      aarch64)
        # Check if prebuilt arm64 binary exists in this release
        ARM_URL="https://github.com/${REPO}/releases/download/v${VERSION}/ckb-light-client_v${VERSION}-aarch64-linux.tar.gz"
        if curl -fsI "$ARM_URL" &>/dev/null; then
          TARBALL="ckb-light-client_v${VERSION}-aarch64-linux.tar.gz"
        else
          echo -e "  ${YELLOW}No prebuilt arm64 binary for v${VERSION} — will build from source (~20-30 min)${RESET}"
          BUILD_FROM_SOURCE=1
          TARBALL=""
        fi
        ;;
      *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
    esac
    IS_LINUX=1; IS_MAC=0
    ;;
  Darwin)
    case "$ARCH" in
      x86_64) TARBALL="ckb-light-client_v${VERSION}-x86_64-darwin.tar.gz" ;;
      arm64)
        ARM_URL="https://github.com/${REPO}/releases/download/v${VERSION}/ckb-light-client_v${VERSION}-aarch64-apple-darwin.tar.gz"
        if curl -fsI "$ARM_URL" &>/dev/null; then
          TARBALL="ckb-light-client_v${VERSION}-aarch64-apple-darwin.tar.gz"
        else
          echo -e "  ${YELLOW}No prebuilt arm64/M1 binary for v${VERSION} — will build from source (~10-15 min)${RESET}"
          BUILD_FROM_SOURCE=1
          TARBALL=""
        fi
        ;;
    esac
    IS_LINUX=0; IS_MAC=1
    ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

TARBALL_URL=""
if [ -n "$TARBALL" ]; then
  TARBALL_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${TARBALL}"
fi

# ── Banner ────────────────────────────────────────────────
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║   CKB Light Client Installer v1.0     ║"
echo "  ║   Nervos CKB · nervosnetwork           ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Light client — syncs headers only, ~50MB vs ~200GB for full node"
echo "  Compatible with ckb-indexer RPC — drop-in for most tooling"
echo ""

# ── Config ────────────────────────────────────────────────
write_step "Configuration"
ask NETWORK      "Network (mainnet/testnet)" "mainnet"
ask INSTALL_DIR  "Install directory" "$HOME/.ckb-light-${NETWORK}"
ask P2P_PORT     "P2P listen port" "8118"
ask RPC_PORT     "RPC listen port" "9000"
ask MAX_PEERS    "Max peers" "125"

DATA_DIR="${INSTALL_DIR}/data"
CONFIG_FILE="${INSTALL_DIR}/config.toml"
LOG_FILE="${DATA_DIR}/ckb-light.log"

echo ""
write_ok "Network:     $NETWORK"
write_ok "Install dir: $INSTALL_DIR"
write_ok "P2P port:    $P2P_PORT"
write_ok "RPC port:    $RPC_PORT"
echo ""

# ── Download / Build ──────────────────────────────────────
write_step "Getting ckb-light-client v${VERSION}"
mkdir -p "${INSTALL_DIR}/bin" "${DATA_DIR}/store" "${DATA_DIR}/network"

if [ "$BUILD_FROM_SOURCE" = "1" ]; then
  write_info "Building from source (arm64 — no prebuilt binary for this release)"

  # Install Rust if needed
  if ! command -v cargo &>/dev/null; then
    write_info "Installing Rust toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    source "$HOME/.cargo/env"
  fi

  # Install build deps
  if [ "$IS_LINUX" = "1" ] && command -v apt-get &>/dev/null; then
    write_info "Installing build dependencies..."
    sudo apt-get install -y -qq build-essential pkg-config libssl-dev clang 2>/dev/null || true
  fi

  TMP_SRC="$(mktemp -d)"
  write_info "Cloning ckb-light-client v${VERSION}..."
  git clone --depth=1 --branch "v${VERSION}" \
    "https://github.com/${REPO}.git" "$TMP_SRC" 2>&1 | tail -3

  write_info "Compiling (this takes 20-30 min on arm64)..."
  cd "$TMP_SRC"
  cargo build --release --bin ckb-light-client 2>&1 | tail -5
  cp "target/release/ckb-light-client" "${INSTALL_DIR}/bin/${BINARY}"
  cd - >/dev/null
  rm -rf "$TMP_SRC"
  write_ok "Built and installed from source"

else
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  if command -v curl &>/dev/null; then
    curl -fsSL -o "${TMP_DIR}/${TARBALL}" "$TARBALL_URL"
  elif command -v wget &>/dev/null; then
    wget -q -O "${TMP_DIR}/${TARBALL}" "$TARBALL_URL"
  else
    write_error "curl or wget required"; exit 1
  fi

  tar -xzf "${TMP_DIR}/${TARBALL}" -C "$TMP_DIR"
  BIN_PATH="$(find "$TMP_DIR" -name "ckb-light-client" -type f | head -1)"
  if [ -z "$BIN_PATH" ]; then
    write_error "Binary not found in tarball"; exit 1
  fi
  cp "$BIN_PATH" "${INSTALL_DIR}/bin/${BINARY}"
  write_ok "Binary installed: ${INSTALL_DIR}/bin/${BINARY}"
fi

chmod +x "${INSTALL_DIR}/bin/${BINARY}"

# ── Config file ───────────────────────────────────────────
write_step "Writing config"

# Fetch upstream bootnodes config
UPSTREAM_CONFIG="$(curl -fsSL "${CONFIG_BASE}/${NETWORK}.toml" 2>/dev/null || true)"
if [ -z "$UPSTREAM_CONFIG" ]; then
  UPSTREAM_CONFIG="$(curl -fsSL "https://api.github.com/repos/${REPO}/contents/config/${NETWORK}.toml" | \
    python3 -c 'import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d["content"]).decode())')"
fi

# Extract bootnodes block
BOOTNODES="$(echo "$UPSTREAM_CONFIG" | awk '/^bootnodes/,/^\]/' | head -40)"

cat > "$CONFIG_FILE" << TOML
chain = "${NETWORK}"

[store]
path = "data/store"

[network]
path = "data/network"
listen_addresses = ["/ip4/0.0.0.0/tcp/${P2P_PORT}"]
${BOOTNODES}

max_peers = ${MAX_PEERS}
max_outbound_peers = 8
ping_interval_secs = 120
ping_timeout_secs = 1200
connect_outbound_interval_secs = 15
upnp = false
discovery_local_address = false
bootnode_mode = false

[rpc]
listen_address = "127.0.0.1:${RPC_PORT}"
TOML
write_ok "Config written: $CONFIG_FILE"

# ── Start script ──────────────────────────────────────────
write_step "Creating start script"
START_SCRIPT="${INSTALL_DIR}/start-ckb-light.sh"
cat > "$START_SCRIPT" << BASH
#!/usr/bin/env bash
RUST_LOG=info,ckb_light_client=info \\
  "${INSTALL_DIR}/bin/${BINARY}" run --config-file "${CONFIG_FILE}" \\
  >> "${LOG_FILE}" 2>&1
BASH
chmod +x "$START_SCRIPT"
write_ok "Start script: $START_SCRIPT"

# ── PATH ──────────────────────────────────────────────────
BIN_DIR="${INSTALL_DIR}/bin"
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  SHELL_RC="$HOME/.bashrc"
  [ "$IS_MAC" = "1" ] && SHELL_RC="$HOME/.zshrc"
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_RC"
  write_ok "Added $BIN_DIR to PATH in $SHELL_RC"
fi

# ── Firewall ──────────────────────────────────────────────
write_step "Firewall"
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q active; then
  ufw allow "${P2P_PORT}/tcp" &>/dev/null && write_ok "ufw: allowed port $P2P_PORT/tcp"
elif command -v firewall-cmd &>/dev/null; then
  firewall-cmd --add-port="${P2P_PORT}/tcp" --permanent &>/dev/null && firewall-cmd --reload &>/dev/null
  write_ok "firewalld: allowed port $P2P_PORT/tcp"
else
  write_warn "No firewall detected — ensure port $P2P_PORT/tcp is open if needed"
fi

# ── Service ───────────────────────────────────────────────
write_step "Installing service"
if [ "$IS_LINUX" = "1" ] && command -v systemctl &>/dev/null; then
  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
  SYSTEMD_USER=0
  if [ "$(id -u)" != "0" ]; then
    SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
    mkdir -p "$(dirname "$SERVICE_FILE")"
    SYSTEMD_USER=1
  fi
  cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=CKB Light Client (${NETWORK})
After=network.target

[Service]
Environment=RUST_LOG=info,ckb_light_client=info
ExecStart=${INSTALL_DIR}/bin/${BINARY} run --config-file ${CONFIG_FILE}
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=10
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
UNIT
  if [ "$SYSTEMD_USER" = "1" ]; then
    systemctl --user daemon-reload
    write_ok "systemd user service installed: $SERVICE_NAME"
  else
    systemctl daemon-reload
    write_ok "systemd system service installed: $SERVICE_NAME"
  fi

elif [ "$IS_MAC" = "1" ]; then
  PLIST_LABEL="xyz.wyltek.ckb-light"
  PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
  cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR}/bin/${BINARY}</string>
    <string>run</string>
    <string>--config-file</string>
    <string>${CONFIG_FILE}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>RUST_LOG</key><string>info,ckb_light_client=info</string>
  </dict>
  <key>WorkingDirectory</key><string>${INSTALL_DIR}</string>
  <key>StandardOutPath</key><string>${LOG_FILE}</string>
  <key>StandardErrorPath</key><string>${LOG_FILE}</string>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST
  write_ok "launchd plist: $PLIST_PATH"
fi

# ── Smoke test ────────────────────────────────────────────
write_step "Smoke Test"
write_info() { echo -e "  ${CYAN}ℹ${RESET} $*"; }
write_info "Starting light client briefly to verify it launches..."

# Kill any existing process
pkill -f "ckb-light-client" 2>/dev/null || true
sleep 1

RUST_LOG=info,ckb_light_client=info \
  "${INSTALL_DIR}/bin/${BINARY}" run --config-file "$CONFIG_FILE" \
  >> "${LOG_FILE}" 2>&1 &
SMOKE_PID=$!

SMOKE_PASS=0
RPC_URL="http://127.0.0.1:${RPC_PORT}"
printf "  Waiting for RPC on 127.0.0.1:${RPC_PORT}"
for i in $(seq 1 20); do
  sleep 1
  printf "."
  RESULT="$(curl -sf -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"local_node_info","params":[],"id":1}' 2>/dev/null || true)"
  if echo "$RESULT" | grep -q '"node_id"'; then
    SMOKE_PASS=1
    break
  fi
done
echo ""

kill "$SMOKE_PID" 2>/dev/null || true
pkill -f "ckb-light-client" 2>/dev/null || true
sleep 1

if [ "$SMOKE_PASS" = "1" ]; then
  write_ok "Smoke test passed ✓"
  NODE_ID="$(echo "$RESULT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["result"]["node_id"])' 2>/dev/null || echo "unknown")"
  write_ok "Node ID: $NODE_ID"
else
  write_warn "Smoke test timed out — check logs: tail -f $LOG_FILE"
fi

# ── Summary ───────────────────────────────────────────────
LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "localhost")"

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  CKB Light Client installed!${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Network:${RESET}     $NETWORK"
echo -e "  ${BOLD}Version:${RESET}     v${VERSION}"
echo -e "  ${BOLD}Install dir:${RESET} $INSTALL_DIR"
echo -e "  ${BOLD}Config:${RESET}      $CONFIG_FILE"
echo -e "  ${BOLD}Log:${RESET}         $LOG_FILE"
echo -e "  ${BOLD}P2P port:${RESET}    $P2P_PORT"
echo -e "  ${BOLD}RPC port:${RESET}    $RPC_PORT (localhost only)"
echo ""
echo -e "  ${BOLD}RPC endpoint:${RESET} http://127.0.0.1:${RPC_PORT}"
echo ""

# ── Offer to start ────────────────────────────────────────
write_step "Start Node?"
read -rp "  Start ckb-light-client now? [Y/n]: " START_NOW
START_NOW="${START_NOW:-Y}"
if [[ "$START_NOW" =~ ^[Yy] ]]; then
  if [ "$IS_LINUX" = "1" ] && command -v systemctl &>/dev/null; then
    if [ "$SYSTEMD_USER" = "1" ]; then
      systemctl --user enable "$SERVICE_NAME"
      systemctl --user start "$SERVICE_NAME"
      write_ok "Started: systemctl --user status $SERVICE_NAME"
    else
      systemctl enable "$SERVICE_NAME"
      systemctl start "$SERVICE_NAME"
      write_ok "Started: systemctl status $SERVICE_NAME"
    fi
  elif [ "$IS_MAC" = "1" ]; then
    launchctl load "$PLIST_PATH"
    write_ok "Started via launchd"
  else
    nohup "$START_SCRIPT" &
    write_ok "Started (nohup)"
  fi
  echo ""
  write_info "Check logs: tail -f $LOG_FILE"
  write_info "Check RPC:  curl -X POST http://127.0.0.1:${RPC_PORT} -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"local_node_info\",\"params\":[],\"id\":1}'"
else
  echo ""
  if [ "$IS_LINUX" = "1" ] && command -v systemctl &>/dev/null; then
    if [ "$SYSTEMD_USER" = "1" ]; then
      write_info "To start: systemctl --user enable --now $SERVICE_NAME"
    else
      write_info "To start: systemctl enable --now $SERVICE_NAME"
    fi
  elif [ "$IS_MAC" = "1" ]; then
    write_info "To start: launchctl load $PLIST_PATH"
  else
    write_info "To start: bash $START_SCRIPT"
  fi
fi

echo ""
write_ok "Done! CKB light client syncs block headers only — no 200GB download needed."
echo ""
