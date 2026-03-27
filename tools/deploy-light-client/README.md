# CKB Light Client — Remote SSH Deployer

Deploy the Nervos CKB light client to any Linux machine over SSH. Supports arm64 (Pi, handhelds, SBCs) and amd64 (desktops, servers).

## Quick Start

```bash
# Interactive — prompts for everything
./deploy.sh

# Skip host prompt
./deploy.sh --host 192.168.1.50 --user phill

# After deployment, run verification report (saved locally)
./verify.sh --host 192.168.1.50 --user root
```

## What It Does

1. Connects to target via SSH (key auth preferred, password fallback)
2. Detects architecture, RAM, disk
3. Downloads prebuilt binary (amd64/arm64) or builds from source / accepts scp binary
4. Generates correct `config.toml` with upstream bootnodes for mainnet or testnet
5. Creates `start.sh`, `stop.sh`, `status.sh`, `test-rpc.sh` on the target
6. Optionally installs a systemd service for auto-start
7. Runs a smoke test to verify RPC responds
8. For Knulli/handheld devices: creates an EmulationStation port launcher

## Verification Script

After deploying, run `verify.sh` to generate a full health report **saved locally** (not on the remote device):

```bash
./verify.sh --host 192.168.68.110 --user root
```

Reports are saved to `tested/` with the format `<hostname>_<date>.md`. The script checks:
- Binary version and process status
- RPC connectivity (local_node_info, get_tip_header, get_peers)
- Sync progress and peer count
- CPU/RAM usage
- Disk usage
- Network config (mainnet/testnet)

## Prerequisites (on your machine)

- `ssh`, `scp`, `curl`
- `sshpass` (optional, only needed for password auth)

```bash
# Debian/Ubuntu
sudo apt install -y sshpass curl

# macOS
brew install hudochenkov/sshpass/sshpass
```

## Knulli / RG35XXH Support

If the target is a Knulli device, the script:
- Installs to `/userdata/ckb-light-client`
- Creates `/userdata/roms/ports/Nervos-Wallet.sh` launcher
- Optionally adds to EmulationStation systems config

After deploy, reboot the handheld or refresh ES — "Nervos Wallet" appears in the Ports menu.

## arm64 Binary Options

