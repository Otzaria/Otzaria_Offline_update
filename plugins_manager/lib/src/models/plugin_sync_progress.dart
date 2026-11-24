/// שלב בדיווח ההתקדמות של סנכרון הקטלוג.
enum PluginSyncPhase { start, plugin, pluginFinished, warning, done }

/// אירוע התקדמות בודד. [warning] אינו עוצר את הסנכרון — קובץ בודד שנכשל
/// פשוט חסר לתוסף, והשאר ממשיך. [PluginSyncPhase.pluginFinished] הוא ליומן
/// בלבד: [message] הוא שם התוסף, ו-[bytes] ו-[elapsed] מה שירד לו וכמה זמן.
class PluginSyncProgress {
  const PluginSyncProgress({
    required this.phase,
    required this.message,
    this.current,
    this.total,
    this.bytes,
    this.elapsed,
  });

  final PluginSyncPhase phase;
  final String message;
  final int? current;
  final int? total;
  final int? bytes;
  final Duration? elapsed;

  /// 0..1 כשידוע היעד, אחרת null (מד לא-קבוע).
  double? get fraction => (current != null && total != null && total! > 0)
      ? current! / total!
      : null;
}
