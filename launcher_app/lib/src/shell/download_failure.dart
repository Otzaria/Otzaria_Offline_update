import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../controllers/download_plan.dart' show MirrorComponent;
import '../services/byte_size.dart';
import '../services/storage_failure.dart';
import 'shell_tasks.dart';

final RegExp _network = RegExp(
  r'SocketException|ClientException|TimeoutException|HandshakeException|'
  r'Failed host lookup|Connection (reset|closed|refused|timed out|aborted)|'
  r'Network is unreachable',
);

/// התעודה נדחתה — בנטפרי וכדומה בלי תעודת המסנן. "נסה שוב" לבדו לא יעזור.
/// ניתוק אחר בלחיצת היד הוא רשת רגילה.
final RegExp _blocked =
    RegExp(r'CERTIFICATE_VERIFY_FAILED|CertificateException');

/// מסווג את סוף ההורדה למסך הכשל: [causes] (החריג) קודם ל-[errors] (טקסט),
/// ו-[shabbat] — האתר דחה את התוספים.
DownloadFailure classifyDownloadFailure({
  required List<MirrorComponent> failed,
  required Map<MirrorComponent, String?> errors,
  Map<MirrorComponent, Object?> causes = const {},
  required bool shabbat,
}) {
  final messages = [
    for (final component in failed)
      if (errors[component] case final error? when error.trim().isNotEmpty)
        (component: component, error: error.trim()),
  ];
  final details = messages.isEmpty
      ? null
      : messages.map((m) => '${m.component.name}: ${m.error}').join('\n');

  // הסיבה המובנית קודמת לניחוש מטקסט; הטקסט נשאר רק למנוע שזרק הודעה.
  for (final component in failed) {
    final error = errors[component]?.trim();
    final full = findStorageFull(causes[component]) ??
        (error == null || error.isEmpty
            ? null
            : storageFullFromUpstream(error));
    if (full == null) continue;
    final needed = full.neededBytes;
    final free = full.freeBytes;
    final text = full.message ?? error;
    final parsed =
        needed == null && text != null ? parseNotEnoughSpace(text) : null;
    return DownloadFailure(
      DownloadFailureKind.diskSpace,
      components: failed,
      details: details,
      needed:
          needed != null && free != null ? formatBytes(needed) : parsed?.needed,
      free: needed != null && free != null ? formatBytes(free) : parsed?.free,
      dir: full.dir,
    );
  }
  final withoutShabbat = [
    for (final m in messages)
      if (!(shabbat && m.component == MirrorComponent.plugins)) m,
  ];
  if (failed
          .where((c) => !(shabbat && c == MirrorComponent.plugins))
          .any((c) => switch (causes[c]) {
                NetworkBlockedException() ||
                NetworkCertificateException() =>
                  true,
                LibraryHttpException(:final isBlockedByFilter) =>
                  isBlockedByFilter,
                _ => false,
              }) ||
      withoutShabbat.any((m) => _blocked.hasMatch(m.error))) {
    return DownloadFailure(
      DownloadFailureKind.blocked,
      components: failed,
      details: details,
    );
  }
  if (withoutShabbat.isNotEmpty &&
      withoutShabbat.every((m) => _network.hasMatch(m.error))) {
    return DownloadFailure(
      DownloadFailureKind.network,
      components: failed,
      details: details,
    );
  }
  if (shabbat && failed.every((c) => c == MirrorComponent.plugins)) {
    return DownloadFailure(DownloadFailureKind.shabbat, components: failed);
  }
  return DownloadFailure(
    DownloadFailureKind.other,
    components: failed,
    details: details,
  );
}