As of v0.5.5-rc1, **prebuilt arm64 binaries are available** (thanks to [PR #265](https://github.com/nervosnetwork/ckb-light-client/pull/265)). The deploy script will auto-download them — no build step needed.

If you need to build from source for an older version, you have two options:

1. **Build on target** — needs ~2GB RAM, takes 20-30 min on arm64
2. **Build once on a fast machine, scp to target** — recommended for low-RAM devices

To cross-compile for arm64 on an amd64 host:
```bash
rustup target add aarch64-unknown-linux-gnu
sudo apt install gcc-aarch64-linux-gnu
cargo build --release --target aarch64-unknown-linux-gnu --bin ckb-light-client
# Binary at: target/aarch64-unknown-linux-gnu/release/ckb-light-client
```

## Compatible Devices

Any Linux device with SSH, arm64 or x86_64, ~50MB free RAM, and ~100MB disk.

### Tier 1 — Easiest (standard Linux, SSH trivial, ample resources)

| Device | SoC | Arch | RAM | OS |
|--------|-----|------|-----|----|
| Raspberry Pi 5 | BCM2712 (Cortex-A76) | arm64 | 2–8GB | Raspberry Pi OS, Ubuntu |
| Raspberry Pi 4B | BCM2711 (Cortex-A72) | arm64 | 1–8GB | Raspberry Pi OS, Ubuntu |
| Orange Pi 5 / Plus | RK3588/S | arm64 | 4–32GB | Ubuntu, Armbian |
| Orange Pi 3B | RK3566 | arm64 | 2–8GB | Ubuntu, Armbian |
| ROCK 5B / 5A | RK3588/S | arm64 | 4–16GB | Ubuntu, Armbian |
| Steam Deck | AMD Zen 2 | x86_64 | 16GB | SteamOS |
| Any x86 Linux box | — | x86_64 | 2GB+ | Any distro |

### Tier 2 — Great (high-RAM handhelds with proven Linux CFW)

| Device | SoC | Arch | RAM | CFW |
|--------|-----|------|-----|-----|
| Retroid Pocket 5 / Mini | Snapdragon 865 | arm64 | 6–8GB | ROCKNIX, Batocera |
| Retroid Pocket 6 | Snapdragon 8 Gen 2 | arm64 | 8–16GB | ROCKNIX |
| Ayn Odin 2 / Pro / Max | Snapdragon 8 Gen 2 | arm64 | 8–16GB | ROCKNIX |
| AYANEO Pocket DMG / ACE | Snapdragon G3x Gen 2 | arm64 | 8–16GB | ROCKNIX |
| GameForce Ace | RK3588s | arm64 | 8–12GB | ROCKNIX |
| Anbernic RG552 | RK3399 | arm64 | 4GB | ROCKNIX |

### Tier 3 — Good (2GB RAM arm64 handhelds)

| Device | SoC | Arch | RAM | CFW |
|--------|-----|------|-----|-----|
| Anbernic RG353P/M/V/VS | RK3566 | arm64 | 2GB | ROCKNIX, ArkOS |
| Anbernic RG503 | RK3566 | arm64 | 2GB | ROCKNIX, ArkOS |
| Anbernic RG ARC-S / ARC-D | RK3566 | arm64 | 2GB | Knulli, ROCKNIX |
| Powkiddy X55 | RK3566 | arm64 | 2GB | Knulli, ROCKNIX |
| Powkiddy RGB10 Max 3 | RK3566 | arm64 | 2GB | ROCKNIX |
| Odroid Go Ultra | S922X | arm64 | 2GB | ROCKNIX |

### Tier 4 — Viable but tight (1GB RAM, ~50MB for light client)

| Device | SoC | Arch | RAM | CFW |
|--------|-----|------|-----|-----|
| Anbernic RG35XX Plus / H / SP | Allwinner H700 | arm64 | 1GB | Knulli, ROCKNIX, muOS |
| Anbernic RG40XX H / V | Allwinner H700 | arm64 | 1GB | Knulli, ROCKNIX, muOS |
| Anbernic RG28XX | Allwinner H700 | arm64 | 1GB | Knulli, ROCKNIX |
| Anbernic RG34XX / SP | Allwinner H700 | arm64 | 1GB | ROCKNIX, muOS |
| Anbernic RG CubeXX | Allwinner H700 | arm64 | 1GB | Knulli, ROCKNIX |
| Powkiddy RGB30 | RK3566 | arm64 | 1GB | Knulli, ROCKNIX |
| TrimUI Smart Pro / Brick | Allwinner A133P | arm64 | 1GB | Knulli |
| Raspberry Pi Zero 2 W | RP3A0 | arm64 | 512MB | Raspberry Pi OS |

### x86_64 Linux Handhelds

| Device | CPU | RAM | OS |
|--------|-----|-----|----|
| Steam Deck LCD / OLED | AMD Zen 2 | 16GB | SteamOS |
| Lenovo Legion Go / Go S | AMD Ryzen Z1/Z2 | 16GB | SteamOS, Bazzite |
| AYANEO 2S / NEXT II / Geek | AMD Ryzen 7000+ | 16–64GB | SteamOS, Bazzite |
| GPD WIN 4 / WIN Max 2 | AMD Ryzen 7000+ | 16–32GB | SteamOS, Bazzite |

### Not Compatible (arm32 only)

| Device | Reason |
|--------|--------|
| Miyoo Mini / Mini Plus | Allwinner V3s — arm32 only |
| Miyoo A30 | Allwinner A33 — arm32 only |
| Anbernic RG35XX (original 2023) | Ships with 32-bit firmware |

### SSH Quick Reference by Firmware

| Firmware | Default User | Default Pass | Enable SSH |
|----------|-------------|-------------|------------|
| **Knulli** | root | (set during setup) | Settings > Network > Enable SSH |
| **ROCKNIX** | root | rocknix | START > Network > Enable SSH |
| **muOS** | root | root | Web Services > Enable SFTP |
| **ArkOS** | ark | ark | Enabled by default |
| **Batocera** | root | linux | Enabled by default |
| **Raspberry Pi OS** | pi | (set during imaging) | raspi-config or `touch /boot/ssh` |
| **SteamOS** | deck | (set via passwd) | `sudo systemctl enable --now sshd` |
| **Ubuntu/Armbian** | varies | varies | `apt install openssh-server` |

## Tested Devices

See the [`tested/`](./tested/) directory for verified deployment reports with resource usage, sync status, and RPC test results.

## Part of ckb-access

This is a standalone tool in the [ckb-access](https://github.com/toastmanAu/ckb-access) repo. It does not depend on the main installers.
