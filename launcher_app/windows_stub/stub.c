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
#include <compressapi.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strsafe.h>
#include <wchar.h>

// גרסת ה-payload, מיוצרת מ-`pubspec.yaml` ע"י build_stub.ps1 אל build\.
#include "version.h"

// חייב להתאים למזהה שב-stub.rc.
#define PAYLOAD_RESOURCE_ID 100

// כותרת ה-payload המוטמע. **חייבת להתאים ל-`pack_payload.ps1`**, שבונה אותו;
// `stub_contract_test.dart` מאמת את המספרים.
static const char kPayloadMagic[8] = {'O', 'T', 'Z', 'P', 'A', 'Y', '1', '\0'};

#pragma pack(push, 1)
typedef struct {
  char magic[8];
  DWORD algorithm;   // אלגוריתם ה-Compression API (LZMS)
  DWORD file_count;
  ULONGLONG raw_size;  // גודל הגוש אחרי פרישה
} PayloadHeader;
#pragma pack(pop)

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

// גרסת ה-payload שה-exe הזה נושא, כפי שהיא נמסרת ללאנצ'ר. הוא משווה אותה
// לשלו: אי-התאמה פירושה app-files ישנה מתחת ל-exe חדש — מצב שהמרקר לבדו
// אינו מזהה, כי העתקה ידנית חלקית בין מחשבים מעתיקה גם אותו. חייב להתאים
// ל-`LauncherInstallLayout.payloadVersionEnvVar`.
static const wchar_t kPayloadVersionEnvVar[] = L"OTZARIA_PAYLOAD_VERSION";

// = `LauncherSelfInstaller.stagedName` / `.previousName` / `.targetName`.
// קובץ ה-target מחזיק את שם ה-exe שהוחלף בפועל — המשתמש יכול לשנות אותו.
static const wchar_t kStagedExeName[] = L".launcher-update.exe";
static const wchar_t kPreviousExeName[] = L".launcher-previous.exe";
static const wchar_t kTargetFileName[] = L".launcher-update.target";

// הלוג של ה-stub, לצד `launcher.log` של הלאנצ'ר. בלעדיו כל מה שקורה כאן —
// חילוץ שנכשל, קובץ שלא נכתב, מרקר שאינו תואם — קורה בשקט מוחלט, ודיווח על
// עדכון שנתקע אינו ניתן לאבחון בכלל.
static const wchar_t kDataDirName[] = L"OtzariaData";  // = `AppPaths.dirName`
static const wchar_t kLogDirName[] = L"logs";
static const wchar_t kLogFileName[] = L"stub.log";

// מעל זה הלוג מתחיל מחדש — הוא יושב על הכונן הנייד ואסור לו לגדול לנצח.
#define LOG_MAX_BYTES (256 * 1024)

// כמה להמתין לסגירת הלאנצ'ר הישן לפני חילוץ מחדש. הוא נסגר מיד אחרי שהוא
// מריץ אותנו; הגבול קיים רק כדי שתקלה לא תשאיר את ה-stub תלוי לנצח.
#define AFTER_UPDATE_WAIT_MS 60000

// NULL כל עוד לא נמצאה תיקייה לכתוב אליה — אז הלוג פשוט לא נכתב.
static wchar_t *g_log_path;

static void FreeString(wchar_t *value) {
  if (value != NULL) {
    HeapFree(GetProcessHeap(), 0, value);
  }
}

// מחרוזת מעוצבת על הערימה, בכל אורך — נתיבים כאן אינם מוגבלים ל-MAX_PATH.
static wchar_t *FormatString(const wchar_t *format, ...) {
  va_list args;
  va_start(args, format);
  const int length = _vscwprintf(format, args);
  va_end(args);
  if (length < 0) {
    return NULL;
  }
  const size_t count = (size_t)length + 1;
  wchar_t *buffer =
      (wchar_t *)HeapAlloc(GetProcessHeap(), 0, count * sizeof(wchar_t));
  if (buffer == NULL) {
    return NULL;
  }
  va_start(args, format);
  const HRESULT result = StringCchVPrintfW(buffer, count, format, args);
  va_end(args);
  if (FAILED(result)) {
    FreeString(buffer);
    return NULL;
  }
  return buffer;
}

// יוצר את `app-files\OtzariaData\logs` וקובע לאן כותבים. נקרא לפני החילוץ:
// הוא דורס מעל התיקיות האלה ואינו מוחק אותן.
static void PrepareLog(const wchar_t *payload_dir) {
  wchar_t *data_dir = FormatString(L"%s\\%s", payload_dir, kDataDirName);
  wchar_t *log_dir =
      FormatString(L"%s\\%s\\%s", payload_dir, kDataDirName, kLogDirName);
  if (data_dir != NULL && log_dir != NULL) {
    CreateDirectoryW(payload_dir, NULL);
    CreateDirectoryW(data_dir, NULL);
    CreateDirectoryW(log_dir, NULL);
    g_log_path = FormatString(L"%s\\%s", log_dir, kLogFileName);
  }
  FreeString(data_dir);
  FreeString(log_dir);
}

// שורת לוג עם חותמת זמן. כשל בכתיבה נבלע: הלוג הוא כלי עזר, ולא סיבה
// להיכשל בהרצה שאחרת הייתה מצליחה.
static void LogLine(const wchar_t *format, ...) {
  if (g_log_path == NULL) {
    return;
  }

  wchar_t message[1024];
  va_list args;
  va_start(args, format);
  const HRESULT formatted =
      StringCchVPrintfW(message, ARRAYSIZE(message), format, args);
  va_end(args);
  // חיתוך הוא בסדר — המאגר עדיין מסתיים ב-NUL; כשל אחר לא.
  if (FAILED(formatted) && formatted != STRSAFE_E_INSUFFICIENT_BUFFER) {
    return;
  }

  SYSTEMTIME now;
  GetLocalTime(&now);
  wchar_t line[1200];
  if (FAILED(StringCchPrintfW(line, ARRAYSIZE(line),
                              L"%04u-%02u-%02u %02u:%02u:%02u  %s\r\n",
                              now.wYear, now.wMonth, now.wDay, now.wHour,
                              now.wMinute, now.wSecond, message))) {
    return;
  }

  // UTF-8 כדי שנתיב עברי ייקרא, ובלי BOM — הקובץ נפתח ב-append.
  char utf8[3600];
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, line, -1, utf8,
                                        (int)sizeof(utf8), NULL, NULL);
  if (bytes <= 1) {
    return;
  }

  HANDLE file = CreateFileW(g_log_path, FILE_APPEND_DATA, FILE_SHARE_READ,
                            NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  LARGE_INTEGER size;
  if (GetFileSizeEx(file, &size) && size.QuadPart > LOG_MAX_BYTES) {
    CloseHandle(file);
    file = CreateFileW(g_log_path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                       CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
      return;
    }
  }
  DWORD written = 0;
  WriteFile(file, utf8, (DWORD)(bytes - 1), &written, NULL);  // בלי ה-NUL
  CloseHandle(file);
}

