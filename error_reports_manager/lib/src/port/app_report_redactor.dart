import 'dart:io';

/// מסתיר מידע אישי בדיווח לפני שהוא יוצא מהמחשב: תיקיית הפרופיל, שם המשתמש
/// במערכת וכתובות מייל. פונקציה טהורה — הסביבה מוזרקת.
class AppReportRedactor {
  AppReportRedactor({required Map<String, String> environment})
      : _profilePatterns = _buildProfilePatterns(environment),
        _userPattern = _buildUserPattern(environment);

  /// לפי משתני הסביבה של התהליך הנוכחי.
  factory AppReportRedactor.fromPlatform() {
    try {
      return AppReportRedactor(environment: Platform.environment);
    } catch (_) {
      return AppReportRedactor(environment: const {});
    }
  }

  static const String profilePlaceholder = '%USERPROFILE%';
  static const String userPlaceholder = '<user>';
  static const String emailPlaceholder = '<email>';
  static const int minUserNameLength = 3;

  /// הדומיין של כתובת דואר, מוגבל (RFC 5321: תווית עד 63). הביטוי המקורי
  /// (`...*@...`) היה מחפש `@` מכל נקודת התחלה בטקסט — ריבועי: `'a' * 200000`
  /// תקע את ה-isolate דקות. לכן מחפשים קודם `@`, וממנו סורקים קדימה ואחורה.
  static final RegExp _emailDomain = RegExp(
    r'[A-Za-z0-9\-]{1,63}(?:\.[A-Za-z0-9\-]{1,63}){0,10}\.[A-Za-z]{2,24}',
  );

  static bool _isAlnum(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A);

  /// תווי החלק המקומי: אות/ספרה ו-`._%+-`.
  static bool _isLocal(int c) =>
      _isAlnum(c) ||
      c == 0x2E ||
      c == 0x5F ||
      c == 0x25 ||
      c == 0x2B ||
      c == 0x2D;

  /// מחליף כל כתובת דואר ב-[emailPlaceholder]. החלק המקומי עד 64 תווים
  /// ומתחיל באות או ספרה (`-a@b.com` מוסתר כ-`-<email>`, לא נשאר גלוי).
  static String _redactEmails(String text) {
    var at = text.indexOf('@');
    if (at < 0) return text;
    final out = StringBuffer();
    var copied = 0;
    while (at >= 0) {
      var start = at;
      while (start > copied &&
          at - start < 64 &&
          _isLocal(text.codeUnitAt(start - 1))) {
        start--;
      }
      while (start < at && !_isAlnum(text.codeUnitAt(start))) {
        start++;
      }
      final domain =
          start < at ? _emailDomain.matchAsPrefix(text, at + 1) : null;
      if (domain == null) {
        at = text.indexOf('@', at + 1);
        continue;
      }
      out
        ..write(text.substring(copied, start))
        ..write(emailPlaceholder);
      copied = domain.end;
      at = text.indexOf('@', copied);
    }
    out.write(text.substring(copied));
    return out.toString();
  }

  /// מקטע נתיב: מותרים בו רווחים פנימיים (`John Smith`, `Program Files`),
  /// אבל לא בתחילתו ובסופו — כך שמשפט שבא אחרי נתיב אינו נבלע בו.
  static const String _segment =
      r'[^\\/\x22\x27<>:|?*,;()\s](?:[^\\/\x22\x27<>:|?*,;()\r\n]*'
      r'[^\\/\x22\x27<>:|?*,;()\s])?';

  /// `<כונן>:\Users\<שם>`, `/Users/<שם>`, `/home/<שם>` — שני הלוכסנים וגם
  /// `\\` כפי שנכתב בתוך JSON. במקרה של Windows השם עשוי לכלול רווח, ועדיף
  /// להסתיר מילים נוספות מלדלוף שם משפחה. הלוכסן הפותח אינו אחרי אות או `/`
  /// (`https://home/x`), חוץ מ-`file:///home/x`, ואות הכונן אינה אחרי אות.
  static final List<RegExp> _genericProfilePatterns = [
    RegExp(
      r'(?<![\p{L}\p{N}_])[A-Za-z]:(?:\\+|/)Users(?:\\+|/)' + _segment,
      caseSensitive: false,
      unicode: true,
    ),
    for (final root in const ['Users', 'home']) ...[
      RegExp(
        r'(?<![\p{L}\p{N}_.:%/-])/' + root + r'/[^\\/\s\x22\x27<>:|?*,;()]+',
        caseSensitive: false,
        unicode: true,
      ),
      RegExp(
        r'(?<=file://)/' + root + r'/[^\\/\s\x22\x27<>:|?*,;()]+',
        caseSensitive: false,
        unicode: true,
      ),
    ],
  ];

