import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_detail_view.dart';
import 'plugin_filters_bar.dart';
import 'plugin_store_body.dart';
import 'plugin_store_card.dart';
import 'plugin_sync_overlay.dart';
import 'plugin_updates_dialog.dart';

/// מסך חנות התוספים — רשימה ועמוד פרטים, שניהם מעל אותו קטלוג מקומי.
///
/// המסך נטען מהמראה בלבד; "סנכרון מהאתר" הוא הפעולה היחידה שדורשת
/// אינטרנט, והיא תמיד יזומה בלחיצה.
class PluginsScreen extends StatefulWidget {
  const PluginsScreen({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

/// גובה כל מה שאינו התמונה בכרטיס — ראו החישוב ב-[_PluginsScreenState._grid].
const double _cardContentHeight = 290;

/// הרוחב המינימלי של כרטיס ברשת. מספר העמודות נגזר ממנו, כמו
/// `minmax(300px, 1fr)` ב-CSS של החנות המקורית.
const double _minCardWidth = 300;

class _PluginsScreenState extends State<PluginsScreen> {
  final TextEditingController _search = TextEditingController();

  /// ה-id של התוסף שפרטיו מוצגים, או null כשמוצגת הרשימה.
  String? _selectedId;

  /// ה-id של התוסף שכרגע רצה עליו פעולה (שמירה / התקנה).
  String? _busyId;

  /// הודעת העדכונים מוצגת פעם אחת בכל הרצה, לא בכל טעינה מחדש.
  bool _updatesDialogShown = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    // הטעינה עצמה נעשית ב-AppShell, כמו לשאר המודולים; כאן רק מגיבים לה.
    _announceUpdatesIfNeeded();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _search.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
    _announceUpdatesIfNeeded();
  }

  /// מציג את הודעת "יש עדכונים זמינים" בפעם הראשונה שהקטלוג נטען בהצלחה.
  void _announceUpdatesIfNeeded() {
    if (_updatesDialogShown) return;
    if (widget.controller.status != PluginsModuleStatus.ready) return;
    final updatable = widget.controller.updatablePlugins;
    if (updatable.isEmpty) return;

    _updatesDialogShown = true;
    unawaited(WidgetsBinding.instance.endOfFrame.then((_) async {
      if (!mounted) return;
      final selected = await showPluginUpdatesDialog(
        context: context,
        controller: widget.controller,
        updatable: updatable,
      );
      if (selected != null && mounted) setState(() => _selectedId = selected);
    }));
  }

  // ── פעולות ────────────────────────────────────────────────────────────────

  Future<void> _sync() async {
    final approved = await showTwoActionsDialog(
      context: context,
      title: 'סנכרון חנות התוספים',
      content: 'הפעולה תוריד מ-otzaria.org את רשימת התוספים, התמונות '
          'וקובצי ההתקנה אל תיקיית ההעברה. דורשת אינטרנט, ומרגע שהסתיימה '
          'החנות עובדת גם במחשב שאין בו אינטרנט.',
      confirmText: 'סנכרן',
    );
    if (!approved) return;

    await widget.controller.sync();
    if (!mounted) return;
    if (widget.controller.status == PluginsModuleStatus.error) {
      UiSnack.showError(widget.controller.errorMessage ?? 'הסנכרון נכשל');
    } else {
      UiSnack.showSuccess(
        'הסנכרון הושלם — ${widget.controller.plugins.length} תוספים בחנות',
      );
    }
  }

  Future<void> _save(StorePlugin plugin) async {
    final destPath = await FilePicker.platform.saveFile(
      dialogTitle: 'שמירת התוסף',
      fileName: widget.controller.suggestedFileName(plugin),
      type: FileType.custom,
      allowedExtensions: const ['otzplugin'],
    );
    if (destPath == null || !mounted) return;

    setState(() => _busyId = plugin.id);
    final result = await widget.controller.saveCopy(plugin, destPath);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (result.success) {
      UiSnack.showSuccess('הקובץ נשמר');
    } else {
      UiSnack.showError(result.error ?? 'שמירת הקובץ נכשלה');
    }
  }

  Future<void> _install(StorePlugin plugin) async {
    setState(() => _busyId = plugin.id);
    final result = await widget.controller.directInstall(plugin);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (result.success) {
      UiSnack.show('אוצריא נפתחה כדי להשלים את התקנת ${plugin.name}');
    } else {
      UiSnack.showError(result.error ?? 'ההתקנה נכשלה');
    }
  }

  // ── תצוגה ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final selected = _selectedId == null ? null : controller.byId(_selectedId!);

    return Stack(
      children: [
        if (selected != null)
          PluginDetailView(
            plugin: selected,
            controller: controller,
            busy: _busyId == selected.id,
            onBack: () => setState(() => _selectedId = null),
            onSave: () => _save(selected),
            onInstall: () => _install(selected),
            onTagSelected: (tag) {
              controller.setTagFilter(tag);
              controller.setSearch('');
              _search.clear();
              setState(() => _selectedId = null);
            },
          )
        else
          _listView(context),
        if (controller.status == PluginsModuleStatus.syncing)
          Positioned.fill(child: PluginSyncOverlay(controller: controller)),
      ],
    );
  }

  Widget _listView(BuildContext context) {
    final controller = widget.controller;
    final filtered = controller.filtered;

    final isLoading = controller.status == PluginsModuleStatus.loading;

    return PluginStoreBody(
      header: _syncHeader(context),
      // הרשת עוברת כ-sliver כדי שתיבנה מדורגת — ראו [PluginStoreBody].
      trailingSliver: (isLoading || filtered.isEmpty)
          ? null
          : _gridSliver(context, filtered),
      children: [
        if (controller.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: AppCard(
              child: InfoErrorRow(
                message: controller.errorMessage!,
                onRetry: controller.load,
              ),
            ),
          ),
        PluginFiltersBar(controller: controller, searchController: _search),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(top: AppTokens.spaceLG),
            child: AppCard(
              child: InfoProgressRow(stage: 'טוען את קטלוג התוספים...'),
            ),
          )
        else ...[
          _summaryRow(context, filtered.length),
          if (filtered.isEmpty) _emptyState(context),
        ],
      ],
    );
  }

