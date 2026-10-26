import 'dart:io';
import 'dart:ui' as ui;

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_detail_view.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_install_action.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_manage_page.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

/// מצבי חנות התוספים והתוכנות הנוספות — לצילומי הסקירה של שלב 4. הנתונים
/// כמו במוקאפ, בלי רשת; התמונות מצוירות לתיקייה זמנית.

/// קונטרולר שמצב ההתקנה שלו נקבע ביד — בלי סריקת אוצריא האמיתית.
class FixturePlugins extends PluginsModuleController {
  FixturePlugins(String dir) : super(mirrorRootDir: dir);

  Set<String> disabled = {};
  Set<String> development = {};
  bool fakeSyncing = false;

  @override
  bool isDisabledInOtzaria(StorePlugin plugin) =>
      disabled.contains(plugin.manifestId);

  @override
  bool isDevelopmentInOtzaria(StorePlugin plugin) =>
      development.contains(plugin.manifestId);

  @override
  bool get isSyncing => fakeSyncing || super.isSyncing;
}

class FixtureApps extends CustomAppsController {
  FixtureApps(String dir) : super(mirrorRootDir: p.join(dir, 'apps-mirror'));

  Map<String, List<String>> shots = {};

  @override
  List<String> shownScreenshotPathsOf(AppDescriptor descriptor) =>
      shots[descriptor.id] ?? const [];
}

StorePlugin _plugin(
  String id,
  String name, {
  required String desc,
  required String version,
  double rating = 4.5,
  int votes = 10,
  String status = 'stable',
  bool net = false,
  String compatibleWith = '',
  List<String> tags = const [],
  String author = 'מפתח',
  String date = '2026-10-20',
  bool file = true,
  bool image = true,
  int size = 1400000,
  List<String> screenshots = const [],
  List<String> categories = const [],
}) {
  final plugin = StorePlugin.fromApi({
    'id': id,
    'name': name,
    'shortDescription': desc,
    'description': '$desc\n\nלחיצה על יום פותחת את הלימוד שלו: הפרשה, '
        'ההפטרה וההלכות של המועד. אפשר להוסיף אירועים אישיים, והתוסף יזכיר '
        'אותם בכל שנה לפי התאריך העברי.',
    'version': version,
    'status': status,
    'author': author,
    'originalDate': date,
    'compatibleWith': compatibleWith,
    'requiresNetwork': net,
    'tags': tags,
    'homepage': 'https://github.com/example/$id',
    'downloadCount': votes * 61,
    'supportsDirectInstall': true,
    'ratingAvg': rating,
    'ratingCount': votes,
    'ratingVerifiedCount': votes ~/ 3,
    'ratingBreakdown': [0, 0, votes ~/ 10, votes ~/ 5, votes - votes ~/ 5],
    'downloadUrl': '/api/plugins/$id/download',
    'pluginUid': 'org.example.$id',
    'versions': [
      {
        'version': version,
        'status': status,
        'compatibleWith': compatibleWith,
        'pluginFileSize': size,
        'releasedAt': date,
        'isLatest': true,
      },
      {
        'version': '1.0.0',
        'status': 'stable',
        'compatibleWith': compatibleWith,
        'pluginFileSize': size - 200000,
        'releasedAt': '2026-08-02',
      },
    ],
  }, 'https://otzaria.org');
  return plugin.copyWith(
    imagePath: image ? 'files/$id/icon.png' : null,
    screenshotPaths: screenshots,
    categorySlugs: categories,
    localFiles: file
        ? {
            version: PluginLocalFile(
              relativePath: 'files/$id/$id.otzplugin',
              fileName: '$id-$version.otzplugin',
              ext: 'otzplugin',
              size: size,
            ),
          }
        : const {},
  );
}

