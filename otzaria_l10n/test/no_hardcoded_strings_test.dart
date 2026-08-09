@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// שומר על הכלל שב-AGENTS.md §4: כל מלל שהמשתמש רואה חי ב-`otzaria_l10n`
/// בלבד — לא בווידג'ט, לא בהודעת חריג ולא ב-callback של התקדמות.
///
/// הבדיקה יושבת דווקא כאן כי זו החבילה שכולם תלויים בה, והיא Dart טהורה
/// (אין `flutter test` שיסבך את קריאת הקבצים).

/// מחרוזת שנמצאה בקוד: מאיפה, מה היא, ואיפה בדיוק בקובץ.
class _Literal {
  _Literal(this.file, this.line, this.offset, this.value);

  final String file;
  final int line;
  final int offset;
  final String value;

  @override
  String toString() => '$file:$line  →  $value';
}

/// קבצים שכל המחרוזות העבריות בהם אינן מלל לתרגום.
const _exemptFiles = <String, String>{
  // נתיבי התקנה ושמות תהליכים — אין מה לתרגם בשם תיקייה.
  'otzaria_manager/lib/src/otzaria_manager.dart': 'נתיבי התקנה',
  'library_manager/lib/src/services/library_db_locator.dart': 'נתיב ברירת מחדל',
  'library_manager/lib/src/services/otzaria_process_guard.dart': 'שם תהליך',
  // גימטריה ושמות חודשים עבריים — התוצאה עברית מעצם טבעה.
  'launcher_app/lib/src/services/hebrew_date.dart': 'לוח השנה העברי',
  // שמות הגוונים; `options` אינו בשימוש בקוד כרגע.
  'launcher_app/lib/src/theme/app_seed_colors.dart': 'שמות גוונים',
};

/// הקשרים שבהם מחרוזת עברית היא הודעה למפתח ולא למשתמש: יומן, `debugPrint`
/// (הנתיב שלפני אתחול הלוגר), ושגיאות תכנות שנזרקות רק כשהקוד עצמו שגוי.
final _developerContext = RegExp(
  r'(AppLogger\.\w+|logger\.\w+|debugPrint|assert'
  r'|StateError|ArgumentError|UnsupportedError)[\s\S]{0,80}$',
);

/// הפרות ידועות שטרם תוקנו — מוצמדות לרשימה סגורה כדי שיישארו גלויות
/// ולא יגדלו.
///
/// שתיהן שמירות-שפיות פנימיות: הן נזרקות רק אם הלאנצ'ר עצמו קורא
/// לפונקציה עם תוכנית מהסוג הלא נכון, ולכן המשתמש לעולם לא אמור לראות
/// אותן. עדיין `LibraryApplyException`, ולכן הן נשארות ברשימה ולא בפטור.
const _knownViolations = <String>{
  'library_manager/lib/src/services/library_update_applier.dart|'
      'applyDelta נקרא על תוכנית שאינה delta',
  'library_manager/lib/src/services/library_update_applier.dart|'
      'applyFullDownload נקרא על תוכנית שאינה fullDownload',
};

bool _isIdentifierChar(String c) =>
    RegExp(r'[A-Za-z0-9_$]').hasMatch(c); // קידומת `r` נחשבת רק כמילה שלמה

/// מוציא את כל מחרוזות-הקוד מקובץ Dart, בלי הערות. הערות בעברית הן תקינות
/// ונפוצות כאן, ולכן חייבים לנתח ולא רק לחפש ביטוי רגולרי.
List<_Literal> _stringLiterals(String file, String src) {
  final out = <_Literal>[];
  var i = 0;
  var line = 1;

  while (i < src.length) {
    final c = src[i];

    if (c == '\n') {
      line++;
      i++;
      continue;
    }

    // הערת שורה
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }

    // הערת בלוק — מקוננת ב-Dart
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      var depth = 0;
      while (i < src.length) {
        if (src.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          i += 2;
          if (depth == 0) break;
        } else {
          if (src[i] == '\n') line++;
          i++;
        }
      }
      continue;
    }

    final isRaw = c == 'r' &&
        i + 1 < src.length &&
        (src[i + 1] == "'" || src[i + 1] == '"') &&
        (i == 0 || !_isIdentifierChar(src[i - 1]));
    final quoteAt = isRaw ? i + 1 : i;
    final quote = src[quoteAt];

    if (quote != "'" && quote != '"') {
      i++;
      continue;
    }

    final triple = src.startsWith(quote * 3, quoteAt);
    final delimiter = triple ? quote * 3 : quote;
    final startLine = line;
    final buffer = StringBuffer();
    var j = quoteAt + delimiter.length;

    while (j < src.length) {
      if (!isRaw && src[j] == r'\') {
        buffer.write(src[j + 1 < src.length ? j + 1 : j]);
        j += 2;
        continue;
      }
      if (src.startsWith(delimiter, j)) {
        j += delimiter.length;
        break;
      }
      if (src[j] == '\n') {
        line++;
        // מחרוזת רגילה אינה חוצה שורות — סימן שהניתוח החליק
        if (!triple) break;
      }
      buffer.write(src[j]);
      j++;
    }

    out.add(_Literal(file, startLine, i, buffer.toString()));
    i = j;
  }
  return out;
}

