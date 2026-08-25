import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/hebrew_date.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_visuals.dart';

/// כרטיס תוסף בודד ברשת החנות.
class PluginStoreCard extends StatelessWidget {
  const PluginStoreCard({
    super.key,
    required this.plugin,
    required this.controller,
    required this.onOpenDetail,
    required this.onSave,
    required this.onInstall,
    this.busy = false,
  });

  final StorePlugin plugin;
  final PluginsModuleController controller;
  final VoidCallback onOpenDetail;
  final VoidCallback onSave;
  final VoidCallback onInstall;
  final bool busy;

  /// תקציבי הגובה של שורות הגלולות. הם חלק מהחישוב של
  /// `_cardContentHeight` ב-`plugins_screen.dart` — שינוי כאן דורש שינוי שם.
  ///
  /// תקציב הגלולות **מוכפל ב-`textScale`**, כמו התקציב שבצד השני של
  /// המשוואה. כשהיה מספר קבוע הוא נגבה במלואו גם בהגדלה 0.9 (שבה התקציב
  /// הקטן ביותר) ובכל זאת חתך גלולות בהגדלה גדולה — הרע שבשני העולמות.
  static const double _badgesHeight = 52;
  static const double _tagsHeight = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installStatus = controller.statusOf(plugin);
    final target = controller.targetOf(plugin);
    final t = context.strings.plugins;

    return AppCard(
      onTap: onOpenDetail,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PluginThumbnail(
                    imagePath: controller.assetPath(plugin.imagePath)),
                if (plugin.isFeatured)
                  Positioned(
                    top: AppTokens.spaceSM,
                    right: AppTokens.spaceSM,
                    child: PluginBadge(
                      label: t.badgeFeaturedShort,
                      icon: FluentIcons.star_24_regular,
                      emphasized: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMD),
            // תקציב גובה לשתי שורות גלולות. הכרטיס ברשת הוא בגובה קבוע
            // (mainAxisExtent), ולכן `Wrap` שגולש לשורה נוספת — למשל עם
            // שבב "עדכון זמין (מותקן …)" בכרטיס צר — היה מגלישׂ את הכרטיס.
            // מה שנחתך הוא האחרון, ולכן גלולת הדירוג היא האחרונה: היא
            // קישוט, ושבב ההתקנה הוא מידע שאסור להיעלם.
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(_badgesHeight),
              child: Wrap(
                spacing: AppTokens.spaceXS,
                runSpacing: AppTokens.spaceXS,
                clipBehavior: Clip.hardEdge,
                children: [
                  PluginBadge(
                    label: pluginStatusLabel(target?.status ?? plugin.status),
                    emphasized: true,
                  ),
                  // הגרסה שתותקן כאן, לא בהכרח האחרונה שפורסמה — ראו
                  // `PluginsModuleController.versionOf`.
                  PluginBadge(
                    label: t.pluginVersionBadge(controller.versionOf(plugin)),
                  ),
                  PluginBadge(
                    label: '${plugin.downloadCount}',
                    icon: FluentIcons.arrow_download_24_regular,
                  ),
                  PluginInstallChip(status: installStatus, compact: true),
                  // כמו באתר: תוסף שטרם דורג אינו מציג גלולת דירוג ריקה.
                  if (plugin.ratingCount > 0) PluginRatingBadge(plugin: plugin),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              plugin.name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              plugin.shortDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (plugin.tags.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSM),
              // שורת תגיות אחת, מאותה סיבה. התגיות המלאות בעמוד התוסף.
              SizedBox(
                height: _tagsHeight,
                child: Wrap(
                  spacing: AppTokens.spaceXS,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final tag in plugin.tags.take(4))
                      PluginTagPill(label: tag),
                  ],
                ),
              ),
            ],
            const Spacer(),
            const SizedBox(height: AppTokens.spaceSM),
            Row(
              children: [
                Expanded(
                  child: ActionButton.neutral(
                    text: t.saveButton,
                    icon: FluentIcons.save_24_regular,
                    isLoading: busy,
                    onPressed: controller.hasFileFor(plugin) ? onSave : null,
                  ),
                ),
                // בלי בילד תואם אין מה להתקין — הכפתור כבוי, והשבב למעלה
                // אומר למה.
                if (target?.supportsDirectInstall ??
                    plugin.supportsDirectInstall) ...[
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: ActionButton.recommended(
                      text: t.installButton,
                      icon: FluentIcons.arrow_download_24_regular,
                      isLoading: busy,
                      onPressed: target == null ? null : onInstall,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: AppTokens.spaceSM),
            // שורת התחתית של הכרטיס באתר: "לפרטים מלאים" מול תאריך העדכון.
            Row(
              children: [
                Text(
                  t.cardDetailsLink,
                  style: TextStyle(
                    fontSize: AppTokens.fontSM,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    t.cardUpdatedOn(
                      HebrewDate.format(plugin.originalDate.isNotEmpty
                          ? plugin.originalDate
                          : plugin.updatedAt),
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
