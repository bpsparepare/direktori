; Inno Setup script for Direktori Windows installer
[Setup]
AppId={{F3B21E6A-6D24-4D0D-9B7C-96B3C4F0E7D2}}
AppName=Direktori
AppVersion=1.0.0
AppPublisher=Statistik Ceria
DefaultDirName={userappdata}\Direktori
DefaultGroupName=Direktori
AllowNoIcons=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=direktori-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
DisableDirPage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\\build\\windows\\x64\\runner\\Release\\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion; Excludes: "*.msix;*.zip;*.pdb;*.lib;*.exp;*.cer;AppxBlockMap.xml;[Content_Types].xml"

[Icons]
Name: "{group}\Direktori"; Filename: "{app}\direktori.exe"
Name: "{commondesktop}\Direktori"; Filename: "{app}\direktori.exe"

[Run]
Filename: "{app}\direktori.exe"; Description: "Jalankan Direktori"; Flags: nowait postinstall skipifsilent
