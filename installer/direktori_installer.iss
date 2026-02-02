; Inno Setup Script for Direktori
#define MyAppName "Direktori"
#define MyAppVersion "1.2.3"
#define BuildTime GetDateTimeString('yyyyMMdd-HHmm', '', '')
[Setup]
AppId={{5D9E2C6E-5A7B-4E1C-A7F7-6A8D7CD2B0C1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Statistik Ceria
AppPublisherURL=https://example.com/direktori
DefaultDirName={autopf}\Direktori
ArchitecturesInstallIn64BitMode=x64
DefaultGroupName=Direktori
DisableProgramGroupPage=yes
OutputDir=d:\flutter\direktori\build\installer
OutputBaseFilename={#MyAppName}-{#BuildTime}
Compression=lzma
SolidCompression=yes
SetupIconFile=d:\flutter\direktori\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\direktori.exe
WizardStyle=modern



[Tasks]
Name: "desktopicon"; Description: "Buat shortcut di Desktop"; Flags: unchecked

[Files]
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\direktori.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\flutter_inappwebview_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs
Source: "d:\flutter\direktori\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Direktori"; Filename: "{app}\direktori.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall Direktori"; Filename: "{uninstallexe}"
Name: "{autoprograms}\Direktori"; Filename: "{app}\direktori.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\Direktori"; Filename: "{app}\direktori.exe"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\direktori.exe"; Description: "Jalankan Direktori"; Flags: postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"