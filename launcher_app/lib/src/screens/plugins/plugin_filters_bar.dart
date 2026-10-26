import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'plugin_visuals.dart';

/// מעל הרשימה: חיפוש ובורר "הכול / מותקנים / לא מותקנים", שבבי הקטגוריות,
/// ו"עוד סינון" מקופל (יציבות ותגיות).
class PluginFiltersBar extends StatefulWidget {
  const PluginFiltersBar({
    super.key,
    required this.controller,
    required this.searchController,
  });

  final PluginsModuleController controller;

  /// בבעלות המסך: הטקסט שהוקלד נשמר גם כשהבר נבנה מחדש.
  final TextEditingController searchController;

  @override
  State<PluginFiltersBar> createState() => _PluginFiltersBarState();
}

/// מעל מספר התגיות הזה הרשימה מתקפלת — כמו `TagFilterChips` באתר.
const int _collapsedTagCount = 14;

class _PluginFiltersBarState extends State<PluginFiltersBar> {
  bool _moreOpen = false;
  bool _allTagsShown = false;

  PluginsModuleController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    // מסנן שנבחר קודם (תגית מדף הפרטים) — "עוד סינון" נפתח כדי שייראה.
    _moreOpen = _c.moreFiltersCount > 0;
  }

  @override
  void didUpdateWidget(PluginFiltersBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_c.moreFiltersCount > 0) _moreOpen = true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolRow(context),
        const SizedBox(height: 12),
        AppDropdownField<PluginSortMode>(
          value: _c.sortMode,
          entries: [
            AppMenuEntry(
                value: PluginSortMode.recommended,
                label: context.strings.plugins.sortRecommended),
            AppMenuEntry(
                value: PluginSortMode.newest,
                label: context.strings.plugins.sortNewest),
            AppMenuEntry(
                value: PluginSortMode.updated,
                label: context.strings.plugins.sortUpdated),
          ],
          onSelected: _c.setSortMode,
        ),
        if (_c.shownCategories.isNotEmpty) ...[
          const SizedBox(height: 12),
          _categories(context),
        ],
        const SizedBox(height: 8),
        _moreFilters(context),
      ],
    );
  }

  Widget _toolRow(BuildContext context) {
    final t = context.strings.plugins;
    final cs = Theme.of(context).colorScheme;
    final search = ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.searchController,
      builder: (context, value, _) => RtlTextField(
        controller: widget.searchController,
        onChanged: _c.setSearch,
        decoration: InputDecoration(
          hintText: t.searchHint,
          constraints: const BoxConstraints(
            minHeight: AppTokens.buttonHeight,
            maxHeight: AppTokens.buttonHeight,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          prefixIcon: Icon(
            FluentIcons.search_20_regular,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : AppIconButton(
                  icon: FluentIcons.dismiss_20_regular,
                  tooltip: t.clearSearchTooltip,
                  small: true,
                  onPressed: () {
                    widget.searchController.clear();
                    _c.setSearch('');
                  },
                ),
        ),
      ),
    );
    final filter = AppSegmentedControl<PluginInstallFilter>(
      options: [
        SegmentOption(value: PluginInstallFilter.all, label: t.filterAll),
        SegmentOption(
          value: PluginInstallFilter.installed,
          label: t.filterInstalled,
        ),
        SegmentOption(
          value: PluginInstallFilter.notInstalled,
          label: t.filterNotInstalled,
        ),
      ],
      currentValue: _c.installFilter,
      onChanged: _c.setInstallFilter,
      height: AppTokens.buttonHeight,
    );
    // הבורר גדל עם הטקסט, ולכן גם הרוחב שממנו הוא נכנס לצד החיפוש.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [search, const SizedBox(height: 12), filter],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            filter,
          ],
        );
      },
    );
  }

  Widget _categories(BuildContext context) {
    final t = context.strings.plugins;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StoreCategoryChip(
          label: t.filterAll,
          count: _c.plugins.length,
          selected: _c.categoryFilter == null,
          onTap: () => _c.setCategory(null),
        ),
        for (final category in _c.shownCategories)
          Tooltip(
            message: category.description,
            child: StoreCategoryChip(
              label: category.name,
              count: _c.pluginsIn(category).length,
              selected: _c.categoryFilter == category.slug,
              onTap: () => _c.setCategory(category.slug),
            ),
          ),
      ],
    );
  }

  Widget _moreFilters(BuildContext context) {
    final t = context.strings.plugins;
    final cs = Theme.of(context).colorScheme;
    final count = _c.moreFiltersCount;
    final head = Semantics(
      expanded: _moreOpen,
      child: FocusRing(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => setState(() => _moreOpen = !_moreOpen),
            borderRadius: AppTokens.borderRadiusAll,
            overlayColor: AppSurfaces.stateLayer(cs.primary),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.filter_20_regular,
                    size: 18,
                    color: cs.outline,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    count == 0 ? t.moreFilters : t.moreFiltersCount(count),
                    style: AppTextStyles.rowTitle.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _moreOpen ? 0.5 : 0,
                    duration: AppTokens.animFast,
                    child: Icon(
                      FluentIcons.chevron_down_20_regular,
                      size: 18,
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!_moreOpen) return head;

    final tags = _c.allTags;
    final hasMore = tags.length > _collapsedTagCount;
    final selectedTag = _c.tagFilter;
    // תגית שנבחרה נשארת גלויה גם כשהרשימה מקופלת — אחרת המסנן פעיל ובלתי נראה.
    final shownTags = _allTagsShown || !hasMore
        ? tags
        : [
            ...tags.take(_collapsedTagCount),
            if (selectedTag != null &&
                !tags.take(_collapsedTagCount).contains(selectedTag))
              selectedTag,
          ];
    final label = AppTextStyles.small.copyWith(color: cs.onSurfaceVariant);

    Widget line(String title, List<Widget> chips) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(title, style: label),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        const SizedBox(height: 4),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(t.filterStatusLabel, [
                for (final status in PluginStatusFilter.values)
                  StoreFilterChip(
                    label: status == PluginStatusFilter.all
                        ? t.filterAll
                        : pluginStatusLabel(status.name),
                    selected: _c.statusFilter == status,
                    onTap: () => _c.setStatusFilter(status),
                  ),
              ]),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                line(t.filterTagsLabel, [
                  for (final tag in shownTags)
                    StoreFilterChip(
                      label: tag,
                      selected: _c.tagFilter == tag,
                      onTap: () =>
                          _c.setTagFilter(_c.tagFilter == tag ? null : tag),
                    ),
                  if (hasMore)
                    ActionButton.ghost(
                      text: _allTagsShown ? t.showFewerTags : t.showMoreTags,
                      size: ActionButtonSize.sm,
                      onPressed: () =>
                          setState(() => _allTagsShown = !_allTagsShown),
                    ),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
