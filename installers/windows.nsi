; EasyPassword Windows installer script (NSIS 3.x)
; Usage: makensis -DVERSION=1.0.0 -DOUTPUT=dist/EasyPassword-Setup.exe -DSOURCE=build/windows/x64/runner/Release installers/windows.nsi

!include "MUI2.nsh"

; Use LZMA solid compression to minimize installer size
SetCompressor /SOLID lzma

!define PRODUCT_NAME "EasyPassword"
!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!ifndef SOURCE
  !define SOURCE "build/windows/x64/runner/Release"
!endif
!ifndef OUTPUT
  !define OUTPUT "dist/EasyPassword-Setup.exe"
!endif

!define PRODUCT_PUBLISHER "EasyPassword Team"
!define PRODUCT_WEB_SITE "https://github.com/CrazyFigure/EasyPassword"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"

Name "${PRODUCT_NAME} ${VERSION}"
OutFile "${OUTPUT}"
InstallDir "$PROGRAMFILES64\EasyPassword"
InstallDirRegKey HKLM "${PRODUCT_UNINST_KEY}" "UninstallString"
RequestExecutionLevel admin

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

; ---------- UI ----------
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

; ---------- Install ----------
Section "MainSection" SEC01
  SetOutPath "$INSTDIR"
  SetOverwrite ifnewer
  ; SOURCE must be an absolute Windows path (e.g. D:\a\...\Release)
  File /r "${SOURCE}\*.*"
  CreateDirectory "$SMPROGRAMS\EasyPassword"
  CreateShortCut "$SMPROGRAMS\EasyPassword\EasyPassword.lnk" "$INSTDIR\easypassword.exe"
  CreateShortCut "$DESKTOP\EasyPassword.lnk" "$INSTDIR\easypassword.exe"
SectionEnd

; ---------- Uninstall ----------
Section Uninstall
  Delete "$INSTDIR\*.*"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\EasyPassword\EasyPassword.lnk"
  RMDir "$SMPROGRAMS\EasyPassword"
  Delete "$DESKTOP\EasyPassword.lnk"
  DeleteRegKey ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}"
SectionEnd
