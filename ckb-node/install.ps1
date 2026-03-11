#Requires -Version 5.1
# CKB Full Node installer — Windows (PowerShell 5.1+)
# Run as Admin: irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-node/install.ps1 | iex

$script:VERSION    = "0.204.0"
$script:BINARY     = "ckb.exe"
$script:REPO       = "nervosnetwork/ckb"
$script:SERVICE_NAME = "CkbNode"

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
    Write-Host "  |   CKB Full Node Installer v1.0          |" -ForegroundColor Cyan
    Write-Host "  |   Nervos CKB - nervosnetwork             |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  WARNING: Mainnet sync requires 200GB+ of disk space." -ForegroundColor Yellow
    Write-Host "  Ensure your data directory has sufficient free space." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Full node - validates all transactions, stores full chain history" -ForegroundColor Gray
    Write-Host ""
}

# ── Config ────────────────────────────────────────────────
function Collect-Config {
    Write-Step "Configuration"
    $script:INSTALL_DIR = Ask "Install directory" "$env:USERPROFILE\.ckb-node"
    $script:RPC_PORT    = Ask "RPC listen port"   "8114"
    $script:P2P_PORT    = Ask "P2P listen port"   "8115"

    $script:LOG_FILE    = "$($script:INSTALL_DIR)\ckb-node.log"

    Write-Host ""
    Write-Ok "Install dir: $($script:INSTALL_DIR)"
    Write-Ok "RPC port:    $($script:RPC_PORT)"
    Write-Ok "P2P port:    $($script:P2P_PORT)"
}

