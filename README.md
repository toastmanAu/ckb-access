# ckb-access

One-command installers for Nervos CKB network tools. Works on Linux, macOS, and Windows.

## Tools

| Tool | Description | Platforms |
|------|-------------|-----------|
| [fiber](./fiber/) | Fiber Network payment channel node | Linux · macOS · Windows |
| ckb-node | Full CKB node *(coming soon)* | — |
| ckb-light | CKB light client *(coming soon)* | — |

## Quick Start

### Fiber Network Node

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/toastmanAu/ckb-access/main/fiber/install.sh | bash
```

**Windows (PowerShell as Admin):**
```powershell
irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/fiber/install.ps1 | iex
```

## About

Built by the Nervos community to make running CKB infrastructure accessible to everyone.

- No manual config required — sensible defaults, Enter-key install
- Auto-installs dependencies (VC++ runtime, Python) on Windows
- Includes a local dashboard for monitoring your node
- Linux systemd · macOS launchctl · Windows NSSM service management

## Community

- [Nervos Nation](https://t.me/NervosNation)
- [Nervos Discord](https://discord.gg/nervos)
