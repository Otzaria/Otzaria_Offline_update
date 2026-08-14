import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

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
    final roots = <({String path, bool existed})>[];
    final files = <String, _FileSnapshot>{};
    final dirs = <String>{};
    final untouched = <String>{};

    for (final rootDir in rootDirs) {
      final root = Directory(rootDir);
      final existed = root.existsSync();
      roots.add((path: rootDir, existed: existed));
      if (!existed) continue;

      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
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
          AppLogger.instance
              .info('צילום המראה לא קרא את ${entity.path}: $error');
        }
      }
    }

    return MirrorDownloadUndo._(roots, files, dirs, untouched);
  }

  static bool _remembersContent(String path, int length) =>
      p.extension(path).toLowerCase() == '.json' &&
      length <= _rememberedContentLimit;

  /// מחזיר את התיקיות למצב שבו היו: קובץ שנוצר נמחק, קובץ שנכתב מחדש
  /// (מניפסט) מוחזר לתוכנו, וקובץ שההורדה רק הוסיפה לסופו (נכס חלקי שהמשיכה)
  /// נחתך חזרה לאורכו — כך שהוא נשאר ניתן לחידוש בהורדה הבאה.
  ///
  /// כל פעולה היא best-effort: קובץ נעול לא מפיל את שאר הניקוי.
  Future<void> revert() async {
    for (final root in _roots) {
      final dir = Directory(root.path);
      if (!dir.existsSync()) continue;
      if (!root.existed) {
        // לא הייתה כאן תיקייה בכלל לפני ההורדה — כל מה שבתוכה ירד בה.
        _quietly(() => dir.deleteSync(recursive: true), root.path);
        continue;
      }
      await _revertInto(dir);
    }
  }

  Future<void> _revertInto(Directory root) async {
    // אוספים קודם ומוחקים אחר כך: מחיקה בתוך `list` שעוד זורם היא בדיוק
    // המקום שבו מערכת הקבצים של ווינדוס מפתיעה.
    final files = <File>[];
    final newDirs = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        if (!_dirs.contains(entity.path)) newDirs.add(entity.path);
      } else if (entity is File) {
        files.add(entity);
      }
    }

    for (final file in files) {
      if (_untouched.contains(file.path)) continue;
      final before = _files[file.path];
      if (before == null) {
        _quietly(() => file.deleteSync(), file.path);
        continue;
      }
      _quietly(() => before.restoreInto(file), file.path);
    }

    // תיקיות שההורדה יצרה. מהעמוקה לרדודה, וב-`recursive` כי גם תיקייה
    // ריקה־למראה עלולה להחזיק קובץ שהמחיקה שלמעלה לא הצליחה למחוק.
    newDirs.sort((a, b) => b.length.compareTo(a.length));
    for (final dir in newDirs) {
      _quietly(() => Directory(dir).deleteSync(recursive: true), dir);
    }
  }

  void _quietly(void Function() action, String path) {
    try {
      action();
    } catch (error) {
      AppLogger.instance.info('ניקוי אחרי ביטול ההורדה דילג על $path: $error');
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
    // רק גדילה מוחזרת: קובץ שהתקצר לא נגע בו איש מלבד ההורדה, וכתיבה עליו
    // ממילא אין לנו במה.
    if (file.lengthSync() <= length) return;
    final handle = file.openSync(mode: FileMode.append);
    try {
      handle.truncateSync(length);
    } finally {
      handle.closeSync();
    }
  }
}
