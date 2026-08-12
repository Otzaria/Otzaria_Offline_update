import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// המרווח בין שתי מסירות רצופות ב"עדכון הכל".
///
/// כל מסירה היא `otzaria://plugin/install-local` אל אוצריא. כשהיא סגורה,
/// המסירה הראשונה מפעילה אותה — ומסירה שנייה שמגיעה לפני שהמופע הראשון
/// תפס את נעילת המופע היחיד הייתה פותחת מופע נוסף.
const Duration pluginUpdateDeliverySpacing = Duration(milliseconds: 1500);

/// גובה מרבי לרשימת התוספים בדיאלוג; הכותרת, "עדכון הכל" וההערה נשארים
/// מחוץ לגליל כדי שלא ייעלמו בגלילה.
const double _listMaxHeight = 300;

/// הודעת "יש עדכונים זמינים" — נפתחת בכניסה למסך, וגם בלחיצה על שבב
/// העדכונים שבשורה העליונה.
///
/// מחזיר את ה-id של התוסף שהמשתמש בחר לפתוח, או `null` אם רק סגר. הבחירה
/// נאספת למשתנה מקומי כי `showSingleActionDialog` (הרכיב המותר לדיאלוגים)
/// אינו מחזיר ערך משלו.
Future<String?> showPluginUpdatesDialog({
  required BuildContext context,
  required PluginsModuleController controller,
  required List<StorePlugin> updatable,
}) async {
  String? selected;

  await showSingleActionDialog(
    context: context,
    title: context.strings.plugins.updatesDialogTitle(updatable.length),
    confirmText: context.strings.common.close,
    customContent: _PluginUpdatesList(
      controller: controller,
      updatable: updatable,
      onOpenDetail: (id) => selected = id,
    ),
  );

  return selected;
}

/// רשימת התוספים שממתינים לעדכון, עם כפתור עדכון לכל אחד ו"עדכון הכל".
///
/// הרשימה עצמה היא תצלום המצב שנמסר בפתיחה, אבל מצב כל שורה נקרא **חי**
/// מהקונטרולר: המסירה לאוצריא אינה ההתקנה, וסריקה מחדש היא הדבר היחיד
/// שיודע מה כבר עודכן שם.
class _PluginUpdatesList extends StatefulWidget {
  const _PluginUpdatesList({
    required this.controller,
    required this.updatable,
    required this.onOpenDetail,
  });

  final PluginsModuleController controller;
  final List<StorePlugin> updatable;
  final ValueChanged<String> onOpenDetail;

  @override
  State<_PluginUpdatesList> createState() => _PluginUpdatesListState();
}

class _PluginUpdatesListState extends State<_PluginUpdatesList> {
  /// תוספים שהמסירה שלהם לאוצריא הצליחה בהרצה הזו.
  final Set<String> _sent = {};

  /// התוסף שהמסירה שלו רצה כרגע, ו"עדכון הכל" שרץ כרגע.
  String? _busyId;
  bool _updatingAll = false;

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

  /// האם אוצריא כבר מדווחת על הגרסה החדשה — כלומר העדכון הושלם שם.
  bool _isDone(StorePlugin plugin) =>
      widget.controller.statusOf(plugin) == PluginInstallStatus.upToDate;

  /// שורות שעדיין יש מה לעשות בהן דרך הכפתור.
  List<StorePlugin> get _pending => [
        for (final plugin in widget.updatable)
          if (plugin.supportsDirectInstall &&
              !_sent.contains(plugin.id) &&
              !_isDone(plugin))
            plugin,
      ];

  Future<void> _install(StorePlugin plugin) async {
    setState(() => _busyId = plugin.id);
    final result = await widget.controller.directInstall(plugin);
    if (!mounted) return;

    setState(() {
      _busyId = null;
      if (result.success) _sent.add(plugin.id);
    });
    if (!result.success) {
      UiSnack.showError(
        result.error ?? context.strings.plugins.installFailedSnack,
      );
    }
  }

  Future<void> _updateAll() async {
    setState(() => _updatingAll = true);

    var first = true;
    for (final plugin in _pending) {
      if (!mounted) break;
      if (!first) await Future<void>.delayed(pluginUpdateDeliverySpacing);
      first = false;
      await _install(plugin);
    }

    if (mounted) setState(() => _updatingAll = false);
  }

  void _openDetail(StorePlugin plugin) {
    widget.onOpenDetail(plugin.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.plugins;
    final pending = _pending;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: Text(
              t.updatesDialogIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // נשאר גלוי גם כשנותר פריט אחד — אחרת הכפתור נעלם באמצע ריצה.
          if (pending.length > 1 || _updatingAll)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
              child: ActionButton.recommended(
                text: t.updatesDialogUpdateAllButton(pending.length),
                icon: FluentIcons.arrow_download_24_regular,
                isLoading: _updatingAll,
                onPressed:
                    _busyId == null ? () => unawaited(_updateAll()) : null,
              ),
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _listMaxHeight),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final plugin in widget.updatable)
                      _row(context, plugin),
                  ],
                ),
              ),
            ),
          ),
          if (_sent.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              t.updatesDialogPendingNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            ActionButton.neutral(
              text: t.updatesDialogRecheckButton,
              icon: FluentIcons.arrow_clockwise_24_regular,
              onPressed: () => unawaited(widget.controller.refreshInstalled()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, StorePlugin plugin) {
    final theme = Theme.of(context);
    final t = context.strings.plugins;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: AppCard(
        onTap: () => _openDetail(plugin),
        padding: const EdgeInsets.all(AppTokens.spaceSM),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppTokens.spaceXS),
                  Text(
                    t.updatesDialogRow(
                      widget.controller.installedVersionOf(plugin) ?? '?',
                      plugin.version,
                    ),
                    style: TextStyle(
                      fontSize: AppTokens.fontSM,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.spaceSM),
            _rowAction(context, plugin),
          ],
        ),
      ),
    );
  }

  /// הפעולה שבקצה השורה. שלושת המצבים אינם זהים: "עודכן" הוא מה שאוצריא
  /// מדווחת, "נשלח" הוא מה ש**אנחנו** מסרנו לה וטרם אושר בסריקה.
  Widget _rowAction(BuildContext context, StorePlugin plugin) {
    final t = context.strings.plugins;

    if (_isDone(plugin)) {
      return StatusChip(
        kind: StatusKind.ok,
        label: t.updatesDialogDoneLabel,
      );
    }
    if (_sent.contains(plugin.id)) {
      return StatusChip(
        kind: StatusKind.working,
        label: t.updatesDialogSentLabel,
      );
    }
    if (!plugin.supportsDirectInstall) {
      return ActionButton.ghost(
        text: t.updatesDialogDetailsButton,
        onPressed: () => _openDetail(plugin),
      );
    }

    final busy = _busyId != null || _updatingAll;
    return ActionButton.recommended(
      text: t.updatesDialogUpdateButton,
      icon: FluentIcons.arrow_download_24_regular,
      isLoading: _busyId == plugin.id,
      onPressed: busy ? null : () => unawaited(_install(plugin)),
    );
  }
}
