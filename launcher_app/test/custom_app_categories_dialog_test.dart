import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_categories_dialog.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';
import 'test_support.dart';

void main() {
  late Directory temporary;
  late CustomAppsController controller;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('category-dialog-');
    await AppLogger.init(temporary.path);
    controller =
        CustomAppsController(mirrorRootDir: p.join(temporary.path, 'mirror'));
  });
  tearDown(() async {
    controller.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  for (final language in AppLanguage.values) {
    final strings = stringsOf(language);
    final t = strings.customApps;

    Future<void> open(WidgetTester tester) async {
      await tester.runAsync(controller.load);
      await pumpScreen(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showCustomAppCategoriesDialog(
                          context: context, controller: controller),
                      child: const Text('open')))),
          language: language,
          size: const Size(900, 1000));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder finder,
        {bool Function()? completed}) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      if (completed != null) {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
          if (completed()) break;
        }
        expect(completed(), isTrue, reason: 'disk operation did not complete');
      }
      await tester.pumpAndSettle();
    }

    testWidgets('$language: blank and whitespace names cannot be submitted',
        (tester) async {
      await open(tester);
      ActionButton button() => tester.widget<ActionButton>(find.ancestor(
          of: find.text(t.addCategoryButton),
          matching: find.byType(ActionButton)));
      expect(button().onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.pump();
      expect(button().onPressed, isNull);
      expect(controller.categories, isEmpty);
      expect(find.text(t.noCategoriesHint), findsOneWidget);
      await tap(tester, find.text(strings.common.close));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
        '$language: add persists trimmed name and description across reopen',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).first, '  לימוד  ');
      await tester.enterText(find.byType(TextField).last, '  כלים ללימוד  ');
      await tester.pump();
      await tap(tester, find.text(t.addCategoryButton),
          completed: () =>
              controller.categories.length == 1 &&
              tester
                  .widget<TextField>(find.byType(TextField).first)
                  .controller!
                  .text
                  .isEmpty);
      expect(controller.categories.single.name, 'לימוד');
      expect(controller.categories.single.description, 'כלים ללימוד');
      expect(find.text('לימוד'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          isEmpty);
      await tap(tester, find.text(strings.common.close));
      await tester.runAsync(controller.load);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('לימוד'), findsOneWidget);
      expect(find.text('כלים ללימוד'), findsOneWidget);
    });

    testWidgets(
        '$language: cancelling edit preserves category and assigned apps',
        (tester) async {
      final slug = await tester.runAsync(
          () => controller.addCategory('לימוד', description: 'מקורי'));
      await tester.runAsync(() => controller.add(AppDescriptor(
          id: 'demo',
          name: 'Demo',
          sourceKind: AppSourceKind.manual,
          categorySlugs: [slug!],
          autoIcon: false)));
      await open(tester);
      await tap(tester, find.byTooltip(t.editTooltip));
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'לימוד');
      await tester.enterText(find.byType(TextField).first, 'שינוי');
      await tap(tester, find.text(strings.common.cancel));
      expect(controller.categories.single.slug, slug);
      expect(controller.categories.single.name, 'לימוד');
      expect(controller.categories.single.description, 'מקורי');
      expect(controller.appsIn(slug!).single.descriptor.id, 'demo');
      expect(find.text(t.addCategoryButton), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          isEmpty);
    });

    testWidgets('$language: rename preserves slug and app membership',
        (tester) async {
      final slug =
          (await tester.runAsync(() => controller.addCategory('לימוד')))!;
      await tester.runAsync(() => controller.add(AppDescriptor(
          id: 'demo',
          name: 'Demo',
          sourceKind: AppSourceKind.manual,
          categorySlugs: [slug],
          autoIcon: false)));
      await open(tester);
      expect(find.text(t.categoryAppCount(1)), findsOneWidget);
      await tap(tester, find.byTooltip(t.editTooltip));
      await tester.enterText(find.byType(TextField).first, '  ספרים  ');
      await tester.enterText(find.byType(TextField).last, 'תיאור');
      await tester.pump();
      await tap(tester, find.text(t.saveEditButton),
          completed: () =>
              controller.categories.single.name == 'ספרים' &&
              tester
                  .widget<TextField>(find.byType(TextField).first)
                  .controller!
                  .text
                  .isEmpty);
      expect(controller.categories.single.slug, slug);
      expect(controller.categories.single.name, 'ספרים');
      expect(controller.appsIn(slug).single.descriptor.id, 'demo');
      expect(find.text('ספרים'), findsOneWidget);
      expect(find.text('תיאור'), findsOneWidget);
    });

    testWidgets('$language: cancelled deletion preserves the category',
        (tester) async {
      await tester.runAsync(() => controller.addCategory('לימוד'));
      await open(tester);
      await tap(tester, find.byTooltip(t.removeCategoryTooltip));
      expect(find.text(t.removeCategoryDialogTitle('לימוד')), findsOneWidget);
      await tap(tester, find.text(strings.common.cancel));
      expect(controller.categories, hasLength(1));
      expect(find.text('לימוד'), findsOneWidget);
    });

    testWidgets(
        '$language: confirmed deletion removes membership and updates open dialog',
        (tester) async {
      final slug =
          (await tester.runAsync(() => controller.addCategory('לימוד')))!;
      await tester.runAsync(() => controller.add(AppDescriptor(
          id: 'demo',
          name: 'Demo',
          sourceKind: AppSourceKind.manual,
          categorySlugs: [slug],
          autoIcon: false)));
      await open(tester);
      await tap(tester, find.byTooltip(t.removeCategoryTooltip));
      expect(
          find.text(t.removeCategoryDialogContent('לימוד', 1)), findsOneWidget);
      final confirm = find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.text(t.removeCategoryTooltip));
      await tap(tester, confirm,
          completed: () =>
              controller.categories.isEmpty &&
              controller.apps.single.descriptor.categorySlugs.isEmpty);
      expect(controller.categories, isEmpty);
      expect(controller.uncategorizedApps.single.descriptor.id, 'demo');
      expect(controller.apps.single.descriptor.categorySlugs, isEmpty);
      expect(find.text('לימוד'), findsNothing);
      expect(find.text(t.noCategoriesHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
