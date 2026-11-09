import '../../controllers/download_plan.dart' show MirrorComponent;
import 'download_task_view.dart' show DownloadSnapshot;

/// מה [DownloadOverallMeter.measure] מחזיר לקריאה אחת.
typedef DownloadOverall = ({
  /// החלק של הרכיב הנוכחי, לפי נפח.
  double? fraction,

  /// האחוז הכולל של ההורדה, משוקלל לפי נפח; `null` כשנפח אחד לא ידוע.
  double? overall,

  /// הגודל של כל רכיב לפי סדר הרכיבים; `null` — לא ידוע.
  List<int?> sizes,

  /// הגודל הצפוי לכל רכיב, כולל הבדיקה המוקדמת של הספרייה.
  Map<MirrorComponent, int> expected,
});

/// מד אחד לכל הרצת הורדה: אותו מופע לאותו מזהה, חדש למזהה חדש.
class DownloadOverallMeters {
  DownloadOverallMeter? _meter;
  int? _run;

  /// `null` כשאין הורדה רצה.
  DownloadOverallMeter? forRun(int? runId) {
    if (runId == null) return null;
    if (_run != runId) {
      _run = runId;
      _meter = DownloadOverallMeter();
    }
    return _meter;
  }
}

/// האחוז הכולל של הורדה לכונן, לבית ולמסך ההורדה יחד. המעטפת מחזיקה מופע
/// אחד לכל הורדה (`ShellTasks.downloadRunId`): מופע לכל מסך מחשב שני מספרים.
class DownloadOverallMeter {
  /// הגודל האחרון שנראה לכל רכיב — לשורה "הושלם · X" אחרי שעבר.
  final Map<MirrorComponent, int> sizes = {};

  double? _peak;

  /// בטוח לקריאה חוזרת עם אותו מצב: החישוב אינו זז בלי דיווח חדש.
  DownloadOverall measure({
    required List<MirrorComponent> components,
    required Map<MirrorComponent, int> expectedBytes,
    required DownloadSnapshot snapshot,
  }) {
    final s = snapshot;
    final current = s.current;
    final received = s.received;
    final total = s.total;
    if (current != null && received != null && total != null) {
      sizes[current] = total;
    }
    final fraction = s.fraction?.clamp(0.0, 1.0);
    final others = s.others;
    final index = current == null ? -1 : components.indexOf(current);
    final finished = s.finished ?? {if (index > 0) ...components.take(index)};
    final running = index >= 0 || others.isNotEmpty;
    final hasProgress = fraction != null ||
        others.values.any((part) => part != null) ||
        finished.any(components.contains);
    final currentSizeUnknown = received != null && total == null;
    final expected = {
      ...expectedBytes,
      if (s.libraryProbe?.bytes case final bytes?)
        MirrorComponent.library: bytes,
    };
    // הגודל האמיתי של הספרייה גובר על הבדיקה המוקדמת.
    final known = [
      for (final c in components)
        c == current && currentSizeUnknown
            ? null
            : c == MirrorComponent.library
                ? sizes[c] ?? expected[c]
                : expected[c] ?? sizes[c],
    ];
    // רכיב שגודלו לא ידוע אינו מקבל משקל שרירותי לפי מספר הרכיבים.
    final weights = [
      for (var i = 0; i < components.length; i++)
        known[i] ?? (finished.contains(components[i]) ? 0 : null),
    ];
    final bytes = weights.fold<int>(0, (sum, size) => sum + (size ?? 0));
    final computed =
        !running || !hasProgress || weights.contains(null) || bytes <= 0
            ? null
            : [
                  for (var i = 0; i < components.length; i++)
                    weights[i]! *
                        (finished.contains(components[i])
                                ? 1.0
                                : components[i] == current
                                    ? fraction ?? 0
                                    : others[components[i]] ?? 0)
                            .clamp(0.0, 1.0),
                ].fold<double>(0, (sum, value) => sum + value) /
                bytes;
    // 100% רק במסך הסיום, אחרי האימות וההרכבה.
    final bounded = computed != null && computed > 0.99 ? 0.99 : computed;
    final peak = _peak;
    final overall =
        bounded == null || peak == null || bounded >= peak ? bounded : peak;
    _peak = overall ?? peak;
    return (
      fraction: fraction,
      overall: overall,
      sizes: known,
      expected: expected,
    );
  }
}
