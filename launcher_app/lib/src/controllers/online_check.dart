/// האם הבדיקה הקלה **הוכיחה** שאין ברשת שום דבר חדש עבור הרכיב הזה.
///
/// כלל אחד לשלושת המודולים, כדי ש-[downloadAll] לא ידלג על אחד מהם לפי
/// היגיון אחר. שני מצבים שאינם הוכחה: בדיקה שלא רצה בכלל ([checkedAt] הוא
/// `null`), ובדיקה שנכשלה ([error]) — "אין רשת" אינו "אין עדכון", ודילוג
/// שם היה משאיר את המשתמש בלי הורדה ובלי לדעת למה.
bool provenUpToDateOnline({
  required DateTime? checkedAt,
  required String? error,
  required bool hasUpdate,
}) => checkedAt != null && error == null && !hasUpdate;

const Duration onlineCheckMaxAge = Duration(minutes: 15);

bool onlineCheckNeedsRefresh({
  required DateTime? checkedAt,
  required String? error,
  DateTime? now,
}) =>
    checkedAt == null ||
    error != null ||
    (now ?? DateTime.now()).difference(checkedAt) > onlineCheckMaxAge;
