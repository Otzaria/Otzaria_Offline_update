/// תוצאת ההצצה הקלה לחנות שברשת: מה יש שם שאין במראה המקומית. מטא-דאטה
/// בלבד — שום קובץ אינו יורד בדרך, וכלום לא נכתב למראה.
class PluginsOnlineStatus {
  const PluginsOnlineStatus({
    this.newPlugins = const [],
    this.updatedPlugins = const [],
    this.missingPlugins = const [],
    this.removedPlugins = const [],
    this.totalOnline = 0,
    this.pendingBytes,
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

  final List<String> removedPlugins;

  final int totalOnline;

  /// גודל הבילדים שסנכרון יוריד; `null` כשלאחד מהם אין גודל בקטלוג.
  final int? pendingBytes;

  int get newCount => newPlugins.length;
  int get updatedCount => updatedPlugins.length;
  int get missingCount => missingPlugins.length;
  int get removedCount => removedPlugins.length;
  bool get hasUpdates =>
      newPlugins.isNotEmpty ||
      updatedPlugins.isNotEmpty ||
      missingPlugins.isNotEmpty ||
      removedPlugins.isNotEmpty;
}
