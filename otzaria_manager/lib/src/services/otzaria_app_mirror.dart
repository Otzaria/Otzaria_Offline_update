import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/otzaria_release.dart';
import 'otzaria_installer.dart';
import 'otzaria_release_client.dart';

/// גרסת אוצריא שיושבת מוכנה בתיקייה המקומית: המטא־דאטה שלה וקובץ ההתקנה
/// שכבר הורד.
class MirroredOtzariaRelease {
  const MirroredOtzariaRelease({
    required this.release,
    required this.installerPath,
  });

  final OtzariaRelease release;

  /// נתיב מלא לקובץ ההתקנה בדיסק — ההתקנה קוראת מכאן, בלי רשת.
  final String installerPath;
}

/// המראה המקומית של **תוכנת אוצריא עצמה**: קובץ ההתקנה של הגרסה האחרונה
/// יחד עם המטא־דאטה שלה, בתיקייה שלצד הלאנצ'ר.
///
/// בלי המטא־דאטה המקומית, בדיקת גרסה הייתה חייבת לפנות ל-GitHub — ובמחשב
/// בלי רשת מודול התוכנה היה פשוט נכשל. עם המראה, [load] עונה מהדיסק
/// ו-[sync] היא הפעולה היחידה שנוגעת ברשת.
class OtzariaAppMirror {
  OtzariaAppMirror({
    required this.mirrorDir,
    required OtzariaReleaseClient releaseClient,
    required OtzariaInstaller installer,
  })  : _releaseClient = releaseClient,
        _installer = installer;

  /// `<dataDir>/mirror/app` — נוסע עם התוכנה על הכונן הנייד.
  final String mirrorDir;

  final OtzariaReleaseClient _releaseClient;
  final OtzariaInstaller _installer;

  static const String _metadataFileName = 'latest-release.json';

  String get _metadataPath => p.join(mirrorDir, _metadataFileName);

  /// קורא את הגרסה שיושבת במראה, או `null` אם אין מראה תקינה: אין קובץ
  /// מטא־דאטה, הוא פגום, או שקובץ ההתקנה שהוא מצביע עליו חסר/בגודל שגוי
  /// (הורדה שנקטעה). בכל המקרים האלה התשובה הנכונה זהה — "צריך להוריד".
  Future<MirroredOtzariaRelease?> load() async {
    final file = File(_metadataPath);
    if (!await file.exists()) return null;

    final OtzariaRelease release;
    final String installerPath;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      release = OtzariaRelease.fromJson(decoded);
      final relative = decoded['installerPath'];
      if (relative is! String || relative.isEmpty) return null;
      // המראה נכתבת ב-POSIX ונקראת גם ב-Windows; `\` היסטורי מקובץ שנכתב
      // בווינדוס עדיין נתמך כדי לא לפסול מראה קיימת.
      installerPath =
          p.joinAll([mirrorDir, ...relative.split(RegExp(r'[/\\]'))]);
    } catch (_) {
      return null;
    }

    final installer = File(installerPath);
    if (!await installer.exists()) return null;
    if (await installer.length() != release.installerSizeBytes) return null;

    return MirroredOtzariaRelease(
      release: release,
      installerPath: installerPath,
    );
  }

  /// מוריד את הגרסה האחרונה בערוץ המבוקש אל [mirrorDir] וכותב את
  /// המטא־דאטה. **הפעולה היחידה כאן שדורשת אינטרנט.**
  ///
  /// המטא־דאטה נכתבת רק אחרי שקובץ ההתקנה כבר בדיסק במלואו, כדי ש-[load]
  /// לא תראה אף פעם מראה חצי-מוכנה.
  Future<MirroredOtzariaRelease> sync({
    required bool allowPrerelease,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final release = await _releaseClient.fetchLatestRelease(
      allowPrerelease: allowPrerelease,
    );

    final installerPath = await _installer.ensureCached(
      release: release,
      onDownloadProgress: onDownloadProgress,
    );

    await Directory(mirrorDir).create(recursive: true);
    final json = release.toJson()
      // **תמיד עם `/`** — מראה שנבנתה בווינדוס נפתחת גם ב-macOS, בדיוק כמו
      // הנתיבים בקטלוג התוספים (`PluginMirrorStore.relativePath`).
      ..['installerPath'] =
          p.relative(installerPath, from: mirrorDir).replaceAll(r'\', '/')
      ..['syncedAt'] = DateTime.now().toIso8601String();

    // כתיבה אטומית — הפסקת חשמל לא תשאיר JSON חצי־כתוב שייקרא כמראה תקינה.
    final temp = File('$_metadataPath.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    await temp.rename(_metadataPath);

    return MirroredOtzariaRelease(
      release: release,
      installerPath: installerPath,
    );
  }
}
