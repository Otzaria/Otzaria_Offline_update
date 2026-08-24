import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/plugin_catalog.dart';
import '../models/store_plugin.dart';

/// שכבת האחסון של החנות בתוך המראה האופליינית.
///
/// המבנה נשמר **בתוך** תיקיית המראה הקיימת של הספרייה, כך שהעתקה אחת
/// ל-USB מעבירה גם ספרייה וגם תוספים:
///
/// ```
/// <mirrorDir>/plugins/catalog.json
/// <mirrorDir>/plugins/files/<pluginId>/{image.*, screenshot-N.*, plugin-<version>.otzplugin}
/// ```
///
/// **קובץ לכל בילד**, כי הכונן נושא עד שתי גרסאות של אוצריא ולכל אחת עשוי
/// להתאים בילד אחר של אותו תוסף. `plugin.otzplugin` בלי גרסה הוא השם הישן
/// ונשאר קריא — ראו `StorePlugin.fromJson`.
///
/// כל הנתיבים בקטלוג נשמרים **יחסית** ל-`plugins/`, כדי שהמראה תעבוד גם
/// כשהיא נפתחת מאות כונן אחרת.
class PluginMirrorStore {
  const PluginMirrorStore(this.mirrorDir);

  /// שורש המראה — `<dataDir>/mirror` בלאנצ'ר, כלומר שכנה של מראת הספרייה
  /// ושל מראת התוכנה תחת אותה תיקייה שצמודה לקובץ ההרצה.
  final String mirrorDir;

  static const String catalogFileName = 'catalog.json';

  String get pluginsDir => p.join(mirrorDir, 'plugins');
  String get filesDir => p.join(pluginsDir, 'files');
  String get catalogPath => p.join(pluginsDir, catalogFileName);

  String pluginDir(String pluginId) => p.join(filesDir, pluginId);

  /// נתיב מוחלט לנכס שנשמר בקטלוג כנתיב יחסי.
  String absolutePath(String relativePath) =>
      resolveAgainst(pluginsDir, relativePath);

  /// הנתיב היחסי שיש לשמור בקטלוג עבור קובץ מוחלט שירד. **תמיד עם `/`**,
  /// כדי שקטלוג שנכתב בווינדוס ייקרא נכון גם כשהמראה נפתחת ב-macOS.
  String relativePath(String absolute) =>
      p.relative(absolute, from: pluginsDir).replaceAll(r'\', '/');

  /// מרכיב נתיב מוחלט מנתיב יחסי בסגנון POSIX שנשמר בקטלוג. חשוף כ-static
  /// כדי שגם שכבת ה-UI תוכל לבנות נתיבי תמונות בלי לגשת לדיסק.
  static String resolveAgainst(String root, String relativePath) =>
      p.joinAll([root, ...relativePath.split('/').where((s) => s.isNotEmpty)]);

  Future<void> ensureDirs() async {
    await Directory(filesDir).create(recursive: true);
  }

  /// קורא את הקטלוג. קובץ חסר או פגום מחזיר קטלוג ריק — זה המצב התקין
  /// לפני הסנכרון הראשון.
  Future<PluginCatalog> load() async {
    try {
      final file = File(catalogPath);
      if (!await file.exists()) return PluginCatalog.empty;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return PluginCatalog.empty;
      return PluginCatalog.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return PluginCatalog.empty;
    }
  }

  /// כתיבה אטומית (קובץ זמני + rename), כמו ב-`SettingsStore` — כדי
  /// שניתוק באמצע כתיבה לא ישאיר קטלוג חצי-כתוב.
  Future<void> save(PluginCatalog catalog) async {
    await ensureDirs();
    final tmp = File('$catalogPath.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(catalog.toJson()),
    );
    await tmp.rename(catalogPath);
  }

  /// האם הנכס (תמונה / צילום מסך) שנשמר בקטלוג קיים בפועל על הדיסק.
  Future<bool> hasAsset(String? relativePath) async =>
      relativePath != null &&
      relativePath.isNotEmpty &&
      await File(absolutePath(relativePath)).exists();

  /// האם הקובץ של בילד מסוים קיים בפועל על הדיסק.
  Future<bool> hasFileFor(StorePlugin plugin, String? version) =>
      hasAsset(plugin.localFileFor(version)?.relativePath);

  /// שם הקובץ (בלי סיומת) של בילד מסוים בתוך תיקיית התוסף. הגרסה נכנסת
  /// לשם כדי ששני בילדים של אותו תוסף יוכלו לשכון זה לצד זה.
  String pluginFilePathNoExt(String pluginId, String version) =>
      p.join(pluginDir(pluginId), 'plugin-${sanitizeVersion(version)}');

  /// גרסאות תוסף הן semver ולכן בטוחות לשמות קבצים, אבל שם קובץ נבנה כאן
  /// מנתון שמגיע מהרשת — כל מה שאינו אות/ספרה/`.`/`-`/`+` מוחלף.
  static String sanitizeVersion(String version) =>
      version.replaceAll(RegExp(r'[^A-Za-z0-9.+_-]'), '_');

  /// מוחק קובצי בילד שכבר אינם בקטלוג — כשגרסת אוצריא שבכונן זזה, הבילד
  /// שהתאים לקודמת אינו נחוץ עוד, וכונן נייד אינו המקום לצבור אותם.
  /// מחזיר כמה נמחקו.
  Future<int> pruneUnusedFiles(StorePlugin plugin) async {
    final dir = Directory(pluginDir(plugin.id));
    if (!await dir.exists()) return 0;

    final keep = {
      for (final file in plugin.localFiles.values)
        p.normalize(absolutePath(file.relativePath)).toLowerCase(),
    };
    var removed = 0;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = p.basename(entry.path).toLowerCase();
      if (!name.startsWith('plugin')) continue;
      if (keep.contains(p.normalize(entry.path).toLowerCase())) continue;
      try {
        await entry.delete();
        removed++;
      } catch (_) {
        // קובץ נעול (אנטי-וירוס, העתקה שרצה) — לא סיבה להפיל סנכרון.
      }
    }
    return removed;
  }
}
