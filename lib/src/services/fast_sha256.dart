import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

/// SHA-256 מוזרם דרך ספריית ההצפנה של המערכת, ובנפילה חזרה `package:crypto`.
///
/// למה: המימוש של `package:crypto` הוא דארט טהור ומגיע ל-~50MB/s, בעוד
/// שהמימוש של המערכת (שמנצל את הוראות SHA של המעבד) נמדד ב-~1,225MB/s —
/// פי 24. אימות ה-hash הלוגי קורא מסד של ~7.4GB, ולכן זה יותר ממחצית זמן
/// האימות של כל patch. אותו חיסכון חל על אימות ה-sha256 של הנכסים בהורדה.
///
/// **התוצאה זהה בית-בבית** — זה אותו אלגוריתם, רק מימוש אחר. חוזה ה-hash מול
/// `LogicalContentHasher.kt` בצד המפיק אינו נוגע בזה: זרם הבתים שנכנס לא
/// משתנה. כדי שטעות במימוש נייטיבי לא תדחה כל עדכון, [_openNative] מריץ
/// בדיקה עצמית מול `package:crypto` ומשתיק את המסלול הנייטיבי אם היא נכשלת.
///
/// לינוקס נופלת ל-`package:crypto` בכוונה: אין שם ספריית מערכת שמובטח
/// שתימצא (OpenSSL אינו תלות של האפליקציה), וזו אופטימיזציה ולא דרישה.
abstract final class FastSha256 {
  /// מכריח את מסלול `package:crypto` — לבדיקות בלבד, כדי להריץ את אותם קלטים
  /// בשני המסלולים ולוודא שהם מסכימים.
  @visibleForTesting
  static bool useFallbackOnly = false;

  /// כמו `sha256.startChunkedConversion` — מחזיר sink שאליו מוזרמים בתים,
  /// ו-[output] מקבל את ה-[Digest] ב-`close`. הקורא חייב לקרוא ל-
  /// [FastSha256Sink.dispose] ב-`finally`; ראו שם.
  static FastSha256Sink start(Sink<Digest> output) {
    final native = _activeNative;
    return native == null
        ? _FallbackSha256Sink(sha256.startChunkedConversion(output))
        : _NativeSha256Sink(native, output);
  }

  /// חישוב חד-פעמי על מטען שכבר בזיכרון, כמו `sha256.convert`.
  static Digest convert(List<int> bytes) {
    final native = _activeNative;
    if (native == null) return sha256.convert(bytes);
    final collector = _DigestCollector();
    final sink = _NativeSha256Sink(native, collector);
    try {
      sink
        ..add(bytes)
        ..close();
    } finally {
      sink.dispose();
    }
    return collector.value;
  }

  /// האם המסלול הנייטיבי בשימוש בסביבה הזו. חשוף לבדיקות ולאבחון בלבד —
  /// הקוד הרגיל לא צריך לדעת, שני המסלולים מחזירים אותו digest.
  static bool get isNativeAvailable => _native != null;
}

/// sink של SHA-256 שניתן לשחרר גם בלי להשלים את החישוב.
abstract class FastSha256Sink extends ByteConversionSink {
  /// משחרר את המשאבים הנייטיביים בלי להפיק digest, ואינו עושה דבר אם ה-sink
  /// כבר נסגר. חייב להיקרא ב-`finally` של הקורא: המסלול הנייטיבי מקצה חוצץ
  /// של 1MB ואובייקט hash שאיסוף האשפה של דארט אינו מכיר, וחריגה או ביטול
  /// באמצע הזרמה היו מדליפים אותם עד סוף התהליך.
  void dispose();
}

/// עוטף את ה-sink של `package:crypto`, שאין לו מה לשחרר, כדי שלקוראים יהיה
/// ממשק אחד בשני המסלולים.
///
/// אין לו זיכרון native לשחרר, אבל [dispose] חייב להיות **ביטול** גם כאן:
/// אחרת אותו `finally` היה מפיק digest בלינוקס ולא בווינדוס, כלומר מסלול
/// שגיאה שמתנהג אחרת לפי הפלטפורמה.
class _FallbackSha256Sink extends FastSha256Sink {
  _FallbackSha256Sink(this._inner);

