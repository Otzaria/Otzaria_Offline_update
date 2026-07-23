import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// כרטיס מנוטרל עבור מודול שעדיין לא נבנה (plugins_manager) — מציג את
/// מקומו העתידי בדשבורד בלי לאפשר פעולה, עם תג "בקרוב".
class ComingSoonCard extends StatelessWidget {
  const ComingSoonCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.parchmentAlt, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.parchmentAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: textTheme.bodySmall),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.parchmentAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'בקרוב',
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
