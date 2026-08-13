@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// `analysis_options_shared.yaml` בשורש מחזיק את ההידוקים שחלים על **כל**
/// החבילות, וכל חבילה חייבת לייבא אותו לצד ערכת הבסיס שלה.
///
/// הבדיקה יושבת כאן מאותה סיבה כמו `no_hardcoded_strings_test.dart`: זו
/// החבילה שכולם תלויים בה, והיא Dart טהורה. בלי שומר, חבילה חדשה (או עריכה
/// של קובץ קיים) פשוט לא תקבל את ההידוקים ואיש לא ישים לב — בדיוק מה שקרה
/// ל-`prefer_single_quotes`, שהיה מופעל ב-`otzaria_l10n` לבדה.

const _sharedFileName = 'analysis_options_shared.yaml';

/// כל החבילות בריפו, לפי §2 ב-AGENTS.md. `.` הוא חבילת השורש.
const _packages = [
  '.',
  'otzaria_l10n',
  'otzaria_manager',
  'library_manager',
  'plugins_manager',
  'custom_apps_manager',
  'launcher_app',
];

/// ערכת הבסיס לכל חבילה: Flutter או Dart טהור. שמור כאן כדי שחבילה לא
/// תחליף ערכה בשקט — `flutter_lints` בחבילה בלי Flutter אינו פתיר.
const _expectedBase = {
  '.': 'package:flutter_lints/flutter.yaml',
  'library_manager': 'package:flutter_lints/flutter.yaml',
  'launcher_app': 'package:flutter_lints/flutter.yaml',
  'otzaria_l10n': 'package:lints/recommended.yaml',
  'otzaria_manager': 'package:lints/recommended.yaml',
  'plugins_manager': 'package:lints/recommended.yaml',
  'custom_apps_manager': 'package:lints/recommended.yaml',
};

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

void main() {
  final root = _repoRoot().path;

  test('הקובץ המשותף קיים ומחזיק הידוקים בפועל', () {
    final shared = File('$root/$_sharedFileName');
    expect(shared.existsSync(), isTrue, reason: _sharedFileName);

    final text = shared.readAsStringSync();
    // לא רק שהקובץ קיים — שהוא באמת מהדק משהו. קובץ שהתרוקן היה עובר בשקט.
    expect(text, contains('strict-casts: true'));
    expect(text, contains('unawaited_futures'));
    expect(text, contains('prefer_single_quotes'));
  });

  test('כל שבע החבילות מייבאות את הקובץ המשותף ואת ערכת הבסיס שלהן', () {
    for (final package in _packages) {
      final path = package == '.'
          ? '$root/analysis_options.yaml'
          : '$root/$package/analysis_options.yaml';
      final file = File(path);
      expect(file.existsSync(), isTrue,
          reason: 'ל-$package אין analysis_options.yaml — בלעדיו האנלייזר '
              'מטפס לשורש, יורש את ה-exclude שמחריג אותו, ולא בודק כלום');

      final text = file.readAsStringSync();
      // הנתיב יחסי, ולכן שונה לשורש ולתת-חבילה.
      final expectedInclude =
          package == '.' ? _sharedFileName : '../$_sharedFileName';
      expect(text, contains(expectedInclude),
          reason: '$package אינו מייבא את $_sharedFileName');
      expect(text, contains(_expectedBase[package]!),
          reason: '$package החליף את ערכת הבסיס שלו');
    }
  });

  test('רשימת החבילות כאן אינה מתיישנת — כל pubspec מכוסה', () {
    // חבילה חדשה שנוספה לריפו חייבת להצטרף לרשימה למעלה, אחרת השומר הזה
    // מסתיים בהצלחה בלי לבדוק אותה בכלל.
    final found = <String>[];
    for (final entity in Directory(root).listSync()) {
      if (entity is File && entity.path.endsWith('pubspec.yaml')) {
        found.add('.');
      } else if (entity is Directory &&
          File('${entity.path}/pubspec.yaml').existsSync()) {
        found.add(entity.path.split(Platform.pathSeparator).last);
      }
    }

    expect(found.toSet(), _packages.toSet());
  });
}
