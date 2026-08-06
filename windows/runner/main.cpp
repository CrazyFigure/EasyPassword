#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 单实例互斥量限制在当前登录会话，避免重复点击后堆积多个后台进程。
constexpr const wchar_t kSingleInstanceMutex[] =
    L"Local\\CrazyFigure.EasyPassword.SingleInstance";

// 已有实例可能还在等待 Flutter 首帧；再次启动时主动显示并激活它。
void ActivateExistingInstance() {
  HWND existing_window =
      ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"EasyPassword");
  if (existing_window == nullptr) {
    return;
  }
  ::ShowWindow(existing_window, SW_RESTORE);
  ::SetForegroundWindow(existing_window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 命名互斥量在窗口创建前建立，后续启动只负责唤醒已有实例。
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 默认窗口 4:3（960x720）：缩短横向长度，更接近内容为主的卡片布局
  Win32Window::Size size(960, 720);
  // 窗口居中：按主显示器工作区（已排除任务栏）计算左上角坐标。
  // 这里传逻辑坐标即可，Win32Window::Create 内部会按 DPI 缩放。
  Win32Window::Point origin(10, 10);
  {
    // 先取主显示器，再拿它的工作区与 DPI，把物理像素换算回逻辑像素
    HMONITOR monitor = ::MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(MONITORINFO);
    if (::GetMonitorInfo(monitor, &monitor_info)) {
      UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
      double scale_factor = dpi / 96.0;
      const RECT& work = monitor_info.rcWork;
      // 工作区尺寸是物理像素，除以缩放比得到逻辑尺寸后再与窗口逻辑尺寸做居中
      double work_width = (work.right - work.left) / scale_factor;
      double work_height = (work.bottom - work.top) / scale_factor;
      double left = work.left / scale_factor + (work_width - size.width) / 2;
      double top = work.top / scale_factor + (work_height - size.height) / 2;
      // 窗口比工作区还大时钳到左上角，避免标题栏跑到屏幕外拖不动
      origin = Win32Window::Point(
          static_cast<unsigned int>(left > 0 ? left : 0),
          static_cast<unsigned int>(top > 0 ? top : 0));
    }
  }
  if (!window.Create(L"EasyPassword", origin, size)) {
    ::ReleaseMutex(single_instance);
    ::CloseHandle(single_instance);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  // Dart 入口会先绘制启动页；这里立即显示原生窗口，初始化异常时也不会隐身。
  window.Show();
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::ReleaseMutex(single_instance);
  ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
