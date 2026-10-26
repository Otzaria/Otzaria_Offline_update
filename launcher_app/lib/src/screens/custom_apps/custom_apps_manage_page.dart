import 'dart:async';

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

/// אותו טופס על רשומה קיימת: מה שאפשר למלא בהוספה חייב להיות גם מה שאפשר
/// לתקן אחריה.
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

/// שואל, ורק אז מסיר את התוכנה מהמרשם.
Future<void> confirmRemoveCustomApp(
  BuildContext context,
  CustomAppsController controller,
  CustomAppView app,
) async {
  final t = context.strings.customApps;
  final approved = await showWarningDialog(
    context: context,
    title: t.removeDialogTitle(app.descriptor.name),
    content: t.removeDialogContent(app.descriptor.name),
    confirmText: t.removeDialogConfirm,
  );
  if (!approved) return;

  if (await controller.remove(app.descriptor.id)) {
    UiSnack.show(AppL10n.strings.customApps.removedSnack(app.descriptor.name));
    return;
  }
  UiSnack.showFailure(controller.errorMessage);
}

/// **כל ניהול התוכנות הנוספות** — הוספה, עריכה, הסרה, קטגוריות וסדר. דף
/// בתוך הגוף תחת ההגדרות (`CustomAppsManageRoute`), מאחורי אותו שער סייפר.
class CustomAppsManagePage extends StatefulWidget {
  const CustomAppsManagePage({
    super.key,
    required this.controller,
    this.readOnly = false,
  });

  final CustomAppsController controller;
  final bool readOnly;

  @override
  State<CustomAppsManagePage> createState() => _CustomAppsManagePageState();
}

class _CustomAppsManagePageState extends State<CustomAppsManagePage> {
  /// הרשומה שנגררת כרגע — מוצגת עמומה במקומה.
  String? _draggingId;

  CustomAppsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool get _locked => widget.readOnly || _c.isBusy;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final add = ActionButton.recommended(
      text: t.addButton,
      icon: FluentIcons.add_20_regular,
      onPressed: _locked ? null : () => openAddCustomApp(context, _c),
    );

