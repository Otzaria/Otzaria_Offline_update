// ה-exe היחיד שמופץ ל-Windows. הוא נושא בתוכו את כל ערמת הקבצים כ-resource,
// מחלץ אותה ל-app-files\ לידו בהרצה הראשונה, ומריץ משם את הלאנצ'ר האמיתי.
// Flutter ל-Windows דורש ש-flutter_windows.dll ותיקיית data\ יהיו צמודות
// ל-exe, ולכן אי אפשר פשוט להוציא אותו מהתיקייה.
//
// חי מחוץ ל-windows/ בכוונה: ה-CI מריץ שם `flutter create` ודורס אותה.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <strsafe.h>
#include <wchar.h>

// חייב להתאים למזהה שב-stub.rc.
#define PAYLOAD_RESOURCE_ID 100

static const wchar_t kPayloadDir[] = L"app-files";
static const wchar_t kTargetExe[] = L"launcher_app.exe";
// נכתב רק אחרי חילוץ שהצליח, ולכן חילוץ שנקטע באמצע לא ייראה שלם.
static const wchar_t kReadyMarker[] = L".ready";

// הטקסט היחיד בפרויקט שלא עובר דרך otzaria_l10n — קוד C לא יכול לתלות
// בחבילת Dart. מוצג רק כשההכנה להרצה הראשונה נכשלה.
static int ReportFailure(void) {
  MessageBoxW(NULL,
              L"הכנת התוכנה להרצה נכשלה.\n\n"
              L"יש להעתיק את הקובץ לכונן שיש בו מקום פנוי והרשאת כתיבה, "
              L"ולהריץ אותו משם שוב.",
              L"עדכוני אוצריא",
              MB_OK | MB_ICONERROR | MB_RTLREADING | MB_RIGHT);
  return EXIT_FAILURE;
}

// רק שורש כונן ("E:\") מסתיים בבקסלאש — שם הוא חלק מהנתיב.
static BOOL EndsWithBackslash(const wchar_t *dir) {
  const size_t length = wcslen(dir);
  return length > 0 && dir[length - 1] == L'\\';
}

// מונע נתיבים כמו "E:\\app-files".
static const wchar_t *SeparatorFor(const wchar_t *dir) {
  return EndsWithBackslash(dir) ? L"" : L"\\";
}

// tar.exe מקבל את הארגומנטים שלו דרך ה-ANSI code page, ולכן נתיב עברי
// (תיקיית משתמש, למשל) עלול להגיע אליו משובש. שם 8.3 הוא ASCII טהור.
static void ShortenPath(wchar_t *path, size_t size) {
  wchar_t buffer[MAX_PATH];
  const DWORD length = GetShortPathNameW(path, buffer, MAX_PATH);
  if (length > 0 && length < MAX_PATH) {
    StringCchCopyW(path, size, buffer);
  }
}

// כותב את ה-zip המוטמע לקובץ על הדיסק, כי tar.exe קורא מקובץ ולא מ-stdin.
static BOOL WritePayloadZip(const wchar_t *zip_path) {
  // ה-cast נחוץ כי RT_RCDATA הוא TCHAR, וה-stub לא מקומפל עם UNICODE.
  HRSRC resource = FindResourceW(NULL, MAKEINTRESOURCEW(PAYLOAD_RESOURCE_ID),
                                 (const wchar_t *)RT_RCDATA);
  if (resource == NULL) {
    return FALSE;
  }
  const DWORD size = SizeofResource(NULL, resource);
  HGLOBAL loaded = LoadResource(NULL, resource);
  if (size == 0 || loaded == NULL) {
    return FALSE;
  }
  const void *bytes = LockResource(loaded);
  if (bytes == NULL) {
    return FALSE;
  }

  HANDLE file = CreateFileW(zip_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_TEMPORARY, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return FALSE;
  }
  DWORD written = 0;
  const BOOL ok =
      WriteFile(file, bytes, size, &written, NULL) && written == size;
  CloseHandle(file);
  return ok;
}

