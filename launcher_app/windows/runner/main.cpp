#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include "flutter_window.h"
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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // החלון מוצג מוגדל (Win32Window::Show). נותנים לו כבר ביצירה את מידות שטח
  // העבודה של הצג, כדי שהפריים הראשון ייוצר בגודלו הסופי ולא ייצבע קטן
  // ויימתח. Create מצפה למידות לוגיות, ולכן מחלקים ב-scale של הצג.
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  RECT work_area;
  if (::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    const POINT top_left = {work_area.left, work_area.top};
    const double scale =
        FlutterDesktopGetDpiForMonitor(
            ::MonitorFromPoint(top_left, MONITOR_DEFAULTTOPRIMARY)) /
        96.0;
    origin = Win32Window::Point(
        static_cast<unsigned int>(work_area.left / scale),
        static_cast<unsigned int>(work_area.top / scale));
    size = Win32Window::Size(
        static_cast<unsigned int>((work_area.right - work_area.left) / scale),
        static_cast<unsigned int>((work_area.bottom - work_area.top) / scale));
  }
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
