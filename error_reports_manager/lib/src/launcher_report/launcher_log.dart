import 'dart:convert';

import '../port/crash_signature.dart';

/// הצורה שבה הלאנצ'ר כותב ל-`launcher.log`, משותפת לכותב (`AppLogger`,
/// `main.dart`) ולקורא שכאן — שינוי באחד בלי השני שובר את זיהוי הקריסה.
abstract final class LauncherLogFormat {
  /// שמות הקבצים מהישן לחדש: `AppLogger` מסובב ל-`.1` מעל 2MB.
  static const List<String> fileNames = ['launcher.log.1', 'launcher.log'];

  /// הכותרות של שגיאה שלא נתפסה — המקבילות ל-`FlutterError`/`Unhandled Error`
  /// ב-errors.txt של אוצריא.
  static const String flutterError = 'FlutterError';
  static const String zoneError = 'Uncaught zone error';
  static const String platformError = 'Uncaught platform error';
  static const List<String> uncaughtKinds = [
    flutterError,
    zoneError,
    platformError,
  ];

  /// מתוכן, אלה שנחשבים ראיה לקריסה.
  static const List<String> fatalKinds = [zoneError, platformError];

  /// קידומת האזהרה "אף פריים לא הוצג" — המקבילה ל-`Startup stall` של אוצריא.
  static const String startupStallTag = 'Startup stall:';

  /// השורה שנושאת את הטיפוס בזמן ריצה, ואחריה `error:` של `AppLogger.error`.
  static const String typePrefix = 'type: ';
  static const String errorPrefix = 'error: ';

  /// ההודעה שנרשמת לשגיאה שלא נתפסה; `AppLogger.error` מוסיף את השגיאה וה-stack.
  static String uncaughtMessage(String kind, Object error) =>
      '$kind\n$typePrefix${error.runtimeType}';
}

/// רשומה אחת מ-`launcher.log`: שורת הכותרת וכל שורות ההמשך שלה.
class LauncherLogBlock {
  const LauncherLogBlock({
    required this.level,
    required this.timestamp,
    required this.text,
  });

  /// `INFO` / `WARN` / `ERROR`.
  final String level;
  final DateTime? timestamp;

  /// הרשומה כפי שנכתבה, כולל שורת הכותרת.
  final String text;

  List<String> get _lines => const LineSplitter().convert(text);

  /// ההודעה בשורת הכותרת, בלי הזמן והרמה.
  String get message {
    final lines = _lines;
    if (lines.isEmpty) return '';
    final header = _header.firstMatch(lines.first);
    return header == null ? lines.first : header.group(3)!.trim();
  }

  bool _isKind(List<String> kinds) =>
      level == 'ERROR' &&
      kinds.any((kind) => message == kind || message.startsWith('$kind:'));

  bool get isUncaughtError => _isKind(LauncherLogFormat.uncaughtKinds);

  /// שגיאה שלא נתפסה ב-zone או בפלטפורמה. `FlutterError` אינו כזה: רובו שגיאת
  /// ציור שהתוכנה ממשיכה אחריה, והוא לבדו אינו ראיה לקריסה.
  bool get isFatalError => _isKind(LauncherLogFormat.fatalKinds);

  bool get isStartupStall =>
      message.startsWith(LauncherLogFormat.startupStallTag);

  /// שגיאה שלא נתפסה או תקיעה — ראיה לקריסה, בניגוד לשגיאה שטופלה.
  bool get isCrashEvidence => isFatalError || isStartupStall;

  String? _lineValue(String prefix) {
    for (final line in _lines.skip(1)) {
      if (line.startsWith(prefix)) return line.substring(prefix.length).trim();
    }
    return null;
  }

  /// השורות מהפריים הראשון (`#0`) עד סוף הרשומה.
  String get stackText {
    final lines = _lines;
    final start = lines.indexWhere((line) => _frame.hasMatch(line));
    return start < 0 ? '' : lines.sublist(start).join('\n');
  }

  /// חתימה לפי הטיפוס (או שורת השגיאה) וה-stack; בלעדיהם — לפי ההודעה.
  CrashSignature get signature {
    final type = _lineValue(LauncherLogFormat.typePrefix);
    if (type != null && type.isNotEmpty) {
      return CrashSignature(
        exceptionType: type.length <= CrashSignature.maxExceptionTypeLength
            ? type
            : type.substring(0, CrashSignature.maxExceptionTypeLength),
        frames: CrashSignature.selectFrames(stackText),
      );
    }
    return CrashSignature.fromLogText(
      exceptionMessage: _lineValue(LauncherLogFormat.errorPrefix) ?? message,
      stackText: stackText,
    );
  }
}

final RegExp _header = RegExp(
  r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?) '
  r'\[(INFO|WARN|ERROR)\] ?(.*)$',
);
final RegExp _frame = RegExp(r'^\s*#\d+\s');

/// מפענח את `launcher.log` לרשומות. טקסט שלפני הכותרת הראשונה (זנב חתוך) נזרק.
List<LauncherLogBlock> parseLauncherLog(String content) {
  final blocks = <LauncherLogBlock>[];
  String? level;
  DateTime? timestamp;
  var buffer = StringBuffer();

  void flush() {
    if (level == null) return;
    blocks.add(
      LauncherLogBlock(
        level: level,
        timestamp: timestamp,
        text: buffer.toString().trimRight(),
      ),
    );
  }

  for (final line in const LineSplitter().convert(content)) {
    final header = _header.firstMatch(line);
    if (header != null) {
      flush();
      timestamp = DateTime.tryParse(header.group(1)!);
      level = header.group(2);
      buffer = StringBuffer()..writeln(line);
      continue;
    }
    if (level != null) buffer.writeln(line);
  }
  flush();
  return blocks;
}

/// רשומות מ-[since] והלאה, מהחדשה לישנה, בגבול [maxBytes] — הישנות נשמטות.
String recentLauncherLogExcerpt(
  String content, {
  required DateTime since,
  required int maxBytes,
}) {
  final recent = parseLauncherLog(content)
      .where((block) => !(block.timestamp?.isBefore(since) ?? true))
      .toList();
  final kept = <String>[];
  var bytes = 0;
  // הקובץ כרונולוגי; הולכים מהסוף כדי שהגבול ישמיט דווקא את הישנות.
  for (final block in recent.reversed) {
    final size = utf8.encode(block.text).length + 1;
    if (bytes + size > maxBytes) break;
    kept.add(block.text);
    bytes += size;
  }
  return kept.reversed.join('\n');
}
