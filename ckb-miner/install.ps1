# ckb-miner Windows installer (PowerShell 5.1)
# Downloads CPU miner for Windows x86_64

$ErrorActionPreference = "Stop"
$script:VERSION = "0.25.0"
$script:REPO = "nervosnetwork/ckb-miner"

# Colors (if supported)
$Host.UI.RawUI.ForegroundColor = "Cyan"
Write-Host "╔══════════════════════════════════════════════════════════╗"
Write-Host "║           ckb-miner installer v$script:VERSION                ║"
Write-Host "╚══════════════════════════════════════════════════════════╝"
$Host.UI.RawUI.ForegroundColor = "White"
Write-Host ""
Write-Host "Installs CKB CPU miner (Eaglesong) for Windows."
Write-Host "CUDA/OpenCL versions available via manual download."
Write-Host ""

# Defaults
$script:DEFAULT_INSTALL_DIR = Join-Path $env:USERPROFILE ".ckb-miner"
$script:DEFAULT_POOL = "stratum+tcp://ckb.viabtc.com:3333"
$script:DEFAULT_WORKER_NAME = "$($env:COMPUTERNAME)-$($env:USERNAME)"
$script:DEFAULT_CPU_THREADS = [System.Environment]::ProcessorCount

# Collect configuration
Write-Host ""
$installDir = Read-Host "Install directory [$script:DEFAULT_INSTALL_DIR]"
if (-not $installDir) { $installDir = $script:DEFAULT_INSTALL_DIR }
$installDir = $installDir.TrimEnd('\')
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

Write-Host ""
Write-Host "Mining pool configuration:"
$poolUrl = Read-Host "Pool URL [$script:DEFAULT_POOL]"
if (-not $poolUrl) { $poolUrl = $script:DEFAULT_POOL }
$workerName = Read-Host "Worker name [$script:DEFAULT_WORKER_NAME]"
if (-not $workerName) { $workerName = $script:DEFAULT_WORKER_NAME }
$cpuThreads = Read-Host "CPU threads (0 = auto) [$script:DEFAULT_CPU_THREADS]"
if (-not $cpuThreads) { $cpuThreads = $script:DEFAULT_CPU_THREADS }

# Binary variant selection
Write-Host ""
Write-Host "Available GPU variants:"
Write-Host "  1) CPU only (default)"
Write-Host "  2) CUDA (NVIDIA GPU)"
Write-Host "  3) OpenCL (AMD/Intel GPU)"
$gpuChoice = Read-Host "Choose variant (1-3) [1]"
switch ($gpuChoice) {
    2 { $binaryVariant = "cuda" }
    3 { $binaryVariant = "opencl" }
    default { $binaryVariant = "cpu" }
}

# Download URL
$archive = "ckb-miner-${binaryVariant}-win.zip"
$downloadUrl = "https://github.com/$script:REPO/releases/download/v$script:VERSION/$archive"

# Download
Write-Host "Downloading $archive..."
$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile "$tempDir\$archive" -UseBasicParsing
} catch {
    Write-Host "Error: Download failed" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

# Extract
Write-Host "Extracting..."
Expand-Archive -Path "$tempDir\$archive" -DestinationPath $tempDir -Force

# Find binary
$binaryPath = Get-ChildItem -Path $tempDir -Recurse -Filter "ckb-miner.exe" | Select-Object -First 1
if (-not $binaryPath) {
    Write-Host "Error: Could not find ckb-miner.exe in archive" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

# Install binary
$binDir = Join-Path $installDir "bin"
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Copy-Item -Path $binaryPath.FullName -Destination $binDir
Write-Host "Installed binary to $binDir\ckb-miner.exe" -ForegroundColor Green

# Create config file
$configFile = Join-Path $installDir "config.toml"
@"
# ckb-miner configuration
pool = "$poolUrl"
worker = "$workerName"
threads = $cpuThreads
"@ | Out-File -FilePath $configFile -Encoding UTF8
Write-Host "Configuration written to $configFile" -ForegroundColor Green

# Create batch script
$batchFile = Join-Path $installDir "start-miner.bat"
@"
@echo off
cd /d "%~dp0"
bin\ckb-miner.exe -c config.toml
"@ | Out-File -FilePath $batchFile -Encoding ASCII
Write-Host "Batch script created: $batchFile" -ForegroundColor Green

# Offer to add to PATH
Write-Host ""
$addPath = Read-Host "Add to user PATH? (Y/N) [N]"
if ($addPath -match '^[Yy]') {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = "$binDir;$userPath"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Added $binDir to user PATH (requires new shell)" -ForegroundColor Green
}

# Offer to install as Windows service
Write-Host ""
$installService = Read-Host "Install as Windows service? (Y/N) [N]"
if ($installService -match '^[Yy]') {
    # Check if NSSM is available
    $nssmPath = "$env:ProgramFiles\nssm\nssm.exe"
    if (-not (Test-Path $nssmPath)) {
        Write-Host "NSSM not installed. Downloading NSSM..." -ForegroundColor Yellow
        $nssmZip = "$tempDir\nssm.zip"
        Invoke-WebRequest -Uri "https://nssm.cc/ci/nssm-2.24-101-g897c7ad.zip" -OutFile $nssmZip -UseBasicParsing
        Expand-Archive -Path $nssmZip -DestinationPath "$tempDir\nssm" -Force
        $nssmExe = Get-ChildItem "$tempDir\nssm" -Filter "nssm.exe" -Recurse | Select-Object -First 1
        if ($nssmExe) {
            $nssmDir = "$env:ProgramFiles\nssm"
            New-Item -ItemType Directory -Path $nssmDir -Force | Out-Null
            Copy-Item -Path $nssmExe.FullName -Destination $nssmDir
            [Environment]::SetEnvironmentVariable("Path", "$nssmDir;$env:Path", "Machine")
            Write-Host "NSSM installed to $nssmDir" -ForegroundColor Green
        }
    }
    if (Test-Path $nssmPath) {
        & $nssmPath install "ckb-miner" "$binDir\ckb-miner.exe" "-c `"$configFile`""
        Write-Host "Windows service 'ckb-miner' installed." -ForegroundColor Green
        Write-Host "Start with: net start ckb-miner" -ForegroundColor Yellow
    } else {
        Write-Host "Skipping service installation (NSSM not available)" -ForegroundColor Yellow
    }
}

# Cleanup
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue

# Summary
Write-Host ""
Write-Host "ckb-miner $script:VERSION installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Binary:   $binDir\ckb-miner.exe"
Write-Host "  Config:   $configFile"
Write-Host "  Pool:     $poolUrl"
Write-Host "  Worker:   $workerName"
Write-Host "  Threads:  $cpuThreads"
Write-Host ""
Write-Host "Commands:" -ForegroundColor Cyan
Write-Host "  Start miner:   $batchFile"
if (Test-Path "$env:ProgramFiles\nssm\nssm.exe") {
    Write-Host "  Service:      net start ckb-miner"
}
Write-Host ""
Write-Host "Happy mining!" -ForegroundColor Green