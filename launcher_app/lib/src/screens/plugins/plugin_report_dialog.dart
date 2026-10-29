import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/error_reports_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';

Future<void> showPluginReportDialog(
  BuildContext context, {
  required StorePlugin plugin,
  required ErrorReportsController reports,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => PluginReportDialog(plugin: plugin, reports: reports),
    );

class PluginReportDialog extends StatefulWidget {
  const PluginReportDialog(
      {super.key, required this.plugin, required this.reports});

  final StorePlugin plugin;
  final ErrorReportsController reports;

  @override
  State<PluginReportDialog> createState() => _PluginReportDialogState();
}

class _PluginReportDialogState extends State<PluginReportDialog> {
  final _details = TextEditingController();
  final _email = TextEditingController();
  String _type = 'bug';
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = context.strings.plugins;
    if (_details.text.trim().isEmpty) {
      setState(() => _error = t.reportEmpty);
      return;
    }
    if (_email.text.trim().isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = context.strings.appReports.emailInvalid);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final p = widget.plugin;
      final id = await widget.reports.queuePluginReport(
        pluginUid: p.pluginUid ?? p.id,
        pluginName: p.name,
        pluginVersion: p.version,
        reportType: _type,
        details: _details.text,
        reporterEmail: _email.text,
      );
      final result =
          await widget.reports.uploadAutomaticPluginReports(reportId: id);
      if (!mounted) return;
      if (result != null && result.rejected > 0) {
        setState(() => _error = t.reportRejected);
        return;
      }
      UiSnack.show(result != null && result.remaining == 0 && result.sent > 0
          ? t.reportSent
          : t.reportSaved);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = t.reportFailed);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;
    return PopScope(
      canPop: !_sending,
      child: AppDialog.custom(
        title: t.reportTitle,
        width: AppTokens.dialogWideWidth,
        customContent: Flexible(
            child: SingleChildScrollView(
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.reportSubtitle(widget.plugin.name, widget.plugin.version)),
            const SizedBox(height: AppTokens.spaceLG),
            Text(t.reportType, style: AppTextStyles.rowTitle),
            const SizedBox(height: AppTokens.spaceSM),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: [
                for (final (value, label, icon) in [
                  ('bug', t.reportBug, FluentIcons.bug_24_regular),
                  ('crash', t.reportCrash, FluentIcons.error_circle_24_regular),
                  ('content', t.reportContent, FluentIcons.document_24_regular),
                  (
                    'other',
                    t.reportOther,
                    FluentIcons.question_circle_24_regular
                  ),
                ])
                  StoreFilterChip(
                      label: label,
                      icon: icon,
                      selected: _type == value,
                      onTap: _sending
                          ? null
                          : () => setState(() => _type = value)),
              ],
            ),
            const SizedBox(height: AppTokens.spaceLG),
            RtlTextField(
              controller: _details,
              enabled: !_sending,
              minLines: 4,
              maxLines: 6,
              maxLength: 5000,
              decoration: InputDecoration(
                  labelText: t.reportDetails, hintText: t.reportHint),
            ),
            const SizedBox(height: AppTokens.spaceLG),
            RtlTextField(
              controller: _email,
              enabled: !_sending,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: t.reportEmail, hintText: t.reportEmailPlaceholder),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(t.reportEmailHint, style: AppTextStyles.meta),
            if (_error case final error?) ...[
              const SizedBox(height: AppTokens.spaceMD),
              NoticeBanner(
                  kind: NoticeKind.warning,
                  leading:
                      const IconTile(icon: FluentIcons.error_circle_24_regular),
                  title: error),
            ],
          ],
        ))),
        actions: [
          ActionButton.recommended(
              text: _sending ? t.reportSending : t.reportSend,
              icon: FluentIcons.send_24_regular,
              isLoading: _sending,
              onPressed: _sending ? null : _submit),
          ActionButton.outlined(
              text: context.strings.common.cancel,
              onPressed: _sending ? null : () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