  final ByteConversionSink _inner;
  bool _released = false;

  @override
  void add(List<int> chunk) => addSlice(chunk, 0, chunk.length, false);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    if (_released) throw StateError('FastSha256 sink: add after close');
    _inner.addSlice(chunk, start, end, isLast);
    if (isLast) _released = true;
  }

  @override
  void close() {
    if (_released) return;
    _released = true;
    _inner.close();
  }

  @override
  void dispose() => _released = true;
}

/// המימוש שבשימוש בפועל — `null` פירושו `package:crypto`.
_Sha256Native? get _activeNative => FastSha256.useFallbackOnly ? null : _native;

/// נטען פעם אחת לכל isolate (משתנים סטטיים אינם משותפים ביניהם). `null`
/// פירושו "השתמש ב-`package:crypto`".
final _Sha256Native? _native = _openNative();

_Sha256Native? _openNative() {
  try {
    final native = Platform.isWindows
        ? _BCryptSha256.openOrNull()
        : Platform.isMacOS
            ? _CommonCryptoSha256.openOrNull()
            : null;
    if (native == null) return null;
    return _selfTestPasses(native) ? native : null;
  } catch (_) {
    // ספרייה חסרה, סמל חסר, פלטפורמה לא מוכרת — נופלים ל-`package:crypto`.
    return null;
  }
}

/// מוודא שהמימוש הנייטיבי מסכים עם `package:crypto` לפני שהוא נכנס לשימוש.
/// הקלטים מכסים ריק, גוש קצר מבלוק (כולל BOM ובתי UTF-8 עבריים גולמיים —
/// בדיוק מה שה-hash הלוגי מזרים), וגוש שחוצה כמה בלוקים של 64 בתים.
bool _selfTestPasses(_Sha256Native native) {
  final samples = <List<int>>[
    const <int>[],
    const <int>[0xEF, 0xBB, 0xBF, 0xD7, 0x90, 0xD7, 0x95, 0x1F, 0xFF],
    Uint8List.fromList(List<int>.generate(1000, (i) => i & 0xFF)),
  ];
  for (final sample in samples) {
    final collector = _DigestCollector();
    final sink = _NativeSha256Sink(native, collector);
    try {
      sink
        ..add(sample)
        ..close();
    } finally {
      sink.dispose();
    }
    if (collector.value.toString() != sha256.convert(sample).toString()) {
      return false;
    }
  }
  return true;
}

/// אוסף את ה-Digest מ-sink מוזרם.
class _DigestCollector implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// חישוב יחיד מתנהל דרך handle אטום (`hHash` ב-Windows, `CC_SHA256_CTX`
/// ב-macOS), כדי שהעטיפה למעלה תהיה זהה בשתי הפלטפורמות.
abstract class _Sha256Native {
  Pointer<Void> begin();
  void update(Pointer<Void> ctx, Pointer<Uint8> data, int length);
  void finish(Pointer<Void> ctx, Pointer<Uint8> out32);
  void release(Pointer<Void> ctx);
}

/// עוטף [_Sha256Native] ב-[ByteConversionSink], כך שהוא drop-in ל-
/// `sha256.startChunkedConversion`.
///
/// הבתים מועתקים לחוצץ native אחד שמוקצה פעם אחת לכל sink; העתקה ב-memcpy
/// זולה בשני סדרי גודל מהחישוב עצמו. גוש גדול מהחוצץ מוזרם במקטעים.
class _NativeSha256Sink extends FastSha256Sink {
  _NativeSha256Sink(this._native, this._output)
      : _ctx = _native.begin(),
        _buffer = malloc.allocate<Uint8>(_bufferBytes);

  /// תואם ל-`_BufferedByteSink._capacity` ב-`LogicalContentHasher`, כך
  /// שהקורא העיקרי שולח גוש שלם בקריאה אחת.
  static const int _bufferBytes = 1 << 20;

  final _Sha256Native _native;
  final Sink<Digest> _output;
  final Pointer<Void> _ctx;
  final Pointer<Uint8> _buffer;
  late final Uint8List _view = _buffer.asTypedList(_bufferBytes);
  bool _closed = false;
  bool _released = false;

