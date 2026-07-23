import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// מצב תצוגה של כרטיס מודול בדשבורד.
enum ModuleStatus { loading, upToDate, updateAvailable, updating, error, needsAction }

/// כרטיס אחיד להצגת מודול בדשבורד (אוצריא עצמה / מסד הספרייה): שם,
/// תת-כותרת (גרסה נוכחית/זמינה), "פס כריכה" צבעוני בצד לפי סטטוס, ופעולה
/// ראשית אחת (בדוק/עדכן/הפעל).
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    this.statusLabel,
    this.progress,
    this.stageText,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.errorMessage,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ModuleStatus status;
  final String? statusLabel;

  /// 0..1 עבור מד התקדמות מדויק, null עבור מד לא-קבוע (indeterminate).
  final double? progress;
  final String? stageText;

  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final String? errorMessage;

  Color get _stripeColor {
    switch (status) {
      case ModuleStatus.upToDate:
        return AppColors.success;
      case ModuleStatus.updateAvailable:
        return AppColors.gold;
      case ModuleStatus.updating:
        return AppColors.ink;
      case ModuleStatus.error:
      case ModuleStatus.needsAction:
        return AppColors.danger;
      case ModuleStatus.loading:
        return AppColors.parchmentAlt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.parchmentAlt, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: _stripeColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.parchment,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: AppColors.ink, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: textTheme.titleLarge),
                              const SizedBox(height: 2),
                              Text(subtitle, style: textTheme.bodySmall),
                            ],
                          ),
                        ),
                        if (status == ModuleStatus.loading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppColors.textSecondary),
                            ),
                          )
                        else if (statusLabel != null)
                          _StatusChip(label: statusLabel!, color: _stripeColor),
                      ],
                    ),
                    if (status == ModuleStatus.updating) ...[
                      const SizedBox(height: 16),
                      if (stageText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(stageText!, style: textTheme.bodySmall),
                        ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: AppColors.parchmentAlt,
                          valueColor: const AlwaysStoppedAnimation(AppColors.ink),
                        ),
                      ),
                    ],
                    if (status == ModuleStatus.error && errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        style: textTheme.bodySmall?.copyWith(color: AppColors.danger),
                      ),
                    ],
                    if (onPrimaryAction != null || onSecondaryAction != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (onSecondaryAction != null)
                            TextButton(
                              onPressed: onSecondaryAction,
                              child: Text(secondaryActionLabel ?? ''),
                            ),
                          const Spacer(),
                          if (onPrimaryAction != null)
                            ElevatedButton(
                              onPressed: onPrimaryAction,
                              child: Text(primaryActionLabel ?? ''),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
