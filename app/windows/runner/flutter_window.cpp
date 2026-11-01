#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
    case WM_SYSCHAR:
      // Alt+digit: 1..8 insert shortcut-slot items (handled by the framework),
      // 0 and 9 are unbound -- but the system still beeps for every WM_SYSCHAR
      // that never became a mnemonic (user report 2026-11-01: Alt+0..9 all beep,
      // independent of selection / panel / slot contents).
      // Swallow only Alt+digit here; Alt+letter mnemonic handling stays untouched.
      // NOTE: keep this file ASCII-only -- MSVC on this machine reads it as
      // code page 936 and C4819 is treated as an error.
      if (wparam >= static_cast<WPARAM>('0') &&
          wparam <= static_cast<WPARAM>('9')) {
        return 0;
      }
      break;
    case WM_SYSKEYDOWN:
    case WM_SYSKEYUP:
      // Swallowing WM_SYSCHAR alone was not enough (user still heard the beep),
      // so the mnemonic path is stopped one step earlier: while Alt is held the
      // key was ALREADY forwarded to the framework by HandleTopLevelWindowProc
      // above (the Alt+1..8 shortcut keeps working), and from here we only deny
      // DefWindowProc its menu-mnemonic handling -- that is what beeps.
      if ((GetKeyState(VK_MENU) & 0x8000) != 0 &&
          wparam >= static_cast<WPARAM>('0') &&
          wparam <= static_cast<WPARAM>('9')) {
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