final _catalog = [
  _plugin('cal', 'לוח שנה עברי',
      desc: 'לוח שנה עברי מלא עם פרשת השבוע, מועדים וראשי חודשים, ומעבר מהיר '
          'לספרים של היום.',
      version: '2.4.0',
      rating: 4.8,
      votes: 41,
      tags: const ['לוח שנה', 'מועדים', 'פרשת השבוע'],
      author: 'יוסף ברגר',
      screenshots: const [
        'files/cal/s1.png',
        'files/cal/s2.png',
        'files/cal/s3.png'
      ],
      categories: const ['zmanim']),
  _plugin('zmanim', 'מזומנים',
      desc: 'זמני היום לפי המקום שלכם: עלות השחר, סוף זמן קריאת שמע ותפילה, '
          'שקיעה וצאת הכוכבים.',
      version: '1.7.0',
      rating: 4.7,
      votes: 28,
      tags: const ['זמני היום', 'הלכה'],
      categories: const ['zmanim']),
  _plugin('shnayim', 'שניים מקרא',
      desc: 'שניים מקרא ואחד תרגום לפי פרשת השבוע, מחולק לימי השבוע עם סימון '
          'של מה שכבר קראתם.',
      version: '1.3.0',
      rating: 4.9,
      votes: 63,
      categories: const ['daily']),
  _plugin('daf', 'דף יומי',
      desc: 'הדף היומי ומחזורי לימוד נוספים, עם פתיחה ישירה לדף של היום '
          'ותזכורת עדינה.',
      version: '1.0.4',
      rating: 4.6,
      votes: 19,
      categories: const ['daily']),
  _plugin('shamor', 'שמור וזכור',
      desc: 'סימון של מה שלמדתם בכל ספר, וחזרה מהירה לנקודה שבה עצרתם בפעם '
          'הקודמת.',
      version: '3.1.0',
      rating: 4.8,
      votes: 35,
      image: false,
      categories: const ['daily']),
  _plugin('aramit', 'מילון ארמית',
      desc: 'פירוש מילים בארמית בלחיצה על מילה בגמרא ובתרגום אונקלוס, עם '
          'דוגמאות מהמקורות.',
      version: '0.9.2',
      rating: 4.4,
      votes: 12,
      status: 'beta',
      categories: const ['tools']),
  _plugin('colors', 'סימניות צבעוניות',
      desc: 'סימון קטעים בצבעים שונים לפי נושא, ומעבר מהיר בין כל הסימונים '
          'בספר.',
      version: '1.5.0',
      rating: 4.2,
      votes: 16,
      categories: const ['view']),
  _plugin('tikkun', 'תיקון קוראים',
      desc: 'תצוגה כפולה של הפרשה, עם טעמים ובלי, לקריאה בתורה ולחזרה עליה.',
      version: '2.0.0',
      rating: 4.7,
      votes: 22,
      compatibleWith: '0.11.0',
      categories: const ['tools']),
  _plugin('nusach', 'סידור לפי נוסח',
      desc: 'סידור תפילה מלא בנוסח אשכנז, ספרד ועדות המזרח, עם התאמה ללוח '
          'השנה.',
      version: '1.1.0',
      votes: 30,
      file: false,
      categories: const ['daily']),
  _plugin('maps', 'מפות ארץ ישראל',
      desc: 'מקומות מהתנ״ך ומהתלמוד על גבי מפה, עם קישור ישיר למקורות שבהם הם '
          'מוזכרים.',
      version: '1.1.0',
      rating: 4.3,
      votes: 9,
      net: true,
      categories: const ['view']),
  _plugin('mydev', 'התוסף שלי',
      desc: 'תוסף שאתם מפתחים במחשב הזה. אוצריא טוענת אותו ישירות מהתיקייה '
          'שלו.',
      version: '0.1.0',
      votes: 0,
      rating: 0,
      image: false,
      categories: const ['tools']),
];

const _categories = [
  PluginStoreCategory(
    slug: 'zmanim',
    name: 'לוח וזמנים',
    pluginIds: ['cal', 'zmanim'],
  ),
  PluginStoreCategory(
    slug: 'daily',
    name: 'לימוד יומי',
    pluginIds: ['shnayim', 'daf', 'shamor', 'nusach'],
  ),
  PluginStoreCategory(
    slug: 'tools',
    name: 'כלי עיון',
    pluginIds: ['aramit', 'tikkun', 'mydev'],
  ),
  PluginStoreCategory(
    slug: 'view',
    name: 'מפות ותצוגה',
    pluginIds: ['colors', 'maps'],
  ),
];

