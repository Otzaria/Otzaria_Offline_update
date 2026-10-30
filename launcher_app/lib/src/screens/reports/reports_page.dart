import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../controllers/error_reports_controller.dart';
import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/widgets_exports.dart';
import '../app_report/app_report_dialog.dart';
import '../app_report/app_reports_panel.dart';

/// דף הדיווחים: הדיווחים של אוצריא (איסוף לכונן ושליחה מהמחשב המחובר),
/// הדיווחים של הכלי על עצמו (תור והיסטוריה), ודיווח על בעיה בכלי.
class ReportsPage extends StatelessWidget {
  const ReportsPage({
    super.key,
    required this.errorReports,
    required this.connection,
    required this.isUploadingAll,
    required this.busy,
    bool? uploadBusy,
    required this.reportsToCollect,
    required this.onCollect,
    required this.onUpload,
    this.onStop,
    this.readOnly = false,
    this.driveFull = false,
    this.legacyNotice = false,
    this.onDismissLegacy,
    this.appReports,
    this.onCheckConnection,
    this.checkingConnection = false,
  }) : uploadBusy = uploadBusy ?? busy;

  final ErrorReportsController? errorReports;

  /// `null` — עוד לא נבדק חיבור; ראו `onlineState`.
  final bool? connection;
  final bool isUploadingAll;

  /// התקנה רצה כאן — אין איסוף עכשיו.
  final bool busy;

  /// השליחה קוראת רק את תיבת היוצאים, ולכן הורדה אינה חוסמת אותה.
  final bool uploadBusy;

  /// דיווחי תקלות שממתינים באוצריא, ורשומות החיפוש החכם שלצידם.
  final int reportsToCollect;
  final VoidCallback onCollect;
  final Future<void> Function()? onUpload;
  final VoidCallback? onStop;

  /// כונן מוגן או מלא: אין איסוף ואין שליחה (שליחה מוחקת מהכונן).
  final bool readOnly;
  final bool driveFull;

  /// דיווחים ישנים (Hive) שאוצריא כבר אינה מעבירה.
  final bool legacyNotice;
  final VoidCallback? onDismissLegacy;

  /// הדיווחים של הכלי על עצמו — `null` בבדיקות.
  final AppReportsController? appReports;

  /// "בדוק חיבור" כש-[connection] עוד `null` — בלעדיו אין דרך לשלוח מכאן.
  final VoidCallback? onCheckConnection;
  final bool checkingConnection;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.pages;
    final listenable = Listenable.merge([
      if (errorReports != null) errorReports!,
    ]);
    final reports = appReports;

