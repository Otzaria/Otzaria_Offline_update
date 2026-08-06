import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../services/file_reveal.dart';
import '../settings/settings_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'app_shell.dart';

/// דף הבית — הורדה אחת מהרשת אל התיקייה שלצד התוכנה, ואחריה התקנה מקומית
/// של כל רכיב. שני השלבים יכולים לקרות על שני מחשבים שונים, בימים שונים.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.otzaria,
    required this.library,
    required this.plugins,
    required this.settings,
    required this.dataDir,
    required this.network,
    required this.otzariaIsRunning,
    required this.isDownloading,
    required this.onRecheck,
    required this.onDownloadAll,
    required this.onGoToLibrary,
    required this.onGoToPlugins,
  });

  final OtzariaModuleController otzaria;
  final LibraryModuleController library;
  final PluginsModuleController plugins;
  final SettingsController settings;
  final String dataDir;
  final NetworkState network;
  final bool otzariaIsRunning;
  final bool isDownloading;
  final Future<void> Function() onRecheck;
  final Future<void> Function() onDownloadAll;
  final VoidCallback onGoToLibrary;
  final VoidCallback onGoToPlugins;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'דף הבית',
      description: 'העדכונים יורדים לתיקייה שלצד התוכנה, ומשם מותקנים. '
          'אחרי ההורדה אין יותר צורך בחיבור לאינטרנט.',
      children: [
        _downloadCard(context),
        _otzariaCard(context),
        _libraryCard(context),
        _pluginsCard(context),
      ],
    );
  }

  // ── הורדה מהרשת ───────────────────────────────────────────────────────────

  Widget _downloadCard(BuildContext context) {
    final s = settings.settings;

    return SettingsCard(
      title: 'הורדת עדכונים',
      subtitle: 'הפעולה היחידה שדורשת אינטרנט. יש להריץ אותה במחשב מקוון; '
          'ההתקנה עצמה תעבוד אחר כך גם בלי רשת.',
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.desktop_24_regular,
          title: 'תוכנת אוצריא',
          subtitle: 'קובץ ההתקנה של הגרסה האחרונה',
          value: s.syncApp,
          enabled: !isDownloading,
          onChanged: (v) => settings.update(s.copyWith(syncApp: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.library_24_regular,
          title: 'ספריית הספרים',
          subtitle: 'הרכיב הכבד — המסד המלא הוא כ-1GB',
          value: s.syncLibrary,
          enabled: !isDownloading,
          onChanged: (v) => settings.update(s.copyWith(syncLibrary: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: 'חנות התוספים',
          subtitle: 'הקטלוג וקובצי ההתקנה של כל התוספים',
          value: s.syncPlugins,
          enabled: !isDownloading,
          onChanged: (v) => settings.update(s.copyWith(syncPlugins: v)),
        ),
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: 'תיקיית הנתונים',
          path: dataDir,
          placeholder: '—',
          actions: [
            ActionButton.ghost(
              text: 'פתיחת התיקייה',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: () => _openDataDir(context),
            ),
          ],
        ),
        if (isDownloading) _downloadProgress(),
        ..._downloadErrors(),
        CardActionsRow(
          actions: [
            ActionButton.recommended(
              text: 'הורדת העדכונים',
              icon: FluentIcons.arrow_download_24_regular,
              isLoading: isDownloading,
              onPressed: s.hasSyncSelection && !isDownloading
                  ? () => onDownloadAll()
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  /// שורת התקדמות אחת לרכיב שמוריד כרגע — ההורדות רצות בטור, ולכן לכל
  /// היותר אחת מהן פעילה.
  Widget _downloadProgress() {
    if (otzaria.downloadStatus == OtzariaDownloadStatus.downloading) {
      final received = otzaria.downloadReceived;
      final total = otzaria.downloadTotal;
      return InfoProgressRow(
        stage: 'מוריד את תוכנת אוצריא...',
        progress: (received != null && total != null && total > 0)
            ? received / total
            : null,
      );
    }
    if (library.downloadStatus == MirrorDownloadStatus.downloading) {
      final done = library.downloadDoneAssets;
      final total = library.downloadTotalAssets;
      return InfoProgressRow(
        stage: library.downloadStage ?? 'מוריד את הספרייה...',
        progress:
            (done != null && total != null && total > 0) ? done / total : null,
      );
    }
    if (plugins.status == PluginsModuleStatus.syncing) {
      return InfoProgressRow(
        stage: plugins.syncMessage ?? 'מוריד את התוספים...',
        progress: plugins.syncProgress,
      );
    }
    return const InfoProgressRow(stage: 'מתחיל הורדה...');
  }

  List<Widget> _downloadErrors() {
    return [
      if (otzaria.downloadError != null)
        InfoErrorRow(message: 'תוכנת אוצריא: ${otzaria.downloadError}'),
      if (library.downloadError != null)
        InfoErrorRow(message: 'ספרייה: ${library.downloadError}'),
    ];
  }

  Future<void> _openDataDir(BuildContext context) async {
    if (!await Directory(dataDir).exists()) {
      UiSnack.show('התיקייה עדיין לא נוצרה.');
      return;
    }
    if (await FileReveal.revealDirectory(dataDir)) return;
    UiSnack.show('הנתיב: $dataDir');
  }

  // ── תוכנת אוצריא ──────────────────────────────────────────────────────────

  Widget _otzariaCard(BuildContext context) {
    final c = otzaria;
    final isBusy = c.status == OtzariaModuleStatus.installing;

    return SettingsCard(
      title: 'תוכנת אוצריא',
      subtitle: 'הגרסה המותקנת במחשב הזה, מול זו שיושבת בתיקייה המקומית.',
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
          InfoErrorRow(message: c.errorMessage!, onRetry: onRecheck),
        if (isBusy) const InfoProgressRow(stage: 'מתקין את אוצריא...'),
        CardActionsRow(
          actions: [
            ActionButton.recommended(
              text: 'הפעלת אוצריא',
              icon: FluentIcons.play_24_regular,
              onPressed: c.canLaunch ? c.launch : null,
            ),
            ActionButton.neutral(
              text: 'התקנה מהתיקייה',
              icon: FluentIcons.desktop_arrow_right_24_regular,
              isLoading: isBusy,
              onPressed: c.status == OtzariaModuleStatus.updateAvailable
                  ? () => _confirmAppInstall(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmAppInstall(BuildContext context) async {
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
            PluginsModuleStatus.syncing => 'מוריד...',
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
          title: 'הקטלוג הורד לאחרונה',
          subtitle: c.lastSync == null
              ? 'טרם הורד'
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
}

// ── תרגום מצב הספרייה לתצוגה — משותף לדף הבית ולמסך הספרייה ──────────────────

StatusKind libraryStatusKind(LibraryModuleStatus status) => switch (status) {
      LibraryModuleStatus.idle => StatusKind.unknown,
      LibraryModuleStatus.checking => StatusKind.working,
      LibraryModuleStatus.upToDate => StatusKind.ok,
      LibraryModuleStatus.updateAvailable => StatusKind.updateAvailable,
      LibraryModuleStatus.updating => StatusKind.working,
      LibraryModuleStatus.error => StatusKind.error,
      LibraryModuleStatus.needsDownload => StatusKind.needsAction,
      LibraryModuleStatus.needsManualPath => StatusKind.needsAction,
    };

String libraryStatusLabel(LibraryModuleController c) => switch (c.status) {
      LibraryModuleStatus.idle => 'טרם נבדק',
      LibraryModuleStatus.checking => 'בודק...',
      LibraryModuleStatus.upToDate => 'מעודכן',
      LibraryModuleStatus.updateAvailable =>
        c.isFreshInstall ? 'טרם הותקנה ספרייה' : 'מוכן להתקנה',
      LibraryModuleStatus.updating => 'מעדכן...',
      LibraryModuleStatus.error => 'שגיאה',
      LibraryModuleStatus.needsDownload => 'טרם הורדו עדכונים',
      LibraryModuleStatus.needsManualPath => 'נדרשת בחירת מיקום',
    };
