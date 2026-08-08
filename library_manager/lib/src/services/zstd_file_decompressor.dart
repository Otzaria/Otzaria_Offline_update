import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// מחלץ קובץ `.zst` **בזרימה**, קובץ-לקובץ, בלי להחזיק את התוכן בזיכרון.
///
/// למה זה קיים: `package:zstandard` חושף רק `decompress(Uint8List)` — כלומר
/// קלט מלא ופלט מלא ב-RAM. במסלול ההורדה המלאה של הספרייה זה אומר את הקובץ
/// הדחוס (מאות MB) **ועוד** את ה-DB המחולץ (~1.1GB) בבת אחת, ואז עוד העתק
/// שלו כשה-Uint8List נשלח ל-isolate שכותב אותו. על מחשב עם 4GB זה פשוט נגמר
/// בכשל הקצאה. כאן קוראים חוצץ קלט קטן, מחלצים לחוצץ פלט קטן וכותבים —
/// שיא הזיכרון הוא סדר גודל של מגה-בייטים בודדים, ללא תלות בגודל ה-DB.
///
/// המימוש נשען על ה-bindings שחבילת ה-zstd של אוצריא כבר מביאה איתה
/// (`zstandard_native`) ועל ה-DLL/framework שהפלאגין של הפלטפורמה טוען —
/// ולכן אין כאן תלות native חדשה, רק שימוש ב-streaming API של libzstd
/// (`ZSTD_decompressStream`) במקום ב-one-shot.
///
/// כשלא ניתן לטעון את הספרייה (פלטפורמה שאין לה פלאגין, למשל בבדיקות על
/// לינוקס) [decompressFileToFile] מחזיר `false` והקורא נופל למסלול הזיכרון
/// הקודם. כלומר זו אופטימיזציה, לא דרישה.
abstract final class ZstdFileDecompressor {
  /// מחלץ [sourcePath] אל [destPath]. מחזיר `false` אם החילוץ בזרימה אינו
  /// זמין בפלטפורמה הזו (ואז יש להשתמש במסלול החלופי); זורק [ZstdStreamException]
  /// אם הוא זמין אך הקובץ פגום.
  ///
  /// רץ ב-isolate נפרד: אלה קריאות native סינכרוניות על מאות MB, והן היו
  /// חוסמות את ה-UI. הפונקציה שנשלחת היא top-level ומקבלת מחרוזות בלבד —
  /// ראו האזהרה על closures ב-`LibraryUpdateApplier`.
  static Future<bool> decompressFileToFile(
    String sourcePath,
    String destPath,
  ) =>
      Isolate.run(() => _decompressInIsolate((sourcePath, destPath)));

  /// ה-bindings הטעונים, או `null` אם אין ספריית zstd לטעינה בסביבה הזו.
  ///
  /// הקוד הרגיל לא צריך את זה — [decompressFileToFile] מחזיר `false` מעצמו.
  /// זה קיים כדי שהבדיקה תדע אם לדלג, ותוכל לייצר קובץ `.zst` אמיתי לבדיקה
  /// באותה ספרייה בדיוק (במקום לשכפל את שמות הספריות לכל פלטפורמה).
  static ZstandardNativeBindings? bindingsOrNull() {
    final library = _openLibrary();
    return library == null ? null : ZstandardNativeBindings(library);
  }
}

class ZstdStreamException implements Exception {
  const ZstdStreamException(this.message);
  final String message;
  @override
  String toString() => 'ZstdStreamException: $message';
}

/// שם הספרייה הדינמית שפלאגין ה-zstd מספק לכל פלטפורמה. אלה אותם שמות
/// ש-`zstandard_windows`/`zstandard_macos` פותחים בעצמם, ולכן ברוב המקרים
/// הספרייה כבר טעונה בתהליך וה-`open` רק מחזיר אליה handle.
DynamicLibrary? _openLibrary() {
  try {
    if (Platform.isWindows) {
      return DynamicLibrary.open('zstandard_windows.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(
        'zstandard_macos.framework/zstandard_macos',
      );
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libzstandard_linux.so');
    }
  } catch (_) {
    // אין ספרייה זמינה — הקורא נופל למסלול הזיכרון.
  }
  return null;
}

