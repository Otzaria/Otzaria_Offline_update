import 'dart:convert';
import 'dart:math';

/// מגבלות הפרוטוקול (v1) שנאכפות בצד הלקוח לפני הכנסה לתור.
abstract final class SearchFeedbackLimits {
  static const int query = 500;
  static const int title = 300;
  static const int reference = 300;
  static const int snippetText = 2000;
  static const int passageText = 20000;
  static const int matchedTextItems = 50;
  static const int matchedTextItemLength = 200;
  static const int resultsPerEvent = 100;
  static const int fallbackKind = 64;
  static const int maxFuzzyDistance = 10;
  static const int maxPageSize = 1000;
  static const int rankingKeys = 40;
  static const int eventsPerBatch = 100;
  static const int batchBytes = 512 * 1024;

  /// מרווח לעטיפת ה-batch (context, מזהים) מתוך [batchBytes].
  static const int batchEnvelopeReserve = 16 * 1024;

  /// אירוע בודד גדול מזה מכווץ (קטעי טקסט) כדי שייכנס ל-batch.
  static const int eventBytes = 256 * 1024;

  /// שדות חופשיים שאין להם מגבלה בפרוטוקול (מצבים, שמות מודל, פאסטות).
  static const int shortField = 64;
  static const int mediumField = 300;
  static const int facets = 50;
  static const Duration maxDwell = Duration(minutes: 30);
}

/// JSON שבו כל תו שאינו ASCII מקודד כ-`\uXXXX` — תקני, אך מסנני רשת
/// שסורקים את גוף הבקשה (נטפרי) אינם חוסמים בו טקסט תורני.
String searchFeedbackJsonEncode(Object? value) {
  final raw = jsonEncode(value);
  final out = StringBuffer();
  for (final unit in raw.codeUnits) {
    if (unit < 0x80) {
      out.writeCharCode(unit);
    } else {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return out.toString();
}

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

/// האם [id] תקין לפי הפרוטוקול (batchId / eventId / searchSessionId / openId).
bool isValidSearchFeedbackId(String id) => _idPattern.hasMatch(id);

/// מזהה אקראי של 128 ביט ב-base64url בלי ריפוד (22 תווים).
String newSearchFeedbackId([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// חותמת זמן UTC בפורמט ISO עם אלפיות בדיוק (`...T10:00:00.000Z`).
String searchFeedbackIsoTime(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = utc.millisecond.toString().padLeft(3, '0');
  final year = utc.year.toString().padLeft(4, '0');
  return '$year-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:'
      '${two(utc.minute)}:${two(utc.second)}.${ms}Z';
}

/// מקצר ל-[max] יחידות UTF-16 בלי לחתוך זוג surrogate באמצע.
String truncateForSearchFeedback(String value, int max) {
  if (value.length <= max) return value;
  var end = max;
  final last = value.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return value.substring(0, end);
}
