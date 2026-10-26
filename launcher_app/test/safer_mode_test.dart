import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

import 'test_harness.dart';

/// בדיקות למצב סייפר — ערבול הסיסמה, המצב הנגזר, שומר הסף והכרטיס שבמסך.
///
/// **מה שאינו נבדק כאן במתכוון:** שהנעילה עומדת מול מי שעורך את קובץ
/// ההגדרות בעצמו. היא לא, וגם לא נועדה לכך — ראו `SaferModePassword`.
void main() {
  group('SaferModePassword — ערבול ואימות', () {
    test('הסיסמה עצמה אינה מופיעה בערך השמור', () {
      final stored = SaferModePassword.encode('סיסמה-סודית');

      expect(stored, isNot(contains('סיסמה-סודית')));
      expect(stored.split(':'), hasLength(2));
    });

    test('הסיסמה הנכונה מאומתת, וכל אחרת נדחית', () {
      final stored = SaferModePassword.encode('1234');

      expect(SaferModePassword.verify(stored, '1234'), isTrue);
      expect(SaferModePassword.verify(stored, '1235'), isFalse);
      expect(SaferModePassword.verify(stored, ''), isFalse);
      expect(SaferModePassword.verify(stored, '1234 '), isFalse);
    });

    test('מלח חדש בכל פעם — אותה סיסמה אינה נראית אותו דבר', () {
      final first = SaferModePassword.encode('1234');
      final second = SaferModePassword.encode('1234');

      expect(first, isNot(second));
      expect(SaferModePassword.verify(first, '1234'), isTrue);
      expect(SaferModePassword.verify(second, '1234'), isTrue);
    });

    test('ערך ריק או פגום נדחה ואינו זורק', () {
      expect(SaferModePassword.verify('', '1234'), isFalse);
      expect(SaferModePassword.verify('בלי-נקודתיים', '1234'), isFalse);
      expect(SaferModePassword.verify(':', '1234'), isFalse);
      expect(SaferModePassword.verify('a:b:c', '1234'), isFalse);
    });
  });

  group('AppSettings — המצב הנגזר', () {
    test('מתג דלוק בלי סיסמה אינו נועל דבר', () {
      const s = AppSettings(saferModeEnabled: true);

      expect(s.hasSaferModePassword, isFalse);
      expect(s.saferModeActive, isFalse);
    });

    test('סיסמה בלי מתג אינה נועלת דבר', () {
      final s = AppSettings(
        saferModePassword: SaferModePassword.encode('1234'),
      );

      expect(s.hasSaferModePassword, isTrue);
      expect(s.saferModeActive, isFalse);
    });

    test('מתג וסיסמה יחד — נעול', () {
      final s = AppSettings(
        saferModeEnabled: true,
        saferModePassword: SaferModePassword.encode('1234'),
      );

      expect(s.saferModeActive, isTrue);
    });

    test('סבב JSON שומר את שני השדות', () {
      final s = AppSettings(
        saferModeEnabled: true,
        saferModePassword: SaferModePassword.encode('1234'),
      );

      final back = AppSettings.fromJson(s.toJson());

      expect(back.saferModeEnabled, isTrue);
      expect(back.saferModePassword, s.saferModePassword);
      expect(SaferModePassword.verify(back.saferModePassword, '1234'), isTrue);
    });

    test('קובץ מלפני השדות — לא נעול, בלי לזרוק', () {
      final back = AppSettings.fromJson({
        'schemaVersion': 9,
        'ui': {'themeMode': 'dark'},
      });

      expect(back.saferModeEnabled, isFalse);
      expect(back.saferModePassword, isEmpty);
      expect(back.saferModeActive, isFalse);
    });

    test('סעיף protection פגום נופל לברירת המחדל', () {
      final back = AppSettings.fromJson({
        'protection': {'enabled': 'כן', 'password': 42},
      });

      expect(back.saferModeEnabled, isFalse);
      expect(back.saferModePassword, isEmpty);
    });
  });

  group('SaferModeGate — האימות מחזיק להרצה אחת', () {
    late Directory dir;
    late SettingsController controller;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('safer_mode_gate');
      controller = SettingsController(dataDir: dir.path);
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('בלי מצב סייפר — לא נעול מלכתחילה', () {
      expect(SaferModeGate(controller).isLocked, isFalse);
    });

    test('מצב פעיל נעול עד לאימות, ואחריו נשאר פתוח', () async {
      await controller.update(
        AppSettings(
          saferModeEnabled: true,
          saferModePassword: SaferModePassword.encode('1234'),
        ),
      );
      final gate = SaferModeGate(controller);

      expect(gate.isLocked, isTrue);
      gate.unlock();
      expect(gate.isLocked, isFalse);
      // מחיקת הסיסמה מחזירה את השער למצב "לא אומת".
      gate.lock();
      expect(gate.isLocked, isTrue);
    });
  });

  group('הגדרות › מתקדם — הנעילה בסיסמה', () {
    late Directory dir;
    late SettingsController settings;
    late SaferModeGate gate;
    final t = stringsOf().saferMode;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('safer_mode_screen');
      settings = SettingsController(dataDir: dir.path);
      gate = SaferModeGate(settings);
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    Widget screen({bool readOnly = false}) => SettingsScreen(
          controller: settings,
          onOpenLog: () {},
          launcherVersion: '0.8.0',
          saferMode: gate,
          readOnly: readOnly,
        );

    /// הנעילה יושבת תחת "מתקדם", שמקופל בכניסה.
    Future<void> pumpAdvanced(WidgetTester tester,
        {bool readOnly = false}) async {
      await pumpScreen(tester, screen(readOnly: readOnly));
      await tester.tap(find.text(stringsOf().pages.advancedTitle));
      await tester.pumpAndSettle();
    }

    Future<void> withPassword(WidgetTester tester, {bool on = false}) =>
        tester.runAsync(
          () => settings.update(
            AppSettings(
              saferModeEnabled: on,
              saferModePassword: SaferModePassword.encode('1234'),
            ),
          ),
        );

    ActionButton button(WidgetTester tester, String text) =>
        tester.widget<ActionButton>(find.widgetWithText(ActionButton, text));

    testWidgets('בלי סיסמה — מציעים לקבוע אחת ואין מתג', (tester) async {
      await pumpAdvanced(tester);

      expect(find.text(t.noPasswordSubtitle), findsOneWidget);
      expect(find.text(t.setPasswordButton), findsOneWidget);
      expect(find.text(t.changeButton), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings.lock')),
          matching: find.byType(Switch),
        ),
        findsNothing,
      );
    });

    testWidgets('סיסמה ראשונה נשמרת ומפעילה את הנעילה, אחרי אימות שני השדות',
        (tester) async {
      await pumpAdvanced(tester);

      await tester.tap(find.text(t.setPasswordButton));
      await tester.pumpAndSettle();
      expect(
          find.text(t.setIntro(SaferModePassword.minLength)), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));

      // קצרה מדי, ואחר כך לא זהות — שגיאה בתוך הדו-שיח, ושום דבר לא נשמר.
      await tester.enterText(fields.at(0), '12');
      await tester.enterText(fields.at(1), '12');
      await tester.tap(find.text(t.setConfirm));
      await tester.pumpAndSettle();
      expect(
        find.text(t.passwordTooShort(SaferModePassword.minLength)),
        findsOneWidget,
      );
      await tester.enterText(fields.at(0), '1234');
      await tester.enterText(fields.at(1), '1235');
      await tester.tap(find.text(t.setConfirm));
      await tester.pumpAndSettle();
      expect(find.text(t.passwordsDoNotMatch), findsOneWidget);
      expect(settings.settings.hasSaferModePassword, isFalse);

      await tester.enterText(fields.at(1), '1234');
      await tester.tap(find.text(t.setConfirm));
      await tester.pumpAndSettle();

      expect(
        SaferModePassword.verify(settings.settings.saferModePassword, '1234'),
        isTrue,
      );
      expect(settings.settings.saferModeActive, isTrue);
      // מי שקבע אותה זה עתה אינו נשאל עליה שוב בהרצה הזו.
      expect(gate.isLocked, isFalse);
    });

    testWidgets('בכונן מוגן ההסבר אומר שההגדרות שבמחשב הזה', (tester) async {
      await pumpAdvanced(tester, readOnly: true);

      await tester.tap(find.text(t.setPasswordButton));
      await tester.pumpAndSettle();
      final intro = t.setIntro(
        SaferModePassword.minLength,
        onThisComputer: true,
      );
      expect(find.text(intro), findsOneWidget);
      expect(intro, contains('שבמחשב הזה'));
      expect(intro, isNot(contains('שבכונן')));
    });

    testWidgets('עם סיסמה — מתג, החלפה ומחיקה', (tester) async {
      await withPassword(tester);
      await pumpAdvanced(tester);

      expect(find.text(t.lockOffSubtitle), findsOneWidget);
      expect(button(tester, t.changeButton).onPressed, isNotNull);
      expect(button(tester, t.clearButton).onPressed, isNotNull);
    });

    testWidgets('כשהנעילה פעילה המחיקה מושבתת ומוסברת', (tester) async {
      await withPassword(tester, on: true);
      await pumpAdvanced(tester);

      expect(button(tester, t.clearButton).onPressed, isNull);
      expect(find.text(t.passwordRowLockedSubtitle), findsOneWidget);
    });

    testWidgets('החלפה מבקשת את הנוכחית; שגויה אינה מחליפה', (tester) async {
      await withPassword(tester);
      await pumpAdvanced(tester);
      final before = settings.settings.saferModePassword;

      await tester.tap(find.text(t.changeButton));
      await tester.pumpAndSettle();
      expect(find.text(t.changeTitle), findsOneWidget);
      expect(find.text(t.currentPasswordLabel), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      // כפתור "הצג" שבשדה לא מגביה אותו מעל גובה השדה.
      expect(tester.getSize(fields.first).height, 44);

      await tester.enterText(fields.at(0), '0000');
      await tester.enterText(fields.at(1), '5678');
      await tester.enterText(fields.at(2), '5678');
      await tester.tap(find.widgetWithText(ActionButton, t.changeButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.wrongPassword), findsOneWidget);
      expect(settings.settings.saferModePassword, before);
      // השגיאה מתחת לשדה הנוכחית (ולא מתחת לאחרון), והשדה נוקה ומוקד.
      final errorTop = tester.getTopLeft(find.text(t.wrongPassword)).dy;
      expect(errorTop, greaterThan(tester.getBottomLeft(fields.at(0)).dy));
      expect(errorTop, lessThan(tester.getTopLeft(fields.at(1)).dy));
      final current = tester.widget<EditableText>(
        find.descendant(of: fields.at(0), matching: find.byType(EditableText)),
      );
      expect(current.controller.text, isEmpty);
      expect(current.focusNode.hasFocus, isTrue);

      // אי-התאמה — מתחת לשדה האימות.
      await tester.enterText(fields.at(0), '1234');
      await tester.enterText(fields.at(2), '5679');
      await tester.tap(find.widgetWithText(ActionButton, t.changeButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.wrongPassword), findsNothing);
      expect(
        tester.getTopLeft(find.text(t.passwordsDoNotMatch)).dy,
        greaterThan(tester.getBottomLeft(fields.at(2)).dy),
      );
      await tester.enterText(fields.at(2), '5678');

      await tester.enterText(fields.at(0), '1234');
      await tester.tap(find.widgetWithText(ActionButton, t.changeButton).last);
      await tester.pumpAndSettle();
      expect(
        SaferModePassword.verify(settings.settings.saferModePassword, '5678'),
        isTrue,
      );
    });

    testWidgets('מחיקה דורשת את הסיסמה הנוכחית, ואז נועלת מחדש את השער',
        (tester) async {
      await withPassword(tester);
      gate.unlock();
      await pumpAdvanced(tester);

      await tester.tap(find.text(t.clearButton));
      await tester.pumpAndSettle();
      expect(find.text(t.clearDialogTitle), findsOneWidget);

      // שדה ריק — "יש להקליד סיסמה", לא "הסיסמה לא נכונה".
      await tester.tap(find.widgetWithText(ActionButton, t.clearButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.passwordRequired), findsOneWidget);
      expect(find.text(t.wrongPassword), findsNothing);

      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.widgetWithText(ActionButton, t.clearButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.wrongPassword), findsOneWidget);
      expect(settings.settings.hasSaferModePassword, isTrue);

      // Enter עם שדה ריק או סיסמה שגויה מראה את השגיאה — לא ממקד בשקט את
      // הביטול, ש-Enter נוסף היה סוגר.
      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(t.passwordRequired), findsOneWidget);
      await tester.enterText(find.byType(TextField), '9999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(t.wrongPassword), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(t.clearDialogTitle), findsOneWidget);

      // Enter בשדה אינו מוחק: הביטול מקבל את המיקוד, ו-Enter נוסף מבטל.
      await tester.enterText(find.byType(TextField), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(t.clearDialogTitle), findsOneWidget);
      expect(find.text(t.wrongPassword), findsNothing);
      expect(find.text(t.passwordRequired), findsNothing);
      expect(settings.settings.hasSaferModePassword, isTrue);
      final cancel = find.widgetWithText(
        FilledButton,
        stringsOf().common.cancel,
      );
      expect(
          Focus.of(tester.element(find.descendant(
            of: cancel,
            matching: find.text(stringsOf().common.cancel),
          ))).hasFocus,
          isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(t.clearDialogTitle), findsNothing);
      expect(settings.settings.hasSaferModePassword, isTrue);

      // מחיקה רק בלחיצה מפורשת.
      await tester.tap(find.text(t.clearButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.widgetWithText(ActionButton, t.clearButton).last);
      await tester.pumpAndSettle();
      expect(settings.settings.hasSaferModePassword, isFalse);
      expect(settings.settings.saferModeEnabled, isFalse);
      expect(find.text(t.setPasswordButton), findsOneWidget);
    });

    testWidgets('המתג מבקש את הסיסמה לפני הפעלה', (tester) async {
      await withPassword(tester);
      await pumpAdvanced(tester);

      await tester.tap(find.text(t.lockTitle));
      await tester.pumpAndSettle();
      expect(find.text(t.verifyEnableHint), findsOneWidget);
      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pumpAndSettle();
      expect(settings.settings.saferModeEnabled, isFalse);

      await tester.tap(find.text(t.lockTitle));
      await tester.pumpAndSettle();
      // בהפעלה ובכיבוי "אישור"; "כניסה" רק כשהסיסמה פותחת דף.
      expect(find.text(t.enterButton), findsNothing);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(stringsOf().common.confirm));
      await tester.pumpAndSettle();
      expect(settings.settings.saferModeEnabled, isTrue);
    });

    testWidgets('איפוס ההגדרות אינו פותח את הנעילה', (tester) async {
      final stored = SaferModePassword.encode('1234');
      await tester.runAsync(
        () => settings.update(
          AppSettings(
            saferModeEnabled: true,
            saferModePassword: stored,
            autoCheckUpdates: false,
          ),
        ),
      );
      await pumpAdvanced(tester);
      final s = stringsOf().settings;

      await tester.ensureVisible(find.byKey(const ValueKey('settings.reset')));
      await tester.tap(find.byKey(const ValueKey('settings.reset')));
      await tester.pumpAndSettle();
      expect(find.text(s.resetDialogTitle), findsOneWidget);
      await tester.tap(find.text(s.resetDialogConfirm));
      await tester.pumpAndSettle();

      // שאר ההגדרות חזרו לברירת המחדל, הנעילה נשארה.
      expect(settings.settings.autoCheckUpdates, isTrue);
      expect(settings.settings.saferModeEnabled, isTrue);
      expect(settings.settings.saferModePassword, stored);
    });
  });
}