  @override
  void add(List<int> chunk) => addSlice(chunk, 0, chunk.length, false);

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    // אחרי השחרור `_view` הוא חלון על זיכרון שהוחזר: כתיבה לתוכו הייתה שחיתות
    // heap שקטה, ולכן זורקים כמו `package:crypto` במקום להמשיך.
    if (_released) throw StateError('FastSha256 sink: add after close');
    var offset = start;
    while (offset < end) {
      final length =
          (end - offset) < _bufferBytes ? end - offset : _bufferBytes;
      _view.setRange(0, length, chunk, offset);
      _native.update(_ctx, _buffer, length);
      offset += length;
    }
    if (isLast) close();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final out = malloc.allocate<Uint8>(32);
    try {
      _native.finish(_ctx, out);
      // העתקה לפני ה-free: `asTypedList` הוא view על הזיכרון ה-native.
      _output.add(Digest(Uint8List.fromList(out.asTypedList(32))));
    } finally {
      malloc.free(out);
      dispose();
    }
    _output.close();
  }

  @override
  void dispose() {
    if (_released) return;
    _released = true;
    _closed = true;
    _native.release(_ctx);
    malloc.free(_buffer);
  }
}

// ── Windows: bcrypt.dll (CNG) ──────────────────────────────────────────────

typedef _BCryptOpenAlgNative = Int32 Function(
    Pointer<Pointer<Void>>, Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _BCryptOpenAlgDart = int Function(
    Pointer<Pointer<Void>>, Pointer<Utf16>, Pointer<Utf16>, int);

typedef _BCryptCreateHashNative = Int32 Function(
    Pointer<Void>,
    Pointer<Pointer<Void>>,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Uint32);
typedef _BCryptCreateHashDart = int Function(Pointer<Void>,
    Pointer<Pointer<Void>>, Pointer<Uint8>, int, Pointer<Uint8>, int, int);

typedef _BCryptHashDataNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Uint32, Uint32);
typedef _BCryptHashDataDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, int);

typedef _BCryptFinishHashNative = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Uint32, Uint32);
typedef _BCryptFinishHashDart = int Function(
    Pointer<Void>, Pointer<Uint8>, int, int);

typedef _BCryptDestroyHashNative = Int32 Function(Pointer<Void>);
typedef _BCryptDestroyHashDart = int Function(Pointer<Void>);

/// SHA-256 של CNG. ספק האלגוריתם נפתח פעם אחת ונשאר פתוח — פתיחתו היא
/// החלק היקר, ואילו `BCryptCreateHash` לכל חישוב הוא זול.
class _BCryptSha256 implements _Sha256Native {
  _BCryptSha256._(
    this._algorithm,
    this._createHash,
    this._hashData,
    this._finishHash,
    this._destroyHash,
  );

  final Pointer<Void> _algorithm;
  final _BCryptCreateHashDart _createHash;
  final _BCryptHashDataDart _hashData;
  final _BCryptFinishHashDart _finishHash;
  final _BCryptDestroyHashDart _destroyHash;

  static _BCryptSha256? openOrNull() {
    // `bcrypt.dll` הוא זה שמייצא את ה-API; `bcryptprimitives.dll` אינו.
    final lib = DynamicLibrary.open('bcrypt.dll');
    final open = lib.lookupFunction<_BCryptOpenAlgNative, _BCryptOpenAlgDart>(
        'BCryptOpenAlgorithmProvider');
    final algorithmOut = calloc<Pointer<Void>>();
    final name = 'SHA256'.toNativeUtf16();
    try {
      if (open(algorithmOut, name, nullptr, 0) != 0) return null;
      return _BCryptSha256._(
        algorithmOut.value,
        lib.lookupFunction<_BCryptCreateHashNative, _BCryptCreateHashDart>(
            'BCryptCreateHash'),
        lib.lookupFunction<_BCryptHashDataNative, _BCryptHashDataDart>(
            'BCryptHashData'),
        lib.lookupFunction<_BCryptFinishHashNative, _BCryptFinishHashDart>(
            'BCryptFinishHash'),
        lib.lookupFunction<_BCryptDestroyHashNative, _BCryptDestroyHashDart>(
            'BCryptDestroyHash'),
      );
    } finally {
      calloc.free(name);
      calloc.free(algorithmOut);
    }
  }

