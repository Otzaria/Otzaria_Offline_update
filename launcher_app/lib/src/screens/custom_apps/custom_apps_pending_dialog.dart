import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_install_action.dart';

/// גובה מרבי לרשימה; הכותרת וההסבר נשארים מחוץ לגליל כדי שלא ייעלמו בו.
const double _listMaxHeight = 300;

/// הודעת "יש תוכנות שממתינות על הכונן" — נפתחת בכניסה למסך התוכנות
/// הנוספות, ורק על תוכנה שעוד לא הוכרזה **במחשב הזה** (`markAnnounced`).
///
/// לכל שורה כפתור התקנה, כדי שלא יהיה צריך לסגור את החלון ולחפש את
/// הכרטיס — זו אותה התקנה בדיוק, דרך [installCustomApp].
Future<void> showCustomAppsPendingDialog({
  required BuildContext context,
  required CustomAppsController controller,
  required List<CustomAppView> pending,
}) =>
    showSingleActionDialog(
      context: context,
      title: context.strings.customApps.pendingDialogTitle(pending.length),
      confirmText: context.strings.common.close,
      customContent: _PendingList(controller: controller, pending: pending),
    );

class _PendingList extends StatefulWidget {
  const _PendingList({required this.controller, required this.pending});

  final CustomAppsController controller;
  final List<CustomAppView> pending;

  @override
  State<_PendingList> createState() => _PendingListState();
}

class _PendingListState extends State<_PendingList> {
  /// התוכנות שההתקנה שלהן הצליחה בחלון הזה, והתוכנה שמותקנת כרגע.
  final Set<String> _installed = {};
  String? _busyId;

  /// שורת הלמידה שאחרי ההתקנה נקראת מהקונטרולר, ולכן צריך להאזין לו.
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

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
                  children: [
                    for (final app in widget.pending) _row(context, app),
                  ],
                ),
              ),
            ),
          ),
          // הלמידה שאחרי ההתקנה יכולה להימשך עד דקה — ראו `InstallLearner`.
          // בלי השורה הזו זה נראה כתקיעה.
          if (widget.controller.isLearning) ...[
            const SizedBox(height: AppTokens.spaceSM),
            InfoProgressRow(stage: t.learningLabel),
          ],
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
        child: Row(
          children: [
            Expanded(
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
            const SizedBox(width: AppTokens.spaceSM),
            _rowAction(context, app),
          ],
        ),
      ),
    );
  }

  /// הפעולה שבקצה השורה: כפתור התקנה, ואחרי שההתקנה הצליחה — שבב במקומו.
  Widget _rowAction(BuildContext context, CustomAppView app) {
    final id = app.descriptor.id;
    if (_installed.contains(id)) {
      return StatusChip(
        kind: StatusKind.ok,
        label: context.strings.customApps.pendingDialogInstalledLabel,
      );
    }

    return ActionButton.recommended(
      text: context.strings.common.install,
      icon: FluentIcons.desktop_arrow_right_24_regular,
      isLoading: _busyId == id,
      onPressed: _busyId == null ? () => unawaited(_install(app)) : null,
    );
  }

  Future<void> _install(CustomAppView app) async {
    final id = app.descriptor.id;
    setState(() => _busyId = id);

    final ok = await installCustomApp(
      context: context,
      controller: widget.controller,
      app: app,
    );
    if (!mounted) return;

    setState(() {
      _busyId = null;
      if (ok) _installed.add(id);
    });
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
