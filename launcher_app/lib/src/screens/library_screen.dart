import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../services/file_reveal.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'home_screen.dart';

/// מסך עדכון הספרייה — מציג את ה-DB שזוהה בפועל ומאפשר החלת עדכון,
/// החלפת מקור (רשת / תיקייה מקומית) והכנת תוכן להעברה (תכנון §6).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.otzariaIsRunning,
    required this.onProcessStateChanged,
  });

  final LibraryModuleController library;
  final bool otzariaIsRunning;
  final Future<void> Function() onProcessStateChanged;

  bool get _isBusy => library.status == LibraryModuleStatus.updating;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'עדכון ספרייה',
      description: 'המסד לא ייגע בו עד שתאשר/י. בזמן שאוצריא פתוחה '
          'העדכון חסום, כדי לא לכתוב לקובץ שנעול על ידה.',
      children: [
        _stateCard(context),
        _sourceCard(context),
        _transferCard(context),
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
          icon: FluentIcons.cloud_arrow_down_24_regular,
          title: 'גרסת היעד במקור הפעיל',
          subtitle: c.targetVersion?.toString() ?? 'לא ידועה — יש לבצע בדיקה',
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
        if (_isBusy)
          InfoProgressRow(
            stage: c.stageText ?? 'מעדכן את המסד...',
            progress: c.applyProgress,
          ),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'בדיקת עדכונים',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _isBusy ? null : c.checkForUpdate,
            ),
            ActionButton.recommended(
              text: 'הורדה והתקנה',
              icon: FluentIcons.arrow_download_24_regular,
              isLoading: _isBusy,
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
          ? 'הספרייה תותקן בפעם הראשונה (גרסה ${c.targetVersion}). '
              'המסד גדול, וההורדה עשויה להימשך זמן רב.'
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

  // ── מקור העדכון ───────────────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = library;
    final isLocal = c.activeMirrorPath != null;

    return SettingsCard(
      title: 'מקור העדכון',
      subtitle: 'המקור לא מוחלף מאחורי הגב — הבחירה כאן היא זו שתקפה.',
      children: [
        SettingsActionTile.path(
          icon: isLocal
              ? FluentIcons.usb_stick_24_regular
              : FluentIcons.cloud_24_regular,
          title: isLocal ? 'תיקייה מקומית / USB' : 'אינטרנט (GitHub)',
          path: c.activeMirrorPath,
          placeholder: 'העדכונים נבדקים ומורדים מהרשת',
        ),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'עדכון מתיקייה מקומית',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickMirrorFolder(context),
            ),
            if (isLocal)
              ActionButton.ghost(
                text: 'חזרה לעדכון מהרשת',
                icon: FluentIcons.cloud_24_regular,
                onPressed: _isBusy ? null : c.useCloud,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickMirrorFolder(BuildContext context) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחירת תיקיית עדכון (כונן USB / תיקייה משותפת)',
    );
    if (path == null) return;
    await library.useLocalMirror(path);
    UiSnack.showSuccess('המקור הפעיל הוא כעת התיקייה שנבחרה');
  }

  // ── תוכן להעברה ───────────────────────────────────────────────────────────

  Widget _transferCard(BuildContext context) {
    final c = library;
    final isRefreshing = c.autoCacheStatus == MirrorExportStatus.exporting;

    return SettingsCard(
      title: 'תוכן להעברה למחשב אחר',
      subtitle: 'התיקייה הזו נבנית ברקע במחשב מקוון, ומועתקת כמות שהיא '
          'לכונן שיחובר למחשב הלא־מקוון.',
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: 'תיקיית ההעברה',
          path: c.offlineMirrorCacheDir,
          placeholder: 'לא נבנתה',
        ),
        InfoStatusRow(
          icon: FluentIcons.arrow_sync_24_regular,
          title: 'מצב הרענון',
          kind: switch (c.autoCacheStatus) {
            MirrorExportStatus.idle => StatusKind.unknown,
            MirrorExportStatus.exporting => StatusKind.working,
            MirrorExportStatus.done => StatusKind.ok,
            MirrorExportStatus.error => StatusKind.error,
          },
          label: switch (c.autoCacheStatus) {
            MirrorExportStatus.idle => 'לא רוענן בהרצה הזו',
            MirrorExportStatus.exporting => 'מרענן...',
            MirrorExportStatus.done => 'מוכן להעתקה',
            MirrorExportStatus.error => 'הרענון נכשל',
          },
        ),
        if (isRefreshing)
          InfoProgressRow(stage: c.autoCacheStage ?? 'מרענן ברקע...'),
        if (c.autoCacheStatus == MirrorExportStatus.error &&
            c.autoCacheError != null)
          InfoErrorRow(message: c.autoCacheError!),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'רענון התיקייה',
              icon: FluentIcons.arrow_download_24_regular,
              isLoading: isRefreshing,
              onPressed:
                  isRefreshing ? null : c.refreshOfflineMirrorCacheInBackground,
            ),
            ActionButton.ghost(
              text: 'פתיחת התיקייה',
              icon: FluentIcons.folder_open_24_regular,
              onPressed: () => _openTransferFolder(c.offlineMirrorCacheDir),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openTransferFolder(String path) async {
    if (!await Directory(path).exists()) {
      UiSnack.show('התיקייה עדיין לא נבנתה — יש לרענן אותה קודם.');
      return;
    }
    if (await FileReveal.revealDirectory(path)) return;
    UiSnack.show('הנתיב: $path');
  }
}
