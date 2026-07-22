import 'dart:io';

/// מפעיל את קובץ ה-exe המותקן. נפרד מ-[OtzariaInstaller] כי "הפעלה" יכולה
/// לקרות גם בלי שהתבצעה התקנה/עדכון בסשן הנוכחי (למשל בכל פתיחה של
/// הלאנצ'ר, כשההתקנה כבר עדכנית).
class OtzariaLauncher {
  const OtzariaLauncher();

  /// מפעיל את אוצריא כתהליך עצמאי (לא ממתין לסיום שלו — אחרת הלאנצ'ר
  /// ייחסם כל עוד אוצריא פתוחה).
  Future<void> launch(String exePath) async {
    if (!await File(exePath).exists()) {
      throw StateError('קובץ ההפעלה לא נמצא בנתיב: $exePath');
    }

    await Process.start(
      exePath,
      const [],
      mode: ProcessStartMode.detached,
    );
  }
}
