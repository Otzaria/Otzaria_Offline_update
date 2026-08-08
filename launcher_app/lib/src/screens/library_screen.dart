import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'home_screen.dart';

/// מסך עדכון הספרייה — מציג את ה-DB שזוהה בפועל ומחיל עליו עדכון מהתיקייה
/// שלצד התוכנה. אין כאן בחירת מקור: המקור תמיד אותה תיקייה.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.otzariaIsRunning,
    required this.isDownloading,
    required this.onProcessStateChanged,
  });

  final LibraryModuleController library;
  final bool otzariaIsRunning;
  final bool isDownloading;
  final Future<void> Function() onProcessStateChanged;

  bool get _isBusy =>
      library.status == LibraryModuleStatus.updating || isDownloading;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'עדכון ספרייה',
      description: 'העדכון מוחל מתיקיית התוכנה. '
          'המסד לא ייגע בו עד שתאשר, ובזמן שאוצריא פתוחה העדכון חסום.',
      children: [
        _stateCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב המסד ──────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = library;

    return SettingsCard(
      title: 'מצב המסד',
      children: [
        InfoStatusRow(
          icon: FluentIcons.database_24_regular,
          title: 'מצב',
          kind: libraryStatusKind(c.status),
          label: libraryStatusLabel(c),
        ),
        SettingsActionTile.path(
          icon: FluentIcons.document_24_regular,
          title: 'קובץ seforim.db הפעיל',
          path: c.dbPath,
          placeholder: 'לא נמצא — יש להצביע על הקובץ',
          actions: [
            ActionButton.neutral(
              text: 'בחירת קובץ מסד',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickDbFile(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.number_symbol_24_regular,
          title: 'גרסה מקומית',
          subtitle: c.localVersion?.toString() ?? 'לא ידועה',
          subtitleLtr: c.localVersion != null,
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: 'גרסת היעד בתיקייה המקומית',
          subtitle: c.targetVersion?.toString() ??
              (c.status == LibraryModuleStatus.needsDownload
                  ? 'טרם הורדו עדכונים'
                  : 'לא ידועה — יש לבצע בדיקה'),
          subtitleLtr: c.targetVersion != null,
        ),
        if (otzariaIsRunning)
          SettingsActionTile.text(
            icon: FluentIcons.warning_24_regular,
            title: 'אוצריא פתוחה',
            subtitle: 'יש לסגור את אוצריא לפני החלת עדכון על המסד.',
          ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == LibraryModuleStatus.updating)
          InfoProgressRow(
            stage: c.stageText ?? 'מעדכן את המסד...',
            progress: c.applyProgress,
          ),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'בדיקה מחדש',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _isBusy ? null : c.checkForUpdate,
            ),
            ActionButton.recommended(
              text: 'התקנת העדכון',
              icon: FluentIcons.database_arrow_right_24_regular,
              isLoading: c.status == LibraryModuleStatus.updating,
              onPressed: c.status == LibraryModuleStatus.updateAvailable
                  ? () => _confirmUpdate(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDbFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'בחירת קובץ seforim.db',
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await library.setCustomDbPath(path);
    UiSnack.showSuccess('מיקום המסד עודכן');
  }

  Future<void> _confirmUpdate(BuildContext context) async {
    await onProcessStateChanged();
    if (otzariaIsRunning) {
      UiSnack.showError('אוצריא פתוחה — יש לסגור אותה ואז לנסות שוב.');
      return;
    }
    if (!context.mounted) return;

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

  // ── התיקייה שממנה מעדכנים ─────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = library;

    return SettingsCard(
      title: 'התיקייה שממנה מעדכנים',
      subtitle: 'קבועה, לצד קובץ ההרצה. כשהתוכנה על כונן נייד היא נוסעת '
          'איתו, וההחלה במחשב הלא־מקוון קוראת ממנה ישירות.',
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: 'תיקיית עדכוני הספרייה',
          path: c.mirrorDir,
          placeholder: '—',
        ),
        InfoStatusRow(
          icon: FluentIcons.arrow_download_24_regular,
          title: 'תוכן התיקייה',
          kind: switch (c.status) {
            LibraryModuleStatus.needsDownload => StatusKind.needsAction,
            LibraryModuleStatus.error => StatusKind.error,
            _ => StatusKind.ok,
          },
          label: switch (c.status) {
            LibraryModuleStatus.needsDownload =>
              'ריקה — יש להריץ הורדה בדף הבית',
            LibraryModuleStatus.error => 'לא ניתן לקרוא',
            _ => c.targetVersion != null
                ? 'מכילה גרסה ${c.targetVersion}'
                : 'קיימת',
          },
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
