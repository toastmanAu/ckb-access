"""
settings.py — Service management and configuration
Start/stop light client, toggle boot service, view config.
"""

import pygame
import subprocess
import os
import threading
import urllib.request
import json
from lib.ui import Page, ScrollList, COLORS, draw_text, draw_status_bar, draw_nav_bar, draw_hline


class SettingsPage(Page):

    def __init__(self, app, rpc, install_dir="/userdata/ckb-light-client"):
        super().__init__(app)
        self.rpc = rpc
        self.install_dir = install_dir
        self.message = ""
        self.message_color = COLORS["text"]
        self.message_timer = 0
        self._installing = False

        self.menu = ScrollList([], item_height=32, visible_area_top=80, visible_area_bottom=32)
        self._rebuild_menu()

    def on_enter(self):
        self._rebuild_menu()

    def update(self, dt):
        if self.message_timer > 0:
            self.message_timer -= dt
            if self.message_timer <= 0:
                self.message = ""

    def _rebuild_menu(self):
        running = self._is_running()
        service = self._has_service()

        items = [
            {
                "text": "Stop Light Client" if running else "Start Light Client",
                "subtext": "● Running" if running else "○ Stopped",
                "subcolor": COLORS["green"] if running else COLORS["red"],
                "action": "toggle_service",
            },
            {
                "text": "Disable Boot Service" if service else "Enable Boot Service",
                "subtext": "auto-start on boot",
                "action": "toggle_boot",
            },
            {
                "text": "Install / Update Light Client",
                "subtext": self._install_status(),
                "subcolor": COLORS["green"] if self._binary_exists() else COLORS["yellow"],
                "action": "install_update",
            },
            {"text": "", "subtext": "", "action": None},  # divider
            {
                "text": "View Config",
                "subtext": "config.toml",
                "action": "view_config",
            },
            {
                "text": "View Log (last 20 lines)",
                "subtext": "ckb-light.log",
                "action": "view_log",
            },
            {
                "text": "Network Info",
                "subtext": self._read_network(),
                "action": None,
            },
            {
                "text": "Install Dir",
                "subtext": self.install_dir,
                "subcolor": COLORS["muted"],
                "action": None,
            },
            {
                "text": "RPC Port",
                "subtext": self._read_rpc_port(),
                "action": None,
            },
        ]
        self.menu.update_items(items)

    def _is_running(self):
        pid_file = os.path.join(self.install_dir, "data", "ckb-light.pid")
        try:
            with open(pid_file) as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)
            return True
        except:
            return False

    def _binary_exists(self):
        return os.path.isfile(os.path.join(self.install_dir, "bin", "ckb-light-client"))

    def _install_status(self):
        if self._binary_exists():
            try:
                result = subprocess.run(
                    [os.path.join(self.install_dir, "bin", "ckb-light-client"), "--version"],
                    capture_output=True, text=True, timeout=5)
                ver = result.stdout.strip().split()[-1] if result.stdout else "installed"
                return f"v{ver}" if not ver.startswith("v") else ver
            except:
                return "installed"
        return "not installed"

    def _has_service(self):
        """Check if an init script or cron entry exists for auto-start."""
        # Check common locations
        for path in ["/etc/init.d/S99ckb-light", "/etc/init.d/ckb-light"]:
            if os.path.exists(path):
                return True
        # Check crontab
        try:
            result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=3)
            if "ckb-light" in result.stdout:
                return True
        except:
            pass
        return False

    def _read_network(self):
        config_path = os.path.join(self.install_dir, "config.toml")
        try:
            with open(config_path) as f:
                for line in f:
                    if line.strip().startswith("chain"):
                        return line.split("=")[1].strip().strip('"')
        except:
            pass
        return "unknown"

    def _read_rpc_port(self):
        config_path = os.path.join(self.install_dir, "config.toml")
        try:
            with open(config_path) as f:
                for line in f:
                    if "listen_address" in line and "rpc" not in line[:10]:
                        continue
                    if "listen_address" in line:
                        return line.split("=")[1].strip().strip('"')
        except:
            pass
        return "127.0.0.1:9000"

    def _set_message(self, text, color=None, duration=3000):
        self.message = text
        self.message_color = color or COLORS["text"]
        self.message_timer = duration

    def _toggle_service(self):
        if self._is_running():
            # Stop
            try:
                subprocess.run([os.path.join(self.install_dir, "stop.sh")],
                               capture_output=True, timeout=5)
                self._set_message("Light client stopped", COLORS["yellow"])
            except Exception as e:
                self._set_message(f"Error: {e}", COLORS["red"])
        else:
            # Start
            try:
                subprocess.run([os.path.join(self.install_dir, "start.sh")],
                               capture_output=True, timeout=5)
                self._set_message("Light client started", COLORS["green"])
            except Exception as e:
                self._set_message(f"Error: {e}", COLORS["red"])
        self._rebuild_menu()

    def _toggle_boot(self):
        """Create or remove an init.d script for auto-start on Knulli/Buildroot."""
        init_script = "/etc/init.d/S99ckb-light"
        if self._has_service():
            try:
                os.remove(init_script)
                self._set_message("Boot service disabled", COLORS["yellow"])
            except Exception as e:
                self._set_message(f"Error: {e}", COLORS["red"])
        else:
            try:
                script = f"""#!/bin/sh
# CKB Light Client auto-start
case "$1" in
  start)
    {self.install_dir}/start.sh
    ;;
  stop)
    {self.install_dir}/stop.sh
    ;;
  *)
    echo "Usage: $0 {{start|stop}}"
    exit 1
    ;;
esac
"""
                with open(init_script, "w") as f:
                    f.write(script)
                os.chmod(init_script, 0o755)
                self._set_message("Boot service enabled", COLORS["green"])
            except Exception as e:
                self._set_message(f"Error: {e}", COLORS["red"])
        self._rebuild_menu()

    def _view_config(self):
        """Navigate to a text viewer showing the config file."""
        config_path = os.path.join(self.install_dir, "config.toml")
        try:
            with open(config_path) as f:
                content = f.read()
            if "text_viewer" in self.app.pages:
                self.app.pages["text_viewer"].set_content("config.toml", content)
                self.app.navigate("text_viewer")
        except Exception as e:
            self._set_message(f"Error: {e}", COLORS["red"])

    def _view_log(self):
        """Navigate to text viewer showing last 20 lines of log."""
        log_path = os.path.join(self.install_dir, "data", "ckb-light.log")
        try:
            with open(log_path) as f:
                lines = f.readlines()
            content = "".join(lines[-20:])
            if "text_viewer" in self.app.pages:
                self.app.pages["text_viewer"].set_content("ckb-light.log (last 20)", content)
                self.app.navigate("text_viewer")
        except Exception as e:
            self._set_message(f"Error: {e}", COLORS["red"])

    def draw(self, surface):
        draw_status_bar(surface, "Settings", "")
        w = surface.get_width()

        # ── Service status indicator panel ────────────────────
        y = 36
        panel = pygame.Rect(8, y, w - 16, 38)
        running = self._is_running()
        installed = self._binary_exists()
        service = self._has_service()

        bg = COLORS["surface"]
        pygame.draw.rect(surface, bg, panel, border_radius=6)
        border_color = COLORS["green"] if running else COLORS["border"]
        pygame.draw.rect(surface, border_color, panel, width=1, border_radius=6)

        # Status dot + text
        dot_color = COLORS["green"] if running else COLORS["red"] if installed else COLORS["yellow"]
        pygame.draw.circle(surface, dot_color, (24, y + 19), 5)

        if running:
            draw_text(surface, "Light Client Running", 36, y + 4, COLORS["green"], size=13, bold=True)
        elif installed:
            draw_text(surface, "Light Client Stopped", 36, y + 4, COLORS["red"], size=13, bold=True)
        else:
            draw_text(surface, "Light Client Not Installed", 36, y + 4, COLORS["yellow"], size=13, bold=True)

        # Sub-info
        tags = []
        if installed:
            tags.append(self._install_status())
        if service:
            tags.append("boot: on")
        else:
            tags.append("boot: off")
        if running:
            tags.append(self._read_network())
        draw_text(surface, " · ".join(tags), 36, y + 21, COLORS["muted"], size=10)

        self.menu.draw(surface)

        # Message toast
        if self.message:
            y = surface.get_height() - 60
            draw_text(surface, self.message, 16, y, self.message_color, size=13)

        draw_nav_bar(surface, [("B", "Back"), ("A", "Select"), ("D-pad", "Scroll")])

    def handle_input(self, event):
        if event.type == pygame.USEREVENT:
            d = event.dict.get("dpad", "")
            if d == "up": self.menu.move(-1)
            elif d == "down": self.menu.move(1)
            return True

        if event.type == pygame.JOYBUTTONDOWN and event.button == 0:
            return self._activate_selected()

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_UP: self.menu.move(-1)
            elif event.key == pygame.K_DOWN: self.menu.move(1)
            elif event.key == pygame.K_RETURN: return self._activate_selected()
            return True

        return False

    def _activate_selected(self):
        selected = self.menu.get_selected()
        if not selected or not selected.get("action"):
            return False
        action = selected["action"]
        if action == "toggle_service":
            self._toggle_service()
        elif action == "toggle_boot":
            self._toggle_boot()
        elif action == "view_config":
            self._view_config()
        elif action == "view_log":
            self._view_log()
        elif action == "install_update":
            self._install_update()
        return True

    def _install_update(self):
        """Download and install/update the light client binary."""
        if self._installing:
            return
        self._installing = True
        self._set_message("Checking latest version...", COLORS["accent"], duration=30000)

        def _do_install():
            try:
                # Find latest release with arm64 binary
                arch = os.uname().machine
                if arch in ("aarch64", "arm64"):
                    target_arch = "aarch64-linux"
                elif arch == "x86_64":
                    target_arch = "x86_64-linux"
                else:
                    self._set_message(f"Unsupported arch: {arch}", COLORS["red"])
                    self._installing = False
                    return

                # Check GitHub releases for latest version with our binary
                releases_url = "https://api.github.com/repos/nervosnetwork/ckb-light-client/releases?per_page=5"
                req = urllib.request.Request(releases_url, headers={"User-Agent": "nervos-wallet"})
                with urllib.request.urlopen(req, timeout=15) as resp:
                    releases = json.loads(resp.read().decode())

                # Find first release with matching binary
                download_url = None
                version = None
                for rel in releases:
                    for asset in rel.get("assets", []):
                        name = asset.get("name", "")
                        if target_arch in name and name.endswith(".tar.gz"):
                            # Prefer portable build
                            if "portable" in name or download_url is None:
                                download_url = asset["browser_download_url"]
                                version = rel["tag_name"]
                            if "portable" in name:
                                break
                    if download_url:
                        break

                if not download_url:
                    self._set_message(f"No {target_arch} binary found in releases", COLORS["red"])
                    self._installing = False
                    return

                self._set_message(f"Downloading {version}...", COLORS["accent"], duration=60000)

                # Download
                os.makedirs(os.path.join(self.install_dir, "bin"), exist_ok=True)
                tarball = os.path.join("/tmp", "ckb-light-update.tar.gz")
                urllib.request.urlretrieve(download_url, tarball)

                # Extract
                self._set_message("Extracting...", COLORS["accent"], duration=30000)
                result = subprocess.run(
                    f"cd /tmp && tar -xzf ckb-light-update.tar.gz && "
                    f"find /tmp -name 'ckb-light-client' -type f -newer {tarball} | head -1",
                    shell=True, capture_output=True, text=True, timeout=30)
                bin_path = result.stdout.strip()

                if not bin_path:
                    # Fallback: find any extracted binary
                    result = subprocess.run(
                        "find /tmp -name 'ckb-light-client' -type f | head -1",
                        shell=True, capture_output=True, text=True, timeout=10)
                    bin_path = result.stdout.strip()

                if not bin_path or not os.path.isfile(bin_path):
                    self._set_message("Binary not found in archive", COLORS["red"])
                    self._installing = False
                    return

                # Stop running instance if any
                was_running = self._is_running()
                if was_running:
                    subprocess.run([os.path.join(self.install_dir, "stop.sh")],
                                   capture_output=True, timeout=5)

                # Install
                dest = os.path.join(self.install_dir, "bin", "ckb-light-client")
                subprocess.run(["cp", bin_path, dest], check=True, timeout=5)
                os.chmod(dest, 0o755)

                # Download config if missing
                config_path = os.path.join(self.install_dir, "config.toml")
                if not os.path.exists(config_path):
                    self._set_message("Downloading config...", COLORS["accent"], duration=10000)
                    config_url = "https://raw.githubusercontent.com/nervosnetwork/ckb-light-client/develop/config/testnet.toml"
                    urllib.request.urlretrieve(config_url, config_path)
                    os.makedirs(os.path.join(self.install_dir, "data", "store"), exist_ok=True)
                    os.makedirs(os.path.join(self.install_dir, "data", "network"), exist_ok=True)

                # Create wrapper scripts if missing
                self._ensure_scripts()

                # Restart if was running
                if was_running:
                    subprocess.run([os.path.join(self.install_dir, "start.sh")],
                                   capture_output=True, timeout=5)

                # Cleanup
                os.remove(tarball)

                self._set_message(f"Installed {version}", COLORS["green"])
                self._rebuild_menu()

            except Exception as e:
                self._set_message(f"Install failed: {e}", COLORS["red"])
            finally:
                self._installing = False

        threading.Thread(target=_do_install, daemon=True).start()

    def _ensure_scripts(self):
        """Create start/stop/status scripts if they don't exist."""
        scripts = {
            "start.sh": '''#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Starting CKB light client..."
RUST_LOG=info,ckb_light_client=info \\
  nohup "$DIR/bin/ckb-light-client" run --config-file "$DIR/config.toml" \\
  >> "$DIR/data/ckb-light.log" 2>&1 &
echo "PID: $!"
echo "$!" > "$DIR/data/ckb-light.pid"
''',
            "stop.sh": '''#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$DIR/data/ckb-light.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null && echo "Stopped" || echo "Not running"
  rm -f "$PID_FILE"
else
  pkill -f ckb-light-client 2>/dev/null && echo "Stopped" || echo "Not running"
fi
''',
            "status.sh": '''#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$DIR/data/ckb-light.pid"
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
  echo "Running (PID $(cat "$PID_FILE"))"
else
  echo "Not running"
fi
curl -s -X POST http://127.0.0.1:9000/ \\
  -H 'Content-Type: application/json' \\
  -d '{"jsonrpc":"2.0","method":"get_tip_header","params":[],"id":1}' | python3 -m json.tool 2>/dev/null || echo "(RPC not responding)"
''',
        }
        for name, content in scripts.items():
            path = os.path.join(self.install_dir, name)
            if not os.path.exists(path):
                with open(path, "w") as f:
                    f.write(content)
                os.chmod(path, 0o755)
