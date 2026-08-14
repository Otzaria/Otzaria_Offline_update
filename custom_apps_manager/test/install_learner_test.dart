import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  /// רישום הסרה מזויף. הצילום האמיתי נבדק מול הרג'יסטרי עצמו ב-
  /// `otzaria_manager/test/windows_install_registry_test.dart`; כאן נבדקת
  /// ההחלטה — מה נלמד ממה שהופיע.
  UninstallEntry entry(
    String keyName,
    String displayName, {
    String? installDir,
  }) =>
      UninstallEntry(
        keyName: keyName,
        displayName: displayName,
        installDir: installDir,
      );

  /// שינה מדומה: הלולאה עדיין מתקדמת בזמן הווירטואלי שלה ולכן מסתיימת,
  /// אבל הבדיקה אינה מחכה דקה אמיתית.
  Future<void> noSleep(Duration _) async {}

  InstallLearner learnerWith({
    List<List<UninstallEntry>> rounds = const [],
    String? exe,
    void Function()? onStart,
  }) {
    var call = 0;
    return InstallLearner(
      onStart: onStart,
      sleep: noSleep,
      lookupUninstallEntries: () async {
        // הסבב האחרון חוזר על עצמו — כך "לא הופיע כלום" מגיע לפסק הזמן.
        final index = call < rounds.length ? call : rounds.length - 1;
        call++;
        return rounds.isEmpty ? const [] : rounds[index];
      },
      lookupExe: exe == null ? null : (dir, _) async => p.join(dir, exe),
    );
  }

  group('הצילום שלפני ההתקנה', () {
    test('בלי תפר — רשימה ריקה, ולא שגיאה', () async {
      expect(await const InstallLearner().snapshot(), isEmpty);
    });

    test('תפר שזורק אינו מפיל את ההתקנה', () async {
      final learner = InstallLearner(
        lookupUninstallEntries: () async => throw StateError('אין הרשאה'),
      );
      expect(await learner.snapshot(), isEmpty);
    });
  });

  group('מה נלמד מהרישום שהופיע', () {
    test('רישום חדש בודד — נלמדים גם התבנית וגם שם קובץ ההרצה', () async {
      final dir = p.join(tempMirrorRoot(), 'Program Files', 'MyApp');
      writeFile(p.join(dir, 'myapp.exe'));

      final learned = await learnerWith(
        rounds: [
          [entry('{OLD}_is1', 'Something Else 1.0')],
          [
            entry('{OLD}_is1', 'Something Else 1.0'),
            entry('{NEW}_is1', 'MyApp 1.4.2', installDir: dir),
          ],
        ],
        exe: 'myapp.exe',
      ).learn(
        descriptor: descriptor(name: 'MyApp'),
        before: [entry('{OLD}_is1', 'Something Else 1.0')],
        installerFileName: 'MyApp-Setup-1.4.2.exe',
      );

      expect(learned, isNotNull);
      expect(learned!.exeName, 'myapp.exe');
      // התבנית ולא ה-`DisplayName` הגולמי — היא צריכה לשרוד את הגרסה הבאה.
      expect(
        RegistryDisplayNamePattern.matches(
            learned.registryDisplayName!, 'MyApp 9.9.9'),
        isTrue,
      );
    });

    test('רישום קיים ששמו אינו קשור לתוכנה אינו נלמד', () async {
      final before = [entry('{OTHER}_is1', 'Runtime 1.0', installDir: r'C:\R')];

      final learned = await learnerWith(rounds: [before]).learn(
        descriptor: descriptor(name: 'MyApp'),
        before: before,
      );
      expect(learned, isNull);
    });

    // ⚠️ קוד יציאה 0 אינו אומר שההתקנה הסתיימה: setup.exe של Inno מחלץ עותק
    // ומשגר תהליך שני. צילום בודד מיד אחרי ההרצה היה מחמיץ את הרישום.
    test('רישום שמופיע רק בסבב מאוחר — הסקירה החוזרת תופסת אותו', () async {
      final learned = await learnerWith(
        rounds: [
          const [],
          const [],
          const [],
          [entry('{NEW}_is1', 'MyApp 1.0', installDir: r'C:\MyApp')],
        ],
      ).learn(
        descriptor: descriptor(name: 'MyApp'),
        before: const [],
      );

      expect(learned, isNotNull);
      expect(learned!.registryDisplayName, isNotNull);
    });

    test('אף רישום לא הופיע — null, וזה מצב תקין ולא שגיאה', () async {
      final learned = await learnerWith().learn(
        descriptor: descriptor(name: 'MyApp'),
        before: const [],
      );
      expect(learned, isNull);
    });
  });

  group('בחירת הרישום — שכבה 1, מפתח שנולד', () {
    // מתקין שגורר איתו VC++ Redistributable מייצר שני רישומים.
    test('רישום ששמו מזכיר את התוכנה מנצח רישום נלווה', () {
      final chosen = InstallLearner.pickEntry(
        [
          entry('{VC}', 'Microsoft Visual C++ 2015 Redistributable 14.0'),
          entry('{APP}', 'MyApp 1.4.2'),
        ],
        const [],
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen!.keyName, '{APP}');
    });

    test('רמז ארוך נבדק לפני רמז קצר, ולא לפי סדר הרישומים', () {
      final chosen = InstallLearner.pickEntry(
        [
          entry('{OTHER}', 'Adobe Pro 2024'),
          entry('{APP}', 'MyApplication Pro 1.0'),
        ],
        const [],
        InstallLearner.nameHintsFor(name: 'MyApplication Pro'),
      );
      expect(chosen!.keyName, '{APP}');
    });

    test('רישום בודד מתקבל גם בלי התאמת שם — אין מועמד אחר', () {
      final chosen = InstallLearner.pickEntry(
        [entry('{APP}', 'שם שלא מזכיר כלום')],
        const [],
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen!.keyName, '{APP}');
    });

    // ניחוש כאן היה מלמד את התוכנה לזהות את עצמה לפי ספרייה נלווית.
    test('כמה רישומים ואף אחד אינו מזכיר את התוכנה — מוותרים', () {
      final chosen = InstallLearner.pickEntry(
        [entry('{A}', 'Runtime A 1.0'), entry('{B}', 'Runtime B 2.0')],
        const [],
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen, isNull);
    });

    test('שם קובץ ההתקנה הוא רמז בפני עצמו — גם כששם התוכנה בעברית', () {
      final chosen = InstallLearner.pickEntry(
        [entry('{VC}', 'Runtime 1.0'), entry('{APP}', 'MyApp 1.4.2')],
        const [],
        InstallLearner.nameHintsFor(
          name: 'התוכנה שלי',
          installerFileName: 'MyApp-Setup-1.4.2.exe',
        ),
      );
      expect(chosen!.keyName, '{APP}');
    });

    test('שם הריפו הוא רמז גם הוא', () {
      final hints = InstallLearner.nameHintsFor(name: 'כלי', repo: 'sefaria');
      expect(hints, contains('sefaria'));
    });

    // שם עברי חייב לשרוד את הנירמול — טווח תווים שנשמט בו סוף הבלוק היה
    // הופך כל אות עברית למפריד, והרמז היה נעלם בשקט.
    test('שם עברי מייצר רמז ומזהה רישום עברי', () {
      final chosen = InstallLearner.pickEntry(
        [entry('{A}', 'Runtime 1.0'), entry('{B}', 'אוצריא גירסה 0.9.96')],
        const [],
        InstallLearner.nameHintsFor(name: 'אוצריא'),
      );
      expect(chosen!.keyName, '{B}');
    });

    test('מספר גרסה לבדו אינו רמז', () {
      expect(InstallLearner.nameHintsFor(name: 'App 2024'), ['app']);
    });

    /// עם שכבה 3 רמז חלש מסוכן: הוא היה מאמץ תוכנה קיימת אקראית.
    test('ארכיטקטורה ומילות התקנה אינן רמזים', () {
      final hints = InstallLearner.nameHintsFor(
        name: 'MyApp',
        installerFileName: 'MyApp-Setup-1.4.2-x64.exe',
      );
      expect(hints, isNot(contains('x64')));
      expect(hints, isNot(contains('setup')));
      expect(hints, contains('myapp'));
    });
  });

  /// ⚠️ המקרה שנכשל על מחשב אמיתי (`KleiKodesh`): התוכנה כבר הייתה מותקנת,
  /// וההתקנה החדשה עדכנה את **אותו מפתח**. אין מפתח חדש, ואין מה ללמוד.
  group('בחירת הרישום — התקנה חוזרת, שאינה יוצרת מפתח חדש', () {
    test('שכבה 2: מפתח שהשתנה ושמו מתאים', () {
      final before = [entry('{APP}', 'MyApp 1.0', installDir: r'C:\Old')];
      final now = [
        entry('{OTHER}', 'Something 5.0'),
        entry('{APP}', 'MyApp 1.4.2', installDir: r'C:\New'),
      ];

      final chosen = InstallLearner.pickEntry(
        now,
        before,
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen!.installDir, r'C:\New');
    });

    test('שכבה 2 דורשת התאמת שם — מעדכן ברקע אינו נחשב', () {
      final before = [entry('{EDGE}', 'Microsoft Edge 130.0')];
      final now = [entry('{EDGE}', 'Microsoft Edge 131.0')];

      final chosen = InstallLearner.pickEntry(
        now,
        before,
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen, isNull);
    });

    /// המקרה של כלי קודש בדיוק: שום דבר לא השתנה ברישום, כי המתקין כתב את
    /// אותם ערכים. השם הוא כל מה שנשאר.
    test('שכבה 3: מפתח קיים ששמו מתאים, גם כששום דבר לא זז', () {
      final entries = [
        entry('{OTHER}', 'Something 5.0'),
        entry('KleiKodesh', 'כלי קודש',
            installDir: r'C:\Users\x\AppData\Local\KleiKodesh'),
      ];

      final chosen = InstallLearner.pickEntry(
        entries,
        entries,
        InstallLearner.nameHintsFor(
          name: 'כלי קודש',
          repo: 'KleiKodeshProject',
          installerFileName: 'KleiKodeshSetup-v9.0.1-x64.exe',
        ),
      );
      expect(chosen!.keyName, 'KleiKodesh');
    });

    /// ה-`DisplayName` הוא לעיתים **קידומת** של הרמז ולא להפך: `KleiKodesh`
    /// מול הרמז `kleikodeshproject` שנגזר משם הריפו.
    test('ההשוואה דו-כיוונית — שם קצר מהרמז עדיין מתאים', () {
      final entries = [entry('{K}', 'KleiKodesh')];

      final chosen = InstallLearner.pickEntry(
        entries,
        entries,
        InstallLearner.nameHintsFor(name: 'x', repo: 'KleiKodeshProject'),
      );
      expect(chosen!.keyName, '{K}');
    });

    // בשכבה 3 אין קבלה של "רישום בודד" — היא הייתה מאמצת תוכנה אקראית.
    test('שכבה 3 אינה מקבלת רישום שאינו מזכיר את התוכנה', () {
      final entries = [entry('{X}', 'תוכנה אחרת לגמרי')];

      final chosen = InstallLearner.pickEntry(
        entries,
        entries,
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen, isNull);
    });

    test('מפתח שנולד מנצח מפתח קיים שגם שמו מתאים', () {
      final before = [entry('{OLD}', 'MyApp Legacy')];
      final now = [
        entry('{OLD}', 'MyApp Legacy'),
        entry('{NEW}', 'MyApp 2.0'),
      ];

      final chosen = InstallLearner.pickEntry(
        now,
        before,
        InstallLearner.nameHintsFor(name: 'MyApp'),
      );
      expect(chosen!.keyName, '{NEW}');
    });
  });

  group('מה לא נדרס', () {
    test('שם קובץ הרצה שהמשתמש מילא אינו מוחלף', () async {
      final dir = p.join(tempMirrorRoot(), 'MyApp');
      writeFile(p.join(dir, 'other.exe'));

      final learned = await learnerWith(
        rounds: [
          [entry('{NEW}', 'MyApp 1.0', installDir: dir)],
        ],
        exe: 'other.exe',
      ).learn(
        descriptor: descriptor(
          name: 'MyApp',
          detect: const AppDetectRules(exeName: 'chosen-by-hand.exe'),
        ),
        before: const [],
      );

      expect(learned!.exeName, 'chosen-by-hand.exe');
      expect(learned.registryDisplayName, isNotNull);
    });

    test('רשומה שכבר יודעת לזהות אינה לומדת שוב — ואינה סורקת בכלל', () async {
      var looked = false;
      final learner = InstallLearner(
        sleep: noSleep,
        lookupUninstallEntries: () async {
          looked = true;
          return const [];
        },
      );

      final learned = await learner.learn(
        descriptor: descriptor(
          detect: const AppDetectRules(
            exeName: 'app.exe',
            registryDisplayName: '^MyApp',
          ),
        ),
        before: const [],
      );

      expect(learned, isNull);
      expect(looked, isFalse);
    });

    test('תיקיות מוצהרות נשמרות כמות שהן', () async {
      final learned = await learnerWith(
        rounds: [
          [entry('{NEW}', 'MyApp 1.0')],
        ],
      ).learn(
        descriptor: descriptor(
          name: 'MyApp',
          detect: const AppDetectRules(dirs: [r'C:\Declared']),
        ),
        before: const [],
      );
      expect(learned!.dirs, [r'C:\Declared']);
    });
  });

  group('מסלול הגיבוי — בלי רישום הסרה', () {
    test('אין רישום, אך יש תיקייה מוצהרת — שם קובץ ההרצה נלמד ממנה', () async {
      final dir = p.join(tempMirrorRoot(), 'Portable');
      writeFile(p.join(dir, 'app.exe'));

      final learned = await learnerWith(exe: 'app.exe').learn(
        descriptor: descriptor(name: 'MyApp', installDir: dir),
        before: const [],
      );

      expect(learned!.exeName, 'app.exe');
      expect(learned.registryDisplayName, isNull);
    });

    test('בלי תפר סריקה ובלי רישום — אין מה ללמוד', () async {
      final learned = await const InstallLearner().learn(
        descriptor: descriptor(installDir: r'C:\Somewhere'),
        before: const [],
      );
      expect(learned, isNull);
    });
  });

  test('ההודעה למשתמש נדלקת רק כשיש מה ללמוד', () async {
    var started = 0;
    await learnerWith(onStart: () => started++).learn(
      descriptor: descriptor(name: 'MyApp'),
      before: const [],
    );
    expect(started, 1);

    await learnerWith(onStart: () => started++).learn(
      descriptor: descriptor(
        detect: const AppDetectRules(
          exeName: 'app.exe',
          registryDisplayName: '^MyApp',
        ),
      ),
      before: const [],
    );
    expect(started, 1);
  });
}
