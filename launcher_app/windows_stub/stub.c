// ה-exe שיושב בשורש הכונן: כל תפקידו להריץ את הלאנצ'ר האמיתי שיושב
// ב-app-files\. Flutter ל-Windows דורש ש-flutter_windows.dll ותיקיית data\
// יהיו צמודות ל-exe, ולכן אי אפשר פשוט להוציא אותו מהתיקייה.
//
// חי מחוץ ל-windows/ בכוונה: ה-CI מריץ שם `flutter create` ודורס אותה.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <strsafe.h>
#include <wchar.h>

static const wchar_t kPayloadDir[] = L"app-files";
static const wchar_t kTargetExe[] = L"launcher_app.exe";

// הטקסט היחיד בפרויקט שלא עובר דרך otzaria_l10n — קוד C לא יכול לתלות
// בחבילת Dart. מוצג רק כשה-zip חולץ חלקית.
static int ReportFailure(void) {
  MessageBoxW(NULL,
              L"קבצי התוכנה לא נמצאו.\n\n"
              L"יש לחלץ את כל תוכן קובץ ה-ZIP לאותה תיקייה. "
              L"חסרה תיקיית המשנה:\napp-files",
              L"עדכוני אוצריא",
              MB_OK | MB_ICONERROR | MB_RTLREADING | MB_RIGHT);
  return EXIT_FAILURE;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  UNREFERENCED_PARAMETER(instance);
  UNREFERENCED_PARAMETER(prev);
  UNREFERENCED_PARAMETER(show_command);

  wchar_t stub_dir[MAX_PATH];
  const DWORD length = GetModuleFileNameW(NULL, stub_dir, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return ReportFailure();
  }
  wchar_t *separator = wcsrchr(stub_dir, L'\\');
  if (separator == NULL) {
    return ReportFailure();
  }
  *separator = L'\0';

  wchar_t work_dir[MAX_PATH];
  wchar_t target[MAX_PATH];
  if (FAILED(StringCchPrintfW(work_dir, MAX_PATH, L"%s\\%s", stub_dir,
                              kPayloadDir)) ||
      FAILED(StringCchPrintfW(target, MAX_PATH, L"%s\\%s", work_dir,
                              kTargetExe))) {
    return ReportFailure();
  }

  // lpCmdLine של wWinMain הוא כבר בלי argv[0], ולכן מועבר כמו שהוא.
  // CreateProcessW כותב לתוך המאגר הזה, ולכן הוא לא const.
  static wchar_t arguments[32768];
  if (FAILED(StringCchPrintfW(arguments, ARRAYSIZE(arguments), L"\"%s\" %s",
                              target, command_line))) {
    return ReportFailure();
  }

  STARTUPINFOW startup;
  ZeroMemory(&startup, sizeof(startup));
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process;
  ZeroMemory(&process, sizeof(process));

  // ה-cwd של הבן הוא app-files, שם הוא מצפה למצוא את ה-DLL וה-data.
  if (!CreateProcessW(target, arguments, NULL, NULL, FALSE, 0, NULL, work_dir,
                      &startup, &process)) {
    return ReportFailure();
  }

  // לא ממתינים: ה-stub מסיים מיד ומשאיר את הלאנצ'ר לבד בשורת המשימות.
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return EXIT_SUCCESS;
}
