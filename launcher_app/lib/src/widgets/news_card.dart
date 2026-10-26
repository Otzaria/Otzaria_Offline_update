import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../theme/theme_exports.dart';
import 'whats_new_view.dart';

/// רשימת "מה חדש" (`.news`) בכרטיס: נקודה בצבע הזוהר לפני כל שורה.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.items, this.footer});

  final List<String> items;

  /// מתחת לרשימה — למשל כפתור "הרשימה המלאה".
  final Widget? footer;

  @override
  Widget build(BuildContext context) => _NewsFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items) NewsBullet(item),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      );
}

/// הערות גרסה ב-Markdown: רשימת נקודות פשוטה מוצגת כ-[NewsCard], וכל
/// מבנה אחר כ-Markdown מלא. בלי הערות לא מציגים כלום — גם לא את הכותרת.
class ReleaseNotesCard extends StatelessWidget {
  const ReleaseNotesCard({super.key, required this.markdown});

  final String? markdown;

  static bool hasNotes(String? markdown) => markdown?.trim().isNotEmpty == true;

  static final _bullet = RegExp(r'^[*\-+]\s+(.*)$');

  /// השורות, אם כל ההערות הן רשימת נקודות אחת; אחרת `null`.
  static List<String>? bulletsOf(String markdown) {
    final items = <String>[];
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = _bullet.firstMatch(line);
      if (match == null) return null;
      items.add(match.group(1)!.replaceAll('**', '').trim());
    }
    return items.isEmpty ? null : items;
  }

  @override
  Widget build(BuildContext context) {
    final data = markdown?.trim() ?? '';
    if (data.isEmpty) return const SizedBox.shrink();
    final bullets = bulletsOf(data);
    if (bullets != null) return NewsCard(items: bullets);
    return _NewsFrame(
      child: MarkdownBody(data: data, styleSheet: whatsNewStyleSheet(context)),
    );
  }
}

class _NewsFrame extends StatelessWidget {
  const _NewsFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppSurfaces.card(context),
          borderRadius: AppTokens.borderRadiusAll,
        ),
        child: child,
      );
}

/// שורה ברשימה: נקודה בצבע הזוהר ואחריה הטקסט — אותה צורה בכל רשימה בכלי.
class NewsBullet extends StatelessWidget {
  const NewsBullet(this.text, {super.key, this.style});

  final String text;

  /// ברירת המחדל — גוף הטקסט בצבע הראשי.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              color: AppPalette.of(context).glow,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: style ?? AppTextStyles.body.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
