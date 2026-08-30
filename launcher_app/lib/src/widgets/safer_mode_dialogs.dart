import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../settings/safer_mode.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'rtl_text_field.dart';
import 'ui_snack.dart';

/// רוחב קבוע לשדות — דיאלוג שרוחבו נגזר מאורך התווית קופץ בין השפות.
const double _fieldWidth = 380;

/// מבקש את סיסמת מצב הסייפר. מחזיר `true` רק כשהוזנה הסיסמה הנכונה.
///
/// [hint] אומר *למה* מבקשים אותה עכשיו — כניסה להגדרות, עריכת ההדרכה,
/// הפעלת המצב או כיבויו.
Future<bool> showSaferModePasswordDialog(
  BuildContext context, {
  required String storedPassword,
  required String hint,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _PasswordDialog(
        storedPassword: storedPassword,
        hint: hint,
      ),
    ) ??
    false;

/// בחירת סיסמה חדשה. מחזיר את הערך המעורבל לשמירה, או `null` בביטול.
Future<String?> showSaferModeSetPasswordDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _SetPasswordDialog(),
    );

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.storedPassword, required this.hint});

  final String storedPassword;
  final String hint;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _password = TextEditingController();
  bool _obscured = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _verify() {
    final t = context.strings.saferMode;
    if (_password.text.isEmpty) {
      UiSnack.showError(t.passwordRequired);
      return;
    }
    if (SaferModePassword.verify(widget.storedPassword, _password.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    // הודעה ולא סגירה: מי שהקליד שגוי מנסה שוב, ואינו נזרק למסך הקודם.
    UiSnack.showError(t.wrongPassword);
    _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;

    return AlertDialog(
      title: _DialogTitle(t.verifyTitle),
      content: SizedBox(
        width: _fieldWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hint(widget.hint),
            const SizedBox(height: AppTokens.spaceMD),
            _PasswordField(
              controller: _password,
              label: t.passwordLabel,
              hint: t.passwordFieldHint,
              icon: FluentIcons.key_24_regular,
              obscured: _obscured,
              autofocus: true,
              onToggleObscured: () => setState(() => _obscured = !_obscured),
              onSubmitted: _verify,
            ),
          ],
        ),
      ),
      actions: [
        ActionButton.neutral(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ActionButton.recommended(
          text: context.strings.common.confirm,
          onPressed: _verify,
        ),
      ],
    );
  }
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final FocusNode _confirmFocus = FocusNode();
  bool _obscured = true;
  bool _obscuredConfirm = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _save() {
    final t = context.strings.saferMode;
    if (_password.text.isEmpty) {
      UiSnack.showError(t.passwordRequired);
      return;
    }
    if (_password.text.length < SaferModePassword.minLength) {
      UiSnack.showError(t.passwordTooShort(SaferModePassword.minLength));
      return;
    }
    if (_password.text != _confirm.text) {
      UiSnack.showError(t.passwordsDoNotMatch);
      return;
    }
    // הדיאלוג מחזיר את הערך המעורבל ולא את הסיסמה — היא לא יוצאת מכאן.
    Navigator.of(context).pop(SaferModePassword.encode(_password.text));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;

    return AlertDialog(
      title: _DialogTitle(t.setTitle),
      content: SizedBox(
        width: _fieldWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hint(t.setIntro),
            const SizedBox(height: AppTokens.spaceMD),
            _PasswordField(
              controller: _password,
              label: t.newPasswordLabel,
              hint: t.minLengthHint(SaferModePassword.minLength),
              icon: FluentIcons.key_24_regular,
              obscured: _obscured,
              autofocus: true,
              onToggleObscured: () => setState(() => _obscured = !_obscured),
              onSubmitted: _confirmFocus.requestFocus,
            ),
            const SizedBox(height: AppTokens.spaceMD),
            _PasswordField(
              controller: _confirm,
              focusNode: _confirmFocus,
              label: t.confirmPasswordLabel,
              hint: t.confirmPasswordFieldHint,
              icon: FluentIcons.checkmark_lock_24_regular,
              obscured: _obscuredConfirm,
              onToggleObscured: () =>
                  setState(() => _obscuredConfirm = !_obscuredConfirm),
              onSubmitted: _save,
            ),
          ],
        ),
      ),
      actions: [
        ActionButton.neutral(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(text: t.saveButton, onPressed: _save),
      ],
    );
  }
}

class _DialogTitle extends StatelessWidget {
  const _DialogTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Icon(FluentIcons.lock_closed_24_regular),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleLarge),
          ),
        ],
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// שדה סיסמה עם כפתור "הצג/הסתר" — שלושה כאלה בקובץ, ואין ביניהם הבדל.
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.obscured,
    required this.onToggleObscured,
    required this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscured;
  final VoidCallback onToggleObscured;
  final VoidCallback onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;

    return RtlTextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscured,
      autofocus: autofocus,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          tooltip: obscured ? t.showPasswordTooltip : t.hidePasswordTooltip,
          icon: Icon(
            obscured
                ? FluentIcons.eye_24_regular
                : FluentIcons.eye_off_24_regular,
          ),
          onPressed: onToggleObscured,
        ),
      ),
    );
  }
}
