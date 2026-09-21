import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';

/// ניווט הקטגוריות של חנות התוספים. הפריסה עצמה — סרגל צד או שורת
/// צ'יפים — היא של `store_kit`; כאן נקבע רק מה יש בה.

List<StoreNavItem> _items(BuildContext context, PluginsModuleController c) {
  final t = context.strings.plugins;

  return [
    StoreNavItem(
      label: t.storeHomeItem,
      chipLabel: t.storeHomeChip,
      icon: FluentIcons.home_24_regular,
      active: c.view == PluginStorePage.home,
      onTap: c.showHome,
    ),
    for (final category in c.categories)
      StoreNavItem(
        label: category.name,
        tooltip: category.description,
        count: category.pluginCount,
        icon: FluentIcons.puzzle_piece_24_regular,
        active: c.openCategorySlug == category.slug,
        onTap: () => c.showCategory(category.slug),
      ),
    // "כל התוספים" — מוצא אחרון, מוצנע בתחתית הסרגל, כמו באתר.
    StoreNavItem(
      label: t.allPluginsPage,
      chipLabel: t.allPluginsWithCount(c.plugins.length),
      count: c.plugins.length,
      icon: FluentIcons.apps_list_24_regular,
      active: c.view == PluginStorePage.all,
      muted: true,
      separatorBefore: true,
      onTap: c.showAllPlugins,
    ),
  ];
}

class PluginStoreSidebar extends StatelessWidget {
  const PluginStoreSidebar({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) => StoreSidebar(
        title: context.strings.plugins.categoriesTitle,
        items: _items(context, controller),
      );
}

class PluginStoreCategoryBar extends StatelessWidget {
  const PluginStoreCategoryBar({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) =>
      StoreCategoryBar(items: _items(context, controller));
}
