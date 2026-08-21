; ==================================================
#define AppVersion "1.0.0"
#define BuildNumber "2"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=MaidKit
AppVersion={#AppVersion}
AppPublisher=dev.solsynth
AppPublisherURL=https://solsynth.dev
AppUpdatesURL=https://github.com/Solsynth/MaidKit/releases
AppCopyright=Copyright © 2026 dev.solsynth
VersionInfoVersion={#FullVersion}
UninstallDisplayName=MaidKit
UninstallDisplayIcon={app}\maid_kit.exe

DefaultDirName={commonpf}\MaidKit
UsePreviousAppDir=no

OutputDir=.\Installer
OutputBaseFilename=windows-x86_64-setup
SetupIconFile=.\assets\icons\icon.ico

Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin

[Files]
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MaidKit"; Filename: "{app}\maid_kit.exe"; IconFilename: "{app}\maid_kit.exe"
Name: "{group}\{cm:UninstallProgram,MaidKit}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MaidKit"; Filename: "{app}\maid_kit.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\maid_kit.exe"; Description: "Launch MaidKit"; Flags: nowait postinstall skipifsilent
; Stop every MaidKit engine before removing files locked by Flutter/WebView2.

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM maid_kit.exe"; Flags: runhidden waituntilterminated skipifdoesntexist

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\dev.solsynth\MaidKit"
Type: files; Name: "{group}\MaidKit.lnk"
Type: files; Name: "{autodesktop}\MaidKit.lnk"
