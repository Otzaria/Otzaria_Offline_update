import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../widgets/widgets_exports.dart';
import 'app_report_dialog.dart';

/// "פרטיות ודיווחים" בהגדרות: מה קורה אחרי סגירה לא צפויה, כניסה לדף
/// הדיווחים (התור וההיסטוריה), ודיווח על בעיה בכלי.
class AppReportsSettingsCard extends StatefulWidget {
  const AppReportsSettingsCard({
    super.key,
    required this.reports,
    this.onOpenReports,
  });

  final AppReportsController reports;
  final VoidCallback? onOpenReports;

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

  @override
  Widget build(BuildContext context) {
    final t = context.strings.appReports;
    const tile = IconTileSize.sm;
    const quiet = IconTileTone.quiet;
    return RowsCard(
      children: [
        AppRow(
          key: const ValueKey('app-reports-crash-mode'),
          leading: const IconTile(
            icon: FluentIcons.shield_checkmark_24_regular,
            size: tile,
            tone: quiet,
          ),
          title: t.crashModeTitle,
          subtitle: t.crashModeSubtitle,
          trailing: AppSegmentedControl<AppCrashReportMode>(
            options: [
              SegmentOption(
                  value: AppCrashReportMode.ask, label: t.crashModeAsk),
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
        ),
        if (widget.onOpenReports case final open?)
          AppRow(
            key: const ValueKey('app-reports-manage'),
            leading: const IconTile(
              icon: FluentIcons.bug_24_regular,
              size: tile,
              tone: quiet,
            ),
            title: t.manageTileTitle,
            subtitle: t.manageTileSubtitle(
              _reports.pendingCount,
              _reports.sentTotal,
            ),
            onTap: open,
          ),
        AppRow(
          key: const ValueKey('app-reports-problem'),
          leading: const IconTile(
            icon: FluentIcons.person_feedback_24_regular,
            size: tile,
            tone: quiet,
          ),
          title: context.strings.pages.repProblemTitle,
          onTap: () => unawaited(_openForm()),
        ),
      ],
    );
  }
}
