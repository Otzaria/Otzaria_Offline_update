import 'dart:convert';
import 'dart:io';

import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// קובץ או תיקייה שאף מניפסט במראה אינו מזכיר עוד.
class MirrorJunk {
  const MirrorJunk({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

/// מוחק מהמראה את מה שאף מניפסט אינו מזכיר — **בשקט, בסוף כל הורדה**.
///
/// כל רכיב מנקה כבר אחרי עצמו, אבל רק בתוך הורדה שהביאה לו משהו: רכיב
/// שדילגו עליו ("אין חדש") או שהייצוא שלו חזר "אין מה לעדכן" אינו מנקה
/// כלום, ולכן כונן שנקלע פעם אחת למצב רע נשאר איתו לנצח — פורום #310
/// (שני מסדים מלאים זה לצד זה) ו-#418 (5GB). גם תוסף שהוסר מהחנות ונכס
/// נלווה שהוחלף אינם מכוסים על ידי אף ניקוי קיים.
///
/// **מניפסט שלא נקרא פירושו דילוג על האזור כולו.** קבוצת שמירה ריקה היא
/// "מחק הכול", וזו בדיוק התקלה שהמראות האחרות כבר נשמרות ממנה (ראו
/// `OtzariaAppMirror.sync`). מאותה סיבה `mirror/apps` (תוכנות שהמשתמש
/// הוסיף) ו-`otzaria-app/` (התקנה חיה) אינם נגעים כאן לעולם.
class MirrorJunkSweeper {
  const MirrorJunkSweeper({required this.dataDir});

  /// `OtzariaData` שלצד קובץ ההרצה — ראו `AppPaths.dataDir`.
  final String dataDir;

  String get _mirrorDir => p.join(dataDir, 'mirror');

  /// מוצא ומוחק. מחזיר כמה בייטים פונו בפועל, ואינו זורק לעולם — ניקוי
  /// שנכשל אינו סיבה להפוך הורדה שהצליחה לשגיאה על המסך.
  Future<int> sweep() async {
    var freed = 0;
    for (final item in await find()) {
      try {
        final dir = Directory(item.path);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          freed += item.bytes;
          continue;
        }
        final file = File(item.path);
        if (await file.exists()) {
          await file.delete();
          freed += item.bytes;
        }
      } catch (_) {
        // קובץ נעול (אנטי-וירוס, העתקה שרצה) — יימחק בניקוי הבא.
      }
    }
    return freed;
  }

  /// מה ייחשב זבל. חשוף כדי שהבדיקות יראו את ההחלטה עצמה, בלי למחוק.
  Future<List<MirrorJunk>> find() async {
    final out = <MirrorJunk>[];
    try {
      await _libraryJunk(out);
      await _companionJunk(out);
      await _appJunk(out);
      await _pluginJunk(out);
      await _launcherJunk(out);
    } catch (_) {
      // כונן שנשלף באמצע סריקה — מוחקים את מה שכבר זוהה, ולא נופלים.
    }
    return out;
  }

  // ── ספרייה ────────────────────────────────────────────────────────────────

  /// נכס שאינו ב-`releases.json` לא ייקרא לעולם — זה מה שהשאיר מסד מלא של
  /// גרסה ישנה על הכונן לצד החדש.
  Future<void> _libraryJunk(List<MirrorJunk> out) async {
    final mirrorDir = p.join(_mirrorDir, 'library');
    final assetsRoot = Directory(p.join(mirrorDir, 'assets'));
    if (!await assetsRoot.exists()) return;

    final List<LibraryRelease> releases;
    try {
      releases = await LocalMirrorLibraryReleaseClient(mirrorDir: mirrorDir)
          .fetchReleases();
    } catch (_) {
      return;
    }
    if (releases.isEmpty) return;

    final keep = <String>{};
    for (final release in releases) {
      for (final asset in release.assets) {
        // במראה מקומית `downloadUrl` הוא כבר נתיב מוחלט לקובץ.
        keep.add(_key(asset.downloadUrl));
        // קובץ הצד הוא חלק מזהות הנכס — ראו `PatchDownloader.resumeSidecarPath`.
        keep.add(_key(PatchDownloader.resumeSidecarPath(asset.downloadUrl)));
      }
    }

    await for (final entity in assetsRoot.list(followLinks: false)) {
      if (entity is! Directory) {
        out.add(await _junkOf(entity));
        continue;
      }
      await _unkeptWithin(entity, keep, out);
    }
  }

  // ── נלווים ────────────────────────────────────────────────────────────────

  /// נכס נלווה שהוחלף (הקטלוג עבר מ-`.db` ל-`.db.zst`) משאיר את הקודם שם,
  /// ו-`CompanionAssetsMirror` אינו מוחק דבר.
  Future<void> _companionJunk(List<MirrorJunk> out) async {
    final dir = Directory(p.join(_mirrorDir, 'companions'));
    if (!await dir.exists()) return;

    final manifest = await CompanionMirrorManifest.load(dir.path);
    if (manifest == null || manifest.isEmpty) return;

    final keep = <String>{
      _key(p.join(dir.path, CompanionMirrorManifest.fileName)),
    };
    for (final entry in manifest.entries.values) {
      if (entry.fileName.isEmpty) continue;
      final path = p.join(dir.path, entry.fileName);
      keep.add(_key(path));
      keep.add(_key(PatchDownloader.resumeSidecarPath(path)));
    }

    await _unkeptWithin(dir, keep, out, wholeDirWhenNothingKept: false);
  }

  // ── תוכנת אוצריא ──────────────────────────────────────────────────────────

  /// תג שאינו במטא־דאטה, וגם חבילת FULL שנשארה בתג שכן נשמר.
  Future<void> _appJunk(List<MirrorJunk> out) async {
    final root = Directory(p.join(_mirrorDir, 'app', 'installers'));
    if (!await root.exists()) return;

    final meta =
        await _readJson(p.join(_mirrorDir, 'app', 'latest-release.json'));
    if (meta == null) return;

    // הפורמט הישן הוא רשומה בודדת בשורש; החדש — רשומה לכל ערוץ.
    final entries = meta['tagName'] is String
        ? [meta]
        : [meta['stable'], meta['prerelease']]
            .whereType<Map<String, dynamic>>();

    final keptFiles = <String, Set<String>>{};
    for (final entry in entries) {
      final tag = entry['tagName'];
      final relative = entry['installerPath'];
      if (tag is! String || tag.isEmpty) continue;
      keptFiles
          .putIfAbsent(_key(tag), () => {})
          .add(relative is String ? _key(_baseName(relative)) : '');
    }
    if (keptFiles.isEmpty) return;

    await _byTagDir(root, keptFiles, out);
  }

  // ── תוספים ────────────────────────────────────────────────────────────────

  /// תוסף שהוסר מהחנות משאיר את כל תיקייתו: `pruneUnusedFiles` רץ רק על
  /// תוספים שעדיין בקטלוג, ולכן אינו יכול לראות אותה.
  Future<void> _pluginJunk(List<MirrorJunk> out) async {
    final store = PluginMirrorStore(_mirrorDir);
    final root = Directory(store.filesDir);
    if (!await root.exists()) return;

    final catalog = await store.load();
    if (catalog.plugins.isEmpty) return;

    final keptDirs = <String>{};
    final keep = <String>{};
    for (final plugin in catalog.plugins) {
      keptDirs.add(_key(plugin.id));
      for (final relative in [
        if (plugin.imagePath case final path?) path,
        ...plugin.screenshotPaths,
        for (final file in plugin.localFiles.values) file.relativePath,
      ]) {
        keep.add(_key(store.absolutePath(relative)));
      }
    }

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory ||
          !keptDirs.contains(_key(p.basename(entity.path)))) {
        out.add(await _junkOf(entity));
        continue;
      }
      await _unkeptWithin(entity, keep, out, wholeDirWhenNothingKept: false);
    }
  }

