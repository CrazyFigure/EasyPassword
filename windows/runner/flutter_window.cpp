#include "flutter_window.h"

#include <optional>
#include <set>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// GDI 字体枚举回调：lfFaceName 是字体族名；过滤竖排字体的 @ 前缀。
int CALLBACK CollectFontFamily(const LOGFONTW* log_font,
                               const TEXTMETRICW* text_metric,
                               DWORD font_type,
                               LPARAM data) {
  auto* families = reinterpret_cast<std::set<std::wstring>*>(data);
  const std::wstring family(log_font->lfFaceName);
  if (!family.empty() && family.front() != L'@') {
    families->insert(family);
  }
  return 1;
}

// 从当前 Windows 字体集合读取真实字体族，结果用于可搜索下拉框。
flutter::EncodableList ListInstalledFontFamilies() {
  std::set<std::wstring> families;
  LOGFONTW filter{};
  filter.lfCharSet = DEFAULT_CHARSET;
  const HDC device_context = GetDC(nullptr);
  if (device_context != nullptr) {
    EnumFontFamiliesExW(device_context, &filter,
                        reinterpret_cast<FONTENUMPROCW>(CollectFontFamily),
                        reinterpret_cast<LPARAM>(&families), 0);
    ReleaseDC(nullptr, device_context);
  }

  flutter::EncodableList result;
  result.reserve(families.size());
  for (const auto& family : families) {
    // StandardMethodCodec 使用 UTF-8 字符串；先计算长度再完成宽字符转换。
    const int size = WideCharToMultiByte(CP_UTF8, 0, family.c_str(),
                                         static_cast<int>(family.size()),
                                         nullptr, 0, nullptr, nullptr);
    if (size <= 0) {
      continue;
    }
    std::string utf8(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, family.c_str(),
                        static_cast<int>(family.size()), utf8.data(), size,
                        nullptr, nullptr);
    result.emplace_back(utf8);
  }
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // 平台字体列表按需返回，应用启动阶段不会触发枚举。
  font_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "easypassword/system_font",
      &flutter::StandardMethodCodec::GetInstance());
  font_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<
             flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "listSystemFonts") {
          result->Success(flutter::EncodableValue(ListInstalledFontFamilies()));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  font_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
