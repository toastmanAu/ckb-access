#!/usr/bin/env bash
set -euo pipefail

# ckb-miner installer
# Downloads CPU miner by default, optional CUDA/OpenCL detection
# Platforms: Linux x86_64, Windows x86_64 (CPU only)
# No macOS support (no binaries)
# No arm64 support (no binaries)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Version to install
VERSION="0.25.0"
REPO="nervosnetwork/ckb-miner"

# Defaults
DEFAULT_INSTALL_DIR="${HOME}/.ckb-miner"
DEFAULT_POOL="stratum+tcp://ckb.viabtc.com:3333"
DEFAULT_WORKER_NAME="$(hostname)-$(whoami)"
DEFAULT_CPU_THREADS="$(nproc)"

# Helper functions
write_info() {
  echo -e "${BLUE}▶${RESET} $1"
}
write_success() {
  echo -e "${GREEN}✓${RESET} $1"
}
write_warning() {
  echo -e "${YELLOW}⚠${RESET} $1"
}
write_error() {
  echo -e "${RED}✗${RESET} $1"
}

# Banner
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║           ckb-miner installer v${VERSION}                ║${RESET}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "Installs CKB CPU miner (Eaglesong) for Linux/Windows."
echo "CUDA/OpenCL versions available via flags."
echo ""

# Detect platform
ARCH="$(uname -m)"
OS="$(uname -s)"
case "${ARCH}" in
  x86_64) ARCH="x86_64" ;;
  *)      write_error "Unsupported architecture: ${ARCH} (only x86_64 supported)"
          exit 1 ;;
esac

case "${OS}" in
  Linux)  PLATFORM="linux" ;;
  Darwin) write_error "macOS not supported by ckb-miner binaries"
          exit 1 ;;
  CYGWIN*|MINGW*|MSYS*)
          PLATFORM="win" ;;
  *)      write_error "Unsupported OS: ${OS}"
          exit 1 ;;
esac

# GPU detection (optional)
if [[ "${PLATFORM}" == "linux" ]]; then
  if command -v nvidia-smi &>/dev/null; then
    write_info "NVIDIA GPU detected (CUDA possible)"
    HAS_CUDA=true
  else
    HAS_CUDA=false
  fi
  if [[ -f /usr/lib/libOpenCL.so ]] || [[ -f /usr/local/lib/libOpenCL.so ]]; then
    write_info "OpenCL library detected"
    HAS_OPENCL=true
  else
    HAS_OPENCL=false
  fi
fi

# Collect user configuration
echo ""
read -p "Install directory [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
mkdir -p "${INSTALL_DIR}" || {
  write_error "Failed to create directory ${INSTALL_DIR}"
  exit 1
}

# Pool configuration
echo ""
echo "Mining pool configuration:"
read -p "Pool URL [${DEFAULT_POOL}]: " POOL_URL
POOL_URL="${POOL_URL:-${DEFAULT_POOL}}"
read -p "Worker name [${DEFAULT_WORKER_NAME}]: " WORKER_NAME
WORKER_NAME="${WORKER_NAME:-${DEFAULT_WORKER_NAME}}"
read -p "CPU threads (0 = auto) [${DEFAULT_CPU_THREADS}]: " CPU_THREADS
CPU_THREADS="${CPU_THREADS:-${DEFAULT_CPU_THREADS}}"

# Binary variant selection
BINARY_VARIANT="cpu"
if [[ "${PLATFORM}" == "linux" && "${HAS_CUDA}" == true ]]; then
  echo ""
  echo "Available GPU variants:"
  echo "  1) CPU only (default)"
  echo "  2) CUDA (NVIDIA GPU)"
  echo "  3) OpenCL (AMD/Intel GPU)"
  read -p "Choose variant (1-3) [1]: " GPU_CHOICE
  case "${GPU_CHOICE}" in
    2) BINARY_VARIANT="cuda" ;;
    3) BINARY_VARIANT="opencl" ;;
    *) BINARY_VARIANT="cpu" ;;
  esac
fi

# Download URL
ARCHIVE="ckb-miner-${BINARY_VARIANT}-${PLATFORM}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ARCHIVE}"

write_info "Downloading ${ARCHIVE}..."
TMP_DIR="$(mktemp -d)"
curl -fsSL -o "${TMP_DIR}/${ARCHIVE}" "${DOWNLOAD_URL}" || {
  write_error "Download failed"
  rm -rf "${TMP_DIR}"
  exit 1
}

