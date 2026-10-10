import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/app_reports_controller.dart';
import '../../settings/safer_mode.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'app_report_form.dart';
import 'app_report_preview_section.dart';
import 'app_report_result_snack.dart';

/// מציג את ההצעה לדווח על קריסה של ההפעלה הקודמת.
Future<AppReportDeliveryResult?> showCrashPromptDialog(
  BuildContext context, {
  required AppReportsController reports,
  required CrashCandidate candidate,
  SaferModeGate? saferMode,
}) {
  return showDialog<AppReportDeliveryResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CrashPromptDialog(
      reports: reports,
      candidate: candidate,
      saferMode: saferMode,
    ),
  );
}

/// "התוכנה נסגרה באופן לא צפוי": תיאור ומייל רשות, תצוגה מקדימה, ובחירה
/// מה לעשות בקריסות הבאות — פורט של `CrashPromptDialog` של אוצריא.
class CrashPromptDialog extends StatefulWidget {
  const CrashPromptDialog({
    super.key,
    required this.reports,
    required this.candidate,
    this.saferMode,
  });

  final AppReportsController reports;
  final CrashCandidate candidate;

  /// שומר הסף של מצב הסייפר; `null` בבדיקות שאינן נוגעות בו.
  final SaferModeGate? saferMode;

  @override
  State<CrashPromptDialog> createState() => _CrashPromptDialogState();
}

class _CrashPromptDialogState extends State<CrashPromptDialog> {
  late final AppReportForm _form = AppReportForm(
    reports: widget.reports,
    trigger: AppReportTrigger.crashPrompt,
    initialType: AppReportType.crash,
    initialTitle: CrashReportDecision.titleFor(
      widget.candidate,
      fallbackTitle: context.strings.appReports.crashFallbackTitle,
    ),
    signature: widget.candidate.signature,
  );
  final _description = TextEditingController();
  late final _email = TextEditingController(text: _form.email);
  AppCrashReportMode _nextTime = AppCrashReportMode.ask;
  bool _started = false;

  /// כאן ולא ב-`initState`: הכותרת הכללית נלקחת מהשפה שב-context.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _form.addListener(_onFormChanged);
      unawaited(_form.loadAttachments());
    }
  }

  @override
  void dispose() {
    _form.removeListener(_onFormChanged);
    _form.dispose();
    _description.dispose();
    _email.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  /// כתיבת הגדרה, ולכן כפופה למצב הסייפר כמו כל כתיבה אחרת: בנעילה נדרשת
  /// סיסמה, ובלעדיה הבחירה אינה נשמרת.
  Future<void> _saveMode() async {
    if (_nextTime == AppCrashReportMode.ask) return;
    final gate = widget.saferMode;
    if (gate != null && gate.isLocked) {
      final verified = await showSaferModePasswordDialog(
        context,
        storedPassword: widget.reports.settings.settings.saferModePassword,
        hint: context.strings.saferMode.verifySettingsHint,
      );
      if (!verified) return;
      gate.unlock();
    }
    await widget.reports.setCrashMode(_nextTime);
  }

  Future<void> _dismiss() async {
    await _saveMode();
    if (!mounted) return;
    UiSnack.show(context.strings.appReports.crashDismissedSnack);
    Navigator.of(context).pop();
  }

  Future<void> _send() async {
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
    if (result == null || !mounted) return;
    if (_form.wasRejected) {
      // הטופס נשאר פתוח עם הטקסט; "אל תשלח" עדיין זמין.
      showAppReportResultSnack(result);
      return;
    }
    await _saveMode();
    if (!mounted) return;
    showAppReportResultSnack(result);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width < 600 ? size.width * 0.95 : 560.0;
    final t = context.strings.appReports;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                t.crashTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildBody(context),
              ),
            ),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.appReports;
    final enabled = !_form.collecting && !_form.isSending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.crashBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppTokens.spaceMD),
        RtlTextField(
          key: const ValueKey('crash-prompt-description'),
          controller: _description,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: t.crashDescriptionLabel,
            alignLabelWithHint: true,
          ),
          onChanged: (value) => _form.update(description: value),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('crash-prompt-email'),
          controller: _email,
          enabled: enabled,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: t.crashEmailLabel,
            errorText:
                _form.invalidField == 'reporterEmail' ? t.emailInvalid : null,
          ),
          onChanged: (value) => _form.update(email: value),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        if (_form.collecting)
          const Padding(
            padding: EdgeInsets.all(AppTokens.spaceMD),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          AppReportPreviewSection(form: _form),
        const SizedBox(height: AppTokens.spaceMD),
        Text(t.crashNextTimeLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppTokens.spaceSM),
        AppSegmentedControl<AppCrashReportMode>(
          options: [
            SegmentOption(value: AppCrashReportMode.ask, label: t.crashNextAsk),
            SegmentOption(
              value: AppCrashReportMode.always,
              label: t.crashNextAlways,
            ),
            SegmentOption(
              value: AppCrashReportMode.never,
              label: t.crashNextNever,
            ),
          ],
          currentValue: _nextTime,
          expandToFillWidth: true,
          onChanged: (mode) => setState(() => _nextTime = mode),
        ),
        const SizedBox(height: AppTokens.spaceSM),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    final t = context.strings.appReports;
    final isSending = _form.isSending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ActionButton.ghost(
            key: const ValueKey('crash-prompt-dismiss'),
            text: t.crashDismissButton,
            onPressed: isSending ? null : _dismiss,
          ),
          const SizedBox(width: AppTokens.spaceSM),
          ActionButton.recommended(
            key: const ValueKey('crash-prompt-send'),
            text: t.crashSendButton,
            icon: FluentIcons.send_24_regular,
            isLoading: isSending,
            onPressed: _form.collecting || isSending ? null : _send,
          ),
        ],
      ),
    );
  }
}
