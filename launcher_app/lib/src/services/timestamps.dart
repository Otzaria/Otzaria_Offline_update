import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'hebrew_date.dart';

/// חותמות של המסגרת בלוח הלועזי, כדי להשוות הרצות; תאריכי החנויות
/// ([formatStoreDate]) בלוח העברי בעברית, כמו באתר.

String _two(int n) => n.toString().padLeft(2, '0');

/// שעה:דקה. שעון 24 שעות — חד-משמעי בשתי השפות, ולכן אינו תלוי בשפה.
String formatClock(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// תאריך ושעה: `dd.mm.yyyy` בעברית, ISO באנגלית — שם `dd.mm.yyyy`
/// נקרא כתאריך אמריקאי הפוך.
String formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final time = '${formatClock(local)}:${_two(local.second)}';
  if (!AppL10n.language.isRtl) {
    return '${local.year}-${_two(local.month)}-${_two(local.day)} $time';
  }
  return '${_two(local.day)}.${_two(local.month)}.${local.year}, $time';
}

/// תאריך בלבד, באותו סדר כמו [formatTimestamp].
String formatDate(DateTime value) {
  final local = value.toLocal();
  if (!AppL10n.language.isRtl) {
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }
  return '${_two(local.day)}.${_two(local.month)}.${local.year}';
}

/// תאריך בחנויות. רגע מהקטלוג נקרא ב-UTC, כמו באתר; רגע שנרשם במחשב
/// הזה — [formatStoreLocalDate].
String formatStoreDate(DateTime value) => _storeDay(value.toUtc());

/// [formatStoreDate] לרגע שנרשם במחשב הזה (סנכרון, הוספה): היום בלוח המקומי.
String formatStoreLocalDate(DateTime value) => _storeDay(value.toLocal());

/// [formatStoreDate] למחרוזת תאריך מה-API (`YYYY-MM-DD` או ISO-8601 מלא).
/// מחרוזת שאינה תאריך מוחזרת כמות שהיא — עדיף על שגיאה במסך.
String formatStoreDateRaw(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  // תאריך בלי שעה הוא יום בלוח, לא רגע — המרה הייתה מזיזה אותו.
  return _storeDay(raw.length <= 10 ? date : date.toUtc());
}

String _storeDay(DateTime day) => AppL10n.language.isRtl
    ? HebrewDate.fromDateTime(day).toString()
    : AppL10n.strings.units.longDate(day.day, day.month, day.year);
