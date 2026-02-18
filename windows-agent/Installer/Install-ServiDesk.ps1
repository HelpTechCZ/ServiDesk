# ServiDesk Installer
# Spustit jako Administrator: pravý klik → Spustit jako správce
# Nebo: powershell -ExecutionPolicy Bypass -File Install-ServiDesk.ps1

param(
    [switch]$Uninstall
)

$AppName = "ServiDesk"
$InstallDir = "$env:ProgramFiles\$AppName"
$ExeName = "ServiDesk.exe"
$SourceExe = Join-Path $PSScriptRoot "..\publish\ServiDesk\$ExeName"
$DesktopShortcut = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$AppName.lnk")
$StartMenuDir = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonPrograms"), $AppName)

# ── Odinstalace ──
if ($Uninstall) {
    Write-Host "Odinstalovavam $AppName..." -ForegroundColor Yellow

    # Zastavit proces
    Get-Process -Name "ServiDesk" -ErrorAction SilentlyContinue | Stop-Process -Force

    # Smazat soubory
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    if (Test-Path $DesktopShortcut) { Remove-Item $DesktopShortcut -Force }
    if (Test-Path $StartMenuDir) { Remove-Item $StartMenuDir -Recurse -Force }

    Write-Host "$AppName odinstalovano." -ForegroundColor Green
    exit 0
}

# ── Kontrola ──
if (-not (Test-Path $SourceExe)) {
    Write-Host "CHYBA: $SourceExe nenalezen!" -ForegroundColor Red
    Write-Host "Nejprve spustte: dotnet publish RemoteAgent.GUI\RemoteAgent.GUI.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish\ServiDesk"
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  $AppName - Instalace v1.1.1" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Kopirovat EXE ──
Write-Host "[1/3] Kopiruji $ExeName do $InstallDir..." -ForegroundColor White
if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }

# Zastavit bezici instanci
Get-Process -Name "ServiDesk" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Copy-Item $SourceExe -Destination $InstallDir -Force
Write-Host "  OK" -ForegroundColor Green

# ── 2. Zkopirovat ikonu (z EXE se pouzije automaticky) ──

# ── 3. Vytvorit zastupce na plose ──
Write-Host "[2/3] Vytvari zastupce na plose..." -ForegroundColor White
$WshShell = New-Object -ComObject WScript.Shell

$Shortcut = $WshShell.CreateShortcut($DesktopShortcut)
$Shortcut.TargetPath = Join-Path $InstallDir $ExeName
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "Vzdalena podpora – ServiDesk by HelpTech.cz"
$Shortcut.IconLocation = (Join-Path $InstallDir $ExeName) + ",0"
$Shortcut.Save()
Write-Host "  OK" -ForegroundColor Green

# ── 4. Start menu ──
Write-Host "[3/3] Vytvari Start menu polozku..." -ForegroundColor White
if (-not (Test-Path $StartMenuDir)) { New-Item -ItemType Directory -Path $StartMenuDir -Force | Out-Null }

$StartShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuDir "$AppName.lnk"))
$StartShortcut.TargetPath = Join-Path $InstallDir $ExeName
$StartShortcut.WorkingDirectory = $InstallDir
$StartShortcut.Description = "Vzdalena podpora – ServiDesk by HelpTech.cz"
$StartShortcut.IconLocation = (Join-Path $InstallDir $ExeName) + ",0"
$StartShortcut.Save()
Write-Host "  OK" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  $AppName uspesne nainstalovan!" -ForegroundColor Green
Write-Host "  Umisteni: $InstallDir\$ExeName" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Spustit
$run = Read-Host "Spustit $AppName nyni? (A/n)"
if ($run -ne "n") {
    Start-Process (Join-Path $InstallDir $ExeName)
}
