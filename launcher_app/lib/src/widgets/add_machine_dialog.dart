import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'rtl_text_field.dart';

typedef NewMachine = ({String name, int version});

/// גרסת ספרייה מעל זה אינה אמיתית — מונע הקלדה שגויה שתקבע את כל ההורדה.
const int maxManualLibraryVersion = 100000;

/// שם וגרסת ספרייה של מחשב שלא מחובר, או `null` בביטול.
Future<NewMachine?> showAddMachineDialog(BuildContext context) =>
    showDialog<NewMachine>(
      context: context,
      builder: (_) => const _AddMachineDialog(),
    );

class _AddMachineDialog extends StatefulWidget {
  const _AddMachineDialog();

  @override
  State<_AddMachineDialog> createState() => _AddMachineDialogState();
}

class _AddMachineDialogState extends State<_AddMachineDialog> {
  final _name = TextEditingController();
  final _version = TextEditingController();
  final _versionFocus = FocusNode();
  ({TextEditingController field, String message})? _error;

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _versionFocus.dispose();
    super.dispose();
  }

  void _save() {
    final t = context.strings.settings;
    final name = _name.text.trim();
    final version = int.tryParse(_version.text.trim());
    final error = switch ((name, version)) {
      ('', _) => (field: _name, message: t.personalMachineAddNameRequired),
      (_, final int? v)
          when v == null || v <= 0 || v > maxManualLibraryVersion =>
        (
          field: _version,
          message: t.personalMachineAddVersionInvalid,
        ),
      _ => null,
    };
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop((name: name, version: version!));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.settings;
    const pad = AppTokens.spaceLG;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.all(pad),
      buttonPadding: EdgeInsets.zero,
      title: Text(t.personalMachineAddTitle),
      content: SizedBox(
        width: AppTokens.dialogFormWidth - 2 * pad,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.personalMachineAddIntro),
              const SizedBox(height: 16),
              _Field(
                label: t.personalMachineAddNameLabel,
                controller: _name,
                error: _error?.field == _name ? _error!.message : null,
                autofocus: true,
                onSubmitted: _versionFocus.requestFocus,
              ),
              const SizedBox(height: 14),
              _Field(
                label: t.personalMachineAddVersionLabel,
                controller: _version,
                focusNode: _versionFocus,
                error: _error?.field == _version ? _error!.message : null,
                numeric: true,
                onSubmitted: _save,
              ),
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
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 104),
              child: ActionButton.ghost(
                text: context.strings.common.cancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 104),
              child: ActionButton.recommended(
                text: t.personalMachineAddConfirm,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onSubmitted,
    this.focusNode,
    this.error,
    this.autofocus = false,
    this.numeric = false,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final FocusNode? focusNode;
  final String? error;
  final bool autofocus;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.sectionLabel.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: label,
          child: RtlTextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            keyboardType: numeric ? TextInputType.number : null,
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
        if (error case final message?) ...[
          const SizedBox(height: 6),
          Text(message, style: AppTextStyles.rowSub.copyWith(color: cs.error)),
        ],
      ],
    );
  }
}
