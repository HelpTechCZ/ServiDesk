# Stáhne FFmpeg do složky Installer/ffmpeg pro zabalení do instalátoru
# Spustit: powershell -ExecutionPolicy Bypass -File download-ffmpeg.ps1

$ErrorActionPreference = "Stop"

$ffmpegDir = Join-Path $PSScriptRoot "ffmpeg"
$ffmpegExe = Join-Path $ffmpegDir "ffmpeg.exe"

if (Test-Path $ffmpegExe) {
    Write-Host "FFmpeg uz existuje: $ffmpegExe" -ForegroundColor Green
    exit 0
}

Write-Host "Stahuji FFmpeg..." -ForegroundColor Cyan

# Vytvorit slozku
New-Item -ItemType Directory -Path $ffmpegDir -Force | Out-Null

# Stahnout z BtbN/FFmpeg-Builds (GPL, essentials = mensi)
$url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$zipPath = Join-Path $env:TEMP "ffmpeg-download.zip"
$extractPath = Join-Path $env:TEMP "ffmpeg-extract"

Write-Host "URL: $url"
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

Write-Host "Rozbaluji..."
if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $extractPath

# Najit ffmpeg.exe v rozbalenem archivu
$found = Get-ChildItem -Path $extractPath -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
if (-not $found) {
    Write-Error "ffmpeg.exe nenalezen v archivu!"
    exit 1
}

Copy-Item $found.FullName $ffmpegExe -Force
Write-Host "FFmpeg ulozen: $ffmpegExe" -ForegroundColor Green

# Uklidit
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

# Velikost
$size = (Get-Item $ffmpegExe).Length / 1MB
Write-Host "Velikost: $([math]::Round($size, 1)) MB"
