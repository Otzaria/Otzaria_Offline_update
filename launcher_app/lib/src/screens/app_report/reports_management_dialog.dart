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

/// פותח את חלון "הדיווחים שלך": התור וההיסטוריה.
Future<void> showReportsManagementDialog(
  BuildContext context, {
  required AppReportsController reports,
  Future<bool> Function(String url) openUrl = FileReveal.openGithubUrl,
}) {
  // `Dialog` גולמי, כמו ניהול התוכנות: אין עוזר `show*Dialog` שמארח רשימות.
  return showDialog<void>(
    context: context,
    builder: (_) => ReportsManagementDialog(reports: reports, openUrl: openUrl),
  );
}

/// ניהול התור וההיסטוריה — פורט של לשונית "התוכנה" ב-`ReportsManagementDialog`
/// של אוצריא, בלי סקריפט השליחה, "סמן כנשלח" ועריכת דיווח שמור.
class ReportsManagementDialog extends StatefulWidget {
  const ReportsManagementDialog({
    super.key,
    required this.reports,
    this.openUrl = FileReveal.openGithubUrl,
  });

  final AppReportsController reports;
  final Future<bool> Function(String url) openUrl;

  @override
  State<ReportsManagementDialog> createState() =>
      _ReportsManagementDialogState();
}

class _ReportsManagementDialogState extends State<ReportsManagementDialog> {
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
    // שליחה ברקע (כל חמש דקות) מעדכנת גם את החלון הפתוח.
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
      await _load();
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
      await _load();
    }
  }

  Future<void> _deletePending(AppReport report) async {
    await _service.deletePendingReport(report.reportId);
    UiSnack.show(AppL10n.strings.appReports.removedFromQueueSnack);
    await _load();
  }

  Future<void> _deleteSent(AppReport report) async {
    await _service.deleteSentReport(report.reportId);
    UiSnack.show(AppL10n.strings.appReports.deletedFromHistorySnack);
    await _load();
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
    await _load();
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
    await _load();
  }

  Future<void> _openIssue(String url) async {
    if (!await widget.openUrl(url)) {
      UiSnack.showError(AppL10n.strings.appReports.cannotOpenIssueSnack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.appReports;
    final size = MediaQuery.sizeOf(context);
    final pending = _pending;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size.width < 760 ? size.width * 0.95 : 720,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppTokens.spaceLG,
                AppTokens.spaceMD,
                AppTokens.spaceSM,
                AppTokens.spaceSM,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.manageDialogTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  SecondaryIconButton(
                    tooltip: context.strings.common.close,
                    icon: FluentIcons.dismiss_24_regular,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: pending == null
                  ? const Padding(
                      padding: EdgeInsets.all(AppTokens.spaceXL),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.spaceLG,
                        0,
                        AppTokens.spaceLG,
                        AppTokens.spaceLG,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t.manageDialogIntro,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppTokens.spaceMD),
                          _pendingSection(context, pending),
                          const SizedBox(height: AppTokens.spaceLG),
                          _sentSection(context),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingSection(BuildContext context, List<AppReport> pending) {
    final t = context.strings.appReports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          t.pendingSectionTitle,
          pending.isEmpty ? t.pendingEmpty : t.pendingCount(pending.length),
        ),
        if (pending.isNotEmpty) ...[
          CardActionsRow(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
            actions: [
              ActionButton.recommended(
                key: const ValueKey('app-reports-flush'),
                text: t.sendNowButton,
                icon: FluentIcons.arrow_sync_24_regular,
                isLoading: _isFlushing,
                onPressed: _isFlushing ? null : _flush,
              ),
              ActionButton.neutral(
                key: const ValueKey('app-reports-clear-pending'),
                text: t.clearPendingButton,
                icon: FluentIcons.delete_24_regular,
                onPressed: _isFlushing ? null : _clearPending,
              ),
            ],
          ),
          AppCard.section(
            children: [
              for (final report in pending)
                SettingsActionTile.text(
                  key: ValueKey('app-report-pending-${report.reportId}'),
                  icon: FluentIcons.bug_24_regular,
                  title: report.title,
                  subtitle: _summaryLine(t, report),
                  actions: [
                    ActionButton.ghost(
                      text: t.detailsButton,
                      onPressed: () => _showDetails(report, sent: false),
                    ),
                    ActionButton.neutral(
                      text: t.sendOneButton,
                      icon: FluentIcons.send_24_regular,
                      isLoading: _sendingReportId == report.reportId,
                      onPressed: _sendingReportId != null || _isFlushing
                          ? null
                          : () => _sendPending(report),
                    ),
                    ActionButton.warning(
                      text: t.deleteButton,
                      onPressed: _sendingReportId == report.reportId
                          ? null
                          : () => _deletePending(report),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sentSection(BuildContext context) {
    final t = context.strings.appReports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          context,
          t.sentSectionTitle,
          _sentTotal == 0
              ? t.sentEmpty
              : t.sentSummary(_sent.length, _sentTotal),
        ),
        if (_sent.isNotEmpty || _sentTotal > 0)
          CardActionsRow(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
            actions: [
              ActionButton.neutral(
                key: const ValueKey('app-reports-clear-sent'),
                text: t.clearSentButton,
                icon: FluentIcons.delete_24_regular,
                onPressed: _clearSent,
              ),
            ],
          ),
        if (_sent.isNotEmpty)
          AppCard.section(
            children: [
              for (final report in _sent)
                SettingsActionTile.text(
                  key: ValueKey('app-report-sent-${report.reportId}'),
                  icon: FluentIcons.checkmark_24_regular,
                  title: report.title,
                  subtitle: _summaryLine(t, report),
                  actions: [
                    ActionButton.ghost(
                      text: t.detailsButton,
                      onPressed: () => _showDetails(report, sent: true),
                    ),
                    if (report.issueUrl case final url? when url.isNotEmpty)
                      ActionButton.neutral(
                        key: ValueKey(
                            'app-report-open-issue-${report.reportId}'),
                        text: t.openIssueButton(report.issueNumber),
                        icon: FluentIcons.open_24_regular,
                        onPressed: () => _openIssue(url),
                      ),
                    ActionButton.warning(
                      text: t.deleteButton,
                      onPressed: () => _deleteSent(report),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
