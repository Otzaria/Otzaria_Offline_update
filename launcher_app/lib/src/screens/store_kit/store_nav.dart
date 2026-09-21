import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import 'store_body.dart';
import 'store_visuals.dart';

/// ניווט הקטגוריות של מסך חנות — סרגל צד במסך רחב, שורת צ'יפים במסך צר.
/// זו הפריסה שבאתר התוספים: הקטגוריות הן הניווט הראשי.
///
/// הסרגל יושב **מחוץ** ל-`CustomScrollView` של התוכן (ראו [StoreBody])
/// ולכן הוא נשאר במקומו בזמן גלילה, כמו ה-`sticky` באתר.
///
/// הפריטים נמסרים מוכנים — מי שבונה אותם הוא שיודע מה הקטגוריות שלו
/// ואיך קוראים להן, וכאן נשארת הפריסה בלבד.

/// מעל הרוחב הזה מוצג סרגל הצד; מתחתיו — שורת צ'יפים אופקית.
const double kStoreSidebarBreakpoint = 1080;

const double _sidebarWidth = 232;

/// פריט ניווט אחד: קטגוריה, דף הבית או "הכול".
class StoreNavItem {
  const StoreNavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.count,
    this.tooltip,
    this.chipLabel,
    this.muted = false,
    this.separatorBefore = false,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  /// כמה פריטים בקטגוריה. `null` לפריט שאינו קטגוריה.
  final int? count;

  final String? tooltip;

  /// התווית בשורת הצ'יפים, כשהיא אינה "השם והמספר בסוגריים".
  final String? chipLabel;

  /// מוצנע — "כל הפריטים" בתחתית הסרגל, כמו באתר.
  final bool muted;

  /// קו מפריד מעליו.
  final bool separatorBefore;
}

class StoreSidebar extends StatelessWidget {
  const StoreSidebar({super.key, required this.title, required this.items});

  final String title;
  final List<StoreNavItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              title,
              style: TextStyle(
                fontSize: AppTokens.fontSM,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final item in items) ...[
            if (item.separatorBefore)
              Divider(
                height: AppTokens.spaceLG,
                color: theme.colorScheme.outlineVariant,
              ),
            _SidebarItem(item: item),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item});

  final StoreNavItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = item.active
        ? cs.onPrimaryContainer
        : (item.muted ? cs.onSurfaceVariant : cs.onSurface);

    final tile = Material(
      color: item.active ? cs.primaryContainer : Colors.transparent,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSM,
            vertical: 9,
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: foreground),
              const SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTokens.fontMD,
                    fontWeight: item.active ? FontWeight.bold : FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
              if (item.count != null)
                Text(
                  '${item.count}',
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

    final description = item.tooltip;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: description == null || description.isEmpty
          ? tile
          : Tooltip(message: description, child: tile),
    );
  }
}

/// שורת הקטגוריות למסך צר — המקבילה ל-`nav` האופקי שבאתר.
class StoreCategoryBar extends StatelessWidget {
  const StoreCategoryBar({super.key, required this.items});

  final List<StoreNavItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: StoreBody.horizontalPadding,
        vertical: AppTokens.spaceSM,
      ),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: AppTokens.spaceSM,
                ),
                child: StoreTagPill(
                  label: item.chipLabel ??
                      (item.count == null
                          ? item.label
                          : '${item.label} (${item.count})'),
                  active: item.active,
                  onTap: item.onTap,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
