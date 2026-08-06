import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// דף הבית — שני אריחים בלבד: עדכון/התקנת תוכנת אוצריא, ועדכון הספרייה.
/// כל פרט טכני נוסף (סנכרון, נתיבים, מספרי גרסה) נמצא במסכים המפורטים
/// ("תוכנה"/"ספרייה") או בהגדרות — כאן רק "יש עדכון? לחצו."
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.otzaria,
    required this.library,
    required this.settings,
    required this.otzariaIsRunning,
    required this.isDownloading,
    required this.isCheckingOnline,
    required this.onCheckOnline,
    required this.onDownloadAll,
    required this.onGoToOtzaria,
    required this.onGoToLibrary,
  });

  final OtzariaModuleController otzaria;
  final LibraryModuleController library;
  final SettingsController settings;
  final bool otzariaIsRunning;
  final bool isDownloading;
  final bool isCheckingOnline;
  final Future<void> Function() onCheckOnline;
  final Future<void> Function() onDownloadAll;
  final VoidCallback onGoToOtzaria;
  final VoidCallback onGoToLibrary;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'דף הבית',
      description: 'עדכון התוכנה והספרייה מהתיקייה שלצד התוכנה — בלי צורך '
          'באינטרנט.',
      children: [
        if (otzariaIsRunning)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: AppCard(
              child: SettingsActionTile.text(
                icon: FluentIcons.warning_24_regular,
                title: 'אוצריא פתוחה',
                subtitle: 'עדכון הספרייה חסום עד לסגירתה.',
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final otzariaTile = _otzariaTile(context);
            final libraryTile = _libraryTile(context);

            if (constraints.maxWidth < 560) {
              return Column(
                children: [
                  otzariaTile,
                  const SizedBox(height: AppTokens.spaceMD),
                  libraryTile,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: otzariaTile),
                const SizedBox(width: AppTokens.spaceMD),
                Expanded(child: libraryTile),
              ],
            );
          },
        ),
        const SizedBox(height: AppTokens.spaceLG),
        _onlineCheckCard(context),
      ],
    );
  }

  // ── אריח תוכנת אוצריא ────────────────────────────────────────────────────

  Widget _otzariaTile(BuildContext context) {
    final c = otzaria;
    final isBusy = c.status == OtzariaModuleStatus.installing;

    return _HomeTile(
      icon: FluentIcons.desktop_24_regular,
      title: 'תוכנת אוצריא',
      statusKind: switch (c.status) {
        OtzariaModuleStatus.idle => StatusKind.unknown,
        OtzariaModuleStatus.checking => StatusKind.working,
        OtzariaModuleStatus.upToDate => StatusKind.ok,
        OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
        OtzariaModuleStatus.installing => StatusKind.working,
        OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
        OtzariaModuleStatus.error => StatusKind.error,
      },
      statusLabel: switch (c.status) {
        OtzariaModuleStatus.idle => 'טרם נבדק',
        OtzariaModuleStatus.checking => 'בודק...',
        OtzariaModuleStatus.upToDate => 'מעודכן',
        OtzariaModuleStatus.updateAvailable => 'יש עדכון חדש',
        OtzariaModuleStatus.installing => 'מתקין...',
        OtzariaModuleStatus.needsDownload =>
          c.currentVersion == null ? 'לא נמצאה התקנה' : 'טרם הורד עדכון',
        OtzariaModuleStatus.error => 'שגיאה',
      },
      primaryActionText: switch (c.status) {
        OtzariaModuleStatus.updateAvailable => 'התקנה',
        _ => c.canLaunch ? 'הפעלה' : null,
      },
      primaryActionIcon: switch (c.status) {
        OtzariaModuleStatus.updateAvailable =>
          FluentIcons.desktop_arrow_right_24_regular,
        _ => FluentIcons.play_24_regular,
      },
      primaryActionLoading: isBusy,
      onPrimaryAction: switch (c.status) {
        OtzariaModuleStatus.updateAvailable => () => _confirmAppInstall(
              context,
            ),
        _ => c.canLaunch ? c.launch : null,
      },
      onDetails: onGoToOtzaria,
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

  // ── אריח הספרייה ──────────────────────────────────────────────────────────

  Widget _libraryTile(BuildContext context) {
    final c = library;
    final isBusy = c.status == LibraryModuleStatus.updating;

    return _HomeTile(
      icon: FluentIcons.library_24_regular,
      title: 'ספריית הספרים',
      statusKind: libraryStatusKind(c.status),
      statusLabel: libraryStatusLabel(c),
      primaryActionText: c.status == LibraryModuleStatus.updateAvailable
          ? (c.isFreshInstall ? 'התקנה' : 'עדכון')
          : null,
      primaryActionIcon: FluentIcons.database_arrow_right_24_regular,
      primaryActionLoading: isBusy,
      onPrimaryAction: c.status == LibraryModuleStatus.updateAvailable
          ? () => _confirmLibraryUpdate(context)
          : null,
      onDetails: onGoToLibrary,
    );
  }

  Future<void> _confirmLibraryUpdate(BuildContext context) async {
    if (otzariaIsRunning) {
      UiSnack.showError('אוצריא פתוחה — יש לסגור אותה ואז לנסות שוב.');
      return;
    }

    final c = library;
    final approved = await showTwoActionsDialog(
      context: context,
      title: 'עדכון ספריית הספרים',
      content: c.isFreshInstall
          ? 'הספרייה תותקן בפעם הראשונה (גרסה ${c.targetVersion}) '
              'מהתיקייה שלצד התוכנה. המסד גדול, וההתקנה עשויה להימשך זמן רב.'
          : 'המסד יעודכן מגרסה ${c.localVersion} לגרסה ${c.targetVersion}. '
              'גיבוי יישמר עד שהגרסה החדשה תיבדק בהצלחה.',
      confirmText: 'עדכן עכשיו',
    );
    if (!approved) return;

    await c.update();
    if (c.status == LibraryModuleStatus.upToDate) {
      UiSnack.showSuccess('המסד עודכן לגרסה ${c.localVersion}');
    }
  }

  // ── בדיקת עדכונים ברשת (צדדי) ────────────────────────────────────────────

  Widget _onlineCheckCard(BuildContext context) {
    final theme = Theme.of(context);
    final otzariaChecked = otzaria.onlineCheckedAt != null;
    final libraryChecked = library.onlineCheckedAt != null;
    final everChecked = otzariaChecked || libraryChecked;
    final otzariaOnline = otzariaChecked && otzaria.onlineCheckError == null;
    final libraryOnline = libraryChecked && library.onlineCheckError == null;
    final isOnline = otzariaOnline || libraryOnline;
    final hasUpdate = otzaria.hasOnlineUpdate || library.hasOnlineUpdate;

    final StatusKind kind;
    final String label;
    if (isCheckingOnline) {
      kind = StatusKind.working;
      label = 'בודק אם יש עדכונים ברשת...';
    } else if (!everChecked) {
      kind = StatusKind.unknown;
      label = 'טרם נבדק בהרצה הזו';
    } else if (!isOnline) {
      kind = StatusKind.unknown;
      label = 'אין חיבור לרשת כרגע';
    } else if (hasUpdate) {
      kind = StatusKind.updateAvailable;
      label = 'נמצאו עדכונים חדשים ברשת';
    } else {
      kind = StatusKind.ok;
      label = 'אין עדכונים חדשים ברשת';
    }

    return SettingsCard(
      title: 'בדיקת עדכונים',
      subtitle: 'רק במחשב שיש בו אינטרנט — לא נדרש בשביל ההתקנה עצמה.',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusChip(kind: kind, label: label),
                  const Spacer(),
                  ActionButton.neutral(
                    text: 'בדיקת עדכונים',
                    icon: FluentIcons.arrow_sync_24_regular,
                    isLoading: isCheckingOnline,
                    onPressed: isCheckingOnline ? null : () => onCheckOnline(),
                  ),
                ],
              ),
              if (isOnline && hasUpdate) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ActionButton.recommended(
                  text: 'הורד עכשיו',
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: isDownloading,
                  onPressed:
                      settings.settings.hasSyncSelection && !isDownloading
                          ? () => onDownloadAll()
                          : null,
                ),
              ],
              if (otzaria.onlineCheckedAt != null ||
                  library.onlineCheckedAt != null) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text(
                  'נבדק לאחרונה: ${_formatTime(otzaria.onlineCheckedAt ?? library.onlineCheckedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _formatTime(DateTime time) {
    final t = time.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
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
        c.isFreshInstall ? 'טרם הותקנה ספרייה' : 'יש עדכון חדש',
      LibraryModuleStatus.updating => 'מעדכן...',
      LibraryModuleStatus.error => 'שגיאה',
      LibraryModuleStatus.needsDownload => 'טרם הורדו עדכונים',
      LibraryModuleStatus.needsManualPath => 'נדרשת בחירת מיקום',
    };

// ── אריח בית — עיצוב אחיד לשני הרכיבים ────────────────────────────────────────

/// אריח גדול אחד בדף הבית: אייקון, כותרת, מצב, פעולה עיקרית (אם יש), וקישור
/// למסך המפורט. הפעולה העיקרית תמיד ברורה מאליה (הפעלה/התקנה/עדכון) —
/// כל שאר הפרטים (גרסאות, נתיבים) נמצאים מעבר לקישור "פרטים נוספים".
class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.title,
    required this.statusKind,
    required this.statusLabel,
    required this.primaryActionText,
    required this.primaryActionIcon,
    required this.primaryActionLoading,
    required this.onPrimaryAction,
    required this.onDetails,
  });

  final IconData icon;
  final String title;
  final StatusKind statusKind;
  final String statusLabel;
  final String? primaryActionText;
  final IconData primaryActionIcon;
  final bool primaryActionLoading;
  final VoidCallback? onPrimaryAction;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Icon(icon, color: cs.onSecondaryContainer, size: 26),
              ),
              const SizedBox(width: AppTokens.spaceMD),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          StatusChip(kind: statusKind, label: statusLabel),
          const SizedBox(height: AppTokens.spaceMD),
          if (primaryActionText != null)
            ActionButton.recommended(
              text: primaryActionText!,
              icon: primaryActionIcon,
              isLoading: primaryActionLoading,
              onPressed: onPrimaryAction,
            )
          else
            Text(
              'אין פעולה זמינה כרגע — לפרטים ולבחירה ידנית ראו למטה.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: AppTokens.spaceSM),
          ActionButton.ghost(
            text: 'פרטים נוספים',
            icon: FluentIcons.arrow_left_24_regular,
            onPressed: onDetails,
          ),
        ],
      ),
    );
  }
}
