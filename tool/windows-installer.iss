; Compile with Inno Setup 6 after the backend deployment and release gates pass.
; This intentionally remains unsigned until a real publisher certificate exists.
#define AppVersion "1.0.10"
#define ReleaseDir "..\build\windows\x64\runner\Release"
#if GetFileVersion(ReleaseDir + "\Saleo_New_Desktop.exe") != "1.0.10.19"
  #error Build and verify the 1.0.10 Windows release before compiling this installer.
#endif
[Setup]
AppId={{EC7612AA-DCAB-4F99-B585-46E65F264ABA}
AppName=Saleo
AppVersion={#AppVersion}
AppPublisher=NAPROJEKTS
DefaultDirName={localappdata}\Programs\Saleo
DefaultGroupName=Saleo
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=Saleo-Windows-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\Saleo_New_Desktop.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb,*.db,*.pem,*.key,.env"
[Icons]
Name: "{group}\Saleo"; Filename: "{app}\Saleo_New_Desktop.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Saleo"; Filename: "{app}\Saleo_New_Desktop.exe"; WorkingDir: "{app}"; Tasks: desktopicon
[Run]
Filename: "{app}\Saleo_New_Desktop.exe"; Description: "Open Saleo"; Flags: nowait postinstall skipifsilent
; No UninstallDelete entries: the separate Saleo_New_Desktop data directory and
; Windows secure-storage keys must survive upgrades and uninstall.
