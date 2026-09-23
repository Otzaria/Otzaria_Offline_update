import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../services/native_file_dialogs.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_categories_dialog.dart';
import 'custom_app_detail_view.dart';
import 'custom_app_install_action.dart';
import 'custom_app_store_card.dart';
import 'custom_apps_manage_dialog.dart';
import 'custom_apps_pending_dialog.dart';

/// מסך "תוכנות נוספות" — רשת כרטיסים עם סרגל קטגוריות בצד, ודף לכל
/// תוכנה. אותה פריסה של חנות התוספים, והרכיבים המשותפים הם אותם רכיבים
/// (`screens/store_kit/`).
///
/// הפריט בסרגל הניווט מופיע **רק אחרי שנוספה תוכנה ראשונה** (ראו
/// `AppShell`), ולכן מי שלא משתמש בתכונה הזו לא פוגש אותה בכלל.
///
/// **בלשונית אין ניהול.** הוספה, עריכה, הסרה, קטגוריות וסדר קיימים רק
/// במצב [manage] — אותו מסך, שנפתח מההגדרות (`showCustomAppsManageDialog`);
/// בלשונית רק מה שעושים עם התוכנות עצמן — הורדה, התקנה והפעלה.
class CustomAppsScreen extends StatefulWidget {
  const CustomAppsScreen({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.manage = false,
    this.onClose,
  });

  final CustomAppsController controller;

  /// הכונן מוגן מפני כתיבה — ראו `AppPaths.readOnly`. תוכנה שכבר יושבת על
  /// הכונן מותקנת ומופעלת כרגיל; הורדה כותבת אליו, ולכן אינה קיימת.
  final bool readOnly;

  /// מצב ניהול: לחיצה על כרטיס עורכת אותו, ובכל כרטיס כלי סדר והסרה.
  /// אין בו פעולות על התוכנות עצמן, ואין דף תוכנה.
  final bool manage;

  /// כפתור הסגירה של מצב הניהול.
  final VoidCallback? onClose;

  @override
  State<CustomAppsScreen> createState() => _CustomAppsScreenState();
}

class _CustomAppsScreenState extends State<CustomAppsScreen> {
  /// ההודעה נאמרת פעם אחת בכל הרצה, ולא בכל רענון של הרשימה. מה שמונע
  /// ממנה לחזור בהרצה הבאה הוא הרישום שבקונטרולר — ראו `markAnnounced`.
  bool _pendingDialogShown = false;