const _glyphs = {
  'cal': FluentIcons.calendar_ltr_24_regular,
  'zmanim': FluentIcons.clock_24_regular,
  'shnayim': FluentIcons.book_open_24_regular,
  'daf': FluentIcons.history_24_regular,
  'aramit': FluentIcons.book_24_regular,
  'colors': FluentIcons.tag_24_regular,
  'tikkun': FluentIcons.text_bullet_list_24_regular,
  'nusach': FluentIcons.document_text_24_regular,
  'maps': FluentIcons.globe_24_regular,
};

/// מצייר סמל Fluent ל-PNG — "התמונה שהאתר שלח" לכל תוסף.
Future<void> _paintIcon(String path, IconData icon) async {
  const size = 128.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: 96,
        color: const Color(0xFF805610),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );
  await _save(recorder, size.toInt(), size.toInt(), path);
}

/// צילום מסך מומצא: חלון קטן עם לוח חודש.
Future<void> _paintShot(String path, int highlight) async {
  const w = 640, h = 400;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromLTRBR(0, 0, w.toDouble(), h.toDouble(), const Radius.circular(8)),
    Paint()..color = const Color(0xFFFFF8F4),
  );
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 30),
    Paint()..color = const Color(0xFFF3E6DA),
  );
  for (var i = 0; i < 35; i++) {
    final col = i % 7, row = i ~/ 7;
    final rect = Rect.fromLTWH(20 + col * 86.0, 46 + row * 68.0, 80, 60);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..color = i == highlight
            ? const Color(0xFF805610)
            : (i % 9 == 0 ? const Color(0xFFFBDEBC) : const Color(0xFFF9ECDF)),
    );
  }
  await _save(recorder, w, h, path);
}

