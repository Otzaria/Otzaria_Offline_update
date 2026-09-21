import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// ניהול הקטגוריות — הוספה, שינוי שם ומחיקה.
///
/// יושב בהגדרות ולא במסך, מאותה סיבה שכל שאר הניהול שם: הקטגוריות נקבעות
/// פעם אחת במחשב המקוון ונוסעות על הכונן.
Future<void> showCustomAppCategoriesDialog({
  required BuildContext context,
  required CustomAppsController controller,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CategoriesDialog(controller: controller),
    );

class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.controller});

  final CustomAppsController controller;

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  /// ה-slug שנערך כרגע, או `null` כשהטופס הוא "הוספה". אותו טופס לשניהם:
  /// מה שאפשר למלא בהוספה חייב להיות גם מה שאפשר לתקן אחריה.
  String? _editingSlug;

  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _startEditing(CustomAppCategory category) {
    setState(() {
      _editingSlug = category.slug;
      _name.text = category.name;
      _description.text = category.description;
    });
  }

  void _clearForm() {
    setState(() {
      _editingSlug = null;
      _name.clear();
      _description.clear();
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);

    final slug = _editingSlug;
    final ok = slug == null
        ? await widget.controller.addCategory(
              _name.text,
              description: _description.text,
            ) !=
            null
        : await widget.controller.renameCategory(
            slug,
            name: _name.text,
            description: _description.text,
          );

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      UiSnack.showError(widget.controller.errorMessage ?? '');
      return;
    }
    _clearForm();
  }

  Future<void> _confirmRemove(CustomAppCategory category) async {
    final t = context.strings.customApps;
    final count = widget.controller.appsIn(category.slug).length;
    final approved = await showWarningDialog(
      context: context,
      title: t.removeCategoryDialogTitle(category.name),
      content: t.removeCategoryDialogContent(category.name, count),
      confirmText: t.removeCategoryTooltip,
    );
    if (!approved) return;

    if (await widget.controller.removeCategory(category.slug)) {
      if (_editingSlug == category.slug) _clearForm();
      UiSnack.show(
        AppL10n.strings.customApps.categoryRemovedSnack(category.name),
      );
      return;
    }
    UiSnack.showError(widget.controller.errorMessage ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);
    final categories = widget.controller.categories;

    return AlertDialog(
      title: Text(t.categoriesTitle, style: theme.textTheme.titleLarge),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.categoriesDialogHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              RtlTextField(
                controller: _name,
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
              const SizedBox(height: AppTokens.spaceMD),
              Wrap(
                spacing: AppTokens.spaceSM,
                runSpacing: AppTokens.spaceSM,
                children: [
                  ActionButton.recommended(
                    text: _editingSlug == null
                        ? t.addCategoryButton
                        : t.saveEditButton,
                    icon: _editingSlug == null
                        ? FluentIcons.add_24_regular
                        : FluentIcons.checkmark_24_regular,
                    isLoading: _busy,
                    onPressed:
                        _busy || _name.text.trim().isEmpty ? null : _submit,
                  ),
                  if (_editingSlug != null)
                    ActionButton.ghost(
                      text: context.strings.common.cancel,
                      onPressed: _busy ? null : _clearForm,
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceLG),
              if (categories.isEmpty)
                SettingsActionTile.text(
                  icon: FluentIcons.tag_24_regular,
                  title: t.categoriesTitle,
                  subtitle: t.noCategoriesHint,
                )
              else
                for (final category in categories)
                  SettingsActionTile.text(
                    icon: FluentIcons.tag_24_regular,
                    // שם הקטגוריה ותיאורה הם תוכן — לא מתורגמים.
                    title: category.name,
                    subtitle: category.description.isEmpty
                        ? t.categoryAppCount(
                            widget.controller.appsIn(category.slug).length,
                          )
                        : category.description,
                    actions: [
                      SecondaryIconButton(
                        icon: FluentIcons.edit_24_regular,
                        tooltip: t.editTooltip,
                        onPressed: _busy ? null : () => _startEditing(category),
                      ),
                      SecondaryIconButton(
                        icon: FluentIcons.delete_24_regular,
                        tooltip: t.removeCategoryTooltip,
                        onPressed:
                            _busy ? null : () => _confirmRemove(category),
                      ),
                    ],
                  ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.neutral(
          text: context.strings.common.close,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