  @override
  Pointer<Void> begin() {
    final hashOut = calloc<Pointer<Void>>();
    try {
      if (_createHash(_algorithm, hashOut, nullptr, 0, nullptr, 0, 0) != 0) {
        throw const _NativeShaFailure('BCryptCreateHash');
      }
      return hashOut.value;
    } finally {
      calloc.free(hashOut);
    }
  }

  @override
  void update(Pointer<Void> ctx, Pointer<Uint8> data, int length) {
    if (_hashData(ctx, data, length, 0) != 0) {
      throw const _NativeShaFailure('BCryptHashData');
    }
  }

  @override
  void finish(Pointer<Void> ctx, Pointer<Uint8> out32) {
    if (_finishHash(ctx, out32, 32, 0) != 0) {
      throw const _NativeShaFailure('BCryptFinishHash');
    }
  }

  @override
  void release(Pointer<Void> ctx) => _destroyHash(ctx);
}

// ── macOS: CommonCrypto (libSystem) ────────────────────────────────────────

typedef _CcInitNative = Int32 Function(Pointer<Void>);
typedef _CcInitDart = int Function(Pointer<Void>);

typedef _CcUpdateNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32);
typedef _CcUpdateDart = int Function(Pointer<Void>, Pointer<Uint8>, int);

typedef _CcFinalNative = Int32 Function(Pointer<Uint8>, Pointer<Void>);
typedef _CcFinalDart = int Function(Pointer<Uint8>, Pointer<Void>);

/// SHA-256 של CommonCrypto. הסמלים יושבים ב-libSystem, שכבר טעון בכל תהליך
/// ב-macOS, ולכן [DynamicLibrary.process] מספיק ואין שם ספרייה לנחש.
class _CommonCryptoSha256 implements _Sha256Native {
  _CommonCryptoSha256._(this._init, this._update, this._final);

  /// `CC_SHA256_CTX` הוא 104 בתים; מוקצה בעיגול למעלה כדי לא להישבר אם
  /// המבנה יגדל בגרסה עתידית.
  static const int _contextBytes = 256;

  final _CcInitDart _init;
  final _CcUpdateDart _update;
  final _CcFinalDart _final;

  static _CommonCryptoSha256? openOrNull() {
    final lib = DynamicLibrary.process();
    return _CommonCryptoSha256._(
      lib.lookupFunction<_CcInitNative, _CcInitDart>('CC_SHA256_Init'),
      lib.lookupFunction<_CcUpdateNative, _CcUpdateDart>('CC_SHA256_Update'),
      lib.lookupFunction<_CcFinalNative, _CcFinalDart>('CC_SHA256_Final'),
    );
  }

  @override
  Pointer<Void> begin() {
    final ctx = calloc.allocate<Uint8>(_contextBytes).cast<Void>();
    if (_init(ctx) != 1) {
      calloc.free(ctx);
      throw const _NativeShaFailure('CC_SHA256_Init');
    }
    return ctx;
  }

  @override
  void update(Pointer<Void> ctx, Pointer<Uint8> data, int length) {
    if (_update(ctx, data, length) != 1) {
      throw const _NativeShaFailure('CC_SHA256_Update');
    }
  }

  @override
  void finish(Pointer<Void> ctx, Pointer<Uint8> out32) {
    if (_final(out32, ctx) != 1) {
      throw const _NativeShaFailure('CC_SHA256_Final');
    }
  }

  @override
  void release(Pointer<Void> ctx) => calloc.free(ctx);
}

/// כשל בקריאה נייטיבית. אינו מוצג למשתמש: הוא נתפס ב-[_openNative] בבדיקה
/// העצמית ומשתיק את המסלול הנייטיבי, ולכן אין לו מלל ב-`otzaria_l10n`.
class _NativeShaFailure implements Exception {
  const _NativeShaFailure(this.symbol);
  final String symbol;
  @override
  String toString() => 'NativeShaFailure: $symbol';
}
