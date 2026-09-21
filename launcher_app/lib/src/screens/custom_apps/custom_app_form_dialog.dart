import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../services/exe_icon_extractor.dart';
import '../../services/native_file_dialogs.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'installer_kind_label.dart';

/// "הוספת תוכנה", והוא גם טופס העריכה — הדרך **היחידה** שבה נכתבת רשומה
/// של תוכנה נוספת.
///
/// המשתמש ממלא שם, מצביע על מקור, ואומר לאן התוכנה מותקנת. כל השאר נגזר:
/// סוג ההתקנה מזוהה מהקובץ, שם קובץ ההרצה נסרק מתיקיית ההתקנה, והמזהה
/// נבנה לבד. "איזה framework בנה את ה-installer" ו"איך קוראים למזהה" הן
/// השאלות שמשתמש רגיל אינו יכול לענות עליהן — ולכן הן אלה שנענות לבד.
///
/// בעריכה ([existing] אינו `null`) **המזהה אינו משתנה**: הוא שם התיקייה
/// שבה כבר יושב קובץ ההתקנה שירד, ושינויו היה מנתק את התוכנה ממנו.
class CustomAppFormDialog extends StatefulWidget {
  const CustomAppFormDialog({
    super.key,
    required this.controller,
    this.existing,
  });

  final CustomAppsController controller;

  /// הרשומה שעורכים, או `null` בהוספה.
  final CustomAppEntry? existing;

  @override
  State<CustomAppFormDialog> createState() => _CustomAppFormDialogState();
}

