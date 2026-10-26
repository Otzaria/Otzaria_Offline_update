import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/app_reports_controller.dart';
import '../../services/app_logger.dart';
import '../../services/coalescing_loader.dart';
import '../../services/file_reveal.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'app_report_result_snack.dart';

/// הדיווחים של הכלי על עצמו: התור וההיסטוריה — פורט של לשונית "התוכנה"
/// ב-`ReportsManagementDialog` של אוצריא, בלי סקריפט השליחה ובלי עריכה.
class AppReportsPanel extends StatefulWidget {
  const AppReportsPanel({
    super.key,
    required this.reports,
    this.openUrl = FileReveal.openGithubUrl,
    this.connection,
    this.checkConnectionButton,
  });

  final AppReportsController reports;
  final Future<bool> Function(String url) openUrl;

  /// שליחה רק כשידוע שיש חיבור — כמו בכרטיס הראשי של הדף.
  final bool? connection;

  /// "בדוק חיבור" של הדף, כשהחיבור עוד לא נבדק.
  final Widget? checkConnectionButton;

  @override
  State<AppReportsPanel> createState() => _AppReportsPanelState();
}

class _AppReportsPanelState extends State<AppReportsPanel> {
  AppReportService get _service => widget.reports.service;

  List<AppReport>? _pending;
  List<AppReport> _sent = const [];
  int _sentTotal = 0;
  bool _isFlushing = false;
  String? _sendingReportId;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // שליחה ברקע (כל חמש דקות) מעדכנת גם את הדף הפתוח.
    _changes = _service.changes.listen((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  /// אירועי `changes` חופפים מתכנסים לטעינה חוזרת אחת (ראו
  /// [CoalescingLoader]); מי שממתין מקבל את הטעינה האחרונה.
  late final CoalescingLoader _loader =
      CoalescingLoader(_loadOnce, isActive: () => mounted);

  Future<void> _load() => _loader.run();

  Future<void> _loadOnce() async {
    try {
      final (pending, sent, total) = await (
        _service.getPendingReports(),
        _service.getSentReports(),
        _service.getSentReportsTotal(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _sent = sent;
        _sentTotal = total;
      });
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('קריאת הדיווחים נכשלה', error, stack);
    }
  }

  /// אחרי כל שינוי: הדף, והמונים שבקונטרולר.
  Future<void> _reload() async {
    await _load();
    await widget.reports.refresh();
  }

  String _summaryLine(AppReportsStrings t, AppReport report) {
    final local = (report.sentAt ?? report.createdAt).toLocal();
    return [
      appReportTypeLabel(t, report.type),
      '${local.day}.${local.month}.${local.year}',
      if (report.issueNumber != null) '#${report.issueNumber}',
      if (report.merged) t.mergedLabel,
    ].join(' · ');
  }

  Future<void> _showDetails(AppReport report, {required bool sent}) async {
    final t = context.strings.appReports;
    final buffer = StringBuffer()
      ..writeln(report.title)
      ..writeln(_summaryLine(t, report))
      ..writeln();
    if (report.description.trim().isNotEmpty) {
      buffer.writeln(report.description.trim());
    }
    if (report.stepsToReproduce.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(t.stepsHeading)
        ..writeln(report.stepsToReproduce.trim());
    }
    final signature = report.signature;
    if (signature != null && signature.exceptionType.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(signature.exceptionType)
        ..writeln(signature.frames.join('\n'));
    }
    await showSingleActionDialog(
      context: context,
      title: sent ? t.detailsSentTitle : t.detailsPendingTitle,
      content: buffer.toString().trimRight(),
      confirmText: context.strings.common.close,
    );
  }

  Future<void> _flush() async {
    final t = context.strings.appReports;
    setState(() => _isFlushing = true);
    try {
      // מצטרף לסבב שרץ ברקע אם יש, ומקבל את תוצאתו. תקרת הסבב אינה כשל.
      final outcome = await _service.flush(
        maxRequests: AppReportService.maxManualFlushPerRun,
      );
      final remaining = await _service.getPendingReportsCount();
      if (outcome.stoppedOnTransientFailure) {
        UiSnack.showError(t.flushFailedSnack(remaining));
      } else if (outcome.failed > 0 && outcome.sent == 0) {
        UiSnack.showError(t.flushErrorSnack(outcome.failed));
      } else if (outcome.failed > 0) {
        // חלק נשלחו וחלק נכשלו מקומית: אסור שההצלחה תסתיר את הכשל.
        UiSnack.showError(t.flushPartialSnack(outcome.sent, outcome.failed));
      } else if (outcome.dropped > 0) {
        UiSnack.show(t.flushDroppedSnack(outcome.sent, outcome.dropped));
      } else if (outcome.capped && remaining > 0) {
        UiSnack.showSuccess(t.flushRemainingSnack(outcome.sent, remaining));
      } else {
        UiSnack.showSuccess(t.flushSentSnack(outcome.sent));
      }
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('שליחת התור נכשלה', error, stack);
      UiSnack.showError(AppL10n.strings.appReports.sendFailedSnack);
    } finally {
      if (mounted) setState(() => _isFlushing = false);
      await _reload();
    }
  }

  Future<void> _sendPending(AppReport report) async {
    setState(() => _sendingReportId = report.reportId);
    try {
      showAppReportResultSnack(await _service.submitPendingReport(report));
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('שליחת דיווח מהתור נכשלה', error, stack);
      UiSnack.showError(AppL10n.strings.appReports.sendFailedSnack);
    } finally {
      if (mounted) setState(() => _sendingReportId = null);
      await _reload();
    }
  }

  Future<void> _deletePending(AppReport report) async {
    await _service.deletePendingReport(report.reportId);
    UiSnack.show(AppL10n.strings.appReports.removedFromQueueSnack);
    await _reload();
  }

  Future<void> _deleteSent(AppReport report) async {
    await _service.deleteSentReport(report.reportId);
    UiSnack.show(AppL10n.strings.appReports.deletedFromHistorySnack);
    await _reload();
  }

  Future<void> _clearPending() async {
    final t = context.strings.appReports;
    final approved = await showWarningDialog(
      context: context,
      title: t.clearPendingDialogTitle,
      content: t.clearPendingDialogContent,
      confirmText: t.clearPendingButton,
    );
    if (!approved) return;
    await _service.clearPendingReports();
    UiSnack.show(t.pendingClearedSnack);
    await _reload();
  }

  Future<void> _clearSent() async {
    final t = context.strings.appReports;
    final approved = await showWarningDialog(
      context: context,
      title: t.clearSentDialogTitle,
      content: t.clearSentDialogContent,
      confirmText: t.clearSentButton,
    );
    if (!approved) return;
    await _service.clearSentReports();
    UiSnack.show(t.historyClearedSnack);
    await _reload();
  }

  Future<void> _openIssue(String url) async {
    if (!await widget.openUrl(url)) {
      UiSnack.showError(AppL10n.strings.appReports.cannotOpenIssueSnack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.appReports;
    final pages = context.strings.pages;
    final cs = Theme.of(context).colorScheme;
    final pending = _pending;
    final meta = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    final canSend = widget.connection == true;

    if (pending == null) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceMD),
        child: AppProgressBar(thin: true),
      );
    }
    // שתי רשימות ריקות — שורה אחת, ולא שני כרטיסים ריקים.
    if (pending.isEmpty && _sent.isEmpty && _sentTotal == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionLabel(pages.repOwnTitle),
          SectionEmptyNote(pages.repOwnEmpty),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending.isNotEmpty) ...[
          SectionLabel(
            pages.repOwnPending(pending.length),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (!canSend && widget.checkConnectionButton != null)
                  widget.checkConnectionButton!,
                if (canSend)
                  ActionButton.ghost(
                    key: const ValueKey('app-reports-flush'),
                    text: t.sendNowButton,
                    icon: FluentIcons.send_24_regular,
                    size: ActionButtonSize.sm,
                    isLoading: _isFlushing,
                    onPressed: _isFlushing ? null : _flush,
                  ),
                ActionButton.warning(
                  key: const ValueKey('app-reports-clear-pending'),
                  text: t.clearPendingButton,
                  size: ActionButtonSize.sm,
                  onPressed: _isFlushing ? null : _clearPending,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              t.manageDialogIntro,
              style: meta,
            ),
          ),
          RowsCard(
            children: [
              for (final report in pending)
                AppRow(
                  key: ValueKey('app-report-pending-${report.reportId}'),
                  leading: const IconTile(
                    icon: FluentIcons.bug_24_regular,
                    size: IconTileSize.sm,
                    tone: IconTileTone.quiet,
                  ),
                  title: report.title,
                  subtitle: _summaryLine(t, report),
                  trailing: Wrap(
                    spacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionButton.ghost(
                        text: t.detailsButton,
                        size: ActionButtonSize.sm,
                        onPressed: () => _showDetails(report, sent: false),
                      ),
                      if (canSend)
                        AppIconButton(
                          icon: FluentIcons.send_24_regular,
                          tooltip: t.sendOneButton,
                          small: true,
                          onPressed: _sendingReportId != null || _isFlushing
                              ? null
                              : () => _sendPending(report),
                        ),
                      AppIconButton(
                        icon: FluentIcons.delete_24_regular,
                        tooltip: t.deleteButton,
                        small: true,
                        danger: true,
                        onPressed: _sendingReportId == report.reportId
                            ? null
                            : () => _deletePending(report),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (_sent.isNotEmpty || _sentTotal > 0) ...[
          SectionLabel(
            _sentTotal == 0
                ? t.sentSectionTitle
                : '${t.sentSectionTitle} · ${t.sentSummary(_sent.length, _sentTotal)}',
            trailing: ActionButton.ghost(
              key: const ValueKey('app-reports-clear-sent'),
              text: t.clearSentButton,
              size: ActionButtonSize.sm,
              onPressed: _sent.isEmpty ? null : _clearSent,
            ),
          ),
          if (_sent.isEmpty)
            SectionEmptyNote(pages.repOwnEmpty)
          else
            RowsCard(
              children: [
                for (final report in _sent)
                  AppRow(
                    key: ValueKey('app-report-sent-${report.reportId}'),
                    leading: const IconTile(
                      icon: FluentIcons.history_24_regular,
                      size: IconTileSize.sm,
                      tone: IconTileTone.quiet,
                    ),
                    title: report.title,
                    subtitle: _summaryLine(t, report),
                    trailing: Wrap(
                      spacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ActionButton.ghost(
                          text: t.detailsButton,
                          size: ActionButtonSize.sm,
                          onPressed: () => _showDetails(report, sent: true),
                        ),
                        if (report.issueUrl case final url? when url.isNotEmpty)
                          ActionButton.ghost(
                            key: ValueKey(
                              'app-report-open-issue-${report.reportId}',
                            ),
                            text: t.openIssueButton(report.issueNumber),
                            icon: FluentIcons.open_24_regular,
                            size: ActionButtonSize.sm,
                            onPressed: () => _openIssue(url),
                          ),
                        AppIconButton(
                          icon: FluentIcons.delete_24_regular,
                          tooltip: t.deleteButton,
                          small: true,
                          danger: true,
                          onPressed: () => _deleteSent(report),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}
