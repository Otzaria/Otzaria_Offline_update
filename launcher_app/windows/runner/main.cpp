#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "splash_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // הסמל עולה כאן, לפני אתחול המנוע: המנוע לוקח ~1.8 שניות שבהן עוד אין שום
  // קוד Dart שיצייר משהו, ובלעדיו הלחיצה נראית כאילו לא קרה דבר. אחרי
  // `CoInitializeEx` — WIC דורש COM.
  splash::Show();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // A medium window: the client area is 1000x720 logical, centred in the
  // primary monitor's work area (see Win32Window::Show).
  const Win32Window::Size preferred(1000, 720);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size = preferred;
  HMONITOR monitor = ::MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {sizeof(MONITORINFO)};
  if (::GetMonitorInfo(monitor, &monitor_info)) {
    // Created inside the work area; Show() sets the final size and position.
    const RECT& work = monitor_info.rcWork;
    const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    const double work_width = (work.right - work.left) / scale;
    const double work_height = (work.bottom - work.top) / scale;
    size = Win32Window::Size(
        static_cast<unsigned int>(std::min<double>(preferred.width, work_width)),
        static_cast<unsigned int>(
            std::min<double>(preferred.height, work_height)));
    origin = Win32Window::Point(static_cast<unsigned int>(work.left / scale),
                                static_cast<unsigned int>(work.top / scale));
  }
  window.SetPreferredSize(preferred, show_command == SW_SHOWMAXIMIZED);
  // Window title, Hebrew for "Otzaria Updates". Kept as escapes and not as
  // literal text on purpose: this file is compiled with /WX, and non-ASCII
  // bytes raise C4819 wherever the system code page is not UTF-8.
  const wchar_t* window_title =
      L"\u05E2\u05D3\u05DB\u05D5\u05E0\u05D9 \u05D0\u05D5\u05E6\u05E8\u05D9\u05D0";
  if (!window.Create(window_title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
