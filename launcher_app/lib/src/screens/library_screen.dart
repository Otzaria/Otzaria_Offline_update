import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/library_module_controller.dart';
import '../services/byte_size.dart';
import '../services/native_file_dialogs.dart';
import '../services/timestamps.dart';
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
    required this.onRequestReindex,
  });

  final LibraryModuleController library;
  final bool otzariaIsRunning;
  final bool isDownloading;

  /// בודקת מחדש אם אוצריא פתוחה ומחזירה את התוצאה הטרייה — ראו
  /// [_confirmUpdate].
  final Future<bool> Function() onProcessStateChanged;

  /// מוסרת לאוצריא את בקשת עדכון אינדקס החיפוש. יושבת ב-`AppShell` כי
  /// המסירה עוברת דרך קובץ ההרצה של אוצריא, שמודול האפליקציה מכיר.
  final Future<void> Function() onRequestReindex;

  bool get _isBusy =>
      library.status == LibraryModuleStatus.updating || isDownloading;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.libraryScreen;

    return ScreenBody(
      title: t.title,
      children: [
        _stateCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב המסד ──────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = library;
    final t = context.strings.libraryScreen;

    return SettingsCard(
      title: t.stateCardTitle,
      actions: [
        RecheckButton(onPressed: _isBusy ? null : _recheck),
        // ההתאוששות אחרי כשל דלתא — מוצגת רק אז, וכשיש מסד מלא במראה.
        if (c.canRetryWithFullDownload)
          ActionButton.neutral(
            text: t.fullDownloadInsteadButton,
            icon: FluentIcons.arrow_download_24_regular,
            onPressed: _isBusy ? null : () => _confirmFullDownload(context),
          ),
        ActionButton.recommended(
          text: t.installUpdateButton,
          icon: FluentIcons.database_arrow_right_24_regular,
          isLoading: c.status == LibraryModuleStatus.updating,
          onPressed: c.status == LibraryModuleStatus.updateAvailable
              ? () => _confirmUpdate(context)
              : null,
        ),
      ],
      children: [
        InfoStatusRow(
          icon: FluentIcons.database_24_regular,
          title: t.stateRowTitle,
          kind: libraryStatusKind(c.status),
          label: libraryStatusLabel(context, c),
        ),
        // כשאין עדיין מסד, האריח מציג את **יעד ההתקנה** ולא "לא נמצא": שם
        // ינחתו הספרים, וזו ההזדמנות לשנות את המיקום לפני שהם יורדים.
        // הנתיב עצמו אינו מוצג — הוא ארוך, ומעתיקים אותו בכפתור.
        SettingsActionTile.text(
          icon: FluentIcons.document_24_regular,
          title: c.dbPath == null ? t.installTargetTitle : t.dbFileTitle,
          subtitle: c.dbPath == null && c.installTargetPath == null
              ? t.dbFileMissing
              : null,
          actions: [
            if (c.dbPath ?? c.installTargetPath case final path?)
              CopyPathButton(path: path),
            if (c.dbPath == null)
              ActionButton.neutral(
                text: t.pickInstallDirButton,
                icon: FluentIcons.folder_add_24_regular,
                onPressed: _isBusy ? null : () => _pickInstallDir(context),
              ),
            ActionButton.neutral(
              text: t.pickDbButton,
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickDbFile(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.number_symbol_24_regular,
          title: t.localVersionTitle,
          subtitle:
              c.localVersion?.toString() ?? context.strings.common.unknownValue,
          subtitleLtr: c.localVersion != null,
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: t.targetVersionTitle,
          subtitle: c.targetVersion?.toString() ??
              (c.status == LibraryModuleStatus.needsDownload
                  ? t.targetVersionNothingDownloaded
                  : t.targetVersionUnknown),
          subtitleLtr: c.targetVersion != null,
        ),
        if (otzariaIsRunning)
          SettingsActionTile.text(
            icon: FluentIcons.warning_24_regular,
            title: t.otzariaRunningTitle,
            subtitle: t.otzariaRunningSubtitle,
          ),
        // האינדקס של אוצריא אינו יודע שהמסד התחלף מתחתיו, ולכן חיפוש בספר
        // שהשתנה מחזיר תוכן ישן עד שהבקשה נמסרת.
        if (c.hasPendingReindex)
          SettingsActionTile.text(
            icon: FluentIcons.search_24_regular,
            title: t.reindexTitle,
            subtitle: t.reindexPendingSubtitle,
            actions: [
              ActionButton.recommended(
                text: t.reindexButton,
                icon: FluentIcons.play_24_regular,
                onPressed: _isBusy ? null : onRequestReindex,
              ),
            ],
          ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == LibraryModuleStatus.updating)
          libraryApplyProgressRow(context, c),
      ],
    );
  }

  /// "בדוק שוב" מרענן גם את מצב התהליך: האזהרה "אוצריא פתוחה" יושבת באותו
  /// כרטיס, ולחיצה על הכפתור שמתחתיה אמורה לרענן גם אותה.
  Future<void> _recheck() async {
    await onProcessStateChanged();
    await library.checkForUpdate();
  }

  Future<void> _pickDbFile(BuildContext context) async {
    final t = context.strings.libraryScreen;
    final path = await NativeFileDialogs.pickFile(
      dialogTitle: t.pickDbDialogTitle,
      allowedExtensions: const ['db'],
    );
    if (path == null || !context.mounted) return;
    if (!await _confirmLocationOutsideOtzaria(context, path)) return;
    await library.setCustomDbPath(path);
    UiSnack.showSuccess(t.dbPathUpdatedSnack);
  }

  /// בחירת התיקייה שאליה תותקן ספרייה חדשה — הדרך לשנות את יעד ההתקנה לפני
  /// שהיא מתחילה.
  Future<void> _pickInstallDir(BuildContext context) async {
    final t = context.strings.libraryScreen;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null || !context.mounted) return;
    if (!await _confirmLocationOutsideOtzaria(context, library.dbPathIn(dir))) {
      return;
    }
    await library.setInstallDir(dir);
    UiSnack.showSuccess(t.installDirUpdatedSnack);
  }

  /// מיקום שאוצריא אינה מחפשת בו מותר — אבל רק אחרי אזהרה מפורשת: היא לא
  /// תראה שם ספרים עד שהמשתמש יצביע על התיקייה מתוך ההגדרות שלה.
  Future<bool> _confirmLocationOutsideOtzaria(
    BuildContext context,
    String dbPath,
  ) async {
    if (await library.isDbPathKnownToOtzaria(dbPath)) return true;
    if (!context.mounted) return false;
    final t = context.strings.libraryScreen;
    return showTwoActionsDialog(
      context: context,
      title: t.customLocationDialogTitle,
      content: t.customLocationPrompt(dbPath),
      confirmText: t.customLocationConfirm,
    );
  }

  Future<void> _confirmUpdate(BuildContext context) async {
    // התוצאה **המוחזרת** ולא [otzariaIsRunning]: המסך הוא `StatelessWidget`,
    // והשדה נלכד בבנייה — אחרי הרענון הוא עדיין "פתוחה", וכך העדכון נחסם
    // לנצח גם אחרי שאוצריא נסגרה.
    if (await onProcessStateChanged()) {
      UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
      return;
    }
    if (!context.mounted) return;
    final home = context.strings.home;

    final c = library;
    final approved = await showTwoActionsDialog(
      context: context,
      title: context.strings.libraryScreen.updateDialogTitle,
      content: c.isFreshInstall
          ? home.libraryFreshInstallPrompt('${c.targetVersion}')
          : home.libraryUpdatePrompt('${c.localVersion}', '${c.targetVersion}'),
      subtitle: home.doNotRemoveDriveWarning,
      confirmText: home.libraryUpdateConfirm,
    );
    if (!approved) return;

    await c.update();
    if (c.status == LibraryModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.libraryUpdatedSnack('${c.localVersion}'),
      );
    }
    // מציעים את עדכון האינדקס מיד — הרגע שבו המשתמש כאן ממילא. סירוב אינו
    // מוחק את הסימון: האריח בכרטיס וההפעלה הבאה של אוצריא יציעו שוב.
    await onRequestReindex();
  }

  /// המסלול החלופי: המסד המלא מהמראה, אחרי שמסלול הדלתא נכשל.
  Future<void> _confirmFullDownload(BuildContext context) async {
    if (await onProcessStateChanged()) {
      UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
      return;
    }
    if (!context.mounted) return;
    final t = context.strings.libraryScreen;

    final c = library;
    final size = c.fullDownloadFallbackSize;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.fullDownloadInsteadDialogTitle,
      content: t.fullDownloadInsteadPrompt(
        size != null && size > 0
            ? formatBytes(size)
            : context.strings.common.unknownValue,
      ),
      subtitle: context.strings.home.doNotRemoveDriveWarning,
      confirmText: context.strings.common.install,
    );
    if (!approved) return;

    await c.updateWithFullDownload();
    if (c.status == LibraryModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.libraryUpdatedSnack('${c.localVersion}'),
      );
    }
    await onRequestReindex();
  }

  // ── התיקייה שממנה מעדכנים ─────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = library;
    final t = context.strings.libraryScreen;

    return SettingsCard(
      title: t.sourceCardTitle,
      hint: t.sourceCardHint,
      children: [
        // הנתיב עצמו אינו מוצג — הוא קבוע, ארוך, ומה שעושים איתו זה להעתיק.
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: t.sourceDirTitle,
          actions: [CopyPathButton(path: c.mirrorDir)],
        ),
        InfoStatusRow(
          icon: FluentIcons.arrow_download_24_regular,
          title: t.mirrorContentTitle,
          kind: switch (c.status) {
            LibraryModuleStatus.needsDownload => StatusKind.needsAction,
            LibraryModuleStatus.error => StatusKind.error,
            _ => StatusKind.ok,
          },
          label: switch (c.status) {
            LibraryModuleStatus.needsDownload => t.mirrorEmpty,
            LibraryModuleStatus.error => t.mirrorUnreadable,
            _ => c.targetVersion != null
                ? t.mirrorHasVersion('${c.targetVersion}')
                : t.mirrorPresent,
          },
        ),
        if (c.lastDownloadedAt != null)
          SettingsActionTile.text(
            icon: FluentIcons.history_24_regular,
            title: context.strings.common.lastDownloaded,
            subtitle: formatTimestamp(c.lastDownloadedAt!),
          ),
        // רק במצב אישי: זו נקודת המוצא של ההורדה, והיא נרשמת אך ורק כאן —
        // התוכנה אינה קוראת את גרסת המסד מעצמה.
        if (c.personalUpdateMode)
          SettingsActionTile.text(
            icon: FluentIcons.person_24_regular,
            title: t.personalVersionTitle,
            subtitle: c.personalFromVersion != null
                ? t.personalVersionRecorded('${c.personalFromVersion}')
                : t.personalVersionMissing,
            actions: [
              ActionButton.neutral(
                text: t.personalVersionButton,
                icon: FluentIcons.database_search_24_regular,
                onPressed:
                    _isBusy ? null : () => _capturePersonalVersion(context),
              ),
            ],
          ),
        if (c.personalUpdateMode && c.personalDownloadNote != null)
          SettingsActionTile.text(
            icon: FluentIcons.info_24_regular,
            title: t.downloadNoteTitle,
            subtitle: switch (c.personalDownloadNote!) {
              LibraryPersonalDownloadNote.fromRecordedVersion =>
                t.downloadNotePersonal('${c.personalFromVersion}'),
              LibraryPersonalDownloadNote.versionUnknown =>
                t.downloadNotePersonalUnknownVersion,
              LibraryPersonalDownloadNote.upToDate =>
                t.downloadNotePersonalUpToDate('${c.personalFromVersion}'),
            },
          ),
      ],
    );
  }

  /// קוראת את גרסת המסד של המחשב הזה ורושמת אותה. הדיווח הוא snack ולא שדה
  /// מצב: לחיצה שלא מצאה מסד היא מידע חד-פעמי, לא תקלה שנשארת על המסך.
  Future<void> _capturePersonalVersion(BuildContext context) async {
    final t = context.strings.libraryScreen;
    final captured = await library.capturePersonalVersion();
    if (!context.mounted) return;
    if (captured) {
      UiSnack.showSuccess(
        t.personalVersionCapturedSnack('${library.personalFromVersion}'),
      );
    } else {
      UiSnack.showError(t.personalVersionNotFoundSnack);
    }
  }
}
