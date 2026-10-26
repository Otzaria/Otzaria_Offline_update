import 'dart:async';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../../controllers/custom_apps_controller.dart';
import '../../services/exe_icon_extractor.dart';
import '../../services/native_file_dialogs.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_form_fields.dart';
import 'custom_app_form_media.dart';
import 'custom_app_form_source.dart';

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

  /// המשתמש לחץ "הסרת האייקון" ולא בחר אחר במקומו. ראו
  /// [AppDescriptor.autoIcon] — בלי הדגל הזה האייקון היה חוזר מעצמו.
  bool _removedIcon = false;

  /// מקור "קובץ שלי" — הקובץ שנבחר.
  String? _localFilePath;
  String? _localFileError;

  /// מה שהריחרוח מצא בקובץ שנבחר עכשיו, או `null` כשאין קובץ כזה או שלא
  /// ניתן היה לקבוע. מוצג בלבד — ההכרעה האמיתית נעשית שוב בזמן ההתקנה,
  /// מהבייטים של הקובץ ששמור על הכונן.
  CustomInstallerKind? _sniffedKind;

  /// "הקובץ אינו מתקין אלא התוכנה עצמה". נשאל במפורש,
  /// כי אי אפשר להריח אותו: exe נייד ומתקין לא-מוכר נראים זהים.
  bool _portableFile = false;
  bool _interactiveInstall = false;

  /// מקור "גיטהאב" — מה שחזר מהריפו.
  GithubRelease? _release;
  GithubAsset? _selectedAsset;
  String? _githubError;
  bool _isFetching = false;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  String? _savedId;

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
      _interactiveInstall = descriptor.interactiveInstall;
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
      _savedId ??
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
      if (CustomAppInstaller.supportsPackageName(asset.name)) {
        _selectedAsset = asset;
        _githubError = null;
      } else {
        _selectedAsset = null;
        _githubError = context.strings.customAppsDomain
            .installerUnsupportedFile(asset.name);
      }
    });
  }

  // ── מקור: קובץ מקומי ──────────────────────────────────────────────────────

  Future<void> _pickLocalFile() async {
    final t = context.strings.customApps;
    final path = await NativeFileDialogs.pickFile(
      dialogTitle: t.pickInstallerDialogTitle,
      allowedExtensions: const ['exe', 'msi', 'zip'],
    );
    if (path == null || !mounted) return;
    if (!CustomAppInstaller.supportsPackageName(path)) {
      setState(
        () => _localFileError = context.strings.customAppsDomain
            .installerUnsupportedFile(p.basename(path)),
      );
      return;
    }

    // סוג ההתקנה **אינו** נשאל ואינו נשמר — הוא נקבע מהקובץ עצמו בזמן
    // ההתקנה. ראו `CustomAppInstaller.install`.
    setState(() {
      _localFilePath = path;
      _localFileError = null;
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
    final saved = _isEditing || _savedId != null
        ? await widget.controller.update(descriptor)
        : await widget.controller.add(descriptor);
    if (!saved) {
      if (mounted) setState(() => _isSaving = false);
      UiSnack.showFailure(widget.controller.errorMessage);
      return;
    }
    _savedId = descriptor.id;

    // קובץ מקומי נאסף מיד: המשתמש יוצא מכאן עם תוכנה מוכנה לנסוע על
    // הכונן, ולא עם רישום ריק. מקור גיטהאב יורד בלחיצה נפרדת, כי הוא
    // הפעולה הכבדה שדורשת רשת.
    if (_source == AppSourceKind.manual && _localFilePath != null) {
      final attached = await widget.controller.attachInstaller(
        descriptor.id,
        sourcePath: _localFilePath!,
        version: readInstallerVersion(_localFilePath!) ?? '',
      );
      if (attached == null) {
        if (mounted) setState(() => _isSaving = false);
        UiSnack.showFailure(widget.controller.errorMessage);
        return;
      }
    }
    // המדיה נכתבת אחרי הרשומה ולא לפניה: היא נשמרת בתיקייה שהרשומה
    // יוצרת, ושמות הקבצים נרשמים בה בסיום. כשלון כאן אינו מבטל את
    // השמירה — הרשומה עצמה כבר נכונה.
    if (!await widget.controller.saveMedia(
      descriptor.id,
      iconSource: _iconPath,
      screenshotSources: _screenshots,
    )) {
      UiSnack.showFailure(widget.controller.errorMessage);
    }
    // מי שלא בחר אייקון מקבל אותו לבד מקובץ ההרצה — ברירת המחדל.
    unawaited(widget.controller.fillMissingIcons());
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
      // הסרה **מפורשת** של אייקון מכבה את המילוי האוטומטי, אחרת הוא היה
      // מחזיר אותו בכניסה הבאה למסך.
      autoIcon: _removedIcon ? false : (existing?.autoIcon ?? true),
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
      interactiveInstall: !_portableFile && _interactiveInstall,
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

  /// הסדר של האשף במוקאפ: מאיפה, איזה קובץ, ואז הפרטים — בדו-שיח אחד.
  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    void rebuild(String _) => setState(() {});
    const pad = AppTokens.spaceLG;
    final github = _source == AppSourceKind.github;

    return AlertDialog(
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.all(pad),
      title: Text(_isEditing ? t.editDialogTitle : t.addDialogTitle),
      content: SizedBox(
        width: AppTokens.dialogFormWidth - 2 * pad,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SectionLabel(t.formStepSource, first: true),
              OptionCard(
                icon: FluentIcons.globe_24_regular,
                title: t.sourceGithubOption,
                description: t.sourceGithubOptionHint,
                selected: github,
                onSelected: () =>
                    setState(() => _source = AppSourceKind.github),
              ),
              const SizedBox(height: 10),
              OptionCard(
                icon: FluentIcons.folder_open_24_regular,
                title: t.sourceFileOption,
                description: t.sourceFileOptionHint,
                selected: !github,
                onSelected: () =>
                    setState(() => _source = AppSourceKind.manual),
              ),
              SectionLabel(github ? t.formStepGithubFile : t.formStepLocalFile),
              if (github)
                CustomAppGithubSection(
                  urlController: _githubUrl,
                  onUrlChanged: rebuild,
                  isFetching: _isFetching,
                  onFetch: _fetchAssets,
                  hasKeptAsset: _keptAssetPattern != null,
                  error: _githubError,
                  release: _release,
                  selectedAsset: _selectedAsset,
                  onSelectAsset: _selectAsset,
                )
              else
                CustomAppLocalFileSection(
                  path: _localFilePath,
                  kept: _keptInstaller,
                  sniffedKind: _sniffedKind,
                  onPick: _pickLocalFile,
                  error: _localFileError,
                ),
              // "זו התוכנה עצמה" נשאל דווקא משום שאי אפשר להריח אותו: exe
              // נייד ומתקין של framework לא מוכר נראים זהים לחלוטין.
              FormCheckRow(
                label: t.portableFileLabel,
                help: t.portableFileHint,
                value: _portableFile,
                onChanged: (value) => setState(() => _portableFile = value),
              ),
              if (!_portableFile)
                FormCheckRow(
                  label: t.interactiveInstallLabel,
                  help: t.interactiveInstallHint,
                  value: _interactiveInstall,
                  onChanged: (value) =>
                      setState(() => _interactiveInstall = value),
                ),
              SectionLabel(t.formStepDetails),
              FormTextField(
                label: t.nameLabel,
                controller: _name,
                hint: t.nameHint,
                onChanged: rebuild,
              ),
              if (widget.controller.categories.isNotEmpty)
                CustomAppCategoriesPicker(
                  categories: widget.controller.categories,
                  selected: _categories,
                  onToggle: (slug) => setState(() {
                    if (!_categories.remove(slug)) _categories.add(slug);
                  }),
                ),
              FormTextField(
                label: t.descriptionLabel,
                controller: _description,
                hint: t.descriptionHint,
              ),
              FormTextField(
                label: t.longDescriptionLabel,
                controller: _longDescription,
                hint: t.longDescriptionHint,
                maxLines: 3,
              ),
              // תוכנה ניידת: התיקייה נבחרת בכל מחשב בזמן ההתקנה, ואין מה לזהות.
              if (_portableFile)
                FormLabelled(
                  label: t.installDirLabel,
                  child: Text(
                    t.portableDestinationHint,
                    style: AppTextStyles.body.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else ...[
                FormTextField(
                  label: t.installDirLabel,
                  controller: _installDir,
                  hint: t.installDirHint,
                  onChanged: rebuild,
                  ltr: true,
                  trailing: ActionButton.neutral(
                    text: t.pickInstallDirButton,
                    onPressed: _pickInstallDir,
                  ),
                ),
                FormTextField(
                  label: t.exeNameLabel,
                  controller: _exeName,
                  hint: t.exeNameHint,
                  onChanged: rebuild,
                  ltr: true,
                ),
              ],
              CustomAppIconSection(
                iconPath: _iconPath,
                canExtract: _iconSourceExe() != null,
                isExtracting: _isExtractingIcon,
                onPick: _pickIcon,
                onExtract: _extractIcon,
                onRemove: () => setState(() {
                  _iconPath = null;
                  _removedIcon = true;
                }),
              ),
              CustomAppScreenshotsSection(
                screenshots: _screenshots,
                onMove: _moveScreenshot,
                onRemove: (i) => setState(() => _screenshots.removeAt(i)),
                onAdd: _pickScreenshots,
              ),
            ],
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTokens.spaceSM,
          children: [
            ActionButton.ghost(
              text: context.strings.common.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
            ActionButton.recommended(
              text: _isEditing ? t.saveEditButton : t.saveButton,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }

  // ── מדיה ──────────────────────────────────────────────────────────────

  Future<void> _pickIcon() async {
    final t = context.strings.customApps;
    final path = await NativeFileDialogs.pickFile(
      dialogTitle: t.pickIconDialogTitle,
      allowedExtensions: customAppImageExtensions,
    );
    if (path == null || !mounted) return;
    setState(() {
      _iconPath = path;
      _removedIcon = false;
    });
  }

  /// מאיזה קובץ הרצה לחלץ — הבחירה עצמה יושבת בקונטרולר
  /// ([CustomAppsController.iconSourceExeOf]), כי גם המילוי האוטומטי
  /// משתמש בה. כאן נוסף רק הקובץ שנבחר עכשיו בטופס וטרם נשמר.
  String? _iconSourceExe() {
    if (!ExeIconExtractor.isSupported) return null;

    final id = widget.existing?.descriptor.id;
    if (id != null) {
      for (final app in widget.controller.apps) {
        if (app.descriptor.id != id) continue;
        if (widget.controller.iconSourceExeOf(app) case final path?) {
          return path;
        }
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
      if (extracted != null) {
        _iconPath = extracted;
        _removedIcon = false;
      }
    });

    final t = AppL10n.strings.customApps;
    if (extracted == null) {
      UiSnack.showError(t.extractIconFailedSnack);
      return;
    }
    UiSnack.showSuccess(t.extractedIconSnack(p.basename(source)));
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
      allowedExtensions: customAppImageExtensions,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _screenshots = [..._screenshots, ...picked]);
  }
}

extension _LetExtension<T> on T {
  R let<R>(R Function(T) transform) => transform(this);
}
