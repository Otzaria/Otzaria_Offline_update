import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// הרג׳יסטרי האמיתי אינו ניתן לזיוף, ולכן הבדיקות כאן **כותבות** רישום הסרה
/// זמני תחת HKCU (לא נדרשת הרשאת מנהל) ומוחקות אותו בסוף. כך נבדקים בפועל
/// הקריאה ב-UTF-16, הסינון לפי `DisplayName`, מסלול הגיבוי מ-`UninstallString`
/// והדרישה לתיקייה מוחלטת שקיימת.
void main() {
  const registry = WindowsInstallRegistry();
  const keyRoot =
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\otzaria-'
      'manager-test';

  /// כותב רישום הסרה זמני. מחזיר false אם אין הרשאת כתיבה — אז הבדיקה מדולגת
  /// ולא נכשלת על מכונה נעולה.
  bool writeEntry(String suffix, Map<String, String> values) {
    final key = '$keyRoot-$suffix';
    for (final entry in values.entries) {
      final result = Process.runSync('reg', [
        'add',
        key,
        '/v',
        entry.key,
        '/t',
        'REG_SZ',
        '/d',
        entry.value,
        '/f',
      ]);
      if (result.exitCode != 0) return false;
    }
    addTearDown(() => Process.runSync('reg', ['delete', key, '/f']));
    return true;
  }

  group('WindowsInstallRegistry — מול הרג׳יסטרי האמיתי', () {
    test(
      'רישום עם DisplayName של אוצריא — התיקייה מוחזרת',
      () {
        final dir = Directory.systemTemp.createTempSync('otzaria-reg-');
        addTearDown(() => dir.deleteSync(recursive: true));
        if (!writeEntry('found', {
          'DisplayName': 'אוצריא גירסה 9.9.9 (בדיקה)',
          'InstallLocation': '${dir.path}${p.separator}',
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        // הלוכסן הסופי מנורמל, בדיוק כמו שהמתקין האמיתי כותב אותו.
        expect(registry.installDirs(), contains(p.normalize(dir.path)));
      },
      testOn: 'windows',
    );

    // התפר שתוכנה מותאמת משתמשת בו: אותו סורק, תבנית שם אחרת.
    test(
      'תבנית DisplayName משלנו מוצאת תוכנה שאינה אוצריא',
      () {
        final dir = Directory.systemTemp.createTempSync('custom-reg-');
        addTearDown(() => dir.deleteSync(recursive: true));
        if (!writeEntry('custom', {
          'DisplayName': 'My Other App 3.1',
          'InstallLocation': dir.path,
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        final normalized = p.normalize(dir.path);
        expect(
          registry.installDirs(
            matchesDisplayName: (name) => name.contains('My Other App'),
          ),
          contains(normalized),
        );
        // ברירת המחדל לא השתנתה — היא עדיין אוצריא בלבד.
        expect(registry.installDirs(), isNot(contains(normalized)));
      },
      testOn: 'windows',
    );

    test(
      'בהיעדר InstallLocation נגזרת התיקייה מ-UninstallString',
      () {
        final dir = Directory.systemTemp.createTempSync('otzaria-reg-');
        addTearDown(() => dir.deleteSync(recursive: true));
        if (!writeEntry('uninst', {
          'DisplayName': 'Otzaria test',
          'UninstallString': '"${p.join(dir.path, 'unins000.exe')}" /SILENT',
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        expect(registry.installDirs(), contains(p.normalize(dir.path)));
      },
      testOn: 'windows',
    );

    test(
      'DisplayName שאינו של אוצריא אינו מוחזר — גם כשהנתיב מזכיר אותה',
      () {
        final dir =
            Directory.systemTemp.createTempSync('otzaria-reg-otzaria-tools-');
        addTearDown(() => dir.deleteSync(recursive: true));
        if (!writeEntry('foreign', {
          'DisplayName': 'Some Other Program',
          'InstallLocation': dir.path,
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        expect(registry.installDirs(), isNot(contains(p.normalize(dir.path))));
      },
      testOn: 'windows',
    );

    test(
      'תיקייה שאינה קיימת אינה מוחזרת',
      () {
        final missing = p.join(Directory.systemTemp.path, 'אוצריא-לא-קיימת-9x');
        if (!writeEntry('missing', {
          'DisplayName': 'אוצריא בדיקה',
          'InstallLocation': missing,
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        expect(registry.installDirs(), isNot(contains(p.normalize(missing))));
      },
      testOn: 'windows',
    );

    test(
      'מה שחוזר הוא נתיבים מוחלטים, בלי כפילויות',
      () {
        final dirs = registry.installDirs();

        expect(
            dirs.map((d) => d.toLowerCase()).toSet(), hasLength(dirs.length));
        for (final dir in dirs) {
          expect(p.isAbsolute(dir), isTrue, reason: dir);
          expect(dir, isNot(endsWith(p.separator)));
        }
      },
      testOn: 'windows',
    );

    test(
      'מחוץ לווינדוס אין קריאה לרג׳יסטרי — רשימה ריקה, לא חריג',
      () => expect(registry.installDirs(), isEmpty),
      testOn: '!windows',
    );
  });

  /// `entries` הוא מה שמאפשר **ללמוד** ולא רק לחפש: `installDirs` זורק את
  /// ה-`DisplayName`, וזה בדיוק הנתון שהלמידה שאחרי התקנה קיימת בשבילו.
  group('entries — הרישומים עצמם, לא רק התיקיות', () {
    test(
      'ה-DisplayName ושם המפתח מוחזרים, לא רק התיקייה',
      () {
        final dir = Directory.systemTemp.createTempSync('entries-reg-');
        addTearDown(() => dir.deleteSync(recursive: true));
        if (!writeEntry('entry', {
          'DisplayName': 'Learnable App 3.1',
          'InstallLocation': dir.path,
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        final found = registry
            .entries(matchesDisplayName: (n) => n.contains('Learnable App'))
            .single;

        expect(found.displayName, 'Learnable App 3.1');
        expect(found.installDir, p.normalize(dir.path));
        // שם המפתח הוא הזהות היציבה שמשווים לפניה ואחריה — ה-DisplayName
        // מכיל את הגרסה ומשתנה איתה.
        expect(found.keyName, endsWith('-entry'));
      },
      testOn: 'windows',
    );

    // להשוואת לפני/אחרי דרוש לראות **שהמפתח נולד**, גם כשאין לו תיקייה
    // שימושית. `installDirs` היה מסנן אותו ומחמיץ את העדות.
    test(
      'רישום בלי InstallLocation קיים מוחזר עם installDir שהוא null',
      () {
        final missing = p.join(Directory.systemTemp.path, 'אין-כזו-תיקייה-9x');
        if (!writeEntry('nodir', {
          'DisplayName': 'Dirless App 1.0',
          'InstallLocation': missing,
        })) {
          markTestSkipped('אין הרשאת כתיבה לרג׳יסטרי');
          return;
        }

        final found = registry
            .entries(matchesDisplayName: (n) => n.contains('Dirless App'))
            .single;

        expect(found.installDir, isNull);
        // ואותו רישום בדיוק אינו נכנס ל-installDirs, שהוא לזיהוי ולא ללמידה.
        expect(
          registry.installDirs(
            matchesDisplayName: (n) => n.contains('Dirless App'),
          ),
          isEmpty,
        );
      },
      testOn: 'windows',
    );

    test(
      'בלי כפילויות לפי שם המפתח',
      () {
        final keys = registry.entries(matchesDisplayName: (_) => true);
        expect(
          keys.map((e) => e.keyName.toLowerCase()).toSet(),
          hasLength(keys.length),
        );
      },
      testOn: 'windows',
    );

    test(
      'מחוץ לווינדוס — רשימה ריקה, לא חריג',
      () => expect(registry.entries(), isEmpty),
      testOn: '!windows',
    );
  });

  group('executableOf — פקודת הסרה אינה נתיב', () {
    test('מירכאות מוסרות והארגומנטים נחתכים', () {
      expect(
        WindowsInstallRegistry.executableOf(
            r'"C:\אוצריא\unins000.exe" /SILENT'),
        r'C:\אוצריא\unins000.exe',
      );
    });

    test('בלי מירכאות — נחתך בסוף ה-exe', () {
      expect(
        WindowsInstallRegistry.executableOf(r'C:\App\unins000.exe /SILENT'),
        r'C:\App\unins000.exe',
      );
    });

    test('פקודת MSI אינה מייצרת נתיב מוחלט', () {
      // בדיוק המקרה שבו p.dirname היה מחזיר "MsiExec.exe " היחסי.
      final exe = WindowsInstallRegistry.executableOf('MsiExec.exe /X{GUID}');
      expect(p.isAbsolute(p.dirname(exe!)), isFalse);
    });

    test('null נשאר null', () {
      expect(WindowsInstallRegistry.executableOf(null), isNull);
    });
  });

  group('expandVariables — REG_EXPAND_SZ', () {
    test('משתנה מוגדר מוחלף', () {
      expect(
        WindowsInstallRegistry.expandVariables(
          r'%ProgramFiles%\Otzaria',
          env: {'ProgramFiles': r'C:\Program Files'},
        ),
        r'C:\Program Files\Otzaria',
      );
    });

    test('משתנה שאינו מוגדר נשאר כמו שהוא', () {
      expect(
        WindowsInstallRegistry.expandVariables(r'%NOPE%\x', env: const {}),
        r'%NOPE%\x',
      );
    });

    test('נתיב בלי אחוזים אינו משתנה', () {
      expect(
        WindowsInstallRegistry.expandVariables(r'C:\אוצריא', env: const {}),
        r'C:\אוצריא',
      );
    });
  });
}
