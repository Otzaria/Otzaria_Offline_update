import 'dart:convert';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// הפעולה שבוצעה (או נדרשת) בעת בדיקת התאוששות בעליית האפליקציה.
enum RecoveryAction {
  /// אין עדכון שנקטע — שום דבר לא נדרש.
  none,

  /// נמצא סימון של עדכון שנקטע. אין מה לשחזר — הקורא צריך לוודא תקינות
  /// (quick_check) ולנקות את הסימון.
  interrupted,
}

class RecoveryResult {
  final RecoveryAction action;
  final String? detail;
  const RecoveryResult(this.action, [this.detail]);
}

/// מנהל את הסימון (marker) של החלת עדכון על `seforim.db`, כדי שקריסה באמצע
/// apply תזוהה בעלייה הבאה.
///
/// **אין כאן גיבוי של המסד, בכוונה.** שני מסלולי ההחלה בטוחים בלי עותק נוסף:
/// מסלול patch עטוף ב-transaction יחיד שמתגלגל אחורה מעצמו, ומסלול המסד המלא
/// מחלץ ל-`<db>.new`, מאמת אותו, ורק אז מחליף ב-rename. עותק שני של מסד ~1GB
/// על כונן נייד היה מכפיל את הדרישה בלי להוסיף ביטחון אמיתי.
class LibraryDbRecoveryService {
  const LibraryDbRecoveryService();

  String markerPathFor(String dbPath) => '$dbPath.applying';

  /// סימון "המסד בגרסה X אך תוכנו לא אומת ב-hash" — ראו [markUnverified].
  String unverifiedMarkerPathFor(String dbPath) => '$dbPath.unverified';

  /// שאריות של מנגנון הגיבוי שהוסר — נמחקות בעלייה כדי לא להשאיר ~1GB תלוי
  /// אצל מי שעדכן מגרסה שכן יצרה גיבוי.
  static const List<String> _legacySuffixes = [
    '.backup',
    '.backup.tmp',
    '.restore.tmp',
  ];

  /// נקרא בעליית האפליקציה, **לפני** פתיחת ה-DB.
  ///
  /// סימון קיים → [RecoveryAction.interrupted]; הקורא מריץ
  /// [checkDbHealthAfterCrash] ומנקה את הסימון. אין סימון → אין מה לעשות.
  Future<RecoveryResult> recoverIfNeeded(String dbPath) async {
    _deleteLegacyArtifacts(dbPath);

    if (!File(markerPathFor(dbPath)).existsSync()) {
      return const RecoveryResult(RecoveryAction.none);
    }
    return RecoveryResult(
      RecoveryAction.interrupted,
      AppL10n.strings.libraryDomain.interruptedUpdateFound,
    );
  }

  /// בודק תקינות DB אחרי עדכון שנקטע. מחזיר `true` אם ה-DB תקין (עבר
  /// `quick_check`).
  ///
  /// חובה לפתוח RW: קריסה באמצע transaction משאירה hot journal, ו-SQLite חייב
  /// גישת כתיבה כדי לגלגלו אחורה. פתיחת readOnly על hot journal נכשלת ב-"attempt
  /// to write a readonly database". הפתיחה כאן מגלגלת ומנקה את ה-journal, כך
  /// שפתיחת ה-read-only הראשית של האפליקציה אחריה מצליחה.
  bool checkDbHealthAfterCrash(String dbPath) {
    try {
      final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readWrite);
      try {
        final result = db.select('PRAGMA quick_check');
        return result.isNotEmpty &&
            result.first.values.first?.toString() == 'ok';
      } finally {
        db.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// נקרא לפני apply: כותב את הסימון (ומנקה שאריות קודמות תחילה).
  Future<void> beginApply({
    required String dbPath,
    required int fromVersion,
    required int toVersion,
    required String timestamp,
  }) async {
    _deleteLegacyArtifacts(dbPath);
    File(markerPathFor(dbPath)).writeAsStringSync(
      jsonEncode({
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'timestamp': timestamp,
      }),
      flush: true,
    );
  }

  /// נקרא אחרי apply מוצלח — ה-DB תקין, מוחקים את הסימון.
  void finishSuccess(String dbPath) => _deleteQuietly(markerPathFor(dbPath));

  /// מסמן שה-DB הגיע ל-[version] בהחלה שה-hash שלה **לא** חושב.
  ///
  /// שרשרת patches מאמתת hash פעם אחת, בצעד האחרון — הוא מוכיח את כל השרשרת
  /// וחוסך קריאה מלאה של ~7.4GB לכל צעד. שרשרת שנקטעה באמצע (ביטול, כשל
  /// הורדה) משאירה מסד שהוחל נקי אך לא אומת, והסימון הזה הוא מה שמונע ממנו
  /// להישאר כך בשקט: ההחלה הבאה שמתחילה מ-[version] מפעילה `verifyFromHash`
  /// ומאמתת אותו לפני שהיא בונה עליו — ראו `LibraryUpdateApplier.applyDelta`.
  void markUnverified(String dbPath, int version) {
    try {
      File(unverifiedMarkerPathFor(dbPath))
          .writeAsStringSync(jsonEncode({'version': version}), flush: true);
    } catch (_) {
      // כשל כתיבה (כונן מלא/לקריאה בלבד) אינו הופך החלה שהצליחה לכישלון;
      // האימות של הצעד האחרון עוד יתפוס תוכן שגוי בהמשך.
    }
  }

  /// הגרסה שסומנה כלא-מאומתת, או `null` כשאין סימון (או שאינו קריא).
  int? unverifiedVersion(String dbPath) {
    try {
      final file = File(unverifiedMarkerPathFor(dbPath));
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync());
      return json is Map && json['version'] is int
          ? json['version'] as int
          : null;
    } catch (_) {
      return null;
    }
  }

  /// נקרא אחרי אימות hash שהצליח, או אחרי התקנת מסד מלא מאומת.
  void clearUnverified(String dbPath) =>
      _deleteQuietly(unverifiedMarkerPathFor(dbPath));

  /// מנקה סימון תקוע — גם אחרי apply שנכשל (וה-DB נשאר בגרסה שלפניו), וגם
  /// אחרי שזוהה מצב לא תקין ודווח (לא מחיקה שקטה).
  void clearStaleArtifacts(String dbPath) =>
      _deleteQuietly(markerPathFor(dbPath));

  void _deleteLegacyArtifacts(String dbPath) {
    for (final suffix in _legacySuffixes) {
      _deleteQuietly('$dbPath$suffix');
    }
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
