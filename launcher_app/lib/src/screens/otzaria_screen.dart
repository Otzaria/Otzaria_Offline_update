import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/otzaria_module_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// מסך עדכון תוכנת אוצריא — מקביל במבנה ל-[LibraryScreen]: מצב, מה
/// התחדש בגרסה האחרונה, והתיקייה שממנה מותקנים.
class OtzariaScreen extends StatelessWidget {
  const OtzariaScreen({
    super.key,
    required this.otzaria,
    required this.otzariaIsRunning,
  });

  final OtzariaModuleController otzaria;
  final bool otzariaIsRunning;

  /// **לא** תלוי בהורדה גלובלית: הורדה של רכיב אחר (למשל הספרייה) לא
  /// אמורה לחסום פעולות מקומיות כאן (בחירת מיקום, בדיקה מחדש).
  bool get _isBusy => otzaria.status == OtzariaModuleStatus.installing;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'עדכון תוכנת אוצריא',
      description: 'ההתקנה מוחלת מהתיקייה שלצד התוכנה, בלי צורך באינטרנט. '
          'יש לוודא שאוצריא סגורה לפני התקנה.',
      children: [
        _stateCard(context),
        _whatsNewCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב ההתקנה ────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = otzaria;

    return SettingsCard(
      title: 'מצב ההתקנה',
      children: [
        InfoStatusRow(
          icon: FluentIcons.desktop_24_regular,
          title: 'מצב',
          kind: switch (c.status) {
            OtzariaModuleStatus.idle => StatusKind.unknown,
            OtzariaModuleStatus.checking => StatusKind.working,
            OtzariaModuleStatus.upToDate => StatusKind.ok,
            OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
            OtzariaModuleStatus.installing => StatusKind.working,
            OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
            OtzariaModuleStatus.error => StatusKind.error,
          },
          label: switch (c.status) {
            OtzariaModuleStatus.idle => 'טרם נבדק',
            OtzariaModuleStatus.checking => 'בודק...',
            OtzariaModuleStatus.upToDate => 'מעודכן',
            OtzariaModuleStatus.updateAvailable => 'מוכן להתקנה',
            OtzariaModuleStatus.installing => 'מתקין...',
            OtzariaModuleStatus.needsDownload => 'טרם הורדה גרסה',
            OtzariaModuleStatus.error => 'שגיאה',
          },
        ),
        SettingsActionTile.text(
          icon: FluentIcons.tag_24_regular,
          title: 'גרסה מותקנת',
          subtitle: c.currentVersion ?? 'לא זוהתה התקנה',
          subtitleLtr: c.currentVersion != null,
          actions: [
            ActionButton.ghost(
              text: 'בחירת מיקום ידנית',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickInstallDir(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: 'גרסה בתיקייה המקומית',
          subtitle: c.latestVersion ?? 'אין — יש להריץ הורדה',
          subtitleLtr: c.latestVersion != null,
        ),
        SettingsActionTile.text(
          icon: FluentIcons.play_24_regular,
          title: 'תהליך אוצריא',
          subtitle: otzariaIsRunning
              ? 'פתוחה כרגע — עדכון מסד חסום עד לסגירתה'
              : 'סגורה',
        ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == OtzariaModuleStatus.installing)
          const InfoProgressRow(stage: 'מתקין את אוצריא...'),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'בדיקה מחדש',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _isBusy ? null : c.checkForUpdate,
            ),
            ActionButton.recommended(
              text: 'הפעלת אוצריא',
              icon: FluentIcons.play_24_regular,
              onPressed: c.canLaunch ? c.launch : null,
            ),
            ActionButton.neutral(
              text: 'התקנת העדכון',
              icon: FluentIcons.desktop_arrow_right_24_regular,
              isLoading: c.status == OtzariaModuleStatus.installing,
              onPressed: c.status == OtzariaModuleStatus.updateAvailable
                  ? () => _confirmInstall(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickInstallDir(BuildContext context) async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחירת תיקיית ההתקנה של אוצריא',
    );
    if (dir == null) return;

    final adopted = await otzaria.adoptInstallDir(dir);
    if (adopted) {
      UiSnack.showSuccess('נמצאה התקנת אוצריא — הגרסה עודכנה');
    } else {
      UiSnack.showError('לא נמצאה התקנת אוצריא בתיקייה שנבחרה');
    }
  }

  Future<void> _confirmInstall(BuildContext context) async {
    final approved = await showTwoActionsDialog(
      context: context,
      title: 'התקנת תוכנת אוצריא',
      content: 'הגרסה ${otzaria.latestVersion} תותקן מהתיקייה המקומית '
          'על גבי ${otzaria.currentVersion ?? 'ההתקנה הקיימת'}. '
          'ההתקנה אינה דורשת אינטרנט. יש לוודא שאוצריא סגורה.',
      confirmText: 'התקן',
    );
    if (!approved) return;
    await otzaria.install();
    if (otzaria.status == OtzariaModuleStatus.upToDate) {
      UiSnack.showSuccess('אוצריא עודכנה לגרסה ${otzaria.currentVersion}');
    }
  }

  // ── מה התחדש ──────────────────────────────────────────────────────────────

  Widget _whatsNewCard(BuildContext context) {
    final notes = otzaria.latestReleaseNotes;

    return SettingsCard(
      title: 'מה התחדש בגרסה האחרונה',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Text(
            (notes == null || notes.trim().isEmpty)
                ? 'אין תיאור לגרסה הזו, או שעדיין לא הורדה גרסה.'
                : notes.trim(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  // ── התיקייה שממנה מתקינים ─────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = otzaria;

    return SettingsCard(
      title: 'התיקייה שממנה מתקינים',
      subtitle: 'קבועה, לצד קובץ ההרצה — ראו "עדכון ספרייה" להסבר המלא.',
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: 'תיקיית עדכוני התוכנה',
          path: c.mirrorDir,
          placeholder: '—',
        ),
        if (c.lastDownloadedAt != null)
          SettingsActionTile.text(
            icon: FluentIcons.history_24_regular,
            title: 'הורד לאחרונה',
            subtitle: c.lastDownloadedAt!.toLocal().toString().split('.').first,
          ),
      ],
    );
  }
}
