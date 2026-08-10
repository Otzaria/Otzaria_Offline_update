import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// בדיקות ל-[AppSettings] ול-[SettingsController]. בדיקות ה-JSON הבסיסיות
/// יושבות ב-`widget_test.dart`; כאן מה שנוגע למלכודות: היעדר שדות נתיב,
/// ברירת מחדל לכל שדה, קובץ פגום, כתיבה אטומית והחלפת שפה.
void main() {
  group('AppSettings — אין ולא יהיו שדות נתיב', () {
    /// כל המפתחות בקובץ, כולל אלה שבתוך הסעיפים.
    Set<String> allKeys(Map<String, dynamic> json) {
      final keys = <String>{};
      void walk(Map<String, dynamic> map) {
        for (final entry in map.entries) {
          keys.add(entry.key);
          final value = entry.value;
          if (value is Map<String, dynamic>) walk(value);
        }
      }

      walk(json);
      return keys;
    }

    test('אין בקובץ שום מפתח שנשמע כמו נתיב/כונן/מיקום', () {
      // המלכודת (AGENTS §5): תיקיית הנתונים צמודה לקובץ ההרצה, ואין לה
      // הגדרה. החזרת שדה כזה שוברת את ההנחה שהכונן נושא הכול.
      const forbidden = [
        'path',
        'paths',
        'dir',
        'directory',
        'folder',
        'usb',
        'drive',
        'location',
        'datadir',
        'installpath',
        'otzariainstallpath',
      ];

      final keys = allKeys(const AppSettings().toJson());
      for (final key in keys) {
        final lower = key.toLowerCase();
        for (final word in forbidden) {
          expect(
            lower.contains(word),
            isFalse,
            reason: 'המפתח "$key" נראה כמו הגדרת נתיב — ראו AGENTS §5',
          );
        }
      }
    });

    test('מבנה הקובץ ידוע ומלא — כל שדה, ותו לא', () {
      final json = const AppSettings().toJson();

      expect(json.keys.toSet(), {
        'schemaVersion',
        'automation',
        'channels',
        'sync',
        'ui',
      });
      expect(allKeys(json), {
        'schemaVersion',
        'automation',
        'metadataCheck',
        'checkOnlineUpdates',
        'installApp',
        'installLibrary',
        'channels',
        'appPrerelease',
        'sync',
        'app',
        'library',
        'plugins',
        'ui',
        'language',
        'themeMode',
        'textScale',
      });
      expect(json['schemaVersion'], AppSettings.schemaVersion);
    });
  });

  group('AppSettings — ברירות מחדל וסבב JSON', () {
    test('לכל שדה יש ברירת מחדל מוגדרת', () {
      const s = AppSettings();

      expect(s.autoMetadataCheck, isTrue);
      expect(s.autoCheckOnlineUpdates, isTrue);
      expect(s.syncApp, isTrue);
      expect(s.syncLibrary, isTrue);
      expect(s.syncPlugins, isTrue);
      expect(s.autoInstallApp, isFalse);
      expect(s.autoInstallLibrary, isFalse);
      expect(s.preferAppPrerelease, isFalse);
      expect(s.language, AppLanguage.hebrew);
      expect(s.themeMode, AppThemeMode.system);
      expect(s.textScale, 1.0);
    });

    test('סבב JSON מלא — כל שדה חוזר כפי שנשמר', () {
      const original = AppSettings(
        autoMetadataCheck: false,
        autoCheckOnlineUpdates: false,
        syncApp: false,
        syncLibrary: false,
        syncPlugins: false,
        autoInstallApp: true,
        autoInstallLibrary: true,
        preferAppPrerelease: true,
        language: AppLanguage.english,
        themeMode: AppThemeMode.light,
        textScale: 1.3,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.autoMetadataCheck, isFalse);
      expect(restored.autoCheckOnlineUpdates, isFalse);
      expect(restored.syncApp, isFalse);
      expect(restored.syncLibrary, isFalse);
      expect(restored.syncPlugins, isFalse);
      expect(restored.autoInstallApp, isTrue);
      expect(restored.autoInstallLibrary, isTrue);
      expect(restored.preferAppPrerelease, isTrue);
      expect(restored.language, AppLanguage.english);
      expect(restored.themeMode, AppThemeMode.light);
      expect(restored.textScale, 1.3);
      expect(restored.hasSyncSelection, isFalse);
    });

    test('JSON ריק → בדיוק ברירות המחדל', () {
      expect(AppSettings.fromJson(const {}).toJson(),
          const AppSettings().toJson());
    });

    test('מפתחות לא מוכרים נבלעים, וטיפוס שגוי נופל לברירת המחדל', () {
      final restored = AppSettings.fromJson({
        'schemaVersion': 99,
        'whatIsThis': {'nested': true},
        'automation': {'metadataCheck': 'כן', 'installApp': 1},
        // הסעיפים 'network' ו-'storage' (גיבוי המסד) הוסרו מה-schema — הם
        // נבלעים ככל מפתח לא מוכר.
        'network': {'timeoutSeconds': 12.5},
        'storage': {'backupsToKeep': 2},
        'ui': {'textScale': 2},
      });

      expect(restored.autoMetadataCheck, isTrue);
      expect(restored.autoInstallApp, isFalse);
      expect(restored.toJson().containsKey('network'), isFalse);
      expect(restored.toJson().containsKey('storage'), isFalse);
      // num שאינו int כן מתקבל ל-textScale (בשונה מהשדות השלמים).
      expect(restored.textScale, 2.0);
      // schemaVersion נכתב תמיד מחדש לגרסה הנוכחית.
      expect(restored.toJson()['schemaVersion'], AppSettings.schemaVersion);
    });

    test('copyWith משנה שדה אחד ומשאיר את השאר', () {
      const original = AppSettings(textScale: 1.15);
      final next = original.copyWith(preferAppPrerelease: true);

      expect(next.preferAppPrerelease, isTrue);
      expect(next.textScale, 1.15);
      expect(next.language, original.language);
    });

    test('preferAppPrerelease נשמר בסעיף הערוצים ולא נוגע בהורדה', () {
      // ההורדה מביאה תמיד את שתי הגרסאות; זו בחירת התקנה בלבד.
      final json = const AppSettings(preferAppPrerelease: true).toJson();

      expect(json['channels'], containsPair('appPrerelease', true));
      expect(json['sync'], containsPair('app', true));
    });

    test('autoCheckOnlineUpdates נפרד מ-autoMetadataCheck', () {
      final json = const AppSettings(autoCheckOnlineUpdates: false)
          .toJson()['automation'] as Map<String, dynamic>;

      expect(json['checkOnlineUpdates'], isFalse);
      expect(json['metadataCheck'], isTrue);
    });
  });

  group('SettingsController', () {
    late Directory tempDir;
    late SettingsController controller;

    File settingsFile() => File(p.join(tempDir.path, 'launcher_settings.json'));

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('settings-test-');
      controller = SettingsController(dataDir: tempDir.path);
      AppL10n.use(AppLanguage.hebrew);
    });
    tearDown(() {
      controller.dispose();
      AppL10n.use(AppLanguage.hebrew);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('בלי קובץ — ברירות המחדל, בלי הודעה ובלי שגיאה', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.load();

      expect(controller.settings.toJson(), const AppSettings().toJson());
      expect(notifications, 0);
      expect(settingsFile().existsSync(), isFalse);
    });

    test('קובץ פגום לא מפיל את העלייה ומשאיר ברירות מחדל', () async {
      settingsFile().writeAsStringSync('{ זה לא JSON');

      await controller.load();

      expect(controller.settings.autoMetadataCheck, isTrue);
      expect(controller.settings.themeMode, AppThemeMode.system);
    });

    test('JSON תקין שאינו אובייקט נבלע גם הוא', () async {
      settingsFile().writeAsStringSync('[1, 2, 3]');

      await controller.load();

      expect(controller.settings.toJson(), const AppSettings().toJson());
    });

    test('שמירה אטומית: אין קובץ .tmp אחרי הכתיבה, והתוכן נקרא חזרה', () async {
      await controller.update(const AppSettings(
        preferAppPrerelease: true,
        textScale: 1.15,
      ));

      expect(File('${settingsFile().path}.tmp').existsSync(), isFalse);
      expect(settingsFile().existsSync(), isTrue);

      final onDisk =
          jsonDecode(settingsFile().readAsStringSync()) as Map<String, dynamic>;
      expect(onDisk['schemaVersion'], AppSettings.schemaVersion);

      final reloaded = SettingsController(dataDir: tempDir.path);
      addTearDown(reloaded.dispose);
      await reloaded.load();

      expect(reloaded.settings.textScale, 1.15);
      expect(reloaded.settings.preferAppPrerelease, isTrue);
    });

    test('update מודיע למאזינים לפני שהכתיבה הסתיימה', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      final pending = controller.update(const AppSettings(syncApp: false));
      expect(notifications, 1, reason: 'ההודעה מיידית, לא אחרי הדיסק');

      await pending;
      expect(controller.settings.syncApp, isFalse);
    });

    test('החלפת שפה מזליגה ל-AppL10n — זה מה שקוראות חבילות התשתית', () async {
      expect(AppL10n.language, AppLanguage.hebrew);

      await controller.update(const AppSettings(language: AppLanguage.english));

      expect(AppL10n.language, AppLanguage.english);
      expect(AppL10n.strings.units.bytes(2), '2 bytes');
    });

    test('טעינה מקובץ שנשמר באנגלית מציבה את השפה כבר ב-load', () async {
      settingsFile().writeAsStringSync(jsonEncode(
        const AppSettings(language: AppLanguage.english).toJson(),
      ));

      await controller.load();

      expect(controller.settings.language, AppLanguage.english);
      expect(AppL10n.language, AppLanguage.english);
    });

    test('התיקייה נוצרת בשמירה גם כשלא הייתה קיימת', () async {
      final nested = p.join(tempDir.path, 'a', 'b');
      final nestedController = SettingsController(dataDir: nested);
      addTearDown(nestedController.dispose);

      await nestedController.update(const AppSettings(textScale: 1.2));

      expect(
        File(p.join(nested, 'launcher_settings.json')).existsSync(),
        isTrue,
      );
    });
  });
}
