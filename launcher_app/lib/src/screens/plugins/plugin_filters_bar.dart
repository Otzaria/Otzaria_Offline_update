import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_store_body.dart';
import 'plugin_visuals.dart';

/// שורת החיפוש והסינון של "כל התוספים" — חיפוש, סטטוס ושורת תגיות מתקפלת.
/// פריסה של שדות בשורה אחת, כמו בחנות המקורית, ולא שורות
/// `SettingsActionTile`.
///
/// מוצגת **רק** במסך "כל התוספים", בדיוק כמו `/plugins/all` באתר: דף הבית
/// ודף הקטגוריה מציגים אצירה ואין בהם סינון. הקטגוריות אינן כאן אלא בסרגל
/// הצד — הן הניווט הראשי, והתגיות סינון משני בתוך הרשימה השטוחה.
///
/// מתג "רק מה שלא מותקן" גם הוא אינו כאן אלא בשורת הסנכרון שבראש המסך:
/// הוא תוספת של הלאנצ'ר (אין לו מקבילה באתר) והוא חל על **כל** מסכי החנות.
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
          const PluginFieldLabel('תגיות'),
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
