; Inno Setup Script for Direktori
[Setup]
AppId={{5D9E2C6E-5A7B-4E1C-A7F7-6A8D7CD2B0C1}
AppName=Direktori
AppVersion=1.0.0
AppPublisher=Statistik Ceria
AppPublisherURL=https://example.com/direktori
DefaultDirName={pf}\Direktori
DefaultGroupName=Direktori
DisableProgramGroupPage=yes
OutputDir=d:\flutter\direktori\build\installer
OutputBaseFilename=DirektoriSetup-1.0.0
Compression=lzma
SolidCompression=yes
SetupIconFile=d:\flutter\direktori\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\direktori.exe
WizardStyle=modern



[Tasks]
Name: "desktopicon"; Description: "Buat shortcut di Desktop"; Flags: unchecked

[Files]
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Direktori"; Filename: "{app}\direktori.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall Direktori"; Filename: "{uninstallexe}"
Name: "{autoprograms}\Direktori"; Filename: "{app}\direktori.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\Direktori"; Filename: "{app}\direktori.exe"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\direktori.exe"; Description: "Jalankan Direktori"; Flags: postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
