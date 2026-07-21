import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../models/patch_table_spec.dart';

/// מחשב logical content hash על תוכן ה-DB, בדיוק כמו `LogicalContentHasher.kt`
/// בצד הייצור (SeforimLibrary). ה-hash משמש לאימות שה-DB המקומי תואם בדיוק
/// ל-`fromContentHash`/`toContentHash` שב-manifest.
///
/// האלגוריתם (אומת אות-באות מול שרשרת v14/v15 האמיתית):
/// * לכל טבלה בסדר ה-hash הנתון ([compute]‏ `tableOrder`, ברירת מחדל
///   [kHashTableOrder]) נכתב הקידומת `" table:<name> "` — תמיד, גם אם הטבלה
///   אינה קיימת. הסדר נבחר לפי גרסת הסכמה (34 לסכמה-2, 33 לסכמה-1).
/// * אם הטבלה קיימת: `"cols:<c1,c2,...>"` (עמודות ממוינות אלפביתית) ואז בית 0x00.
/// * השורות נקראות לפי `ORDER BY id` (אם יש עמודת id) או לפי כל העמודות.
/// * לכל תא: בית-סוג ואז הנתונים, ואז מפריד יחידה 0x1F.
///   null=0, blob=1+bytes, מספר=2+toString().utf8, טקסט=3+toString().utf8.
/// * אחרי כל שורה: מפריד שורה 0xFF.
///
/// זרם הבתים מוזרם ל-SHA-256 דרך [_BufferedByteSink] שמקבץ ~1MB לפני כל
/// עדכון — חוסך מיליוני קריאות זעירות. SHA-256 אינו תלוי בגודל ה-chunks,
/// אז הקיבוץ אינו משנה את התוצאה.
class LogicalContentHasher {
  const LogicalContentHasher();

  // בתים של תגי-סוג ומפרידים — זהים למימוש ה-Kotlin, אין לשנות.
  static const int _nullTag = 0x00;
  static const int _blobTag = 0x01;
  static const int _numberTag = 0x02;
  static const int _textTag = 0x03;
  static const int _unitSeparator = 0x1F;
  static const int _rowSeparator = 0xFF;

  /// מחשב את ה-hash על [db] ומחזיר אותו כ-hex. ניתן להריץ על חיבור read-only
  /// (preflight) או על חיבור כתיב בתוך transaction (אימות אחרי apply).
  ///
  /// [onProgress] מדווח את מספר הבתים המצטבר שהוזרם ל-SHA עד כה (מדוד כל
  /// ~16MB), למד התקדמות במהלך האימות הארוך.
  /// [tableOrder] — סדר הטבלאות לשקלול ב-hash. ברירת מחדל: [kHashTableOrder]
  /// (34 טבלאות, סכמה-2). ה-caller בוחר את הסדר לפי גרסת הסכמה של ה-DB.
  String compute(sqlite3.Database db,
      {List<String> tableOrder = kHashTableOrder,
      void Function(int bytesHashed)? onProgress}) {
    final digestSink = _DigestSink();
    final shaSink = sha256.startChunkedConversion(digestSink);
    final out = _BufferedByteSink(shaSink, onProgress: onProgress);

    for (final table in tableOrder) {
      out.addBytes(utf8.encode(' table:$table '));
      final cols = _readColumnsCanonical(db, table);
      if (cols == null) continue;
      out.addBytes(utf8.encode('cols:${cols.join(',')}'));
      out.addByte(_nullTag);

      // ל-text קוראים את ה-bytes הגולמיים (CAST AS BLOB) כדי לא לאבד BOM
      // מוביל — ה-decoder של Dart מסיר U+FEFF, ולכן String רגיל היה משנה את
      // ה-hash. typeof קובע את בית-הסוג; ה-CASE מחזיר blob רק ל-text.
      final selectCols = cols
          .map((c) => 'typeof("$c"),CASE WHEN typeof("$c")=\'text\' '
              'THEN CAST("$c" AS BLOB) ELSE "$c" END')
          .join(',');
      final orderBy =
          cols.contains('id') ? 'id' : cols.map((c) => '"$c"').join(',');
      final stmt =
          db.prepare('SELECT $selectCols FROM "$table" ORDER BY $orderBy');
      try {
        final cursor = stmt.selectCursor(const []);
        while (cursor.moveNext()) {
          final values = cursor.current.values;
          for (var i = 0; i < values.length; i += 2) {
            _encodeCell(out, values[i] as String, values[i + 1]);
          }
          out.addByte(_rowSeparator);
        }
      } finally {
        stmt.close();
      }
    }

    out.flush();
    // דיווח סופי מדויק — מאפשר ל-caller לשמור את סך-הבתים האמיתי לריצה הבאה.
    onProgress?.call(out.totalHashed);
    shaSink.close();
    return digestSink.digest.toString();
  }

