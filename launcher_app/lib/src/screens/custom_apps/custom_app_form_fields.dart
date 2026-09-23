import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';

/// אבני הבניין של טופס התוכנה — ראו `CustomAppFormDialog`.

/// כותרת קטנה ומתחתיה התוכן.
class FormLabelled extends StatelessWidget {
  const FormLabelled({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppTokens.spaceSM),
          child,
        ],
      );
}

/// שדה טקסט עם תווית ורמז. [onChanged] קיים כי המזהה והכפתור "שמירה"
/// נגזרים מהשדות, והטופס צריך להיבנות מחדש בכל הקשה.
class FormTextField extends StatelessWidget {
  const FormTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
        child: RtlTextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label, helperText: hint),
          onChanged: onChanged,
        ),
      );
}

/// כותרת של קבוצת שדות בטופס — מפרידה בין "מה התוכנה" ל"מאיפה היא מגיעה".
class FormSectionHeader extends StatelessWidget {
  const FormSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
    );
  }
}

/// הקטגוריות כגלולות שנבחרות. **אין כאן יצירה של קטגוריה** — היא נעשית
/// בחלון הניהול; כשאין אף קטגוריה הטופס אינו מציג את זה בכלל.
class CustomAppCategoriesPicker extends StatelessWidget {
  const CustomAppCategoriesPicker({
    super.key,
    required this.categories,
    required this.selected,
    required this.onToggle,
  });

  final List<CustomAppCategory> categories;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);

    return FormLabelled(
      label: t.appCategoriesLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              for (final category in categories)
                StoreTagPill(
                  label: category.name,
                  active: selected.contains(category.slug),
                  onTap: () => onToggle(category.slug),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            t.appCategoriesHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
