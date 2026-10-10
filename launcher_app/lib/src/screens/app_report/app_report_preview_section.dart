import 'dart:convert';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'app_report_form.dart';

/// תצוגה מקדימה של מה שיישלח: שדות הדיווח עצמו, מפת האבחון וקטע היומן,
/// כל צרופה עם מתג להחרגה. הטקסטים טכניים ולכן מוצגים LTR.
class AppReportPreviewSection extends StatefulWidget {
  const AppReportPreviewSection({super.key, required this.form});

  final AppReportForm form;

  /// מפה כטקסט מסודר לתצוגה.
  static String prettyJson(Map<String, dynamic> json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (error) {
      return '$error';
    }
  }

  /// גוף הבקשה בלי הצרופות — הן מוצגות בנפרד, והתמונות כבר נראות למעלה.
  static Map<String, dynamic> reportFields(AppReport report) => report.copyWith(
      diagnostics: null, errorLog: null, images: const []).toApiPayload();

  @override
  State<AppReportPreviewSection> createState() =>
      _AppReportPreviewSectionState();
}

class _AppReportPreviewSectionState extends State<AppReportPreviewSection> {
  bool _isExpanded = false;

  /// הפורמט של האבחון נעשה פעם אחת לאובייקט, לא בכל הקלדה בטופס.
  Map<String, dynamic>? _prettySource;
  String _prettyText = '';

  String _diagnosticsText(Map<String, dynamic> diagnostics) {
    if (!identical(_prettySource, diagnostics)) {
      _prettySource = diagnostics;
      _prettyText = AppReportPreviewSection.prettyJson(diagnostics);
    }
    return _prettyText;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.appReports;
    final form = widget.form;
    final enabled = !form.isSending;
    final diagnostics = form.diagnostics;
    final errorLog = form.errorLog;
    final hasLog = errorLog != null && errorLog.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsActionTile.switchTile(
          key: const ValueKey('app-report-include-diagnostics'),
          icon: FluentIcons.info_24_regular,
          title: t.includeDiagnostics,
          subtitle: diagnostics == null ? t.diagnosticsUnavailable : null,
          value: form.includeDiagnostics && diagnostics != null,
          enabled: enabled && diagnostics != null,
          onChanged: (v) => form.update(includeDiagnostics: v),
        ),
        SettingsActionTile.switchTile(
          key: const ValueKey('app-report-include-log'),
          icon: FluentIcons.document_bullet_list_24_regular,
          title: t.includeLog,
          subtitle: hasLog ? null : t.logEmpty,
          value: form.includeErrorLog && hasLog,
          enabled: enabled && hasLog,
          onChanged: (v) => form.update(includeErrorLog: v),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.ghost(
            key: const ValueKey('app-report-toggle-preview'),
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
            icon: _isExpanded
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.chevron_down_24_regular,
            text: _isExpanded ? t.hidePreviewButton : t.showPreviewButton,
          ),
        ),
        if (_isExpanded) ...[
          _PreviewBox(
            key: const ValueKey('app-report-preview-report'),
            title: 'report.json',
            content: AppReportPreviewSection.prettyJson(
              AppReportPreviewSection.reportFields(form.buildReport()),
            ),
          ),
          if (diagnostics != null && form.includeDiagnostics)
            _PreviewBox(
              title: 'diagnostics.json',
              content: _diagnosticsText(diagnostics),
            ),
          if (hasLog && form.includeErrorLog)
            _PreviewBox(title: 'launcher.log', content: errorLog),
        ],
        const SizedBox(height: AppTokens.spaceSM),
        Container(
          padding: const EdgeInsets.all(AppTokens.spaceSM),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.shield_task_24_regular,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text(
                  t.privacyNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({super.key, required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: AppTokens.spaceXS),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(AppTokens.spaceSM),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
