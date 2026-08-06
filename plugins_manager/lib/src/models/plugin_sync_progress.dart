/// שלב בדיווח ההתקדמות של סנכרון הקטלוג.
enum PluginSyncPhase { start, plugin, warning, done }

/// אירוע התקדמות בודד. [warning] אינו עוצר את הסנכרון — קובץ בודד שנכשל
/// פשוט חסר לתוסף, והשאר ממשיך.
class PluginSyncProgress {
  const PluginSyncProgress({
    required this.phase,
    required this.message,
    this.current,
    this.total,
  });

  final PluginSyncPhase phase;
  final String message;
  final int? current;
  final int? total;

  /// 0..1 כשידוע היעד, אחרת null (מד לא-קבוע).
  double? get fraction => (current != null && total != null && total! > 0)
      ? current! / total!
      : null;
}
