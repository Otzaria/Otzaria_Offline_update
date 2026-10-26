import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'app_logger.dart';

/// צילום מצב של תיקיות המראה **לפני** הורדה, וההחזרה שלו לאחור כשהמשתמש
/// ביטל אותה — כך שנמחק בדיוק מה שההורדה הזו הביאה.
///
/// **למה לא "מחק את תיקיית המראה":** על הכונן יושבים נכסים מהורדות קודמות
/// (המסד הדחוס לבדו ~1.5GB), ומחיקתם בגלל ביטול הייתה עולה למשתמש שעה של
/// הורדה מחדש. ולמה לא לספור קבצים בזמן ההורדה: זה היה מחייב callback חדש
/// דרך ארבע חבילות, כשהמידע כולו יושב על הדיסק ממילא.
class MirrorDownloadUndo {
  MirrorDownloadUndo._(this._roots, this._files, this._dirs, this._untouched);

  /// עד לאיזה גודל נשמר גם **התוכן** ולא רק הגודל. המניפסטים של המראה
  /// (`releases.json`, `companions.json`, `catalog.json`,
  /// `latest-release.json`) נכתבים מחדש בתוך ההורדה, וביטול שמחק נכסים אך
  /// השאיר מניפסט חדש היה משאיר מראה שמצביעה על קבצים שאינם שם.
  static const int _rememberedContentLimit = 4 << 20;

  /// התיקיות שצולמו — כל אחת נחשבת "לא הייתה קיימת" אם לא נמצאה בצילום.
  final List<({String path, bool existed})> _roots;
  final Map<String, _FileSnapshot> _files;
  final Set<String> _dirs;

  /// קבצים שהצילום לא הצליח לקרוא (נעולים/נעלמו באמצע) — [revert] לא נוגע
  /// בהם: מחיקה של קובץ שאיננו יודעים אם ההורדה הביאה היא הנזק היחיד כאן.
  final Set<String> _untouched;

  /// צילום של [rootDirs]. תיקייה שאינה קיימת היא מצב תקין ושכיח (הורדה
  /// ראשונה) — ביטול פשוט ימחק אותה כולה.
  static Future<MirrorDownloadUndo> capture(List<String> rootDirs) async {
    final (undo, notes) = await Isolate.run(() => _capture(rootDirs));
    notes.forEach(AppLogger.instance.info);
    return undo;
  }

