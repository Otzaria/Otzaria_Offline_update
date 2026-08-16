/// מה נאמר בסוף הורדה — הודעה **אחת**.
///
/// ל-`UiSnack` אין תור: הודעה שנייה שנשלחת באותו רגע דורסת את הראשונה מיד,
/// וכך "דילגנו על..." לא נראתה מעולם כשגם משהו נכשל. הכי חמור הוא מה שנאמר.
enum DownloadSummary {
  /// שום דבר לא נכשל ולא דולג — וזה מה שלא נאמר קודם בכלל: ההורדה, שאורכת
  /// עשרות דקות, נגמרה בכך שמד ההתקדמות פשוט נעלם מהמסך.
  done,
  skipped,
  failed,
}

DownloadSummary summarizeDownload({
  required List<String> failed,
  required List<String> skipped,
}) {
  if (failed.isNotEmpty) return DownloadSummary.failed;
  if (skipped.isNotEmpty) return DownloadSummary.skipped;
  return DownloadSummary.done;
}
