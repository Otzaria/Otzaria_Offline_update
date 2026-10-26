// בדיקות לשאלות הנפוצות — דף העזרה שנפתח מ-"?" בשורת הכותרת, האקורדיון,
// ומצב העריכה (כולל השער של מצב הסייפר ובקשת העריכה מההגדרות).
//
// הבדיקה האחרונה כאן היא השומר החשוב: שדה שאלה/תשובה שנוסף לחוזה המלל ולא
// נכנס ל-`faqGroups` פשוט לא היה מוצג, בלי שדבר ייפול.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/faq_controller.dart';
import 'package:launcher_app/src/screens/faq/faq_content.dart';
import 'package:launcher_app/src/screens/help/help_page.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/faq_customization.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';
import 'test_support.dart';

void main() {
  final t = stringsOf().faq;

  late Directory tempDir;
  late FaqController faq;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('faq_test');
    await AppLogger.init(tempDir.path);
    faq = FaqController(dataDir: tempDir.path);
  });

  tearDown(() async {
    faq.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  Future<void> pumpBody(
    WidgetTester tester, {
    SaferModeGate? saferMode,
    ValueNotifier<bool>? editRequests,
    bool active = true,
    bool readOnly = false,
  }) =>
      pumpScreen(
        tester,
        Scaffold(
          body: HelpPage(
            faq: faq,
            saferMode: saferMode,
            editRequests: editRequests,
            active: active,
            readOnly: readOnly,
          ),
        ),
      );

  /// הדף גולל, ולכן כל לחיצה בו חייבת קודם להביא את המטרה אל תוך החלון.
  Future<void> tapInList(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// כניסה למצב העריכה ויציאה ממנו — אותו כפתור בראש הדף.
  Future<void> enterEditMode(WidgetTester tester) async {
    expect(find.text(t.editButton), findsOneWidget);
    await tapInList(tester, find.byKey(const ValueKey('faq.edit')));
  }

  Future<void> leaveEditMode(WidgetTester tester) async {
    expect(find.text(t.editDoneButton), findsOneWidget);
    await tapInList(tester, find.byKey(const ValueKey('faq.edit')));
  }

  group('דף העזרה', () {
    testWidgets('הדף מציג את השאלות עם כל הקבוצות, בלי דו-שיח', (tester) async {
      await pumpBody(tester);

      expect(find.text(t.title), findsOneWidget);
      expect(find.text(t.intro), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      for (final group in faqGroups(stringsOf())) {
        expect(find.text(group.title), findsOneWidget, reason: group.title);
      }
      // איש הקשר אינו שם כל עוד לא מולאו פרטים — "אפשר לפנות אלינו" בלי
      // לומר למי אינו עוזר לאיש.
      expect(find.text(t.contactTitle), findsNothing);
    });

    testWidgets('בקשת עריכה מההגדרות נכנסת לעריכה ומתאפסת', (tester) async {
      final request = ValueNotifier(true);
      addTearDown(request.dispose);
      await pumpBody(tester, editRequests: request);
      await tester.pumpAndSettle();

      expect(find.text(t.editTitle), findsOneWidget);
      expect(request.value, isFalse);

      // ובקשה בזמן שהדף כבר פתוח — אחרי יציאה מהעריכה.
      await leaveEditMode(tester);
      expect(find.text(t.editTitle), findsNothing);
      request.value = true;
      await tester.pumpAndSettle();
      expect(find.text(t.editTitle), findsOneWidget);
    });

    testWidgets('כשהדף מפסיק להיות מוצג — יוצאים מהעריכה ושומרים מיד',
        (tester) async {
      await pumpBody(tester);
      await enterEditMode(tester);

      final nameField = find.byKey(const ValueKey('faq.contact.name'));
      await tester.ensureVisible(nameField);
      await tester.pumpAndSettle();
      await tester.enterText(nameField, 'ר׳ ישראל');
      // עוד לפני ההשהיה: שום דבר לא נכתב לדיסק.
      final file = File('${tempDir.path}/faq_customization.json');
      expect(file.existsSync(), isFalse);

      // הדף נשאר בעץ (IndexedStack) — רק `active` משתנה.
      await pumpBody(tester, active: false);
      // הכתיבה היא I/O אמיתי — נותנים לה לרוץ, בלי לקדם את שעון ההשהיה.
      for (var i = 0; i < 20 && !file.existsSync(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(file.existsSync(), isTrue);
      expect(
        jsonDecode(file.readAsStringSync())['contact']['name'],
        'ר׳ ישראל',
      );

      // חזרה לדף — השאלות, לא העריכה.
      await pumpBody(tester);
      expect(find.text(t.editTitle), findsNothing);
      expect(find.text(t.title), findsOneWidget);
    });

    testWidgets('בכונן מוגן העריכה אומרת שהשינויים נשמרים במחשב הזה',
        (tester) async {
      await pumpBody(tester, readOnly: true);
      await enterEditMode(tester);

      expect(find.text(t.editIntroThisComputer), findsOneWidget);
      expect(find.text(t.editIntro), findsNothing);
    });
  });

  group('עריכה במצב סייפר', () {
    late Directory settingsDir;
    late SettingsController settings;

    setUp(() {
      settingsDir = Directory.systemTemp.createTempSync('faq_safer');
      settings = SettingsController(dataDir: settingsDir.path);
    });

    tearDown(() async {
      settings.dispose();
      await deleteTempDir(settingsDir);
    });

    testWidgets('הכניסה לעריכה מבקשת סיסמה; שגויה או ביטול — נשארים בקריאה',
        (tester) async {
      await tester.runAsync(
        () => settings.update(
          AppSettings(
            saferModeEnabled: true,
            saferModePassword: SaferModePassword.encode('1234'),
          ),
        ),
      );
      final gate = SaferModeGate(settings);
      final s = stringsOf().saferMode;
      await pumpBody(tester, saferMode: gate);

      await tester.tap(find.byKey(const ValueKey('faq.edit')));
      await tester.pumpAndSettle();
      expect(find.text(s.verifyTitle), findsOneWidget);
      expect(find.text(s.verifyFaqHint), findsOneWidget);

      await tester.enterText(find.byType(TextField), '9999');
      // הסיסמה פותחת את העריכה — "כניסה" ולא "אישור".
      await tester.tap(find.text(s.enterButton));
      await tester.pumpAndSettle();
      // השגיאה בתוך הדו-שיח, והוא נשאר פתוח.
      expect(find.text(s.wrongPassword), findsOneWidget);
      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pumpAndSettle();
      expect(find.text(t.editTitle), findsNothing);
      expect(gate.isLocked, isTrue);

      await tester.tap(find.byKey(const ValueKey('faq.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(s.enterButton));
      await tester.pumpAndSettle();
      expect(find.text(t.editTitle), findsOneWidget);
      expect(gate.isLocked, isFalse);

      // יציאה וכניסה חוזרת — בלי לשאול שוב באותה הרצה.
      await leaveEditMode(tester);
      await tester.tap(find.byKey(const ValueKey('faq.edit')));
      await tester.pumpAndSettle();
      expect(find.text(s.verifyTitle), findsNothing);
      expect(find.text(t.editTitle), findsOneWidget);
    });
  });

  group('רשימת השאלות', () {
    testWidgets('תשובה נפתחת בלחיצה, ורק אחת פתוחה בכל רגע', (tester) async {
      // משטח גבוה: הרשימה כולה גלולה, ומה שמחוץ לחלון אינו נלחץ.
      await pumpBody(tester);

      expect(find.text(t.aWhatIsThis), findsNothing);

      await tester.tap(find.text(t.qWhatIsThis));
      await tester.pumpAndSettle();
      expect(find.text(t.aWhatIsThis), findsOneWidget);

      await tester.tap(find.text(t.qOfflineFlow));
      await tester.pumpAndSettle();
      expect(find.text(t.aOfflineFlow), findsOneWidget);
      expect(find.text(t.aWhatIsThis), findsNothing);

      // לחיצה שנייה על אותה שאלה סוגרת אותה.
      await tester.tap(find.text(t.qOfflineFlow));
      await tester.pumpAndSettle();
      expect(find.text(t.aOfflineFlow), findsNothing);
    });

    testWidgets('כל כניסה לדף העזרה מתחילה מלמעלה', (tester) async {
      useViewSize(tester, const Size(900, 500));
      await pumpBody(tester);
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(300);
      await tester.pump();
      expect(scrollable.position.pixels, 300);

      await pumpBody(tester, active: false);
      await pumpBody(tester);
      expect(scrollable.position.pixels, 0);
    });

    testWidgets('כל השאלות מוצגות באנגלית גם כן', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(body: HelpPage(faq: faq)),
        language: AppLanguage.english,
      );
      final en = stringsOf(AppLanguage.english);
      for (final group in faqGroups(en)) {
        for (final entry in group.entries) {
          expect(find.text(entry.question), findsOneWidget,
              reason: entry.question);
        }
      }
    });
  });

  group('התאמה אישית', () {
    testWidgets('הסתרת שאלה מוציאה אותה מהרשימה, והחזרה מחזירה אותה',
        (tester) async {
      await pumpBody(tester);
      await enterEditMode(tester);

      // במצב עריכה כל השאלות מוצגות — כולל אלה שיוסתרו — אחרת אין דרך חזרה.
      await tapInList(tester, find.byKey(const ValueKey('faq-hide-qFree')));

      expect(faq.value.hiddenIds, contains('qFree'));
      expect(find.text(t.hiddenLabel), findsOneWidget);

      // חזרה לקריאה — השאלה אינה שם.
      await leaveEditMode(tester);
      expect(find.text(t.qFree), findsNothing);
      // שאר הקבוצה נשארה במקומה.
      expect(find.text(t.qNoExpenses), findsOneWidget);

      // והחזרה מהעריכה מחזירה אותה לרשימה.
      await enterEditMode(tester);
      await tapInList(tester, find.byKey(const ValueKey('faq-hide-qFree')));
      await leaveEditMode(tester);
      expect(find.text(t.qFree), findsOneWidget);
    });

    testWidgets('שאלה שהמשתמש הוסיף מופיעה בהדרכה ונמחקת באישור',
        (tester) async {
      await pumpBody(tester);
      await enterEditMode(tester);
      expect(find.text(t.noExtrasYet), findsOneWidget);

      await tapInList(tester, find.text(t.addQuestionButton));

      await tester.enterText(
        find.widgetWithText(TextField, t.formQuestionLabel),
        'איפה הקפה?',
      );
      await tester.enterText(
        find.widgetWithText(TextField, t.formAnswerLabel),
        'במטבח.',
      );
      await tester.tap(find.text(t.formSave));
      await tester.pumpAndSettle();

      expect(faq.value.extras, hasLength(1));
      expect(find.text('איפה הקפה?'), findsOneWidget);

      // ובמצב קריאה היא קבוצה משל עצמה, ותשובתה נפתחת כמו כל שאלה אחרת.
      await leaveEditMode(tester);
      expect(find.text(t.myQuestionsTitle), findsOneWidget);
      await tapInList(tester, find.text('איפה הקפה?'));
      expect(find.text('במטבח.'), findsOneWidget);

      // מחיקה דורשת אישור.
      await enterEditMode(tester);
      await tapInList(
        tester,
        find.byKey(const ValueKey('faq-extra-delete-0')),
      );
      expect(find.text(t.deleteConfirmTitle), findsOneWidget);
      await tester.tap(find.text(stringsOf().common.continueAction));
      await tester.pumpAndSettle();

      expect(faq.value.extras, isEmpty);
      expect(find.text(t.noExtrasYet), findsOneWidget);
    });

    testWidgets('שאלה בלי תשובה אינה נשמרת — נאמר למה', (tester) async {
      await pumpBody(tester);
      await enterEditMode(tester);
      await tapInList(tester, find.text(t.addQuestionButton));

      await tester.enterText(
        find.widgetWithText(TextField, t.formQuestionLabel),
        'שאלה בלי תשובה',
      );
      await tester.tap(find.text(t.formSave));
      await tester.pumpAndSettle();

      // ההודעה עצמה יוצאת ב-`UiSnack`, שדורש `navigatorKey` ולכן אינו נבנה
      // בבדיקת מסך בודד; מה שנבדק כאן הוא שכלום לא נשמר.
      expect(faq.value.extras, isEmpty);
      expect(find.text(t.noExtrasYet), findsOneWidget);
    });

    testWidgets('איש הקשר מופיע רק אחרי שמולאו פרטים', (tester) async {
      await pumpBody(tester);
      expect(find.text(t.contactTitle), findsNothing);

      await enterEditMode(tester);

      final nameField = find.byKey(const ValueKey('faq.contact.name'));
      await tester.ensureVisible(nameField);
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'ר׳ ישראל');
      await tester.enterText(
        find.byKey(const ValueKey('faq.contact.phone')),
        '050-0000000',
      );
      // השמירה מושהית בכוונה — כתיבת קובץ בכל הקשה על כונן נייד.
      await tester.pump(const Duration(milliseconds: 600));
      expect(faq.value.contactPhone, '050-0000000');

      await leaveEditMode(tester);

      expect(find.text(t.contactTitle), findsOneWidget);
      expect(find.text('ר׳ ישראל'), findsOneWidget);
      expect(find.text('050-0000000'), findsOneWidget);
    });

    testWidgets('איש הקשר בראש דף העזרה, לפני השאלות', (tester) async {
      await tester.runAsync(
        () => faq.update(const FaqCustomization(
          contactName: 'ר׳ ישראל',
          contactPhone: '050-0000000',
        )),
      );
      await pumpBody(tester);

      final contact = find.byKey(const ValueKey('faq.contact'));
      expect(contact, findsOneWidget);
      expect(
        find.descendant(of: contact, matching: find.text('050-0000000')),
        findsOneWidget,
      );
      final firstGroup = find.text(faqGroups(stringsOf()).first.title);
      expect(
        tester.getRect(contact).bottom,
        lessThan(tester.getRect(firstGroup).top),
      );
    });

    testWidgets('איש קשר עם שם בלבד: השם לבדו, בלי שורת טלפון', (tester) async {
      await tester.runAsync(
        () => faq.update(const FaqCustomization(contactName: 'ר׳ ישראל')),
      );
      await pumpBody(tester);

      final contact = find.byKey(const ValueKey('faq.contact'));
      expect(contact, findsOneWidget);
      final texts = tester
          .widgetList<Text>(
              find.descendant(of: contact, matching: find.byType(Text)))
          .map((w) => w.data)
          .toList();
      expect(texts, ['ר׳ ישראל']);
    });

    testWidgets('איש קשר עם טלפון בלבד: הטלפון הוא הכותרת, משמאל לימין', (
      tester,
    ) async {
      await tester.runAsync(
        () => faq.update(const FaqCustomization(contactPhone: '050-0000000')),
      );
      await pumpBody(tester);

      final contact = find.byKey(const ValueKey('faq.contact'));
      expect(contact, findsOneWidget);
      final phone = find.descendant(
        of: contact,
        matching: find.text('050-0000000'),
      );
      expect(phone, findsOneWidget);
      expect(tester.widget<Text>(phone).textDirection, TextDirection.ltr);
    });
  });

  group('השמירה לדיסק', () {
    test('שינוי מושהה נכתב רק אחרי ההשהיה, או מיד ב-flush', () async {
      final file = File('${tempDir.path}/faq_customization.json');
      faq.updateDeferred(
        faq.value.copyWith(contactName: 'א'),
        const Duration(hours: 1),
      );
      expect(faq.value.contactName, 'א');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(file.existsSync(), isFalse);

      await faq.flush();
      expect(jsonDecode(file.readAsStringSync())['contact']['name'], 'א');
      // ואין מה לכתוב שוב.
      await faq.flush();
    });

    test('flush ממתין גם לכתיבה שכבר רצה — הסגירה לא קוטעת אותה', () async {
      final file = File('${tempDir.path}/faq_customization.json');
      // שינוי מיידי (הסתרה, מחיקה) שנשלח ממש לפני הסגירה: אין טיימר ממתין.
      unawaited(faq.update(faq.value.copyWith(contactName: 'ב')));

      await faq.flush();
      expect(jsonDecode(file.readAsStringSync())['contact']['name'], 'ב');
    });

    test('הסתרה ושאלה מתווספת נשמרות ונטענות מקובץ', () async {
      await faq.update(const FaqCustomization(
        hiddenIds: {'qFree'},
        extras: [FaqUserEntry(question: 'ש', answer: 'ת')],
        contactName: 'שם',
        contactPhone: '05',
      ));

      final reloaded = FaqController(dataDir: tempDir.path);
      addTearDown(reloaded.dispose);
      await reloaded.load();

      expect(reloaded.value.hiddenIds, {'qFree'});
      expect(reloaded.value.extras.single.question, 'ש');
      expect(reloaded.value.contactName, 'שם');
      expect(reloaded.value.hasContact, isTrue);
    });

    test('קובץ פגום מחזיר את ההדרכה לנוסח המקורי ואינו זורק', () async {
      await File('${tempDir.path}/faq_customization.json')
          .writeAsString('{ לא JSON');

      await faq.load();
      expect(faq.value.hiddenIds, isEmpty);
      expect(faq.value.extras, isEmpty);
    });

    test('רשומה בלי תשובה מדולגת, ושאר הרשימה נשמרת', () {
      final custom = FaqCustomization.fromJson(
        jsonDecode(jsonEncode({
          'extras': [
            {'question': 'יש', 'answer': 'תשובה'},
            {'question': 'אין תשובה'},
            {'question': '  ', 'answer': 'ריק'},
          ],
        })) as Map<String, dynamic>,
      );

      expect(custom.extras, hasLength(1));
      expect(custom.extras.single.question, 'יש');
    });
  });

  test('כל שדה שאלה/תשובה בחוזה נמצא ב-faqGroups', () {
    final contract = File('../otzaria_l10n/lib/src/app_strings.dart')
        .readAsStringSync()
        .split('abstract class FaqStrings')
        .last
        .split('\n}')
        .first;
    final content =
        File('lib/src/screens/faq/faq_content.dart').readAsStringSync();

    final fields = RegExp(r'String get ([qa][A-Z]\w*);')
        .allMatches(contract)
        .map((m) => m.group(1)!)
        .toList();

    // הגנה מפני regex שהפסיק להתאים ועובר על ריק.
    expect(fields, hasLength(greaterThanOrEqualTo(20)));
    for (final field in fields) {
      expect(content, contains('t.$field'), reason: field);
      // השאלות (ולא התשובות) הן גם המזהה שנשמר בהסתרה.
      if (field.startsWith('q')) {
        expect(content, contains("'$field'"), reason: '$field כמזהה');
      }
    }
  });
}
