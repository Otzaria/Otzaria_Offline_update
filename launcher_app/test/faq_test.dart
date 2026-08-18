// בדיקות להדרכת "שאלות נפוצות" — הכפתור הצף, הבועה שבעלייה, האקורדיון,
// וההתאמה האישית שנפתחת בגלגל השיניים.
//
// הבדיקה האחרונה כאן היא השומר החשוב: שדה שאלה/תשובה שנוסף לחוזה המלל ולא
// נכנס ל-`faqGroups` פשוט לא היה מוצג, בלי שדבר ייפול.

import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/faq_controller.dart';
import 'package:launcher_app/src/screens/faq/faq_content.dart';
import 'package:launcher_app/src/screens/faq/faq_dialog.dart';
import 'package:launcher_app/src/screens/faq/faq_floating_button.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/faq_customization.dart';
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

  /// הבועה שמעל הכפתור — ה-`AnimatedOpacity` היחיד בתת-העץ שלו.
  double bubbleOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.descendant(
        of: find.byType(FaqFloatingButton),
        matching: find.byType(AnimatedOpacity),
      ))
      .opacity;

  Future<void> pumpBody(WidgetTester tester) =>
      pumpScreen(tester, Scaffold(body: FaqBody(faq: faq)));

  /// רשימת השאלות גוללת (גובהה חסום), ולכן כל לחיצה בתוכה חייבת קודם להביא
  /// את המטרה אל תוך החלון — אחרת ה-tap נופל על קואורדינטה שמחוץ לגליל.
  Future<void> tapInList(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// כניסה למצב העריכה דרך גלגל השיניים, ויציאה ממנו. שניהם מחוץ לגליל.
  Future<void> enterEditMode(WidgetTester tester) async {
    await tester.tap(find.byIcon(FluentIcons.settings_24_regular));
    await tester.pumpAndSettle();
  }

  Future<void> leaveEditMode(WidgetTester tester) async {
    await tester.tap(find.byIcon(FluentIcons.checkmark_24_regular));
    await tester.pumpAndSettle();
  }

  group('הכפתור הצף', () {
    testWidgets('הבועה נפתחת בעלייה, נסגרת מעצמה, וההבהוב מסתיים',
        (tester) async {
      await tester.pumpWidget(
        wrap(Center(child: FaqFloatingButton(faq: faq))),
      );

      // לפני ההשהיה הבועה סגורה — היא לא אמורה לקדום את הצביעה הראשונה.
      expect(bubbleOpacity(tester), 0);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 300));
      expect(bubbleOpacity(tester), 1);
      expect(find.text(t.title), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(bubbleOpacity(tester), 0);

      // ההבהוב סופי ואינו `repeat()` — אחרת זה לא היה מתייצב לעולם.
      await tester.pumpAndSettle();
    });

    testWidgets('showIntro=false — בלי בועה ובלי הבהוב', (tester) async {
      await tester.pumpWidget(
        wrap(Center(child: FaqFloatingButton(faq: faq, showIntro: false))),
      );
      await tester.pumpAndSettle();
      expect(bubbleOpacity(tester), 0);
    });

    testWidgets('לחיצה פותחת את ההדרכה עם כל הקבוצות', (tester) async {
      await tester.pumpWidget(
        wrap(Center(child: FaqFloatingButton(faq: faq, showIntro: false))),
      );
      await tester.tap(find.byType(FaqFloatingButton));
      await tester.pumpAndSettle();

      // הבועה נשארת בעץ בשקיפות 0, ולכן הכותרת נחפשת בתוך הדיאלוג עצמו.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(t.title),
        ),
        findsOneWidget,
      );
      expect(find.text(t.intro), findsOneWidget);
      for (final group in faqGroups(stringsOf())) {
        expect(find.text(group.title), findsOneWidget, reason: group.title);
      }
      // כרטיס הסיום אינו שם כל עוד לא מולאו פרטים — "אפשר לפנות אלינו" בלי
      // לומר למי אינו עוזר לאיש.
      expect(find.text(t.contactTitle), findsNothing);
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

    testWidgets('כל השאלות מוצגות באנגלית גם כן', (tester) async {
      await pumpScreen(
        tester,
        Scaffold(body: FaqBody(faq: faq)),
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

    testWidgets('כרטיס הסיום מופיע רק אחרי שמולאו פרטים', (tester) async {
      await pumpBody(tester);
      expect(find.text(t.contactTitle), findsNothing);

      await enterEditMode(tester);

      final nameField = find.widgetWithText(TextField, t.contactNameLabel);
      await tester.ensureVisible(nameField);
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'ר׳ ישראל');
      await tester.enterText(
        find.widgetWithText(TextField, t.contactPhoneLabel),
        '050-0000000',
      );
      // השמירה מושהית בכוונה — כתיבת קובץ בכל הקשה על כונן נייד.
      await tester.pump(const Duration(milliseconds: 600));
      expect(faq.value.contactPhone, '050-0000000');

      await leaveEditMode(tester);

      expect(find.text(t.contactTitle), findsOneWidget);
      expect(find.text('ר׳ ישראל'), findsOneWidget);
      expect(find.text(t.contactPhoneLine('050-0000000')), findsOneWidget);
    });
  });

  group('השמירה לדיסק', () {
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
