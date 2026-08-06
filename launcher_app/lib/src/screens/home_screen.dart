import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../settings/settings_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'app_shell.dart';

/// דף הבית — תמונת מצב אחת של המחשב הזה, ועדכון תוכנת אוצריא (תכנון §5).
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.otzaria,
    required this.library,
    required this.plugins,
    required this.settings,
    required this.network,
    required this.otzariaIsRunning,
    required this.onRecheck,
    required this.onGoToLibrary,
    required this.onGoToPlugins,
  });

  final OtzariaModuleController otzaria;
  final LibraryModuleController library;
  final PluginsModuleController plugins;
  final SettingsController settings;
  final NetworkState network;
  final bool otzariaIsRunning;
  final Future<void> Function() onRecheck;
  final VoidCallback onGoToLibrary;
  final VoidCallback onGoToPlugins;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'דף הבית',
      description: 'פתיחת האפליקציה אינה מורידה ואינה מתקינה דבר. '
          'כל הורדה או התקנה מתחילה רק בלחיצה שלך.',
      children: [
        _otzariaCard(context),
        _libraryCard(context),
        _pluginsCard(context),
        _transferCard(context),
      ],
    );
  }

  // ── תוכנת אוצריא ──────────────────────────────────────────────────────────

  Widget _otzariaCard(BuildContext context) {
    final c = otzaria;
    final isBusy = c.status == OtzariaModuleStatus.updating;
    final progress = (c.downloadReceived != null &&
            c.downloadTotal != null &&
            c.downloadTotal! > 0)
        ? c.downloadReceived! / c.downloadTotal!
        : null;

    return SettingsCard(
      title: 'תוכנת אוצריא',
      subtitle: 'הגרסה המותקנת במחשב הזה, והגרסה הזמינה במקור הפעיל.',
      children: [
        InfoStatusRow(
          icon: FluentIcons.desktop_24_regular,
          title: 'מצב',
          kind: switch (c.status) {
            OtzariaModuleStatus.idle => StatusKind.unknown,
            OtzariaModuleStatus.checking => StatusKind.working,
            OtzariaModuleStatus.upToDate => StatusKind.ok,
            OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
            OtzariaModuleStatus.updating => StatusKind.working,
            OtzariaModuleStatus.error => StatusKind.error,
          },
          label: switch (c.status) {
            OtzariaModuleStatus.idle => 'טרם נבדק',
            OtzariaModuleStatus.checking => 'בודק...',
            OtzariaModuleStatus.upToDate => 'מעודכן',
            OtzariaModuleStatus.updateAvailable => 'עדכון זמין',
            OtzariaModuleStatus.updating => 'מוריד ומתקין...',
            OtzariaModuleStatus.error => 'שגיאה',
          },
        ),
        SettingsActionTile.text(
          icon: FluentIcons.tag_24_regular,
          title: 'גרסה מותקנת',
          subtitle: c.currentVersion ?? 'לא זוהתה התקנה שנוהלה מהלאנצ׳ר הזה',
          subtitleLtr: c.currentVersion != null,
        ),
        SettingsActionTile.text(
          icon: FluentIcons.cloud_arrow_down_24_regular,
          title: 'גרסה זמינה',
          subtitle: c.latestVersion ?? 'לא ידועה — יש לבצע בדיקה',
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
          InfoErrorRow(message: c.errorMessage!, onRetry: onRecheck),
        if (isBusy)
          InfoProgressRow(
            stage: 'מוריד ומתקין את אוצריא...',
            progress: progress,
          ),
        CardActionsRow(
          actions: [
            ActionButton.recommended(
              text: 'הפעלת אוצריא',
              icon: FluentIcons.play_24_regular,
              onPressed: c.canLaunch ? c.launch : null,
            ),
            ActionButton.neutral(
              text: 'בדיקה מחדש',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: isBusy ? null : () => onRecheck(),
            ),
            // הורדה והתקנה עדיין מאוחדות בקריאה אחת ל-otzaria_manager;
            // ההפרדה ביניהן מתוכננת לשלב 2 (תכנון §2.3).
            ActionButton.neutral(
              text: 'הורדה והתקנה',
              icon: FluentIcons.arrow_download_24_regular,
              isLoading: isBusy,
              onPressed: c.status == OtzariaModuleStatus.updateAvailable
                  ? () => _confirmAppUpdate(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmAppUpdate(BuildContext context) async {
    final approved = await showTwoActionsDialog(
      context: context,
      title: 'עדכון תוכנת אוצריא',
      content: 'הגרסה ${otzaria.latestVersion} תורד ותותקן על גבי '
          '${otzaria.currentVersion ?? 'ההתקנה הקיימת'}. '
          'יש לוודא שאוצריא סגורה לפני ההתקנה.',
      confirmText: 'הורד והתקן',
    );
    if (!approved) return;
    await otzaria.update();
    if (otzaria.status == OtzariaModuleStatus.upToDate) {
      UiSnack.showSuccess('אוצריא עודכנה לגרסה ${otzaria.currentVersion}');
    }
  }

  // ── ספרייה ────────────────────────────────────────────────────────────────

  Widget _libraryCard(BuildContext context) {
    final c = library;

    return SettingsCard(
      title: 'ספריית הספרים',
      subtitle: 'תקציר בלבד — הפעולות המלאות במסך "ספרייה".',
      children: [
        InfoStatusRow(
          icon: FluentIcons.library_24_regular,
          title: 'מצב',
          kind: libraryStatusKind(c.status),
          label: libraryStatusLabel(c),
        ),
        SettingsActionTile.text(
          icon: FluentIcons.number_symbol_24_regular,
          title: 'גרסת המסד המקומית',
          subtitle: c.localVersion?.toString() ?? 'לא ידועה',
          subtitleLtr: c.localVersion != null,
        ),
        SettingsActionTile.path(
          icon: FluentIcons.document_24_regular,
          title: 'קובץ seforim.db',
          path: c.dbPath,
          placeholder: 'לא נמצא — יש לבחור מיקום במסך "ספרייה"',
        ),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'מסך הספרייה',
              icon: FluentIcons.arrow_forward_24_regular,
              onPressed: onGoToLibrary,
            ),
          ],
        ),
      ],
    );
  }

  // ── תוספים ────────────────────────────────────────────────────────────────

  Widget _pluginsCard(BuildContext context) {
    final c = plugins;
    final updatable = c.updatablePlugins.length;

    return SettingsCard(
      title: 'תוספים',
      subtitle: 'תקציר בלבד — החנות המלאה במסך "תוספים".',
      children: [
        InfoStatusRow(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'מצב',
          kind: switch (c.status) {
            PluginsModuleStatus.idle => StatusKind.unknown,
            PluginsModuleStatus.loading ||
            PluginsModuleStatus.syncing =>
              StatusKind.working,
            PluginsModuleStatus.error => StatusKind.error,
            PluginsModuleStatus.ready =>
              updatable == 0 ? StatusKind.ok : StatusKind.updateAvailable,
          },
          label: switch (c.status) {
            PluginsModuleStatus.idle => 'טרם נטען',
            PluginsModuleStatus.loading => 'טוען...',
            PluginsModuleStatus.syncing => 'מסנכרן...',
            PluginsModuleStatus.error => 'שגיאה',
            PluginsModuleStatus.ready => updatable == 0
                ? 'אין עדכונים ממתינים'
                : '$updatable עדכונים זמינים',
          },
        ),
        SettingsActionTile.text(
          icon: FluentIcons.apps_list_24_regular,
          title: 'תוספים מותקנים באוצריא',
          subtitle: c.status == PluginsModuleStatus.idle
              ? 'טרם נסרקו'
              : '${c.installedCount} זוהו',
        ),
        SettingsActionTile.text(
          icon: FluentIcons.arrow_sync_24_regular,
          title: 'הקטלוג סונכרן לאחרונה',
          subtitle: c.lastSync == null
              ? 'טרם בוצע סנכרון'
              : c.lastSync!.toLocal().toString().split('.').first,
        ),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'מסך התוספים',
              icon: FluentIcons.arrow_forward_24_regular,
              onPressed: onGoToPlugins,
            ),
          ],
        ),
      ],
    );
  }

  // ── העברה למחשב לא־מקוון ──────────────────────────────────────────────────

  Widget _transferCard(BuildContext context) {
    final s = settings.settings;

    return SettingsCard(
      title: 'העברה למחשב לא־מקוון',
      subtitle: 'הורדה במחשב מקוון, החלה במחשב שאין בו אינטרנט.',
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.cloud_24_regular,
          title: 'מצב הרשת',
          subtitle: switch (network) {
            NetworkState.online => 'מחובר — ניתן להוריד ולהכין כונן',
            NetworkState.offline =>
              'לא מחובר — ניתן לעדכן מחבילה שכבר קיימת בכונן',
            NetworkState.checking => 'בודק...',
            NetworkState.unknown => 'טרם נבדק',
          },
        ),
        SettingsActionTile.path(
          icon: FluentIcons.usb_stick_24_regular,
          title: 'יעד USB מועדף',
          path: s.preferredUsbPath,
          placeholder: 'לא נבחר — ניתן להגדיר במסך ההגדרות',
        ),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'העברת הספרייה',
              icon: FluentIcons.arrow_forward_24_regular,
              onPressed: onGoToLibrary,
            ),
            // חבילת USB אחידה לתוכנה + ספרייה + תוספים היא שלב 3 בתכנון.
            const ActionButton.ghost(
              text: 'חבילת עדכון אחידה (בבנייה)',
              icon: FluentIcons.box_24_regular,
              onPressed: null,
            ),
          ],
        ),
      ],
    );
  }
}

