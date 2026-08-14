import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

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
  final _installDir = TextEditingController();
  final _exeName = TextEditingController();
  final _githubUrl = TextEditingController();

  AppSourceKind _source = AppSourceKind.github;

  /// מקור "קובץ שלי" — הקובץ שנבחר.
  String? _localFilePath;

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
      _installDir.text = descriptor.installDir ?? '';
      _exeName.text = descriptor.detect.exeName ?? '';
      _source = descriptor.sourceKind;
      if (descriptor.github case final source?) _githubUrl.text = source.webUrl;
    }
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _description,
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
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: t.pickInstallerDialogTitle,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    // סוג ההתקנה **אינו** נשאל ואינו נשמר — הוא נקבע מהקובץ עצמו בזמן
    // ההתקנה. ראו `CustomAppInstaller.install`.
    setState(() {
      _localFilePath = path;
      if (_name.text.isEmpty) _name.text = p.basenameWithoutExtension(path);
    });
  }

  // ── מיקום ההתקנה ──────────────────────────────────────────────────────────

  Future<void> _pickInstallDir() async {
    final t = context.strings.customApps;
    final dir = await FilePicker.platform.getDirectoryPath(
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
      // שדות שהטופס אינו מציג נגררים כמות שהם — עריכה של שם לא אמורה
      // למחוק בשקט שדה שהמשתמש אינו רואה בכלל.
      publisher: existing?.publisher,
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
              const SizedBox(height: AppTokens.spaceSM),
              _sourcePicker(context),
              const SizedBox(height: AppTokens.spaceLG),
              if (_source == AppSourceKind.github)
                _githubSection(context)
              else
                _localFileSection(context),
              const SizedBox(height: AppTokens.spaceLG),
              const SizedBox(height: AppTokens.spaceLG),
              _installDirRow(context),
              _field(t.exeNameLabel, _exeName, hint: t.exeNameHint),
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
        const SizedBox(height: AppTokens.spaceSM),
        ActionButton.neutral(
          text: t.pickInstallerButton,
          icon: FluentIcons.folder_open_24_regular,
          isLoading: _isFetching,
          onPressed: _isFetching ? null : _pickLocalFile,
        ),
      ],
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

  Widget _field(String label, TextEditingController controller,
      {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
      child: RtlTextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, helperText: hint),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

extension _LetExtension<T> on T {
  R let<R>(R Function(T) transform) => transform(this);
}