Future<void> _save(
    ui.PictureRecorder recorder, int w, int h, String path) async {
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path)..parent.createSync(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

/// הקונטרולרים והתיקייה של מצב אחד.
class StoreFixture {
  StoreFixture(this.dir)
      : plugins = FixturePlugins(dir),
        apps = FixtureApps(dir);

  final String dir;
  final FixturePlugins plugins;
  final FixtureApps apps;

  String get _pluginsDir => p.join(dir, 'plugins');

  /// מצייר את התמונות. רץ ב-`runAsync`.
  Future<void> paint() async {
    for (final MapEntry(key: id, value: icon) in _glyphs.entries) {
      await _paintIcon(p.join(_pluginsDir, 'files', id, 'icon.png'), icon);
    }
    for (var i = 0; i < 3; i++) {
      await _paintShot(
          p.join(_pluginsDir, 'files', 'cal', 's${i + 1}.png'), 19 + i);
    }
    await _paintShot(p.join(dir, 'apps-shot.png'), 12);
  }

  void seedPlugins({bool empty = false}) {
    plugins
      ..plugins = empty ? const [] : _catalog
      ..categories = empty ? const [] : _categories
      ..pluginsDir = _pluginsDir
      ..lastSync = DateTime(2026, 10, 18)
      ..appVersion = '0.10.3'
      ..status = PluginsModuleStatus.ready
      ..installed = const {
        'org.example.cal': '2.3.1',
        'org.example.zmanim': '1.6.0',
        'org.example.shnayim': '1.2.0',
        'org.example.shamor': '3.1.0',
        'org.example.colors': '1.4.0',
        'org.example.mydev': '0.1.0',
      };
    plugins
      ..disabled = {'org.example.colors'}
      ..development = {'org.example.mydev'};
  }

  void seedApps({bool empty = false}) {
    StoredInstaller stored(String file, String version, int mb) =>
        StoredInstaller(
          fileName: file,
          version: version,
          sizeBytes: mb * 1024 * 1024,
          addedAt: DateTime(2026, 9, 3),
        );
    apps
      ..categories = empty
          ? const []
          : const [
              CustomAppCategory(slug: 'audio', name: 'שמע'),
              CustomAppCategory(slug: 'dict', name: 'מילונים'),
            ]
      ..apps = empty
          ? const []
          : [
              CustomAppView(
                entry: CustomAppEntry(
                  descriptor: const AppDescriptor(
                    id: 'player',
                    name: 'נגן שיעורים',
                    description:
                        'נגן לקובצי שמע של שיעורים, עם המשך מהמקום שבו '
                        'עצרתם ושינוי מהירות ההשמעה.',
                    longDescription: 'נגן פשוט לשיעורים מוקלטים. זוכר איפה '
                        'עצרתם בכל קובץ, ומאפשר להאיץ או להאט את ההשמעה.',
                    categorySlugs: ['audio'],
                    sourceKind: AppSourceKind.github,
                    github: GithubSource(
                      owner: 'example',
                      repo: 'shiur-player',
                      assetPattern: r'^ShiurPlayer-.*-setup\.exe$',
                    ),
                    detect: AppDetectRules(exeName: 'ShiurPlayer.exe'),
                  ),
                  installer: stored('ShiurPlayer-4.2.0-setup.exe', '4.2.0', 86),
                ),
                installed: const CustomAppInstallState(
                  version: '4.2.0',
                  installDir: r'C:\Program Files\ShiurPlayer',
                  launchPath: r'C:\Program Files\ShiurPlayer\ShiurPlayer.exe',
                ),
              ),
              CustomAppView(
                entry: CustomAppEntry(
                  descriptor: const AppDescriptor(
                    id: 'dict',
                    name: 'מילון עברי־אנגלי',
                    description:
                        'מילון מלא שעובד בלי אינטרנט, כולל ניקוד, הטיות '
                        'ודוגמאות שימוש.',
                    categorySlugs: ['dict'],
                    sourceKind: AppSourceKind.manual,
                    detect: AppDetectRules(exeName: 'Dict.exe'),
                  ),
                  installer: stored('Dict-2.1.exe', '2.1', 34),
                ),
              ),
              CustomAppView(
                entry: CustomAppEntry(
                  descriptor: const AppDescriptor(
                    id: 'editor',
                    name: 'עורך מסמכים',
                    description: 'עורך מסמכים בעברית עם תמיכה בניקוד, הערות '
                        'שוליים ויצוא ל-PDF.',
                    sourceKind: AppSourceKind.github,
                    github: GithubSource(
                      owner: 'example',
                      repo: 'doc-editor',
                      assetPattern: r'^Editor-.*\.exe$',
                    ),
                    detect: AppDetectRules(exeName: 'Editor.exe'),
                  ),
                  installer: stored('Editor-7.5.exe', '7.5', 212),
                ),
                installed: const CustomAppInstallState(
                  version: '7.4',
                  installDir: r'C:\Program Files\Editor',
                  launchPath: r'C:\Program Files\Editor\Editor.exe',
                ),
              ),
            ];
    apps.shots = {
      'player': [p.join(dir, 'apps-shot.png')],
    };
  }

  void dispose() {
    plugins.dispose();
    apps.dispose();
  }
}

/// מצב לצילום: מה בונים, ומה עושים אחרי שעלה (לחיצה, גלילה).
typedef StoreScenario = ({
  Widget Function(StoreFixture f) build,
  Future<void> Function(WidgetTester tester, StoreFixture f)? after,
});

Widget _store(StoreFixture f, {String? detail, bool online = true}) =>
    PluginsScreen(
      controller: f.plugins,
      online: online,
      detailId: detail,
      onDetailChanged: detail == null ? null : (_) {},
    );

Widget _apps(StoreFixture f, {String? detail}) => CustomAppsScreen(
      controller: f.apps,
      detailId: detail,
      onDetailChanged: detail == null ? null : (_) {},
    );

final Map<String, StoreScenario> storeScenarios = {
  'plugins': (
    build: (f) {
      f.seedPlugins();
      return _store(f);
    },
    after: null,
  ),
  'plugins_scrolled': (
    build: (f) {
      f.seedPlugins();
      return _store(f);
    },
    after: (t, f) async {
      await t.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await t.pump();
    },
  ),
  'plugins_offline': (
    build: (f) {
      f.seedPlugins();
      return _store(f, online: false);
    },
    after: null,
  ),
  'plugins_more': (
    build: (f) {
      f.seedPlugins();
      f.plugins.setTagFilter('מועדים');
      return _store(f);
    },
    after: null,
  ),
  'plugins_search': (
    build: (f) {
      f.seedPlugins();
      f.plugins.setSearch('לוח');
      return _store(f);
    },
    after: null,
  ),
  'plugins_none': (
    build: (f) {
      f.seedPlugins();
      f.plugins.setSearch('הגדה של פסח');
      return _store(f);
    },
    after: null,
  ),
  'plugins_empty': (
    build: (f) {
      f.seedPlugins(empty: true);
      return _store(f);
    },
    after: null,
  ),
  'plugins_syncing': (
    build: (f) {
      f.seedPlugins();
      f.plugins
        ..fakeSyncing = true
        ..syncMessage = 'מוריד את לוח שנה עברי (2 מתוך 5)'
        ..syncProgress = 0.4;
      return _store(f);
    },
    after: null,
  ),
  'plugin_cal': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'cal');
    },
    after: null,
  ),
  'plugin_cal_scrolled': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'cal');
    },
    after: (t, f) async {
      await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await t.pump();
    },
  ),
  'lightbox': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'cal');
    },
    after: (t, f) async {
      await t.tap(find.byIcon(FluentIcons.zoom_in_20_regular));
      await t.pump();
    },
  ),
  'plugin_tikkun': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'tikkun');
    },
    after: null,
  ),
  'plugin_colors': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'colors');
    },
    after: null,
  ),
  'plugin_nusach': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'nusach');
    },
    after: null,
  ),
  'plugin_nusach_offline': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'nusach', online: false);
    },
    after: null,
  ),
  'plugins_updating': (
    build: (f) {
      f.seedPlugins();
      f.plugins.updateAllRun = (done: 1, total: 3);
      return _store(f);
    },
    after: null,
  ),
  'plugin_mydev': (
    build: (f) {
      f.seedPlugins();
      return _store(f, detail: 'mydev');
    },
    after: null,
  ),
  'apps': (
    build: (f) {
      f.seedApps();
      return _apps(f);
    },
    after: null,
  ),
  'app_player': (
    build: (f) {
      f.seedApps();
      return _apps(f, detail: 'player');
    },
    after: null,
  ),
  'app_trust': (
    build: (f) {
      f.seedApps();
      return _apps(f);
    },
    after: (t, f) async {
      final context = t.element(find.byType(CustomAppsScreen));
      final app = f.apps.apps[1];
      // ignore: unawaited_futures
      showCustomAppTrustDialog(context, app);
      await t.pump();
    },
  ),
  'manage': (
    build: (f) {
      f.seedApps();
      return CustomAppsManagePage(controller: f.apps);
    },
    after: null,
  ),
  'manage_empty': (
    build: (f) {
      f.seedApps(empty: true);
      return CustomAppsManagePage(controller: f.apps);
    },
    after: null,
  ),
  'addapp': (
    build: (f) {
      f.seedApps();
      return CustomAppsManagePage(controller: f.apps);
    },
    after: (t, f) async {
      final context = t.element(find.byType(CustomAppsManagePage));
      // ignore: unawaited_futures
      openAddCustomApp(context, f.apps);
      await t.pump();
    },
  ),
  'app_detail_editor': (
    build: (f) {
      f.seedApps();
      return CustomAppDetailView(
        controller: f.apps,
        app: f.apps.apps[2],
        readOnly: false,
        onInstall: () {},
        onLaunch: () {},
        onDownload: () {},
        onPickLocation: () {},
        onCategorySelected: (_) {},
      );
    },
    after: null,
  ),
};
