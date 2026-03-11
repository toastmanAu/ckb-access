# ckb-access

One-command installers for Nervos CKB network tools. Works on Linux, macOS, and Windows.

## Tools

| Tool | Description | Version | Platforms |
|------|-------------|---------|-----------|
| [fiber](./fiber/) | Fiber Network payment channel node | v0.7.1 | Linux · macOS · Windows |
| [ckb-light](./ckb-light/) | CKB light client — headers only, ~50MB | v0.5.4 | Linux · macOS · Windows |
| [ckb-node](./ckb-node/) | CKB full node — complete blockchain | v0.204.0 | Linux · macOS · Windows |
| [ckb-cli](./ckb-cli/) | CKB command-line wallet & tools | v2.0.0 | Linux · macOS · Windows |

## Quick Start

### Fiber Network Node
Payment channels on CKB — open/close channels, send/receive off-chain.

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/fiber/install.sh | bash
```
**Windows (PowerShell as Admin):**
```powershell
irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/fiber/install.ps1 | iex
```

---

### CKB Light Client
Sync in seconds instead of days. Compatible with ckb-indexer RPC — drop-in for most tooling.

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-light/install.sh | bash
```
**Windows:**
```powershell
irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-light/install.ps1 | iex
```

---

### CKB Full Node
Run the complete chain. Required for mining and maximum trustlessness. (~200GB disk)

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-node/install.sh | bash
```
**Windows:**
```powershell
irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-node/install.ps1 | iex
```

---

### CKB CLI
Command-line wallet and developer tools for CKB.

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-cli/install.sh | bash
```
**Windows:**
```powershell
irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-cli/install.ps1 | iex
```

---

## Platform Support

| Platform | fiber | ckb-light | ckb-node | ckb-cli |
|----------|-------|-----------|----------|---------|
| Linux x86_64 | ✅ | ✅ | ✅ | ✅ |
| Linux arm64 (Pi/OrangePi) | ✅ | ⚙️ build* | ✅ | ✅ |
| macOS x86_64 | ✅ | ✅ | ✅ | ✅ |
| macOS arm64 (M1/M2/M3) | ✅ | ⚙️ build* | ✅ | ✅ |
| Windows x86_64 | ✅ | ✅ | ✅ | ✅ |

*ckb-light arm64 prebuilt binary coming in next release ([#272](https://github.com/nervosnetwork/ckb-light-client/issues/272)). Installer auto-builds from source in the meantime.

## About

Built by the Nervos community to make running CKB infrastructure accessible to everyone.

- **No manual config required** — sensible defaults, Enter-key install works
- **Auto-installs dependencies** — VC++ runtime, Python, Rust toolchain as needed
- **Service management** — systemd (Linux) · launchd (macOS) · NSSM (Windows)
- **Smoke test** — every installer verifies the binary starts and RPC responds before finishing
- **Tested end-to-end** on Raspberry Pi · Ubuntu · macOS · Windows 10

## Community

- [Nervos Nation Telegram](https://t.me/NervosNation)
- [Nervos Discord](https://discord.gg/nervos)
- [Nervos Website](https://nervos.org)
