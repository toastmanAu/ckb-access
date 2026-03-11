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
echo "  ╔═══════════════════════════════════════╗"
echo "  ║   CKB CLI Installer v1.0              ║"
echo "  ║   Nervos CKB · nervosnetwork           ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"
echo "  ckb-cli — command-line interface for Nervos CKB"
echo "  Send transactions, manage wallets, query chain state"
echo ""

# ── Config ────────────────────────────────────────────────
write_step "Configuration"
INSTALL_DIR="$HOME/.ckb-cli/bin"
ask INSTALL_DIR "Install directory" "$INSTALL_DIR"

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
write_step "PATH"
if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
  SHELL_RC="$HOME/.bashrc"
  [ "$IS_MAC" = "1" ] && SHELL_RC="$HOME/.zshrc"
  echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_RC"
  write_ok "Added $INSTALL_DIR to PATH in $SHELL_RC"
  export PATH="${INSTALL_DIR}:${PATH}"
else
  write_ok "$INSTALL_DIR already in PATH"
fi

# ── Smoke test ────────────────────────────────────────────
write_step "Smoke Test"
SMOKE_PASS=0
VERSION_OUTPUT="$("${INSTALL_DIR}/${BINARY}" --version 2>/dev/null || true)"
if echo "$VERSION_OUTPUT" | grep -q "$VERSION"; then
  SMOKE_PASS=1
fi

if [ "$SMOKE_PASS" = "1" ]; then
  write_ok "Smoke test passed ✓"
  write_ok "Version: $VERSION_OUTPUT"
else
  write_warn "Unexpected version output: $VERSION_OUTPUT"
  write_warn "Try: ${INSTALL_DIR}/${BINARY} --version"
fi

# ── Summary ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  CKB CLI installed!${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Version:${RESET}     v${VERSION}"
echo -e "  ${BOLD}Binary:${RESET}      ${INSTALL_DIR}/${BINARY}"
echo ""
echo -e "  ${BOLD}Quick start:${RESET}"
echo -e "  ${CYAN}  ckb-cli --version${RESET}"
echo -e "  ${CYAN}  ckb-cli wallet get-capacity --address <addr>${RESET}"
echo -e "  ${CYAN}  ckb-cli rpc local_node_info --url http://127.0.0.1:8114${RESET}"
echo ""
write_info "Restart your shell or run: export PATH=\"${INSTALL_DIR}:\$PATH\""
echo ""
write_ok "Done! ckb-cli is ready to use."
echo ""
