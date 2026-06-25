; Inno Setup Script for NGO Application
; This script defines how the Windows installer will be created and configured

[Setup]
AppName=NGO
AppVersion=1.0.0
AppVerName=NGO v1.0.0
AppPublisher=Aryahs World Infotech Pvt. Ltd.
AppPublisherURL=https://example.com
AppSupportURL=https://example.com/support
AppUpdatesURL=https://example.com/updates
DefaultDirName={autopf}\NGO
DefaultGroupName=NGO
AllowNoIcons=yes
LicenseFile=
InfoBeforeFile=
InfoAfterFile=
Compression=lzma
SolidCompression=yes
VersionInfoVersion=1.0.0.0
VersionInfoCompany=Aryahs World Infotech Pvt. Ltd.
VersionInfoProductName=NGO
VersionInfoProductVersion=1.0.0
VersionInfoDescription=NGO Application Installer
OutputDir=build\windows\x64\runner\Release\Installer
OutputBaseFilename=NGO-Setup-1.0.0
UninstallDisplayIcon={app}\ngo.exe
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
DisableProgramGroupPage=no
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1

[Files]
; Main executable
Source: "build\windows\x64\runner\Release\ngo.exe"; DestDir: "{app}"; Flags: ignoreversion

; Application icon (convert logo.jpeg to logo.ico first)
Source: "assets\images\logo.ico"; DestDir: "{app}"; Flags: ignoreversion

; Application logo image
Source: "assets\images\logo.jpeg"; DestDir: "{app}"; Flags: ignoreversion

; Runtime dependencies (add as needed)
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Flutter runtime assets
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; Data files if any
Source: "lib\data\room_config.json"; DestDir: "{app}\data"; Flags: ignoreversion

; Assets
Source: "assets\images\*"; DestDir: "{app}\assets\images"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu shortcut
Name: "{group}\NGO"; Filename: "{app}\ngo.exe"; IconFilename: "{app}\logo.ico"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,NGO}"; Filename: "{uninstallexe}"

; Desktop shortcut (if user selected it)
Name: "{commondesktop}\NGO"; Filename: "{app}\ngo.exe"; IconFilename: "{app}\logo.ico"; Tasks: desktopicon; WorkingDir: "{app}"

; Quick Launch shortcut (if user selected it)
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\NGO"; Filename: "{app}\ngo.exe"; IconFilename: "{app}\logo.ico"; Tasks: quicklaunchicon; WorkingDir: "{app}"

[Run]
; Launch the application after installation
Filename: "{app}\ngo.exe"; Description: "{cm:LaunchProgram,NGO}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up any generated files during uninstall
Type: dirifempty; Name: "{app}"
Type: dirifempty; Name: "{app}\data"
Type: dirifempty; Name: "{app}\assets"
Type: dirifempty; Name: "{app}\assets\images"

[Code]
// Optional: Add custom code here if needed for advanced functionality
// For example, registry modifications, version checks, etc.

procedure InitializeWizard;
begin
  // Custom initialization code can go here
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Code to run after installation completes
  end;
end;
