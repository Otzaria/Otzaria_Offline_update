import 'package:otzaria_l10n/otzaria_l10n.dart';

/// גדלים לתצוגה למשתמש. בסיס 1024, ספרה אחת אחרי הנקודה רק כשזה מוסיף
/// מידע — "1.1 GB" מדויק מספיק, ו-"1126 MB" רק מרעיש.
String formatBytes(int bytes) {
  final units = AppL10n.strings.units;
  if (bytes < 1024) return units.bytes(bytes);
  final kb = bytes / 1024;
  if (kb < 1024) return units.kilobytes(kb.toStringAsFixed(0));
  final mb = kb / 1024;
  if (mb < 1024) return units.megabytes(mb.toStringAsFixed(mb < 10 ? 1 : 0));
  return units.gigabytes((mb / 1024).toStringAsFixed(2));
}

/// "412 MB מתוך 1.1 GB" לשורת ההתקדמות. `null` כשעוד לא הגיע דיווח בייטים,
/// ובלי היעד — רק כמה ירד עד כה.
String? formatBytesProgress(int? received, int? total) {
  if (received == null) return null;
  if (total == null || total <= 0) return formatBytes(received);
  return AppL10n.strings.units.progressOf(
    formatBytes(received),
    formatBytes(total),
  );
}
