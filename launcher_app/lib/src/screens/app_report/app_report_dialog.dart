import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../services/image_clipboard.dart';
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
  ImageClipboard clipboard = const SystemImageClipboard(),
}) {
  return showDialog<AppReportDeliveryResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppReportDialog(
      reports: reports,
      imageSource: imageSource,
      clipboard: clipboard,
    ),
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
    this.clipboard = const SystemImageClipboard(),
  });

  final AppReportsController reports;
  final AppReportImageSource imageSource;
  final ImageClipboard clipboard;

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

  /// הטופס נפתח מטיוטה ששמרה — אז יש מה למחוק.
  bool _hadDraft = false;

  @override
  void initState() {
    super.initState();
    _form.addListener(_onFormChanged);
    unawaited(_load());
  }

  // The draft is restored before the fields appear, so no typing is lost.
  Future<void> _load() async {
    if (await _form.restoreDraft() && mounted) {
      _hadDraft = true;
      _title.text = _form.title;
      _description.text = _form.description;
      _steps.text = _form.steps;
    }
    await _form.loadAttachments();
  }

  Future<void> _saveDraft() async {
    try {
      await _form.saveDraft();
    } catch (_) {
      if (mounted) {
        UiSnack.showError(context.strings.appReports.draftSaveFailedSnack);
      }
      return;
    }
    if (!mounted) return;
    UiSnack.showSuccess(context.strings.appReports.draftSavedSnack);
    Navigator.of(context).pop();
  }

  Future<void> _discardDraft() async {
    try {
      await _form.discardDraft();
    } catch (_) {
      // נשארה טיוטה בדיסק — היא תיפתח שוב, ואין כאן נזק.
    }
    if (mounted) Navigator.of(context).pop();
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
    final t = context.strings.appReports;
    final cs = Theme.of(context).colorScheme;
    return AppDialog.custom(
      title: t.dialogTitle,
      width: AppTokens.dialogWideWidth,
      customContent: Flexible(
        child: _form.collecting
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTokens.spaceXL),
                child: AppProgressBar(thin: true),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.dialogSubtitle,
                      style: AppTextStyles.dialogBody.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (_hadDraft) ...[
                      const SizedBox(height: AppTokens.spaceSM),
                      Text(
                        t.draftRestoredNote,
                        key: const ValueKey('app-report-draft-note'),
                        style: AppTextStyles.meta.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceMD),
                    _buildForm(context),
                  ],
                ),
              ),
      ),
      actions: _buildActions(context),
    );
  }

  /// תווית שדה: אייקון שמזהה את סוג המידע, ולצידו שם השדה.
  Widget _fieldLabel(
    BuildContext context,
    IconData icon,
    String label, {
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSM),
          Text(
            label,
            style: AppTextStyles.rowTitle.copyWith(color: cs.onSurface),
          ),
          if (hint != null) ...[
            const SizedBox(width: AppTokens.spaceXS),
            Text(
              hint,
              style: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
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
          onChanged: enabled ? (type) => form.update(type: type) : null,
        ),
        if (form.invalidField == 'type')
          Text(
            t.typeRequired,
            style: AppTextStyles.meta.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
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
          otherAttachmentBytes: form.otherAttachmentBytes,
          enabled: enabled,
          source: widget.imageSource,
          clipboard: widget.clipboard,
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

  List<Widget> _buildActions(BuildContext context) {
    final t = context.strings.appReports;
    final isSending = _form.isSending;
    final drafts = _form.supportsDraft;
    return [
      if (_hadDraft)
        ActionButton.ghost(
          key: const ValueKey('app-report-discard-draft'),
          text: t.discardDraftButton,
          onPressed: isSending ? null : _discardDraft,
        ),
      ActionButton.ghost(
        text: context.strings.common.cancel,
        onPressed: isSending ? null : () => Navigator.of(context).pop(),
      ),
      if (drafts)
        ActionButton.neutral(
          key: const ValueKey('app-report-save-draft'),
          text: t.saveDraftButton,
          onPressed: _form.collecting || isSending ? null : _saveDraft,
        ),
      ActionButton.recommended(
        key: const ValueKey('app-report-send'),
        text: t.sendButton,
        icon: FluentIcons.send_24_regular,
        isLoading: isSending,
        onPressed: _form.collecting || isSending ? null : _submit,
      ),
    ];
  }
}