  /// שורת הסנכרון בראש המסך. אין כאן מיתוג או כותרת — הלאנצ'ר כבר מציג
  /// סרגל עליון משלו, וזו גרסת התוספים שבתוכו.
  Widget _syncHeader(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final lastSync = controller.lastSync;
    final isSyncing = controller.status == PluginsModuleStatus.syncing;

    return Container(
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PluginStoreBody.horizontalPadding,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        children: [
          ActionButton.recommended(
            text: 'סנכרון מהאתר',
            icon: FluentIcons.arrow_sync_24_regular,
            isLoading: isSyncing,
            onPressed: isSyncing ? null : _sync,
          ),
          const SizedBox(width: AppTokens.spaceSM),
          SecondaryIconButton(
            icon: FluentIcons.arrow_clockwise_24_regular,
            tooltip: 'טעינה מחדש מהתיקייה המקומית',
            onPressed: isSyncing ? null : controller.load,
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Tooltip(
            message: controller.pluginsDir ?? 'התיקייה תיקבע בסנכרון הראשון',
            child: Text(
              lastSync == null
                  ? 'טרם בוצע סנכרון'
                  : 'סונכרן לאחרונה: ${_formatDateTime(lastSync)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          if (controller.status == PluginsModuleStatus.ready &&
              controller.updatablePlugins.isNotEmpty)
            StatusChip(
              kind: StatusKind.updateAvailable,
              label: '${controller.updatablePlugins.length} עדכונים זמינים',
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, int shown) {
    final theme = Theme.of(context);
    final total = widget.controller.plugins.length;

    final String summary;
    if (shown == 0) {
      summary = 'לא נמצאו תוספים לפי הסינון שבחרתם';
    } else if (shown == total) {
      summary = 'כל התוספים מוצגים';
    } else {
      summary = 'מוצגים $shown מתוך $total תוספים';
    }

    return Padding(
      padding: const EdgeInsets.only(
        top: AppTokens.spaceLG,
        bottom: AppTokens.spaceMD,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'בחרו את התוסף שמתאים לכם',
            style: theme.textTheme.headlineSmall,
          ),
          const Spacer(),
          Text(
            summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final neverSynced = widget.controller.plugins.isEmpty;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: 56,
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
              neverSynced
                  ? 'עדיין לא סונכרנו תוספים'
                  : 'לא נמצאו תוספים לפי הסינון שבחרתם',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.spaceSM),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                neverSynced
                    ? 'לחצו על "סנכרון מהאתר" במחשב שיש בו אינטרנט כדי לטעון '
                        'את רשימת התוספים העדכנית מ-otzaria.org.'
                    : 'נסו לחפש בשם אחר, להסיר תגית, או לכבות את '
                        '"הצג רק מה שלא מותקן".',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridSliver(BuildContext context, List<StorePlugin> plugins) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // מספר העמודות נגזר מרוחב מינימלי לכרטיס, כמו auto-fill ב-CSS —
        // כך שמסך רחב מקבל יותר עמודות ולא כרטיסים מנופחים.
        const spacing = AppTokens.spaceLG;
        final width = constraints.crossAxisExtent;
        final columns =
            ((width + spacing) / (_minCardWidth + spacing)).floor().clamp(1, 6);

        // גובה הכרטיס נגזר ולא קבוע: התמונה תופסת יחס 16/11 מרוחב הכרטיס,
        // ולכן כרטיס רחב הוא גם גבוה יותר. שאר התוכן מקבל גובה קבוע
        // שמוכפל בהגדלת הטקסט של המשתמש — אחרת טקסט מוגדל היה גולש.
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        final imageHeight = (tileWidth - AppTokens.spaceMD * 2) * 11 / 16;
        final textScale = MediaQuery.textScalerOf(context).scale(1);

        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: imageHeight + _cardContentHeight * textScale,
          ),
          itemCount: plugins.length,
          itemBuilder: (context, index) {
            final plugin = plugins[index];
            return PluginStoreCard(
              plugin: plugin,
              controller: widget.controller,
              busy: _busyId == plugin.id,
              onOpenDetail: () => setState(() => _selectedId = plugin.id),
              onSave: () => _save(plugin),
              onInstall: () => _install(plugin),
            );
          },
        );
      },
    );
  }

  static String _formatDateTime(DateTime value) {
    final t = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}, '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