class _CustomAppFormDialogState extends State<CustomAppFormDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _longDescription = TextEditingController();
  final _installDir = TextEditingController();
  final _exeName = TextEditingController();
  final _githubUrl = TextEditingController();

  AppSourceKind _source = AppSourceKind.github;

  /// הקטגוריות שסומנו, לפי slug.
  final Set<String> _categories = {};

  /// נתיבים **מלאים** — גם לתמונה חדשה שנבחרה וגם לזו שכבר יושבת
  /// ב-`media/`. ההעתקה פנימה וההמרה לשמות יחסיים נעשות בשמירה, ב-
  /// `CustomAppsManager.saveMedia`.
  String? _iconPath;
  List<String> _screenshots = [];

  bool _isExtractingIcon = false;

  /// מקור "קובץ שלי" — הקובץ שנבחר.
  String? _localFilePath;

  /// מה שהריחרוח מצא בקובץ שנבחר עכשיו, או `null` כשאין קובץ כזה או שלא
  /// ניתן היה לקבוע. מוצג בלבד — ההכרעה האמיתית נעשית שוב בזמן ההתקנה,
  /// מהבייטים של הקובץ ששמור על הכונן.
  CustomInstallerKind? _sniffedKind;

  /// "הקובץ אינו מתקין אלא התוכנה עצמה". השאלה היחידה על הקובץ שכן נשאלת,
  /// כי אי אפשר להריח אותה: exe נייד ומתקין לא-מוכר נראים זהים.
  bool _portableFile = false;

  /// מקור "גיטהאב" — מה שחזר מהריפו.
  GithubRelease? _release;
  GithubAsset? _selectedAsset;
  String? _githubError;
  bool _isFetching = false;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing?.descriptor case final descriptor?) {
      _name.text = descriptor.name;
      _description.text = descriptor.description ?? '';
      _longDescription.text = descriptor.longDescription ?? '';
      _installDir.text = descriptor.installDir ?? '';
      _exeName.text = descriptor.detect.exeName ?? '';
      _source = descriptor.sourceKind;
      _portableFile = descriptor.portableFile;
      _categories.addAll(descriptor.categorySlugs);
      // המדיה נטענת כנתיבים מלאים, כדי שמה שנשאר ומה שנוסף עכשיו ייראו
      // אותו הדבר לשמירה.
      _iconPath = widget.controller.iconPathOf(descriptor);
      _screenshots = widget.controller.screenshotPathsOf(descriptor);
      if (descriptor.github case final source?) _githubUrl.text = source.webUrl;
    }
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _description,
      _longDescription,
      _installDir,
      _exeName,
      _githubUrl,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  /// המזהה נגזר משם קובץ ההרצה, ואם אין — מהשם שנבחר. הוא רק שם תיקייה,
  /// ולכן אינו מוצג ואינו נשאל. בעריכה הוא נשאר כשהיה.
  String get _id =>
      widget.existing?.descriptor.id ??
      AppDescriptorIdGenerator.from(
        _exeName.text.isNotEmpty
            ? p.basenameWithoutExtension(_exeName.text)
            : (_selectedAsset?.name ??
                _localFilePath?.let(p.basenameWithoutExtension) ??
                _name.text),
        taken: widget.controller.takenIds,
      );

  /// התבנית שכבר נשמרה, כשעורכים ולא נגעו במקור. מתאפסת ברגע שבשדה יושב
  /// ריפו אחר — תבנית שנבחרה בריפו אחד אינה אומרת דבר על השני.
  String? get _keptAssetPattern {
    if (_source != AppSourceKind.github) return null;
    final source = widget.existing?.descriptor.github;
    if (source == null || source.assetPattern.isEmpty) return null;
    final parsed = GithubSource.parseUrl(_githubUrl.text);
    if (parsed == null) return null;
    if (parsed.owner != source.owner || parsed.repo != source.repo) return null;
    return source.assetPattern;
  }

  /// קובץ ההתקנה שכבר יושב על הכונן. בעריכה הוא מקור לגיטימי בפני עצמו —
  /// אין שום סיבה לדרוש מהמשתמש לבחור שוב קובץ שכבר נסע איתו.
  StoredInstaller? get _keptInstaller =>
      _source == AppSourceKind.manual ? widget.existing?.installer : null;

  bool get _hasSource => switch (_source) {
        AppSourceKind.github =>
          _selectedAsset != null || _keptAssetPattern != null,
        AppSourceKind.manual =>
          _localFilePath != null || _keptInstaller != null,
      };

  // ── מקור: גיטהאב ──────────────────────────────────────────────────────────

  Future<void> _fetchAssets() async {
    final t = context.strings.customApps;
    final parsed = GithubSource.parseUrl(_githubUrl.text);
    if (parsed == null) {
      setState(() => _githubError = t.githubUrlInvalid);
      return;
    }

    setState(() {
      _isFetching = true;
      _githubError = null;
      _release = null;
      _selectedAsset = null;
    });

    try {
      final release = await widget.controller.github.fetchLatest(
        GithubSource(
          owner: parsed.owner,
          repo: parsed.repo,
          assetPattern: '',
        ),
      );
      if (!mounted) return;
      setState(() {
        _release = release;
        _isFetching = false;
        // שם ברירת מחדל מהריפו, רק כשהמשתמש עוד לא כתב אחד משלו.
        if (_name.text.isEmpty) _name.text = parsed.repo;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetching = false;
        _githubError = '$e';
      });
    }
  }

  /// בחירת קובץ מתוך ה-release — ומיד גם זיהוי סוג ההתקנה משמו.
  void _selectAsset(GithubAsset asset) {
    setState(() {
      _selectedAsset = asset;
    });
  }

  // ── מקור: קובץ מקומי ──────────────────────────────────────────────────────

  Future<void> _pickLocalFile() async {
    final t = context.strings.customApps;
    final path = await NativeFileDialogs.pickFile(
      dialogTitle: t.pickInstallerDialogTitle,
    );
    if (path == null || !mounted) return;

    // סוג ההתקנה **אינו** נשאל ואינו נשמר — הוא נקבע מהקובץ עצמו בזמן
    // ההתקנה. ראו `CustomAppInstaller.install`.
    setState(() {
      _localFilePath = path;
      _sniffedKind = null;
      if (_name.text.isEmpty) _name.text = p.basenameWithoutExtension(path);
    });
    await _sniffKind(path);
  }

  /// מריח את הקובץ ומראה מה נמצא — ZIP בעיקר, שגורלו שונה לגמרי (הוא
  /// מועתק לתיקיית ההורדות ואינו מותקן), אבל גם כדי שיהיה ברור מראש
  /// כשייפתח חלון מתקין במקום התקנה שקטה.
  ///
  /// כשל כאן אינו כשל של הטופס: הריחרוח הוא הצגה בלבד, וההכרעה נעשית שוב
  /// בזמן ההתקנה מהקובץ ששמור על הכונן.
  Future<void> _sniffKind(String path) async {
    CustomInstallerKind? kind;
    try {
      kind = await const InstallerKindSniffer().sniff(path);
    } catch (_) {
      kind = null;
    }
    if (!mounted || _localFilePath != path) return;
    setState(() => _sniffedKind = kind);
  }

  // ── מיקום ההתקנה ──────────────────────────────────────────────────────────

  Future<void> _pickInstallDir() async {
    final t = context.strings.customApps;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null || !mounted) return;
    setState(() => _installDir.text = dir);

    final suggestion = await _findExeIn(dir);
    if (suggestion == null || !mounted) return;
    setState(() => _exeName.text = suggestion);
  }

  /// שם קובץ ההרצה אינו נשאל אם אפשר למצוא אותו: כשהתוכנה כבר מותקנת,
  /// ה-exe יושב בתיקייה שהמשתמש הרגע הצביע עליה.
  ///
  /// ⚠️ עובר דרך `CustomAppsController.findInstalledExe` ולא דרך "ה-exe
  /// הראשון בתיקייה". הגרסה הקודמת כאן לקחה את הראשון מ-`listSync()` — סדר
  /// לא מובטח, בלי לפסול `unins000.exe` ובלי לפסול עזרי Flutter — וזה בדיוק
  /// הבאג המתועד של `crashpad_handler.exe`, שגם מקדים באלף-בית וגם נושא שדה
  /// גרסה משל עצמו.
  Future<String?> _findExeIn(String dir) async {
    if (_exeName.text.isNotEmpty) return null;
    final path = await CustomAppsController.findInstalledExe(dir, _nameHints());
    return path == null ? null : p.basename(path);
  }

  /// אותם רמזים שהלמידה שאחרי ההתקנה משתמשת בהם — השם שהוקלד, שם הריפו ושם
  /// קובץ ההתקנה.
  List<String> _nameHints() => InstallLearner.nameHintsFor(
        name: _name.text,
        repo: GithubSource.parseUrl(_githubUrl.text)?.repo,
        installerFileName: _selectedAsset?.name ?? _localFilePath,
      );

  // ── שמירה ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final t = context.strings.customApps;
    if (_name.text.trim().isEmpty) {
      UiSnack.showError(t.nameRequired);
      return;
    }
    if (!_hasSource) {
      UiSnack.showError(t.sourceRequired);
      return;
    }

    setState(() => _isSaving = true);
    final descriptor = _buildDescriptor();
    final saved = _isEditing
        ? await widget.controller.update(descriptor)
        : await widget.controller.add(descriptor);
    if (!saved) {
      if (mounted) setState(() => _isSaving = false);
      UiSnack.showError(widget.controller.errorMessage ?? '');
      return;
    }

    // קובץ מקומי נאסף מיד: המשתמש יוצא מכאן עם תוכנה מוכנה לנסוע על
    // הכונן, ולא עם רישום ריק. מקור גיטהאב יורד בלחיצה נפרדת, כי הוא
    // הפעולה הכבדה שדורשת רשת.
    if (_source == AppSourceKind.manual && _localFilePath != null) {
      await widget.controller.attachInstaller(
        descriptor.id,
        sourcePath: _localFilePath!,
        version: readInstallerVersion(_localFilePath!) ?? '',
      );
    }
    // המדיה נכתבת אחרי הרשומה ולא לפניה: היא נשמרת בתיקייה שהרשומה
    // יוצרת, ושמות הקבצים נרשמים בה בסיום. כשלון כאן אינו מבטל את
    // השמירה — הרשומה עצמה כבר נכונה.
    if (!await widget.controller.saveMedia(
      descriptor.id,
      iconSource: _iconPath,
      screenshotSources: _screenshots,
    )) {
      UiSnack.showError(widget.controller.errorMessage ?? '');
    }
    if (!mounted) return;

    Navigator.of(context).pop();
    final strings = AppL10n.strings.customApps;
    UiSnack.showSuccess(
      _isEditing
          ? strings.updatedSnack(descriptor.name)
          : strings.addedSnack(descriptor.name),
    );
  }

  AppDescriptor _buildDescriptor() {
    final parsed = GithubSource.parseUrl(_githubUrl.text);
    final asset = _selectedAsset;
    final existing = widget.existing?.descriptor;
    return AppDescriptor(
      id: _id,
      name: _name.text.trim(),
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      longDescription: _longDescription.text.trim().isEmpty
          ? null
          : _longDescription.text.trim(),
      categorySlugs: _categories.toList(growable: false),
      // שדות שהטופס אינו מציג נגררים כמות שהם — עריכה של שם לא אמורה
      // למחוק בשקט שדה שהמשתמש אינו רואה בכלל.
      publisher: existing?.publisher,
      // שמות קובצי המדיה נגררים גם הם, ונכתבים מחדש רק כש-`saveMedia`
      // מצליח — אחרת כשלון בהעתקת תמונה היה מוחק מהרשומה מדיה שקיימת.
      iconFile: existing?.iconFile,
      screenshotFiles: existing?.screenshotFiles ?? const [],
      sourceKind: _source,
      github: _source == AppSourceKind.github && parsed != null
          ? GithubSource(
              owner: parsed.owner,
              repo: parsed.repo,
              // התבנית נבנית משם הקובץ שנבחר, כדי שהיא תמשיך להתאים גם
              // בגרסה הבאה — ראו [GithubAssetPattern]. בעריכה שלא נגעה
              // במקור נשמרת התבנית שכבר הייתה.
              assetPattern: asset != null
                  ? GithubAssetPattern.fromAssetName(asset.name)
                  : _keptAssetPattern ?? '',
            )
          : null,
      installDir:
          _installDir.text.trim().isEmpty ? null : _installDir.text.trim(),
      portableFile: _portableFile,
      detect: AppDetectRules(
        exeName: _exeName.text.trim().isEmpty ? null : _exeName.text.trim(),
        registryDisplayName: existing?.detect.registryDisplayName,
        dirs: [
          if (_installDir.text.trim().isNotEmpty) _installDir.text.trim(),
        ],
      ),
    );
  }

  // ── תצוגה ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        _isEditing ? t.editDialogTitle : t.addDialogTitle,
        style: theme.textTheme.titleLarge,
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(t.nameLabel, _name, hint: t.nameHint),
              _field(t.descriptionLabel, _description, hint: t.descriptionHint),
              _field(
                t.longDescriptionLabel,
                _longDescription,
                hint: t.longDescriptionHint,
                maxLines: 4,
              ),
              if (widget.controller.categories.isNotEmpty) ...[
                _categoriesSection(context),
                const SizedBox(height: AppTokens.spaceLG),
              ],
              const SizedBox(height: AppTokens.spaceSM),
              _sourcePicker(context),
              const SizedBox(height: AppTokens.spaceLG),
              if (_source == AppSourceKind.github)
                _githubSection(context)
              else
                _localFileSection(context),
              const SizedBox(height: AppTokens.spaceLG),
              _portableFileRow(context),
              const SizedBox(height: AppTokens.spaceLG),
              _installDirRow(context),
              _field(t.exeNameLabel, _exeName, hint: t.exeNameHint),
              const SizedBox(height: AppTokens.spaceSM),
              _iconSection(context),
              const SizedBox(height: AppTokens.spaceLG),
              _screenshotsSection(context),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.neutral(
          text: context.strings.common.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: _isEditing ? t.saveEditButton : t.saveButton,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _save,
        ),
      ],
    );
  }

  Widget _sourcePicker(BuildContext context) {
    final t = context.strings.customApps;
    return _labelled(
      context,
      t.sourceLabel,
      AppSegmentedControl<AppSourceKind>(
        options: [
          SegmentOption(value: AppSourceKind.github, label: t.sourceGithub),
          SegmentOption(value: AppSourceKind.manual, label: t.sourceFile),
        ],
        currentValue: _source,
        onChanged: (value) => setState(() => _source = value),
      ),
    );
  }

  Widget _githubSection(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(t.githubUrlLabel, _githubUrl, hint: t.githubUrlHint),
        ActionButton.neutral(
          text: t.fetchAssetsButton,
          icon: FluentIcons.search_24_regular,
          isLoading: _isFetching,
          onPressed: _isFetching ? null : _fetchAssets,
        ),
        // בעריכה, כל עוד לא הובאה רשימה חדשה, אומרים במפורש מה יישאר.
        if (_release == null && _keptAssetPattern != null) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Text(
            t.githubAssetKept,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_githubError case final error?) ...[
          const SizedBox(height: AppTokens.spaceSM),
          InfoErrorRow(message: error),
        ],
        if (_release case final release?) ...[
          const SizedBox(height: AppTokens.spaceMD),
          Text(
            t.assetsFromRelease(release.tagName),
            style: theme.textTheme.labelLarge,
          ),
          Text(
            t.assetHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSM),
          if (release.assets.isEmpty)
            Text(t.noAssetsFound, style: theme.textTheme.bodyMedium)
          else
            // ⚠️ הבחירה כאן היא כל ההבדל בין "מוריד את הקובץ הנכון" לבין
            // "מוריד את הראשון ברשימה" — ל-release טיפוסי יש גם x86, גם
            // portable וגם קובצי sha.
            for (final asset in release.assets)
              SettingsActionTile.text(
                icon: asset == _selectedAsset
                    ? FluentIcons.checkmark_circle_24_filled
                    : FluentIcons.circle_24_regular,
                title: asset.name,
                subtitle: formatBytes(asset.sizeBytes),
                onTap: () => _selectAsset(asset),
              ),
        ],
      ],
    );
  }

  Widget _localFileSection(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);
    final path = _localFilePath;
    final kept = _keptInstaller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // מה שנבחר עכשיו קודם לְמה ששמור, ובלי שניהם — הזמנה לבחור.
          path != null
              ? p.basename(path)
              : kept != null
                  ? t.installerKept(kept.fileName)
                  : t.pickInstallerDialogTitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        // מה שזוהה בקובץ. ל-ZIP זה השינוי הגדול ביותר — הוא אינו מותקן
        // אלא מועתק לתיקיית ההורדות, וכדאי לדעת זאת לפני ולא אחרי.
        if (_sniffedKind case final kind?) ...[
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            t.installerKindSniffed(installerKindLabelOf(kind, t)),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppTokens.spaceSM),
        ActionButton.neutral(
          text: t.pickInstallerButton,
          icon: FluentIcons.folder_open_24_regular,
          onPressed: _pickLocalFile,
        ),
      ],
    );
  }

  /// ההצהרה "זו התוכנה עצמה". היא נשאלת דווקא משום שאי אפשר להריח אותה:
  /// exe נייד ומתקין של framework לא מוכר נראים זהים לחלוטין, ושניהם
  /// נופלים ל-`interactive`. הרצת קובץ נייד "כמתקין" רק מפעילה אותו מהכונן
  /// — הוא לעולם לא מגיע למחשב.
  Widget _portableFileRow(BuildContext context) {
    final t = context.strings.customApps;
    return SettingsActionTile.switchTile(
      icon: FluentIcons.document_arrow_right_24_regular,
      title: t.portableFileLabel,
      subtitle: t.portableFileHint,
      value: _portableFile,
      onChanged: (value) => setState(() => _portableFile = value),
    );
  }

  Widget _installDirRow(BuildContext context) {
    final t = context.strings.customApps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(t.installDirLabel, _installDir, hint: t.installDirHint),
        ActionButton.neutral(
          text: t.pickInstallDirButton,
          icon: FluentIcons.folder_24_regular,
          onPressed: _pickInstallDir,
        ),
        const SizedBox(height: AppTokens.spaceMD),
      ],
    );
  }

  Widget _labelled(
    BuildContext context,
    String label,
    Widget child, {
    TextStyle? style,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style ?? Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppTokens.spaceSM),
          child,
        ],
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
      child: RtlTextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, helperText: hint),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ── קטגוריות ──────────────────────────────────────────────────────────

  /// הקטגוריות כגלולות שנבחרות. **אין כאן יצירה של קטגוריה** — היא נעשית
  /// בכרטיס שבהגדרות, יחד עם שאר ניהול המרשם; כשאין אף קטגוריה הסעיף כולו
  /// אינו מוצג.
  Widget _categoriesSection(BuildContext context) {
    final t = context.strings.customApps;

    return _labelled(
      context,
      t.appCategoriesLabel,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              for (final category in widget.controller.categories)
                StoreTagPill(
                  label: category.name,
                  active: _categories.contains(category.slug),
                  onTap: () => setState(() {
                    if (!_categories.remove(category.slug)) {
                      _categories.add(category.slug);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            t.appCategoriesHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  // ── אייקון ────────────────────────────────────────────────────────────

  Widget _iconSection(BuildContext context) {
    final t = context.strings.customApps;
    final path = _iconPath;

    return _labelled(
      context,
      t.iconLabel,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: StoreThumbnail(
              imagePath: path,
              placeholderIcon: FluentIcons.box_24_regular,
              aspectRatio: 1,
              iconSize: 28,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceSM,
              children: [
                ActionButton.neutral(
                  text: t.pickIconButton,
                  icon: FluentIcons.image_24_regular,
                  onPressed: _pickIcon,
                ),
                // רק כשיש ממה לחלץ, ורק בווינדוס.
                if (_iconSourceExe() != null)
                  ActionButton.ghost(
                    text: t.extractIconButton,
                    icon: FluentIcons.wand_24_regular,
                    isLoading: _isExtractingIcon,
                    onPressed: _isExtractingIcon ? null : _extractIcon,
                  ),
                if (path != null)
                  ActionButton.ghost(
                    text: t.removeIconTooltip,
                    icon: FluentIcons.dismiss_24_regular,
                    onPressed: () => setState(() => _iconPath = null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickIcon() async {
    final t = context.strings.customApps;
    final path = await NativeFileDialogs.pickFile(
      dialogTitle: t.pickIconDialogTitle,
      allowedExtensions: _imageExtensions,
    );
    if (path == null || !mounted) return;
    setState(() => _iconPath = path);
  }

  /// מאיזה קובץ הרצה לחלץ. הסדר הוא סדר האיכות: התוכנה עצמה כשהיא
  /// מותקנת כאן, ואחריה המתקין ששמור על הכונן — שנושא כמעט תמיד את אותו
  /// אייקון, וזה הקובץ היחיד שקיים במחשב המקוון.
  String? _iconSourceExe() {
    if (!ExeIconExtractor.isSupported) return null;

    final id = widget.existing?.descriptor.id;
    if (id != null) {
      for (final app in widget.controller.apps) {
        if (app.descriptor.id != id) continue;
        if (app.installed?.launchPath case final path?) return path;
      }
      final stored = widget.controller.storedInstallerPathOf(id);
      if (stored != null && p.extension(stored).toLowerCase() == '.exe') {
        return stored;
      }
    }
    final local = _localFilePath;
    if (local != null && p.extension(local).toLowerCase() == '.exe') {
      return local;
    }
    return null;
  }

  Future<void> _extractIcon() async {
    final source = _iconSourceExe();
    if (source == null) return;

    setState(() => _isExtractingIcon = true);
    final extracted = await ExeIconExtractor.extract(source);
    if (!mounted) return;
    setState(() {
      _isExtractingIcon = false;
      if (extracted != null) _iconPath = extracted;
    });

    final t = AppL10n.strings.customApps;
    if (extracted == null) {
      UiSnack.showError(t.extractIconFailedSnack);
      return;
    }
    UiSnack.showSuccess(t.extractedIconSnack(p.basename(source)));
  }

  // ── צילומי מסך ────────────────────────────────────────────────────────

  Widget _screenshotsSection(BuildContext context) {
    final t = context.strings.customApps;

    return _labelled(
      context,
      t.screenshotsLabel,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _screenshots.length; i++)
            _ScreenshotRow(
              path: _screenshots[i],
              // התמונה הראשונה היא זו שנראית ראשונה בדף, ולכן הסדר כן
              // משנה — והדרך לשנות אותו היא הזזה ולא הסרה ובחירה מחדש.
              onMoveBack: i == 0 ? null : () => _moveScreenshot(i, i - 1),
              onMoveForward: i == _screenshots.length - 1
                  ? null
                  : () => _moveScreenshot(i, i + 1),
              onRemove: () => setState(() => _screenshots.removeAt(i)),
            ),
          if (_screenshots.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
              child: Text(
                t.screenshotsChosen(_screenshots.length),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ActionButton.neutral(
            text: t.addScreenshotsButton,
            icon: FluentIcons.image_multiple_24_regular,
            onPressed: _pickScreenshots,
          ),
        ],
      ),
    );
  }

  void _moveScreenshot(int from, int to) {
    setState(() {
      final path = _screenshots.removeAt(from);
      _screenshots.insert(to, path);
    });
  }

  Future<void> _pickScreenshots() async {
    final t = context.strings.customApps;
    final picked = await NativeFileDialogs.pickManyFiles(
      dialogTitle: t.pickScreenshotsDialogTitle,
      allowedExtensions: _imageExtensions,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _screenshots = [..._screenshots, ...picked]);
  }
}

extension _LetExtension<T> on T {
  R let<R>(R Function(T) transform) => transform(this);
}

/// הסיומות שדיאלוג הבחירה מציע. אותה רשימה שמאשרת `CustomAppMedia` —
/// עדיף לסנן בדיאלוג מאשר לדחות אחרי שהמשתמש כבר בחר.
final List<String> _imageExtensions = [
  for (final extension in CustomAppMedia.allowedExtensions)
    extension.substring(1),
];

/// שורת צילום מסך אחת בטופס: תצוגה מקדימה, הזזה בסדר, והסרה.
class _ScreenshotRow extends StatelessWidget {
  const _ScreenshotRow({
    required this.path,
    required this.onMoveBack,
    required this.onMoveForward,
    required this.onRemove,
  });

  final String path;
  final VoidCallback? onMoveBack;
  final VoidCallback? onMoveForward;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: StoreThumbnail(
              imagePath: path,
              placeholderIcon: FluentIcons.image_off_24_regular,
              aspectRatio: 16 / 9,
              iconSize: 20,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Text(
              p.basename(path),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          // ⚠️ חיצים ולא `RtlIcon`: אלה חיצי סדר ברשימה אנכית, ו-RTL
          // אינו הופך "למעלה" ו"למטה".
          SecondaryIconButton(
            icon: FluentIcons.arrow_up_24_regular,
            tooltip: t.moveScreenshotBackTooltip,
            onPressed: onMoveBack,
          ),
          SecondaryIconButton(
            icon: FluentIcons.arrow_down_24_regular,
            tooltip: t.moveScreenshotForwardTooltip,
            onPressed: onMoveForward,
          ),
          SecondaryIconButton(
            icon: FluentIcons.delete_24_regular,
            tooltip: t.removeScreenshotTooltip,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
