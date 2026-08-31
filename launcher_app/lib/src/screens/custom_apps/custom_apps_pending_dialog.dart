import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// גובה מרבי לרשימה; הכותרת וההסבר נשארים מחוץ לגליל כדי שלא ייעלמו בו.
const double _listMaxHeight = 300;

/// הודעת "יש תוכנות שממתינות על הכונן" — נפתחת בכניסה למסך התוכנות
/// הנוספות, ורק על תוכנה שעוד לא הוכרזה **במחשב הזה** (`markAnnounced`).
///
/// **הודעה בלבד.** ההתקנה נשארת בכרטיס שבמסך: היא יכולה לפתוח אשף, לשאול
/// לאן להעתיק קובץ נייד ולהמשיך בלמידה של עד דקה — וכל אלה לא שייכים
/// לחלון שכל תפקידו לומר מה יש.
Future<void> showCustomAppsPendingDialog({
  required BuildContext context,
  required List<CustomAppView> pending,
}) =>
    showSingleActionDialog(
      context: context,
      title: context.strings.customApps.pendingDialogTitle(pending.length),
      confirmText: context.strings.common.close,
      customContent: _PendingList(pending: pending),
    );

class _PendingList extends StatelessWidget {
  const _PendingList({required this.pending});

  final List<CustomAppView> pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.customApps;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: Text(
              t.pendingDialogIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _listMaxHeight),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final app in pending) _row(context, app)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, CustomAppView app) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: AppCard(
        padding: const EdgeInsets.all(AppTokens.spaceSM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // שם התוכנה הוא תוכן שהמשתמש כתב — אינו מתורגם.
            Text(
              app.descriptor.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              _rowLabel(context, app),
              style: TextStyle(
                fontSize: AppTokens.fontSM,
                color: theme.colorScheme.tertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "עוד לא הותקנה כאן" ו"יש חדשה יותר" אינם אותו דבר, ולכן אינם אותה
  /// שורה — ראו [CustomAppPending].
  String _rowLabel(BuildContext context, CustomAppView app) {
    final t = context.strings.customApps;
    final stored = app.storedInstaller!.version;

    return switch (app.pending) {
      CustomAppPending.newerOnDrive => t.pendingDialogUpdateRow(
          app.installed?.version ?? '?',
          stored,
        ),
      _ => t.pendingDialogNotInstalledRow(stored),
    };
  }
}