    return StoreBody(
      maxWidth: LayoutConstraints.panelContentMaxWidth,
      slivers: [
        StoreBody.block(
          StorePageHead(
            title: t.manageDialogTitle,
            description: t.manageDialogHint,
            actions: [if (_c.hasApps) add],
          ),
        ),
        if (_c.isLearning)
          StoreBody.block(
            AppCard(
              padding: const EdgeInsets.all(16),
              child: InfoProgressRow(stage: t.learningLabel),
            ),
            bottom: 12,
          ),
        if (!_c.hasApps)
          StoreBody.block(
            EmptyState(
              icon: FluentIcons.apps_add_in_24_regular,
              title: t.manageEmptyTitle,
              body: t.manageEmptyBody,
              actions: [add],
            ),
          )
        else ...[
          StoreBody.block(_categories(context)),
          StoreBody.block(_apps(context)),
        ],
      ],
    );
  }

  Widget _categories(BuildContext context) {
    final t = context.strings.customApps;
    final categories = _c.categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          t.categoriesTitle,
          first: true,
          trailing: ActionButton.ghost(
            text: t.addCategoryButton,
            icon: FluentIcons.add_20_regular,
            size: ActionButtonSize.sm,
            onPressed: _locked
                ? null
                : () => showCustomAppCategoriesDialog(
                      context: context,
                      controller: _c,
                    ),
          ),
        ),
        if (categories.isEmpty)
          SectionEmptyNote(t.noCategoriesTitle, hint: t.noCategoriesHint)
        else
          RowsCard(
            children: [
              for (final category in categories)
                AppRow(
                  leading: const IconTile(
                    icon: FluentIcons.tag_20_regular,
                    size: IconTileSize.sm,
                    tone: IconTileTone.quiet,
                  ),
                  // שם הקטגוריה ותיאורה הם תוכן — לא מתורגמים.
                  title: category.name,
                  subtitle: category.description.isEmpty
                      ? t.categoryAppCount(_c.appsIn(category.slug).length)
                      : category.description,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIconButton(
                        icon: FluentIcons.edit_20_regular,
                        tooltip: t.editTooltip,
                        small: true,
                        onPressed: _locked
                            ? null
                            : () => showCustomAppCategoriesDialog(
                                  context: context,
                                  controller: _c,
                                  editing: category,
                                ),
                      ),
                      AppIconButton(
                        icon: FluentIcons.delete_20_regular,
                        tooltip: t.removeCategoryTooltip,
                        small: true,
                        danger: true,
                        onPressed: _locked
                            ? null
                            : () => confirmRemoveCustomAppCategory(
                                  context,
                                  _c,
                                  category,
                                ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _apps(BuildContext context) {
    final t = context.strings.customApps;
    final cs = Theme.of(context).colorScheme;
    final apps = _c.apps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(t.orderSectionTitle),
        RowsCard(
          children: [
            for (var i = 0; i < apps.length; i++) _appRow(context, apps, i),
          ],
        ),
        // מוצג רק כשיש מה לסדר.
        if (apps.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            t.orderHint,
            style: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _appRow(BuildContext context, List<CustomAppView> apps, int index) {
    final t = context.strings.customApps;
    final app = apps[index];
    final id = app.descriptor.id;
    final category = app.descriptor.categorySlugs.isEmpty
        ? t.uncategorizedItem
        : app.descriptor.categorySlugs.map(_c.categoryName).join(', ');

    Widget row({required Widget handle}) => AppRow(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(width: 6),
              StoreIcon(
                imagePath: _c.iconPathOf(app.descriptor),
                placeholderIcon: FluentIcons.box_20_regular,
                size: 32,
              ),
            ],
          ),
          // שם התוכנה הוא תוכן שהמשתמש כתב — לא מתורגם.
          title: app.descriptor.name,
          subtitle: '$category · ${customAppSourceLabel(context, app)}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ⚠️ חיצים אנכיים: RTL אינו הופך "למעלה" ו"למטה".
              AppIconButton(
                icon: FluentIcons.arrow_up_20_regular,
                tooltip: t.moveAppEarlierTooltip,
                small: true,
                onPressed: _locked || index == 0
                    ? null
                    : () => _moveOnto(id, apps[index - 1].descriptor.id),
              ),
              AppIconButton(
                icon: FluentIcons.arrow_down_20_regular,
                tooltip: t.moveAppLaterTooltip,
                small: true,
                onPressed: _locked || index == apps.length - 1
                    ? null
                    : () => _moveOnto(id, apps[index + 1].descriptor.id),
              ),
              AppIconButton(
                icon: FluentIcons.edit_20_regular,
                tooltip: t.editTooltip,
                small: true,
                onPressed: _locked
                    ? null
                    : () => openEditCustomApp(context, _c, app.entry),
              ),
              AppIconButton(
                icon: FluentIcons.delete_20_regular,
                tooltip: t.removeTooltip,
                small: true,
                danger: true,
                onPressed: _locked
                    ? null
                    : () => confirmRemoveCustomApp(context, _c, app),
              ),
            ],
          ),
        );

    return LayoutBuilder(
      key: ValueKey(id),
      builder: (context, constraints) {
        // הגרירה יושבת בידית בלבד: גרירה מכל השורה הייתה חוטפת את הגלילה.
        final handle = Draggable<String>(
          data: id,
          maxSimultaneousDrags: _locked || apps.length < 2 ? 0 : 1,
          onDragStarted: () => setState(() => _draggingId = id),
          onDragEnd: (_) => setState(() => _draggingId = null),
          feedback: Material(
            color: AppSurfaces.cardSelected(context),
            borderRadius: AppTokens.borderRadiusAll,
            child: SizedBox(
              width: constraints.maxWidth,
              child: row(handle: _handle(context, enabled: true)),
            ),
          ),
          child: _handle(context, enabled: !_locked && apps.length > 1),
        );
        return DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != id,
          onAcceptWithDetails: (details) => _moveOnto(details.data, id),
          builder: (context, candidates, _) => ColoredBox(
            color: candidates.isNotEmpty
                ? AppSurfaces.cardSelected(context)
                : Colors.transparent,
            child: Opacity(
              opacity: _draggingId == id ? 0.4 : 1,
              child: row(handle: handle),
            ),
          ),
        );
      },
    );
  }

  Widget _handle(BuildContext context, {required bool enabled}) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      child: Tooltip(
        message: context.strings.customApps.dragToReorderTooltip,
        child: Icon(
          FluentIcons.re_order_dots_vertical_20_regular,
          size: 20,
          color: enabled ? cs.outline : AppPalette.of(context).disabledText,
        ),
      ),
    );
  }

  /// מניח את [id] במקומו של [targetId] ברשימה המלאה, לפי מזהים.
  void _moveOnto(String id, String targetId) {
    // גרירה שהתחילה לפני שמירה קודמת עלולה לנחות בזמנה.
    if (_c.isBusy) return;
    final apps = _c.apps;
    final from = apps.indexWhere((a) => a.descriptor.id == id);
    final to = apps.indexWhere((a) => a.descriptor.id == targetId);
    if (from < 0 || to < 0) return;
    unawaited(_c.moveApp(from, to));
  }
}
