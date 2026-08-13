/// מה מותקן מהתוכנה המותאמת **על המחשב הזה**.
///
/// נגזר בכל פעם מחדש מהדיסק ואינו נשמר לקובץ, בכוונה: קובץ מצב היה נוסע
/// על הכונן ומכריז "מותקן" במחשב שאין בו כלום — המחלה שתועדה ב-AGENTS.md
/// לגבי `otzaria_install_state.json`. כאן פשוט אין קובץ כזה שאפשר לשקר בו.
class CustomAppInstallState {
  const CustomAppInstallState({
    required this.version,
    required this.installDir,
    required this.launchPath,
  });

  /// הגרסה שנקראה מקובץ ההרצה, או `null` כשהקובץ נמצא אך אין בו שדה גרסה.
  /// `null` אינו כשל: הוא אומר "מותקן, אך לא ניתן לדעת איזו גרסה", והממשק
  /// חייב לומר בדיוק את זה ולא להציג "מעודכן".
  final String? version;

  final String installDir;
  final String launchPath;
}
