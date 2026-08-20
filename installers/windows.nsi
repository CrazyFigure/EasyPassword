; EasyPassword Windows installer script (NSIS 3.x)
; Usage: makensis -DVERSION=1.0.0 -DOUTPUT=dist/EasyPassword-Setup.exe -DSOURCE=build/windows/x64/runner/Release installers/windows.nsi

; 声明脚本使用 UTF-8 编码，避免中文字符串在编译时乱码
Unicode True

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
InstallDirRegKey HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation"
RequestExecutionLevel admin

; 安装器自身图标（任务栏/资源管理器/任务管理器）。
; 路径可通过 -DMUI_ICON_PATH="xxx" 覆盖，默认取项目 installers/installer.ico
!ifndef MUI_ICON_PATH
  !define MUI_ICON_PATH "installers\installer.ico"
!endif
!define MUI_ICON "${MUI_ICON_PATH}"
!define MUI_UNICON "${MUI_ICON_PATH}"

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
  ; 升级前必须关闭旧进程，否则 Windows 可能锁住 EXE/DLL，形成新旧文件混装。
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "EasyPassword"
  StrCmp $0 0 app_closed
  MessageBox MB_YESNO|MB_ICONEXCLAMATION \
    "EasyPassword 正在运行，安装前需要关闭。是否由安装程序立即关闭？" \
    IDYES close_running_app IDNO cancel_install
  close_running_app:
    ; 只结束应用主进程，不使用 /T：应用内更新时由普通用户权限的临时辅助进程
    ; 等待本安装器结束并拉起新版本，误杀进程树会导致更新完成后无法自动恢复。
    nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /IM easypassword.exe'
    Pop $1
    Pop $2
    Sleep 500
    FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "EasyPassword"
    StrCmp $0 0 app_closed
    MessageBox MB_OK|MB_ICONSTOP "无法关闭 EasyPassword，请在任务管理器中结束进程后重试。"
    Abort
  cancel_install:
    Abort
  app_closed:

  SetOutPath "$INSTDIR"
  ; 每次发布强制使用同一次构建的完整文件集，不能按文件时间戳选择性跳过。
  SetOverwrite on
  ; SOURCE must be an absolute Windows path (e.g. D:\a\...\Release)
  File /r "${SOURCE}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoRepair" 1
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
