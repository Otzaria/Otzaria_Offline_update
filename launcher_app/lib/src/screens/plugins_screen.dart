import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// סינון רשימת התוספים (תכנון §7.3).
enum PluginFilter { all, installed, updateAvailable, notInstalled }

/// מסך התוספים. המודול עצמו (`plugins_manager`) עוד לא נבנה — המסך מציג את
/// הפריסה ואת מצב הריק האמיתי, בלי לנחש תוספים לפי שמות תיקיות.
class PluginsScreen extends StatefulWidget {
  const PluginsScreen({super.key});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  final TextEditingController _search = TextEditingController();
  PluginFilter _filter = PluginFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'עדכון תוספים',
      description: 'הזיהוי יתבסס על מנגנון התוספים של אוצריא עצמה, '
          'ולא על ניחוש לפי שמות תיקיות.',
      children: [
        _searchCard(context),
        _emptyStateCard(context),
        _plannedActionsCard(context),
      ],
    );
  }

  Widget _searchCard(BuildContext context) {
    return SettingsCard(
      title: 'חיפוש וסינון',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: RtlTextField(
            controller: _search,
            enabled: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(
                borderRadius: AppTokens.borderRadiusAll,
              ),
              prefixIcon: Icon(FluentIcons.search_24_regular),
              labelText: 'חיפוש תוסף',
              hintText: 'יהיה פעיל כשקטלוג התוספים יחובר',
            ),
          ),
        ),
        SettingsActionTile.segmentedTile<PluginFilter>(
          icon: FluentIcons.filter_24_regular,
          title: 'הצגה',
          currentValue: _filter,
          onChanged: (value) => setState(() => _filter = value),
          options: const [
            SegmentOption(value: PluginFilter.all, label: 'הכל'),
            SegmentOption(value: PluginFilter.installed, label: 'מותקן'),
            SegmentOption(
              value: PluginFilter.updateAvailable,
              label: 'עדכון זמין',
            ),
            SegmentOption(
              value: PluginFilter.notInstalled,
              label: 'לא מותקן',
            ),
          ],
        ),
      ],
    );
  }

  Widget _emptyStateCard(BuildContext context) {
    final theme = Theme.of(context);

    return SettingsCard(
      title: 'תוספים',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMD,
            vertical: AppTokens.spaceXL,
          ),
          child: Column(
            children: [
              Icon(
                FluentIcons.puzzle_piece_24_regular,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppTokens.spaceMD),
              Text(
                'אין עדיין רשימת תוספים',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTokens.spaceSM),
              Text(
                'לפני שניתן להציג תוספים יש להכריע בחוזה התוסף: מזהה, '
                'גרסה, קבצים, תלויות ומקור אמון. עד אז המסך לא ימציא '
                'נתונים שאינם קיימים.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _plannedActionsCard(BuildContext context) {
    return const SettingsCard(
      title: 'פעולות מתוכננות',
      subtitle: 'הכפתורים מושבתים עד שהמודול ייבנה.',
      children: [
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: 'עדכון כל המותקנים',
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: null,
            ),
            ActionButton.neutral(
              text: 'התקנת תוסף חדש',
              icon: FluentIcons.add_24_regular,
              onPressed: null,
            ),
            ActionButton.ghost(
              text: 'הורדת כל התוספים לחבילה',
              icon: FluentIcons.arrow_download_24_regular,
              onPressed: null,
            ),
          ],
        ),
      ],
    );
  }
}
