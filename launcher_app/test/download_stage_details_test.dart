import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/screens/tasks/download_task_view.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  for (final language in AppLanguage.values) {
    for (final size in [const Size(760, 560), const Size(1000, 720)]) {
      final label = '${language.name} $size';
      final strings = stringsOf(language);

      testWidgets('plugin stage updates and clears when finished (#202) $label',
          (tester) async {
        final progress = ValueNotifier(0);
        addTearDown(progress.dispose);
        final first = strings.pluginsDomain.syncPlugin('First plugin', 1, 4);
        final next = strings.pluginsDomain.syncPlugin('Next plugin', 2, 4);
        var snapshot = DownloadSnapshot(
          current: MirrorComponent.plugins,
          fraction: 0.25,
          stages: {MirrorComponent.plugins: first},
        );
        await pumpScreen(
          tester,
          DownloadTaskView(
            task: const DownloadTask(
              phase: DownloadTaskPhase.running,
              components: [MirrorComponent.plugins],
            ),
            progress: progress,
            snapshot: () => snapshot,
            actions: DownloadTaskActions(
              onAnswer: (_) {},
              onCancel: () {},
              onRetry: () {},
              onHome: () {},
              onHere: () {},
            ),
          ),
          language: language,
          size: size,
        );
        expect(find.text(first), findsOneWidget);

        snapshot = DownloadSnapshot(
          current: MirrorComponent.plugins,
          fraction: 0.5,
          stages: {MirrorComponent.plugins: next},
        );
        progress.value++;
        await tester.pump();
        expect(find.text(first), findsNothing);
        expect(find.text(next), findsOneWidget);

        snapshot = DownloadSnapshot(
          finished: const {MirrorComponent.plugins},
          stages: {MirrorComponent.plugins: next},
        );
        progress.value++;
        await tester.pump();
        expect(find.text(next), findsNothing);
        expect(tester.widget<StageRow>(find.byType(StageRow)).state,
            StageState.done);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'library, companions and plugins show simultaneous stages (#202) $label',
          (tester) async {
        final progress = ValueNotifier(0);
        addTearDown(progress.dispose);
        final library = strings.libraryDomain.exportDownloading(
          'v35',
          'seforim-library-very-long-file-name.db.zst',
        );
        final companion = strings.libraryDomain.companionDownloading(
          List.filled(6, 'Companion').join(' '),
        );
        final plugin = strings.pluginsDomain.syncPlugin(
          List.filled(10, 'Plugin').join(' '),
          3,
          10,
        );
        final libraryStages = '$library\n$companion';
        var snapshot = DownloadSnapshot(
          current: MirrorComponent.app,
          stages: {
            MirrorComponent.library: libraryStages,
            MirrorComponent.plugins: plugin,
          },
        );
        var hidden = false;
        var cancelled = false;
        await pumpScreen(
          tester,
          DownloadTaskView(
            task: const DownloadTask(
              phase: DownloadTaskPhase.running,
              components: [
                MirrorComponent.app,
                MirrorComponent.library,
                MirrorComponent.plugins,
              ],
            ),
            progress: progress,
            snapshot: () => snapshot,
            actions: DownloadTaskActions(
              onAnswer: (_) {},
              onCancel: () => cancelled = true,
              onHide: () => hidden = true,
              onRetry: () {},
              onHome: () {},
              onHere: () {},
            ),
          ),
          language: language,
          size: size,
        );
        expect(find.text(libraryStages), findsNothing);
        expect(find.text(plugin), findsNothing);

        snapshot = DownloadSnapshot(
          current: MirrorComponent.library,
          fraction: 0.3,
          received: 300,
          total: 1000,
          others: const {MirrorComponent.plugins: 0.3},
          finished: const {MirrorComponent.app},
          stages: {
            MirrorComponent.library: libraryStages,
            MirrorComponent.plugins: plugin,
          },
        );
        progress.value++;
        await tester.pump();
        final rows =
            tester.widgetList<StageRow>(find.byType(StageRow)).toList();
        expect(rows.map((row) => row.state), [
          StageState.done,
          StageState.current,
          StageState.current,
        ]);
        expect(
          find.descendant(
            of: find.byWidget(rows[1]),
            matching: find.text(libraryStages),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byWidget(rows[2]),
            matching: find.text(plugin),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text(plugin));
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(ShellKeys.taskHide));
        await tester.tap(find.byKey(ShellKeys.taskCancel));
        expect(hidden, isTrue);
        expect(cancelled, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
