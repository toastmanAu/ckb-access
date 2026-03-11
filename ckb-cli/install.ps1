#Requires -Version 5.1
# CKB CLI installer — Windows (PowerShell 5.1+)
# Run: irm https://raw.githubusercontent.com/toastmanAu/ckb-access/main/ckb-cli/install.ps1 | iex

$script:VERSION = "2.0.0"
$script:BINARY  = "ckb-cli.exe"
$script:REPO    = "nervosnetwork/ckb-cli"

# ── Helpers ───────────────────────────────────────────────
function Write-Step { param($m) Write-Host "`n  >> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Info { param($m) Write-Host "  [i]  $m" -ForegroundColor Gray }
function Write-Err  { param($m) Write-Host "  [X]  $m" -ForegroundColor Red }

function Ask {
    param($Prompt, $Default)
    $val = Read-Host "  $Prompt [$Default]"
    if ($val -eq "") { return $Default }
    return $val
}

# ── Banner ────────────────────────────────────────────────
function Show-Banner {
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   CKB CLI Installer v1.0                  |" -ForegroundColor Cyan
    Write-Host "  |   Nervos CKB - nervosnetwork               |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ckb-cli - command-line interface for Nervos CKB" -ForegroundColor Gray
    Write-Host "  Query blockchain, manage wallets, send transactions" -ForegroundColor Gray
    Write-Host ""
}

# ── Config ────────────────────────────────────────────────
function Collect-Config {
    Write-Step "Configuration"
    $defaultDir = "$env:USERPROFILE\.ckb-cli\bin"
    $script:INSTALL_DIR = Ask "Install directory" $defaultDir

    Write-Host ""
    Write-Ok "Install dir: $($script:INSTALL_DIR)"
}

# ── Download binary ───────────────────────────────────────
function Download-Binary {
    param($InstallDir)
    $ErrorActionPreference = "Stop"
    Write-Step "Downloading ckb-cli v$($script:VERSION)"

    # Windows: always x86_64, .zip archive
    $zipName = "ckb-cli_v$($script:VERSION)_x86_64-pc-windows-msvc.zip"
    $url     = "https://github.com/$($script:REPO)/releases/download/v$($script:VERSION)/$zipName"

    try {
        $null = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Err "Release zip not found at: $url"
        Write-Info "Check https://github.com/$($script:REPO)/releases for available versions"
        exit 1
    }

    $tmp     = "$env:TEMP\ckb-cli-$($script:VERSION)"
    $archive = "$tmp\$zipName"

    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    Write-Info "Downloading from GitHub..."
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing

    Write-Info "Extracting..."
    Expand-Archive -Path $archive -DestinationPath $tmp -Force

    $binSrc = Get-ChildItem -Path $tmp -Filter "ckb-cli.exe" -Recurse | Select-Object -First 1
    if (-not $binSrc) {
        Write-Err "ckb-cli.exe not found in zip"
        exit 1
    }
    Copy-Item $binSrc.FullName "$InstallDir\$($script:BINARY)" -Force
    Write-Ok "Binary installed: $InstallDir\$($script:BINARY)"
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ── PATH ──────────────────────────────────────────────────
function Add-ToPath {
    param($InstallDir)
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$current;$InstallDir", "User")
        $env:PATH += ";$InstallDir"
        Write-Ok "Added $InstallDir to PATH"
    } else {
        Write-Ok "$InstallDir already in PATH"
    }
}

# ── Smoke test ────────────────────────────────────────────
function Run-SmokeTest {
    param($InstallDir)
    Write-Step "Smoke Test"

    $binExe     = "$InstallDir\$($script:BINARY)"
    $smokePass  = $false
    $versionOut = ""

    try {
        $versionOut = & $binExe --version 2>&1
        $versionStr = "$versionOut"
        if ($versionStr -like "*$($script:VERSION)*") {
            $smokePass = $true
        }
    } catch {
        $versionOut = "error: $_"
    }

    if ($smokePass) {
        Write-Ok "Smoke test passed!"
        Write-Ok "Version: $versionOut"
    } else {
        Write-Warn "Version check unexpected output: $versionOut"
        Write-Warn "Binary may still work -- check manually: $binExe --version"
    }
}

# ── Summary ───────────────────────────────────────────────
function Show-Summary {
    param($InstallDir)
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  ckb-cli installed!" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""
    Write-Ok "Version:  v$($script:VERSION)"
    Write-Ok "Binary:   $InstallDir\$($script:BINARY)"
    Write-Host ""
    Write-Info "Usage examples:"
    Write-Info "  ckb-cli --version"
    Write-Info "  ckb-cli wallet get-capacity --address <addr>"
    Write-Info "  ckb-cli rpc get_tip_block_number"
    Write-Host ""
    Write-Host "  Note: Open a new terminal for PATH changes to take effect." -ForegroundColor Yellow
    Write-Host ""
    Write-Ok "Done!"
    Write-Host ""
}

# ── Main ──────────────────────────────────────────────────
Show-Banner
Collect-Config
Download-Binary -InstallDir $script:INSTALL_DIR
Add-ToPath      -InstallDir $script:INSTALL_DIR
Run-SmokeTest   -InstallDir $script:INSTALL_DIR
Show-Summary    -InstallDir $script:INSTALL_DIR
