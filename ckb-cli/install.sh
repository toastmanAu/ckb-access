#!/usr/bin/env bash
# ckb-cli installer — Linux & macOS
# One command: curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-cli/install.sh | bash
set -euo pipefail

VERSION="2.0.0"
BINARY="ckb-cli"
REPO="nervosnetwork/ckb-cli"

# ── Colours ──────────────────────────────────────────────
BOLD="\033[1m"; RESET="\033[0m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"
write_step()  { echo -e "\n${BOLD}${CYAN}▶ $*${RESET}"; }
write_ok()    { echo -e "  ${GREEN}✓${RESET} $*"; }
write_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
write_error() { echo -e "  ${RED}✗${RESET} $*"; }
write_info()  { echo -e "  ${CYAN}ℹ${RESET} $*"; }
ask() { local var="$1" prompt="$2" default="$3"; read -rp "  ${prompt} [${default}]: " val; eval "$var=\"${val:-$default}\""; }

# ── Platform detect ───────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64)  TARBALL="ckb-cli_v${VERSION}_x86_64-unknown-linux-gnu.tar.gz" ;;
      aarch64) TARBALL="ckb-cli_v${VERSION}_aarch64-unknown-linux-gnu.tar.gz" ;;
      *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
    esac
    IS_LINUX=1; IS_MAC=0
    ;;
  Darwin)
    case "$ARCH" in
      x86_64) TARBALL="ckb-cli_v${VERSION}_x86_64-apple-darwin.tar.gz" ;;
      arm64)  TARBALL="ckb-cli_v${VERSION}_aarch64-apple-darwin.tar.gz" ;;
      *)      echo "Unsupported arch: $ARCH"; exit 1 ;;
    esac
    IS_LINUX=0; IS_MAC=1
    ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

TARBALL_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${TARBALL}"

# ── Banner ────────────────────────────────────────────────
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║   CKB CLI Installer v1.0                  ║"
echo "  ║   Nervos CKB · nervosnetwork               ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  ckb-cli — command-line interface for Nervos CKB"
echo "  Query blockchain, manage wallets, send transactions"
echo ""

# ── Config ────────────────────────────────────────────────
write_step "Configuration"
DEFAULT_INSTALL="$HOME/.ckb-cli/bin"
ask INSTALL_DIR  "Install directory" "$DEFAULT_INSTALL"

echo ""
write_ok "Install dir: $INSTALL_DIR"
echo ""

# ── Download binary ───────────────────────────────────────
write_step "Downloading ckb-cli v${VERSION}"
mkdir -p "${INSTALL_DIR}"

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
BIN_PATH="$(find "$TMP_DIR" -name "ckb-cli" -type f | head -1)"
if [ -z "$BIN_PATH" ]; then
  write_error "ckb-cli binary not found in tarball"; exit 1
fi
cp "$BIN_PATH" "${INSTALL_DIR}/${BINARY}"
chmod +x "${INSTALL_DIR}/${BINARY}"
write_ok "Binary installed: ${INSTALL_DIR}/${BINARY}"

# ── PATH ──────────────────────────────────────────────────
write_step "Adding to PATH"
if ! echo "$PATH" | grep -q "${INSTALL_DIR}"; then
  SHELL_RC="$HOME/.bashrc"
  [ "$IS_MAC" = "1" ] && SHELL_RC="$HOME/.zshrc"
  echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" >> "$SHELL_RC"
  write_ok "Added ${INSTALL_DIR} to PATH in $SHELL_RC"
  export PATH="${INSTALL_DIR}:$PATH"
else
  write_ok "${INSTALL_DIR} already in PATH"
fi

# ── Smoke test ────────────────────────────────────────────
write_step "Smoke Test"
SMOKE_PASS=0
VERSION_OUT="$("${INSTALL_DIR}/${BINARY}" --version 2>&1 || true)"
if echo "$VERSION_OUT" | grep -q "${VERSION}"; then
  SMOKE_PASS=1
fi

if [ "$SMOKE_PASS" = "1" ]; then
  write_ok "Smoke test passed ✓"
  write_ok "Version: $VERSION_OUT"
else
  write_warn "Version check unexpected output: $VERSION_OUT"
  write_warn "Binary may still work — check manually: ${INSTALL_DIR}/${BINARY} --version"
fi

# ── Summary ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  ckb-cli installed!${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Version:${RESET}     v${VERSION}"
echo -e "  ${BOLD}Binary:${RESET}      ${INSTALL_DIR}/${BINARY}"
echo ""
echo -e "  ${BOLD}Usage examples:${RESET}"
echo "    ckb-cli --version"
echo "    ckb-cli wallet get-capacity --address <addr>"
echo "    ckb-cli rpc get_tip_block_number"
echo ""
echo -e "  ${YELLOW}Note:${RESET} Restart your shell or run: export PATH=\"${INSTALL_DIR}:\$PATH\""
echo ""
write_ok "Done!"
echo ""
