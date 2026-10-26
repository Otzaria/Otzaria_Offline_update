import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/store_kit/store_screenshot_lightbox.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  testWidgets('צילום המסך בתצוגה המוגדלת מפוענח לכל היותר בגודל המסך',
      (tester) async {
    late ImageProvider provider;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1000, 700), devicePixelRatio: 2),
        child: Builder(
          builder: (context) {
            provider = screenBoundImage(context, 'shot.png');
            return const SizedBox();
          },
        ),
      ),
    );

    expect(provider, isA<ResizeImage>());
    final resized = provider as ResizeImage;
    expect(resized.width, 2048);
    expect(resized.height, 1408);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(resized.allowUpscaling, isFalse);
  });

  // "קדימה" הוא כיוון הקריאה: חץ שמאלה בעברית, ימינה באנגלית.
  for (final (language, forward) in [
    (AppLanguage.hebrew, LogicalKeyboardKey.arrowLeft),
    (AppLanguage.english, LogicalKeyboardKey.arrowRight),
  ]) {
    testWidgets('$language: החצים מתקדמים לפי כיוון השפה, ו-Esc סוגר',
        (tester) async {
      final t = stringsOf(language).plugins;
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showStoreScreenshots(
              context,
              paths: const ['a.png', 'b.png', 'c.png'],
              initialIndex: 0,
            ),
            child: const Text('open'),
          ),
        ),
        language: language,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(t.screenshotNumber(1, 3)), findsOneWidget);

      await tester.sendKeyEvent(forward);
      await tester.pump();
      expect(find.text(t.screenshotNumber(2, 3)), findsOneWidget);

      // מהראשון אחורה — מסתובב לאחרון.
      await tester.tap(find.byTooltip(t.screenshotPrevious));
      await tester.pump();
      await tester.tap(find.byTooltip(t.screenshotPrevious));
      await tester.pump();
      expect(find.text(t.screenshotNumber(3, 3)), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(t.screenshotNumber(3, 3)), findsNothing);
    });
  }

  // הכפתורים עקביים עם החצים: בעברית → הוא "הקודם", ולכן "הקודם" בצד ימין.
  for (final (language, previousOnRight) in [
    (AppLanguage.hebrew, true),
    (AppLanguage.english, false),
  ]) {
    testWidgets('$language: "הקודם" בצד שממנו באים', (tester) async {
      final t = stringsOf(language).plugins;
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showStoreScreenshots(
              context,
              paths: const ['a.png', 'b.png'],
              initialIndex: 0,
            ),
            child: const Text('open'),
          ),
        ),
        language: language,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final previous = tester.getCenter(find.byTooltip(t.screenshotPrevious));
      final next = tester.getCenter(find.byTooltip(t.screenshotNext));
      expect(previous.dx > next.dx, previousOnRight);
    });
  }
}
