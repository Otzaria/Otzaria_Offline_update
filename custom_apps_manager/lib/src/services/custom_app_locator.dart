import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';
import '../models/custom_app_install_state.dart';

/// קורא את הגרסה מקובץ הרצה. **מוזרק מבחוץ** ולא ממומש כאן: הקריאה
/// דורשת Win32/FFI ב-Windows ו-`Info.plist` ב-macOS, והלאנצ'ר כבר מחזיק
/// את שתיהן (`installedVersionReaderFor`). התפר הזה שומר את החבילה נקייה
/// מ-win32 ומאפשר לבדיקות להזריק קורא צפוי.
typedef AppVersionReader = String? Function(String exePath);

/// מחזיר תיקיות התקנה שרשומות ברג'יסטרי ההסרה של ווינדוס ושה-`DisplayName`
/// שלהן תואם לתבנית. גם הוא מוזרק — מאותה סיבה.
typedef UninstallDirLookup = List<String> Function(RegExp displayName);

/// מחזיר את נתיב ההרצה של תהליך שרץ **כרגע** ושמו [exeName], או `null`.
///
/// זה הסימן החזק ביותר: הוא אינו ניחוש אלא העותק שהמשתמש מפעיל בפועל,
/// כולל התקנה בתיקייה שאיש לא ניחש. בדיוק מה ש-`RunningOtzariaLocator`
/// עושה עבור אוצריא, והלאנצ'ר מזליג לכאן את אותו מנגנון.
typedef RunningProcessLookup = Future<String?> Function(String exeName);

/// מאתר את ההתקנה של תוכנה נוספת על המחשב הזה.
class CustomAppLocator {
  const CustomAppLocator({
    required this.readVersion,
    this.lookupUninstallDirs,
    this.lookupRunningProcess,
  });

  final AppVersionReader readVersion;

  /// `null` בפלטפורמה שאין בה רג'יסטרי — אז נשארים עם התיקיות המוצהרות.
  final UninstallDirLookup? lookupUninstallDirs;

  final RunningProcessLookup? lookupRunningProcess;

  /// עומק הסריקה בתוך תיקיית מועמדת. שתיים בלבד, ובחיפוש לרוחב — אותו
  /// שיקול שתועד ב-`OtzariaAppLocator`: סריקה עמוקה ולא-מסודרת מחזירה
  /// תשובות שונות במחשבים שונים, ועלולה לטייל בתוך עץ ענק.
  static const int _maxDepth = 2;

  /// מחפש את ההתקנה, או `null` כשלא נמצאה. אינו סורק את כל המחשב.
  ///
  /// [learnedDirs] הם מיקומים שכבר נמצאו במחשבים אחרים, מהנפוץ לנדיר —
  /// ראו `KnownLocationsStore`.
  Future<CustomAppInstallState?> detect(
    AppDescriptor descriptor, {
    List<String> learnedDirs = const [],
  }) async {
    final exeName = descriptor.detect.exeName;
    if (exeName == null || exeName.isEmpty) return null;

    // התהליך הרץ ראשון, לפני כל חיפוש בתיקיות: הוא אינו ניחוש אלא הקובץ
    // שמורץ בפועל ברגע זה.
    if (lookupRunningProcess case final lookup?) {
      final running = await lookup(exeName);
      if (running != null && await File(running).exists()) {
        return _stateAt(running);
      }
    }

    for (final dir in _candidateDirs(descriptor, learnedDirs)) {
      final found = await _findExeIn(dir, exeName);
      if (found != null) return _stateAt(found);
    }
    return null;
  }

  /// חיפוש **בתיקייה אחת בלבד** — מה שקורה כשהמשתמש מצביע ידנית.
  /// `null` כשקובץ ההרצה אינו שם, או כשלא הוגדר שם כזה בכלל.
  Future<CustomAppInstallState?> findIn(String dir, String? exeName) async {
    if (exeName == null || exeName.isEmpty) return null;
    final found = await _findExeIn(dir, exeName);
    return found == null ? null : _stateAt(found);
  }

  CustomAppInstallState _stateAt(String launchPath) => CustomAppInstallState(
        version: readVersion(launchPath),
        installDir: p.dirname(launchPath),
        launchPath: launchPath,
      );

  /// התיקיות שבהן מחפשים, לפי סדר עדיפות — מהעדות החזקה לניחוש.
  ///
  /// המיקומים הנלמדים קודמים לרג'יסטרי: תיקייה שכבר נמצאה בכמה מחשבים
  /// היא תצפית שהתאמתה, בעוד שהרג'יסטרי הוא רישום שהמתקין כתב (ועדיין
  /// טוב בהרבה מהתיקייה שהמשתמש הקליד בטופס).
  Iterable<String> _candidateDirs(
    AppDescriptor descriptor,
    List<String> learnedDirs,
  ) sync* {
    yield* learnedDirs;

    final pattern = descriptor.detect.registryDisplayName;
    final lookup = lookupUninstallDirs;
    if (pattern != null && pattern.isNotEmpty && lookup != null) {
      yield* lookup(RegExp(pattern, caseSensitive: false));
    }
    if (descriptor.installDir case final dir? when dir.isNotEmpty) yield dir;
    yield* descriptor.detect.dirs;
  }

  /// חיפוש לרוחב אחרי [exeName] תחת [root], עד [_maxDepth].
  Future<String?> _findExeIn(String root, String exeName) async {
    final target = exeName.toLowerCase();
    var level = <Directory>[Directory(root)];

    for (var depth = 0; depth < _maxDepth && level.isNotEmpty; depth++) {
      final next = <Directory>[];
      for (final dir in level) {
        if (!await dir.exists()) continue;
        try {
          await for (final child in dir.list(followLinks: false)) {
            if (child is Directory) {
              next.add(child);
              continue;
            }
            if (p.basename(child.path).toLowerCase() == target) {
              return child.path;
            }
          }
        } catch (_) {
          // תיקייה בלי הרשאת קריאה אינה כשל של החיפוש כולו.
        }
      }
      level = next;
    }
    return null;
  }
}
