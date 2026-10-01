import 'app_descriptor_id.dart';

/// שם קובץ (מדיה או קובץ התקנה) שבטוח לצרף לנתיב, או `null`. הרשומה
/// מגיעה מכונן שנדד, ולכן `../../windows/system32` כאן הוא גבול אמיתי ולא
/// ניקיון — אותו שיקול בדיוק כמו ב-[AppDescriptorId].
String? safeFileName(Object? value) {
  if (value is! String || value.isEmpty) return null;
  // Windows silently strips trailing spaces and dots, so the name on disk
  // would differ from the stored one; this also rejects `.` and `..`.
  if (value != value.trim() || value.endsWith('.')) return null;
  if (value.contains('/') || value.contains(r'\') || value.contains(':')) {
    return null;
  }
  return value;
}
