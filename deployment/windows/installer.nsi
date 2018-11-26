
!define PRODUCT_NAME "Vasaro"
!define PRODUCT_VERSION "1.0"
!define PRODUCT_PUBLISHER "Andrea Fontana"
 
SetCompressor lzma
 
; MUI 1.67 compatible ------
!include "MUI.nsh"
 
; MUI Settings
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
 
; Welcome page
!insertmacro MUI_PAGE_WELCOME
; Components page
!insertmacro MUI_PAGE_COMPONENTS
; Instfiles page
!insertmacro MUI_PAGE_INSTFILES
; Finish page
!insertmacro MUI_PAGE_FINISH
 
; Language files
!insertmacro MUI_LANGUAGE "English"
 
; Reserve files
!insertmacro MUI_RESERVEFILE_INSTALLOPTIONS
 
; MUI end ------
 
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "vasaro-1.0-setup.exe"
InstallDir "$PROGRAMFILES64\Vasaro"
ShowInstDetails show


Section -SETTINGS
  SetOutPath "$INSTDIR"
  SetOverwrite ifnewer
  WriteUninstaller $INSTDIR\uninstaller.exe
SectionEnd

Section Vasaro
   SectionIn 1 RO
   File vasaro.exe
   File SDL2.dll
SectionEnd

Section "gtk3-runtime" SEC01
  File "gtk3-runtime-3.24.1-2018-10-03-ts-win64.exe"
  ExecWait "$INSTDIR\gtk3-runtime-3.24.1-2018-10-03-ts-win64.exe /S"
  Delete "$INSTDIR\gtk3-runtime-3.24.1-2018-10-03-ts-win64.exe"
SectionEnd


 

Section "Uninstall"
 
   Delete $INSTDIR\uninstaller.exe
   Delete $INSTDIR\vasaro.exe
   Delete $INSTDIR\SDL2.dll

SectionEnd