/// גוף החילוץ. top-level ומקבל רק מחרוזות, כדי שלא ייתפס שום `this` בדרך
/// ל-isolate. [args]: `($1: מקור, $2: יעד)`.
bool _decompressInIsolate((String, String) args) {
  final library = _openLibrary();
  if (library == null) return false;
  final zstd = ZstandardNativeBindings(library);

  final inCapacity = zstd.ZSTD_DStreamInSize();
  final outCapacity = zstd.ZSTD_DStreamOutSize();

  final dctx = zstd.ZSTD_createDCtx();
  if (dctx == nullptr) {
    throw const ZstdStreamException('יצירת הקשר החילוץ (DCtx) נכשלה');
  }
  final inPtr = malloc.allocate<Uint8>(inCapacity);
  final outPtr = malloc.allocate<Uint8>(outCapacity);
  final inBuffer = malloc<ZSTD_inBuffer>();
  final outBuffer = malloc<ZSTD_outBuffer>();

  final source = File(args.$1).openSync();
  final dest = File(args.$2).openSync(mode: FileMode.write);
  // view על הזיכרון ה-native — אין העתקה, רק גישה מ-Dart לאותם בתים.
  final inView = inPtr.asTypedList(inCapacity);
  final outView = outPtr.asTypedList(outCapacity);

  try {
    zstd.ZSTD_initDStream(dctx);
    inBuffer.ref.src = inPtr.cast();
    outBuffer.ref.dst = outPtr.cast();

    var lastResult = 0;
    var sawInput = false;
    while (true) {
      final read = source.readIntoSync(inView, 0, inCapacity);
      if (read == 0) break;
      sawInput = true;

      inBuffer.ref.size = read;
      inBuffer.ref.pos = 0;

      // frame בודד יכול להתפרס על פני כמה חוצצי קלט, וחוצץ קלט בודד יכול
      // להפיק יותר מחוצץ פלט אחד — ולכן לולאה פנימית עד שהקלט נצרך כולו.
      while (inBuffer.ref.pos < inBuffer.ref.size) {
        outBuffer.ref.size = outCapacity;
        outBuffer.ref.pos = 0;
        lastResult = zstd.ZSTD_decompressStream(dctx, outBuffer, inBuffer);
        if (zstd.ZSTD_isError(lastResult) != 0) {
          throw ZstdStreamException(
            'חילוץ ה-zstd נכשל: ${_errorName(zstd, lastResult)}',
          );
        }
        final produced = outBuffer.ref.pos;
        if (produced > 0) {
          dest.writeFromSync(outView, 0, produced);
        }
      }
    }

    if (!sawInput) {
      throw const ZstdStreamException('הקובץ הדחוס ריק');
    }
    // `0` = ה-frame נסגר כהלכה. כל ערך אחר אומר שהקלט נגמר באמצע frame,
    // כלומר קובץ קטוע — בדיוק המצב שאסור לכתוב ממנו DB.
    if (lastResult != 0) {
      throw const ZstdStreamException(
        'הקובץ הדחוס נקטע — ה-frame לא הושלם',
      );
    }
    dest.flushSync();
    return true;
  } finally {
    source.closeSync();
    dest.closeSync();
    malloc.free(inBuffer);
    malloc.free(outBuffer);
    malloc.free(inPtr);
    malloc.free(outPtr);
    zstd.ZSTD_freeDCtx(dctx);
  }
}

String _errorName(ZstandardNativeBindings zstd, int code) {
  try {
    return zstd.ZSTD_getErrorName(code).cast<Utf8>().toDartString();
  } catch (_) {
    return 'code $code';
  }
}
