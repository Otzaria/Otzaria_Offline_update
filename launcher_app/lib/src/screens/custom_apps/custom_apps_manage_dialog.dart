import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_categories_dialog.dart';
import 'custom_app_form_dialog.dart';
import 'custom_app_status.dart';

/// פותח את טופס ההוספה.
Future<void> openAddCustomApp(
  BuildContext context,
  CustomAppsController controller,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => CustomAppFormDialog(controller: controller),
    );

/// פותח את אותו טופס עצמו על רשומה קיימת. אותו טופס בכוונה: מה שאפשר
/// למלא בהוספה חייב להיות גם מה שאפשר לתקן אחריה.
Future<void> openEditCustomApp(
  BuildContext context,
  CustomAppsController controller,
  CustomAppEntry entry,
) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          CustomAppFormDialog(controller: controller, existing: entry),
    );

/// **כל ניהול התוכנות הנוספות יושב כאן** — הוספה, עריכה, הסרה, קטגוריות
/// וסדר התצוגה.
///
/// המרשם הוא הגדרה ולא שימוש: הוא נקבע פעם אחת במחשב המקוון ואחר כך נוסע
/// על הכונן. מסך "תוכנות נוספות" נשאר למה שעושים איתו כל יום — הורדה,
/// התקנה והפעלה. בהגדרות נשארה שורה אחת בלבד, שכל תפקידה לפתוח את החלון
/// הזה — ראו `CustomAppsSettingsCard`.
Future<void> showCustomAppsManageDialog({
  required BuildContext context,
  required CustomAppsController controller,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ManageDialog(controller: controller),
    );

/// מתחת למספר הזה חיפוש רק מוסיף שדה ריק — הרשימה כולה נראית ממילא.
const int _searchThreshold = 6;

class _ManageDialog extends StatefulWidget {
  const _ManageDialog({required this.controller});

  final CustomAppsController controller;

  @override
  State<_ManageDialog> createState() => _ManageDialogState();
}

class _ManageDialogState extends State<_ManageDialog> {
  final _search = TextEditingController();
  String _query = '';

  CustomAppsController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CustomAppView app) {
    if (_query.isEmpty) return true;
    final d = app.descriptor;
    return [d.name, d.description, d.publisher]
        .whereType<String>()
        .any((text) => text.toLowerCase().contains(_query));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // החלון מאזין בעצמו: הוספה, הסרה ושינוי סדר משנים את הרשימה בזמן
    // שהוא פתוח, ואיש אינו בונה אותו מחדש מבחוץ.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final apps = controller.apps;
        final showSearch = apps.length >= _searchThreshold;
        // סינון מציג רשימה חלקית, ואינדקס בה אינו המקום ברשימה המלאה.
        final searching = showSearch && _query.isNotEmpty;

        return AlertDialog(
          title: Text(t.manageDialogTitle, style: theme.textTheme.titleLarge),
          // רוחב קבוע: `AlertDialog` מודד רוחב פנימי, ורשימה נגללת אינה
          // יודעת לענות עליו.
          content: SizedBox(
            width: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.manageDialogHint, style: hint),
                const SizedBox(height: AppTokens.spaceMD),
                Wrap(
                  spacing: AppTokens.spaceSM,
                  runSpacing: AppTokens.spaceSM,
                  children: [
                    ActionButton.recommended(
                      text: t.addButton,
                      icon: FluentIcons.add_24_regular,
                      onPressed: controller.isBusy
                          ? null
                          : () => openAddCustomApp(context, controller),
                    ),
                    // הקטגוריות הן חלק מאותו מרשם, ולכן הניהול שלהן יושב
                    // כאן ולא במסך — שם רואים אותן כסרגל צד ואי אפשר לשנותן.
                    ActionButton.neutral(
                      text: t.manageCategoriesButton,
                      icon: FluentIcons.tag_24_regular,
                      onPressed: controller.isBusy
                          ? null
                          : () => showCustomAppCategoriesDialog(
                                context: context,
                                controller: controller,
                              ),
                    ),
                  ],
                ),
                if (showSearch) ...[
                  const SizedBox(height: AppTokens.spaceMD),
                  RtlTextField(
                    controller: _search,
                    onChanged: (value) => setState(
                      () => _query = value.trim().toLowerCase(),
                    ),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(
                        borderRadius: AppTokens.borderRadiusAll,
                      ),
                      prefixIcon: const Icon(FluentIcons.search_24_regular),
                      hintText: t.manageSearchHint,
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLG),
                Flexible(child: _list(context, apps, searching)),
                // מוצג רק כשיש מה לסדר.
                if (apps.length > 1) ...[
                  const SizedBox(height: AppTokens.spaceSM),
                  Text(
                    searching
                        ? t.manageReorderDisabledWhileSearching
                        : t.orderHint,
                    style: hint,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ActionButton.neutral(
              text: context.strings.common.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _list(
    BuildContext context,
    List<CustomAppView> apps,
    bool searching,
  ) {
    final t = context.strings.customApps;
    if (apps.isEmpty) {
      return SettingsActionTile.text(
        icon: FluentIcons.box_24_regular,
        title: t.settingsCardTitle,
        subtitle: t.emptyHint,
      );
    }

    if (searching) {
      final shown = apps.where(_matches).toList();
      if (shown.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceLG),
          child: Center(child: Text(t.manageNoResults)),
        );
      }
      return ListView(
        shrinkWrap: true,
        children: [
          for (final app in shown)
            _ManagedAppRow(controller: controller, app: app),
        ],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      // ידית גרירה מפורשת: גרירה מכל השורה הייתה מתנגשת בכפתורים שבה.
      buildDefaultDragHandles: false,
      itemCount: apps.length,
      // `onReorderItem` כבר מתקן את היעד להסרה — בדיוק מה ש-`moveApp` מצפה.
      onReorderItem: (from, to) => controller.moveApp(from, to),
      proxyDecorator: (child, _, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Material(
          elevation: 6 * animation.value,
          borderRadius: AppTokens.borderRadiusAll,
          color: Colors.transparent,
          child: child,
        ),
        child: child,
      ),
      itemBuilder: (context, i) => _ManagedAppRow(
        key: ValueKey(apps[i].descriptor.id),
        controller: controller,
        app: apps[i],
        index: i,
        total: apps.length,
      ),
    );
  }
}

/// שורת תוכנה אחת במרשם — מה שהמשתמש רשם, והכפתורים שמשנים אותו.
///
/// [index] הוא `null` כשהרשימה מסוננת: אז אין ידית ואין חיצים.
class _ManagedAppRow extends StatelessWidget {
  const _ManagedAppRow({
    super.key,
    required this.controller,
    required this.app,
    this.index,
    this.total = 0,
  });

  final CustomAppsController controller;
  final CustomAppView app;
  final int? index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final busy = controller.isBusy;
    final d = app.descriptor;
    final i = index;
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: Material(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceSM),
          child: Row(
            children: [
              if (i != null)
                ReorderableDragStartListener(
                  index: i,
                  enabled: !busy && total > 1,
                  child: MouseRegion(
                    cursor: busy || total < 2
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.grab,
                    child: Tooltip(
                      message: t.dragToReorderTooltip,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceXS,
                        ),
                        child: Icon(
                          FluentIcons.re_order_dots_vertical_24_regular,
                          color: total > 1 ? cs.onSurfaceVariant : cs.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: AppTokens.spaceSM),
              SizedBox.square(
                dimension: 40,
                child: StoreThumbnail.icon(
                  imagePath: controller.iconPathOf(d),
                  aspectRatio: 1,
                  iconSize: 22,
                  placeholderIcon: FluentIcons.box_24_regular,
                ),
              ),
              const SizedBox(width: AppTokens.spaceMD),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
                    Text(
                      d.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_sourceLabel(context)} · '
                      '${customAppStoredLabel(context, app)}',
                      style: meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (d.categorySlugs.isNotEmpty) ...[
                      const SizedBox(height: AppTokens.spaceXS),
                      Wrap(
                        spacing: AppTokens.spaceXS,
                        runSpacing: AppTokens.spaceXS,
                        children: [
                          for (final slug in d.categorySlugs)
                            StoreTagPill(label: controller.categoryName(slug)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // ⚠️ חיצי מעלה/מטה ולא `context.backArrowIcon`: אלה חיצי סדר
              // ברשימה אנכית, ו-RTL אינו הופך "למעלה" ו"למטה". הם נשארים
              // לצד הגרירה בשביל המקלדת.
              if (i != null) ...[
                SecondaryIconButton(
                  icon: FluentIcons.arrow_up_24_regular,
                  tooltip: t.moveAppUpTooltip,
                  onPressed: busy || i == 0
                      ? null
                      : () => controller.moveApp(i, i - 1),
                ),
                SecondaryIconButton(
                  icon: FluentIcons.arrow_down_24_regular,
                  tooltip: t.moveAppDownTooltip,
                  onPressed: busy || i == total - 1
                      ? null
                      : () => controller.moveApp(i, i + 1),
                ),
              ],
              SecondaryIconButton(
                icon: FluentIcons.edit_24_regular,
                tooltip: t.editTooltip,
                onPressed: busy
                    ? null
                    : () => openEditCustomApp(context, controller, app.entry),
              ),
              SecondaryIconButton(
                icon: FluentIcons.delete_24_regular,
                tooltip: t.removeTooltip,
                onPressed: busy ? null : () => _confirmRemove(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(BuildContext context) {
    final t = context.strings.customApps;
    final github = app.descriptor.github;
    if (app.descriptor.sourceKind == AppSourceKind.github && github != null) {
      // LTR מפורש: שם ריפו בתוך שורה עברית מתהפך סביב הלוכסן.
      return '${t.infoSourceGithub} \u{2066}${github.owner}/${github.repo}\u{2069}';
    }
    return t.infoSourceFile;
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final t = context.strings.customApps;
    final approved = await showWarningDialog(
      context: context,
      title: t.removeDialogTitle,
      content: t.removeDialogContent(app.descriptor.name),
      confirmText: t.removeDialogConfirm,
    );
    if (!approved) return;

    if (await controller.remove(app.descriptor.id)) {
      UiSnack.show(
        AppL10n.strings.customApps.removedSnack(app.descriptor.name),
      );
      return;
    }
    UiSnack.showError(controller.errorMessage ?? '');
  }
}
