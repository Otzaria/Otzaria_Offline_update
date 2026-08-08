import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_store_body.dart';
import 'plugin_visuals.dart';

/// שורת החיפוש והסינון של החנות — חיפוש, סטטוס, מתג "רק לא-מותקן", ושורת
/// תגיות מתקפלת. פריסה של שדות בשורה אחת, כמו בחנות המקורית, ולא שורות
/// `SettingsActionTile`.
class PluginFiltersBar extends StatefulWidget {
  const PluginFiltersBar({
    super.key,
    required this.controller,
    required this.searchController,
  });

  final PluginsModuleController controller;
  final TextEditingController searchController;

  @override
  State<PluginFiltersBar> createState() => _PluginFiltersBarState();
}

class _PluginFiltersBarState extends State<PluginFiltersBar> {
  /// כמה תגיות מוצגות לפני "הצג עוד" — שתי שורות בקירוב.
  static const int _collapsedTagCount = 14;

  bool _allTagsShown = false;

  /// מעל הרוחב הזה שלושת הפקדים נכנסים לשורה אחת.
  static const double _singleRowWidth = 840;

  static const double _statusWidth = 180;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= _singleRowWidth
                      ? _wideRow()
                      : _narrowColumn(),
            ),
            _tagsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _wideRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _searchField()),
        const SizedBox(width: AppTokens.spaceMD),
        SizedBox(width: _statusWidth, child: _statusField()),
        const SizedBox(width: AppTokens.spaceMD),
        _installedToggle(),
      ],
    );
  }

  Widget _narrowColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField(),
        const SizedBox(height: AppTokens.spaceMD),
        _statusField(),
        const SizedBox(height: AppTokens.spaceMD),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: _installedToggle()),
      ],
    );
  }

  Widget _searchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PluginFieldLabel('חיפוש'),
        RtlTextField(
          controller: widget.searchController,
          onChanged: widget.controller.setSearch,
          decoration: const InputDecoration(
            border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
            prefixIcon: Icon(FluentIcons.search_24_regular),
            hintText: 'שם, תיאור או תגית...',
            isDense: true,
          ),
        ),
      ],
    );
  }

  static const Map<PluginStatusFilter, String> _statusLabels = {
    PluginStatusFilter.all: 'הכול',
    PluginStatusFilter.stable: 'יציב',
    PluginStatusFilter.beta: 'בטא',
    PluginStatusFilter.experimental: 'ניסיוני',
  };

  /// תפריט נפתח, לא `AppSegmentedControl` — כדי לשבת בשורה אחת עם שדה
  /// החיפוש בלי לתפוס יותר מקום ממנו.
  Widget _statusField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PluginFieldLabel('סטטוס'),
        DropdownButtonFormField<PluginStatusFilter>(
          initialValue: widget.controller.statusFilter,
          onChanged: (value) {
            if (value != null) widget.controller.setStatusFilter(value);
          },
          isDense: true,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          items: [
            for (final entry in _statusLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
        ),
      ],
    );
  }

  Widget _installedToggle() {
    final controller = widget.controller;
    final cs = Theme.of(context).colorScheme;
    final isOn = controller.hideInstalled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isOn ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: AppTokens.borderRadiusAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => controller.setHideInstalled(!isOn),
            mouseCursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD,
                vertical: 9,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeFocus(
                    child: CustomSwitch(
                      value: isOn,
                      onChanged: controller.setHideInstalled,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Text(
                    'הצג רק מה שלא מותקן / יש לו עדכון',
                    style: TextStyle(
                      fontSize: AppTokens.fontSM,
                      fontWeight: FontWeight.bold,
                      color: isOn ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'זוהו ${controller.installedCount} תוספים מותקנים באוצריא',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _tagsSection(BuildContext context) {
    final tags = widget.controller.allTags;
    if (tags.isEmpty) return const SizedBox.shrink();

    final hasMore = tags.length > _collapsedTagCount;
    final shown =
        _allTagsShown || !hasMore ? tags : tags.take(_collapsedTagCount);

    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              PluginTagPill(
                label: 'כל התגיות',
                active: widget.controller.tagFilter == null,
                onTap: () => widget.controller.setTagFilter(null),
              ),
              for (final tag in shown)
                PluginTagPill(
                  label: tag,
                  active: widget.controller.tagFilter == tag,
                  onTap: () => widget.controller.setTagFilter(tag),
                ),
            ],
          ),
          if (hasMore)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionButton.ghost(
                text: _allTagsShown ? 'הצג פחות' : 'הצג עוד',
                onPressed: () => setState(() => _allTagsShown = !_allTagsShown),
              ),
            ),
        ],
      ),
    );
  }
}
