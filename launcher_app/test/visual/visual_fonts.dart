// גופנים אמיתיים לצילומי הסקירה. Segoe UI אינו מופץ עם הריפו, ולכן נטען
// מ-C:\Windows\Fonts — הצילומים רצים רק ב-Windows.

import 'dart:io';

import 'package:flutter/services.dart';

const _windowsFonts = r'C:\Windows\Fonts';

/// מלכוד: סגנון בלי `fontFamily` שאינו יורש מה-theme יוצא כאן במשבצות של גופן
/// הבדיקות, אף שב-Windows הוא נופל ל-Segoe UI.
const _uiFamilies = ['Segoe UI'];
const _uiFiles = ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'];

const _monoFamilies = ['Consolas', 'monospace'];
const _monoFiles = ['consola.ttf', 'consolab.ttf'];

const _iconFonts = {
  'packages/fluentui_system_icons/FluentSystemIcons-Regular':
      'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf',
  'packages/fluentui_system_icons/FluentSystemIcons-Filled':
      'packages/fluentui_system_icons/fonts/FluentSystemIcons-Filled.ttf',
};

/// חייב לרוץ בתוך `tester.runAsync` — קריאות דיסק אמיתיות.
Future<void> loadVisualFonts() async {
  Future<ByteData> windowsFont(String name) async => ByteData.sublistView(
        await File('$_windowsFonts\\$name').readAsBytes(),
      );

  Future<void> load(List<String> families, List<String> files) async {
    final data = [for (final f in files) await windowsFont(f)];
    for (final family in families) {
      final loader = FontLoader(family);
      for (final d in data) {
        loader.addFont(Future.value(d));
      }
      await loader.load();
    }
  }

  await load(_uiFamilies, _uiFiles);
  await load(_monoFamilies, _monoFiles);
  for (final MapEntry(key: family, value: asset) in _iconFonts.entries) {
    await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
  }
}
