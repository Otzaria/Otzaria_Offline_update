import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/tasks/task_parts.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  for (final language in AppLanguage.values) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('toast geometry across task transitions: $language / $scale',
          (tester) async {
        tester.view.physicalSize = const Size(950, 700);
        tester.view.devicePixelRatio = 1.25;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        AppL10n.use(language);
        addTearDown(() => AppL10n.use(AppLanguage.hebrew));
        final phase = ValueNotifier(0);
        addTearDown(phase.dispose);
        var actions = 0;
        final text = stringsOf(language);
        final button = ActionButton.ghost(
          text: text.task.backHome,
          onPressed: () => actions++,
        );
        await tester.pumpWidget(wrap(
          Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: phase,
              builder: (_, value, __) => switch (value) {
                1 => TaskFrame(start: button, child: const SizedBox.shrink()),
                2 => TaskResult(
                    badge: const SizedBox.shrink(),
                    title: '',
                    body: '',
                    actions: [button, button, button],
                  ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
          language: language,
          navigatorKey: navigatorKey,
        ));
        final message =
            List.filled(20, text.plugins.installDoneSnack('Example')).join(' ');
        UiSnack.showSuccess(message);
        await tester.pump();
        try {
          for (final value in [0, 1, 2, 0, 2, 1]) {
            phase.value = value;
            await tester.pump();
            final snack = find
                .ancestor(
                    of: find.text(message), matching: find.byType(Material))
                .first;
            final rect = tester.getRect(snack);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(760));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(560));
            expect(rect.center.dx, closeTo(380, 0.1));
            expect(
                MediaQuery.textScalerOf(tester.element(find.text(message)))
                    .scale(1),
                scale);
            if (value == 0) {
              expect(rect.bottom, closeTo(540, 0.1));
            } else {
              final anchor = tester.getRect(find.byType(UiSnackAnchor));
              expect(rect.bottom, lessThanOrEqualTo(anchor.top));
              await tester.tap(find.text(text.task.backHome).last);
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
          }
          expect(actions, 4);
        } finally {
          await tester.pump(const Duration(seconds: 7));
        }
      });
    }
  }

  testWidgets('only the painted anchor in an IndexedStack positions the toast',
      (tester) async {
    useViewSize(tester, const Size(760, 560));
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(wrap(
      Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (_, index, __) => IndexedStack(
            index: index,
            children: [
              for (final height in [68.0, 200.0])
                Column(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    UiSnackAnchor(child: SizedBox(height: height, width: 760)),
                  ],
                ),
            ],
          ),
        ),
      ),
      navigatorKey: navigatorKey,
    ));
    final message = stringsOf().plugins.installDoneSnack('Example');
    UiSnack.showSuccess(message);
    await tester.pump();
    try {
      for (final index in [0, 1, 0, 1]) {
        selected.value = index;
        await tester.pump();
        final anchorTop = index == 0 ? 492.0 : 360.0;
        final toast = find
            .ancestor(of: find.text(message), matching: find.byType(Material))
            .first;
        expect(tester.getRect(toast).bottom, closeTo(anchorTop - 16, 0.1));
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pump(const Duration(seconds: 7));
    }
  });
}
