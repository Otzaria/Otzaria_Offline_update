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
import 'plugin_store_nav.dart';
import 'plugin_sync_overlay.dart';
import 'plugin_updates_dialog.dart';
import 'plugin_visuals.dart';

/// מסך חנות התוספים — פורט של מבנה החנות שבאתר: דף בית אצור
/// (`/plugins`), "כל התוספים" (`/plugins/all`) ודף קטגוריה
/// (`/plugins/category/<slug>`), עם סרגל צד של קטגוריות ביניהם.
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
const double _cardContentHeight = 336;

/// הרוחב המינימלי של כרטיס ברשת; ממנו נגזר מספר העמודות.
///
/// 280 ולא 300: באתר הרשת היא `xl:grid-cols-3` בתוך מכל של 1280px פחות
/// סרגל צד — כלומר כרטיס של כ-300px, ושלוש עמודות כבר סביב 950px של תוכן.
/// עם 300 העמודה השלישית נפתחה רק ב-950+ ובחלון בינוני נשארו שתי עמודות
/// עם כרטיסים רחבים בהרבה מאלה שבאתר.
const double _minCardWidth = 280;

/// כמה נבחרים מוצגים לפני "הצג עוד נבחרים" — כמו `FEATURED_PREVIEW_COUNT`.
const int _featuredPreviewCount = 6;

/// מתחת לרוחב הזה שורת הסנכרון נשברת לשתי שורות.
const double _wideHeaderWidth = 900;

class _PluginsScreenState extends State<PluginsScreen> {
  /// משמש גם את תיבת החיפוש של דף הבית וגם את זו שב"כל התוספים" — הן
  /// לעולם לא מוצגות יחד, וכך טקסט שהוקלד בדף הבית ממשיך לשם.
  final TextEditingController _search = TextEditingController();

  /// ה-id של התוסף שפרטיו מוצגים, או null כשמוצגת הרשימה.
  String? _selectedId;

  /// ה-id של התוסף שכרגע רצה עליו פעולה (שמירה / התקנה).
  String? _busyId;

  /// הודעת העדכונים מוצגת פעם אחת בכל הרצה, לא בכל טעינה מחדש.
  bool _updatesDialogShown = false;

  /// "הצג עוד נבחרים" — נפתח פעם אחת ונשאר פתוח, כמו באתר.
  bool _allFeaturedShown = false;

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
      content: 'הפעולה תוריד מ-otzaria.org את רשימת התוספים, הקטגוריות, '
          'התמונות וקובצי ההתקנה אל תיקיית ההעברה. דורשת אינטרנט, ומרגע '
          'שהסתיימה החנות עובדת גם במחשב שאין בו אינטרנט.',
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

