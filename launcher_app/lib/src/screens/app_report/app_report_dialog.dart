import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'app_report_form.dart';
import 'app_report_images_section.dart';
import 'app_report_preview_section.dart';
import 'app_report_result_snack.dart';

/// פותח את טופס הדיווח על התוכנה. מחזיר את תוצאת השליחה, או null בביטול.
Future<AppReportDeliveryResult?> showAppReportDialog(
  BuildContext context, {
  required AppReportsController reports,
  AppReportImageSource imageSource = const AppReportImageSource(),
}) {
  return showDialog<AppReportDeliveryResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppReportDialog(reports: reports, imageSource: imageSource),
  );
}

/// אייקון לכל סוג דיווח בבורר — מה שמבדיל בין ארבע התוויות הקצרות במבט.
IconData appReportTypeIcon(AppReportType type) => switch (type) {
      AppReportType.bug => FluentIcons.bug_24_regular,
      AppReportType.crash => FluentIcons.error_circle_24_regular,
      AppReportType.performance => FluentIcons.top_speed_24_regular,
      AppReportType.suggestion => FluentIcons.lightbulb_24_regular,
    };

/// טופס דיווח ידני: סוג, כותרת, תיאור, שלבי שחזור, מייל (חובה), תמונות
/// ותצוגה מקדימה של הצרופות — פורט של `AppReportDialog` של אוצריא.
class AppReportDialog extends StatefulWidget {
  const AppReportDialog({
    super.key,
    required this.reports,
    this.imageSource = const AppReportImageSource(),
  });

  final AppReportsController reports;
  final AppReportImageSource imageSource;

  @override
  State<AppReportDialog> createState() => _AppReportDialogState();
}

class _AppReportDialogState extends State<AppReportDialog> {
  late final AppReportForm _form =
      AppReportForm(reports: widget.reports, trigger: AppReportTrigger.manual);
  late final _title = TextEditingController(text: _form.title);
  final _description = TextEditingController();
  final _steps = TextEditingController();
  late final _email = TextEditingController(text: _form.email);

  @override
  void initState() {
    super.initState();
    _form.addListener(_onFormChanged);
    unawaited(_form.loadAttachments());
  }

  @override
  void dispose() {
    _form.removeListener(_onFormChanged);
    _form.dispose();
    _title.dispose();
    _description.dispose();
    _steps.dispose();
    _email.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    try {
      final invalid = await _form.submit();
      if (!mounted) return;
      if (invalid != null) {
        UiSnack.showError(
          appReportInvalidFieldMessage(
            invalid,
            emailEmpty: _form.email.trim().isEmpty,
          ),
        );
        return;
      }
    } catch (_) {
      UiSnack.showError(context.strings.appReports.sendFailedSnack);
      return;
    }
    final result = _form.result;
    if (_form.wasRejected && result != null) {
      // הטופס נשאר פתוח עם הטקסט: המשתמש מתקן את השדה ושולח שוב.
      showAppReportResultSnack(result);
      return;
    }
    if (!_form.isFinished || result == null || !mounted) return;
    showAppReportResultSnack(result);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width < 600 ? size.width * 0.95 : 640.0;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Flexible(
              child: _form.collecting
                  ? const Padding(
                      padding: EdgeInsets.all(AppTokens.spaceXL),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.spaceLG,
                        AppTokens.spaceMD,
                        AppTokens.spaceLG,
                        0,
                      ),
                      child: _buildForm(context),
                    ),
            ),
            const Divider(height: 1),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  /// כותרת הטופס: אייקון, שם הטופס ומשפט שמסביר מה עוזר בדיווח.
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = context.strings.appReports;
    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppTokens.spaceLG,
        AppTokens.spaceMD,
        AppTokens.spaceSM,
        AppTokens.spaceMD,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.person_feedback_24_regular,
              size: 22,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.dialogTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  t.dialogSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SecondaryIconButton(
            tooltip: context.strings.common.close,
            icon: FluentIcons.dismiss_24_regular,
            onPressed:
                _form.isSending ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// תווית שדה: אייקון שמזהה את סוג המידע, ולצידו שם השדה.
  Widget _fieldLabel(
    BuildContext context,
    IconData icon,
    String label, {
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSM),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: AppTokens.spaceXS),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    required String hint,
    String? error,
  }) =>
      InputDecoration(
        filled: true,
        fillColor: AppSurfaces.card(context),
        hintText: hint,
        alignLabelWithHint: true,
        errorText: error,
      );

  Widget _buildForm(BuildContext context) {
    final t = context.strings.appReports;
    final form = _form;
    final enabled = !form.isSending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, FluentIcons.tag_24_regular, t.typeLabel),
        AppSegmentedControl<AppReportType>(
          options: [
            for (final type in AppReportType.values)
              SegmentOption(
                value: type,
                label: appReportTypeLabel(t, type),
                icon: appReportTypeIcon(type),
              ),
          ],
          currentValue: form.type,
          expandToFillWidth: true,
          onChanged: (type) => form.update(type: type),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(context, FluentIcons.textbox_24_regular, t.titleLabel),
        RtlTextField(
          key: const ValueKey('app-report-title'),
          controller: _title,
          enabled: enabled,
          autofocus: true,
          decoration: _decoration(
            context,
            hint: t.titleHint,
            error: form.invalidField == 'title' ? t.titleRequired : null,
          ),
          onChanged: (value) => form.update(title: value),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(
          context,
          FluentIcons.chat_warning_24_regular,
          t.descriptionLabel,
        ),
        RtlTextField(
          key: const ValueKey('app-report-description'),
          controller: _description,
          enabled: enabled,
          minLines: 3,
          maxLines: 6,
          decoration: _decoration(
            context,
            hint: t.descriptionHint,
            error: form.invalidField == 'description'
                ? t.descriptionRequired
                : null,
          ),
          onChanged: (value) => form.update(description: value),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(
          context,
          FluentIcons.text_number_list_ltr_24_regular,
          t.stepsLabel,
          hint: t.optionalHint,
        ),
        RtlTextField(
          key: const ValueKey('app-report-steps'),
          controller: _steps,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          decoration: _decoration(context, hint: t.stepsHint),
          onChanged: (value) => form.update(steps: value),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        _fieldLabel(context, FluentIcons.mail_24_regular, t.emailLabel),
        RtlTextField(
          key: const ValueKey('app-report-email'),
          controller: _email,
          enabled: enabled,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration(
            context,
            hint: 'name@example.com',
            error: form.invalidField == 'reporterEmail' ? t.emailInvalid : null,
          ),
          onChanged: (value) => form.update(email: value),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        AppReportImagesSection(
          images: form.images,
          enabled: enabled,
          source: widget.imageSource,
          onChanged: (images) => form.update(images: images),
        ),
        const SizedBox(height: AppTokens.spaceLG),
        _fieldLabel(
            context, FluentIcons.attach_24_regular, t.attachmentsHeading),
        AppReportPreviewSection(form: form),
        const SizedBox(height: AppTokens.spaceMD),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final t = context.strings.appReports;
    final isSending = _form.isSending;
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ActionButton.ghost(
            text: context.strings.common.cancel,
            onPressed: isSending ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          ActionButton.recommended(
            key: const ValueKey('app-report-send'),
            text: t.sendButton,
            icon: FluentIcons.send_24_regular,
            isLoading: isSending,
            onPressed: _form.collecting || isSending ? null : _submit,
          ),
        ],
      ),
    );
  }
}
