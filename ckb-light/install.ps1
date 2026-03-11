#Requires -Version 5.1
# CKB Light Client installer — Windows (PowerShell 5.1+)
# Run as Admin: irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-light/install.ps1 | iex

$script:VERSION    = "0.5.4"
$script:BINARY     = "ckb-light-client.exe"
$script:REPO       = "nervosnetwork/ckb-light-client"
$script:CONFIG_BASE = "https://raw.githubusercontent.com/nervosnetwork/ckb-light-client/main/config"

# ── Helpers ───────────────────────────────────────────────
function Write-Step  { param($m) Write-Host "`n  >> $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Info  { param($m) Write-Host "  [i]  $m" -ForegroundColor Gray }
function Write-Err   { param($m) Write-Host "  [X]  $m" -ForegroundColor Red }

function Ask {
    param($Prompt, $Default)
    $val = Read-Host "  $Prompt [$Default]"
    if ($val -eq "") { return $Default }
    return $val
}

# ── Banner ────────────────────────────────────────────────
function Show-Banner {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CKB Light Client Installer v1.0       |" -ForegroundColor Cyan
    Write-Host "  |   Nervos CKB - nervosnetwork             |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Light client - syncs headers only, ~50MB vs ~200GB full node" -ForegroundColor Gray
    Write-Host "  Compatible with ckb-indexer RPC - drop-in for most tooling" -ForegroundColor Gray
    Write-Host ""
}

# ── Config ────────────────────────────────────────────────
function Collect-Config {
    Write-Step "Configuration"
    $script:NETWORK     = Ask "Network (mainnet/testnet)" "mainnet"
    $script:INSTALL_DIR = Ask "Install directory" "$env:USERPROFILE\.ckb-light-$($script:NETWORK)"
    $script:P2P_PORT    = Ask "P2P listen port" "8118"
    $script:RPC_PORT    = Ask "RPC listen port" "9000"
    $script:MAX_PEERS   = Ask "Max peers" "125"

    $script:DATA_DIR    = "$($script:INSTALL_DIR)\data"
    $script:CONFIG_FILE = "$($script:INSTALL_DIR)\config.toml"
    $script:LOG_FILE    = "$($script:DATA_DIR)\ckb-light.log"

    Write-Host ""
    Write-Ok "Network:     $($script:NETWORK)"
    Write-Ok "Install dir: $($script:INSTALL_DIR)"
    Write-Ok "P2P port:    $($script:P2P_PORT)"
    Write-Ok "RPC port:    $($script:RPC_PORT)"
}

# ── Download binary ───────────────────────────────────────
function Download-Binary {
    param($InstallDir)
    $ErrorActionPreference = "Stop"
    Write-Step "Downloading ckb-light-client v$($script:VERSION)"

    # Windows is always x86_64 — prebuilt binary always available
    $tarball = "ckb-light-client_v$($script:VERSION)-x86_64-windows.tar.gz"
    $url     = "https://github.com/$($script:REPO)/releases/download/v$($script:VERSION)/$tarball"

    # Verify URL exists before downloading
    try {
        $null = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Err "Release tarball not found at: $url"
        Write-Info "Check https://github.com/$($script:REPO)/releases for available versions"
        exit 1
    }

    $tmp     = "$env:TEMP\ckb-light-$($script:VERSION)"
    $archive = "$tmp\$tarball"

    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    New-Item -ItemType Directory -Force -Path "$InstallDir\bin" | Out-Null
    New-Item -ItemType Directory -Force -Path "$($script:DATA_DIR)\store" | Out-Null
    New-Item -ItemType Directory -Force -Path "$($script:DATA_DIR)\network" | Out-Null

    Write-Info "Downloading from GitHub..."
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing

    Write-Info "Extracting..."
    & tar -xzf $archive -C $tmp 2>&1 | Out-Null

    $binSrc = Get-ChildItem -Path $tmp -Filter "ckb-light-client.exe" -Recurse | Select-Object -First 1
    if (-not $binSrc) {
        Write-Err "Binary not found in tarball"
        exit 1
    }
    Copy-Item $binSrc.FullName "$InstallDir\bin\$($script:BINARY)" -Force
    Write-Ok "Binary installed: $InstallDir\bin\$($script:BINARY)"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Write config ──────────────────────────────────────────
function Write-LightConfig {
    param($InstallDir, $DataDir, $Network, $P2pPort, $RpcPort, $MaxPeers)
    Write-Step "Writing config"

    # Fetch bootnodes from upstream
    $bootnodes = ""
    try {
        $apiUrl = "https://api.github.com/repos/$($script:REPO)/contents/config/$Network.toml"
        $resp = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing | ConvertFrom-Json
        $raw  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($resp.content))
        # Extract bootnodes block
        $lines    = $raw -split "`n"
        $inBlock  = $false
        $bnLines  = @()
        foreach ($line in $lines) {
            if ($line -match "^bootnodes") { $inBlock = $true }
            if ($inBlock) {
                $bnLines += $line
                if ($line -match "^\]") { $inBlock = $false; break }
            }
        }
        $bootnodes = $bnLines -join "`n"
    } catch {
        Write-Warn "Could not fetch upstream bootnodes — using empty list (node will still find peers)"
        $bootnodes = "bootnodes = []"
    }

    $config = @"
chain = "$Network"

[store]
path = "data/store"

[network]
path = "data/network"
listen_addresses = ["/ip4/0.0.0.0/tcp/$P2pPort"]
$bootnodes

max_peers = $MaxPeers
max_outbound_peers = 8
ping_interval_secs = 120
ping_timeout_secs = 1200
connect_outbound_interval_secs = 15
upnp = false
discovery_local_address = false
bootnode_mode = false

[rpc]
listen_address = "127.0.0.1:$RpcPort"
"@
    $config | Set-Content -Path $script:CONFIG_FILE -Encoding UTF8
    Write-Ok "Config written: $($script:CONFIG_FILE)"
}

# ── Start bat ─────────────────────────────────────────────
function Write-StartBat {
    param($InstallDir)
    $bat = @"
@echo off
set RUST_LOG=info,ckb_light_client=info
"$InstallDir\bin\$($script:BINARY)" run --config-file "$($script:CONFIG_FILE)" >> "$($script:LOG_FILE)" 2>&1
"@
    $bat | Set-Content -Path "$InstallDir\start-ckb-light.bat" -Encoding ASCII
    Write-Ok "Start script: $InstallDir\start-ckb-light.bat"
}

# ── Service (NSSM) ────────────────────────────────────────
function Install-Service {
    param($InstallDir, $Network)
    Write-Step "Installing Windows Service"
    $svcName = if ($Network -eq "testnet") { "CkbLightTestnet" } else { "CkbLight" }

    $nssmExe = "$InstallDir\bin\nssm.exe"
    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"

    try {
        $tmp = "$env:TEMP\nssm-dl"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        Invoke-WebRequest -Uri $nssmUrl -OutFile "$tmp\nssm.zip" -UseBasicParsing
        & tar -xf "$tmp\nssm.zip" -C $tmp 2>&1 | Out-Null
        $nssmSrc = Get-ChildItem -Path $tmp -Filter "nssm.exe" -Recurse |
                   Where-Object { $_.FullName -like "*win64*" } | Select-Object -First 1
        if (-not $nssmSrc) {
            $nssmSrc = Get-ChildItem -Path $tmp -Filter "nssm.exe" -Recurse | Select-Object -First 1
        }
        if ($nssmSrc) {
            Copy-Item $nssmSrc.FullName $nssmExe -Force
        }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warn "Could not install NSSM — service not created. Use start-ckb-light.bat to run manually."
        return
    }

    # Remove existing service
    & $nssmExe stop $svcName 2>&1 | Out-Null
    & $nssmExe remove $svcName confirm 2>&1 | Out-Null
    Start-Sleep 1

    & $nssmExe install $svcName "$InstallDir\bin\$($script:BINARY)" | Out-Null
    & $nssmExe set $svcName AppParameters "run --config-file `"$($script:CONFIG_FILE)`"" | Out-Null
    & $nssmExe set $svcName AppDirectory $InstallDir | Out-Null
    & $nssmExe set $svcName AppEnvironmentExtra "RUST_LOG=info,ckb_light_client=info" | Out-Null
    & $nssmExe set $svcName AppStdout $script:LOG_FILE | Out-Null
    & $nssmExe set $svcName AppStderr $script:LOG_FILE | Out-Null
    & $nssmExe set $svcName Start SERVICE_AUTO_START | Out-Null

    Write-Ok "Service installed: $svcName"
    Write-Info "Manage with: nssm start/stop/restart $svcName"
}

# ── PATH ──────────────────────────────────────────────────
function Add-ToPath {
    param($InstallDir)
    $binDir = "$InstallDir\bin"
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$binDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$current;$binDir", "User")
        $env:PATH += ";$binDir"
        Write-Ok "Added $binDir to PATH"
    }
}

# ── Firewall ──────────────────────────────────────────────
function Add-FirewallRule {
    param($Port, $Network)
    Write-Step "Firewall"
    $ruleName = "CKB Light Client ($Network) P2P"
    try {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Ok "Firewall rule already exists"
            return
        }
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound `
            -Protocol TCP -LocalPort $Port -Action Allow -ErrorAction Stop | Out-Null
        Write-Ok "Firewall rule added: TCP port $Port"
    } catch {
        Write-Warn "Could not add firewall rule — add manually if needed: TCP port $Port"
    }
}

