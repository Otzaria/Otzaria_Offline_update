import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
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
  /// חוסמות את ה-UI. הפונקציה שנשלחת היא top-level ומקבלת ערכים ניתנים-
  /// לשליחה בלבד — ראו האזהרה על closures ב-`LibraryUpdateApplier`.
  ///
  /// [onProgress] מדווח כמה נקרא מהקובץ **הדחוס** מתוך גודלו — גודל המסד
  /// שייצא אינו ידוע מראש. הדיווח חוזר דרך [ReceivePort] כדי שה-callback
  /// עצמו לא ייכנס ל-`Context` של סוגר ה-`Isolate.run`.
  ///
  /// השפה מועברת במפורש כי משתנים סטטיים אינם משותפים בין isolates — בלעדיה
  /// הודעות ה-[ZstdStreamException] היו יוצאות תמיד בברירת המחדל (עברית).
  static Future<bool> decompressFileToFile(
    String sourcePath,
    String destPath, {
    void Function(int bytesRead, int totalBytes)? onProgress,
  }) async {
    final language = AppL10n.language;
    if (onProgress == null) {
      return _runDecompressIsolate(sourcePath, destPath, language, null);
    }

    final port = ReceivePort();
    final sub = port.listen((msg) {
      if (msg is (int, int)) onProgress(msg.$1, msg.$2);
    });
    try {
      return await _runDecompressIsolate(
        sourcePath,
        destPath,
        language,
        port.sendPort,
      );
    } finally {
      // ההודעה האחרונה עדיין בתור כש-`Isolate.run` חוזר — בלי המתנה לסבב
      // אירועים אחד המד היה נתקע לפני הסוף.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      port.close();
    }
  }

  /// מתודה נפרדת: כאן נוצר סוגר ה-`Isolate.run`, ולכן היא מקבלת **רק** ערכים
  /// ניתנים-לשליחה — ראו האזהרה ב-`LibraryUpdateApplier`.
  static Future<bool> _runDecompressIsolate(
    String sourcePath,
    String destPath,
    AppLanguage language,
    SendPort? sendPort,
  ) {
    return Isolate.run(
      () => _decompressInIsolate((sourcePath, destPath, language, sendPort)),
    );
  }

  /// ה-bindings הטעונים, או `null` אם אין ספריית zstd לטעינה בסביבה הזו.
  ///
  /// הקוד הרגיל לא צריך את זה — [decompressFileToFile] מחזיר `false` מעצמו.
  /// זה קיים כדי שהבדיקה תדע אם לדלג, ותוכל לייצר קובץ `.zst` אמיתי לבדיקה
  /// באותה ספרייה בדיוק (במקום לשכפל את שמות הספריות לכל פלטפורמה).
  static ZstandardNativeBindings? bindingsOrNull() {
    final library = _openLibrary();
    return library == null ? null : ZstandardNativeBindings(library);
  }

  /// הגודל **המחולץ** של קובץ ה-`.zst` לפי כותרת ה-frame שלו, או `null` כשהוא
  /// אינו רשום שם או שאין ספריית zstd. עולה קריאה של 18 בתים.
  ///
  /// זה מה שמאפשר לבדוק מקום פנוי לפני חילוץ של ~7GB במקום להתנגש בדיסק מלא
  /// באמצע. הנכס האמיתי של המסד אכן נושא את הגודל בכותרת (נמדד); patch אינו,
  /// ואז התשובה `null` והקורא פשוט אינו בודק.
  static int? contentSizeOf(String sourcePath) {
    final bindings = bindingsOrNull();
    if (bindings == null) return null;
    final file = File(sourcePath);
    if (!file.existsSync()) return null;

    // ZSTD_frameHeaderSize_max הוא 18 — די בו כדי לקרוא את הגודל.
    const headerMax = 18;
    final raf = file.openSync();
    final buffer = malloc.allocate<Uint8>(headerMax);
    try {
      final view = buffer.asTypedList(headerMax);
      final read = raf.readIntoSync(view, 0, headerMax);
      if (read <= 0) return null;
      final size = bindings.ZSTD_getFrameContentSize(buffer.cast(), read);
      // -1 = הגודל אינו בכותרת, -2 = שגיאה. שניהם "לא יודע".
      if (size < 0) return null;
      return size;
    } catch (_) {
      return null;
    } finally {
      malloc.free(buffer);
      raf.closeSync();
    }
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

/// גבול חלון הפענוח. 31 הוא המקסימום שהפורמט מגדיר, ומרווח הוא כל העניין:
/// קלט שנדחס ב-`--long` היה נדחה בברירת המחדל (27).
const int _maxWindowLog = 31;

/// גוף החילוץ. top-level ומקבל רק ערכים ניתנים-לשליחה, כדי שלא ייתפס שום
/// `this` בדרך ל-isolate. [args]: `($1: מקור, $2: יעד, $3: שפה, $4: יציאת
/// דיווח ההתקדמות או null)`.
bool _decompressInIsolate((String, String, AppLanguage, SendPort?) args) {
  AppL10n.use(args.$3);
  final progressPort = args.$4;
  final strings = AppL10n.strings.libraryDomain;
  final library = _openLibrary();
  if (library == null) return false;
  final zstd = ZstandardNativeBindings(library);

  final inCapacity = zstd.ZSTD_DStreamInSize();
  final outCapacity = zstd.ZSTD_DStreamOutSize();

  final dctx = zstd.ZSTD_createDCtx();
  if (dctx == nullptr) {
    throw ZstdStreamException(strings.zstdContextCreationFailed);
  }
  final inPtr = malloc.allocate<Uint8>(inCapacity);
  final outPtr = malloc.allocate<Uint8>(outCapacity);
  final inBuffer = malloc<ZSTD_inBuffer>();
  final outBuffer = malloc<ZSTD_outBuffer>();

  final source = File(args.$1).openSync();
  final totalBytes = source.lengthSync();
  final dest = File(args.$2).openSync(mode: FileMode.write);
  // view על הזיכרון ה-native — אין העתקה, רק גישה מ-Dart לאותם בתים.
  final inView = inPtr.asTypedList(inCapacity);
  final outView = outPtr.asTypedList(outCapacity);

  try {
    final init = zstd.ZSTD_initDStream(dctx);
    if (zstd.ZSTD_isError(init) != 0) {
      throw ZstdStreamException(strings.zstdContextCreationFailed);
    }
    // ברירת המחדל של libzstd היא windowLogMax=27 (128MB), וה-patches שהמאגר
    // מפרסם יושבים בדיוק על 27 — עובר, בלי מרווח. שינוי אחד בהגדרות הדחיסה
    // אצל המפיק (`--long`, `--ultra`) היה מפיל כל patch ב-windowTooLarge.
    zstd.ZSTD_DCtx_setParameter(
      dctx,
      ZSTD_dParameter.ZSTD_d_windowLogMax,
      _maxWindowLog,
    );
    inBuffer.ref.src = inPtr.cast();
    outBuffer.ref.dst = outPtr.cast();

    var lastResult = 0;
    var sawInput = false;
    var bytesRead = 0;
    while (true) {
      final read = source.readIntoSync(inView, 0, inCapacity);
      if (read == 0) break;
      sawInput = true;
      bytesRead += read;
      // חוצץ הקלט הוא ~128KB, כלומר אלפי דיווחים על קובץ של ~1GB. הצד המקבל
      // מדלל אותם (`ProgressNotifier`), וכאן זה עדיין זול משמעותית מה-I/O.
      progressPort?.send((bytesRead, totalBytes));

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
            strings.zstdDecompressionFailed(_errorName(zstd, lastResult)),
          );
        }
        final produced = outBuffer.ref.pos;
        if (produced > 0) {
          dest.writeFromSync(outView, 0, produced);
        }
      }
    }

    if (!sawInput) {
      throw ZstdStreamException(strings.zstdEmptyInput);
    }
    // `0` = ה-frame נסגר כהלכה. כל ערך אחר אומר שהקלט נגמר באמצע frame,
    // כלומר קובץ קטוע — בדיוק המצב שאסור לכתוב ממנו DB.
    if (lastResult != 0) {
      throw ZstdStreamException(strings.zstdTruncatedFrame);
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