  /// המזהה של התוכנה שדף הפרטים שלה מוצג, או `null` כשמוצגת הרשת.
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    // ⚠️ המסך מאזין בעצמו, בדיוק כמו `PluginsScreen`: הקטגוריה הפתוחה
    // יושבת בקונטרולר, ולחיצה בסרגל הצד חייבת לרענן את הרשת גם כשאיש
    // אינו בונה את המסך מחדש מבחוץ.
    widget.controller.addListener(_onControllerChange);
    _announcePendingIfNeeded();
    _fillMissingIcons();
  }

  /// מילוי האייקונים החסרים הוא **ברירת המחדל**, ורץ בכניסה למסך ולא
  /// בעלייה: כל ניסיון הוא תהליך PowerShell, ומי שאינו נכנס ללשונית אינו
  /// משלם עליו. הקונטרולר זוכר את מי כבר ניסה, ולכן הקריאה החוזרת זולה.
  void _fillMissingIcons() => unawaited(
        widget.controller.fillMissingIcons(readOnly: widget.readOnly),
      );

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
    _announcePendingIfNeeded();
    // גם תוכנה שקובץ ההתקנה שלה הרגע ירד מקבלת אייקון, בלי כניסה מחדש.
    _fillMissingIcons();
  }

  /// `AppShell` בונה את המסך מחדש גם הוא, ולכן רשימה שהגיעה מאוחר מגיעה
  /// לכאן בשני המסלולים.
  @override
  void didUpdateWidget(CustomAppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
    _announcePendingIfNeeded();
  }

  /// **המסך הוא התנאי.** הוא נבנה רק כשנכנסים ללשונית (ראו
  /// `AppShell._builtScreens`), ולכן מי שלא נכנס אליה אינו רואה את ההודעה.
  void _announcePendingIfNeeded() {
    // מסך הניהול נפתח כדי לערוך, לא כדי להתקין.
    if (widget.manage || _pendingDialogShown) return;
    final pending = widget.controller.unannouncedApps;
    if (pending.isEmpty) return;

    _pendingDialogShown = true;
    // אחרי סיום הפריים: פתיחת דיאלוג בתוך build/initState אסורה.
    unawaited(WidgetsBinding.instance.endOfFrame.then((_) async {
      if (!mounted) return;
      // נרשם עם הפתיחה ולא עם הסגירה: מה שנרשם הוא שההודעה הוצגה כאן.
      unawaited(widget.controller.markAnnounced(pending));
      await showCustomAppsPendingDialog(
        context: context,
        controller: widget.controller,
        pending: pending,
      );
    }));
  }

  CustomAppView? _byId(String id) {
    for (final app in widget.controller.apps) {
      if (app.descriptor.id == id) return app;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedId == null || widget.manage ? null : _byId(_selectedId!);
    if (selected == null) return _gridView(context);

    return CustomAppDetailView(
      controller: widget.controller,
      app: selected,
      readOnly: widget.readOnly,
      onBack: () => setState(() => _selectedId = null),
      onInstall: () => _install(selected),
      onLaunch: () => widget.controller.launch(selected.installed!),
      onDownload: () => _download(selected),
      onPickLocation: () => _pickLocation(selected),
      onCategorySelected: (slug) {
        widget.controller.showCategory(slug);
        setState(() => _selectedId = null);
      },
    );
  }

  Widget _gridView(BuildContext context) {
    final controller = widget.controller;

    return LayoutBuilder(
      builder: (context, constraints) {
        // בלי קטגוריות אין ניווט להציג, והמסך הוא רשת אחת — זה המצב של
        // מי שלא הגדיר קטגוריות, כלומר של רוב המשתמשים.
        final hasNav = controller.categories.isNotEmpty;
        final sidebar =
            hasNav && constraints.maxWidth >= kStoreSidebarBreakpoint;

        return StoreBody(
          header: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              if (hasNav && !sidebar)
                StoreCategoryBar(items: _navItems(context)),
            ],
          ),
          sidebar: sidebar
              ? StoreSidebar(
                  title: context.strings.customApps.categoriesTitle,
                  items: _navItems(context),
                )
              : null,
          slivers: _slivers(context),
        );
      },
    );
  }

  // ── סרגל הניווט ───────────────────────────────────────────────────────

  List<StoreNavItem> _navItems(BuildContext context) {
    final t = context.strings.customApps;
    final controller = widget.controller;
    final uncategorized = controller.uncategorizedApps.length;

    return [
      StoreNavItem(
        label: t.allAppsItem,
        chipLabel: t.allAppsWithCount(controller.apps.length),
        count: controller.apps.length,
        icon: FluentIcons.apps_list_24_regular,
        active: controller.page == CustomAppsPage.all,
        onTap: controller.showAllApps,
      ),
      for (final category in controller.categories)
        StoreNavItem(
          label: category.name,
          tooltip: category.description,
          count: controller.appsIn(category.slug).length,
          icon: FluentIcons.box_24_regular,
          active: controller.page == CustomAppsPage.category &&
              controller.openCategorySlug == category.slug,
          onTap: () => controller.showCategory(category.slug),
        ),
      // מוצג רק כשיש מה לאסוף לתוכו — אחרת זו שורה שלעולם ריקה.
      if (uncategorized > 0)
        StoreNavItem(
          label: t.uncategorizedItem,
          count: uncategorized,
          icon: FluentIcons.tag_dismiss_24_regular,
          active: controller.page == CustomAppsPage.uncategorized,
          muted: true,
          separatorBefore: true,
          onTap: controller.showUncategorized,
        ),
    ];
  }

  // ── הכותרת: שם המסך והפעולות המרוכזות ─────────────────────────────────

  /// שתי הפעולות המרוכזות — "בדיקה ברשת לכל התוכנות" ו"הורדת כל
  /// העדכונים". הבקשה שחזרה מהפורום: לא ללחוץ על כל כרטיס בנפרד. יושבות
  /// כאן ולא בדף הבית בכוונה: הבדיקה המרוכזת שם נוגעת ברכיבי הליבה בלבד.
  Widget _header(BuildContext context) {
    if (widget.manage) return _manageHeader(context);
    final theme = Theme.of(context);
    final t = context.strings.customApps;
    final controller = widget.controller;
    final busy = controller.isCheckingAll || controller.isDownloadingAll;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t.screenTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              // שתיהן נוגעות ברשת, וההורדה כותבת לכונן — ולכן אינן במצב
              // קריאה, ואינן קיימות כשאין אף תוכנה עם מקור מקוון.
              if (controller.hasOnlineSources && !widget.readOnly) ...[
                ActionButton.neutral(
                  text: t.checkAllOnlineButton,
                  icon: FluentIcons.arrow_sync_24_regular,
                  isLoading: controller.isCheckingAll,
                  onPressed: busy ? null : _checkAll,
                ),
                ActionButton.recommended(
                  text: t.downloadAllButton,
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: controller.isDownloadingAll,
                  onPressed: busy || controller.downloadingId != null
                      ? null
                      : _downloadAll,
                ),
              ],
            ],
          ),
          if (controller.isCheckingAll) ...[
            const SizedBox(height: AppTokens.spaceSM),
            InfoProgressRow(
              stage: t.checkingAllOnlineLabel(
                controller.checkAllDone ?? 0,
                controller.checkAllTotal ?? 0,
              ),
              progress: (controller.checkAllTotal ?? 0) > 0
                  ? (controller.checkAllDone ?? 0) / controller.checkAllTotal!
                  : null,
            ),
          ],
          // מונה התוכנות, ומתחתיו ההתקדמות של הקובץ שיורד כרגע — בלעדיה
          // הורדה של מאות מגה־בייט נראית תקועה.
          if (controller.isDownloadingAll) ...[
            const SizedBox(height: AppTokens.spaceSM),
            InfoProgressRow(
              stage: t.downloadingAllLabel(
                controller.downloadAllDone ?? 0,
                controller.downloadAllTotal ?? 0,
              ),
              progress: (controller.downloadAllTotal ?? 0) > 0
                  ? (controller.downloadAllDone ?? 0) /
                      controller.downloadAllTotal!
                  : null,
              detail: formatBytesProgress(
                controller.downloadReceived,
                controller.downloadTotal,
              ),
            ),
          ],
          // הלמידה שאחרי ההתקנה יכולה להימשך עד דקה — ראו `InstallLearner`.
          // בלי השורה הזו זה נראה כתקיעה.
          if (controller.isLearning) ...[
            const SizedBox(height: AppTokens.spaceSM),
            InfoProgressRow(stage: t.learningLabel),
          ],
        ],
      ),
    );
  }

  /// הכותרת של מצב הניהול: הוספה וקטגוריות, ההסבר, וסגירה.
  Widget _manageHeader(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.customApps;
    final controller = widget.controller;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppTokens.spaceSM,
                  runSpacing: AppTokens.spaceSM,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t.manageDialogTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    ActionButton.recommended(
                      text: t.addButton,
                      icon: FluentIcons.add_24_regular,
                      onPressed: controller.isBusy
                          ? null
                          : () => openAddCustomApp(context, controller),
                    ),
                    ActionButton.neutral(
                      text: t.manageCategoriesButton,
                      icon: FluentIcons.tag_24_regular,
                      onPressed: controller.isBusy
                          ? null
                          : () => showCustomAppCategoriesDialog(
                                context: context,
                                controller: controller,
                              ),
                    ),
                  ],
                ),
              ),
              if (widget.onClose case final onClose?)
                ActionButton.neutral(
                  text: context.strings.common.close,
                  icon: FluentIcons.dismiss_24_regular,
                  onPressed: onClose,
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXS),
          Text(t.manageDialogHint, style: hint),
          // מוצג רק כשיש מה לסדר.
          if (controller.apps.length > 1) Text(t.orderHint, style: hint),
          if (controller.isLearning) ...[
            const SizedBox(height: AppTokens.spaceSM),
            InfoProgressRow(stage: t.learningLabel),
          ],
        ],
      ),
    );
  }

  // ── התוכן הגליל ───────────────────────────────────────────────────────

  List<Widget> _slivers(BuildContext context) {
    final controller = widget.controller;
    final visible = controller.visibleApps;
    final header = _sectionHeader(context);

    return [
      if (header != null)
        StoreBody.block(header,
            top: AppTokens.spaceLG, bottom: AppTokens.spaceMD),
      if (visible.isEmpty)
        StoreBody.block(_emptyState(context), top: AppTokens.spaceLG)
      else
        StoreBody.padded(
          _gridSliver(context, visible),
          top: header == null ? AppTokens.spaceLG : 0,
        ),
    ];
  }

  /// כותרת הסעיף קיימת רק בקטגוריה — "כל התוכנות" הוא המסך עצמו, וכותרת
  /// שחוזרת על שם המסך היא רעש.
  Widget? _sectionHeader(BuildContext context) {
    final t = context.strings.customApps;
    final controller = widget.controller;

    return switch (controller.page) {
      CustomAppsPage.all => null,
      CustomAppsPage.uncategorized => StoreSectionHeader(
          title: t.uncategorizedItem,
          footnote: t.categoryAppCount(controller.uncategorizedApps.length),
        ),
      CustomAppsPage.category => switch (controller.openCategory) {
          null => null,
          final category => StoreSectionHeader(
              // שם הקטגוריה ותיאורה הם תוכן שהמשתמש כתב — לא מתורגמים.
              title: category.name,
              description: category.description,
              footnote: t.categoryAppCount(
                controller.appsIn(category.slug).length,
              ),
            ),
        },
    };
  }

  Widget _emptyState(BuildContext context) {
    final t = context.strings.customApps;
    final uncategorized =
        widget.controller.page == CustomAppsPage.uncategorized;
    // מרשם ריק לגמרי — רק במסך הניהול, כי בלי תוכנות אין לשונית.
    final nothingYet = widget.manage && !widget.controller.hasApps;
    final title = nothingYet
        ? t.emptyHint
        : uncategorized
            ? t.emptyUncategorizedTitle
            : t.emptyCategoryTitle;
    final body = nothingYet
        ? null
        : uncategorized
            ? t.emptyUncategorizedBody
            : t.emptyCategoryBody;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXL),
        child: Column(
          children: [
            Icon(
              FluentIcons.box_24_regular,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: AppTokens.spaceXS),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gridSliver(BuildContext context, List<CustomAppView> apps) {
    return SliverGrid.builder(
      gridDelegate: StoreGridDelegate(
        textScale: MediaQuery.textScalerOf(context).scale(1),
        minCardWidth: kCustomAppMinCardWidth,
        contentHeight: kCustomAppCardContentHeight,
        imageAspectRatio: kStoreIconFrameAspect,
        imageMaxWidth: kCustomAppIconFrameMaxWidth,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        if (widget.manage) return _managedCard(apps, index);
        return CustomAppStoreCard(
          controller: widget.controller,
          app: app,
          readOnly: widget.readOnly,
          onOpenDetail: () => setState(() => _selectedId = app.descriptor.id),
          onInstall: () => _install(app),
          onLaunch: () => widget.controller.launch(app.installed!),
          onDownload: () => _download(app),
        );
      },
    );
  }

  // ── מצב ניהול ─────────────────────────────────────────────────────────

  /// המזהה של הכרטיס שנגרר כרגע — הוא מוצג עמום במקומו.
  String? _draggingId;

  /// כרטיס שאפשר להניח עליו כרטיס אחר. [visible] הוא מה שמוצג בקטגוריה
  /// הפתוחה — "הקודם" ו"הבא" נמדדים בו, לא ברשימה המלאה.
  Widget _managedCard(List<CustomAppView> visible, int index) {
    final controller = widget.controller;
    final app = visible[index];
    final id = app.descriptor.id;

    return LayoutBuilder(
      key: ValueKey(id),
      builder: (context, constraints) {
        Widget card({bool highlighted = false, Widget? toolbar}) =>
            CustomAppStoreCard(
              controller: controller,
              app: app,
              readOnly: widget.readOnly,
              highlighted: highlighted,
              onOpenDetail: controller.isBusy
                  ? () {}
                  : () => openEditCustomApp(context, controller, app.entry),
              onInstall: () {},
              onLaunch: () {},
              onDownload: () {},
              manageToolbar: toolbar ?? const SizedBox(height: 36),
            );

        // הגרירה יושבת בידית בלבד: גרירה מכל הכרטיס הייתה חוטפת במסך מגע
        // את הגלילה. מה שנגרר על המסך הוא הכרטיס כולו.
        final handle = Draggable<String>(
          data: id,
          maxSimultaneousDrags: controller.isBusy ? 0 : 1,
          onDragStarted: () => setState(() => _draggingId = id),
          onDragEnd: (_) => setState(() => _draggingId = null),
          feedback: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: AppTokens.borderRadiusAll,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: card(),
            ),
          ),
          child: _dragHandle(visible.length > 1 && !controller.isBusy),
        );

        return DragTarget<String>(
          onWillAcceptWithDetails: (details) => details.data != id,
          onAcceptWithDetails: (details) => _moveOnto(details.data, id),
          builder: (context, candidates, _) => Opacity(
            opacity: _draggingId == id ? 0.4 : 1,
            child: card(
              highlighted: candidates.isNotEmpty,
              toolbar: _manageToolbar(visible, index, handle),
            ),
          ),
        );
      },
    );
  }

  Widget _dragHandle(bool enabled) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      child: Tooltip(
        message: context.strings.customApps.dragToReorderTooltip,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceXS),
          child: Icon(
            FluentIcons.re_order_dots_vertical_24_regular,
            color: enabled ? cs.onSurfaceVariant : cs.outline,
          ),
        ),
      ),
    );
  }

  Widget _manageToolbar(
    List<CustomAppView> visible,
    int index,
    Widget handle,
  ) {
    final t = context.strings.customApps;
    final controller = widget.controller;
    final busy = controller.isBusy;
    final app = visible[index];

    return Row(
      children: [
        handle,
        const Spacer(),
        // ⚠️ בכוונה בלי `context.backArrowIcon`: בסדר הרשת "הקודם" הוא בכיוון
        // הקריאה, ו-`RtlIcon` הופך את החץ ב-RTL.
        SecondaryIconButton(
          icon: FluentIcons.arrow_left_24_regular,
          tooltip: t.moveAppEarlierTooltip,
          onPressed: busy || index == 0
              ? null
              : () => _moveOnto(
                  app.descriptor.id, visible[index - 1].descriptor.id),
        ),
        const SizedBox(width: AppTokens.spaceXS),
        SecondaryIconButton(
          icon: FluentIcons.arrow_right_24_regular,
          tooltip: t.moveAppLaterTooltip,
          onPressed: busy || index == visible.length - 1
              ? null
              : () => _moveOnto(
                  app.descriptor.id, visible[index + 1].descriptor.id),
        ),
        const SizedBox(width: AppTokens.spaceXS),
        SecondaryIconButton(
          icon: FluentIcons.edit_24_regular,
          tooltip: t.editTooltip,
          onPressed: busy
              ? null
              : () => openEditCustomApp(context, controller, app.entry),
        ),
        const SizedBox(width: AppTokens.spaceXS),
        SecondaryIconButton(
          icon: FluentIcons.delete_24_regular,
          tooltip: t.removeTooltip,
          onPressed: busy
              ? null
              : () => confirmRemoveCustomApp(context, controller, app),
        ),
      ],
    );
  }

  /// מניח את [id] במקומו של [targetId] ברשימה **המלאה**, לפי מזהים: בקטגוריה
  /// פתוחה האינדקס ברשת אינו המקום בסדר השמור.
  void _moveOnto(String id, String targetId) {
    final controller = widget.controller;
    // גרירה שהתחילה לפני שמירה קודמת עלולה לנחות בזמנה.
    if (controller.isBusy) return;
    final apps = controller.apps;
    final from = apps.indexWhere((a) => a.descriptor.id == id);
    final to = apps.indexWhere((a) => a.descriptor.id == targetId);
    if (from < 0 || to < 0) return;
    unawaited(controller.moveApp(from, to));
  }

  // ── פעולות ────────────────────────────────────────────────────────────

  Future<void> _install(CustomAppView app) => installCustomApp(
        context: context,
        controller: widget.controller,
        app: app,
      );

  Future<void> _download(CustomAppView app) async {
    final stored = await widget.controller.download(app.descriptor.id);
    if (stored == null) {
      UiSnack.showError(widget.controller.errorMessage ?? '');
      return;
    }
    UiSnack.showSuccess(
      AppL10n.strings.customApps.downloadedSnack(stored.version),
    );
  }

  Future<void> _pickLocation(CustomAppView app) async {
    final t = context.strings.customApps;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    if (await widget.controller.adoptInstallDir(app.descriptor, dir)) {
      UiSnack.showSuccess(AppL10n.strings.customApps.locationAdoptedSnack(dir));
      return;
    }
    UiSnack.showError(AppL10n.strings.customApps.locationNotFoundSnack);
  }

  Future<void> _checkAll() async {
    final result = await widget.controller.checkAllOnline();
    if (result.checked == 0) return;
    final t = AppL10n.strings.customApps;

    // כולן נכשלו = אין רשת. זו התשובה השלמה, ואין מה להוסיף עליה.
    if (result.failed == result.checked) {
      UiSnack.showError(t.checkAllOnlineAllFailed);
      return;
    }
    final summary = result.updates > 0
        ? t.checkAllOnlineSummary(result.updates, result.checked)
        : t.checkAllOnlineNoUpdates(result.checked);
    // בדיקה שנכשלה לחלק מהן אינה שגיאה, אבל אסור לבלוע אותה: "אין עדכונים"
    // על תוכנות שכלל לא נבדקו הוא בדיוק מה שמטעה.
    final text = result.failed > 0
        ? '$summary ${t.checkAllOnlineSomeFailed(result.failed)}'
        : summary;
    if (result.updates > 0) {
      UiSnack.show(text);
    } else {
      UiSnack.showSuccess(text);
    }
  }

  Future<void> _downloadAll() async {
    final result = await widget.controller.downloadAllOutdated();
    final t = AppL10n.strings.customApps;
    if (result.checked == 0 && result.notChecked == 0) return;

    // לא נבדקה אף אחת = אין רשת. אין טעם לומר "אין מה להוריד" על כך.
    if (result.checked == 0) {
      UiSnack.showError(t.checkAllOnlineAllFailed);
      return;
    }
    // מה שלא נבדק נאמר בכל מקרה: "הכול מעודכן" על תוכנות שלא נבדקו מטעה.
    final notChecked = result.notChecked > 0
        ? ' ${t.checkAllOnlineSomeFailed(result.notChecked)}'
        : '';
    if (result.downloaded == 0 && result.failed == 0) {
      UiSnack.showSuccess(
        '${t.downloadAllNothingNew(result.checked)}$notChecked',
      );
      return;
    }
    final done = t.downloadAllDoneSnack(result.downloaded);
    if (result.failed > 0) {
      UiSnack.showError(
        '$done ${t.downloadAllSomeFailed(result.failed)}$notChecked',
      );
      return;
    }
    UiSnack.showSuccess('$done$notChecked');
  }
}