    return ScreenBody(
      title: context.strings.guide.tileReports,
      description: t.repDescription,
      children: [
        if (legacyNotice) _legacy(context),
        ListenableBuilder(
          listenable: listenable,
          builder: (context, _) => _statusCard(context),
        ),
        if (reports != null)
          AppReportsPanel(
            reports: reports,
            connection: connection,
            checkConnectionButton: _checkConnectionButton(context),
          ),
        if (reports != null) ...[
          SectionLabel(t.repProblemSection),
          RowsCard(
            children: [
              AppRow(
                key: ShellKeys.reportsProblem,
                leading: const IconTile(
                  icon: FluentIcons.person_feedback_24_regular,
                ),
                title: t.repProblemTitle,
                subtitle: t.repProblemBody,
                onTap: () => _openForm(context, reports),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget? _checkConnectionButton(BuildContext context) {
    if (connection != null || onCheckConnection == null) return null;
    return ActionButton.ghost(
      key: ShellKeys.reportsCheckConnection,
      text: context.strings.pages.repCheckConnectionButton,
      icon: FluentIcons.globe_24_regular,
      size: ActionButtonSize.sm,
      isLoading: checkingConnection,
      onPressed: checkingConnection ? null : onCheckConnection,
    );
  }

  Future<void> _openForm(
    BuildContext context,
    AppReportsController reports,
  ) async {
    await showAppReportDialog(context, reports: reports);
    await reports.refresh();
  }

  Widget _legacy(BuildContext context) {
    final t = context.strings.errorReports;
    return NoticeBanner(
      key: ShellKeys.reportsLegacy,
      leading: const IconTile(
        icon: FluentIcons.history_24_regular,
        tone: IconTileTone.quiet,
      ),
      title: t.legacyReportsDialogTitle,
      body: t.legacyReportsDialogContent,
      actions: [
        ActionButton.ghost(
          text: t.introDialogConfirm,
          size: ActionButtonSize.sm,
          onPressed: onDismissLegacy,
        ),
      ],
    );
  }

  Widget _statusCard(BuildContext context) {
    final t = context.strings.pages;
    final g = context.strings.guide;
    final e = context.strings.errorReports;
    final cs = Theme.of(context).colorScheme;
    final sub = AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant);
    final reports = errorReports;
    final waitingReports = reports?.outboxCount ?? 0;
    final waiting = waitingReports;
    final collecting = reportsToCollect;
    final uploading = isUploadingAll || (reports?.isUploading ?? false);

    if (uploading) {
      final p = reports?.progress;
      final wait = p?.waitRemaining;
      return StatusCard(
        icon: FluentIcons.send_24_regular,
        title: t.repSendingTitle,
        extra: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wait != null
                    ? e.uploadWaitingStage(
                        (wait.inMilliseconds / 1000).ceil(),
                      )
                    : e.uploadingStage(p?.done ?? 0, p?.total ?? 0),
                style: sub,
              ),
              const SizedBox(height: 8),
              AppProgressBar(
                thin: true,
                value: p == null || p.total == 0 ? null : p.done / p.total,
              ),
            ],
          ),
        ],
        actions: [
          ActionButton.neutral(
            key: ShellKeys.reportsStop,
            text: e.uploadStopButton,
            onPressed: () {
              onStop?.call();
              if (reports?.isUploading ?? false) reports!.stop();
            },
          ),
        ],
      );
    }

    if (readOnly) {
      return StatusCard(
        icon: FluentIcons.arrow_upload_24_regular,
        title: waiting > 0
            ? t.repStoredTitle(waiting)
            : collecting > 0
                ? g.reportsCollectTitle(
                    reports: reportsToCollect,
                    searchRecords: 0,
                  )
                : t.repNothingTitle,
        // בלי גילוי אין כפתור איסוף — גם לא מושבת.
        subtitle: g.reportsLockedNote(driveFull: driveFull),
      );
    }

    final sendButton = ActionButton.recommended(
      key: ShellKeys.reportsSend,
      text: t.repSendButton,
      icon: FluentIcons.send_24_regular,
      onPressed: uploadBusy || onUpload == null ? null : () => onUpload!(),
    );
    final busyNote = busy || uploadBusy
        ? Text(key: ShellKeys.pageBusyNote, t.pageBusyNote, style: sub)
        : null;

    final checkButton = _checkConnectionButton(context);
    if (collecting > 0) {
      final canSend = waiting > 0 && connection == true;
      return StatusCard(
        icon: FluentIcons.arrow_upload_24_regular,
        title: g.reportsCollectTitle(
          reports: reportsToCollect,
          searchRecords: 0,
        ),
        subtitle: [
          if (waiting > 0) t.repAlsoStored(waiting),
          g.reportsCollectBody,
        ].join(' '),
        extra: [
          // הגילוי הוא ההסכמה: אין דו-שיח אחרי הלחיצה.
          KeyedSubtree(
            key: ShellKeys.reportsDisclosure,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reportsToCollect > 0)
                  NewsBullet(g.reportsDisclosureReports, style: sub),
                const SizedBox(height: 6),
                Text(g.reportsDisclosureStorage, style: sub),
              ],
            ),
          ),
          if (busyNote != null) busyNote,
        ],
        actions: [
          ActionButton.recommended(
            key: ShellKeys.reportsCollect,
            text: g.reportsCollectButton,
            icon: FluentIcons.arrow_upload_24_regular,
            onPressed: busy ? null : onCollect,
          ),
          // מה שכבר בכונן נשלח גם בלי לאסוף קודם.
          if (waiting > 0 && !canSend && checkButton != null) checkButton,
          if (canSend)
            ActionButton.neutral(
              key: ShellKeys.reportsSend,
              text: t.repSendStoredButton(waiting),
              icon: FluentIcons.send_24_regular,
              onPressed:
                  uploadBusy || onUpload == null ? null : () => onUpload!(),
            ),
        ],
      );
    }

    if (waiting > 0 && connection == true) {
      return StatusCard(
        icon: FluentIcons.send_24_regular,
        title: t.repWaitingTitle(waiting),
        subtitle: t.repWaitingBody(withSearch: false),
        extra: [if (uploadBusy && busyNote != null) busyNote],
        actions: [
          sendButton,
          ActionButton.ghost(
            text: t.repWhatIsSent,
            onPressed: () => showReportsDisclosure(
              context,
              reports: waitingReports > 0,
              search: false,
            ),
          ),
        ],
      );
    }

    if (waiting > 0) {
      return StatusCard(
        icon: FluentIcons.arrow_upload_24_regular,
        title: t.repStoredTitle(waiting),
        subtitle: connection == null ? t.repUncheckedBody : t.repStoredBody,
        actions: [
          checkButton ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.info_16_regular,
                      size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(t.repOnlyOnline, style: sub),
                ],
              ),
        ],
      );
    }

    return StatusCard(
      icon: FluentIcons.checkmark_24_regular,
      quiet: true,
      title: t.repNothingTitle,
      subtitle: g.reportsNothing,
    );
  }
}

/// "מה נשלח?" — הגילוי המלא, גם מדף הדיווחים וגם לפני ההסכמה לחיפוש החכם.
Future<void> showReportsDisclosure(
  BuildContext context, {
  required bool reports,
  required bool search,
}) {
  final g = context.strings.guide;
  return showSingleActionDialog(
    context: context,
    title: context.strings.pages.repWhatIsSent,
    content: [
      if (reports) g.reportsDisclosureReports,
      if (search) g.reportsDisclosureSearch,
      g.reportsDisclosureStorage,
    ].join('\n\n'),
    confirmText: context.strings.common.close,
  );
}
