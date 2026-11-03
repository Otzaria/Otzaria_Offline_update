import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/tasks/update_here_task_view.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

const _done = UpdateHereTask(
  phase: UpdateHereTaskPhase.done,
  stages: [GuidanceItem.plugins],
  outcomes: {GuidanceItem.plugins: StageOutcome.done},
  plugins: [PluginDelivery('Example', PluginDeliveryState.sent)],
);

Widget _task(UpdateHereTask task, VoidCallback onHome) => UpdateHereTaskView(
      task: task,
      libraryProgress: const AlwaysStoppedAnimation(0),
      librarySnapshot: () => const LibraryApplySnapshot(),
      actions: UpdateHereActions(
        onRespond: (_) {},
        onStopWaiting: () {},
        onFinishWithoutWaiting: () {},
        onLaunch: () {},
        onHome: onHome,
        onRetry: () {},
        onOpenPage: (_) {},
        onHide: onHome,
      ),
    );

Widget _result(VoidCallback onHome) => _task(_done, onHome);

Finder _snack(String message) => find
    .ancestor(of: find.text(message), matching: find.byType(Material))
    .first;

void main() {
  for (final language in AppLanguage.values) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'plugin completion toast leaves actions usable in $language at $scale',
          (tester) async {
        useViewSize(tester, const Size(760, 560));
        AppL10n.use(language);
        addTearDown(() => AppL10n.use(AppLanguage.hebrew));
        final t = stringsOf(language);
        final completed = ValueNotifier(false);
        addTearDown(completed.dispose);
        var homeCalls = 0;
        await tester.pumpWidget(wrap(
          MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: ValueListenableBuilder<bool>(
              valueListenable: completed,
              builder: (_, done, __) =>
                  done ? _result(() => homeCalls++) : const SizedBox.shrink(),
            ),
          ),
          language: language,
          navigatorKey: navigatorKey,
        ));

        final message = t.plugins.installDoneSnack('Example');
        UiSnack.showSuccess(message);
        await tester.pump();
        completed.value = true;
        await tester.pump();

        try {
          final snackRect = tester.getRect(_snack(message));
          final actionsRect =
              tester.getRect(find.byKey(const ValueKey('task.result.actions')));
          await tester.tap(find.text(t.task.backHome), warnIfMissed: false);
          expect(
            (overlap: snackRect.overlaps(actionsRect), homeCalls: homeCalls),
            (overlap: false, homeCalls: 1),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pump(const Duration(seconds: 7));
        }
      });
    }
  }

  testWidgets('running-task actions stay clear when the window is resized',
      (tester) async {
    useViewSize(tester, const Size(760, 560));
    var homeCalls = 0;
    await tester.pumpWidget(wrap(
      _task(
        const UpdateHereTask(
          phase: UpdateHereTaskPhase.running,
          stages: [GuidanceItem.library],
        ),
        () => homeCalls++,
      ),
      navigatorKey: navigatorKey,
    ));
    final t = stringsOf();
    final message = t.plugins.installDoneSnack('Example');
    UiSnack.showSuccess(message);
    await tester.pump();

    try {
      for (final size in [const Size(760, 560), const Size(640, 480)]) {
        tester.view.physicalSize = size;
        await tester.pump();
        final actionsRect = tester.getRect(find.byType(UiSnackAnchor));
        expect(tester.getRect(_snack(message)).bottom,
            lessThanOrEqualTo(actionsRect.top));
        await tester.tap(find.text(t.task.backHome));
      }
      expect(homeCalls, 2);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pump(const Duration(seconds: 7));
    }
  });

  testWidgets('toast returns to the bottom when the task is hidden',
      (tester) async {
    useViewSize(tester, const Size(760, 560));
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(wrap(
      ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, show, __) =>
            show ? _result(() {}) : const SizedBox.shrink(),
      ),
      navigatorKey: navigatorKey,
    ));
    final message = stringsOf().plugins.installDoneSnack('Example');
    UiSnack.showSuccess(message);
    await tester.pump();

    try {
      final actionsRect =
          tester.getRect(find.byKey(const ValueKey('task.result.actions')));
      expect(tester.getRect(_snack(message)).bottom,
          lessThanOrEqualTo(actionsRect.top));

      visible.value = false;
      await tester.pump();
      expect(tester.getRect(_snack(message)).bottom, closeTo(540, 0.01));

      visible.value = true;
      await tester.pump();
      final restoredActions =
          tester.getRect(find.byKey(const ValueKey('task.result.actions')));
      expect(tester.getRect(_snack(message)).bottom,
          lessThanOrEqualTo(restoredActions.top));
    } finally {
      await tester.pump(const Duration(seconds: 7));
    }
  });
}