// הטקסט היחיד בפרויקט שלא עובר דרך otzaria_l10n — קוד C לא יכול לתלות
// בחבילת Dart. מוצג רק כשההכנה להרצה הראשונה נכשלה.
static int ReportFailure(void) {
  LogLine(L"ההכנה להרצה נכשלה — מוצגת תיבת שגיאה");
  MessageBoxW(NULL,
              L"הכנת התוכנה להרצה נכשלה.\n\n"
              L"יש להעתיק את הקובץ לכונן שיש בו מקום פנוי והרשאת כתיבה, "
              L"ולהריץ אותו משם שוב.",
              L"עדכוני אוצריא",
              MB_OK | MB_ICONERROR | MB_RTLREADING | MB_RIGHT);
  return EXIT_FAILURE;
}

// הטקסט השני שאינו ב-otzaria_l10n. Explorer מריץ exe מתוך zip מעותק ב-%TEMP%,
// וכל מה שהלאנצ'ר היה מוריד לשם נמחק עם התיקייה הזמנית.
static int ReportTemporaryLocation(void) {
  MessageBoxW(NULL,
              L"התוכנה הופעלה מתוך קובץ ZIP או מתיקייה זמנית.\n\n"
              L"כל מה שהיא מורידה משם נמחק יחד עם התיקייה הזמנית. "
              L"יש לחלץ את הקובץ לדיסק און קי או לכונן חיצוני "
              L"ולהפעיל אותו משם.",
              L"עדכוני אוצריא",
              MB_OK | MB_ICONWARNING | MB_RTLREADING | MB_RIGHT);
  return EXIT_FAILURE;
}

