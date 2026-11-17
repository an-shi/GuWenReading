#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The engine's accessibility bridge can crash while reparenting semantics
// nodes when a native modal dialog closes (for example the file picker).
// Refuse MSAA/UIA queries on the Flutter view's child window as well; the
// top-level window does the same in MessageHandler.
WNDPROC g_flutter_child_wndproc = nullptr;

LRESULT CALLBACK FlutterChildWndProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam) {
  if (message == WM_GETOBJECT) {
    return 0;
  }
  return CallWindowProc(g_flutter_child_wndproc, hwnd, message, wparam, lparam);
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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (g_flutter_child_wndproc == nullptr) {
    HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
    if (flutter_view) {
      auto original = reinterpret_cast<WNDPROC>(
          SetWindowLongPtr(flutter_view, GWLP_WNDPROC,
                           reinterpret_cast<LONG_PTR>(FlutterChildWndProc)));
      if (original != nullptr) {
        g_flutter_child_wndproc = original;
      }
    }
  }

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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Flutter 3.47's Windows accessibility bridge can crash in
  // AccessibilityBridge::CreateRemoveReparentedNodesUpdate when a native
  // dialog (for example the file picker) opens while a UI automation client is
  // querying the window. This is a local desktop reader and does not ship an
  // accessibility tree, so decline MSAA/UIA requests instead of crashing.
  if (message == WM_GETOBJECT) {
    return 0;
  }

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
