import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../widgets/widgets_exports.dart';
import 'app_report_dialog.dart';
import 'reports_management_dialog.dart';

/// כרטיס "דיווח על תקלות" בהגדרות: פתיחת הטופס, מצב הדיווח אחרי קריסה,
/// וסיכום התור וההיסטוריה עם הכניסה לניהולם — כמו `ReportsCard` +
/// `AppReportsPanel` של אוצריא, בכרטיס אחד.
class AppReportsSettingsCard extends StatefulWidget {
  const AppReportsSettingsCard({super.key, required this.reports});

  final AppReportsController reports;

  @override
  State<AppReportsSettingsCard> createState() => _AppReportsSettingsCardState();
}

class _AppReportsSettingsCardState extends State<AppReportsSettingsCard> {
  AppReportsController get _reports => widget.reports;

  @override
  void initState() {
    super.initState();
    _reports.addListener(_onChanged);
    _reports.settings.addListener(_onChanged);
  }

  @override
  void dispose() {
    _reports.removeListener(_onChanged);
    _reports.settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openForm() async {
    await showAppReportDialog(context, reports: _reports);
    await _reports.refresh();
  }

  Future<void> _openManagement() async {
    await showReportsManagementDialog(context, reports: _reports);
    await _reports.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.appReports;
    return SettingsCard(
      title: t.cardTitle,
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.bug_24_regular,
          title: t.reportTileTitle,
          subtitle: t.reportTileSubtitle,
          actions: [
            ActionButton.recommended(
              key: const ValueKey('app-reports-open-form'),
              text: t.openFormButton,
              onPressed: _openForm,
            ),
          ],
        ),
        SettingsActionTile.segmentedTile<AppCrashReportMode>(
          key: const ValueKey('app-reports-crash-mode'),
          icon: FluentIcons.warning_24_regular,
          title: t.crashModeTitle,
          subtitle: t.crashModeSubtitle,
          options: [
            SegmentOption(value: AppCrashReportMode.ask, label: t.crashModeAsk),
            SegmentOption(
              value: AppCrashReportMode.always,
              label: t.crashModeAlways,
            ),
            SegmentOption(
              value: AppCrashReportMode.never,
              label: t.crashModeNever,
            ),
          ],
          currentValue: _reports.crashMode,
          onChanged: _reports.setCrashMode,
        ),
        SettingsActionTile.text(
          icon: FluentIcons.task_list_ltr_24_regular,
          title: t.manageTileTitle,
          subtitle: t.manageTileSubtitle(
            _reports.pendingCount,
            _reports.sentTotal,
          ),
          actions: [
            ActionButton.neutral(
              key: const ValueKey('app-reports-manage'),
              text: t.manageButton,
              onPressed: _openManagement,
            ),
          ],
        ),
      ],
    );
  }
}