# ── Download binary ───────────────────────────────────────
function Download-Binary {
    param($InstallDir)
    $ErrorActionPreference = "Stop"
    Write-Step "Downloading ckb v$($script:VERSION)"

    $zipName = "ckb_v$($script:VERSION)_x86_64-pc-windows-msvc.zip"
    $url     = "https://github.com/$($script:REPO)/releases/download/v$($script:VERSION)/$zipName"

    try {
        $null = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Err "Release archive not found at: $url"
        Write-Info "Check https://github.com/$($script:REPO)/releases for available versions"
        exit 1
    }

    $tmp     = "$env:TEMP\ckb-node-$($script:VERSION)"
    $archive = "$tmp\$zipName"

    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    New-Item -ItemType Directory -Force -Path "$InstallDir\bin" | Out-Null

    Write-Info "Downloading from GitHub..."
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing

    Write-Info "Extracting..."
    & tar -xf $archive -C $tmp 2>&1 | Out-Null

    $binSrc = Get-ChildItem -Path $tmp -Filter "ckb.exe" -Recurse | Select-Object -First 1
    if (-not $binSrc) {
        Write-Err "ckb.exe not found in archive"
        exit 1
    }
    Copy-Item $binSrc.FullName "$InstallDir\bin\$($script:BINARY)" -Force
    Write-Ok "Binary installed: $InstallDir\bin\$($script:BINARY)"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Init node ─────────────────────────────────────────────
function Init-Node {
    param($InstallDir)
    Write-Step "Initialising CKB node (mainnet)"
    $configFile = "$InstallDir\ckb.toml"
    if (Test-Path $configFile) {
        Write-Warn "Config already exists — skipping init (delete $configFile to reinitialise)"
        $script:CONFIG_FILE = $configFile
        return
    }
    & "$InstallDir\bin\$($script:BINARY)" init --chain mainnet -C $InstallDir 2>&1 | Out-Null
    $script:CONFIG_FILE = $configFile
    Write-Ok "Config generated: $configFile"

    # Patch RPC port if non-default
    if ($script:RPC_PORT -ne "8114") {
        $content = Get-Content $configFile -Raw
        $content = $content -replace 'listen_address = "127\.0\.0\.1:8114"', "listen_address = `"127.0.0.1:$($script:RPC_PORT)`""
        $content | Set-Content $configFile -Encoding UTF8
        Write-Ok "RPC port patched to $($script:RPC_PORT)"
    }

    # Patch P2P port if non-default
    if ($script:P2P_PORT -ne "8115") {
        $content = Get-Content $configFile -Raw
        $content = $content -replace '/tcp/8115"', "/tcp/$($script:P2P_PORT)`""
        $content | Set-Content $configFile -Encoding UTF8
        Write-Ok "P2P port patched to $($script:P2P_PORT)"
    }
}

# ── Start bat ─────────────────────────────────────────────
function Write-StartBat {
    param($InstallDir)
    $bat = "@echo off`r`nset RUST_LOG=info`r`n`"$InstallDir\bin\$($script:BINARY)`" run -C `"$InstallDir`" >> `"$($script:LOG_FILE)`" 2>&1`r`n"
    $bat | Set-Content -Path "$InstallDir\start-ckb-node.bat" -Encoding ASCII
    Write-Ok "Start script: $InstallDir\start-ckb-node.bat"
}

# ── Service (NSSM) ────────────────────────────────────────
function Install-Service {
    param($InstallDir)
    Write-Step "Installing Windows Service"
    $svcName = $script:SERVICE_NAME

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
        Write-Warn "Could not install NSSM — service not created. Use start-ckb-node.bat to run manually."
        return
    }

    & $nssmExe stop $svcName 2>&1 | Out-Null
    & $nssmExe remove $svcName confirm 2>&1 | Out-Null
    Start-Sleep 1

    & $nssmExe install $svcName "$InstallDir\bin\$($script:BINARY)" | Out-Null
    & $nssmExe set $svcName AppParameters "run -C `"$InstallDir`"" | Out-Null
    & $nssmExe set $svcName AppDirectory $InstallDir | Out-Null
    & $nssmExe set $svcName AppEnvironmentExtra "RUST_LOG=info" | Out-Null
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
    param($Port)
    Write-Step "Firewall"
    $ruleName = "CKB Full Node P2P"
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
    param($InstallDir, $RpcPort)
    Write-Step "Smoke Test"
    Write-Info "Starting node briefly to verify it launches..."

    try { $null = & taskkill /IM "ckb.exe" /F 2>&1 } catch {}
    Start-Sleep 2

    $env:RUST_LOG = "info"
    $proc = Start-Process -FilePath "$InstallDir\bin\$($script:BINARY)" `
        -ArgumentList "run -C `"$InstallDir`"" `
        -WindowStyle Hidden -PassThru

    $smokePass = $false
    $rpcUrl    = "http://127.0.0.1:$RpcPort"
    $body      = '{"jsonrpc":"2.0","method":"local_node_info","params":[],"id":1}'
    Write-Host "  Waiting for RPC on 127.0.0.1:$RpcPort" -NoNewline

    for ($i = 0; $i -lt 30; $i++) {
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

    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
    Start-Sleep 1
    try { $null = & taskkill /IM "ckb.exe" /F 2>&1 } catch {}
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
    param($InstallDir, $RpcPort, $P2pPort)
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  CKB Full Node installed!" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""
    Write-Ok "Version:     v$($script:VERSION)"
    Write-Ok "Install dir: $InstallDir"
    Write-Ok "Config:      $InstallDir\ckb.toml"
    Write-Ok "Log:         $($script:LOG_FILE)"
    Write-Ok "P2P port:    $P2pPort"
    Write-Ok "RPC port:    $RpcPort (localhost only)"
    Write-Host ""
    Write-Ok "RPC endpoint: http://127.0.0.1:$RpcPort"
    Write-Host ""
    Write-Warn "Mainnet sync will take days and use 200GB+ of disk."
    Write-Host ""
    Write-Info "Test RPC after start:"
    Write-Info "  curl -X POST http://127.0.0.1:$RpcPort -H 'Content-Type: application/json' -d '{`"jsonrpc`":`"2.0`",`"method`":`"local_node_info`",`"params`":[],`"id`":1}'"
    Write-Host ""
}

# ── Start now? ────────────────────────────────────────────
function Start-CkbNode {
    param($InstallDir)
    $svcName = $script:SERVICE_NAME
    $nssmExe = "$InstallDir\bin\nssm.exe"

    Write-Step "Start Node?"
    $startNow = Ask "Start ckb-node now?" "Y"
    if ($startNow -match "^[Yy]") {
        if (Test-Path $nssmExe) {
            & $nssmExe start $svcName 2>&1 | Out-Null
            Write-Ok "Service started: $svcName"
            Write-Info "Manage: nssm start/stop/restart $svcName"
        } else {
            $bat = "$InstallDir\start-ckb-node.bat"
            Start-Process -FilePath "cmd" -ArgumentList "/c `"$bat`"" -WindowStyle Minimized
            Write-Ok "Started via bat file (minimized window)"
        }
        Write-Info "Check logs: $($script:LOG_FILE)"
    } else {
        if (Test-Path $nssmExe) {
            Write-Info "To start: nssm start $svcName"
        } else {
            Write-Info "To start: $InstallDir\start-ckb-node.bat"
        }
    }
}

# ── Main ──────────────────────────────────────────────────
Show-Banner
Collect-Config

Download-Binary  -InstallDir $script:INSTALL_DIR
Init-Node        -InstallDir $script:INSTALL_DIR
Write-StartBat   -InstallDir $script:INSTALL_DIR
Add-ToPath       -InstallDir $script:INSTALL_DIR
Add-FirewallRule -Port $script:P2P_PORT
Install-Service  -InstallDir $script:INSTALL_DIR
Run-SmokeTest    -InstallDir $script:INSTALL_DIR -RpcPort $script:RPC_PORT
Show-Summary     -InstallDir $script:INSTALL_DIR -RpcPort $script:RPC_PORT -P2pPort $script:P2P_PORT
Start-CkbNode    -InstallDir $script:INSTALL_DIR
