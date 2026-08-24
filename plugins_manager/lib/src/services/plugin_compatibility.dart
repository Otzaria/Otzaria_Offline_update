/// בחירת בילד התוסף המתאים לגרסת אוצריא נתונה — פורט של
/// `src/lib/pluginCompatibility.js` באתר, כדי שהמראה האופליינית תביא בדיוק
/// את מה שהאתר היה נותן לאותו משתמש.
///
/// לכל בילד יש טווח: `compatibleWith` (מינימום) ו-`maxAppVersion` (תקרה).
/// נבחר **הבילד הגבוה ביותר שגרסת אוצריא נופלת בטווח שלו** — כך שמחשב עם
/// אוצריא ישנה מקבל את האחרון שעוד תמך בו, במקום בילד שלא יעלה אצלו.
///
/// הפונקציות כאן עובדות על רשימת בילדים ולא על `StorePlugin`, כדי שהמודל
/// יוכל להשתמש בהן בלי ייבוא מעגלי.
library;

import '../models/plugin_version_entry.dart';
import 'plugin_version_compare.dart';

/// האם [appVersion] נופלת בטווח התאימות של [entry].
///
/// שדה חסר = גבול פתוח. בילדים היסטוריים שאורכבו לפני שנשמרו שדות התאימות
/// מגיעים עם `compatibleWith` ריק, ואין לפסול אותם בגלל נתון חסר. גם
/// [appVersion] ריקה (לא ידוע מה מותקן) אינה פוסלת דבר.
bool isCompatibleWithApp(PluginVersionEntry entry, String? appVersion) {
  if (appVersion == null || appVersion.isEmpty) return true;
  if (entry.compatibleWith.isNotEmpty &&
      comparePluginVersions(appVersion, entry.compatibleWith) < 0) {
    return false;
  }
  final max = entry.maxAppVersion;
  if (max != null &&
      max.isNotEmpty &&
      comparePluginVersions(appVersion, max) > 0) {
    return false;
  }
  return true;
}

/// הבילד הגבוה ביותר מתוך [entries] שתואם ל-[appVersion], או `null` כשאין
/// כזה. [entries] חייבת להיות ממוינת יורד — `StorePlugin` דואג לכך.
PluginVersionEntry? resolveCompatibleVersion(
  List<PluginVersionEntry> entries,
  String? appVersion,
) {
  for (final entry in entries) {
    if (isCompatibleWithApp(entry, appVersion)) return entry;
  }
  return null;
}

/// הבילדים שצריכים לרדת למראה עבור [appVersions] — אחד לכל גרסת אוצריא
/// שהכונן נושא, בלי כפילות כששתיהן נפתרות לאותו בילד.
///
/// רשימת גרסאות ריקה = אין מול מה לסנן (מראת תוכנה ריקה), ואז יורד הבילד
/// החי בלבד: בדיוק ההתנהגות שהייתה לפני שהתאימות נכנסה.
List<PluginVersionEntry> resolveTargets(
  List<PluginVersionEntry> entries,
  List<String> appVersions,
) {
  if (entries.isEmpty) return const [];
  if (appVersions.isEmpty) return [entries.first];

  final targets = <String, PluginVersionEntry>{};
  for (final appVersion in appVersions) {
    final entry = resolveCompatibleVersion(entries, appVersion);
    if (entry != null) targets[entry.version] = entry;
  }
  return targets.values.toList(growable: false);
}

/// גרסת האוצריא הנמוכה ביותר שעדיין מריצה בילד כלשהו — הרצפה הנמוכה מכל
/// הבילדים, ולא זו של החי. מאפשר לומר למי שאין לו גרסה תואמת מה הוא באמת
/// צריך, במקום את דרישת הבילד האחרון שהיא לרוב גבוהה יותר.
///
/// `null` כשלבילד כלשהו אין רצפה בכלל — ואז "אוצריא ישנה מדי" אינו ההסבר.
String? lowestSupportedAppVersion(List<PluginVersionEntry> entries) {
  String? lowest;
  for (final entry in entries) {
    if (entry.compatibleWith.isEmpty) return null;
    if (lowest == null ||
        comparePluginVersions(entry.compatibleWith, lowest) < 0) {
      lowest = entry.compatibleWith;
    }
  }
  return lowest;
}