  /// קורא את שמות העמודות ממוינים אלפביתית, או null אם הטבלה אינה קיימת.
  List<String>? _readColumnsCanonical(sqlite3.Database db, String table) {
    final result = db.select('PRAGMA table_info("$table")');
    if (result.isEmpty) return null;
    final names = result.map((r) => r['name'] as String).toList();
    names.sort();
    return names;
  }

  /// [type] הוא תוצאת `typeof()` ('null'/'integer'/'real'/'text'/'blob').
  /// עבור 'text' ו-'blob', [value] הוא ה-bytes הגולמיים (Uint8List).
  void _encodeCell(_BufferedByteSink out, String type, Object? value) {
    switch (type) {
      case 'null':
        out.addByte(_nullTag);
      case 'text':
        out.addByte(_textTag);
        out.addBytes(value as Uint8List);
      case 'blob':
        out.addByte(_blobTag);
        out.addBytes(value as Uint8List);
      default: // 'integer' / 'real'
        out.addByte(_numberTag);
        out.addBytes(utf8.encode(value.toString()));
    }
    out.addByte(_unitSeparator);
  }
}

/// חוצץ בינארי שמצטבר ומוזרם ל-SHA-256 מדי ~1MB. מחליף מיליוני `add` זעירים
/// (בית/תא) בעדכונים גדולים בודדים, בלי לשנות את זרם הבתים.
class _BufferedByteSink {
  _BufferedByteSink(this._sink, {this.onProgress});

  final ByteConversionSink _sink;
  final void Function(int bytesHashed)? onProgress;
  static const int _capacity = 1 << 20; // 1MB
  static const int _progressInterval = 16 << 20; // 16MB
  final Uint8List _buffer = Uint8List(_capacity);
  int _length = 0;
  int _totalHashed = 0;
  int _lastReported = 0;

  int get totalHashed => _totalHashed;

  void addByte(int byte) {
    if (_length == _capacity) flush();
    _buffer[_length++] = byte;
    _totalHashed++;
  }

  void addBytes(List<int> bytes) {
    final len = bytes.length;
    // ערך גדול מהחוצץ מוזרם ישירות אחרי flush — בלי העתקה מיותרת. ה-flush
    // חובה לפני, אחרת סדר הבתים ישתבש.
    if (len >= _capacity) {
      flush();
      _sink.add(bytes);
      _totalHashed += len;
      _reportIfDue();
      return;
    }
    if (_length + len > _capacity) flush();
    _buffer.setRange(_length, _length + len, bytes);
    _length += len;
    _totalHashed += len;
  }

  /// מזרים את מה שהצטבר. הזרם הסינכרוני של SHA-256 לא מחזיק את ה-view, אז
  /// ניתן לעשות שימוש חוזר ב-[_buffer] מיד אחרי.
  void flush() {
    if (_length == 0) return;
    _sink.add(Uint8List.sublistView(_buffer, 0, _length));
    _length = 0;
    _reportIfDue();
  }

  void _reportIfDue() {
    if (onProgress == null) return;
    if (_totalHashed - _lastReported < _progressInterval) return;
    _lastReported = _totalHashed;
    onProgress!(_totalHashed);
  }
}

/// אוסף את ה-Digest הסופי מ-`startChunkedConversion`.
class _DigestSink implements Sink<Digest> {
  late Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