// הטקסט השלישי שאינו ב-otzaria_l10n; = `setupError.systemDrive`. נבדק לפני
// החילוץ, כדי לא להשאיר ערמת קבצים על כונן המערכת.
static int ReportSystemDrive(void) {
  MessageBoxW(NULL,
              L"התוכנה נושאת את העדכונים ממחשב למחשב, ולכן היא צריכה "
              L"להימצא על דיסק און קי או על כונן חיצוני — לא על הכונן "
              L"הראשי של המחשב.\n\n"
              L"יש להעתיק את כל תיקיית התוכנה (כולל התיקייה app-files) "
              L"לכונן הנייד ולהפעיל אותה משם.",
              L"עדכוני אוצריא",
              MB_OK | MB_ICONWARNING | MB_RTLREADING | MB_RIGHT);
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

// ── חילוץ ─────────────────────────────────────────────────────────────────
//
// הכול קורה **בתוך התהליך הזה**. הגרסה הקודמת כתבה zip ל-%TEMP% והריצה עליו
// את `tar.exe` של Windows, ושתי התלויות האלה הן ששברו חילוץ בשטח:
// `tar.exe` קיים רק מ-Windows 10 1803, והנתיבים הועברו אליו דרך שורת פקודה
// שעוברת המרה ל-ANSI — נתיב עברי על כונן שאין בו שמות 8.3 (exFAT, וכל כונן
// שאינו כונן המערכת) הגיע אליו משובש. כאן אין תהליך חיצוני, אין קובץ זמני,
// והנתיבים נשארים UTF-16 מקצה לקצה.

// ההתקדמות, כפי שחוט החלון קורא אותה בזמן שהחילוץ רץ. יחידה = בית שנכתב,
// ועוד kFileWeight לכל קובץ: על כונן USB פתיחת קובץ עולה כמו כתיבת עשרות KB.
static volatile LONG g_files_done;
static DWORD g_files_total;
static volatile LONG64 g_units_done;
static volatile LONG64 g_units_total;  // 0 כל עוד הגוש עדיין נפרש
#define kFileWeight (32 * 1024)
#define kWriteChunk (1024 * 1024)

// נתיב ארוך מ-MAX_PATH הוא מציאותי כאן (`data\flutter_assets\packages\...`
// בתוך תיקייה של המשתמש), ולכן הכתיבה היא דרך תחילית `\\?\`. היא חוקית רק
// לנתיב מוחלט על אות כונן; ל-UNC ולכל השאר נשארים בלעדיה.
static BOOL UseLongPathPrefix(const wchar_t *root) {
  return root[0] != L'\0' && root[1] == L':';
}

// יוצר את תיקיות האב של הנתיב, החל מ-[from] — כל מה שלפניו הוא תיקיית היעד
// שכבר קיימת. חשוב שיתחיל שם ולא בתחילת המחרוזת: היא פותחת ב-`\\?\C:\...`,
// ו-`CreateDirectoryW` על החלקים האלה נכשל ומפיל את כל השרשרת.
// שגיאת "כבר קיימת" אינה שגיאה — חילוץ שאחרי עדכון עצמי רץ מעל תיקיות
// שכולן כבר שם.
static BOOL EnsureParentDirs(wchar_t *path, size_t from) {
  for (wchar_t *cursor = path + from; *cursor != L'\0'; ++cursor) {
    if (*cursor != L'\\') {
      continue;
    }
    *cursor = L'\0';
    const BOOL created = CreateDirectoryW(path, NULL);
    const DWORD error = GetLastError();
    *cursor = L'\\';
    if (!created && error != ERROR_ALREADY_EXISTS) {
      LogLine(L"יצירת תיקייה נכשלה בשגיאה %lu: %s", error, path);
      return FALSE;
    }
  }
  return TRUE;
}

// הנתיב מגיע מתוך ה-exe שלנו, אבל resource פגום לא יכתוב מחוץ ליעד.
static BOOL IsSafeRelativePath(const wchar_t *relative) {
  if (relative[0] == L'\0' || relative[0] == L'\\') {
    return FALSE;
  }
  if (relative[0] != L'\0' && relative[1] == L':') {
    return FALSE;
  }
  for (const wchar_t *cursor = relative; *cursor != L'\0'; ++cursor) {
    if (cursor[0] != L'.' || cursor[1] != L'.') {
      continue;
    }
    const BOOL at_start = (cursor == relative) || (cursor[-1] == L'\\');
    if (at_start && (cursor[2] == L'\\' || cursor[2] == L'\0')) {
      return FALSE;
    }
  }
  return TRUE;
}

// כותב קובץ אחד מהגוש הפרוש אל היעד.
static BOOL WriteOneFile(const wchar_t *dest_root, const char *path_utf8,
                         DWORD path_bytes, const BYTE *data, DWORD size) {
  wchar_t relative[1024];
  const int length =
      MultiByteToWideChar(CP_UTF8, 0, path_utf8, (int)path_bytes, relative,
                          ARRAYSIZE(relative) - 1);
  if (length <= 0) {
    LogLine(L"שם קובץ שאי אפשר לפענח ב-payload — דילוג");
    return FALSE;
  }
  relative[length] = L'\0';
  for (wchar_t *cursor = relative; *cursor != L'\0'; ++cursor) {
    if (*cursor == L'/') {
      *cursor = L'\\';
    }
  }
  if (!IsSafeRelativePath(relative)) {
    LogLine(L"נתיב חשוד ב-payload: %s — דילוג", relative);
    return FALSE;
  }

  static wchar_t full[4096];
  const wchar_t *prefix = UseLongPathPrefix(dest_root) ? L"\\\\?\\" : L"";
  if (FAILED(StringCchPrintfW(full, ARRAYSIZE(full), L"%s%s%s", prefix,
                              dest_root, SeparatorFor(dest_root)))) {
    LogLine(L"נתיב היעד ארוך מדי");
    return FALSE;
  }
  // כל מה שעד כאן קיים; התיקיות שצריך ליצור הן אלה שבתוך הנתיב היחסי.
  const size_t root_length = wcslen(full);
  if (FAILED(StringCchCatW(full, ARRAYSIZE(full), relative))) {
    LogLine(L"נתיב ארוך מדי: %s", relative);
    return FALSE;
  }

  if (!EnsureParentDirs(full, root_length)) {
    return FALSE;
  }

  HANDLE file = CreateFileW(full, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE && GetLastError() == ERROR_ACCESS_DENIED) {
    // קובץ קיים שסומן לקריאה-בלבד או מוסתר — CREATE_ALWAYS נכשל עליו.
    SetFileAttributesW(full, FILE_ATTRIBUTE_NORMAL);
    file = CreateFileW(full, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                       FILE_ATTRIBUTE_NORMAL, NULL);
  }
  if (file == INVALID_HANDLE_VALUE) {
    LogLine(L"כתיבת %s נכשלה בשגיאה %lu", relative, GetLastError());
    return FALSE;
  }

  BOOL ok = TRUE;
  DWORD offset = 0;
  while (offset < size) {
    // במנות, כדי שקובץ גדול (flutter_windows.dll) לא יקפיץ את הפס בבת אחת.
    const DWORD chunk = min(size - offset, (DWORD)kWriteChunk);
    DWORD written = 0;
    if (!WriteFile(file, data + offset, chunk, &written, NULL) ||
        written == 0) {
      LogLine(L"כתיבת %s נקטעה בשגיאה %lu", relative, GetLastError());
      ok = FALSE;
      break;
    }
    offset += written;
    InterlockedExchangeAdd64(&g_units_done, written);
  }
  CloseHandle(file);
  return ok;
}

// פורש את ה-resource לזיכרון. מחזיר את הגוש ואת גודלו, או NULL.
static BYTE *DecompressPayload(ULONGLONG *out_size, DWORD *out_count) {
  // ה-cast נחוץ כי RT_RCDATA הוא TCHAR, וה-stub לא מקומפל עם UNICODE.
  HRSRC resource = FindResourceW(NULL, MAKEINTRESOURCEW(PAYLOAD_RESOURCE_ID),
                                 (const wchar_t *)RT_RCDATA);
  if (resource == NULL) {
    LogLine(L"אין payload ב-exe (שגיאה %lu)", GetLastError());
    return NULL;
  }
  const DWORD resource_size = SizeofResource(NULL, resource);
  HGLOBAL loaded = LoadResource(NULL, resource);
  const BYTE *bytes = (loaded == NULL) ? NULL : (const BYTE *)LockResource(loaded);
  if (bytes == NULL || resource_size <= sizeof(PayloadHeader)) {
    LogLine(L"ה-payload קטן מדי או לא נטען (%lu בתים)", resource_size);
    return NULL;
  }

  PayloadHeader header;
  memcpy(&header, bytes, sizeof(header));
  if (memcmp(header.magic, kPayloadMagic, sizeof(kPayloadMagic)) != 0) {
    LogLine(L"חתימת ה-payload אינה מוכרת");
    return NULL;
  }
  // האלגוריתם נקרא מהכותרת אך אינו נבחר על ידה: `pack_payload.ps1` כותב
  // LZMS, וכל ערך אחר פירושו קובץ פגום ולא פורמט אחר שצריך לתמוך בו.
  if (header.algorithm != COMPRESS_ALGORITHM_LZMS) {
    LogLine(L"אלגוריתם לא צפוי ב-payload: %lu", header.algorithm);
    return NULL;
  }
  if (header.raw_size == 0 || header.raw_size > (ULONGLONG)1024 * 1024 * 1024) {
    LogLine(L"גודל payload לא סביר: %llu", header.raw_size);
    return NULL;
  }

  DECOMPRESSOR_HANDLE decompressor = NULL;
  if (!CreateDecompressor(header.algorithm, NULL, &decompressor)) {
    LogLine(L"CreateDecompressor(%lu) נכשל בשגיאה %lu", header.algorithm,
            GetLastError());
    return NULL;
  }

  BYTE *raw = (BYTE *)HeapAlloc(GetProcessHeap(), 0, (SIZE_T)header.raw_size);
  if (raw == NULL) {
    LogLine(L"אין זיכרון ל-%llu בתים", header.raw_size);
    CloseDecompressor(decompressor);
    return NULL;
  }

#ifdef STUB_SLOW_DEMO
  Sleep(1500);  // צילום הפס בלי ערך בלבד
#endif
  SIZE_T produced = 0;
  const BOOL ok = Decompress(decompressor, (PVOID)(bytes + sizeof(header)),
                             resource_size - sizeof(header), raw,
                             (SIZE_T)header.raw_size, &produced);
  CloseDecompressor(decompressor);
  if (!ok || produced != (SIZE_T)header.raw_size) {
    LogLine(L"פרישת ה-payload נכשלה (שגיאה %lu, %llu מתוך %llu)",
            GetLastError(), (ULONGLONG)produced, header.raw_size);
    HeapFree(GetProcessHeap(), 0, raw);
    return NULL;
  }

  *out_size = header.raw_size;
  *out_count = header.file_count;
  return raw;
}

// עובר על הגוש הפרוש וכותב את הקבצים. מעבר ראשון מאמת את הטבלה ומוצא היכן
// מתחיל התוכן, והשני כותב — כך נתונים פגומים מתגלים לפני שנגענו בדיסק.
static BOOL WritePayloadFiles(const wchar_t *dest_root, const BYTE *raw,
                              ULONGLONG raw_size, DWORD expected_count) {
  const BYTE *const end = raw + raw_size;
  if (raw_size < sizeof(DWORD)) {
    return FALSE;
  }
  DWORD count = 0;
  memcpy(&count, raw, sizeof(count));
  if (count != expected_count || count == 0) {
    LogLine(L"טבלת ה-payload מכריזה על %lu קבצים והכותרת על %lu", count,
            expected_count);
    return FALSE;
  }

  const BYTE *cursor = raw + sizeof(DWORD);
  ULONGLONG total_data = 0;
  for (DWORD i = 0; i < count; ++i) {
    if ((ULONGLONG)(end - cursor) < 2 * sizeof(DWORD)) {
      return FALSE;
    }
    DWORD path_bytes = 0;
    DWORD data_bytes = 0;
    memcpy(&path_bytes, cursor, sizeof(path_bytes));
    memcpy(&data_bytes, cursor + sizeof(DWORD), sizeof(data_bytes));
    cursor += 2 * sizeof(DWORD);
    if (path_bytes == 0 || (ULONGLONG)(end - cursor) < path_bytes) {
      return FALSE;
    }
    cursor += path_bytes;
    total_data += data_bytes;
  }
  if ((ULONGLONG)(end - cursor) < total_data) {
    LogLine(L"ה-payload קצר מהטבלה שלו");
    return FALSE;
  }

  g_units_total = (LONG64)total_data + (LONG64)count * kFileWeight;

  const BYTE *data = cursor;
  cursor = raw + sizeof(DWORD);
  BOOL all_ok = TRUE;
  for (DWORD i = 0; i < count; ++i) {
    DWORD path_bytes = 0;
    DWORD data_bytes = 0;
    memcpy(&path_bytes, cursor, sizeof(path_bytes));
    memcpy(&data_bytes, cursor + sizeof(DWORD), sizeof(data_bytes));
    cursor += 2 * sizeof(DWORD);
    if (!WriteOneFile(dest_root, (const char *)cursor, path_bytes, data,
                      data_bytes)) {
      all_ok = FALSE;
    }
    cursor += path_bytes;
    data += data_bytes;
    InterlockedIncrement(&g_files_done);
    InterlockedExchangeAdd64(&g_units_done, kFileWeight);
#ifdef STUB_SLOW_DEMO
    Sleep(STUB_SLOW_DEMO);  // צילום החלון בלבד; הבנייה הרגילה אינה מגדירה אותו
#endif
  }
  return all_ok;
}

// מה שחולץ בפועל, כפי שנרשם במרקר: הגרסה, ובבניית בדיקה גם מזהה הקומיט —
// אחרת בנייה חדשה באותה גרסה לא חולצה ורץ הקוד הישן. ASCII בכוונה.
static BOOL MarkerMatchesPayload(const wchar_t *marker) {
  HANDLE file = CreateFileW(marker, GENERIC_READ, FILE_SHARE_READ, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    LogLine(L"אין מרקר — חילוץ ראשון");
    return FALSE;
  }
  char buffer[64];
  DWORD read = 0;
  const BOOL ok =
      ReadFile(file, buffer, (DWORD)(sizeof(buffer) - 1), &read, NULL);
  CloseHandle(file);
  if (!ok) {
    LogLine(L"קריאת המרקר נכשלה בשגיאה %lu", GetLastError());
    return FALSE;
  }
  buffer[read] = '\0';
  if (strcmp(buffer, PAYLOAD_MARKER_A) != 0) {
    LogLine(L"המרקר מחזיק '%hs' וה-payload הוא '%hs' — חילוץ מחדש", buffer,
            PAYLOAD_MARKER_A);
    return FALSE;
  }
  return TRUE;
}

// FILE_ATTRIBUTE_HIDDEN חייב להישאר גם כאן: CREATE_ALWAYS על קובץ מוסתר
// קיים נכשל ב-ACCESS_DENIED אם התכונה לא צוינה מחדש.
static BOOL WriteMarker(const wchar_t *marker) {
  HANDLE file = CreateFileW(marker, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    return FALSE;
  }
  const DWORD length = (DWORD)strlen(PAYLOAD_MARKER_A);
  DWORD written = 0;
  const BOOL ok =
      WriteFile(file, PAYLOAD_MARKER_A, length, &written, NULL) &&
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

// ממתין לסגירת הלאנצ'ר הישן. בלי זה החילוץ היה מנסה לדרוס את
// launcher_app.exe ואת flutter_windows.dll בזמן שהם עוד נעולים על ידו.
static void WaitForProcessExit(DWORD process_id) {
  if (process_id == 0) {
    return;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, process_id);
  if (process == NULL) {
    return;  // כבר יצא (או שאין הרשאה) — ממשיכים.
  }
  const DWORD waited = WaitForSingleObject(process, AFTER_UPDATE_WAIT_MS);
  CloseHandle(process);
  if (waited == WAIT_TIMEOUT) {
    // החילוץ שאחרי זה ייכשל על קבצים נעולים — שיהיה כתוב למה.
    LogLine(L"הלאנצ'ר הקודם (pid %lu) לא נסגר בזמן", process_id);
  }
}

// מחלץ הכול ליעד וכותב את המרקר. אין קובץ זמני ואין תהליך חיצוני: ה-payload
// נפרש מהזיכרון של ה-exe ישירות אל הדיסק.
static BOOL ExtractPayload(const wchar_t *dest_dir, const wchar_t *marker,
                           const wchar_t *target) {
  ULONGLONG raw_size = 0;
  DWORD count = 0;
  BYTE *raw = DecompressPayload(&raw_size, &count);
  if (raw == NULL) {
    return FALSE;
  }
  g_files_total = count;
  LogLine(L"מחלץ %lu קבצים אל %s", count, dest_dir);

  const BOOL wrote = WritePayloadFiles(dest_dir, raw, raw_size, count);
  HeapFree(GetProcessHeap(), 0, raw);
  if (!wrote) {
    return FALSE;
  }

  // המרקר נכתב רק כשהלאנצ'ר באמת שם: חילוץ שכתב 1999 קבצים מתוך 2000 אינו
  // "מוכן", וזה בדיוק המצב שהמרקר לא אמור להכריז עליו כתקין.
  if (GetFileAttributesW(target) == INVALID_FILE_ATTRIBUTES) {
    LogLine(L"החילוץ הסתיים אבל אין %s", target);
    return FALSE;
  }
  if (!WriteMarker(marker)) {
    LogLine(L"כתיבת המרקר נכשלה בשגיאה %lu — יחולץ שוב בהרצה הבאה",
            GetLastError());
    return FALSE;
  }
  return TRUE;
}

// ── חלון ההמתנה ───────────────────────────────────────────────────────────
//
// בלי סימן חיים, חילוץ של שניות לכונן USB נראה תקוע. בנוי כמו מסך ההורדה
// של הלאנצ'ר, ומצויר ביד אל מאגר אחד — בלי comctl32, GDI+ או ערכת נושא.

// `AppPalette.light` וה-ColorScheme שנגזר מ-`AppThemeData.seed`. אין קישור
// בזמן קומפילציה ל-Dart: צבע שמשתנה שם משתנה גם כאן ידנית.
static const COLORREF kPageColor = RGB(0xF6, 0xED, 0xE5);
static const COLORREF kBorderColor = RGB(0xE1, 0xD4, 0xC8);
static const COLORREF kPrimaryColor = RGB(0x80, 0x56, 0x10);
static const COLORREF kTrackColor = RGB(0xFB, 0xDE, 0xBC);
static const COLORREF kOnSurfaceColor = RGB(0x20, 0x1B, 0x13);
static const COLORREF kOnSurfaceVariantColor = RGB(0x4F, 0x45, 0x39);

static const wchar_t kProgressClass[] = L"OtzariaStubProgress";
static const wchar_t kWindowTitle[] = L"עדכוני אוצריא";
static const wchar_t kProgressTitle[] = L"מכין את התוכנה להרצה";
static const wchar_t kProgressSubtitle[] = L"התוכנה תיפתח מיד בסיום.";
static const wchar_t kUnpackingText[] = L"פורש את הקבצים…";
static const wchar_t kWritingFormat[] = L"מעתיק קבצים · %lu מתוך %lu";

// מידות ב-DIP, כמו בפלאטר; S() ממיר לפיקסלים לפי ה-DPI של החלון.
#define UI_WIDTH 440
#define UI_HEIGHT 276
#define UI_LOGO 48
#define UI_BAR_INSET 40
#define UI_BAR_HEIGHT 8
#define UI_TIMER_MS 16
#define UI_SWEEP_MS 1800

typedef struct {
  UINT dpi;
  HFONT title_font;
  HFONT body_font;
  HFONT status_font;
  HFONT percent_font;
  HICON logo;
  HDC buffer_dc;
  HBITMAP buffer;
  HGDIOBJ buffer_old;
  DWORD *pixels;
  int width;
  int height;
  double shown;  // השבר שמוצג, מתקרב בהדרגה לשבר האמיתי
  DWORD started;
} ProgressUi;

static ProgressUi g_ui;

static int S(int dips) { return MulDiv(dips, (int)g_ui.dpi, 96); }

// GetDpiForWindow קיים רק מ-Windows 10 1607; לפניו המניפסט נותן "system aware".
static UINT DpiOf(HWND window) {
  typedef UINT(WINAPI * GetDpiForWindowFn)(HWND);
  const GetDpiForWindowFn get_dpi = (GetDpiForWindowFn)(void *)GetProcAddress(
      GetModuleHandleW(L"user32.dll"), "GetDpiForWindow");
  if (get_dpi != NULL && window != NULL) {
    const UINT dpi = get_dpi(window);
    if (dpi != 0) {
      return dpi;
    }
  }
  HDC screen = GetDC(NULL);
  const int dpi = screen == NULL ? 96 : GetDeviceCaps(screen, LOGPIXELSY);
  if (screen != NULL) {
    ReleaseDC(NULL, screen);
  }
  return dpi > 0 ? (UINT)dpi : 96;
}

static HFONT MakeFont(int dips, int weight) {
  return CreateFontW(-S(dips), 0, 0, 0, weight, FALSE, FALSE, FALSE,
                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}

static void DeleteIfSet(HGDIOBJ object) {
  if (object != NULL) {
    DeleteObject(object);
  }
}

static void ReleaseUiResources(void) {
  DeleteIfSet(g_ui.title_font);
  DeleteIfSet(g_ui.body_font);
  DeleteIfSet(g_ui.status_font);
  DeleteIfSet(g_ui.percent_font);
  if (g_ui.logo != NULL) {
    DestroyIcon(g_ui.logo);
  }
  if (g_ui.buffer_dc != NULL) {
    SelectObject(g_ui.buffer_dc, g_ui.buffer_old);
    DeleteIfSet(g_ui.buffer);
    DeleteDC(g_ui.buffer_dc);
  }
  g_ui.title_font = g_ui.body_font = NULL;
  g_ui.status_font = g_ui.percent_font = NULL;
  g_ui.logo = NULL;
  g_ui.buffer_dc = NULL;
  g_ui.buffer = NULL;
  g_ui.pixels = NULL;
}

// נבנה מחדש בכל שינוי DPI — גם האייקון, כדי שייטען מהגודל המתאים ב-ico.
static void CreateUiResources(UINT dpi) {
  ReleaseUiResources();
  g_ui.dpi = dpi;
  g_ui.title_font = MakeFont(20, FW_SEMIBOLD);
  g_ui.body_font = MakeFont(14, FW_NORMAL);
  g_ui.status_font = MakeFont(13, FW_NORMAL);
  g_ui.percent_font = MakeFont(32, FW_SEMIBOLD);
  g_ui.logo = (HICON)LoadImageW(GetModuleHandleW(NULL), MAKEINTRESOURCEW(1),
                                IMAGE_ICON, S(UI_LOGO), S(UI_LOGO),
                                LR_DEFAULTCOLOR);
}

// מאגר DIB בגודל החלון: הטקסט נכתב אליו ב-GDI, והפס מצויר ישירות בפיקסלים.
static BOOL EnsureBuffer(HDC target, int width, int height) {
  if (g_ui.buffer_dc != NULL && g_ui.width == width && g_ui.height == height) {
    return TRUE;
  }
  if (g_ui.buffer_dc != NULL) {
    SelectObject(g_ui.buffer_dc, g_ui.buffer_old);
    DeleteIfSet(g_ui.buffer);
    DeleteDC(g_ui.buffer_dc);
    g_ui.buffer_dc = NULL;
  }
  BITMAPINFO info;
  ZeroMemory(&info, sizeof(info));
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;  // מלמעלה למטה
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void *bits = NULL;
  g_ui.buffer = CreateDIBSection(target, &info, DIB_RGB_COLORS, &bits, NULL, 0);
  if (g_ui.buffer == NULL) {
    return FALSE;
  }
  g_ui.buffer_dc = CreateCompatibleDC(target);
  if (g_ui.buffer_dc == NULL) {
    DeleteObject(g_ui.buffer);
    g_ui.buffer = NULL;
    return FALSE;
  }
  g_ui.buffer_old = SelectObject(g_ui.buffer_dc, g_ui.buffer);
  g_ui.pixels = (DWORD *)bits;
  g_ui.width = width;
  g_ui.height = height;
  return TRUE;
}

// האם נקודה בתוך גלולה אופקית [left, right] סביב center_y.
static BOOL InPill(double x, double y, double left, double right,
                   double center_y, double radius) {
  if (right - left < 2 * radius) {
    return FALSE;
  }
  double dx = 0;
  if (x < left + radius) {
    dx = left + radius - x;
  } else if (x > right - radius) {
    dx = x - (right - radius);
  }
  const double dy = y - center_y;
  return dx * dx + dy * dy <= radius * radius;
}

static DWORD BlendPixel(int track, int fill, int samples) {
  const COLORREF colors[3] = {kPageColor, kTrackColor, kPrimaryColor};
  const int weights[3] = {samples - track, track - fill, fill};
  int r = 0, g = 0, b = 0;
  for (int i = 0; i < 3; ++i) {
    r += GetRValue(colors[i]) * weights[i];
    g += GetGValue(colors[i]) * weights[i];
    b += GetBValue(colors[i]) * weights[i];
  }
  return ((DWORD)(r / samples) << 16) | ((DWORD)(g / samples) << 8) |
         (DWORD)(b / samples);
}

// `AppProgressBar`; fraction < 0 הוא פס בלי ערך — מקטע של 30% שנע בכיוון
// הקריאה. GDI אינו מחליק קצוות, ולכן כל פיקסל נדגם 4x4.
static void PaintBar(RECT bar, double fraction, double sweep) {
  const double left = bar.left, right = bar.right;
  const double width = right - left;
  const double radius = (bar.bottom - bar.top) / 2.0;
  const double center_y = bar.top + radius;
  double fill_left = right, fill_right = right;
  if (fraction >= 0) {
    // מימין לשמאל, כמו בממשק העברי; לפחות גלולה עגולה אחת, כמו בפלאטר.
    double fill_width = width * min(fraction, 1.0);
    fill_width = max(fill_width, 2 * radius);
    fill_left = right - fill_width;
  } else {
    const double segment = width * 0.3;
    const double travel = (width + segment) * sweep;
    fill_right = right - (travel - segment);
    fill_left = fill_right - segment;
  }
  const int sub = 4;
  for (int y = bar.top; y < bar.bottom; ++y) {
    if (y < 0 || y >= g_ui.height) {
      continue;
    }
    for (int x = bar.left - 1; x <= bar.right; ++x) {
      if (x < 0 || x >= g_ui.width) {
        continue;
      }
      int track = 0, fill = 0;
      for (int j = 0; j < sub; ++j) {
        for (int i = 0; i < sub; ++i) {
          const double sx = x + (i + 0.5) / sub;
          const double sy = y + (j + 0.5) / sub;
          if (!InPill(sx, sy, left, right, center_y, radius)) {
            continue;
          }
          ++track;
          // רק דגימות שבתוך המסילה נספרות — המקטע נחתך בקצותיה, כמו ClipRRect.
          if (InPill(sx, sy, fill_left, fill_right, center_y, radius)) {
            ++fill;
          }
        }
      }
      if (track > 0) {
        g_ui.pixels[y * g_ui.width + x] = BlendPixel(track, fill, sub * sub);
      }
    }
  }
}

static void DrawLine(const wchar_t *text, HFONT font, COLORREF color, int top,
                     int height, BOOL rtl) {
  RECT rect = {S(24), S(top), g_ui.width - S(24), S(top + height)};
  SelectObject(g_ui.buffer_dc, font);
  SetTextColor(g_ui.buffer_dc, color);
  DrawTextW(g_ui.buffer_dc, text, -1, &rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
                DT_END_ELLIPSIS | (rtl ? DT_RTLREADING : 0));
}

static double CurrentFraction(void) {
  const LONG64 total = g_units_total;
  if (total <= 0) {
    return -1;
  }
  const double fraction = (double)g_units_done / (double)total;
  return fraction > 1 ? 1 : fraction;
}

static void PaintProgress(HWND window, HDC target) {
  RECT client;
  GetClientRect(window, &client);
  if (!EnsureBuffer(target, client.right, client.bottom)) {
    return;
  }
  HDC dc = g_ui.buffer_dc;

  HBRUSH page = CreateSolidBrush(kPageColor);
  FillRect(dc, &client, page);
  DeleteObject(page);
  HBRUSH border = CreateSolidBrush(kBorderColor);
  FrameRect(dc, &client, border);
  DeleteObject(border);

  if (g_ui.logo != NULL) {
    DrawIconEx(dc, (g_ui.width - S(UI_LOGO)) / 2, S(28), g_ui.logo, S(UI_LOGO),
               S(UI_LOGO), 0, NULL, DI_NORMAL);
  }

  SetBkMode(dc, TRANSPARENT);
  HGDIOBJ previous_font = SelectObject(dc, g_ui.title_font);
  DrawLine(kProgressTitle, g_ui.title_font, kOnSurfaceColor, 88, 28, TRUE);
  DrawLine(kProgressSubtitle, g_ui.body_font, kOnSurfaceVariantColor, 120, 20,
           TRUE);

  const double fraction = CurrentFraction();
  if (fraction >= 0) {  // בזמן הפרישה אין ערך, ו-"0%" ליד פס שנע סותר אותו
    wchar_t percent[16];
    StringCchPrintfW(percent, ARRAYSIZE(percent), L"%d%%",
                     (int)(g_ui.shown * 100));
    DrawLine(percent, g_ui.percent_font, kPrimaryColor, 154, 42, FALSE);
  }

  wchar_t status[96];
  if (fraction < 0) {
    StringCchCopyW(status, ARRAYSIZE(status), kUnpackingText);
  } else {
    StringCchPrintfW(status, ARRAYSIZE(status), kWritingFormat,
                     (unsigned long)g_files_done, (unsigned long)g_files_total);
  }
  DrawLine(status, g_ui.status_font, kOnSurfaceVariantColor, 226, 20, TRUE);
  SelectObject(dc, previous_font);

  GdiFlush();  // לפני נגיעה ישירה בפיקסלים
  RECT bar = {S(UI_BAR_INSET), S(206), g_ui.width - S(UI_BAR_INSET),
              S(206) + S(UI_BAR_HEIGHT)};
  const DWORD elapsed = GetTickCount() - g_ui.started;
  PaintBar(bar, fraction < 0 ? -1 : g_ui.shown,
           (double)(elapsed % UI_SWEEP_MS) / UI_SWEEP_MS);

  BitBlt(target, 0, 0, g_ui.width, g_ui.height, dc, 0, 0, SRCCOPY);
}

static LRESULT CALLBACK ProgressWindowProc(HWND window, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT paint;
      HDC dc = BeginPaint(window, &paint);
      PaintProgress(window, dc);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;  // הכול נצבע ב-WM_PAINT; מחיקה לפניו היא ההבהוב
    case WM_TIMER: {
      const double fraction = CurrentFraction();
      // מתקרב לערך האמיתי ולא קופץ אליו — אחרת מנות של 1MB נראות כמו מדרגות.
      g_ui.shown =
          fraction < 0 ? 0 : g_ui.shown + (fraction - g_ui.shown) * 0.2;
      InvalidateRect(window, NULL, FALSE);
      return 0;
    }
    case WM_NCHITTEST:
      return HTCAPTION;  // אין שורת כותרת, ולכן גוררים מכל מקום
    case WM_DPICHANGED: {
      CreateUiResources(HIWORD(wparam));
      const RECT *suggested = (const RECT *)lparam;
      SetWindowPos(window, NULL, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      InvalidateRect(window, NULL, FALSE);
      return 0;
    }
    // אין WM_CLOSE: סגירה באמצע חילוץ היא בדיוק מה שמשאיר ערמת קבצים חלקית.
    case WM_CLOSE:
      return 0;
    default:
      return DefWindowProcW(window, message, wparam, lparam);
  }
}

// ממורכז באזור העבודה של המסך שבו העכבר — שם המשתמש לחץ על הקובץ.
static void PlaceWindow(HWND window) {
  POINT cursor = {0, 0};
  GetCursorPos(&cursor);
  RECT work;
  MONITORINFO monitor;
  monitor.cbSize = sizeof(monitor);
  if (GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY),
                      &monitor)) {
    work = monitor.rcWork;
  } else {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  }
  const int width = S(UI_WIDTH);
  const int height = S(UI_HEIGHT);
  SetWindowPos(window, NULL, work.left + (work.right - work.left - width) / 2,
               work.top + (work.bottom - work.top - height) / 2, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

// פינות מעוגלות ב-Windows 11; לפניו המאפיין אינו מוכר והקריאה נכשלת.
// dwmapi נטען מ-System32 בלבד: ייבוא סטטי היה מחפש אותו גם ליד ה-exe.
static BOOL RequestRoundCorners(HWND window) {
  typedef HRESULT(WINAPI * DwmSetWindowAttributeFn)(HWND, DWORD, LPCVOID,
                                                    DWORD);
  HMODULE dwm = LoadLibraryExW(L"dwmapi.dll", NULL,
                               LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (dwm == NULL) {
    return FALSE;
  }
  const DwmSetWindowAttributeFn set_attribute =
      (DwmSetWindowAttributeFn)(void *)GetProcAddress(dwm,
                                                      "DwmSetWindowAttribute");
  const DWORD corner_preference = 33;  // DWMWA_WINDOW_CORNER_PREFERENCE
  const DWORD round = 2;               // DWMWCP_ROUND
  const BOOL ok =
      set_attribute != NULL &&
      SUCCEEDED(set_attribute(window, corner_preference, &round,
                              sizeof(round)));
  FreeLibrary(dwm);
  return ok;
}

static HWND CreateProgressWindow(HINSTANCE instance) {
  WNDCLASSEXW window_class;
  ZeroMemory(&window_class, sizeof(window_class));
  window_class.cbSize = sizeof(window_class);
  window_class.style = CS_DROPSHADOW;
  window_class.lpfnWndProc = ProgressWindowProc;
  window_class.hInstance = instance;
  // ה-cast כמו אצל RT_RCDATA: IDC_ARROW הוא TCHAR, וה-stub אינו UNICODE.
  window_class.hCursor = LoadCursorW(NULL, (const wchar_t *)IDC_ARROW);
  window_class.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));
  window_class.lpszClassName = kProgressClass;
  if (RegisterClassExW(&window_class) == 0) {
    return NULL;
  }

  ZeroMemory(&g_ui, sizeof(g_ui));
  g_ui.started = GetTickCount();
  CreateUiResources(DpiOf(NULL));
  HWND window = CreateWindowExW(0, kProgressClass, kWindowTitle, WS_POPUP, 0,
                                0, S(UI_WIDTH), S(UI_HEIGHT), NULL, NULL,
                                instance, NULL);
  if (window == NULL) {
    ReleaseUiResources();
    return NULL;
  }
  const UINT dpi = DpiOf(window);
  if (dpi != g_ui.dpi) {
    CreateUiResources(dpi);
  }
  // מעבר למסך ב-DPI אחר משנה את הגודל דרך WM_DPICHANGED; השני ממרכז מחדש.
  PlaceWindow(window);
  PlaceWindow(window);
  if (RequestRoundCorners(window)) {
    // DWM מצייר צל משלו לחלון מעוגל; הצל של המחלקה מלבני ויוצא כפול.
    SetClassLongPtrW(window, GCL_STYLE,
                     GetClassLongPtrW(window, GCL_STYLE) & ~CS_DROPSHADOW);
  }
  SetTimer(window, 1, UI_TIMER_MS, NULL);
  ShowWindow(window, SW_SHOWNORMAL);
  UpdateWindow(window);
  return window;
}

typedef struct {
  const wchar_t *dest_dir;
  const wchar_t *marker;
  const wchar_t *target;
  BOOL ok;
} ExtractJob;

static DWORD WINAPI ExtractThread(LPVOID parameter) {
  ExtractJob *job = (ExtractJob *)parameter;
  job->ok = ExtractPayload(job->dest_dir, job->marker, job->target);
  return 0;
}

// מחלץ בחוט נפרד ומזרים הודעות בחוט הזה — בלי לולאת ההודעות החלון היה נצבע
// לבן ומסומן כ"אינו מגיב" תוך שניות.
static BOOL ExtractWithProgress(HINSTANCE instance, const wchar_t *dest_dir,
                                const wchar_t *marker, const wchar_t *target) {
  ExtractJob job;
  job.dest_dir = dest_dir;
  job.marker = marker;
  job.target = target;
  job.ok = FALSE;

  HWND window = CreateProgressWindow(instance);
  HANDLE thread = CreateThread(NULL, 0, ExtractThread, &job, 0, NULL);
  if (thread == NULL) {
    // בלי חוט אין לולאת הודעות, אבל יש חילוץ — זה מה שחשוב.
    job.ok = ExtractPayload(dest_dir, marker, target);
  } else {
    for (;;) {
      const DWORD waited =
          MsgWaitForMultipleObjects(1, &thread, FALSE, INFINITE, QS_ALLINPUT);
      if (waited == WAIT_OBJECT_0 || waited == WAIT_FAILED) {
        break;
      }
      MSG message;
      while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
    CloseHandle(thread);
  }

  if (window != NULL) {
    KillTimer(window, 1);
    if (job.ok) {
      // רגע של 100% לפני הסגירה, כדי שהסיום ייראה כסיום ולא כקטיעה.
      g_ui.shown = 1;
      InvalidateRect(window, NULL, FALSE);
      UpdateWindow(window);
      Sleep(150);
    }
    DestroyWindow(window);
    ReleaseUiResources();
  }
  return job.ok;
}

// הנתיב של ה-exe הזה בכל אורך: מאגר קבוע של MAX_PATH נכשל בתיקייה עמוקה.
static wchar_t *GetOwnPath(void) {
  for (DWORD capacity = MAX_PATH; capacity <= 32768; capacity *= 2) {
    wchar_t *buffer = (wchar_t *)HeapAlloc(GetProcessHeap(), 0,
                                           capacity * sizeof(wchar_t));
    if (buffer == NULL) {
      return NULL;
    }
    const DWORD length = GetModuleFileNameW(NULL, buffer, capacity);
    if (length > 0 && length < capacity) {
      return buffer;
    }
    FreeString(buffer);
    if (length == 0) {
      return NULL;
    }
  }
  return NULL;
}

// GetTempPathW מחזיר לעתים שם 8.3 (ADMINI~1), ולכן משווים גם בצורה הארוכה.
static wchar_t *LongPathOf(const wchar_t *path) {
  const DWORD needed = GetLongPathNameW(path, NULL, 0);
  if (needed > 0) {
    wchar_t *buffer =
        (wchar_t *)HeapAlloc(GetProcessHeap(), 0, needed * sizeof(wchar_t));
    if (buffer != NULL) {
      const DWORD written = GetLongPathNameW(path, buffer, needed);
      if (written > 0 && written < needed) {
        return buffer;
      }
      FreeString(buffer);
    }
  }
  return FormatString(L"%s", path);
}

static BOOL IsInsideFolder(const wchar_t *path, const wchar_t *folder) {
  size_t length = wcslen(folder);
  while (length > 0 && folder[length - 1] == L'\\') {
    --length;
  }
  if (length == 0 || wcslen(path) < length ||
      CompareStringOrdinal(path, (int)length, folder, (int)length, TRUE) !=
          CSTR_EQUAL) {
    return FALSE;
  }
  return path[length] == L'\0' || path[length] == L'\\';
}

// = `AppPaths.isTemporaryLocation`.
// Explorer מריץ exe מתוך zip מעותק תחת %TEMP%; temp שהוא שורש כונן אינו נחשב.
static BOOL IsTemporaryLocation(const wchar_t *dir) {
  wchar_t temp[MAX_PATH + 1];
  const DWORD length = GetTempPathW(ARRAYSIZE(temp), temp);
  if (length == 0 || length >= ARRAYSIZE(temp) || length <= 3) {
    return FALSE;
  }
  wchar_t *long_temp = LongPathOf(temp);
  wchar_t *long_dir = LongPathOf(dir);
  const BOOL inside = IsInsideFolder(dir, temp) ||
                      (long_temp != NULL && long_dir != NULL &&
                       IsInsideFolder(long_dir, long_temp));
  FreeString(long_temp);
  FreeString(long_dir);
  return inside;
}

// = `AppPaths.isOnSystemDrive`. נתיב רשת (גם \\?\UNC\) אינו אות כונן — מותר.
static BOOL IsOnSystemDrive(const wchar_t *dir) {
  if (wcsncmp(dir, L"\\\\?\\", 4) == 0) {
    dir += 4;
  }
  wchar_t system[MAX_PATH + 1];
  const DWORD length =
      GetEnvironmentVariableW(L"SystemDrive", system, ARRAYSIZE(system));
  if (length < 2 || length >= ARRAYSIZE(system) || system[1] != L':' ||
      dir[0] == L'\0' || dir[1] != L':') {
    return FALSE;
  }
  return CompareStringOrdinal(dir, 1, system, 1, TRUE) == CSTR_EQUAL;
}

static BOOL FileExists(const wchar_t *path) {
  return path != NULL && GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES;
}

// שם ה-exe שההחלפה כיוונה אליו, מתוך קובץ ה-target (UTF-8), או NULL.
static wchar_t *ReadReplaceTarget(const wchar_t *stub_dir) {
  wchar_t *path = FormatString(L"%s%s%s", stub_dir, SeparatorFor(stub_dir),
                               kTargetFileName);
  if (path == NULL) {
    return NULL;
  }
  HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  FreeString(path);
  if (file == INVALID_HANDLE_VALUE) {
    return NULL;
  }
  char utf8[1024];
  DWORD read = 0;
  const BOOL ok = ReadFile(file, utf8, sizeof(utf8) - 1, &read, NULL);
  CloseHandle(file);
  if (!ok || read == 0) {
    return NULL;
  }
  wchar_t name[MAX_PATH];
  const int length =
      MultiByteToWideChar(CP_UTF8, 0, utf8, (int)read, name, MAX_PATH - 1);
  if (length <= 0) {
    return NULL;
  }
  name[length] = L'\0';
  if (wcschr(name, L'\\') != NULL || wcschr(name, L'/') != NULL ||
      wcschr(name, L':') != NULL || _wcsicmp(name, kStagedExeName) == 0 ||
      _wcsicmp(name, kPreviousExeName) == 0) {
    return NULL;
  }
  return FormatString(L"%s%s%s", stub_dir, SeparatorFor(stub_dir), name);
}

// עדכון עצמי שנקטע בין שני ה-rename של `LauncherSelfInstaller` משאיר רק את
// הקבצים הזמניים; מי מהם שיופעל מחזיר את הגרסה הקודמת לשם שנרשם ב-target.
// מחזיר נתיב להריץ במקומנו, או NULL כשממשיכים כרגיל.
static wchar_t *RecoverInterruptedUpdate(const wchar_t *stub_dir,
                                         wchar_t **stub_path) {
  const wchar_t *name = wcsrchr(*stub_path, L'\\');
  name = name == NULL ? *stub_path : name + 1;
  const BOOL is_staged = _wcsicmp(name, kStagedExeName) == 0;
  const BOOL is_previous = _wcsicmp(name, kPreviousExeName) == 0;
  if (!is_staged && !is_previous) {
    return NULL;
  }
  wchar_t *target = ReadReplaceTarget(stub_dir);
  if (target == NULL || FileExists(target)) {
    FreeString(target);
    return NULL;
  }
  wchar_t *previous = FormatString(L"%s%s%s", stub_dir, SeparatorFor(stub_dir),
                                   kPreviousExeName);
  wchar_t *relaunch = NULL;
  const BOOL from_previous = FileExists(previous);
  const wchar_t *source = from_previous ? previous : *stub_path;
  if (MoveFileExW(source, target, 0)) {
    LogLine(L"עדכון עצמי שנקטע: %s שוחזר אל %s", source, target);
    if (is_previous || !from_previous) {
      FreeString(*stub_path);
      *stub_path = target;
    } else {
      relaunch = target;
    }
    target = NULL;
  } else {
    LogLine(L"שחזור %s נכשל בשגיאה %lu", source, GetLastError());
  }
  FreeString(target);
  FreeString(previous);
  return relaunch;
}

// CreateProcessW כותב לתוך שורת הפקודה, ולכן היא מועתקת למאגר משלה.
static BOOL StartProcess(const wchar_t *exe, const wchar_t *forwarded,
                         const wchar_t *work_dir) {
  wchar_t *arguments = FormatString(L"\"%s\" %s", exe, forwarded);
  if (arguments == NULL) {
    return FALSE;
  }
  STARTUPINFOW startup;
  ZeroMemory(&startup, sizeof(startup));
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process;
  ZeroMemory(&process, sizeof(process));
  const BOOL started = CreateProcessW(exe, arguments, NULL, NULL, FALSE, 0,
                                      NULL, work_dir, &startup, &process);
  if (started) {
    // לא ממתינים: ה-stub מסיים מיד ומשאיר את הלאנצ'ר לבד בשורת המשימות.
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  } else {
    LogLine(L"הרצת %s נכשלה בשגיאה %lu", exe, GetLastError());
  }
  FreeString(arguments);
  return started;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  UNREFERENCED_PARAMETER(prev);
  UNREFERENCED_PARAMETER(show_command);

  wchar_t *stub_path = GetOwnPath();
  wchar_t *stub_dir = stub_path == NULL ? NULL : FormatString(L"%s", stub_path);
  if (stub_dir == NULL) {
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

  if (IsTemporaryLocation(stub_dir)) {
    return ReportTemporaryLocation();
  }
  if (IsOnSystemDrive(stub_dir)) {
    return ReportSystemDrive();
  }

  wchar_t *work_dir =
      FormatString(L"%s%s%s", stub_dir, SeparatorFor(stub_dir), kPayloadDir);
  wchar_t *target =
      work_dir == NULL ? NULL : FormatString(L"%s\\%s", work_dir, kTargetExe);
  wchar_t *marker =
      work_dir == NULL ? NULL : FormatString(L"%s\\%s", work_dir, kReadyMarker);
  if (target == NULL || marker == NULL) {
    return ReportFailure();
  }

  PrepareLog(work_dir);

  // lpCmdLine של wWinMain הוא כבר בלי argv[0]. מועתק כדי שנוכל להסיר ממנו
  // את הדגל הפנימי שלנו בלי לגעת במאגר של ה-CRT.
  static wchar_t forwarded[32768];
  if (FAILED(StringCchCopyW(forwarded, ARRAYSIZE(forwarded), command_line))) {
    return ReportFailure();
  }
  const DWORD after_update_pid = TakeAfterUpdatePid(forwarded);

  wchar_t *recovered = RecoverInterruptedUpdate(stub_dir, &stub_path);
  if (recovered != NULL) {
    return StartProcess(recovered, command_line, stub_dir) ? EXIT_SUCCESS
                                                           : ReportFailure();
  }
  // הלאנצ'ר צריך את הנתיב שלנו כדי לדעת איזה קובץ להחליף בעדכון הבא, ואת
  // גרסת ה-payload כדי לדעת אם מה שהוא מריץ הוא בכלל מה שאנחנו נושאים;
  // התהליך הבן יורש את הסביבה שלנו, ולכן די בהצבה כאן.
  SetEnvironmentVariableW(kStubPathEnvVar, stub_path);
  SetEnvironmentVariableW(kPayloadVersionEnvVar, PAYLOAD_VERSION_W);

  LogLine(L"--- stub %hs --- %s", PAYLOAD_VERSION_A, stub_path);
  if (after_update_pid != 0) {
    LogLine(L"הרצה אחרי עדכון עצמי, ממתין ל-pid %lu", after_update_pid);
  }

  // חילוץ בהרצה הראשונה, וגם כשגרסת ה-payload שונה מזו שבמרקר — כלומר אחרי
  // שהעדכון העצמי החליף את ה-exe הזה. גם משחזר ערמת קבצים שנמחקה: ה-payload
  // נשאר מוטמע ב-exe לתמיד.
  if (!MarkerMatchesPayload(marker)) {
    WaitForProcessExit(after_update_pid);
    // חילוץ שנכשל כשכבר יש לאנצ'ר על הדיסק אינו סוף הדרך: מריצים את מה שיש,
    // והמרקר (שלא נכתב) יגרום לניסיון נוסף בהרצה הבאה. תיבת שגיאה נשמרת
    // למצב שבו אין מה להריץ בכלל.
    if (!ExtractWithProgress(instance, stub_dir, marker, target)) {
      if (GetFileAttributesW(target) == INVALID_FILE_ATTRIBUTES) {
        return ReportFailure();
      }
      // מה שרץ עכשיו אינו ה-payload שלנו. הלאנצ'ר יזהה זאת בעצמו דרך
      // `OTZARIA_PAYLOAD_VERSION` ויעצור, במקום להריץ ערמת קבצים מעורבת.
      LogLine(L"החילוץ נכשל — מורץ מה שכבר יש ב-%s", work_dir);
    } else {
      LogLine(L"החילוץ הושלם, המרקר נכתב");
    }
  }

  // ה-cwd של הבן הוא app-files, שם הוא מצפה למצוא את ה-DLL וה-data.
  if (!StartProcess(target, forwarded, work_dir)) {
    return ReportFailure();
  }
  return EXIT_SUCCESS;
}
