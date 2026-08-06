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
/// <mirrorDir>/plugins/files/<pluginId>/{image.*, screenshot-N.*, plugin.otzplugin}
/// ```
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

  /// האם קובץ ה-`.otzplugin` של [plugin] קיים בפועל על הדיסק.
  Future<bool> hasLocalFile(StorePlugin plugin) async {
    final local = plugin.localFile;
    if (local == null) return false;
    return File(absolutePath(local.relativePath)).exists();
  }
}
