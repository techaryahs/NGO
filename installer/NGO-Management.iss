; -----------------------------------------------------------------------------
; NGO Management - Inno Setup Script
; Publisher: Aryahs World Infotech(OPC) Pvt. Ltd.
; Architecture: Windows x64
; -----------------------------------------------------------------------------

#define MyAppName "NGO Management"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Aryahs World Infotech(OPC) Pvt. Ltd."
#define MyAppExeName "ngo.exe"
#define MyAppCopyright "Copyright (C) 2026 Aryahs World Infotech(OPC) Pvt. Ltd."
#define MyOutputDir "output"

[Setup]
; Unique application identity (stable GUID)
AppId={{CD274C8F-6868-4C42-8AC4-E435639CED52}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright={#MyAppCopyright}
AppComments=NGO Management Application

; Installation Directory & Group
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes

; Target Architecture (Windows x64)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Privilege Strategy:
; Default to current user directory without forcing UAC elevation;
; allow user to elevate and install for all users via dialog or CLI parameter.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline

; Output Packaging
OutputDir={#MyOutputDir}
OutputBaseFilename=NGO-Management-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; Compression Configuration
Compression=lzma2/max
SolidCompression=yes

; Wizard UI Configuration
WizardStyle=modern dynamic
DisableDirPage=no
DisableProgramGroupPage=no

; Graceful Application Upgrade & Process Handling
CloseApplications=yes

; Executable Version Info Metadata
VersionInfoVersion=1.0.0.1
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright={#MyAppCopyright}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main Executable
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Complete Flutter Release Directory (DLLs, plugins, SQLite runtime, data, assets, and configuration)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "{#MyAppExeName}"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
