// ה-exe היחיד שמופץ ל-Windows. הוא נושא בתוכו את כל ערמת הקבצים כ-resource,
// מחלץ אותה ל-app-files\ לידו בהרצה הראשונה, ומריץ משם את הלאנצ'ר האמיתי.
// Flutter ל-Windows דורש ש-flutter_windows.dll ותיקיית data\ יהיו צמודות
// ל-exe, ולכן אי אפשר פשוט להוציא אותו מהתיקייה.
//
// חי מחוץ ל-windows/ בכוונה: ה-CI מריץ שם `flutter create` ודורס אותה.
//
// הוא גם הצד השני של העדכון העצמי: הלאנצ'ר מחליף את ה-exe הזה בגרסה חדשה
// (ראו `lib/src/self_update/`) ומריץ אותו עם `--after-update=<pid>`. ה-exe
// החדש נושא payload חדש, מזהה שהמרקר `.ready` מחזיק גרסה אחרת, ומחלץ אותו
// **מעל** app-files הקיימת. `OtzariaData\` שבתוכה לא נוגעים בה בכלל — לא
// מוחקים כלום, רק דורסים את מה שב-payload.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <strsafe.h>
#include <wchar.h>

// גרסת ה-payload, מיוצרת מ-`pubspec.yaml` ע"י build_stub.ps1 אל build\.
#include "version.h"

// חייב להתאים למזהה שב-stub.rc.
#define PAYLOAD_RESOURCE_ID 100

static const wchar_t kPayloadDir[] = L"app-files";
static const wchar_t kTargetExe[] = L"launcher_app.exe";
// נכתב רק אחרי חילוץ שהצליח, ולכן חילוץ שנקטע באמצע לא ייראה שלם. מאז
// העדכון העצמי הוא גם מחזיק את **גרסת ה-payload** שחולצה: מרקר עם גרסה
// אחרת (או ריק, כמו זה שכתבו גרסאות קודמות) פירושו "יש לחלץ מחדש".
static const wchar_t kReadyMarker[] = L".ready";

// הדגל שהלאנצ'ר מעביר אחרי שהחליף את ה-exe. חייב להתאים ל-
// `LauncherInstallLayout.afterUpdateFlag`.
static const wchar_t kAfterUpdateFlag[] = L"--after-update=";

// משתנה הסביבה שבו מועבר ללאנצ'ר הנתיב של ה-exe הזה — הוא לבדו יודע אותו,
// כי `Platform.resolvedExecutable` של הבן מצביע לתוך app-files. חייב להתאים
// ל-`LauncherInstallLayout.stubPathEnvVar`.
static const wchar_t kStubPathEnvVar[] = L"OTZARIA_LAUNCHER_STUB";

// כמה להמתין לסגירת הלאנצ'ר הישן לפני חילוץ מחדש. הוא נסגר מיד אחרי שהוא
// מריץ אותנו; הגבול קיים רק כדי שתקלה לא תשאיר את ה-stub תלוי לנצח.
#define AFTER_UPDATE_WAIT_MS 60000

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

// גרסת ה-payload שחולצה בפועל, כפי שנרשמה במרקר. ASCII בכוונה — מספר גרסה
// הוא ספרות ונקודות, ואין צורך בקידוד.
static BOOL MarkerMatchesPayload(const wchar_t *marker) {
  HANDLE file = CreateFileW(marker, GENERIC_READ, FILE_SHARE_READ, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return FALSE;
  }
  char buffer[64];
  DWORD read = 0;
  const BOOL ok =
      ReadFile(file, buffer, (DWORD)(sizeof(buffer) - 1), &read, NULL);
  CloseHandle(file);
  if (!ok) {
    return FALSE;
  }
  buffer[read] = '\0';
  return strcmp(buffer, PAYLOAD_VERSION_A) == 0;
}

