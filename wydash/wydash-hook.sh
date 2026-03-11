#!/usr/bin/env bash
# wydash-hook.sh — WyDash integration helper
# Source this in any component installer:
#   source <(curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/wydash/wydash-hook.sh)
# Then call: offer_wydash_module "fiber"

# ── Find WyDash config in any common location ─────────────────────────────
find_wydash_conf() {
  for candidate in \
    "$HOME/wydash/wydash.conf" \
    "$HOME/.wydash/wydash.conf" \
    "/opt/wydash/wydash.conf" \
    "/usr/local/wydash/wydash.conf"; do
    [ -f "$candidate" ] && echo "$candidate" && return
  done
  # Also check if systemd service points somewhere else
  if command -v systemctl >/dev/null 2>&1; then
    local svc_dir
    svc_dir=$(systemctl --user cat wydash 2>/dev/null \
      | grep 'WorkingDirectory=' | head -1 | cut -d= -f2)
    [ -f "${svc_dir}/wydash.conf" ] && echo "${svc_dir}/wydash.conf" && return
  fi
  echo ""
}

# ── Get WyDash port from .port file or service definition ─────────────────
find_wydash_port() {
  local conf="$1"
  local dir
  dir="$(dirname "$conf")"
  if [ -f "${dir}/.port" ]; then
    cat "${dir}/.port"
  else
    echo "9999"
  fi
}

# ── Check if a module is already enabled ──────────────────────────────────
module_enabled() {
  local conf="$1" module="$2"
  grep -q "^${module}\s*=\s*true" "$conf" 2>/dev/null
}

# ── Enable a module in wydash.conf ────────────────────────────────────────
enable_wydash_module() {
  local conf="$1" module="$2"
  if grep -q "^${module}\s*=" "$conf"; then
    # Line exists — flip false→true
    sed -i "s/^${module}\s*=\s*false/${module} = true/" "$conf"
  else
    # Module line missing (old conf) — append under [modules]
    sed -i "/^\[modules\]/a ${module} = true" "$conf"
  fi
}

# ── Main entry point: call this at end of any component installer ──────────
# Usage: offer_wydash_module "fiber"
#        offer_wydash_module "ckb_node"
#        offer_wydash_module "mining"
offer_wydash_module() {
  local MODULE="$1"
  local CONF
  CONF=$(find_wydash_conf)

  # Colour helpers (graceful if not defined by caller)
  local G="${GREEN:-}"  Y="${YELLOW:-}"  C="${CYAN:-}"  B="${BOLD:-}"  R="${RESET:-}"

  echo ""
  echo -e "${B}── WyDash Integration ───────────────────────────────────────────${R}"

  if [ -n "$CONF" ]; then
    local PORT
    PORT=$(find_wydash_port "$CONF")

    if module_enabled "$CONF" "$MODULE"; then
      echo -e "${G}✅ WyDash detected — ${MODULE} module already enabled.${R}"
      echo -e "   Dashboard: ${C}http://localhost:${PORT}${R}"
    else
      echo -e "${C}WyDash detected at: ${CONF}${R}"
      echo -n "   Enable the ${B}${MODULE}${R} module in WyDash? [Y/n] "
      read -r ans </dev/tty
      if [[ "${ans:-y}" != "n" && "${ans:-y}" != "N" ]]; then
        enable_wydash_module "$CONF" "$MODULE"
        echo -e "${G}✅ ${MODULE} module enabled. Refresh WyDash to see it.${R}"
        echo -e "   Dashboard: ${C}http://localhost:${PORT}${R}"
      else
        echo -e "${Y}   Skipped. Edit ${CONF} manually to enable later.${R}"
      fi
    fi

  else
    # WyDash not installed — mention it as optional
    echo -e "   No WyDash install found."
    echo -e "   WyDash is a browser-based dashboard for managing your CKB stack."
    echo -e "   Install it later: ${C}curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/wydash/install.sh | bash${R}"
  fi

  echo -e "─────────────────────────────────────────────────────────────────"
  echo ""
}

# ── Detect old installs (v1.0 / v1.1) for upgrade flows ───────────────────
# Returns: "none" | "v1.0" | "v1.1"
detect_legacy_fiber() {
  # v1.1 = systemd service named 'fiber' or 'fnn'
  for svc in fiber fnn fiber-mainnet fiber-testnet; do
    if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
      echo "v1.1"; return
    fi
  done
  # v1.0 = manual process or binary present but no service
  for bin in "$HOME/.fiber/bin/fnn" "$HOME/fiber/bin/fnn" "$HOME/.fiber-mainnet/bin/fnn"; do
    [ -f "$bin" ] && echo "v1.0" && return
  done
  echo "none"
}
