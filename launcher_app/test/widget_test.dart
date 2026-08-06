import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

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

    test('preview אינו ברירת מחדל באף רכיב', () {
      const s = AppSettings();

      expect(s.appChannel, UpdateChannel.stable);
      expect(s.libraryChannel, UpdateChannel.stable);
      expect(s.pluginsChannel, UpdateChannel.stable);
    });

    test('סבב JSON שומר את הערכים', () {
      const original = AppSettings(
        autoMetadataCheck: false,
        autoInstallLibrary: true,
        syncLibrary: false,
        libraryChannel: UpdateChannel.stableAndPreview,
        backupsToKeep: 3,
        themeMode: AppThemeMode.dark,
        textScale: 1.15,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.autoMetadataCheck, isFalse);
      expect(restored.autoInstallLibrary, isTrue);
      expect(restored.syncLibrary, isFalse);
      expect(restored.libraryChannel, UpdateChannel.stableAndPreview);
      expect(restored.backupsToKeep, 3);
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

    // קובץ מ-schemaVersion 1 מכיל נתיבים ומתגים שהוסרו. חשוב שהוא לא
    // יזרוק — ושמה שנשאר רלוונטי ימשיך להיקרא.
    test('קובץ הגדרות מ-schemaVersion 1 נקרא בלי לזרוק', () {
      final restored = AppSettings.fromJson({
        'schemaVersion': 1,
        'automation': {'metadataCheck': false, 'downloadLibrary': true},
        'channels': {'library': 'stableAndPreview'},
        'paths': {'preferredUsb': r'E:\otzaria', 'backupsToKeep': 2},
        'network': {'offlineOnly': true, 'timeoutSeconds': 45},
        'ui': {'themeMode': 'dark', 'textScale': 1.15},
      });

      expect(restored.autoMetadataCheck, isFalse);
      expect(restored.libraryChannel, UpdateChannel.stableAndPreview);
      expect(restored.networkTimeoutSeconds, 45);
      expect(restored.themeMode, AppThemeMode.dark);
      // 'paths' כבר לא נקרא, ולכן backupsToKeep חוזר לברירת המחדל.
      expect(restored.backupsToKeep, 1);
      expect(restored.hasSyncSelection, isTrue);
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
  });
}
