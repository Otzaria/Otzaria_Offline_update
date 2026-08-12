import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';

/// תוצאת ניסיון פעולה מול מערכת ההפעלה — מוחזרת כערך ולא כחריג, בדיוק
/// כמו ב-`FileReveal` בלאנצ'ר: ה-UI מציג הודעה, לא stack trace.
class PluginInstallResult {
  const PluginInstallResult.ok()
      : success = true,
        error = null;
  const PluginInstallResult.failure(this.error) : success = false;

  final bool success;
  final String? error;
}

/// מתקין תוסף באוצריא דרך הפרוטוקול `otzaria://`.
///
/// **למה דווקא כך, ולא חילוץ ה-ZIP בעצמנו:** אוצריא מנהלת רישום פנימי
/// לתוספים המותקנים (מעבר לתיקיית `installed/`), ופרישה ידנית של הארכיון
/// עוקפת אותו. `install-local` קורא את הקובץ ישירות מהדיסק ולכן עובד
/// **בלי שום גישה לרשת** — זה בדיוק המסלול שהמחשב הלא-מקוון צריך.
/// (ה-`install?url=` הישן דורש אינטרנט ולכן אינו בשימוש כאן.)
///
/// כשידוע נתיב ההתקנה שהלאנצ'ר זיהה, ה-URL נמסר **לקובץ ההרצה עצמו**
/// ולא למערכת ההפעלה — ראו [openProtocolUrl].
abstract final class PluginDirectInstaller {
  /// [pluginFilePath] חייב להיות נתיב **מוחלט** לקובץ `.otzplugin` קיים.
  /// [otzariaLaunchPath] הוא ההתקנה שהלאנצ'ר זיהה, כשהיא ידועה.
  static Future<PluginInstallResult> install(
    String pluginFilePath, {
    String? otzariaLaunchPath,
  }) async {
    final strings = AppL10n.strings.pluginsDomain;
    if (!File(pluginFilePath).existsSync()) {
      return PluginInstallResult.failure(strings.localPluginFileMissing);
    }
    if (!pluginFilePath.toLowerCase().endsWith('.otzplugin')) {
      return PluginInstallResult.failure(strings.badPluginExtension);
    }

    return openProtocolUrl(
      installLocalUrl(pluginFilePath),
      otzariaLaunchPath: otzariaLaunchPath,
    );
  }

  /// ה-URL שנמסר למערכת ההפעלה. חשוף בנפרד כדי שבדיקות יאמתו אותו בלי
  /// להפעיל מטפל פרוטוקול אמיתי.
  static String installLocalUrl(String pluginFilePath) =>
      'otzaria://plugin/install-local?path=${Uri.encodeComponent(pluginFilePath)}';

  /// פותח כתובת דרך מטפל הפרוטוקול של מערכת ההפעלה. לא נעשה שימוש ב-
  /// `url_launcher` מאותה סיבה כמו ב-`FileReveal`: כאן רוצים בדיוק דבר
  /// אחד — למסור את ה-URL למערכת — וזה שונה בין הפלטפורמות.
  ///
  /// [otzariaLaunchPath] עוקף את מטפל הפרוטוקול ומריץ את ההתקנה שהלאנצ'ר
  /// זיהה עם ה-URL כארגומנט — **בדיוק** מה שהרישום ברג'יסטרי היה עושה
  /// (`"otzaria.exe" "%1"`). התקנה ניידת אינה רושמת את הסכימה `otzaria://`
  /// בכלל, ולכן בלי זה ההתקנה הישירה נכשלה שם ב"ודא שאוצריא מותקנת".
  static Future<PluginInstallResult> openProtocolUrl(
    String url, {
    String? otzariaLaunchPath,
  }) async {
    final strings = AppL10n.strings.pluginsDomain;
    try {
      final direct = await _openWithKnownInstall(url, otzariaLaunchPath);
      if (direct != null) return direct;

      if (Platform.isWindows) {
        // הארגומנט הריק הראשון הוא הכותרת של החלון עבור `start`; בלעדיו
        // `start` מפרש URL במרכאות ככותרת ולא פותח כלום.
        final result = await Process.run('cmd', ['/c', 'start', '', url]);
        if (result.exitCode != 0) {
          return PluginInstallResult.failure(
            '${strings.otzariaOpenFailedHint}(${result.stderr})',
          );
        }
        return const PluginInstallResult.ok();
      }

      if (Platform.isMacOS) {
        final result = await Process.run('/usr/bin/open', [url]);
        if (result.exitCode != 0) {
          return PluginInstallResult.failure(
            '${strings.otzariaOpenFailedHint}(${result.stderr})',
          );
        }
        return const PluginInstallResult.ok();
      }

      return PluginInstallResult.failure(
        strings.directInstallUnsupportedPlatform,
      );
    } catch (e) {
      return PluginInstallResult.failure(strings.otzariaOpenFailed('$e'));
    }
  }

  /// ההתקנה שאליה יימסר ה-URL, או `null` כשאין כזו ויש ליפול חזרה למטפל
  /// הפרוטוקול של מערכת ההפעלה: אין נתיב ידוע, או שהוא כבר לא קיים על
  /// הדיסק (אוצריא נמחקה/הכונן נותק מאז הזיהוי). חשוף בנפרד כדי שבדיקות
  /// יאמתו את ההכרעה בלי להריץ תהליך.
  static String? deliveryTargetFor(String? otzariaLaunchPath) {
    final path = otzariaLaunchPath;
    if (path == null || path.isEmpty) return null;
    final exists = path.toLowerCase().endsWith('.app')
        ? Directory(path).existsSync()
        : File(path).existsSync();
    return exists ? path : null;
  }

  /// מוסר את ה-URL להתקנה ידועה. `null` = אין למי למסור, ראו
  /// [deliveryTargetFor].
  static Future<PluginInstallResult?> _openWithKnownInstall(
    String url,
    String? otzariaLaunchPath,
  ) async {
    final launchPath = deliveryTargetFor(otzariaLaunchPath);
    if (launchPath == null) return null;
    final strings = AppL10n.strings.pluginsDomain;

    // חבילת `.app` היא תיקייה, ומריצים אותה דרך Launch Services — אותו
    // שיקול כמו ב-`OtzariaLauncher`. `open -a` מוסר את ה-URL לאפליקציה.
    if (launchPath.toLowerCase().endsWith('.app')) {
      final result = await Process.run('/usr/bin/open', [
        '-a',
        launchPath,
        url,
      ]);
      if (result.exitCode != 0) {
        return PluginInstallResult.failure(
          '${strings.otzariaOpenFailedHint}(${result.stderr})',
        );
      }
      return const PluginInstallResult.ok();
    }

    // מנותק: אוצריא נשארת פתוחה אחרי שהלאנצ'ר ייסגר, ו-`Process.run` היה
    // ממתין לה עד אז.
    await Process.start(
      launchPath,
      [url],
      mode: ProcessStartMode.detached,
    );
    return const PluginInstallResult.ok();
  }
}
