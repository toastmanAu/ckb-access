# CKB Light Client — Remote SSH Deployer

Deploy the Nervos CKB light client to any Linux machine over SSH. Supports arm64 (Pi, handhelds, SBCs) and amd64 (desktops, servers).

## Quick Start

```bash
# Interactive — prompts for everything
./deploy.sh

# Skip host prompt
./deploy.sh --host 192.168.1.50 --user phill
```

## What It Does

1. Connects to target via SSH (key auth preferred, password fallback)
2. Detects architecture, RAM, disk
3. Downloads prebuilt binary (amd64) or builds from source / accepts scp binary (arm64)
4. Generates correct `config.toml` with upstream bootnodes for mainnet or testnet
5. Creates `start.sh`, `stop.sh`, `status.sh`, `test-rpc.sh` on the target
6. Optionally installs a systemd service for auto-start
7. Runs a smoke test to verify RPC responds
8. For Knulli/handheld devices: creates an EmulationStation port launcher

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

## Part of ckb-access

This is a standalone tool in the [ckb-access](https://github.com/toastmanAu/ckb-access) repo. It does not depend on the main installers.
