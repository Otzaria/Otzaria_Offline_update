import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/coming_soon_card.dart';
import '../widgets/module_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.dataDir});

  final String dataDir;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final OtzariaModuleController _otzaria;
  late final LibraryModuleController _library;

  @override
  void initState() {
    super.initState();
    _otzaria = OtzariaModuleController(dataDir: widget.dataDir)..addListener(_onChange);
    _library = LibraryModuleController(dataDir: widget.dataDir)..addListener(_onChange);
    _syncOtzaria();
    _syncLibrary();
  }

  void _onChange() => setState(() {});

  /// בודק עדכון ל-אוצריא, ואם יש — מוריד ומתקין אותו **מיד, אוטומטית**
  /// (לא מחכה ללחיצה על "עדכן"). המטרה: שבסוף הריצה הראשונה המשתמש כבר
  /// מסונכרן עם הגרסה העדכנית ביותר, ויכול לעבוד לגמרי אופליין מכאן.
  Future<void> _syncOtzaria() async {
    await _otzaria.checkForUpdate();
    if (_otzaria.status == OtzariaModuleStatus.updateAvailable) {
      await _otzaria.update();
    }
  }

  /// אותו דבר עבור מסד הספרייה.
  Future<void> _syncLibrary() async {
    await _library.checkForUpdate();
    if (_library.status == LibraryModuleStatus.updateAvailable) {
      await _library.update();
    }
  }

  @override
  void dispose() {
    _otzaria.removeListener(_onChange);
    _library.removeListener(_onChange);
    _otzaria.dispose();
    _library.dispose();
    super.dispose();
  }

  Future<void> _pickLibraryFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'בחר/י את קובץ seforim.db',
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    final path = result?.files.single.path;
    if (path != null) {
      await _library.setCustomDbPath(path);
    }
  }

  /// בוחר תיקיית מראה מקומית (offline) קיימת ועובר לעדכן ממנה — למשל
  /// כונן USB שהוכן מראש במחשב אחר דרך "הכנת עדכון להעברה".
  Future<void> _pickLocalMirrorFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחר/י את תיקיית המראה המקומית (USB / תיקייה משותפת)',
    );
    if (path != null) {
      await _library.useLocalMirror(path);
    }
  }

  /// בוחר תיקיית יעד ומייצא אליה מראה מקומית מלאה מה-cloud — להעברה
  /// למחשב בלי אינטרנט בכלל. דורש אינטרנט בעצמו.
  Future<void> _pickExportDestinationAndRun() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחר/י תיקיית יעד לייצוא (USB / תיקייה משותפת)',
    );
    if (path != null) {
      await _library.exportOfflineMirror(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("לאנצ'ר אוצריא")),
      body: RefreshIndicator(
        color: AppColors.ink,
        onRefresh: () async {
          await Future.wait([_syncOtzaria(), _syncLibrary()]);
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'ניהול העדכונים שלך',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'בפתיחה, הלאנצ׳ר בודק ומוריד אוטומטית את הגרסאות העדכניות ביותר '
              'של אוצריא והספרייה — כדי שתוכל/י להמשיך לעבוד לגמרי אופליין.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _buildOtzariaCard(),
            const SizedBox(height: 16),
            _buildLibraryCard(),
            const SizedBox(height: 16),
            const ComingSoonCard(
              icon: Icons.extension_outlined,
              title: 'חנות התוספים',
              subtitle: 'ניהול והתקנת תוספים לאוצריא יתווסף כאן.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtzariaCard() {
    final c = _otzaria;
    final subtitle = switch (c.status) {
      OtzariaModuleStatus.idle || OtzariaModuleStatus.checking => 'בודק גרסה מותקנת...',
      _ when c.currentVersion == null => 'טרם הותקנה על ידי הלאנצ׳ר הזה',
      _ => 'גרסה מותקנת: ${c.currentVersion}',
    };

    return ModuleCard(
      icon: Icons.menu_book_outlined,
      title: 'אוצריא',
      subtitle: subtitle,
      status: switch (c.status) {
        OtzariaModuleStatus.idle || OtzariaModuleStatus.checking => ModuleStatus.loading,
        OtzariaModuleStatus.upToDate => ModuleStatus.upToDate,
        OtzariaModuleStatus.updateAvailable => ModuleStatus.updateAvailable,
        OtzariaModuleStatus.updating => ModuleStatus.updating,
        OtzariaModuleStatus.error => ModuleStatus.error,
      },
      statusLabel: switch (c.status) {
        OtzariaModuleStatus.upToDate => 'מעודכן',
        OtzariaModuleStatus.updateAvailable => 'עדכון זמין: ${c.latestVersion}',
        OtzariaModuleStatus.updating => 'מעדכן...',
        OtzariaModuleStatus.error => 'שגיאה',
        _ => null,
      },
      progress: (c.downloadReceived != null && c.downloadTotal != null && c.downloadTotal! > 0)
          ? c.downloadReceived! / c.downloadTotal!
          : null,
      errorMessage: c.errorMessage,
      primaryActionLabel: switch (c.status) {
        OtzariaModuleStatus.updateAvailable => 'עדכן',
        OtzariaModuleStatus.upToDate => 'הפעל',
        OtzariaModuleStatus.error => 'נסה שוב',
        _ => null,
      },
      onPrimaryAction: switch (c.status) {
        OtzariaModuleStatus.updateAvailable => c.update,
        OtzariaModuleStatus.upToDate => c.launch,
        OtzariaModuleStatus.error => _syncOtzaria,
        _ => null,
      },
    );
  }

  Widget _buildLibraryCard() {
    final c = _library;

    if (c.status == LibraryModuleStatus.needsManualPath) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModuleCard(
            icon: Icons.storage_outlined,
            title: 'ספריית הספרים (DB)',
            subtitle: 'לא נמצא קובץ seforim.db במיקום ברירת המחדל.',
            status: ModuleStatus.needsAction,
            statusLabel: 'נדרשת פעולה',
            primaryActionLabel: 'בחר/י מיקום',
            onPrimaryAction: _pickLibraryFile,
          ),
          _buildLibrarySourceRow(),
        ],
      );
    }

    final mirrorPath = c.activeMirrorPath;
    final sourceNote = mirrorPath != null ? ' (מקור: מראה מקומית — $mirrorPath)' : '';

    final subtitle = switch (c.status) {
      LibraryModuleStatus.idle || LibraryModuleStatus.checking =>
        'בודק גרסת מסד...$sourceNote',
      _ when c.localVersion == null || c.isFreshInstall =>
        'מוריד ספרייה בפעם הראשונה...$sourceNote',
      _ => 'גרסת מסד: ${c.localVersion}$sourceNote',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleCard(
          icon: Icons.storage_outlined,
          title: 'ספריית הספרים (DB)',
          subtitle: subtitle,
          status: switch (c.status) {
            LibraryModuleStatus.idle || LibraryModuleStatus.checking => ModuleStatus.loading,
            LibraryModuleStatus.upToDate => ModuleStatus.upToDate,
            LibraryModuleStatus.updateAvailable => ModuleStatus.updateAvailable,
            LibraryModuleStatus.updating => ModuleStatus.updating,
            LibraryModuleStatus.error => ModuleStatus.error,
            LibraryModuleStatus.needsManualPath => ModuleStatus.needsAction,
          },
          statusLabel: switch (c.status) {
            LibraryModuleStatus.upToDate => 'מעודכן',
            LibraryModuleStatus.updateAvailable =>
              c.isFreshInstall ? 'מוריד ספרייה...' : 'עדכון זמין: גרסה ${c.targetVersion}',
            LibraryModuleStatus.updating => 'מעדכן...',
            LibraryModuleStatus.error => 'שגיאה',
            _ => null,
          },
          progress: (c.downloadReceived != null && c.downloadTotal != null && c.downloadTotal! > 0)
              ? c.downloadReceived! / c.downloadTotal!
              : null,
          stageText: c.stageText,
          errorMessage: c.errorMessage,
          primaryActionLabel: switch (c.status) {
            LibraryModuleStatus.updateAvailable => 'עדכן',
            LibraryModuleStatus.error => 'נסה שוב',
            _ => null,
          },
          onPrimaryAction: switch (c.status) {
            LibraryModuleStatus.updateAvailable => c.update,
            LibraryModuleStatus.error => _syncLibrary,
            _ => null,
          },
        ),
        _buildLibrarySourceRow(),
      ],
    );
  }

  /// שורת פעולות קטנה מתחת לכרטיס הספרייה: מעבר בין מקור ה-cloud למראה
  /// מקומית (offline), והכנת מראה כזו להעברה למחשב אחר. מוצג תמיד (לא רק
  /// כשיש בעיה) כי אלה בחירות יזומות של המשתמש, לא תגובה למצב שגיאה.
  Widget _buildLibrarySourceRow() {
    final c = _library;
    final isExporting = c.mirrorExportStatus == MirrorExportStatus.exporting;

    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 8, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            children: [
              if (c.activeMirrorPath == null)
                TextButton.icon(
                  onPressed: isExporting ? null : _pickLocalMirrorFolder,
                  icon: const Icon(Icons.usb_outlined, size: 16),
                  label: const Text('עדכן מתיקייה מקומית (USB)'),
                )
              else
                TextButton.icon(
                  onPressed: isExporting ? null : _library.useCloud,
                  icon: const Icon(Icons.cloud_outlined, size: 16),
                  label: const Text('חזור לעדכון מהענן'),
                ),
              TextButton.icon(
                onPressed: isExporting ? null : _pickExportDestinationAndRun,
                icon: const Icon(Icons.sd_storage_outlined, size: 16),
                label: const Text('הכן עדכון להעברה למחשב אחר'),
              ),
            ],
          ),
          if (isExporting)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.mirrorExportStage ?? 'מייצא מראה מקומית...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (c.mirrorExportDoneAssets != null &&
                              c.mirrorExportTotalAssets != null &&
                              c.mirrorExportTotalAssets! > 0)
                          ? c.mirrorExportDoneAssets! / c.mirrorExportTotalAssets!
                          : null,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            )
          else if (c.mirrorExportStatus == MirrorExportStatus.done)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'הייצוא הושלם — אפשר להעביר את התיקייה למחשב היעד.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.success),
              ),
            )
          else if (c.mirrorExportStatus == MirrorExportStatus.error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'הייצוא נכשל: ${c.mirrorExportError}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.danger),
              ),
            ),
        ],
      ),
    );
  }
}
