
[Setup]
AppName=Vasaro
AppVersion=1.0.2
DefaultDirName={pf}\Vasaro
DefaultGroupName=Vasaro
UninstallDisplayIcon={app}\Vasaro.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
LicenseFile=../../LICENSE
             

[Files]
Source: "bin\*.*"; DestDir: "{app}\bin"; Flags: recursesubdirs
Source: "etc\*.*"; DestDir: "{app}\etc"; Flags: recursesubdirs
Source: "share\*.*"; DestDir: "{app}\share"; Flags: recursesubdirs
Source: "lib\*.*"; DestDir: "{app}\lib"; Flags: recursesubdirs
Source: "..\..\res\logo.ico"; DestDir: "{app}"; DestName: "vasaro.ico"; Flags: recursesubdirs

[Tasks]
Name: desktopicon; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:";

[Icons]
Name: "{userdesktop}\Vasaro"; Filename: "{app}\bin\vasaro.exe"; IconFilename: "{app}\vasaro.ico"; Tasks: desktopicon
Name: "{group}\Vasaro"; Filename: "{app}\bin\vasaro.exe"; IconFilename: "{app}\vasaro.ico";
Name: "{app}\Start Vasaro"; Filename: "{app}\bin\vasaro.exe"; IconFilename: "{app}\vasaro.ico"

[Run]
Filename: "{app}\bin\vasaro.exe"; Description: "Launch vasaro"; Flags: postinstall 