  /// הרכיב האחרון של נתיב: בלי רווחים, וגם בלי `:` — `a.dart:12:5` שומר
  /// את מיקום השורה.
  static const String _fileName = r'[^\s\x22\x27<>:|?*,;()\\/]*';

  static final RegExp _windowsAbsolutePath = RegExp(
    r'(?<![\p{L}\p{N}_])(?:[A-Za-z]:|\\\\[^\s\\/]+)(?:[\\/]' +
        _segment +
        r')*[\\/]' +
        _fileName,
    unicode: true,
  );
  static final RegExp _posixAbsolutePath = RegExp(
    r'(?<![\p{L}\p{N}_.:/%-])(?:/' +
        _segment +
        r')+/' +
        _fileName +
        r'(?<=[^/])',
    unicode: true,
  );
  static final RegExp _trailingPunctuation = RegExp(r'[.,;)\]}]+$');

  /// מצמצם נתיב מוחלט שנשאר בטקסט (מחוץ לפרופיל) לשם הקובץ שלו — ליומן, שבו
  /// שמות תיקיות של המשתמש חושפים יותר ממה שהאבחון צריך. שם הקובץ עצמו נשאר.
  static String reducePaths(String text) {
    if (text.isEmpty) return text;
    String reduce(Match m) {
      final raw = m.group(0)!;
      final tail = _trailingPunctuation.firstMatch(raw)?.group(0) ?? '';
      final path = raw.substring(0, raw.length - tail.length);
      final segments =
          path.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();
      return (segments.isEmpty ? path : segments.last) + tail;
    }

    return text
        .replaceAllMapped(_windowsAbsolutePath, reduce)
        .replaceAllMapped(_posixAbsolutePath, reduce);
  }

  final List<RegExp> _profilePatterns;
  final RegExp? _userPattern;

  String redactText(String text) {
    if (text.isEmpty) return text;
    var result = _redactEmails(text);
    for (final pattern in _profilePatterns) {
      result = result.replaceAll(pattern, profilePlaceholder);
    }
    // גם נתיב פרופיל שאינו במשתני הסביבה, למשל צורת 8.3 (`ZEEVLE~1`).
    for (final pattern in _genericProfilePatterns) {
      result = result.replaceAll(pattern, profilePlaceholder);
    }
    final user = _userPattern;
    if (user != null) result = result.replaceAll(user, userPlaceholder);
    return result;
  }

  /// מחיל את ההסתרה על כל מחרוזת במבנה JSON, כולל מפתחות של מפות.
  Object? redactJson(Object? value) {
    if (value is String) return redactText(value);
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          redactText('${entry.key}'): redactJson(entry.value),
      };
    }
    if (value is List) return value.map(redactJson).toList();
    return value;
  }

  /// כל צורות הנתיב: שני סוגי הלוכסנים, וגם `\\` כפי שנכתב בתוך JSON.
  static List<RegExp> _buildProfilePatterns(Map<String, String> env) {
    final variants = <String>{};
    for (final key in const ['USERPROFILE', 'HOME']) {
      var path = env[key]?.trim() ?? '';
      while (path.length > 1 && (path.endsWith('/') || path.endsWith('\\'))) {
        path = path.substring(0, path.length - 1);
      }
      // נתיב קצר מדי (`/`, `C:`) היה מוחק חלקים לא אישיים מכל הדוח.
      if (path.length < 4) continue;
      final segments = path.split(RegExp(r'[\\/]+'));
      variants
        ..add(segments.join('\\'))
        ..add(segments.join('/'))
        ..add(segments.join(r'\\'));
    }
    final sorted = variants.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return [
      for (final variant in sorted)
        RegExp(
          '${RegExp.escape(variant)}(?![A-Za-z0-9_\\-.])',
          caseSensitive: false,
        ),
    ];
  }

  static RegExp? _buildUserPattern(Map<String, String> env) {
    final names = <String>{
      for (final key in const ['USERNAME', 'USER'])
        if ((env[key]?.trim() ?? '').length >= minUserNameLength)
          env[key]!.trim(),
    };
    if (names.isEmpty) return null;
    final alternatives = (names.toList()
          ..sort((a, b) => b.length.compareTo(a.length)))
        .map(RegExp.escape)
        .join('|');
    // `<` / `>`: הסתרה חוזרת לא תהפוך את `<user>` של שם המשתמש User ל-`<<user>>`.
    return RegExp(
      r'(?<![\p{L}\p{N}_<])(?:' + alternatives + r')(?![\p{L}\p{N}_>])',
      caseSensitive: false,
      unicode: true,
    );
  }
}
