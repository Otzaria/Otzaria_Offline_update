import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../services/native_file_dialogs.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_detail_view.dart';
import 'custom_app_install_action.dart';
import 'custom_app_store_card.dart';

/// "תוכנות נוספות" בערכת החנות. כאן רק הורדה, התקנה והפעלה; ההוספה
/// והניהול בהגדרות (`CustomAppsManagePage`).
class CustomAppsScreen extends StatefulWidget {
  const CustomAppsScreen({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.detailId,
    this.onDetailChanged,
    this.online,
    this.onOpenManage,
  });

  final CustomAppsController controller;

  /// הכונן מוגן מפני כתיבה. תוכנה שכבר בכונן מותקנת ומופעלת כרגיל; הורדה
  /// כותבת אליו, ולכן אינה קיימת.
  final bool readOnly;

  /// כמו ב-`PluginsScreen`: עם [onDetailChanged] התוכנה שדף הפרטים שלה מוצג
  /// היא נתיב בנווט.
  final String? detailId;
  final ValueChanged<String?>? onDetailChanged;

  /// `false` — אין אינטרנט במחשב הזה: אין בדיקה ואין הורדה ברשת.
  final bool? online;

  /// "ניהול התוכנות" כשאין עדיין אף תוכנה. `null` — אין כניסה (כונן מוגן).
  final VoidCallback? onOpenManage;

  @override
  State<CustomAppsScreen> createState() => _CustomAppsScreenState();
}

class _CustomAppsScreenState extends State<CustomAppsScreen> {
  String? _localSelectedId;

  String? get _selectedId =>
      widget.onDetailChanged == null ? _localSelectedId : widget.detailId;

  void _select(String? id) {
    final external = widget.onDetailChanged;
    if (external != null) {
      external(id);
    } else {
      setState(() => _localSelectedId = id);
    }
  }

  CustomAppsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    // הקטגוריה הפתוחה יושבת בקונטרולר, ולחיצה על שבב חייבת לרענן את הרשת
    // גם כשאיש אינו בונה את המסך מחדש מבחוץ.
    _c.addListener(_onControllerChange);
    _fillMissingIcons();
  }

  /// המסגרת משאירה את המסך בנוי גם כשאינו מוצג, ומכבה לו את הטיקרים.
  bool _shown = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    _markPendingSeen();
  }

  /// המילוי רץ בכניסה למסך ולא בעלייה, כדי שמי שאינו נכנס לא ישלם עליו.
  void _fillMissingIcons() =>
      unawaited(_c.fillMissingIcons(readOnly: widget.readOnly));

  @override
  void dispose() {
    _c.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
    _markPendingSeen();
    // גם תוכנה שקובץ ההתקנה שלה הרגע ירד מקבלת אייקון, בלי כניסה מחדש.
    _fillMissingIcons();
  }

  @override
  void didUpdateWidget(CustomAppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
    _markPendingSeen();
  }

  /// רק דף שמוצג מסמן את הממתינות כ"נראו" — עד אז השבב באריח בולט.
  void _markPendingSeen() {
    if (!_shown || _c.unannouncedApps.isEmpty) return;
    // אחרי הפריים: הרישום מודיע לסשן, והקריאה מגיעה מתוך בנייה של המסגרת.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shown) return;
      final pending = _c.unannouncedApps;
      if (pending.isNotEmpty) unawaited(_c.markAnnounced(pending));
    });
  }

  CustomAppView? _byId(String id) {
    for (final app in _c.apps) {
      if (app.descriptor.id == id) return app;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final id = _selectedId;
    final selected = id == null ? null : _byId(id);
    if (selected != null) {
      return CustomAppDetailView(
        controller: _c,
        app: selected,
        readOnly: widget.readOnly,
        online: widget.online != false,
        onInstall: () => _install(selected),
        onLaunch: () => _launch(selected),
        onDownload: () => _download(selected),
        onPickLocation: () => _pickLocation(selected),
        onCategorySelected: (slug) {
          _c.showCategory(slug);
          _select(null);
        },
      );
    }
    return StoreBody(slivers: _slivers(context));
  }

  List<Widget> _slivers(BuildContext context) {
    final t = context.strings.customApps;
    final busy = _c.isCheckingAll || _c.isDownloadingAll;
    final online =
        _c.hasOnlineSources && !widget.readOnly && widget.online != false;
    final visible = _c.visibleApps;
    final progress = _progress(context);

    return [
      StoreBody.block(
        StorePageHead(
          title: t.screenTitle,
          description: t.screenSubtitle,
          actions: [
            if (online) ...[
              ActionButton.ghost(
                text: t.checkAllOnlineButton,
                icon: FluentIcons.arrow_sync_20_regular,
                spinning: _c.isCheckingAll,
                onPressed: busy ? null : _checkAll,
              ),
              ActionButton.ghost(
                text: t.downloadAllButton,
                icon: FluentIcons.arrow_download_20_regular,
                onPressed:
                    busy || _c.downloadingId != null ? null : _downloadAll,
              ),
            ],
          ],
        ),
      ),
      if (progress != null) StoreBody.block(progress, bottom: 14),
      if (_c.categories.isNotEmpty)
        StoreBody.block(_categories(context), bottom: 14),
      if (visible.isEmpty)
        StoreBody.block(_emptyState(context))
      else
        SliverGrid.builder(
          gridDelegate: StoreGridDelegate(
            textScale: MediaQuery.textScalerOf(context).scale(1),
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final app = visible[index];
            return CustomAppStoreCard(
              controller: _c,
              app: app,
              readOnly: widget.readOnly,
              online: widget.online != false,
              onOpenDetail: () => _select(app.descriptor.id),
              onInstall: () => _install(app),
              onLaunch: () => _launch(app),
              onDownload: () => _download(app),
            );
          },
        ),
    ];
  }

  /// בדיקה והורדה מרוכזות, ולמידת ההתקנה — בשורות התקדמות בדף.
  Widget? _progress(BuildContext context) {
    final t = context.strings.customApps;
    final rows = <Widget>[
      if (_c.isCheckingAll)
        InfoProgressRow(
          stage: t.checkingAllOnlineLabel(
            _c.checkAllDone ?? 0,
            _c.checkAllTotal ?? 0,
          ),
          progress: (_c.checkAllTotal ?? 0) > 0
              ? (_c.checkAllDone ?? 0) / _c.checkAllTotal!
              : null,
        ),
      if (_c.isDownloadingAll)
        ListenableBuilder(
          listenable: _c.progress,
          builder: (context, _) => InfoProgressRow(
            stage: t.downloadingAllLabel(
              _c.downloadAllDone ?? 0,
              _c.downloadAllTotal ?? 0,
            ),
            progress: (_c.downloadAllTotal ?? 0) > 0
                ? (_c.downloadAllDone ?? 0) / _c.downloadAllTotal!
                : null,
            detail: formatBytesProgress(_c.downloadReceived, _c.downloadTotal),
          ),
        ),
      if (_c.isLearning) InfoProgressRow(stage: t.learningLabel),
    ];
    if (rows.isEmpty) return null;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            row,
          ],
        ],
      ),
    );
  }

  Widget _categories(BuildContext context) {
    final t = context.strings.customApps;
    final uncategorized = _c.uncategorizedApps.length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StoreCategoryChip(
          label: t.allAppsItem,
          count: _c.apps.length,
          selected: _c.page == CustomAppsPage.all,
          onTap: _c.showAllApps,
        ),
        for (final category in _c.categories)
          Tooltip(
            message: category.description,
            child: StoreCategoryChip(
              // שם הקטגוריה הוא תוכן שהמשתמש כתב — לא מתורגם.
              label: category.name,
              count: _c.appsIn(category.slug).length,
              selected: _c.page == CustomAppsPage.category &&
                  _c.openCategorySlug == category.slug,
              onTap: () => _c.showCategory(category.slug),
            ),
          ),
        // רק כשיש מה לאסוף לתוכו — אחרת זה שבב שלעולם ריק.
        if (uncategorized > 0)
          StoreCategoryChip(
            label: t.uncategorizedItem,
            count: uncategorized,
            selected: _c.page == CustomAppsPage.uncategorized,
            onTap: _c.showUncategorized,
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final t = context.strings.customApps;
    if (!_c.hasApps) {
      return EmptyState(
        icon: FluentIcons.apps_add_in_24_regular,
        title: t.manageEmptyTitle,
        body: widget.readOnly ? t.emptyReadOnlyBody : t.manageEmptyBody,
        actions: [
          if (widget.onOpenManage case final open?)
            ActionButton.recommended(
              text: t.openManagerButton,
              onPressed: open,
            ),
        ],
      );
    }
    final uncategorized = _c.page == CustomAppsPage.uncategorized;
    return EmptyState(
      icon: FluentIcons.box_24_regular,
      quiet: true,
      title: uncategorized ? t.emptyUncategorizedTitle : t.emptyCategoryTitle,
      body: uncategorized ? t.emptyUncategorizedBody : t.emptyCategoryBody,
      actions: [
        if (_c.page != CustomAppsPage.all)
          ActionButton.neutral(
            text: t.showAllAppsButton,
            onPressed: _c.showAllApps,
          ),
      ],
    );
  }

  // ── פעולות ────────────────────────────────────────────────────────────

  Future<void> _install(CustomAppView app) =>
      installCustomApp(context: context, controller: _c, app: app);

  Future<void> _launch(CustomAppView app) =>
      launchCustomApp(context: context, controller: _c, app: app);

  Future<void> _download(CustomAppView app) async {
    final stored = await _c.download(app.descriptor.id);
    if (stored == null) {
      UiSnack.showFailure(_c.errorMessage);
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

    if (await _c.adoptInstallDir(app.descriptor, dir)) {
      UiSnack.showSuccess(AppL10n.strings.customApps.locationAdoptedSnack(dir));
      return;
    }
    UiSnack.showError(AppL10n.strings.customApps.locationNotFoundSnack);
  }

  Future<void> _checkAll() async {
    final result = await _c.checkAllOnline();
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
    // "אין עדכונים" על תוכנות שכלל לא נבדקו הוא בדיוק מה שמטעה.
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
    final result = await _c.downloadAllOutdated();
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
          '${t.downloadAllNothingNew(result.checked)}$notChecked');
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