# ── Smoke test ────────────────────────────────────────────
function Run-SmokeTest {
    param($InstallDir, $ConfigFile, $RpcPort)
    Write-Step "Smoke Test"
    Write-Info "Starting light client briefly to verify it launches..."

    $binExe = "$InstallDir\bin\$($script:BINARY)"

    # Kill any existing process
    try { $null = & taskkill /IM $script:BINARY /F 2>&1 } catch {}
    Start-Sleep 2

    # Set env and launch hidden
    $env:RUST_LOG = "info,ckb_light_client=info"
    $proc = Start-Process -FilePath $binExe `
        -ArgumentList "run --config-file `"$ConfigFile`"" `
        -WindowStyle Hidden -PassThru

    $smokePass = $false
    $rpcUrl    = "http://127.0.0.1:$RpcPort"
    $body      = '{"jsonrpc":"2.0","method":"local_node_info","params":[],"id":1}'
    Write-Host "  Waiting for RPC on 127.0.0.1:$RpcPort" -NoNewline

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep 1
        Write-Host "." -NoNewline
        try {
            $r = Invoke-WebRequest -Uri $rpcUrl -Method POST `
                 -Body $body -ContentType "application/json" `
                 -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($r.Content -like '*node_id*') {
                $smokePass = $true
                $nodeId = ($r.Content | ConvertFrom-Json).result.node_id
                break
            }
        } catch {}
    }
    Write-Host ""

    # Kill smoke test process
    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
    Start-Sleep 1
    try { $null = & taskkill /IM $script:BINARY /F 2>&1 } catch {}
    Start-Sleep 1
    Write-Ok "Smoke test node stopped"

    if ($smokePass) {
        Write-Ok "Smoke test passed!"
        Write-Ok "Node ID: $nodeId"
    } else {
        Write-Warn "Smoke test timed out — check logs: $($script:LOG_FILE)"
    }
}

