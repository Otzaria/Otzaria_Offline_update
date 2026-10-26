import 'package:otzaria_l10n/otzaria_l10n.dart';

/// גדלים לתצוגה למשתמש, בבסיס 1024: GB עם ספרה אחת אחרי הנקודה ("1.1 GB"),
/// MB ו-KB שלמים — "1126 MB" או "403.4 MB" רק מרעישים.
String formatBytes(int bytes) {
  final units = AppL10n.strings.units;
  if (bytes < 1024) return units.bytes(bytes);
  final kb = bytes / 1024;
  if (kb < 1024) return units.kilobytes(kb.toStringAsFixed(0));
  final mb = kb / 1024;
  if (mb < 1024) return units.megabytes(mb.toStringAsFixed(0));
  return units.gigabytes((mb / 1024).toStringAsFixed(1));
}

/// מהירות העברה: "6.8 MB/s" — מתחת ל-10 MB/s ספרה אחת אחרי הנקודה, כמו
/// במוקאפ.
String formatRate(double bytesPerSecond) {
  final units = AppL10n.strings.units;
  final mb = bytesPerSecond / (1024 * 1024);
  final size = mb >= 1 && mb < 10
      ? units.megabytes(mb.toStringAsFixed(1))
      : formatBytes(bytesPerSecond.round());
  return units.perSecond(size);
}

final RegExp _bidiIsolates = RegExp('[\u2066-\u2069]');

/// [text] בלי תווי הבידוד ועם רווח רגיל במקום הקשיח — ליומן ול"העתק פרטים",
/// כדי שחיפוש "403 MB" ימצא את השורה.
String withoutBidiMarks(String text) =>
    text.replaceAll(_bidiIsolates, '').replaceAll('\u00a0', ' ');

/// "412 MB מתוך 1.1 GB" לשורת ההתקדמות. `null` כשעוד לא הגיע דיווח בייטים,
/// ובלי היעד — רק כמה ירד עד כה. גם 0 מתוך 0 הוא `null`: זו הורדה שכל
/// קבציה כבר על הכונן, ו-"0 בייט" רק מבלבל.
String? formatBytesProgress(int? received, int? total) {
  if (received == null) return null;
  if (total == null || total <= 0) {
    return received > 0 ? formatBytes(received) : null;
  }
  return AppL10n.strings.units.progressOf(
    formatBytes(received),
    formatBytes(total),
  );
}
