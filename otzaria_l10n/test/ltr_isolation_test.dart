@TestOn('vm')
library;

import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

/// פרמטר שמחזיק גרסה, כונן, נתיב, שם קובץ או כתובת — טקסט LTR.
final _ltrParam = RegExp(
  r'^(version|\w+Version|stable|prerelease|installed|onDrive|needs|here|'
  r'tag|tagName|releaseTag|path|\w+Path|dir|\w+Dir|letter|fileName|exeName|'
  r'asset|url|machineName)$',
);

final _header = RegExp(r'^  (?:String|Future<String>)\s+(\w+)\(');

/// כל מתודה ב-strings_he: השם, הפרמטרים מסוג String והגוף.
Iterable<({String name, List<String> params, String body})> _methods(
  String source,
) sync* {
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final header = _header.firstMatch(lines[i]);
    if (header == null) continue;
    var j = i + 1;
    while (j < lines.length &&
        !lines[j].startsWith('  @override') &&
        !lines[j].startsWith('}') &&
        _header.firstMatch(lines[j]) == null) {
      j++;
    }
    final text = lines.sublist(i, j).join('\n');
    final signature =
        RegExp(r'\((.*?)\)\s*(=>|\{)', dotAll: true).firstMatch(text);
    if (signature == null) continue;
    yield (
      name: header.group(1)!,
      params: [
        for (final m
            in RegExp(r'String\??\s+(\w+)').allMatches(signature.group(1)!))
          m.group(1)!,
      ],
      body: text.substring(signature.end),
    );
  }
}

void main() {
  final he = AppL10n.stringsFor(AppLanguage.hebrew);

  test('גרסת beta וכונן נשארים בכיוון שלהם בתוך עברית', () {
    expect(
      he.appScreen.channelPair('0.10.4', '0.10.5-beta'),
      contains('\u20660.10.5-beta\u2069'),
    );
    expect(he.guide.drive('C:'), 'כונן \u2066C:\u2069');
    expect(he.pages.appWhatsNew('0.10.5'), contains('\u20660.10.5\u2069'));
  });

  test('כל תבנית עם גרסה, כונן או נתיב מבודדת אותם ב-_ltr', () {
    final source = File('lib/src/strings_he.dart').readAsStringSync();
    final offenders = <String>[];
    var checked = 0;
    for (final method in _methods(source)) {
      for (final param in method.params.where(_ltrParam.hasMatch)) {
        checked++;
        final raw = RegExp('\\\$(\\{$param\\}|$param(?![A-Za-z0-9_]))');
        if (raw.hasMatch(method.body)) offenders.add('${method.name}($param)');
      }
    }
    expect(checked, greaterThan(50), reason: 'הסורק לא מצא את התבניות');
    expect(offenders, isEmpty);
  });
}
