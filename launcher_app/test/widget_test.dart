import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

void main() {
  group('AppSettings', () {
    test('ברירת המחדל: שום התקנה אוטומטית, רק בדיקה מקומית', () {
      const s = AppSettings();

      expect(s.autoMetadataCheck, isTrue);
      expect(s.autoInstallApp, isFalse);
      expect(s.autoInstallLibrary, isFalse);
    });

    test('ברירת המחדל: ההורדה מסמנת את שלושת הרכיבים', () {
      const s = AppSettings();

      expect(s.syncApp, isTrue);
      expect(s.syncLibrary, isTrue);
      expect(s.syncPlugins, isTrue);
      expect(s.hasSyncSelection, isTrue);
    });

    test('hasSyncSelection כבוי כשלא נבחר שום רכיב', () {
      const s = AppSettings(
        syncApp: false,
        syncLibrary: false,
        syncPlugins: false,
      );

      expect(s.hasSyncSelection, isFalse);
    });

    test('סבב JSON שומר את הערכים', () {
      const original = AppSettings(
        autoMetadataCheck: false,
        autoInstallLibrary: true,
        syncLibrary: false,
        themeMode: AppThemeMode.dark,
        textScale: 1.15,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.autoMetadataCheck, isFalse);
      expect(restored.autoInstallLibrary, isTrue);
      expect(restored.syncLibrary, isFalse);
      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.textScale, 1.15);
    });

    test('JSON פגום נופל לברירות המחדל ולא זורק', () {
      final restored = AppSettings.fromJson({
        'schemaVersion': 2,
        'automation': 'לא אובייקט',
        'ui': {'themeMode': 'ערכה שלא קיימת'},
      });

      expect(restored.autoMetadataCheck, isTrue);
      expect(restored.autoInstallApp, isFalse);
      expect(restored.themeMode, AppThemeMode.system);
    });

    // קובץ ישן מכיל נתיבים, ערוצי גרסאות ומתגים שהוסרו. חשוב שהוא לא
    // יזרוק — ושמה שנשאר רלוונטי ימשיך להיקרא.
    test('קובץ הגדרות מגרסה ישנה נקרא בלי לזרוק', () {
      final restored = AppSettings.fromJson({
        'schemaVersion': 1,
        'automation': {'metadataCheck': false, 'downloadLibrary': true},
        'channels': {'library': 'stableAndPreview'},
        'paths': {'preferredUsb': r'E:\otzaria'},
        'storage': {'backupsToKeep': 2},
        'network': {'offlineOnly': true, 'timeoutSeconds': 45},
        'ui': {'themeMode': 'dark', 'textScale': 1.15},
      });

      expect(restored.autoMetadataCheck, isFalse);
      expect(restored.themeMode, AppThemeMode.dark);
      // הסעיפים שהוסרו ('paths', 'storage', 'network') נבלעים בשקט.
      expect(restored.toJson().keys, isNot(contains('storage')));
      expect(restored.hasSyncSelection, isTrue);
      // קובץ מלפני שדה השפה נטען לזיהוי אוטומטי — כמו התקנה חדשה.
      expect(restored.languagePreference, AppLanguagePreference.system);
    });

    test('שפת הממשק עוברת הלוך-חזור דרך ה-JSON', () {
      const settings =
          AppSettings(languagePreference: AppLanguagePreference.english);
      final restored = AppSettings.fromJson(settings.toJson());

      expect(settings.toJson()['ui'], containsPair('language', 'en'));
      expect(restored.languagePreference, AppLanguagePreference.english);
      expect(restored.language, AppLanguage.english);
      // "אוטומטי" נשמר כערך משלו, ולא כשפה שנפתרה ממנו.
      expect(
        const AppSettings().toJson()['ui'],
        containsPair('language', 'system'),
      );
      // ערך לא מוכר נופל לאוטומטי, שהוא ברירת המחדל של השדה.
      expect(
        AppSettings.fromJson({
          'ui': {'language': 'fr'}
        }).languagePreference,
        AppLanguagePreference.system,
      );
    });
  });

  group('רכיבי ממשק', () {
    testWidgets('StatusChip מציג טקסט לצד הסמל — לא צבע בלבד', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusChip(kind: StatusKind.ok, label: 'מעודכן'),
          ),
        ),
      );

      expect(find.text('מעודכן'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('switchTile מחליף מצב בהקשה על השורה כולה', (tester) async {
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SettingsCard(
                title: 'אוטומציה',
                children: [
                  SettingsActionTile.switchTile(
                    title: 'הורדת עדכון ספרייה',
                    value: value,
                    onChanged: (v) => setState(() => value = v),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('אוטומציה'), findsOneWidget);
      await tester.tap(find.text('הורדת עדכון ספרייה'));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });

    // הכפתורים גלשו מגובה התיבה שלהם, והתוויות ישבו מתחת למרכזה.
    testWidgets('תוויות הסגמנטד ממורכזות בגובה בתוך התיבה', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SettingsCard(
                children: [
                  SettingsActionTile.segmentedTile<int>(
                    title: 'ערכת נושא',
                    currentValue: 1,
                    onChanged: (_) {},
                    width: 300,
                    options: const [
                      SegmentOption(value: 0, label: 'מערכת'),
                      SegmentOption(value: 1, label: 'בהיר'),
                      SegmentOption(value: 2, label: 'כהה'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final box = tester.getRect(find.byType(SegmentedButton<int>));
      for (final label in ['מערכת', 'בהיר', 'כהה']) {
        expect(
          (tester.getRect(find.text(label)).center.dy - box.center.dy).abs(),
          lessThan(0.6),
          reason: 'התווית "$label" אינה ממורכזת בגובה',
        );
      }
    });
  });
}
