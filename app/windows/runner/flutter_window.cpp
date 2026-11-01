#include "flutter_window.h"

#include <flutter/generated_plugin_registrant.h>

#include <cstring>
#include <optional>

namespace {

// ---------------------------------------------------------------------------
// Silence the Alt+digit beep WITHOUT taking the Alt+1..8 shortcut with it.
//
// The seam matters. The beep is produced AFTER the engine has already seen the
// character: the engine reads WM_SYSCHAR (that is how the deferred key event for
// Alt+digit is dispatched -- the shortcut works that way), then passes the very
// same message on to DefWindowProcW, whose default handling plays the system
// beep. Swallowing the message earlier -- subclassing the FLUTTERVIEW child,
// tried on 2026-11-01 -- also takes the character away from the engine, and the
// shortcut dies with it. The only correct seam is between the engine and
// DefWindowProc, and the engine reaches DefWindowProc through the import table
// of flutter_windows.dll. So we replace that one import and forward everything
// else untouched.
//
// Failure mode is a no-op: if the import cannot be found (say, after a Flutter
// SDK upgrade) nothing gets patched, the app behaves exactly as before, and the
// beep simply comes back.
//
// Measured on 2026-11-01: only WM_SYSCHAR (0x0106) actually reaches
// DefWindowProcW for Alt+digit -- the engine consumes the key messages itself.
// The key messages are still listed below because on another Windows build the
// default handling could be the one that beeps, and swallowing them here is
// harmless: by the time we run, the engine has already forwarded them.
// ---------------------------------------------------------------------------

using DefWindowProcWFn = LRESULT(WINAPI*)(HWND, UINT, WPARAM, LPARAM);

DefWindowProcWFn g_real_def_window_proc = nullptr;

bool IsAltDigitMessage(UINT message, WPARAM wparam) {
  if (message != WM_SYSCHAR && message != WM_SYSKEYDOWN &&
      message != WM_SYSKEYUP) {
    return false;
  }
  if ((::GetKeyState(VK_MENU) & 0x8000) == 0) {
    return false;
  }
  return wparam >= static_cast<WPARAM>('0') && wparam <= static_cast<WPARAM>('9');
}

LRESULT WINAPI HookDefWindowProcW(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
  if (IsAltDigitMessage(message, wparam)) {
    return 0;
  }
  return g_real_def_window_proc(hwnd, message, wparam, lparam);
}

// Replaces one named import in |module|'s import address table.
// Returns the previous target, or nullptr when the import is not there.
void* PatchImport(HMODULE module, const char* func_name, void* replacement) {
  if (module == nullptr) {
    return nullptr;
  }
  auto base = reinterpret_cast<BYTE*>(module);
  auto dos = reinterpret_cast<PIMAGE_DOS_HEADER>(base);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
    return nullptr;
  }
  auto nt = reinterpret_cast<PIMAGE_NT_HEADERS>(base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE) {
    return nullptr;
  }
  const IMAGE_DATA_DIRECTORY dir =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (dir.VirtualAddress == 0) {
    return nullptr;
  }

  auto desc =
      reinterpret_cast<PIMAGE_IMPORT_DESCRIPTOR>(base + dir.VirtualAddress);
  for (; desc->Name != 0; ++desc) {
    // Names live in OriginalFirstThunk; a bound import has none and cannot be
    // patched by name.
    if (desc->OriginalFirstThunk == 0) {
      continue;
    }
    auto thunk = reinterpret_cast<PIMAGE_THUNK_DATA>(base + desc->FirstThunk);
    auto name_thunk =
        reinterpret_cast<PIMAGE_THUNK_DATA>(base + desc->OriginalFirstThunk);
    for (; thunk->u1.Function != 0; ++thunk, ++name_thunk) {
      if (IMAGE_SNAP_BY_ORDINAL(name_thunk->u1.Ordinal)) {
        continue;
      }
      auto import = reinterpret_cast<PIMAGE_IMPORT_BY_NAME>(
          base + name_thunk->u1.AddressOfData);
      if (std::strcmp(reinterpret_cast<const char*>(import->Name), func_name) !=
          0) {
        continue;
      }
      void* original = reinterpret_cast<void*>(thunk->u1.Function);
      DWORD old_protect = 0;
      if (!::VirtualProtect(&thunk->u1.Function, sizeof(ULONG_PTR),
                            PAGE_READWRITE, &old_protect)) {
        return nullptr;
      }
      thunk->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
      DWORD ignored = 0;
      ::VirtualProtect(&thunk->u1.Function, sizeof(ULONG_PTR), old_protect,
                       &ignored);
      ::FlushInstructionCache(::GetCurrentProcess(), &thunk->u1.Function,
                              sizeof(ULONG_PTR));
      return original;
    }
  }
  return nullptr;
}

void MuteAltDigitBeep() {
  HMODULE engine = ::GetModuleHandleW(L"flutter_windows.dll");
  if (engine == nullptr) {
    return;
  }
  void* original = PatchImport(engine, "DefWindowProcW",
                               reinterpret_cast<void*>(&HookDefWindowProcW));
  if (original != nullptr) {
    // Assigned before any window message can be dispatched again: we are inside
    // OnCreate, which runs while this thread is still handling WM_CREATE.
    g_real_def_window_proc = reinterpret_cast<DefWindowProcWFn>(original);
  }
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

  // Alt+digit: keep the shortcut, drop the beep. See the block comment above.
  MuteAltDigitBeep();

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
