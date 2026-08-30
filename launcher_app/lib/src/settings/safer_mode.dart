import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'app_settings.dart';
import 'settings_controller.dart';

/// מצב סייפר — נעילת ההגדרות ועריכת ההדרכה בסיסמה, כמו באוצריא עצמה.
///
/// **זו הרתעה, לא הצפנה.** הקובץ יושב על הכונן וכל מי שיש לו גישה לדיסק
/// יכול למחוק אותו ולקבל הגדרות ברירת מחדל. המטרה היא שמי שיושב מול
/// התוכנה לא ישנה בה הגדרות — לא לעצור מי שעורך קבצים.
class SaferModePassword {
  /// אורך הסיסמה המזערי, כמו באוצריא.
  static const int minLength = 4;

  /// אורך המלח בבתים, לפני קידוד ל-hex.
  static const int _saltBytes = 8;

  /// `Random.secure()` ולא `Random()` — מלח צפוי מבטל את מה שהוא בא למנוע.
  static final Random _random = Random.secure();

  /// מערבל סיסמה עם מלח חדש. הפורמט `"<מלח>:<תקציר>"`, וזה מה שנשמר.
  static String encode(String password) {
    final salt = [
      for (var i = 0; i < _saltBytes; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    return '$salt:${_digest(password, salt)}';
  }

  /// האם [password] מתאים ל-[stored] שנשמר ב-[encode]. ערך ריק או פגום —
  /// `false`, ולא חריגה: קובץ הגדרות שנערך ביד לא יפיל את התוכנה.
  static bool verify(String stored, String password) {
    final parts = stored.split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return false;
    return _digest(password, parts[0]) == parts[1];
  }

  static String _digest(String password, String salt) =>
      sha256.convert(utf8.encode('$salt$password')).toString();
}

/// שומר הסף של מצב הסייפר: מחזיק את האימות **להרצה אחת** ומוודא אותו לפני
/// כל כניסה למקום נעול.
///
/// אימות אחד מספיק עד סגירת התוכנה — מי שנכנס להגדרות, יצא וחזר אינו נשאל
/// שוב. הבחירה הזו מכוונת: הנעילה נועדה למנוע שינוי הגדרות בהיסח הדעת ולא
/// לשמור על מחשב שעובר מיד ליד באמצע הרצה.
class SaferModeGate {
  SaferModeGate(this.settings);

  final SettingsController settings;

  bool _unlocked = false;

  AppSettings get _s => settings.settings;

  /// נעול כרגע — כלומר הכניסה הבאה תבקש סיסמה.
  bool get isLocked => _s.saferModeActive && !_unlocked;

  /// מסמן שהמשתמש הוכיח את הסיסמה. נקרא גם אחרי *בחירת* סיסמה חדשה: מי
  /// שקבע אותה זה עתה אינו צריך להקליד אותה מיד שוב.
  void unlock() => _unlocked = true;

  /// מבטל את האימות — למשל אחרי מחיקת הסיסמה, כדי שסיסמה שתיבחר אחריה
  /// תיכנס לתוקף מיד.
  void lock() => _unlocked = false;
}
