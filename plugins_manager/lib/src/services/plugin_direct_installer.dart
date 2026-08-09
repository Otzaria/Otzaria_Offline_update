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
abstract final class PluginDirectInstaller {
  /// [pluginFilePath] חייב להיות נתיב **מוחלט** לקובץ `.otzplugin` קיים.
  static Future<PluginInstallResult> install(String pluginFilePath) async {
    final strings = AppL10n.strings.pluginsDomain;
    if (!File(pluginFilePath).existsSync()) {
      return PluginInstallResult.failure(strings.localPluginFileMissing);
    }
    if (!pluginFilePath.toLowerCase().endsWith('.otzplugin')) {
      return PluginInstallResult.failure(strings.badPluginExtension);
    }

    final url =
        'otzaria://plugin/install-local?path=${Uri.encodeComponent(pluginFilePath)}';
    return openProtocolUrl(url);
  }

  /// פותח כתובת דרך מטפל הפרוטוקול של מערכת ההפעלה. לא נעשה שימוש ב-
  /// `url_launcher` מאותה סיבה כמו ב-`FileReveal`: כאן רוצים בדיוק דבר
  /// אחד — למסור את ה-URL למערכת — וזה שונה בין הפלטפורמות.
  static Future<PluginInstallResult> openProtocolUrl(String url) async {
    final strings = AppL10n.strings.pluginsDomain;
    try {
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
}