  // ── הלאנצ'ר עצמו ──────────────────────────────────────────────────────────

  Future<void> _launcherJunk(List<MirrorJunk> out) async {
    final root = Directory(p.join(_mirrorDir, 'launcher', 'files'));
    if (!await root.exists()) return;

    final meta =
        await _readJson(p.join(_mirrorDir, 'launcher', 'latest-release.json'));
    final release = meta?['release'];
    if (release is! Map<String, dynamic>) return;
    final tag = release['tagName'];
    if (tag is! String || tag.isEmpty) return;
    final relative = meta?['filePath'];

    await _byTagDir(
      root,
      {
        _key(tag): {relative is String ? _key(_baseName(relative)) : ''},
      },
      out,
    );
  }

  // ── עזר ───────────────────────────────────────────────────────────────────

  /// תיקיות שנקראות על שם תג: תג שאינו נשמר יורד כולו, ובתג שכן — כל קובץ
  /// שאינו זה שהמטא־דאטה מצביעה עליו.
  Future<void> _byTagDir(
    Directory root,
    Map<String, Set<String>> keptFilesByTag,
    List<MirrorJunk> out,
  ) async {
    await for (final entity in root.list(followLinks: false)) {
      final keep = keptFilesByTag[_key(p.basename(entity.path))];
      if (entity is! Directory || keep == null) {
        out.add(await _junkOf(entity));
        continue;
      }
      await for (final file in entity.list(followLinks: false)) {
        if (!keep.contains(_key(p.basename(file.path)))) {
          out.add(await _junkOf(file));
        }
      }
    }
  }

  /// כל מה שב-[dir] ואינו ב-[keep]. כשאף קובץ בתיקייה אינו נשמר — התיקייה
  /// עצמה היא הזבל, כדי שלא יישאר על הכונן שלד ריק של תגים.
  Future<void> _unkeptWithin(
    Directory dir,
    Set<String> keep,
    List<MirrorJunk> out, {
    bool wholeDirWhenNothingKept = true,
  }) async {
    final unkept = <FileSystemEntity>[];
    var kept = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (keep.contains(_key(entity.path))) {
        kept++;
      } else {
        unkept.add(entity);
      }
    }
    if (unkept.isEmpty) return;
    if (kept == 0 && wholeDirWhenNothingKept) {
      out.add(await _junkOf(dir));
      return;
    }
    for (final entity in unkept) {
      out.add(await _junkOf(entity));
    }
  }

  Future<MirrorJunk> _junkOf(FileSystemEntity entity) async =>
      MirrorJunk(path: entity.path, bytes: await _sizeOf(entity));

  /// נתיב שנשמר במניפסט נכתב תמיד עם `/`, גם כשהוא נקרא בווינדוס.
  static String _baseName(String path) =>
      p.basename(path.replaceAll(r'\', '/'));

  /// השוואת נתיבים מנורמלת וללא תלות ברישיות — אותו קובץ על כונן ווינדוס
  /// מגיע בשתי כתיבות שונות.
  static String _key(String path) => p.normalize(path).toLowerCase();

  static Future<Map<String, dynamic>?> _readJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<int> _sizeOf(FileSystemEntity entity) async {
    try {
      if (entity is File) return await entity.length();
      if (entity is! Directory) return 0;
      var total = 0;
      await for (final child
          in entity.list(recursive: true, followLinks: false)) {
        if (child is File) {
          try {
            total += await child.length();
          } catch (_) {
            // קובץ שנעלם בין הרשימה למדידה — לא נספר.
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