  /// I/O סינכרוני על כל המראה — רץ ב-isolate, ולכן שורות הלוג מוחזרות
  /// ונכתבות בצד הראשי.
  static (MirrorDownloadUndo, List<String>) _capture(List<String> rootDirs) {
    final notes = <String>[];
    final roots = <({String path, bool existed})>[];
    final files = <String, _FileSnapshot>{};
    final dirs = <String>{};
    final untouched = <String>{};

    for (final rootDir in rootDirs) {
      final root = Directory(rootDir);
      final existed = root.existsSync();
      roots.add((path: rootDir, existed: existed));
      if (!existed) continue;

      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          dirs.add(entity.path);
          continue;
        }
        if (entity is! File) continue;
        try {
          final length = entity.lengthSync();
          files[entity.path] = _FileSnapshot(
            length: length,
            content: _remembersContent(entity.path, length)
                ? entity.readAsBytesSync()
                : null,
          );
        } catch (error) {
          untouched.add(entity.path);
          notes.add('Mirror snapshot could not read ${entity.path}: $error');
        }
      }
    }

    return (MirrorDownloadUndo._(roots, files, dirs, untouched), notes);
  }

  /// קובצי הצד של ההורדה (`.resume`, ומצב הטווחים `.segments`) נכתבים מחדש
  /// בכל ריצה — חיתוך לאורך הישן היה מותיר אותם קטועים ומאבד את החידוש.
  static const Set<String> _rememberedExtensions = {
    '.json',
    '.resume',
    '.segments',
  };

  static bool _remembersContent(String path, int length) =>
      _rememberedExtensions.contains(p.extension(path).toLowerCase()) &&
      length <= _rememberedContentLimit;

  /// [roots]: רק התיקיות האלה מוחזרות, והשאר נשארות כמו שההורדה השאירה
  /// אותן. `null` = כל מה שצולם.
  Future<void> revert({Iterable<String>? roots}) async {
    final undo = this;
    final only = roots?.toSet();
    final notes = await Isolate.run(() => undo._revert(only));
    notes.forEach(AppLogger.instance.info);
  }

  List<String> _revert(Set<String>? only) {
    final notes = <String>[];
    final retainedAssets = _consumedSegmentAssets();
    for (final root in _roots) {
      if (only != null && !only.contains(root.path)) continue;
      final dir = Directory(root.path);
      if (!dir.existsSync()) continue;
      if (!root.existed) {
        _revertInto(dir, notes, retainedAssets);
        _quietly(() {
          if (dir.listSync(followLinks: false).isEmpty) dir.deleteSync();
        }, root.path, notes);
        continue;
      }
      if (_lostFileUnder(root.path, retainedAssets) case final lost?) {
        notes.add('Cancel keeps ${root.path}: $lost was pruned');
        continue;
      }
      _revertInto(dir, notes, retainedAssets);
    }
    return notes;
  }

  static final RegExp _segmentSuffix = RegExp(r'\.seg-\d+$');

  // טווח שנמחק כבר נמצא בתוך הנכס; חיתוך הנכס יאבד גם בתים קודמים.
  // שומרים את כל משפחתו יחד, כולל מצב ההורדה העדכני, בלי להעתיק נכסים.
  Set<String> _consumedSegmentAssets() {
    final retained = <String>{};
    for (final path in _files.keys) {
      if (!_segmentSuffix.hasMatch(path) || File(path).existsSync()) continue;
      final asset = path.replaceFirst(_segmentSuffix, '');
      if (retained.contains(asset)) continue;
      final sidecar = '$asset.resume';
      final oldContent = _files[sidecar]?.content;
      if (oldContent == null || !File(asset).existsSync()) continue;
      try {
        final oldToken = utf8.decode(oldContent).split('\n').first;
        final current = File(sidecar);
        if (oldToken.isNotEmpty &&
            current.lengthSync() <= _rememberedContentLimit &&
            current.readAsLinesSync().first == oldToken) {
          retained.add(asset);
        }
      } catch (_) {
        // בלי זהות ניתנת לאימות, השורש נשמר כולו ולא מוחזר מניפסט ישן.
      }
    }
    return retained;
  }

  static bool _belongsToAsset(String path, Set<String> assets) {
    if (assets.contains(path)) return true;
    if (path.endsWith('.resume')) {
      return assets.contains(path.substring(0, path.length - '.resume'.length));
    }
    final suffix = _downloadSideFile.firstMatch(path);
    return suffix != null && assets.contains(path.substring(0, suffix.start));
  }

  String? _lostFileUnder(String rootPath, Set<String> retainedAssets) {
    for (final path in _files.keys) {
      if (_belongsToAsset(path, retainedAssets)) continue;
      if (_isDownloadSideFile(path) && !_segmentSuffix.hasMatch(path)) continue;
      if (p.isWithin(rootPath, path) && !File(path).existsSync()) return path;
    }
    return null;
  }

  /// קובצי הצד של נכס: טווחים, מצב הטווחים ונעילה.
  static final RegExp _downloadSideFile =
      RegExp(r'\.(seg-\d+|segments|segments\.tmp|lock)$', caseSensitive: false);

  static bool _isDownloadSideFile(String path) =>
      _downloadSideFile.hasMatch(p.basename(path));

  static const Set<String> _keptFileNames = {
    LibraryMirrorExporter.rejectedSplitsFileName,
  };

  static bool _isKept(Directory root, String path) =>
      p.equals(p.dirname(path), root.path) &&
      _keptFileNames.contains(p.basename(path));

  void _revertInto(
      Directory root, List<String> notes, Set<String> retainedAssets) {
    final files = <File>[];
    final newDirs = <String>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        if (!_dirs.contains(entity.path)) newDirs.add(entity.path);
      } else if (entity is File) {
        files.add(entity);
      }
    }

    for (final file in files) {
      // A lock's inode must outlive every downloader holding it.
      if (p.extension(file.path).toLowerCase() == '.lock' ||
          _untouched.contains(file.path) ||
          _isKept(root, file.path) ||
          _belongsToAsset(file.path, retainedAssets)) {
        continue;
      }
      final before = _files[file.path];
      if (before == null) {
        _quietly(() => file.deleteSync(), file.path, notes);
        continue;
      }
      _quietly(() => before.restoreInto(file), file.path, notes);
    }

    for (final MapEntry(key: path, value: before) in _files.entries) {
      final content = before.content;
      if (_belongsToAsset(path, retainedAssets) ||
          content == null ||
          !_isDownloadSideFile(path) ||
          !p.isWithin(root.path, path) ||
          File(path).existsSync()) {
        continue;
      }
      _quietly(
        () => File(path).writeAsBytesSync(content, flush: true),
        path,
        notes,
      );
    }

    newDirs.sort((a, b) => b.length.compareTo(a.length));
    for (final dir in newDirs) {
      _quietly(() {
        final directory = Directory(dir);
        if (directory.listSync(followLinks: false).isEmpty) {
          directory.deleteSync();
        }
      }, dir, notes);
    }
  }

  void _quietly(void Function() action, String path, List<String> notes) {
    try {
      action();
    } catch (error) {
      notes.add('Cancel cleanup skipped $path: $error');
    }
  }
}

/// מצבו של קובץ בודד לפני ההורדה. [content] קיים רק למניפסטים — ראו
/// [MirrorDownloadUndo._rememberedContentLimit].
class _FileSnapshot {
  const _FileSnapshot({required this.length, this.content});

  final int length;
  final Uint8List? content;

  void restoreInto(File file) {
    final content = this.content;
    if (content != null) {
      file.writeAsBytesSync(content, flush: true);
      return;
    }
    final now = file.lengthSync();
    // קצר מכפי שהיה = ההורדה מחקה את הנכס והתחילה לכתוב אותו מאפס (טוקן
    // שאינו תואם, או 200 במקום 206). התוכן הישן איננו ואין לנו במה להחזירו,
    // ולכן משאירים "לא קיים" ולא חתיכה זרה תחת המניפסט הישן — שהיה נראה
    // כמראה שלמה ונופל באימות ה-sha256 רק במחשב המנותק.
    if (now < length) {
      file.deleteSync();
      return;
    }
    if (now == length) return;
    final handle = file.openSync(mode: FileMode.append);
    try {
      handle.truncateSync(length);
    } finally {
      handle.closeSync();
    }
  }
}
