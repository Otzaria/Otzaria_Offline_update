import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/library_module_controller.dart';
import '../flows/library_flows.dart';
import '../services/byte_size.dart';
import '../services/timestamps.dart';
import '../shell/shell_keys.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'reports/reports_page.dart' show showReportsDisclosure;

/// דף "הספרייה": כרטיס מצב, הסכמה לחיפוש החכם, מה חדש ומתקדם.
/// ההחלה עצמה רצה במסך המשימה ("עדכון כאן", הספרייה בלבד).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.otzariaIsRunning,
    required this.isDownloading,
    required this.onProcessStateChanged,
    required this.onCloseOtzaria,
    required this.onRequestReindex,
    required this.onGoToSettings,
    this.onGrantSemanticConsent,
    this.onUpdateHere,
    this.onInstallFull,
    this.semanticOffer = false,
    this.busy = false,
    this.readOnly = false,
    this.appInstalled = true,
    this.appInstallable = false,
  });

  final LibraryModuleController library;
  final bool otzariaIsRunning;
  final bool isDownloading;

  /// בודקת מחדש אם אוצריא פתוחה — "בדוק שוב" מרענן גם את האזהרה.
  final Future<bool> Function() onProcessStateChanged;

  /// מבקשת מאוצריא הפתוחה להיסגר ומחזירה אם היא אכן נסגרה.
  final Future<bool> Function() onCloseOtzaria;

  /// מוסרת לאוצריא את בקשת בניית החיפוש. יושבת ב-`AppSession` כי המסירה
  /// עוברת דרך קובץ ההרצה של אוצריא, שמודול האפליקציה מכיר.
  final Future<void> Function() onRequestReindex;

  /// "שינוי" ליד היעד של ההורדה — הקבוצה בהגדרות.
  final VoidCallback onGoToSettings;
  final Future<void> Function()? onGrantSemanticConsent;

  /// עדכון או התקנה של הספרייה במסך המשימה.
  final VoidCallback? onUpdateHere;

  /// הספרייה המלאה שבכונן, במקום עדכון שנכשל — באותו מסך משימה.
  final VoidCallback? onInstallFull;

  /// `AppSession.onlineSemanticOffer` — שורה משלו, לא חלק מ"זמין להורדה".
  final bool semanticOffer;

  /// משימה ארוכה רצה במקום אחר.
  final bool busy;

  /// כונן מוגן: אי אפשר לרשום אליו את המחשב הזה או לשנות את המיקום.
  final bool readOnly;

  /// אוצריא מותקנת במחשב הזה. בלעדיה "עדכון כאן" מתקין קודם את התוכנה —
  /// ורק כשהיא בכונן ([appInstallable]) והספרייה עוד לא מותקנת.
  final bool appInstalled;

  /// `null` — מודול התוכנה עוד בבדיקה או שהבדיקה נכשלה: לא ידוע אם היא בכונן.
  final bool? appInstallable;

  bool get _isBusy =>
      library.isApplying ||
      library.status == LibraryModuleStatus.updating ||
      isDownloading;

  @override
  Widget build(BuildContext context) {
    final c = library;
    final t = context.strings.pages;
    if (c.status == LibraryModuleStatus.needsManualPath) {
      return ScreenBody(children: [_notFoundCard(context)]);
    }
    return ScreenBody(
      children: [
        ..._notices(context),
        _statusCard(context),
        if (c.semanticPending || c.semanticConsentGranted) ...[
          SectionLabel(t.libSemanticSection),
          _consentCard(context),
        ],
        if (c.changesNotes.isNotEmpty) ...[
          SectionLabel(context.strings.libraryScreen.changesTitle),
          LibraryChangesCard(library: c),
        ],
        AdvancedSection(
          key: ShellKeys.pageAdvanced,
          title: t.advancedTitle,
          summary: t.libAdvancedSummary(reindex: c.hasPendingReindex),
          child: _advanced(context),
        ),
      ],
    );
  }

  // ── הודעות מעל הכרטיס ─────────────────────────────────────────────────────

  List<Widget> _notices(BuildContext context) {
    final c = library;
    final t = context.strings.pages;
    final s = context.strings.libraryScreen;
    final g = context.strings.guide;
    final domain = AppL10n.strings.libraryDomain;
    const warning = IconTile(
      icon: FluentIcons.warning_24_regular,
      tone: IconTileTone.error,
    );
    return [
      // רשומה במראה שהקובץ שלה לא נסע לכונן — בלי זה היא נעלמת לגמרי.
      if (c.unavailableCompanions.isNotEmpty)
        NoticeBanner(
          kind: NoticeKind.warning,
          leading: warning,
          title: t.libMissingFilesTitle,
          body: domain.companionsMissingFromMirror(c.unavailableCompanionNames),
        ),
      // לא הצעה ולא "מעודכן": החיפוש החכם שבכונן אינו מותקן כאן, והסיבה נאמרת.
      if (c.semanticIncompatibility case final incompatible?)
        NoticeBanner(
          kind: NoticeKind.warning,
          leading: warning,
          title: t.libSemanticSection,
          body: '$incompatible',
        ),
      if (c.mirrorLacksCompanions)
        NoticeBanner(
          kind: NoticeKind.warning,
          leading: warning,
          title: t.libMissingFilesTitle,
          body: domain.companionsAbsentFromMirror,
        ),
      if (c.status == LibraryModuleStatus.personalTargetElsewhere)
        NoticeBanner(
          leading: const IconTile(
            icon: FluentIcons.person_24_regular,
            tone: IconTileTone.quiet,
          ),
          title: s.personalOtherMachineTitle,
          body: [
            s.personalOtherMachineSubtitle(
              c.personalFromVersion?.toString() ??
                  context.strings.common.unknownValue,
            ),
            if (readOnly) t.libPersonalReadOnly,
          ].join(' '),
          actions: [
            ActionButton.neutral(
              text: s.personalVersionButton,
              onPressed: _isBusy || readOnly
                  ? null
                  : () => capturePersonalVersion(context, library),
            ),
            ActionButton.ghost(
              text: s.personalOtherMachineSettingsButton,
              onPressed: onGoToSettings,
            ),
          ],
        ),
      if (otzariaIsRunning)
        NoticeBanner(
          kind: NoticeKind.banner,
          leading: const IconTile(child: OtzariaLogo()),
          title: g.otzariaOpenTitle,
          body: g.otzariaOpenBody,
          actions: [CloseOtzariaButton(onClose: onCloseOtzaria)],
        ),
    ];
  }

  // ── כרטיס המצב ────────────────────────────────────────────────────────────

  Widget _chip(BuildContext context) {
    final c = library;
    final t = context.strings.pages;
    final g = context.strings.guide;
    final (kind, label) = switch (c.status) {
      LibraryModuleStatus.idle => (
          StatusKind.unknown,
          context.strings.common.notCheckedYet,
        ),
      LibraryModuleStatus.checking => (StatusKind.working, g.chipChecking),
      LibraryModuleStatus.updating => (StatusKind.working, g.chipUpdating),
      LibraryModuleStatus.error => (StatusKind.error, g.chipAttention),
      LibraryModuleStatus.updateAvailable when c.isFreshInstall => (
          StatusKind.updateAvailable,
          g.chipReadyToInstall,
        ),
      LibraryModuleStatus.updateAvailable when c.companionsOnly => (
          StatusKind.updateAvailable,
          t.libChipCompanions(c.pendingCompanionNames),
        ),
      LibraryModuleStatus.updateAvailable => (
          StatusKind.updateAvailable,
          t.chipUpdateOnDrive,
        ),
      LibraryModuleStatus.needsDownload ||
      LibraryModuleStatus.upToDate when c.hasOnlineUpdate =>
        (
          StatusKind.updateAvailable,
          g.chipNewOnline,
        ),
      LibraryModuleStatus.upToDate => (StatusKind.ok, t.chipUpToDate),
      LibraryModuleStatus.needsDownload => (
          StatusKind.needsAction,
          g.chipNotOnDrive,
        ),
      LibraryModuleStatus.needsManualPath => (
          StatusKind.needsAction,
          t.libNotFoundTitle,
        ),
      LibraryModuleStatus.personalTargetElsewhere => (
          StatusKind.needsAction,
          context.strings.libraryScreen.personalChipElsewhere,
        ),
    };
    return StatusChip(kind: kind, label: label);
  }

  Widget _statusCard(BuildContext context) {
    final c = library;
    final t = context.strings.pages;
    final s = context.strings.libraryScreen;
    final updating = c.status == LibraryModuleStatus.updating;
    final canUpdate = c.status == LibraryModuleStatus.updateAvailable;
    final downloadedAt = c.lastDownloadedAt;
    final local = c.localVersion;
    final target = c.targetVersion;
    final sub = AppTextStyles.rowSub.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final full = c.canRetryWithFullDownload;
    final withApp = !appInstalled && appInstallable == true && c.isFreshInstall;
    final blocked = _isBusy || busy;
    final updateText = withApp
        ? t.libInstallWithAppButton
        : c.isFreshInstall
            ? t.libInstallButton
            : t.libUpdateButton;
    final onUpdate =
        blocked || (!appInstalled && !withApp) ? null : onUpdateHere;

    return StatusCard(
      icon: FluentIcons.library_24_regular,
      title: context.strings.guide.tileLibrary,
      chip: _chip(context),
      values: [
        StatusValue(
          label: t.onThisComputer,
          value: local != null
              ? t.libVersion(local)
              : c.isFreshInstall
                  ? t.libNotInstalled
                  : context.strings.common.unknownValue,
        ),
        StatusValue(
          label: t.onTheDrive,
          value: target != null
              ? t.libVersion(target)
              : c.status == LibraryModuleStatus.needsDownload
                  ? t.nothingYet
                  : context.strings.common.unknownValue,
          meta: target != null && downloadedAt != null
              ? t.downloadedOn(formatDate(downloadedAt))
              : null,
        ),
        if (c.onlineCheckedAt != null && c.onlineLibraryProofError == null)
          StatusValue(
            label: t.onlineAvailable,
            value: switch (c.onlineUpdateVersion) {
              final online? => t.libVersion(online),
              null when c.onlinePendingCompanionNames.isNotEmpty =>
                c.onlinePendingCompanionNames,
              null => t.nothingNewOnline,
            },
          ),
        if (semanticOffer)
          StatusValue(
            label: t.libSemanticSection,
            value: t.onlineAvailable,
          ),
      ],
      extra: [
        if (updating) libraryApplyProgressRow(context, c),
        // "בדוק שוב" שבכרטיס הוא הניסיון החוזר — בלי כפתור שני לאותה פעולה.
        if (c.errorMessage case final error?) InfoErrorRow(message: error),
        // הורדה של מסד שלם במקום קובצי עדכון היא הפרש של שלוש סדרי גודל,
        // ולכן הסיבה נאמרת ולא נשארת בלוג בלבד.
        if (c.updateRouteNote case final note?) Text(note, style: sub),
        if (c.personalUpdateMode) _personalRow(context, sub),
        if (canUpdate && withApp)
          Text(
            key: ShellKeys.libraryInstallNote,
            t.libInstallWithAppNote,
            style: sub,
          )
        else if ((canUpdate || full) && !appInstalled)
          if (appInstallable case final installable?)
            Text(
              key: ShellKeys.libraryInstallNote,
              installable ? t.libUpdateNeedsApp : t.libInstallNeedsApp,
              style: sub,
            ),
        if (full && appInstalled)
          if (_fullMeta(context) case final meta?) Text(meta, style: sub),
        if (busy && !updating)
          Text(key: ShellKeys.pageBusyNote, t.pageBusyNote, style: sub),
      ],
      actions: [
        if (canUpdate)
          full
              ? ActionButton.neutral(text: updateText, onPressed: onUpdate)
              : ActionButton.recommended(
                  key: ShellKeys.statusPrimary,
                  text: updateText,
                  onPressed: onUpdate,
                ),
        // ההתאוששות אחרי כשל עדכון היא הפעולה הראשית של הדף.
        if (full)
          ActionButton.recommended(
            key: ShellKeys.statusPrimary,
            text: s.fullDownloadInsteadButton,
            onPressed: blocked || !appInstalled ? null : onInstallFull,
          ),
      ],
      endActions: [RecheckButton(onPressed: _isBusy ? null : _recheck)],
    );
  }

  Widget _notFoundCard(BuildContext context) {
    final t = context.strings.pages;
    return StatusCard(
      icon: FluentIcons.library_24_regular,
      quiet: true,
      title: t.libNotFoundTitle,
      subtitle: t.libNotFoundBody,
      actions: [
        ActionButton.recommended(
          key: ShellKeys.statusPrimary,
          text: t.libPickFolderButton,
          icon: FluentIcons.folder_open_24_regular,
          onPressed:
              _isBusy ? null : () => pickLibraryInstallDir(context, library),
        ),
        ActionButton.ghost(
          text: context.strings.libraryScreen.pickDbButton,
          onPressed: _isBusy ? null : () => pickLibraryDbFile(context, library),
        ),
      ],
      endActions: [RecheckButton(onPressed: _isBusy ? null : _recheck)],
    );
  }

  /// `null` כשלא ידועים לא הגודל ולא האומדן — אז האומדן נאמר רק בשלב.
  String? _fullMeta(BuildContext context) {
    final size = library.fullDownloadFallbackSize;
    final minutes = library.applyEstimateFor(fullDownload: true);
    if ((size == null || size <= 0) && minutes == null) return null;
    return context.strings.pages.libFullMeta(
      size: size != null && size > 0 ? formatBytes(size) : null,
      lowMinutes: minutes?.low,
      highMinutes: minutes?.high,
    );
  }

  /// "בדוק שוב" מרענן גם את מצב התהליך — האזהרה "אוצריא פתוחה" באותו דף.
  Future<void> _recheck() async {
    await onProcessStateChanged();
    await library.checkForUpdate();
  }

  // ── חיפוש חכם ─────────────────────────────────────────────────────────────

  Widget _consentCard(BuildContext context) {
    final c = library;
    final t = context.strings.pages;
    final cs = Theme.of(context).colorScheme;
    final granted = c.semanticConsentGranted;
    return Container(
      key: ShellKeys.libraryConsent,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(icon: FluentIcons.sparkle_24_regular),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t.libSemanticTitle,
                      style: AppTextStyles.rowValue.copyWith(
                        color: cs.onSurface,
                        fontWeight: AppTextStyles.semibold,
                      ),
                    ),
                    if (granted)
                      StatusChip(
                        kind: StatusKind.ok,
                        label: t.libSemanticActive,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  granted ? t.libSemanticActiveBody : t.libSemanticBody,
                  style: AppTextStyles.body.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (!granted) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionButton.neutral(
                        text: t.libSemanticGrant,
                        onPressed: _isBusy ? null : onGrantSemanticConsent,
                      ),
                      ActionButton.ghost(
                        key: ShellKeys.libraryConsentWhatIsSent,
                        text: t.repWhatIsSent,
                        onPressed: () => showReportsDisclosure(
                          context,
                          reports: false,
                          search: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.libSemanticClosedNote,
                    style: AppTextStyles.meta.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── מתקדם ─────────────────────────────────────────────────────────────────

  Widget _advanced(BuildContext context) {
    final c = library;
    final t = context.strings.pages;
    final s = context.strings.libraryScreen;
    final common = context.strings.common;
    final location = c.dbPath ?? c.installTargetPath;
    final fullSize = c.fullDownloadFallbackSize;
    final downloadedAt = c.lastDownloadedAt;

    return RowsCard(
      children: [
        // בלי מסד מוצג **יעד ההתקנה**: שם ינחתו הספרים, וזו ההזדמנות לשנות.
        AppRow(
          key: ShellKeys.libraryLocation,
          title: t.libLocationTitle,
          subtitle: location == null ? t.libLocationNone : null,
          below: location == null ? null : PathText(location, copyable: true),
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (c.dbPath == null)
                ActionButton.ghost(
                  text: s.pickInstallDirButton,
                  icon: FluentIcons.folder_open_24_regular,
                  onPressed: _isBusy
                      ? null
                      : () => pickLibraryInstallDir(context, library),
                ),
              ActionButton.ghost(
                text: s.pickDbButton,
                icon: FluentIcons.document_24_regular,
                onPressed:
                    _isBusy ? null : () => pickLibraryDbFile(context, library),
              ),
            ],
          ),
        ),
        // האינדקס של אוצריא אינו יודע שהמסד התחלף מתחתיו — הבקשה נמסרת רק
        // כשאוצריא השאירה סימון.
        if (c.hasPendingReindex)
          AppRow(
            key: ShellKeys.libraryReindex,
            title: s.reindexTitle,
            subtitle: s.reindexPendingSubtitle,
            trailing: ActionButton.neutral(
              text: s.reindexButton,
              onPressed: _isBusy ? null : onRequestReindex,
            ),
          ),
        AppRow(
          key: ShellKeys.libraryFull,
          title: t.libFullTitle,
          subtitle: !c.canRetryWithFullDownload
              ? t.libFullUnavailable
              : fullSize != null && fullSize > 0
                  ? t.libFullBody(formatBytes(fullSize))
                  : t.libFullBodyNoSize,
          trailing: ActionButton.neutral(
            text: s.fullDownloadInsteadButton,
            onPressed:
                c.canRetryWithFullDownload && !_isBusy && !busy && appInstalled
                    ? onInstallFull
                    : null,
          ),
        ),
        AppRow(
          key: ShellKeys.librarySource,
          title: t.libSourceTitle,
          subtitle: [
            _mirrorContent(context),
            if (downloadedAt != null)
              '${common.lastDownloaded}: ${formatDate(downloadedAt)}',
          ].join('\n'),
          below: PathText(c.mirrorDir),
          trailing: CopyPathButton(path: c.mirrorDir),
        ),
        if (c.downloadNotes case final notes when notes.isNotEmpty)
          SettingsActionTile.text(
            icon: FluentIcons.warning_24_regular,
            title: s.downloadNoteTitle,
            subtitle: notes.join('\n'),
          ),
      ],
    );
  }

  /// למי הכונן מוכן, בשורה אחת בכרטיס — רק כשמורידים רק את מה שחסר.
  Widget _personalRow(BuildContext context, TextStyle style) {
    final s = context.strings.libraryScreen;
    final machines = library.registeredMachines;
    final floor = machines.isEmpty ? null : '${machines.first.version}';
    final here = machines.any((m) => m.isThisMachine);
    final others = machines.where((m) => !m.isThisMachine).length;
    final text = switch (floor) {
      null => s.personalCardNone,
      final v when here && others > 0 => s.personalCardThisAndOthers(others, v),
      final v when here => s.personalCardThis(v),
      final v => s.personalCardOthers(machines.length, v),
    };
    return Row(
      key: ShellKeys.libraryPersonal,
      children: [
        Icon(FluentIcons.person_16_regular, size: 16, color: style.color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: style)),
        const SizedBox(width: 8),
        TextLink(text: s.personalChange, onTap: onGoToSettings, style: style),
      ],
    );
  }

  String _mirrorContent(BuildContext context) {
    final c = library;
    final s = context.strings.libraryScreen;
    return switch (c.status) {
      LibraryModuleStatus.needsDownload => s.mirrorEmpty,
      LibraryModuleStatus.error when c.localDbUnreadable => s.mirrorNotChecked,
      // כשל בהחלה אינו כשל בקריאת הכונן — הגרסה שבו כבר ידועה.
      LibraryModuleStatus.error when c.targetVersion == null =>
        s.mirrorUnreadable,
      _ => c.targetVersion != null
          ? s.mirrorHasVersion('${c.targetVersion}')
          : s.mirrorPresent,
    };
  }
}