// FILE_ATTRIBUTE_HIDDEN חייב להישאר גם כאן: CREATE_ALWAYS על קובץ מוסתר
// קיים נכשל ב-ACCESS_DENIED אם התכונה לא צוינה מחדש.
static BOOL WriteMarker(const wchar_t *marker) {
  HANDLE file = CreateFileW(marker, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return FALSE;
  }
  const DWORD length = (DWORD)strlen(PAYLOAD_VERSION_A);
  DWORD written = 0;
  const BOOL ok =
      WriteFile(file, PAYLOAD_VERSION_A, length, &written, NULL) &&
      written == length;
  CloseHandle(file);
  return ok;
}

// שולף את ה-pid מהדגל **ומסיר את הדגל** מהמחרוזת, כדי שלא יועבר לתהליך הבן.
static DWORD TakeAfterUpdatePid(wchar_t *command_line) {
  wchar_t *found = wcsstr(command_line, kAfterUpdateFlag);
  if (found == NULL) {
    return 0;
  }
  wchar_t *cursor = found + wcslen(kAfterUpdateFlag);
  wchar_t *end = cursor;
  const DWORD process_id = (DWORD)wcstoul(cursor, &end, 10);
  memmove(found, end, (wcslen(end) + 1) * sizeof(wchar_t));
  return process_id;
}

// ממתין לסגירת הלאנצ'ר הישן. בלי זה tar היה מנסה לדרוס את launcher_app.exe
// ואת flutter_windows.dll בזמן שהם עוד נעולים על ידו, והחילוץ היה נכשל.
static void WaitForProcessExit(DWORD process_id) {
  if (process_id == 0) {
    return;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, process_id);
  if (process == NULL) {
    return;  // כבר יצא (או שאין הרשאה) — ממשיכים.
  }
  WaitForSingleObject(process, AFTER_UPDATE_WAIT_MS);
  CloseHandle(process);
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
  return WriteMarker(marker);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  UNREFERENCED_PARAMETER(instance);
  UNREFERENCED_PARAMETER(prev);
  UNREFERENCED_PARAMETER(show_command);

  wchar_t stub_path[MAX_PATH];
  wchar_t stub_dir[MAX_PATH];
  const DWORD length = GetModuleFileNameW(NULL, stub_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH ||
      FAILED(StringCchCopyW(stub_dir, MAX_PATH, stub_path))) {
    return ReportFailure();
  }
  // הלאנצ'ר צריך את הנתיב שלנו כדי לדעת איזה קובץ להחליף בעדכון הבא;
  // התהליך הבן יורש את הסביבה שלנו, ולכן די בהצבה כאן.
  SetEnvironmentVariableW(kStubPathEnvVar, stub_path);

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

  // lpCmdLine של wWinMain הוא כבר בלי argv[0]. מועתק כדי שנוכל להסיר ממנו
  // את הדגל הפנימי שלנו בלי לגעת במאגר של ה-CRT.
  static wchar_t forwarded[32768];
  if (FAILED(StringCchCopyW(forwarded, ARRAYSIZE(forwarded), command_line))) {
    return ReportFailure();
  }
  const DWORD after_update_pid = TakeAfterUpdatePid(forwarded);

  // חילוץ בהרצה הראשונה, וגם כשגרסת ה-payload שונה מזו שבמרקר — כלומר אחרי
  // שהעדכון העצמי החליף את ה-exe הזה. גם משחזר ערמת קבצים שנמחקה: ה-payload
  // נשאר מוטמע ב-exe לתמיד.
  if (!MarkerMatchesPayload(marker)) {
    WaitForProcessExit(after_update_pid);
    // חילוץ שנכשל כשכבר יש לאנצ'ר על הדיסק אינו סוף הדרך: מריצים את מה שיש,
    // והמרקר (שלא נכתב) יגרום לניסיון נוסף בהרצה הבאה. תיבת שגיאה נשמרת
    // למצב שבו אין מה להריץ בכלל.
    if (!ExtractPayload(stub_dir, marker) &&
        GetFileAttributesW(target) == INVALID_FILE_ATTRIBUTES) {
      return ReportFailure();
    }
  }

  // CreateProcessW כותב לתוך המאגר הזה, ולכן הוא לא const.
  static wchar_t arguments[32768];
  if (FAILED(StringCchPrintfW(arguments, ARRAYSIZE(arguments), L"\"%s\" %s",
                              target, forwarded))) {
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