# Extract
write_info "Extracting..."
if command -v unzip &>/dev/null; then
  unzip -q "${TMP_DIR}/${ARCHIVE}" -d "${TMP_DIR}"
else
  # fallback with python
  python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
          "${TMP_DIR}/${ARCHIVE}" "${TMP_DIR}" 2>/dev/null || {
    write_error "Extraction failed (install unzip or python3)"
    rm -rf "${TMP_DIR}"
    exit 1
  }
fi

# Find binary
BINARY_PATH=""
if [[ "${PLATFORM}" == "windows" ]]; then
  BINARY_PATH="$(find "${TMP_DIR}" -name "ckb-miner.exe" -type f | head -1)"
else
  BINARY_PATH="$(find "${TMP_DIR}" -name "ckb-miner" -type f | head -1)"
fi

if [[ -z "${BINARY_PATH}" ]]; then
  write_error "Could not find miner binary in archive"
  rm -rf "${TMP_DIR}"
  exit 1
fi

# Install
write_info "Installing to ${INSTALL_DIR}/bin/"
mkdir -p "${INSTALL_DIR}/bin"
cp "${BINARY_PATH}" "${INSTALL_DIR}/bin/"
chmod +x "${INSTALL_DIR}/bin/$(basename "${BINARY_PATH}")"

# Create config file
CONFIG_FILE="${INSTALL_DIR}/config.toml"
cat > "${CONFIG_FILE}" << EOF
# ckb-miner configuration
pool = "${POOL_URL}"
worker = "${WORKER_NAME}"
threads = ${CPU_THREADS}
EOF

write_success "Configuration written to ${CONFIG_FILE}"

# Create start script
START_SCRIPT="${INSTALL_DIR}/start-miner.sh"
cat > "${START_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
exec ./bin/ckb-miner -c config.toml
EOF
chmod +x "${START_SCRIPT}"
write_success "Start script created: ${START_SCRIPT}"

# Offer systemd service (Linux only)
if [[ "${PLATFORM}" == "linux" ]]; then
  echo ""
  read -p "Install systemd service? (y/N): " INSTALL_SERVICE
  if [[ "${INSTALL_SERVICE}" =~ ^[Yy] ]]; then
    SERVICE_FILE="/etc/systemd/system/ckb-miner.service"
    sudo tee "${SERVICE_FILE}" > /dev/null << EOF
[Unit]
Description=CKB Miner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/start-miner.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    write_info "Systemd service installed at ${SERVICE_FILE}"
    sudo systemctl daemon-reload
    write_success "Service loaded. Enable with: sudo systemctl enable ckb-miner"
    echo ""
    read -p "Start miner now? (y/N): " START_NOW
    if [[ "${START_NOW}" =~ ^[Yy] ]]; then
      sudo systemctl start ckb-miner
      sleep 2
      sudo systemctl status ckb-miner --no-pager
    fi
  fi
fi

# Add to PATH
echo ""
read -p "Add miner to PATH in ~/.profile? (y/N): " ADD_PATH
if [[ "${ADD_PATH}" =~ ^[Yy] ]]; then
  echo "export PATH=\"${INSTALL_DIR}/bin:\$PATH\"" >> "${HOME}/.profile"
  write_success "Added to PATH. Run: source ~/.profile"
fi

# Cleanup
rm -rf "${TMP_DIR}"

# Summary
echo ""
write_success "ckb-miner ${VERSION} installed successfully!"
echo ""
echo "Summary:"
echo "  Binary:   ${INSTALL_DIR}/bin/$(basename "${BINARY_PATH}")"
echo "  Config:   ${CONFIG_FILE}"
echo "  Pool:     ${POOL_URL}"
echo "  Worker:   ${WORKER_NAME}"
echo "  Threads:  ${CPU_THREADS}"
echo ""
if [[ "${PLATFORM}" == "linux" ]]; then
  echo "Commands:"
  echo "  Start miner:   ${START_SCRIPT}"
  echo "  Systemd:       sudo systemctl start ckb-miner"
  echo "  View logs:     sudo journalctl -u ckb-miner -f"
else
  echo "Commands:"
  echo "  Start miner:   cd ${INSTALL_DIR} && ./start-miner.sh"
fi
echo ""
echo "Happy mining!"