// ── תרגום מצב הספרייה לתצוגה — משותף לדף הבית ולמסך הספרייה ──────────────────

StatusKind libraryStatusKind(LibraryModuleStatus status) => switch (status) {
      LibraryModuleStatus.idle => StatusKind.unknown,
      LibraryModuleStatus.checking => StatusKind.working,
      LibraryModuleStatus.upToDate => StatusKind.ok,
      LibraryModuleStatus.updateAvailable => StatusKind.updateAvailable,
      LibraryModuleStatus.updating => StatusKind.working,
      LibraryModuleStatus.error => StatusKind.error,
      LibraryModuleStatus.needsManualPath => StatusKind.needsAction,
    };

String libraryStatusLabel(LibraryModuleController c) => switch (c.status) {
      LibraryModuleStatus.idle => 'טרם נבדק',
      LibraryModuleStatus.checking => 'בודק...',
      LibraryModuleStatus.upToDate => 'מעודכן',
      LibraryModuleStatus.updateAvailable =>
        c.isFreshInstall ? 'טרם הותקנה ספרייה' : 'עדכון זמין',
      LibraryModuleStatus.updating => 'מעדכן...',
      LibraryModuleStatus.error => 'שגיאה',
      LibraryModuleStatus.needsManualPath => 'נדרשת בחירת מיקום',
    };
