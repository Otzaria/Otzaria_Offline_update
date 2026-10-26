import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/download_plan.dart' show MirrorComponent;
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

/// מסווג את סוף ההורדה למסך הכשל. [errors] — ההודעה של כל רכיב שנכשל
/// (`null` כשאין), [shabbat] — האתר דחה את התוספים כי שבת.
DownloadFailure classifyDownloadFailure({
  required List<MirrorComponent> failed,
  required Map<MirrorComponent, String?> errors,
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

  for (final m in messages) {
    final space = parseNotEnoughSpace(m.error);
    if (space != null) {
      return DownloadFailure(
        DownloadFailureKind.diskSpace,
        components: failed,
        details: details,
        needed: space.needed,
        free: space.free,
      );
    }
  }
  final withoutShabbat = [
    for (final m in messages)
      if (!(shabbat && m.component == MirrorComponent.plugins)) m,
  ];
  if (withoutShabbat.any((m) => _blocked.hasMatch(m.error))) {
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

/// "אין מספיק מקום" לפי התבנית המתורגמת עצמה, בכל השפות — המנוע זורק
/// טקסט בלבד, והשפה יכולה להתחלף אחרי הכשל.
({String needed, String free})? parseNotEnoughSpace(String error) {
  for (final language in AppLanguage.values) {
    final space = _parseNotEnoughSpace(
      error,
      AppL10n.stringsFor(language).libraryDomain,
    );
    if (space != null) return space;
  }
  return null;
}

({String needed, String free})? _parseNotEnoughSpace(
  String error,
  LibraryDomainStrings strings,
) {
  const marks = ['\u0001', '\u0002', '\u0003'];
  final template =
      strings.mirrorNotEnoughDiskSpace(marks[0], marks[1], marks[2]);

  final pattern = StringBuffer();
  var rest = template;
  final groups = <String>[];
  while (true) {
    final next = marks
        .map((m) => (mark: m, at: rest.indexOf(m)))
        .where((e) => e.at >= 0)
        .fold<({String mark, int at})?>(
          null,
          (best, e) => best == null || e.at < best.at ? e : best,
        );
    if (next == null) {
      pattern.write(RegExp.escape(rest));
      break;
    }
    pattern
      ..write(RegExp.escape(rest.substring(0, next.at)))
      ..write('(.+?)');
    groups.add(next.mark);
    rest = rest.substring(next.at + 1);
  }
  final match = RegExp(pattern.toString(), dotAll: true).firstMatch(error);
  if (match == null) return null;
  String? group(String mark) {
    final index = groups.indexOf(mark);
    return index < 0 ? null : match.group(index + 1);
  }

  final needed = group(marks[1]);
  final free = group(marks[2]);
  if (needed == null || free == null) return null;
  return (needed: needed, free: free);
}
