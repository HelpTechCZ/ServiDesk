; ServiDesk Remote Agent – Inno Setup Script

[Setup]
AppName=ServiDesk Remote Agent
AppVersion=1.0.0
AppPublisher=HelpTech.cz
AppPublisherURL=https://helptech.cz
DefaultDirName={autopf}\ServiDesk RemoteAgent
DefaultGroupName=ServiDesk
OutputBaseFilename=ServiDesk-RemoteAgent-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "czech"; MessagesFile: "compiler:Languages\Czech.isl"

[Files]
; Služba
Source: "..\RemoteAgent.Service\bin\Release\net8.0-windows\win-x64\publish\*"; DestDir: "{app}\Service"; Flags: recursesubdirs
; GUI
Source: "..\RemoteAgent.GUI\bin\Release\net8.0-windows\win-x64\publish\*"; DestDir: "{app}\GUI"; Flags: recursesubdirs
; FFmpeg
Source: "ffmpeg\ffmpeg.exe"; DestDir: "{app}\Service"; Flags: ignoreversion
; Konfigurace
Source: "config.json.template"; DestDir: "{commonappdata}\RemoteAgent"; DestName: "config.json"; Flags: onlyifdoesntexist

[Icons]
Name: "{group}\ServiDesk Vzdálená podpora"; Filename: "{app}\GUI\RemoteAgent.GUI.exe"
Name: "{commondesktop}\ServiDesk Vzdálená podpora"; Filename: "{app}\GUI\RemoteAgent.GUI.exe"

[Run]
; Nainstalovat Windows službu
Filename: "sc.exe"; Parameters: "create RemoteAgentService binPath=""{app}\Service\RemoteAgent.Service.exe"" start=delayed-auto DisplayName=""ServiDesk Remote Agent"""; Flags: runhidden
; Nastavit popis služby
Filename: "sc.exe"; Parameters: "description RemoteAgentService ""Služba pro vzdálenou správu ServiDesk"""; Flags: runhidden
; Nastavit auto-recovery (restart 3x: po 10s, 30s, 60s)
Filename: "sc.exe"; Parameters: "failure RemoteAgentService reset=86400 actions=restart/10000/restart/30000/restart/60000"; Flags: runhidden
; Spustit službu
Filename: "sc.exe"; Parameters: "start RemoteAgentService"; Flags: runhidden
; Povolit outbound ve firewallu
Filename: "netsh.exe"; Parameters: "advfirewall firewall add rule name=""ServiDesk RemoteAgent"" dir=out action=allow program=""{app}\Service\RemoteAgent.Service.exe"" enable=yes"; Flags: runhidden
; Spustit GUI po instalaci
Filename: "{app}\GUI\RemoteAgent.GUI.exe"; Description: "Spustit ServiDesk"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; Zastavit a odebrat službu
Filename: "sc.exe"; Parameters: "stop RemoteAgentService"; Flags: runhidden
Filename: "sc.exe"; Parameters: "delete RemoteAgentService"; Flags: runhidden
; Odebrat firewall pravidlo
Filename: "netsh.exe"; Parameters: "advfirewall firewall delete rule name=""ServiDesk RemoteAgent"""; Flags: runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\RemoteAgent"
