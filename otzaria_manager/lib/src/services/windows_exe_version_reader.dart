import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'installed_version_reader.dart';

/// קורא את שדה ה-ProductVersion המוטבע ב-Windows version resource של קובץ
/// exe נתון, דרך Win32 API (`GetFileVersionInfoSize`/`GetFileVersionInfo`/
/// `VerQueryValue`, package:win32).
///
/// אומת ידנית (בסביבת פיתוח, לא ווינדוס) שקובצי ה-otzaria.exe שיוצאים
/// מתהליך הבנייה של Flutter/Windows *כוללים* את השדה הזה, ושהוא תואם
/// בדיוק לתג ה-release (למשל "0.9.53"). ⚠️ **קוד ה-FFI כאן לא נבדק על
/// ווינדוס בפועל** (הסביבה ששימשה לפיתוח היא Linux, בלי אפשרות להריץ
/// exe/FFI של Windows) — יש לבדוק ולתקן אצלך אם יש שגיאות קומפילציה/
/// ריצה. חשודים סבירים: שמות/חתימות הפונקציות ב-package:win32 עשויים
/// להשתנות בין גרסאות; טיפול במצביעים (Pointer casting) בין
/// Uint16/Utf16/Void.
///
/// **הערה לגבי מקביליות ל-macOS:** הקובץ הזה מיובא (דרך
/// [installedVersionReaderFor]) גם בבנייה ל-macOS, ולכן גם `package:win32`
/// נכנס לקומפילציה שם. זה בטוח: כל ה-bindings ב-`package:win32` הם
/// `DynamicLibrary.open` בתוך משתני `final` ברמת הקובץ — כלומר lazy, נטענים
/// רק בקריאה הראשונה בפועל, שלעולם לא מתרחשת ב-macOS (ראו ה-guard בתחילת
/// [readVersion]).
class WindowsExeVersionReader implements InstalledVersionReader {
  const WindowsExeVersionReader();

  /// מחזיר את ה-ProductVersion (למשל "0.9.53"), או null אם הקובץ לא
  /// קיים, אין לו version resource, או שהקריאה נכשלה מכל סיבה אחרת.
  ///
  /// זורק [UnsupportedError] אם מופעל שלא בווינדוס (אין טעם לנסות FFI
  /// של Win32 API בפלטפורמה אחרת).
  @override
  String? readVersion(String exePath) {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsExeVersionReader עובד רק בווינדוס.');
    }
    if (!File(exePath).existsSync()) return null;

    final pathPtr = exePath.toNativeUtf16();
    final handlePtr = calloc<Uint32>();
    Pointer<Uint8>? dataPtr;
    final blockPtrPtr = calloc<Pointer<Void>>();
    final lenPtr = calloc<Uint32>();

    try {
      final size = GetFileVersionInfoSize(pathPtr, handlePtr);
      if (size == 0) return null;

      dataPtr = calloc<Uint8>(size);
      final gotInfo = GetFileVersionInfo(pathPtr, 0, size, dataPtr.cast());
      if (gotInfo == 0) return null;

      // שלב 1: לשלוף את זוג (language, codepage) הזמין בקובץ, כדי לדעת
      // איזה תת-בלוק StringFileInfo לקרוא. כמעט תמיד יש בלוק אחד יחיד.
      final translationKey = r'\VarFileInfo\Translation'.toNativeUtf16();
      int translationOk;
      try {
        translationOk = VerQueryValue(
          dataPtr.cast(),
          translationKey,
          blockPtrPtr,
          lenPtr,
        );
      } finally {
        calloc.free(translationKey);
      }

      if (translationOk == 0 ||
          lenPtr.value < 4 ||
          blockPtrPtr.value == nullptr) {
        return null;
      }

      final translation = blockPtrPtr.value.cast<Uint16>();
      final langId = translation[0];
      final codePage = translation[1];
      final langHex = langId.toRadixString(16).padLeft(4, '0');
      final codePageHex = codePage.toRadixString(16).padLeft(4, '0');

      // שלב 2: לקרוא את ProductVersion מתוך תת-הבלוק הספציפי הזה.
      final versionKey =
          '\\StringFileInfo\\$langHex$codePageHex\\ProductVersion'
              .toNativeUtf16();
      int versionOk;
      try {
        versionOk = VerQueryValue(
          dataPtr.cast(),
          versionKey,
          blockPtrPtr,
          lenPtr,
        );
      } finally {
        calloc.free(versionKey);
      }

      if (versionOk == 0 || blockPtrPtr.value == nullptr) return null;

      return blockPtrPtr.value.cast<Utf16>().toDartString();
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      calloc.free(blockPtrPtr);
      calloc.free(lenPtr);
      if (dataPtr != null) calloc.free(dataPtr);
    }
  }
}
