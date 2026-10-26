import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';

/// אבני הבניין של טופס התוכנה (`.field`) — ראו `CustomAppFormDialog`.

/// תווית 13/600 מעל התוכן.
class FormLabelled extends StatelessWidget {
  const FormLabelled({
    super.key,
    required this.label,
    required this.child,
    this.help,
  });

  final String label;
  final Widget child;

  /// הסבר קטן מתחת (`.help`).
  final String? help;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: AppTextStyles.sectionLabel.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          child,
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(
              help!,
              style: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// שדה טקסט עם תווית מעליו והסבר מתחתיו. [onChanged] קיים כי המזהה
/// והכפתורים נגזרים מהשדות, והטופס צריך להיבנות מחדש בכל הקשה.
class FormTextField extends StatelessWidget {
  const FormTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
    this.ltr = false,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  /// נתיב, כתובת, שם קובץ — LTR.
  final bool ltr;

  /// כפתור בשורה של השדה ("הצגת הקבצים", "בחירה…").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final field = RtlTextField(
      controller: controller,
      decoration: const InputDecoration(),
      maxLines: maxLines,
      minLines: maxLines,
      textDirection: ltr ? TextDirection.ltr : null,
      onChanged: onChanged,
    );
    return FormLabelled(
      label: label,
      help: hint,
      child: trailing == null
          ? field
          : Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: AppTokens.spaceSM),
                trailing!,
              ],
            ),
    );
  }
}

/// הקטגוריות כשבבי בחירה. **אין כאן יצירה של קטגוריה** — היא נעשית בדף
/// הניהול; כשאין אף קטגוריה הטופס אינו מציג את זה בכלל.
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
    return FormLabelled(
      label: t.appCategoriesLabel,
      help: t.appCategoriesHint,
      child: Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (final category in categories)
            StoreFilterChip(
              label: category.name,
              selected: selected.contains(category.slug),
              onTap: () => onToggle(category.slug),
            ),
        ],
      ),
    );
  }
}
