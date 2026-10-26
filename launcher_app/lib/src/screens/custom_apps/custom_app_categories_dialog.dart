import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// טופס קטגוריה אחת: הוספה, או עריכה של [editing]. הרשימה עצמה, עם העריכה
/// והמחיקה, בדף הניהול — כאן היא הייתה כפולה.
Future<void> showCustomAppCategoriesDialog({
  required BuildContext context,
  required CustomAppsController controller,
  CustomAppCategory? editing,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          _CategoriesDialog(controller: controller, editing: editing),
    );

/// שואל, ורק אז מוחק קטגוריה. התוכנות שבה עוברות ל"ללא קטגוריה".
Future<bool> confirmRemoveCustomAppCategory(
  BuildContext context,
  CustomAppsController controller,
  CustomAppCategory category,
) async {
  final t = context.strings.customApps;
  final count = controller.appsIn(category.slug).length;
  final approved = await showWarningDialog(
    context: context,
    title: t.removeCategoryDialogTitle(category.name),
    content: t.removeCategoryDialogContent(category.name, count),
    confirmText: t.removeCategoryTooltip,
  );
  if (!approved) return false;

  if (await controller.removeCategory(category.slug)) {
    UiSnack.show(
      AppL10n.strings.customApps.categoryRemovedSnack(category.name),
    );
    return true;
  }
  UiSnack.showFailure(controller.errorMessage);
  return false;
}

class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.controller, this.editing});

  final CustomAppsController controller;
  final CustomAppCategory? editing;

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  bool _busy = false;

  bool get _editing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    if (widget.editing case final category?) {
      _name.text = category.name;
      _description.text = category.description;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);

    final editing = widget.editing;
    final ok = editing == null
        ? await widget.controller.addCategory(
              _name.text,
              description: _description.text,
            ) !=
            null
        : await widget.controller.renameCategory(
            editing.slug,
            name: _name.text,
            description: _description.text,
          );

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      UiSnack.showFailure(widget.controller.errorMessage);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    const pad = AppTokens.spaceLG;

    return AlertDialog(
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.all(pad),
      title: Text(_editing ? t.editCategoryTitle : t.addCategoryButton),
      content: SizedBox(
        width: AppTokens.dialogFormWidth - 2 * pad,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.categoriesDialogHint),
              const SizedBox(height: AppTokens.spaceMD),
              RtlTextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.categoryNameLabel,
                  helperText: t.categoryNameHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              RtlTextField(
                controller: _description,
                decoration: InputDecoration(
                  labelText: t.categoryDescriptionLabel,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTokens.spaceSM,
          children: [
            ActionButton.ghost(
              text: context.strings.common.cancel,
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            ActionButton.recommended(
              text: _editing ? t.saveEditButton : t.addCategoryButton,
              isLoading: _busy,
              onPressed: _busy || _name.text.trim().isEmpty ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }
}
