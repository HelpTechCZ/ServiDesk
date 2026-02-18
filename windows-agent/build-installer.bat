@echo off
echo.
echo  ==========================================
echo   ServiDesk - Build + Installer
echo   HelpTech.cz
echo  ==========================================
echo.

if exist ".\publish\ServiDesk" rmdir /s /q ".\publish\ServiDesk"

echo  [1/2] Kompilace ServiDesk.exe ...
echo.
dotnet publish RemoteAgent.GUI\RemoteAgent.GUI.csproj -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none -p:DebugSymbols=false -o .\publish\ServiDesk
if errorlevel 1 (
    echo.
    echo  CHYBA: Build selhal!
    pause
    exit /b 1
)
echo.

echo  [2/2] Vytvarim installer ...
echo.
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"

if "%ISCC%"=="" (
    echo  Inno Setup 6 nenalezen!
    echo  Instalace: winget install JRSoftware.InnoSetup
    echo.
    echo  EXE je pripraven: publish\ServiDesk\ServiDesk.exe
    pause
    exit /b 0
)

"%ISCC%" installer\ServiDesk.iss
if errorlevel 1 (
    echo.
    echo  CHYBA: Installer selhal!
    pause
    exit /b 1
)

echo.
echo  ==========================================
echo   Hotovo!
echo   Installer: publish\ServiDesk-Setup-1.1.1.exe
echo  ==========================================
echo.
pause
