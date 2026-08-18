import 'dart:io';

import 'launcher_install_layout.dart';
import 'launcher_version.dart';

/// ה-exe שליד `app-files` נושא גרסה אחת, ומה שרץ מתוכה הוא גרסה אחרת.
class PayloadMismatch {
  const PayloadMismatch({
    required this.runningVersion,
    required this.stubVersion,
    this.markerPath,
  });

  /// הגרסה של `launcher_app.exe` שרץ כרגע — כלומר של ה-payload שעל הדיסק.
  final String runningVersion;

  /// הגרסה שה-exe החיצוני נושא בתוכו ומצפה שתרוץ.
  final String stubVersion;

  /// המרקר שנמחק כדי לבקש חילוץ מחדש, או `null` אם לא נמצא מה למחוק.
  final String? markerPath;

  @override
  String toString() =>
      'PayloadMismatch(running: $runningVersion, stub: $stubVersion)';
}

/// מאתר `app-files` שאינה תואמת ל-exe שלצידה.
///
/// המרקר `.ready` מחזיק את גרסת ה-payload, ולכן ה-stub יודע לחלץ מחדש אחרי
/// עדכון עצמי — אבל הוא **קובץ בתוך אותה תיקייה**: העתקה ידנית חלקית בין
/// מחשבים (מה שהמשתמשים עושים כשהכונן נוסע) מעתיקה אותו יחד עם חלק מהקבצים
/// ומשאירה מרקר שמכריז "מעודכן" על ערמה מעורבת. מרקר כזה אינו יכול להעיד על
/// עצמו; ההשוואה כאן היא בין שני מקורות בלתי תלויים — הקבוע שנקמפל לתוך
/// ה-exe שרץ, מול הגרסה שה-stub מסר בסביבה.
///
/// דווח בפורום (post/34063) כעדכון ש"תוקע את התוכנה והיא מפסיקה לעבוד":
/// `launcher_app.exe` מגרסה אחת מול `flutter_windows.dll` מאחרת קורס מיד.
class PayloadCheck {
  const PayloadCheck._();

  /// מה ה-stub מסר, או `null` כשאין מי שיציב — הרצה מ-`flutter run`, בנייה
  /// לא ארוזה, או stub מגרסה שקדמה למשתנה הזה.
  static String? stubPayloadVersion([Map<String, String>? environment]) {
    final value = (environment ??
        Platform.environment)[LauncherInstallLayout.payloadVersionEnvVar];
    return (value == null || value.isEmpty) ? null : value;
  }

  /// `null` כשהכול תואם — או כשאין ממה להסיק, וזו תשובה תקינה: הצהרה על
  /// תקלה בלי ראיה גרועה מלא לבדוק.
  static PayloadMismatch? detect({
    Map<String, String>? environment,
    LauncherInstallLayout? layout,
    String? runningVersion,
  }) {
    final stub = stubPayloadVersion(environment);
    if (stub == null) return null;

    final running = runningVersion ?? launcherVersion;
    // השוואה מספרית ולא השוואת מחרוזות: ה-stub צורב את הגרסה מ-pubspec, שם
    // יושב `0.2.0` בגלל דרישת pub, בעוד התוכנה מדווחת `0.2`.
    if (LauncherVersion.compare(stub, running) == 0) return null;

    return PayloadMismatch(
      runningVersion: running,
      stubVersion: stub,
      markerPath: layout?.readyMarkerPath,
    );
  }

  /// מוחק את המרקר, כדי שההרצה הבאה של ה-stub תחלץ מחדש. best-effort:
  /// כישלון כאן אינו משנה את מה שמוצג למשתמש — הוא מתבקש לסגור ולפתוח בכל
  /// מקרה, וחילוץ מחדש יקרה גם אם המחיקה נכשלה ורק המרקר נשאר שגוי.
  static Future<void> requestReextract(PayloadMismatch mismatch) async {
    final path = mismatch.markerPath;
    if (path == null) return;
    try {
      final marker = File(path);
      if (await marker.exists()) await marker.delete();
    } catch (_) {
      // נעול או לקריאה בלבד — אין מה לעשות מכאן.
    }
  }
}
