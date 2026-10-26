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

    /// כפתור שמריץ את [action] — פתיחת הטופס או אישור המחיקה, כמו מדף הניהול.
    Future<void> pumpButton(
      WidgetTester tester,
      Future<void> Function(BuildContext context) action,
    ) async {
      await tester.runAsync(controller.load);
      await pumpScreen(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => action(context),
                      child: const Text('open')))),
          language: language,
          size: const Size(900, 1000));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, {CustomAppCategory? editing}) =>
        pumpButton(
          tester,
          (context) => showCustomAppCategoriesDialog(
            context: context,
            controller: controller,
            editing: editing,
          ),
        );

    Future<void> openRemove(WidgetTester tester) => pumpButton(
          tester,
          (context) => confirmRemoveCustomAppCategory(
            context,
            controller,
            controller.categories.single,
          ),
        );

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

    Finder inDialog(String text) => find.descendant(
        of: find.byType(AlertDialog), matching: find.text(text));

    ActionButton submit(WidgetTester tester, String text) =>
        tester.widget<ActionButton>(find.ancestor(
            of: inDialog(text), matching: find.byType(ActionButton)));

    bool dialogClosed() => find.byType(AlertDialog).evaluate().isEmpty;

    testWidgets('$language: blank and whitespace names cannot be submitted',
        (tester) async {
      await open(tester);
      expect(submit(tester, t.addCategoryButton).onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.pump();
      expect(submit(tester, t.addCategoryButton).onPressed, isNull);
      expect(controller.categories, isEmpty);
      await tap(tester, find.text(strings.common.cancel));
      expect(find.byType(AlertDialog), findsNothing);
    });

    // הרשימה, העריכה והמחיקה בדף הניהול — הדו-שיח הוא טופס אחד בלבד.
    testWidgets('$language: the dialog is only the form, not a second list',
        (tester) async {
      await tester.runAsync(() => controller.addCategory('לימוד'));
      await open(tester);
      expect(find.text('לימוד'), findsNothing);
      expect(find.text(t.noCategoriesHint), findsNothing);
      expect(find.byTooltip(t.editTooltip), findsNothing);
      expect(find.byTooltip(t.removeCategoryTooltip), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('$language: add persists trimmed name and description',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).first, '  לימוד  ');
      await tester.enterText(find.byType(TextField).last, '  כלים ללימוד  ');
      await tester.pump();
      await tap(tester, find.widgetWithText(ActionButton, t.addCategoryButton),
          completed: () => controller.categories.length == 1);
      expect(dialogClosed(), isTrue);
      expect(controller.categories.single.name, 'לימוד');
      expect(controller.categories.single.description, 'כלים ללימוד');
      await tester.runAsync(controller.load);
      expect(controller.categories.single.name, 'לימוד');
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
      await open(tester, editing: controller.categories.single);
      expect(find.text(t.editCategoryTitle), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'שינוי');
      await tap(tester, find.text(strings.common.cancel));
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.categories.single.slug, slug);
      expect(controller.categories.single.name, 'לימוד');
      expect(controller.categories.single.description, 'מקורי');
      expect(controller.appsIn(slug!).single.descriptor.id, 'demo');
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
      await open(tester, editing: controller.categories.single);
      await tester.enterText(find.byType(TextField).first, '  ספרים  ');
      await tester.enterText(find.byType(TextField).last, 'תיאור');
      await tester.pump();
      await tap(tester, inDialog(t.saveEditButton),
          completed: () => controller.categories.single.name == 'ספרים');
      expect(dialogClosed(), isTrue);
      expect(controller.categories.single.slug, slug);
      expect(controller.categories.single.name, 'ספרים');
      expect(controller.categories.single.description, 'תיאור');
      expect(controller.appsIn(slug).single.descriptor.id, 'demo');
    });

    testWidgets('$language: cancelled deletion preserves the category',
        (tester) async {
      await tester.runAsync(() => controller.addCategory('לימוד'));
      await openRemove(tester);
      expect(find.text(t.removeCategoryDialogTitle('לימוד')), findsOneWidget);
      await tap(tester, find.text(strings.common.cancel));
      expect(controller.categories, hasLength(1));
    });

    testWidgets('$language: confirmed deletion removes membership',
        (tester) async {
      final slug =
          (await tester.runAsync(() => controller.addCategory('לימוד')))!;
      await tester.runAsync(() => controller.add(AppDescriptor(
          id: 'demo',
          name: 'Demo',
          sourceKind: AppSourceKind.manual,
          categorySlugs: [slug],
          autoIcon: false)));
      await openRemove(tester);
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
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$language: opened on a category (from the manage page) '
        'starts with its fields filled', (tester) async {
      await tester.runAsync(controller.load);
      await tester.runAsync(
          () => controller.addCategory('לימוד', description: 'כלים ללימוד'));
      await open(tester, editing: controller.categories.single);

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller?.text)
          .toList();
      expect(fields, containsAll(['לימוד', 'כלים ללימוד']));
      await tap(tester, find.text(strings.common.cancel));
    });
  }
}
