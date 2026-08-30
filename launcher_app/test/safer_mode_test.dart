import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';

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

  group('מסך ההגדרות — כרטיס מצב הסייפר', () {
    late Directory dir;
    late SettingsController settings;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('safer_mode_screen');
      settings = SettingsController(dataDir: dir.path);
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    Widget screen() => SettingsScreen(
          controller: settings,
          onOpenLog: () {},
          launcherVersion: '0.8.0',
          saferMode: SaferModeGate(settings),
        );

    testWidgets('בלי סיסמה — הכרטיס מציע לבחור אחת ואין מתג', (tester) async {
      await pumpScreen(tester, screen());

      expect(find.text('יש לבחור סיסמה תחילה'), findsOneWidget);
      expect(find.text('בחר סיסמה'), findsOneWidget);
      expect(find.text('אפשרויות'), findsNothing);
    });

    testWidgets('עם סיסמה — מתג ושורת סיסמה', (tester) async {
      await tester.runAsync(
        () => settings.update(
          AppSettings(saferModePassword: SaferModePassword.encode('1234')),
        ),
      );
      await pumpScreen(tester, screen());

      expect(
        find.text('ההגדרות פתוחות לכל מי שפותח את התוכנה'),
        findsOneWidget,
      );
      expect(find.text('אפשרויות'), findsOneWidget);
      expect(find.text('מחיקת הסיסמה'), findsOneWidget);
    });

    testWidgets('כשהמצב פעיל אי אפשר למחוק את הסיסמה', (tester) async {
      await tester.runAsync(
        () => settings.update(
          AppSettings(
            saferModeEnabled: true,
            saferModePassword: SaferModePassword.encode('1234'),
          ),
        ),
      );
      await pumpScreen(tester, screen());

      expect(find.text('מחיקת הסיסמה'), findsNothing);
      expect(
        find.text('יש להשבית את מצב הסייפר לפני מחיקת הסיסמה'),
        findsOneWidget,
      );
    });

    testWidgets('הכניסה לשינוי הסיסמה מבקשת את הנוכחית', (tester) async {
      await tester.runAsync(
        () => settings.update(
          AppSettings(saferModePassword: SaferModePassword.encode('1234')),
        ),
      );
      await pumpScreen(tester, screen());

      await tester.tap(find.text('אפשרויות'));
      await tester.pumpAndSettle();

      expect(find.text('הזן סיסמה'), findsOneWidget);
      expect(
        find.text('הזן את הסיסמה הנוכחית כדי לשנות אותה.'),
        findsOneWidget,
      );
    });

    testWidgets('איפוס ההגדרות אינו פותח את הנעילה', (tester) async {
      final stored = SaferModePassword.encode('1234');
      await tester.runAsync(
        () => settings.update(
          AppSettings(
            saferModeEnabled: true,
            saferModePassword: stored,
            showFaqButton: false,
          ),
        ),
      );
      await pumpScreen(tester, screen());

      await tester.tap(find.text('איפוס'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('אפס הגדרות'));
      await tester.pumpAndSettle();

      // שאר ההגדרות חזרו לברירת המחדל, הנעילה נשארה.
      expect(settings.settings.showFaqButton, isTrue);
      expect(settings.settings.saferModeEnabled, isTrue);
      expect(settings.settings.saferModePassword, stored);
    });
  });
}
