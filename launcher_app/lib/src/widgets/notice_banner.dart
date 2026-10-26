import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// notice — כרטיס; warning — על רקע אזהרה; banner — פס tonal;
/// inCard — רקע של קטע-משנה, כדי שלא תיבלע בכרטיס.
enum NoticeKind { notice, warning, banner, inCard }

/// הודעה קבועה בדף: אריח (או לוגו), כותרת, פירוט ופעולות בקצה.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.leading,
    required this.title,
    this.body,
    this.actions = const [],
    this.kind = NoticeKind.notice,
    this.below,
  });

  final Widget leading;
  final String title;
  final String? body;
  final List<Widget> actions;
  final NoticeKind kind;

  /// מתחת לפירוט — למשל נתיב, שאינו חלק מהמשפט.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        context,
        // צר: הפעולות יורדות מתחת לפירוט, ולא דוחסות אותו לעמודה צרה.
        stacked: actions.isNotEmpty && constraints.maxWidth < 560,
      ),
    );
  }

  Widget _build(BuildContext context, {required bool stacked}) {
    final cs = Theme.of(context).colorScheme;
    final banner = kind == NoticeKind.banner;
    final background = switch (kind) {
      NoticeKind.notice => AppSurfaces.card(context),
      NoticeKind.warning => AppSurfaces.warningNotice(context),
      NoticeKind.banner => AppSurfaces.banner(context),
      NoticeKind.inCard => AppSurfaces.panelSection(context),
    };
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: banner
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        // הודעה עם כפתור: הכפתור באמצע הגובה, לא צמוד לשורה הראשונה.
        crossAxisAlignment: !stacked && (banner || actions.isNotEmpty)
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.rowTitle.copyWith(color: cs.onSurface),
                ),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    body!,
                    style: AppTextStyles.rowSub.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (below != null) ...[const SizedBox(height: 6), below!],
                if (stacked) ...[const SizedBox(height: 10), buttons],
              ],
            ),
          ),
          if (actions.isNotEmpty && !stacked) ...[
            const SizedBox(width: 14),
            buttons,
          ],
        ],
      ),
    );
  }
}
