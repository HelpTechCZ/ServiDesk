# ServiDesk Windows Agent - Build Script
# Spustit: powershell -ExecutionPolicy Bypass -File build.ps1
# Nebo v PowerShell: .\build.ps1

param(
    [switch]$NoInstaller,  # Pouze kompilace bez Inno Setup installeru
    [string]$RelayUrl = "",  # URL relay serveru (wss://...)
    [string]$ProvisionToken = ""  # Provisioning token pro auto-registraci agenta
)

$ErrorActionPreference = "Stop"
$Version = "1.3.0"

Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host "   ServiDesk Agent v$Version - Build" -ForegroundColor Cyan
Write-Host "   HelpTech.cz" -ForegroundColor Cyan
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host ""

# Pracovni adresar = koren windows-agent
$Root = $PSScriptRoot
Set-Location $Root

# ── 0. Nastavit verzi ve vsech souborech ──
Write-Host "[0/4] Nastavuji verzi $Version..." -ForegroundColor Yellow

# GUI .csproj
$guiCsproj = "RemoteAgent.GUI\RemoteAgent.GUI.csproj"
(Get-Content $guiCsproj) -replace '<Version>.*?</Version>', "<Version>$Version</Version>" | Set-Content $guiCsproj
Write-Host "  $guiCsproj" -ForegroundColor DarkGray

# Service .csproj - pridat Version pokud chybi, nebo prepsat
$svcCsproj = "RemoteAgent.Service\RemoteAgent.Service.csproj"
$svcContent = Get-Content $svcCsproj -Raw
if ($svcContent -match '<Version>') {
    $svcContent = $svcContent -replace '<Version>.*?</Version>', "<Version>$Version</Version>"
} else {
    $svcContent = $svcContent -replace '(<OutputType>Exe</OutputType>)', "`$1`r`n    <Version>$Version</Version>"
}
Set-Content $svcCsproj $svcContent
Write-Host "  $svcCsproj" -ForegroundColor DarkGray

# AgentConfig.cs - AgentVersion default
$agentConfig = "RemoteAgent.Shared\Config\AgentConfig.cs"
(Get-Content $agentConfig) -replace 'AgentVersion \{ get; set; \} = ".*?"', "AgentVersion { get; set; } = ""$Version""" | Set-Content $agentConfig
Write-Host "  $agentConfig" -ForegroundColor DarkGray

# AgentConfig.cs - RelayServerUrl + UpdateManifestUrl (injekce při buildu)
if ($RelayUrl) {
    (Get-Content $agentConfig) -replace 'RelayServerUrl \{ get; set; \} = ".*?"', "RelayServerUrl { get; set; } = ""$RelayUrl""" | Set-Content $agentConfig
    # Odvodit update URL z relay URL (wss://host/ws → https://host/update/manifest.json)
    $updateUrl = $RelayUrl -replace 'wss://', 'https://' -replace 'ws://', 'http://' -replace '/ws$', '/update/manifest.json'
    (Get-Content $agentConfig) -replace 'UpdateManifestUrl \{ get; set; \} = ".*?"', "UpdateManifestUrl { get; set; } = ""$updateUrl""" | Set-Content $agentConfig
    Write-Host "  $agentConfig (relay: $RelayUrl)" -ForegroundColor DarkGray
} else {
    Write-Host "  $agentConfig (relay URL: prazdna – pouzij -RelayUrl)" -ForegroundColor DarkYellow
}

# AgentConfig.cs - ProvisionToken default (injekce při buildu)
if ($ProvisionToken) {
    (Get-Content $agentConfig) -replace 'ProvisionToken \{ get; set; \} = ".*?"', "ProvisionToken { get; set; } = ""$ProvisionToken""" | Set-Content $agentConfig
    Write-Host "  $agentConfig (provision token: set)" -ForegroundColor DarkGray
} else {
    Write-Host "  $agentConfig (provision token: prazdny – pouzij -ProvisionToken)" -ForegroundColor DarkYellow
}

# Inno Setup .iss
$issFile = "Installer\ServiDesk.iss"
if (Test-Path $issFile) {
    (Get-Content $issFile) -replace '#define MyAppVersion ".*?"', "#define MyAppVersion ""$Version""" | Set-Content $issFile
    Write-Host "  $issFile" -ForegroundColor DarkGray
}

Write-Host "  OK" -ForegroundColor Green

# ── 1. Vycistit predchozi build ──
Write-Host "[1/4] Cistim predchozi build..." -ForegroundColor Yellow
if (Test-Path ".\publish\ServiDesk") {
    Remove-Item ".\publish\ServiDesk" -Recurse -Force
}
Write-Host "  OK" -ForegroundColor Green

# ── 2. Restore NuGet balicku ──
Write-Host "[2/4] Obnovuji NuGet balicky..." -ForegroundColor Yellow
dotnet restore RemoteAgent.sln
if ($LASTEXITCODE -ne 0) {
    Write-Host "  CHYBA: dotnet restore selhal!" -ForegroundColor Red
    exit 1
}
Write-Host "  OK" -ForegroundColor Green

# ── 3. Kompilace + Publish ──
Write-Host "[3/4] Kompiluji ServiDesk.exe (Release, self-contained)..." -ForegroundColor Yellow
dotnet publish RemoteAgent.GUI\RemoteAgent.GUI.csproj `
    -c Release `
    -r win-x64 `
    --self-contained `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=none `
    -p:DebugSymbols=false `
    -o .\publish\ServiDesk

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  CHYBA: Build selhal!" -ForegroundColor Red
    exit 1
}

$exePath = ".\publish\ServiDesk\ServiDesk.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "  CHYBA: $exePath nenalezen!" -ForegroundColor Red
    exit 1
}

$exeSize = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
Write-Host "  OK - ServiDesk.exe ($exeSize MB)" -ForegroundColor Green

# ── 4. Installer (Inno Setup) ──
if ($NoInstaller) {
    Write-Host "[4/4] Installer preskocen (-NoInstaller)" -ForegroundColor DarkGray
} else {
    Write-Host "[4/4] Vytvarim installer (Inno Setup)..." -ForegroundColor Yellow

    $ISCC = $null
    if (Test-Path "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe") {
        $ISCC = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    } elseif (Test-Path "$env:ProgramFiles\Inno Setup 6\ISCC.exe") {
        $ISCC = "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    }

    if ($ISCC) {
        & $ISCC "Installer\ServiDesk.iss"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  CHYBA: Inno Setup selhal!" -ForegroundColor Red
            exit 1
        }
        Write-Host "  OK - publish\ServiDesk-Setup-$Version.exe" -ForegroundColor Green
    } else {
        Write-Host "  Inno Setup 6 nenalezen (winget install JRSoftware.InnoSetup)" -ForegroundColor DarkYellow
        Write-Host "  EXE je pripraven: publish\ServiDesk\ServiDesk.exe" -ForegroundColor DarkYellow
    }
}

# ── Hotovo ──
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Green
Write-Host "   Build uspesne dokoncen! v$Version" -ForegroundColor Green
Write-Host "  ==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Vystupy:" -ForegroundColor White
Write-Host "    EXE:       publish\ServiDesk\ServiDesk.exe" -ForegroundColor White
if (-not $NoInstaller -and $ISCC) {
    Write-Host "    Installer: publish\ServiDesk-Setup-$Version.exe" -ForegroundColor White
}
Write-Host ""