// חלון הקונסולה של tar נשאר גלוי בכוונה: חילוץ לכונן USB אורך שניות,
// ובלי שום סימן חיים ההרצה הראשונה נראית תקועה.
static BOOL RunTar(const wchar_t *zip_path, const wchar_t *dest_dir) {
  wchar_t tar[MAX_PATH];
  const UINT length = GetSystemDirectoryW(tar, MAX_PATH);
  if (length == 0 || length >= MAX_PATH ||
      FAILED(StringCchCatW(tar, MAX_PATH, L"\\tar.exe"))) {
    return FALSE;
  }

  wchar_t zip_arg[MAX_PATH];
  wchar_t dest_arg[MAX_PATH];
  if (FAILED(StringCchCopyW(zip_arg, MAX_PATH, zip_path)) ||
      FAILED(StringCchCopyW(dest_arg, MAX_PATH, dest_dir))) {
    return FALSE;
  }
  ShortenPath(zip_arg, MAX_PATH);
  ShortenPath(dest_arg, MAX_PATH);
  // "E:\" בתוך מרכאות נשבר — הבקסלאש בורח מהמרכאה הסוגרת. "E:\." שקול לו.
  if (EndsWithBackslash(dest_arg) &&
      FAILED(StringCchCatW(dest_arg, MAX_PATH, L"."))) {
    return FALSE;
  }

  // CreateProcessW כותב לתוך המאגר הזה, ולכן הוא לא const.
  static wchar_t command[32768];
  if (FAILED(StringCchPrintfW(command, ARRAYSIZE(command),
                              L"\"%s\" -x -v -f \"%s\" -C \"%s\"", tar,
                              zip_arg, dest_arg))) {
    return FALSE;
  }

  STARTUPINFOW startup;
  ZeroMemory(&startup, sizeof(startup));
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process;
  ZeroMemory(&process, sizeof(process));
  if (!CreateProcessW(tar, command, NULL, NULL, FALSE, 0, NULL, dest_dir,
                      &startup, &process)) {
    return FALSE;
  }

  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 1;
  const BOOL ok =
      GetExitCodeProcess(process.hProcess, &exit_code) && exit_code == 0;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return ok;
}

// ה-zip נכתב ל-%TEMP% ולא ליד ה-exe, כדי לא להשאיר פסולת על הכונן של
// המשתמש אם החילוץ נכשל.
static BOOL ExtractPayload(const wchar_t *dest_dir, const wchar_t *marker) {
  wchar_t temp_dir[MAX_PATH];
  const DWORD length = GetTempPathW(MAX_PATH, temp_dir);
  if (length == 0 || length >= MAX_PATH) {
    return FALSE;
  }
  wchar_t zip_path[MAX_PATH];
  if (GetTempFileNameW(temp_dir, L"otz", 0, zip_path) == 0) {
    return FALSE;
  }

  const BOOL extracted =
      WritePayloadZip(zip_path) && RunTar(zip_path, dest_dir);
  DeleteFileW(zip_path);
  if (!extracted) {
    return FALSE;
  }

  HANDLE done = CreateFileW(marker, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN, NULL);
  if (done == INVALID_HANDLE_VALUE) {
    return FALSE;
  }
  CloseHandle(done);
  return TRUE;
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
  // בשורש כונן ("E:\עדכוני אוצריא.exe") משאירים את הבקסלאש: "E:" לבדו
  // מסמן את התיקייה הנוכחית בכונן, ולא את השורש.
  const BOOL at_drive_root = (separator == stub_dir + 2 && stub_dir[1] == L':');
  separator[at_drive_root ? 1 : 0] = L'\0';

  wchar_t work_dir[MAX_PATH];
  wchar_t target[MAX_PATH];
  wchar_t marker[MAX_PATH];
  if (FAILED(StringCchPrintfW(work_dir, MAX_PATH, L"%s%s%s", stub_dir,
                              SeparatorFor(stub_dir), kPayloadDir)) ||
      FAILED(StringCchPrintfW(target, MAX_PATH, L"%s\\%s", work_dir,
                              kTargetExe)) ||
      FAILED(StringCchPrintfW(marker, MAX_PATH, L"%s\\%s", work_dir,
                              kReadyMarker))) {
    return ReportFailure();
  }

  // הרצה ראשונה בלבד; מכאן והלאה ה-marker קיים והחילוץ מדולג. גם משחזר
  // ערמת קבצים שנמחקה — ה-payload נשאר מוטמע ב-exe לתמיד.
  if (GetFileAttributesW(marker) == INVALID_FILE_ATTRIBUTES &&
      !ExtractPayload(stub_dir, marker)) {
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
