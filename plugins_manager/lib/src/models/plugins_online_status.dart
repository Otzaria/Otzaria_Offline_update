/// תוצאת ההצצה הקלה לחנות שברשת: מה יש שם שאין במראה המקומית. מטא-דאטה
/// בלבד — שום קובץ אינו יורד בדרך, וכלום לא נכתב למראה.
class PluginsOnlineStatus {
  const PluginsOnlineStatus({
    this.newPlugins = const [],
    this.updatedPlugins = const [],
    this.missingPlugins = const [],
    this.totalOnline = 0,
  });

  static const PluginsOnlineStatus empty = PluginsOnlineStatus();

  /// שמות התוספים שאינם בקטלוג המקומי כלל.
  final List<String> newPlugins;

  /// שמות התוספים שגרסתם באתר שונה מזו שבמראה.
  final List<String> updatedPlugins;

  /// שמות התוספים שהקטלוג מכיר אבל קובץ ההתקנה שלהם אינו בתיקייה — נמחק,
  /// לא הועתק, או שהורדה קודמת נכשלה. בלי הבדיקה הזו התיקייה נראית שלמה
  /// כי הקטלוג שלם, והמחשב המנותק מגלה את החוסר רק כשמנסים להתקין.
  final List<String> missingPlugins;

  /// כמה תוספים יש בחנות ברשת — לתצוגה בלבד.
  final int totalOnline;

  int get newCount => newPlugins.length;
  int get updatedCount => updatedPlugins.length;
  int get missingCount => missingPlugins.length;
  bool get hasUpdates =>
      newPlugins.isNotEmpty ||
      updatedPlugins.isNotEmpty ||
      missingPlugins.isNotEmpty;
}