# ── Summary ───────────────────────────────────────────────
function Show-Summary {
    param($InstallDir, $Network, $P2pPort, $RpcPort)
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  CKB Light Client installed!" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""
    Write-Ok "Network:     $Network"
    Write-Ok "Version:     v$($script:VERSION)"
    Write-Ok "Install dir: $InstallDir"
    Write-Ok "Config:      $($script:CONFIG_FILE)"
    Write-Ok "Log:         $($script:LOG_FILE)"
    Write-Ok "P2P port:    $P2pPort"
    Write-Ok "RPC port:    $RpcPort (localhost only)"
    Write-Host ""
    Write-Ok "RPC endpoint: http://127.0.0.1:$RpcPort"
    Write-Host ""
    Write-Info "Test RPC after start:"
    Write-Info "  curl -X POST http://127.0.0.1:$RpcPort -H 'Content-Type: application/json' -d '{`"jsonrpc`":`"2.0`",`"method`":`"local_node_info`",`"params`":[],`"id`":1}'"
    Write-Host ""
}

# ── Start now? ────────────────────────────────────────────
function Start-LightNode {
    param($InstallDir, $Network)
    $svcName = if ($Network -eq "testnet") { "CkbLightTestnet" } else { "CkbLight" }
    $nssmExe = "$InstallDir\bin\nssm.exe"

    Write-Step "Start Node?"
    $startNow = Ask "Start ckb-light-client now?" "Y"
    if ($startNow -match "^[Yy]") {
        if (Test-Path $nssmExe) {
            & $nssmExe start $svcName 2>&1 | Out-Null
            Write-Ok "Service started: $svcName"
            Write-Info "Manage: nssm start/stop/restart $svcName"
        } else {
            $bat = "$InstallDir\start-ckb-light.bat"
            Start-Process -FilePath "cmd" -ArgumentList "/c `"$bat`"" -WindowStyle Minimized
            Write-Ok "Started via bat file (minimized window)"
        }
        Write-Info "Check logs: $($script:LOG_FILE)"
    } else {
        if (Test-Path $nssmExe) {
            Write-Info "To start: nssm start $svcName"
        } else {
            Write-Info "To start: $InstallDir\start-ckb-light.bat"
        }
    }
}

# ── Main ──────────────────────────────────────────────────
Show-Banner
Collect-Config

Download-Binary  -InstallDir $script:INSTALL_DIR
Write-LightConfig -InstallDir $script:INSTALL_DIR -DataDir $script:DATA_DIR `
                  -Network $script:NETWORK -P2pPort $script:P2P_PORT `
                  -RpcPort $script:RPC_PORT -MaxPeers $script:MAX_PEERS
Write-StartBat   -InstallDir $script:INSTALL_DIR
Add-ToPath       -InstallDir $script:INSTALL_DIR
Add-FirewallRule -Port $script:P2P_PORT -Network $script:NETWORK
Install-Service  -InstallDir $script:INSTALL_DIR -Network $script:NETWORK
Run-SmokeTest    -InstallDir $script:INSTALL_DIR -ConfigFile $script:CONFIG_FILE -RpcPort $script:RPC_PORT
Show-Summary     -InstallDir $script:INSTALL_DIR -Network $script:NETWORK `
                 -P2pPort $script:P2P_PORT -RpcPort $script:RPC_PORT
Start-LightNode  -InstallDir $script:INSTALL_DIR -Network $script:NETWORK
