@echo off
echo.
echo  ==========================================
echo   ServiDesk - Build + Installer
echo   HelpTech.cz
echo  ==========================================
echo.

REM Pouziti: build-installer.bat [RELAY_URL] [PROVISION_TOKEN]
REM Priklad: build-installer.bat wss://my-server.com/ws abc123def456...
set "RELAY_URL=%~1"
set "PROVISION_TOKEN=%~2"
set "CFG=RemoteAgent.Shared\Config\AgentConfig.cs"
if not "%RELAY_URL%"=="" (
    echo  [*] Injecting relay URL into build...
    powershell -Command "(Get-Content '%CFG%') -replace 'RelayServerUrl \{ get; set; \} = \".*?\"', 'RelayServerUrl { get; set; } = \"%RELAY_URL%\"' | Set-Content '%CFG%'"
    echo  OK
)
if not "%PROVISION_TOKEN%"=="" (
    echo  [*] Injecting provision token into build...
    powershell -Command "(Get-Content '%CFG%') -replace 'ProvisionToken \{ get; set; \} = \".*?\"', 'ProvisionToken { get; set; } = \"%PROVISION_TOKEN%\"' | Set-Content '%CFG%'"
    echo  OK
)
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
