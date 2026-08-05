import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

void main() {
  group('AppSettings', () {
    test('ברירת המחדל: שום הורדה או התקנה אוטומטית, רק בדיקת מטא־דאטה', () {
      const s = AppSettings();

      expect(s.autoMetadataCheck, isTrue);
      expect(s.autoDownloadApp, isFalse);
      expect(s.autoInstallApp, isFalse);
      expect(s.autoDownloadLibrary, isFalse);
      expect(s.autoInstallLibrary, isFalse);
      expect(s.autoDownloadInstalledPlugins, isFalse);
      expect(s.autoInstallInstalledPlugins, isFalse);
      expect(s.autoDownloadAllPlugins, isFalse);
      expect(s.autoPrepareUsbBundle, isFalse);
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
        autoDownloadLibrary: true,
        libraryChannel: UpdateChannel.stableAndPreview,
        preferredUsbPath: r'E:\otzaria-update',
        offlineOnly: true,
        themeMode: AppThemeMode.dark,
        textScale: 1.15,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.autoMetadataCheck, isFalse);
      expect(restored.autoDownloadLibrary, isTrue);
      expect(restored.libraryChannel, UpdateChannel.stableAndPreview);
      expect(restored.preferredUsbPath, r'E:\otzaria-update');
      expect(restored.offlineOnly, isTrue);
      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.textScale, 1.15);
    });

    test('JSON פגום נופל לברירות המחדל ולא זורק', () {
      final restored = AppSettings.fromJson({
        'schemaVersion': 1,
        'automation': 'לא אובייקט',
        'ui': {'themeMode': 'ערכה שלא קיימת'},
      });

      expect(restored.autoMetadataCheck, isTrue);
      expect(restored.autoDownloadApp, isFalse);
      expect(restored.themeMode, AppThemeMode.system);
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
