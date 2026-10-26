import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../settings/safer_mode.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'rtl_text_field.dart';

/// סיסמת מצב הסייפר; `true` רק בסיסמה הנכונה. [hint] אומר למה מבקשים
/// אותה עכשיו.
Future<bool> showSaferModePasswordDialog(
  BuildContext context, {
  required String storedPassword,
  required String hint,
  String? confirmText,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _VerifyDialog(
        storedPassword: storedPassword,
        hint: hint,
        confirmText: confirmText,
      ),
    ) ??
    false;

/// קביעת סיסמה ראשונה. מחזיר את הערך המעורבל לשמירה, או `null` בביטול.
/// [onThisComputer] — בכונן מוגן ההגדרות נשמרות במחשב, וההסבר אומר זאת.
Future<String?> showSaferModeSetPasswordDialog(
  BuildContext context, {
  bool onThisComputer = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _SetPasswordDialog(onThisComputer: onThisComputer),
    );

/// החלפת סיסמה: הנוכחית והחדשה פעמיים בדו-שיח אחד. מחזיר את הערך המעורבל
/// החדש, או `null` בביטול.
Future<String?> showSaferModeChangePasswordDialog(
  BuildContext context, {
  required String storedPassword,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _SetPasswordDialog(storedPassword: storedPassword),
    );

/// מחיקת הסיסמה — אזהרה עם הסיסמה הנוכחית. `true` רק כשהיא נכונה ואושרה.
Future<bool> showSaferModeClearPasswordDialog(
  BuildContext context, {
  required String storedPassword,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ClearPasswordDialog(storedPassword: storedPassword),
    ) ??
    false;

class _VerifyDialog extends StatefulWidget {
  const _VerifyDialog({
    required this.storedPassword,
    required this.hint,
    this.confirmText,
  });

  final String storedPassword;
  final String hint;
  final String? confirmText;

  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends State<_VerifyDialog> {
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _verify() {
    final t = context.strings.saferMode;
    if (_password.text.isEmpty) {
      setState(() => _error = t.passwordRequired);
      return;
    }
    if (SaferModePassword.verify(widget.storedPassword, _password.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    // שגיאה בתוך הדו-שיח ולא סגירה: מי שהקליד שגוי מנסה שוב.
    _password.clear();
    setState(() => _error = t.wrongPassword);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    return _FormDialog(
      title: t.verifyTitle,
      intro: widget.hint,
      fields: [
        _PasswordField(
          controller: _password,
          label: t.passwordLabel,
          error: _error,
          autofocus: true,
          onSubmitted: _verify,
        ),
      ],
      actions: [
        ActionButton.ghost(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ActionButton.recommended(
          text: widget.confirmText ?? context.strings.common.confirm,
          onPressed: _verify,
        ),
      ],
    );
  }
}

/// קביעה, ועם [storedPassword] — החלפה (שדה הסיסמה הנוכחית נוסף בראש).
class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog({this.storedPassword, this.onThisComputer = false});

  final String? storedPassword;
  final bool onThisComputer;

  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final FocusNode _currentFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  /// השגיאה מוצגת מתחת לשדה שגרם לה.
  ({TextEditingController field, String message})? _error;

  bool get _changing => widget.storedPassword != null;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    _currentFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String? _errorOf(TextEditingController field) =>
      _error?.field == field ? _error!.message : null;

  void _save() {
    final t = context.strings.saferMode;
    if (_changing &&
        !SaferModePassword.verify(widget.storedPassword!, _current.text)) {
      _current.clear();
      _currentFocus.requestFocus();
      setState(() => _error = (field: _current, message: t.wrongPassword));
      return;
    }
    final error = switch (_password.text) {
      '' => (field: _password, message: t.passwordRequired),
      final p when p.length < SaferModePassword.minLength => (
          field: _password,
          message: t.passwordTooShort(SaferModePassword.minLength),
        ),
      final p when p != _confirm.text => (
          field: _confirm,
          message: t.passwordsDoNotMatch,
        ),
      _ => null,
    };
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    // הדו-שיח מחזיר את הערך המעורבל ולא את הסיסמה — היא לא יוצאת מכאן.
    Navigator.of(context).pop(SaferModePassword.encode(_password.text));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    return _FormDialog(
      title: _changing ? t.changeTitle : t.setTitle,
      intro: _changing
          ? null
          : t.setIntro(
              SaferModePassword.minLength,
              onThisComputer: widget.onThisComputer,
            ),
      fields: [
        if (_changing)
          _PasswordField(
            controller: _current,
            focusNode: _currentFocus,
            label: t.currentPasswordLabel,
            error: _errorOf(_current),
            autofocus: true,
            onSubmitted: _passwordFocus.requestFocus,
          ),
        _PasswordField(
          controller: _password,
          focusNode: _passwordFocus,
          label: _changing ? t.newPasswordLabel : t.passwordLabel,
          error: _errorOf(_password),
          autofocus: !_changing,
          onSubmitted: _confirmFocus.requestFocus,
        ),
        _PasswordField(
          controller: _confirm,
          focusNode: _confirmFocus,
          label: t.confirmPasswordLabel,
          error: _errorOf(_confirm),
          onSubmitted: _save,
        ),
      ],
      actions: [
        ActionButton.ghost(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: _changing ? t.changeButton : t.setConfirm,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _ClearPasswordDialog extends StatefulWidget {
  const _ClearPasswordDialog({required this.storedPassword});

  final String storedPassword;

  @override
  State<_ClearPasswordDialog> createState() => _ClearPasswordDialogState();
}

class _ClearPasswordDialogState extends State<_ClearPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _cancelFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _passwordFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  /// מציג את השגיאה ומחזיר false כשהסיסמה ריקה או שגויה.
  bool _check() {
    final t = context.strings.saferMode;
    if (_password.text.isEmpty) {
      _passwordFocus.requestFocus();
      setState(() => _error = t.passwordRequired);
      return false;
    }
    if (SaferModePassword.verify(widget.storedPassword, _password.text)) {
      return true;
    }
    _password.clear();
    _passwordFocus.requestFocus();
    setState(() => _error = t.wrongPassword);
    return false;
  }

  void _clear() {
    if (_check()) Navigator.of(context).pop(true);
  }

  /// Enter אינו מוחק: שגיאה נשארת בשדה, ורק סיסמה נכונה ממקדת את הביטול.
  void _submitted() {
    if (!_check()) return;
    setState(() => _error = null);
    _cancelFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    // אזהרה: הבטוח (ביטול) מומלץ, והפעולה ההרסנית בקצה — כמו `showWarningDialog`.
    return _FormDialog(
      title: t.clearDialogTitle,
      intro: t.clearDialogContent,
      fields: [
        _PasswordField(
          controller: _password,
          focusNode: _passwordFocus,
          label: t.currentPasswordLabel,
          error: _error,
          autofocus: true,
          onSubmitted: _submitted,
        ),
      ],
      actions: [
        ActionButton.recommended(
          focusNode: _cancelFocus,
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        ActionButton.warning(text: t.clearButton, onPressed: _clear),
      ],
    );
  }
}

/// דו-שיח שדות (`.dialog.form`): 440, ריפוד 24, הסבר ושדות עם תווית מעליהם.
/// השגיאה בתוך הדו-שיח, מתחת לשדה שלה — לא בהודעה צפה.
class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.fields,
    required this.actions,
    this.intro,
  });

  final String title;
  final String? intro;
  final List<Widget> fields;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    const pad = AppTokens.spaceLG;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.all(pad),
      buttonPadding: EdgeInsets.zero,
      title: Text(title),
      content: SizedBox(
        width: AppTokens.dialogFormWidth - 2 * pad,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (intro != null) ...[Text(intro!), const SizedBox(height: 16)],
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                fields[i],
              ],
            ],
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: [
            for (final action in actions)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 104),
                child: action,
              ),
          ],
        ),
      ],
    );
  }
}

/// שדה סיסמה (`.field`): תווית 13/600 מעליו, כפתור "הצג/הסתר" בקצה ושורת
/// שגיאה (`.errline`) מתחתיו.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.focusNode,
    this.error,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSubmitted;
  final FocusNode? focusNode;
  final String? error;
  final bool autofocus;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.saferMode;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.sectionLabel.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: widget.label,
          child: RtlTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            obscureText: _obscured,
            autofocus: widget.autofocus,
            onSubmitted: (_) => widget.onSubmitted(),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                // 40 ולא 48 של יעד המגע, כדי שהשדה יישאר 44.
                visualDensity: VisualDensity.compact,
                tooltip:
                    _obscured ? t.showPasswordTooltip : t.hidePasswordTooltip,
                icon: Icon(
                  _obscured
                      ? FluentIcons.eye_24_regular
                      : FluentIcons.eye_off_24_regular,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),
        ),
        if (widget.error case final error?) ...[
          const SizedBox(height: 6),
          Text(error, style: AppTextStyles.rowSub.copyWith(color: cs.error)),
        ],
      ],
    );
  }
}
