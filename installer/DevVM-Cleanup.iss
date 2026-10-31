; Inno-Setup-Skript für DevVM Cleanup (Inno Setup 6.3 oder neuer).
; Aufruf (Release-Workflow): ISCC.exe /DAppVersion=0.3.0 installer\DevVM-Cleanup.iss
; Voraussetzung: die veröffentlichte App liegt unter publish\app (dotnet publish ... -o publish/app).
; Ergebnis: artifacts\DevVM-Cleanup_<version>_Setup.exe
; Die AppId bleibt für alle Versionen gleich, damit ein neues Setup die installierte Version ersetzt (Update).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "DevVM Cleanup"
#define AppExe "DevVM-Cleanup.exe"

[Setup]
AppId={{5D3227B2-5849-49AE-B07C-62E26A68A387}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=SPÄNI Elektro-Mechanik AG
AppPublisherURL=https://support.elektro-spaeni.ch
AppSupportURL=https://support.elektro-spaeni.ch
AppUpdatesURL=https://github.com/SPAENI-AG/DevVM-Cleanup/releases
AppCopyright=© SPÄNI Elektro-Mechanik AG
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
; Die App verlangt selbst Administratorrechte (Manifest), das Setup deshalb ebenfalls.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\LICENSE
SetupIconFile=..\src\DevVmCleanup.App\Assets\icon.ico
OutputDir=..\artifacts
OutputBaseFilename=DevVM-Cleanup_{#AppVersion}_Setup
; Läuft die App beim Update noch, wird sie vorher geschlossen.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Exe samt Ordnern "modules" und "Help" (lesbare Skripte/Hilfe müssen neben der Exe liegen)
Source: "..\publish\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent shellexec

; Einstellungen und Logs unter %APPDATA%\DevVM-Cleanup bleiben bei der Deinstallation bewusst erhalten.
