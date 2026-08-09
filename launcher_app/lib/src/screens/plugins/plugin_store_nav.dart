import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_store_body.dart';
import 'plugin_visuals.dart';

/// ניווט הקטגוריות של החנות — סרגל צד במסך רחב, שורת צ'יפים במסך צר.
/// זו הפריסה שבאתר: הקטגוריות הן הניווט הראשי, ו"כל התוספים" מוצנע בסוף.
///
/// הסרגל יושב **מחוץ** ל-`CustomScrollView` של התוכן (ראו [PluginStoreBody])
/// ולכן הוא נשאר במקומו בזמן גלילה, כמו ה-`sticky` באתר.

/// מעל הרוחב הזה מוצג סרגל הצד; מתחתיו — שורת צ'יפים אופקית.
const double kStoreSidebarBreakpoint = 1080;

const double _sidebarWidth = 232;

class PluginStoreSidebar extends StatelessWidget {
  const PluginStoreSidebar({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.plugins;

    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        // הסרגל יושב בצד ה-start של התוכן, ולכן הקו המפריד הוא בקצה ה-end
        // שלו — ימין ב-LTR, שמאל ב-RTL.
        border: BorderDirectional(
          end: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: AppTokens.spaceMD,
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppTokens.spaceSM,
              bottom: AppTokens.spaceSM,
            ),
            child: Text(
              t.categoriesTitle,
              style: TextStyle(
                fontSize: AppTokens.fontSM,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _SidebarItem(
            label: t.storeHomeItem,
            icon: FluentIcons.home_24_regular,
            active: controller.view == PluginStorePage.home,
            onTap: controller.showHome,
          ),
          for (final category in controller.categories)
            _SidebarItem(
              label: category.name,
              tooltip: category.description,
              count: category.pluginCount,
              icon: FluentIcons.puzzle_piece_24_regular,
              active: controller.openCategorySlug == category.slug,
              onTap: () => controller.showCategory(category.slug),
            ),
          Divider(
            height: AppTokens.spaceLG,
            color: theme.colorScheme.outlineVariant,
          ),
          // "כל התוספים" — מוצא אחרון, מוצנע בתחתית הסרגל, כמו באתר.
          _SidebarItem(
            label: t.allPluginsPage,
            count: controller.plugins.length,
            icon: FluentIcons.apps_list_24_regular,
            active: controller.view == PluginStorePage.all,
            muted: true,
            onTap: controller.showAllPlugins,
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.count,
    this.tooltip,
    this.muted = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final String? tooltip;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = active
        ? cs.onPrimaryContainer
        : (muted ? cs.onSurfaceVariant : cs.onSurface);

    final item = Material(
      color: active ? cs.primaryContainer : Colors.transparent,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSM,
            vertical: 9,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontMD,
                    fontWeight: active ? FontWeight.bold : FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: AppTokens.fontSM,
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final description = tooltip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: description == null || description.isEmpty
          ? item
          : Tooltip(message: description, child: item),
    );
  }
}

/// שורת הקטגוריות למסך צר — המקבילה ל-`nav` האופקי שבאתר.
class PluginStoreCategoryBar extends StatelessWidget {
  const PluginStoreCategoryBar({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.plugins;

    return Container(
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PluginStoreBody.horizontalPadding,
        vertical: AppTokens.spaceSM,
      ),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _BarChip(
              label: t.storeHomeChip,
              active: controller.view == PluginStorePage.home,
              onTap: controller.showHome,
            ),
            for (final category in controller.categories)
              _BarChip(
                label: '${category.name} (${category.pluginCount})',
                active: controller.openCategorySlug == category.slug,
                onTap: () => controller.showCategory(category.slug),
              ),
            _BarChip(
              label: t.allPluginsWithCount(controller.plugins.length),
              active: controller.view == PluginStorePage.all,
              onTap: controller.showAllPlugins,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppTokens.spaceSM),
      child: PluginTagPill(label: label, active: active, onTap: onTap),
    );
  }
}