  /// חזרה מעמוד הפרטים אל רשימה מסוננת — החיפוש החופשי מתאפס כדי שהסינון
  /// החדש לא ייחתך בטקסט שהוקלד קודם.
  void _backToList() {
    widget.controller.setSearch('');
    _search.clear();
    setState(() => _selectedId = null);
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
              controller.showAllPlugins();
              controller.setTagFilter(tag);
              _backToList();
            },
            onCategorySelected: (slug) {
              controller.setTagFilter(null);
              controller.showCategory(slug);
              _backToList();
            },
          )
        else
          _storeView(context),
        if (controller.status == PluginsModuleStatus.syncing)
          Positioned.fill(child: PluginSyncOverlay(controller: controller)),
      ],
    );
  }

  Widget _storeView(BuildContext context) {
    final controller = widget.controller;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasNav = controller.categories.isNotEmpty;
        final sidebar =
            hasNav && constraints.maxWidth >= kStoreSidebarBreakpoint;

        return PluginStoreBody(
          header: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _syncHeader(context),
              if (hasNav && !sidebar)
                PluginStoreCategoryBar(controller: controller),
            ],
          ),
          sidebar: sidebar ? PluginStoreSidebar(controller: controller) : null,
          slivers: _slivers(context),
        );
      },
    );
  }

  /// התוכן הגליל, לפי המסך שנבחר. הכול slivers — ראו [PluginStoreBody].
  List<Widget> _slivers(BuildContext context) {
    final controller = widget.controller;

    return [
      if (controller.errorMessage != null)
        PluginStoreBody.block(
          AppCard(
            child: InfoErrorRow(
              message: controller.errorMessage!,
              onRetry: controller.load,
            ),
          ),
          top: AppTokens.spaceMD,
        ),
      if (controller.status == PluginsModuleStatus.loading)
        PluginStoreBody.block(
          const AppCard(
            child: InfoProgressRow(stage: 'טוען את קטלוג התוספים...'),
          ),
          top: AppTokens.spaceLG,
        )
      else if (controller.plugins.isEmpty)
        PluginStoreBody.block(_neverSyncedState(context),
            top: AppTokens.spaceLG)
      else
        ...switch (controller.view) {
          PluginStorePage.home => _homeSlivers(context),
          PluginStorePage.all => _allSlivers(context),
          PluginStorePage.category => _categorySlivers(context),
        },
    ];
  }

  // ── דף הבית האצור ─────────────────────────────────────────────────────────

  List<Widget> _homeSlivers(BuildContext context) {
    final controller = widget.controller;
    final featured = controller.featured;
    final visibleFeatured = _allFeaturedShown
        ? featured
        : featured.take(_featuredPreviewCount).toList(growable: false);

    return [
      PluginStoreBody.block(_hero(context), top: AppTokens.spaceLG),
      // אין אצירה להציג — שער אל כל התוספים, כמו המצב הריק של דף הבית באתר.
      if (!controller.hasCuratedHome)
        PluginStoreBody.block(
          _emptyCard(
            context,
            icon: FluentIcons.puzzle_piece_24_regular,
            title: 'החנות בבנייה — אבל התוספים כבר כאן',
            body: 'בקרוב יופיעו כאן תוספים נבחרים וקטגוריות מסודרות. בינתיים '
                'אפשר לחפש למעלה או לעיין ברשימה המלאה של כל התוספים.',
            action: ActionButton.recommended(
              text: 'לכל התוספים (${controller.plugins.length})',
              icon: FluentIcons.apps_list_24_regular,
              onPressed: controller.showAllPlugins,
            ),
          ),
          top: AppTokens.spaceLG,
        ),
      // יש אצירה, אבל המתג "רק מה שלא מותקן" הסתיר את כולה.
      if (controller.hasCuratedHome &&
          featured.isEmpty &&
          controller.homeCategories.isEmpty)
        PluginStoreBody.block(_allInstalledState(context),
            top: AppTokens.spaceLG),
      if (featured.isNotEmpty) ...[
        PluginStoreBody.block(
          const _SectionHeader(
            eyebrow: 'מומלצי החנות',
            title: 'תוספים נבחרים',
          ),
          top: AppTokens.spaceXL,
          bottom: AppTokens.spaceMD,
        ),
        PluginStoreBody.padded(_gridSliver(context, visibleFeatured)),
        if (featured.length > _featuredPreviewCount && !_allFeaturedShown)
          PluginStoreBody.block(
            Center(
              child: ActionButton.neutral(
                text: 'הצג עוד נבחרים',
                icon: FluentIcons.chevron_down_24_regular,
                onPressed: () => setState(() => _allFeaturedShown = true),
              ),
            ),
            top: AppTokens.spaceMD,
          ),
      ],
      for (final category in controller.homeCategories) ...[
        PluginStoreBody.block(
          _SectionHeader(
            title: category.name,
            description: category.description,
            action: ActionButton.ghost(
              text: 'לכל הקטגוריה (${category.pluginCount})',
              icon: FluentIcons.arrow_left_24_regular,
              onPressed: () => controller.showCategory(category.slug),
            ),
          ),
          top: AppTokens.spaceXL,
          bottom: AppTokens.spaceMD,
        ),
        PluginStoreBody.padded(
          _gridSliver(
            context,
            controller.pluginsIn(category, limit: category.homeLimit),
          ),
        ),
      ],
      if (controller.hasCuratedHome)
        PluginStoreBody.block(_discoveryStrip(context), top: AppTokens.spaceXL),
    ];
  }

  /// ה-hero של דף הבית: כותרת, תקציר ותיבת חיפוש בולטת. באתר החיפוש מוביל
  /// לדף חיפוש צד-שרת; כאן — לסינון המקומי ב"כל התוספים".
  Widget _hero(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLG,
          vertical: AppTokens.spaceXL,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Text(
                  controller.homeTitle,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.spaceSM),
                Text(
                  controller.homeSubtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTokens.spaceLG),
                Row(
                  children: [
                    Expanded(
                      child: RtlTextField(
                        controller: _search,
                        onSubmitted: _submitHeroSearch,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: AppTokens.borderRadiusAll,
                          ),
                          prefixIcon: Icon(FluentIcons.search_24_regular),
                          hintText: 'חפשו תוסף לפי שם, תיאור או נושא...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSM),
                    ActionButton.recommended(
                      text: 'חיפוש',
                      icon: FluentIcons.search_24_regular,
                      onPressed: () => _submitHeroSearch(_search.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitHeroSearch(String query) =>
      widget.controller.showAllPlugins(query: query);

  /// פס הגילוי בתחתית דף הבית — "לא מצאתם? עיינו בכל התוספים".
  Widget _discoveryStrip(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'לא מצאתם את מה שחיפשתם?',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceMD),
            ActionButton.neutral(
              text: 'עיינו בכל התוספים (${controller.plugins.length})',
              icon: FluentIcons.apps_list_24_regular,
              onPressed: controller.showAllPlugins,
            ),
          ],
        ),
      ),
    );
  }

  // ── כל התוספים ────────────────────────────────────────────────────────────

  List<Widget> _allSlivers(BuildContext context) {
    final controller = widget.controller;
    final filtered = controller.filtered;

    return [
      PluginStoreBody.block(
        _breadcrumb(context, 'כל התוספים'),
        top: AppTokens.spaceMD,
        bottom: AppTokens.spaceSM,
      ),
      PluginStoreBody.block(
        PluginFiltersBar(
          controller: controller,
          searchController: _search,
        ),
      ),
      PluginStoreBody.block(
        _SectionHeader(
          eyebrow: 'רשימת תוספים',
          title: 'בחרו את התוסף שמתאים לכם',
          action: Text(
            _summaryText(filtered.length, controller.plugins.length),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        top: AppTokens.spaceLG,
        bottom: AppTokens.spaceMD,
      ),
      if (filtered.isEmpty)
        PluginStoreBody.block(_noResultsState(context))
      else
        PluginStoreBody.padded(_gridSliver(context, filtered)),
    ];
  }

  static String _summaryText(int shown, int total) {
    if (shown == 0) return 'לא נמצאו תוספים לפי הסינון שבחרתם';
    if (shown == total) return 'כל התוספים מוצגים';
    return 'מוצגים $shown מתוך $total תוספים';
  }

  // ── דף קטגוריה ────────────────────────────────────────────────────────────

  List<Widget> _categorySlivers(BuildContext context) {
    final controller = widget.controller;
    final category = controller.openCategory;
    if (category == null) return _allSlivers(context);

    final plugins = controller.pluginsIn(category);

    return [
      PluginStoreBody.block(
        _breadcrumb(context, category.name),
        top: AppTokens.spaceMD,
        bottom: AppTokens.spaceSM,
      ),
      PluginStoreBody.block(
        _SectionHeader(
          title: category.name,
          description: category.description,
          footnote: plugins.length == 1
              ? 'תוסף אחד בקטגוריה'
              : '${plugins.length} תוספים בקטגוריה',
        ),
        bottom: AppTokens.spaceMD,
      ),
      if (plugins.isEmpty)
        PluginStoreBody.block(
          // קטגוריה שיש בה תוספים אבל כולם מותקנים — לא "בקרוב יתווספו".
          category.pluginIds.isEmpty
              ? _emptyCategoryState(context)
              : _allInstalledState(context),
        )
      else
        PluginStoreBody.padded(_gridSliver(context, plugins)),
    ];
  }

  /// פירורי לחם — "חנות התוספים ‹ <המסך>", כמו באתר.
  Widget _breadcrumb(BuildContext context, String current) {
    final theme = Theme.of(context);

    return Row(
      children: [
        ActionButton.ghost(
          text: 'חנות התוספים',
          icon: FluentIcons.arrow_right_24_regular,
          onPressed: widget.controller.showHome,
        ),
        const SizedBox(width: AppTokens.spaceSM),
        Text('‹', style: theme.textTheme.bodyMedium),
        const SizedBox(width: AppTokens.spaceSM),
        Flexible(
          child: Text(
            current,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // ── שורת הסנכרון ──────────────────────────────────────────────────────────

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = [
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
          ];

          // גמיש: הטקסט מתקצר לפני שהשורה גולשת.
          final status = Expanded(
            child: Tooltip(
              message: controller.pluginsDir ?? 'התיקייה תיקבע בסנכרון הראשון',
              child: Text(
                lastSync == null
                    ? 'טרם בוצע סנכרון'
                    : 'סונכרן לאחרונה: ${_formatDateTime(lastSync)}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );

          final updates = controller.status == PluginsModuleStatus.ready &&
                  controller.updatablePlugins.isNotEmpty
              ? StatusChip(
                  kind: StatusKind.updateAvailable,
                  label: '${controller.updatablePlugins.length} עדכונים זמינים',
                )
              : null;

          // בחלון צר הכול לא נכנס לשורה אחת; המתג נשאר בקצה השמאלי העליון
          // בשני המצבים, ומועד הסנכרון יורד לשורה שנייה.
          if (constraints.maxWidth < _wideHeaderWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ...actions,
                    const Spacer(),
                    _installedFilterToggle(context),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSM),
                Row(
                  children: [
                    status,
                    if (updates != null) updates,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              ...actions,
              const SizedBox(width: AppTokens.spaceMD),
              status,
              if (updates != null) ...[
                updates,
                const SizedBox(width: AppTokens.spaceSM),
              ],
              _installedFilterToggle(context),
            ],
          );
        },
      ),
    );
  }

  /// מתג "רק מה שלא מותקן" — קטן, בקצה השמאלי של שורת הסנכרון, וחל על כל
  /// מסכי החנות (גם דף הבית והקטגוריות, שאין בהם סינון אחר).
  Widget _installedFilterToggle(BuildContext context) {
    final controller = widget.controller;
    final isOn = controller.hideInstalled;

    return Tooltip(
      message: isOn
          ? 'מוצגים רק תוספים שאינם מותקנים או שיש להם עדכון.\n'
              'זוהו ${controller.installedCount} תוספים מותקנים באוצריא.'
          : 'מוצגים כל התוספים, כולל המותקנים והמעודכנים.\n'
              'זוהו ${controller.installedCount} תוספים מותקנים באוצריא.',
      child: PluginTagPill(
        label: 'רק מה שלא מותקן',
        icon: FluentIcons.filter_24_regular,
        active: isOn,
        onTap: () => controller.setHideInstalled(!isOn),
      ),
    );
  }

  // ── מצבים ריקים ───────────────────────────────────────────────────────────

  Widget _neverSyncedState(BuildContext context) => _emptyCard(
        context,
        icon: FluentIcons.puzzle_piece_24_regular,
        title: 'עדיין לא סונכרנו תוספים',
        body: 'לחצו על "סנכרון מהאתר" במחשב שיש בו אינטרנט כדי לטעון את '
            'רשימת התוספים העדכנית מ-otzaria.org.',
      );

  Widget _noResultsState(BuildContext context) => _emptyCard(
        context,
        icon: FluentIcons.search_24_regular,
        title: 'לא נמצאו תוספים לפי הסינון שבחרתם',
        body: 'נסו לחפש בשם אחר, להסיר תגית, לבחור סטטוס שונה, או לכבות את '
            '"הצג רק מה שלא מותקן".',
      );

  /// כל מה שהיה אמור להופיע כאן כבר מותקן ומעודכן — ולכן הוסתר במתג.
  Widget _allInstalledState(BuildContext context) => _emptyCard(
        context,
        icon: FluentIcons.checkmark_circle_24_regular,
        title: 'הכול מותקן ומעודכן',
        body: 'המתג "רק מה שלא מותקן" מסתיר תוספים שכבר מותקנים אצלכם '
            'בגרסה העדכנית. כבו אותו כדי לראות גם אותם.',
        action: ActionButton.neutral(
          text: 'הצג גם את המותקנים',
          icon: FluentIcons.eye_24_regular,
          onPressed: () => widget.controller.setHideInstalled(false),
        ),
      );

  Widget _emptyCategoryState(BuildContext context) => _emptyCard(
        context,
        icon: FluentIcons.puzzle_piece_24_regular,
        title: 'בקרוב יתווספו תוספים לקטגוריה זו',
        body: 'בינתיים אפשר לעיין ברשימה המלאה של כל התוספים בחנות.',
        action: ActionButton.neutral(
          text: 'לכל התוספים',
          icon: FluentIcons.apps_list_24_regular,
          onPressed: widget.controller.showAllPlugins,
        ),
      );

  Widget _emptyCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    final theme = Theme.of(context);

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: 56,
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.spaceSM),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppTokens.spaceMD),
              action,
            ],
          ],
        ),
      ),
    );
  }

  // ── הרשת ──────────────────────────────────────────────────────────────────

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

/// כותרת סעיף בחנות — "קו + עינית" מעל כותרת גדולה, תיאור אופציונלי,
/// ופעולה בקצה השורה. הפורמט של כל הסעיפים באתר.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.eyebrow,
    this.description = '',
    this.footnote,
    this.action,
  });

  final String title;
  final String? eyebrow;
  final String description;
  final String? footnote;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                PluginSectionEyebrow(eyebrow!),
                const SizedBox(height: AppTokens.spaceXS),
              ],
              Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (footnote != null) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(
                  footnote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: AppTokens.spaceMD),
          action!,
        ],
      ],
    );
  }
}
