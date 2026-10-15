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

  Future<void> revert() async {
    final undo = this;
    final notes = await Isolate.run(() => undo._revert());
    notes.forEach(AppLogger.instance.info);
  }

  List<String> _revert() {
    final notes = <String>[];
    for (final root in _roots) {
      final dir = Directory(root.path);
      if (!dir.existsSync()) continue;
      if (!root.existed) {
        if (_keepsFileUnder(root.path)) {
          _revertInto(dir, notes);
        } else {
          _quietly(() => dir.deleteSync(recursive: true), root.path, notes);
        }
        continue;
      }
      if (_lostFileUnder(root.path) case final lost?) {
        notes.add('Cancel keeps ${root.path}: $lost was pruned');
        continue;
      }
      _revertInto(dir, notes);
    }
    return notes;
  }

  String? _lostFileUnder(String rootPath) {
    for (final path in _files.keys) {
      if (p.isWithin(rootPath, path) && !File(path).existsSync()) return path;
    }
    return null;
  }

  static const Set<String> _keptFileNames = {
    LibraryMirrorExporter.rejectedSplitsFileName,
  };

  static bool _isKept(Directory root, String path) =>
      p.equals(p.dirname(path), root.path) &&
      _keptFileNames.contains(p.basename(path));

  bool _keepsFileUnder(String rootPath) =>
      _keptFileNames.any((name) => File(p.join(rootPath, name)).existsSync());

  void _revertInto(Directory root, List<String> notes) {
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
      if (_untouched.contains(file.path) || _isKept(root, file.path)) continue;
      final before = _files[file.path];
      if (before == null) {
        _quietly(() => file.deleteSync(), file.path, notes);
        continue;
      }
      _quietly(() => before.restoreInto(file), file.path, notes);
    }

    newDirs.sort((a, b) => b.length.compareTo(a.length));
    for (final dir in newDirs) {
      _quietly(() => Directory(dir).deleteSync(recursive: true), dir, notes);
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