/// נתיבים מנורמלים ל-`/` כדי שהמפתחות ברשימות יהיו זהים בכל מערכת.
String _slashes(String path) => path.replaceAll(r'\', '/');

/// עולה מתיקיית החבילה עד שורש המאגר, כדי שהבדיקה תעבוד מכל מקום.
Directory _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/AGENTS.md').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('לא נמצא שורש המאגר (AGENTS.md) מעל ${Directory.current.path}');
    }
    dir = parent;
  }
  return dir;
}

final _hebrewLetter = RegExp(r'[֐-׿]');

/// כל המחרוזות העבריות שאינן פטורות, לפי קובץ והקשר.
({List<_Literal> offenders, int filesScanned}) _scan(Directory root) {
  // `otzaria_l10n/lib` אינו ברשימה — הוא היעד, לא העבירה.
  const scanned = [
    'lib',
    'launcher_app/lib',
    'library_manager/lib',
    'otzaria_manager/lib',
    'plugins_manager/lib',
  ];

  final rootPath = _slashes(root.path);
  final offenders = <_Literal>[];
  var filesScanned = 0;

  for (final relative in scanned) {
    final dir = Directory('$rootPath/$relative');
    if (!dir.existsSync()) fail('תיקייה חסרה: $relative');

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      filesScanned++;
      final file = _slashes(entity.path).substring(rootPath.length + 1);
      if (_exemptFiles.containsKey(file)) continue;

      final src = entity.readAsStringSync();
      for (final literal in _stringLiterals(file, src)) {
        if (!_hebrewLetter.hasMatch(literal.value)) continue;
        final prefix = src.substring(
          literal.offset < 200 ? 0 : literal.offset - 200,
          literal.offset,
        );
        if (_developerContext.hasMatch(prefix)) continue;
        offenders.add(literal);
      }
    }
  }
  return (offenders: offenders, filesScanned: filesScanned);
}

String _key(_Literal literal) => '${literal.file}|${literal.value}';

void main() {
  test('אין מחרוזת עברית קשיחה חדשה מחוץ ל-otzaria_l10n', () {
    final result = _scan(_repoRoot());

    // הגנה מפני בדיקה שעוברת כי לא קראה כלום.
    expect(result.filesScanned, greaterThan(80));

    final unexpected =
        result.offenders.where((l) => !_knownViolations.contains(_key(l)));
    expect(
      unexpected,
      isEmpty,
      reason: 'מלל למשתמש חייב לחיות ב-otzaria_l10n:\n'
          '${unexpected.join('\n')}',
    );
  });

  test('ההפרות הידועות לא נעלמו ולא התרבו', () {
    // כשהן יתוקנו הבדיקה תיפול, וזה בדיוק הרגע להוריד אותן מהרשימה.
    final result = _scan(_repoRoot());
    expect(
      result.offenders.map(_key).toSet(),
      _knownViolations,
      reason: 'עדכנו את _knownViolations',
    );
  });

  test('רשימת הקבצים הפטורים אינה מתיישנת בשקט', () {
    final root = _slashes(_repoRoot().path);
    for (final entry in _exemptFiles.entries) {
      final file = File('$root/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      final hasHebrew = _stringLiterals(entry.key, file.readAsStringSync())
          .any((l) => _hebrewLetter.hasMatch(l.value));
      expect(hasHebrew, isTrue,
          reason: '${entry.key} כבר אינו זקוק לפטור (${entry.value})');
    }
  });
}
