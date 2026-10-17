import 'package:seforim_library_updater/seforim_library_updater.dart';

/// החיבורים לקובץ גדול במשבצת של [scheduler] — אותה חלוקה של הייצוא, כדי
/// שגם הנלווים שחולקים איתו את המשבצות לא יעברו את התקרה הכוללת.
int connectionsPerFile(DownloadScheduler scheduler) {
  final share =
      LibraryMirrorExporter.maxTotalConnections ~/ scheduler.maxConcurrent;
  if (share < 1) return 1;
  const requested = PatchDownloader.defaultMaxConnections;
  return share < requested ? share : requested;
}
