import 'package:equatable/equatable.dart';

import '../services/plugin_compatibility.dart';
import '../services/plugin_version_compare.dart';
import 'plugin_install_status.dart';
import 'plugin_version_entry.dart';

/// קובץ ה-`.otzplugin` כפי שהוא יושב במראה המקומית.
class PluginLocalFile extends Equatable {
  const PluginLocalFile({
    required this.relativePath,
    required this.fileName,
    required this.ext,
    required this.size,
  });

  /// יחסי לשורש תיקיית התוספים במראה — כך שהעתקת התיקייה לכונן אחר
  /// (או לאות כונן אחרת ב-USB) לא שוברת את הקטלוג.
  final String relativePath;
  final String fileName;
  final String ext;
  final int size;

  Map<String, dynamic> toJson() => {
        'path': relativePath,
        'fileName': fileName,
        'ext': ext,
        'size': size,
      };

  static PluginLocalFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    if (path is! String || path.isEmpty) return null;
    return PluginLocalFile(
      relativePath: path,
      fileName: json['fileName'] is String ? json['fileName'] as String : path,
      ext: json['ext'] is String ? json['ext'] as String : '',
      size: json['size'] is int ? json['size'] as int : 0,
    );
  }

  @override
  List<Object?> get props => [relativePath, fileName, ext, size];
}

/// תוסף בקטלוג המקומי — מיזוג של המטא-דאטה מ-`/api/plugins` עם הנתיבים
/// היחסיים של הקבצים שירדו למראה.
///
/// **הקבצים הם מפה, לא קובץ אחד** ([localFiles]): הכונן נושא עד שתי גרסאות
/// של אוצריא, ולכל אחת עשוי להתאים בילד אחר של אותו תוסף. ראו
/// `plugin_compatibility.dart`.
class StorePlugin extends Equatable {
  /// [versions] נכנס **כפי שהוא**, בהנחה שהוא ממוין מהגבוה לנמוך — ההכרעה
  /// נשענת על הסדר. שני היצרנים שקוראים נתונים מבחוץ ([fromApi], [fromJson])
  /// מסדרים בעצמם; המיון כאן היה מבטל את היות הבנאי `const`.
  const StorePlugin({
    required this.id,
    required this.name,
    required this.shortDescription,
    required this.description,
    required this.version,
    required this.status,
    required this.author,
    required this.updatedAt,
    required this.originalDate,
    required this.compatibleWith,
    required this.maxAppVersion,
    required this.requiresNetwork,
    required this.tags,
    required this.homepage,
    required this.downloadCount,
    required this.supportsDirectInstall,
    required this.isFeatured,
    required this.remoteDownloadUrl,
    this.remoteImageUrl = '',
    this.remoteScreenshotUrls = const [],
    this.imagePath,
    this.screenshotPaths = const [],
    this.categorySlugs = const [],
    this.localFiles = const {},
    this.manifestId,
    this.versions = const [],
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.ratingVerifiedCount = 0,
    this.ratingBreakdown = const [0, 0, 0, 0, 0],
  });

  /// מזהה מסד-הנתונים של האתר. **אינו** המזהה שאוצריא משתמשת בו לתיקיית
  /// ההתקנה — לשם כך יש [manifestId].
  final String id;
  final String name;
  final String shortDescription;
  final String description;

  /// הגרסה **החיה** באתר. אינה בהכרח זו שתותקן: ראו [installTarget].
  final String version;
  final String status;
  final String author;
  final String updatedAt;
  final String originalDate;
  final String compatibleWith;
  final String? maxAppVersion;
  final bool requiresNetwork;
  final List<String> tags;
  final String homepage;
  final int downloadCount;
  final bool supportsDirectInstall;

  /// דירוג המשתמשים כפי שהאתר מחשב אותו. **לקריאה בלבד** — הדירוג נעשה
  /// באתר (דורש חשבון), והמראה רק נושאת את התוצאה אל המחשב הלא-מקוון.
  final double ratingAvg;
  final int ratingCount;

  /// מדרגים שהתקנת התוסף אצלם נרשמה בפועל.
  final int ratingVerifiedCount;

  /// כמה מדרגים נתנו כל ציון — חמישה מספרים, מכוכב אחד ועד חמישה.
  final List<int> ratingBreakdown;

  /// כל הבילדים שהאתר מכיר — החי וההיסטוריים — ממוינים מהגבוה לנמוך.
  /// זה מה שמאפשר להכריע אופליין איזה בילד מתאים לגרסת אוצריא שבמחשב.
  final List<PluginVersionEntry> versions;

  /// "תוסף נבחר" — האצירה הידנית של דף הבית בחנות. באתר השדה עדיין נקרא
  /// `isPinned` (תאימות לאחור), ומשמעותו כיום featured.
  final bool isFeatured;

  /// כתובת מוחלטת להורדת קובץ התוסף — נשמרת בקטלוג כדי שהתקנה ישירה תוכל
  /// להשלים קובץ חסר גם בלי סנכרון מלא מחדש.
  final String remoteDownloadUrl;

  /// הכתובות שמהן ירדו התמונות, כפי שהאתר החזיר אותן. נשמרות כדי שסנכרון
  /// הבא ידע אם התמונה בכלל השתנתה — אחרת כל סנכרון הוריד את כולן מחדש.
  final String remoteImageUrl;
  final List<String> remoteScreenshotUrls;

  final String? imagePath;
  final List<String> screenshotPaths;

  /// ה-slug של כל קטגוריה שהתוסף משובץ בה. אינו מגיע מ-`/api/plugins`
  /// אלא מחושב בסנכרון מתוך רשימות החברות של הקטגוריות.
  final List<String> categorySlugs;

  /// `גרסת הבילד -> הקובץ שלו במראה`. רק בילדים שהקובץ שלהם באמת ירד.
  final Map<String, PluginLocalFile> localFiles;

  /// ה-id האמיתי מתוך `manifest.json` שבקובץ ה-`.otzplugin`. זהו המפתח
  /// היחיד שמותר להשוות מולו את התוספים המותקנים (`installed/<manifestId>/`).
  final String? manifestId;

  /// הבילדים להכרעה. קטלוג ישן (או אתר בלי `versions`) מקבל רשומה אחת
  /// שנבנית מהשדות העליונים — בדיוק `buildLiveVersionEntry` של האתר.
  List<PluginVersionEntry> get versionEntries =>
      versions.isNotEmpty ? versions : [_liveEntry];

  PluginVersionEntry get _liveEntry => PluginVersionEntry(
        version: version,
        status: status,
        compatibleWith: compatibleWith,
        maxAppVersion: maxAppVersion,
        downloadUrl: remoteDownloadUrl,
        requiresNetwork: requiresNetwork,
        supportsDirectInstall: supportsDirectInstall,
        isLatest: true,
      );

  /// הקובץ שירד עבור בילד מסוים, או null אם הבילד הזה אינו במראה.
  PluginLocalFile? localFileFor(String? version) =>
      version == null ? null : localFiles[version];

  /// קובץ כלשהו שירד — לתצוגה בלבד, כשאין גרסת אוצריא להכריע לפיה.
  PluginLocalFile? get anyLocalFile =>
      localFiles[version] ??
      (localFiles.isEmpty ? null : localFiles.values.first);

  /// הבילד הגבוה ביותר שתואם ל-[appVersion], בין אם הקובץ שלו במראה ובין
  /// אם לא. `null` = לתוסף אין מה להציע לגרסה הזו.
  PluginVersionEntry? compatibleFor(String? appVersion) =>
      resolveCompatibleVersion(versionEntries, appVersion);

  /// הבילד שיותקן במחשב שמריץ [appVersion]: הגבוה ביותר שתואם לו **ושהקובץ
  /// שלו יושב במראה**. כשאף בילד תואם לא ירד מוחזר הגבוה שתואם, כדי
  /// שהממשק יאמר "הקובץ לא ירד" ולא "אין תוסף".
  PluginVersionEntry? installTarget(String? appVersion) {
    PluginVersionEntry? compatible;
    for (final entry in versionEntries) {
      if (!isCompatibleWithApp(entry, appVersion)) continue;
      compatible ??= entry;
      if (localFiles.containsKey(entry.version)) return entry;
    }
    return compatible;
  }

  /// הבילדים שצריכים לרדת עבור הגרסאות שהכונן נושא — ראו [resolveTargets].
  List<PluginVersionEntry> targetsFor(List<String> appVersions) =>
      resolveTargets(versionEntries, appVersions);

  /// גרסת אוצריא המינימלית שמריצה בילד כלשהו של התוסף — לשורת היומן
  /// שמסבירה למה תוסף לא ירד. ראו [PluginSyncOutcome.incompatible].
  String? get lowestSupportedApp => lowestSupportedAppVersion(versionEntries);

  /// מצב התוסף מול מפת המותקנים (`manifestId -> גרסה מותקנת`), ביחס
  /// ל-[appVersion] של אוצריא שבמחשב הזה.
  ///
  /// [PluginInstallStatus.incompatible] הוא מצב אמיתי ולא שגיאה: לתוסף אין
  /// אף בילד שירוץ על הגרסה הזו, ולכן אין מה להציע.
  PluginInstallStatus statusAgainst(
    Map<String, String> installed, {
    String? appVersion,
  }) {
    final target = installTarget(appVersion);
    if (target == null) return PluginInstallStatus.incompatible;

    final key = manifestId;
    if (key == null || key.isEmpty) return PluginInstallStatus.unknown;
    final installedVersion = installed[key];
    if (installedVersion == null) return PluginInstallStatus.notInstalled;
    return comparePluginVersions(target.version, installedVersion) > 0
        ? PluginInstallStatus.updateAvailable
        : PluginInstallStatus.upToDate;
  }

  /// האם התוסף תואם לטקסט חיפוש חופשי. אותם שדות שהחיפוש החכם באתר מדרג
  /// (שם, תגיות, תקציר, מפתח, תיאור) — כאן בלי דירוג, כי החיפוש מקומי.
  bool matchesQuery(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        shortDescription.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        author.toLowerCase().contains(q) ||
        tags.any((t) => t.toLowerCase().contains(q));
  }

  StorePlugin copyWith({
    String? imagePath,
    List<String>? screenshotPaths,
    List<String>? categorySlugs,
    Map<String, PluginLocalFile>? localFiles,
    String? manifestId,
    List<PluginVersionEntry>? versions,
  }) {
    return StorePlugin(
      id: id,
      name: name,
      shortDescription: shortDescription,
      description: description,
      version: version,
      status: status,
      author: author,
      updatedAt: updatedAt,
      originalDate: originalDate,
      compatibleWith: compatibleWith,
      maxAppVersion: maxAppVersion,
      requiresNetwork: requiresNetwork,
      tags: tags,
      homepage: homepage,
      downloadCount: downloadCount,
      supportsDirectInstall: supportsDirectInstall,
      isFeatured: isFeatured,
      remoteDownloadUrl: remoteDownloadUrl,
      remoteImageUrl: remoteImageUrl,
      remoteScreenshotUrls: remoteScreenshotUrls,
      imagePath: imagePath ?? this.imagePath,
      screenshotPaths: screenshotPaths ?? this.screenshotPaths,
      categorySlugs: categorySlugs ?? this.categorySlugs,
      localFiles: localFiles ?? this.localFiles,
      manifestId: manifestId ?? this.manifestId,
      versions: versions ?? this.versions,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
      ratingVerifiedCount: ratingVerifiedCount,
      ratingBreakdown: ratingBreakdown,
    );
  }

  /// בונה רשומה מתשובת `/api/plugins`. [baseUrl] נדרש כדי להפוך את
  /// `downloadUrl` היחסי לכתובת מוחלטת שתישמר בקטלוג.
  factory StorePlugin.fromApi(Map<String, dynamic> json, String baseUrl) {
    return StorePlugin(
      id: _string(json['id']),
      name: _string(json['name']),
      shortDescription: _string(json['shortDescription']),
      description: _string(json['description']),
      version: _string(json['version']),
      status: _string(json['status']),
      author: _string(json['author']),
      updatedAt: _string(json['updatedAt']),
      originalDate: _string(json['originalDate']),
      compatibleWith: _string(json['compatibleWith']),
      maxAppVersion: json['maxAppVersion'] is String
          ? json['maxAppVersion'] as String
          : null,
      requiresNetwork: json['requiresNetwork'] == true,
      tags: _stringList(json['tags']),
      homepage: _string(json['homepage']),
      downloadCount:
          json['downloadCount'] is int ? json['downloadCount'] as int : 0,
      supportsDirectInstall: json['supportsDirectInstall'] == true,
      isFeatured: json['isPinned'] == true,
      ratingAvg: _double(json['ratingAvg']),
      ratingCount: _int(json['ratingCount']),
      ratingVerifiedCount: _int(json['ratingVerifiedCount']),
      ratingBreakdown: _breakdown(json['ratingBreakdown']),
      remoteDownloadUrl: _absolute(_string(json['downloadUrl']), baseUrl),
      versions: _sortedDescending(_versions(json['versions'], baseUrl)),
      // כמו שהאתר שלח, בלי להפוך למוחלט: הן נשמרות כדי להשוות מול התשובה
      // הבאה, וההורדה עצמה כבר יודעת להשלים כתובת יחסית.
      remoteImageUrl: _string(json['image']),
      remoteScreenshotUrls: [
        for (final url in _stringList(json['screenshots']))
          if (url.isNotEmpty) url,
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shortDescription': shortDescription,
        'description': description,
        'version': version,
        'status': status,
        'author': author,
        'updatedAt': updatedAt,
        'originalDate': originalDate,
        'compatibleWith': compatibleWith,
        'maxAppVersion': maxAppVersion,
        'requiresNetwork': requiresNetwork,
        'tags': tags,
        'homepage': homepage,
        'downloadCount': downloadCount,
        'supportsDirectInstall': supportsDirectInstall,
        'isFeatured': isFeatured,
        'ratingAvg': ratingAvg,
        'ratingCount': ratingCount,
        'ratingVerifiedCount': ratingVerifiedCount,
        'ratingBreakdown': ratingBreakdown,
        'remoteDownloadUrl': remoteDownloadUrl,
        'remoteImageUrl': remoteImageUrl,
        'remoteScreenshotUrls': remoteScreenshotUrls,
        'image': imagePath,
        'screenshots': screenshotPaths,
        'categories': categorySlugs,
        'versions': [for (final entry in versions) entry.toJson()],
        'localFiles': {
          for (final entry in localFiles.entries)
            entry.key: entry.value.toJson(),
        },
        'manifestId': manifestId,
      };

  /// קורא רשומה מהקטלוג השמור. שדה חסר או פגום נופל לברירת המחדל שלו,
  /// כדי שקטלוג שנפגם חלקית לא יאבד את כל התוספים.
  factory StorePlugin.fromJson(Map<String, dynamic> json) {
    final version = _string(json['version']);
    return StorePlugin(
      id: _string(json['id']),
      name: _string(json['name']),
      shortDescription: _string(json['shortDescription']),
      description: _string(json['description']),
      version: version,
      status: _string(json['status']),
      author: _string(json['author']),
      updatedAt: _string(json['updatedAt']),
      originalDate: _string(json['originalDate']),
      compatibleWith: _string(json['compatibleWith']),
      maxAppVersion: json['maxAppVersion'] is String
          ? json['maxAppVersion'] as String
          : null,
      requiresNetwork: json['requiresNetwork'] == true,
      tags: _stringList(json['tags']),
      homepage: _string(json['homepage']),
      downloadCount:
          json['downloadCount'] is int ? json['downloadCount'] as int : 0,
      supportsDirectInstall: json['supportsDirectInstall'] == true,
      // `isPinned` — קטלוג שנכתב לפני שהאתר שינה את המשמעות ל"נבחר".
      isFeatured: json['isFeatured'] == true || json['isPinned'] == true,
      ratingAvg: _double(json['ratingAvg']),
      ratingCount: _int(json['ratingCount']),
      ratingVerifiedCount: _int(json['ratingVerifiedCount']),
      ratingBreakdown: _breakdown(json['ratingBreakdown']),
      remoteDownloadUrl: _string(json['remoteDownloadUrl']),
      remoteImageUrl: _string(json['remoteImageUrl']),
      remoteScreenshotUrls: _stringList(json['remoteScreenshotUrls']),
      imagePath: json['image'] is String ? json['image'] as String : null,
      screenshotPaths: _stringList(json['screenshots']),
      categorySlugs: _stringList(json['categories']),
      versions: _sortedDescending(_versions(json['versions'], '')),
      localFiles: _localFiles(json, version),
      manifestId: json['manifestId'] is String &&
              (json['manifestId'] as String).isNotEmpty
          ? json['manifestId'] as String
          : null,
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  /// `ratingAvg` חוזר מהאתר כשלם כשאין לו שבר (`5` ולא `5.0`).
  static double _double(Object? value) => value is num ? value.toDouble() : 0;

  static int _int(Object? value) => value is int ? value : 0;

  /// תמיד חמישה מספרים — פילוח קטוע היה מפיל את שורות הפירוט בעמוד התוסף.
  static List<int> _breakdown(Object? value) {
    if (value is! List) return const [0, 0, 0, 0, 0];
    return [
      for (var i = 0; i < 5; i++)
        i < value.length && value[i] is int ? value[i] as int : 0,
    ];
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  static List<PluginVersionEntry> _versions(Object? value, String baseUrl) {
    if (value is! List) return const [];
    return [
      for (final raw in value)
        if (PluginVersionEntry.fromApi(raw, baseUrl) case final entry?) entry,
    ];
  }

  /// קורא את מפת הקבצים, **וגם** קטלוג ישן שכתב `localFile` יחיד: הקובץ
  /// ההוא שייך לגרסה שנרשמה לצדו, וכך הוא ממשיך להיחשב במראה בלי הורדה
  /// מחדש. בלי ההגירה הזו הסנכרון הראשון שאחרי העדכון היה מוריד את כל
  /// החנות שוב.
  static Map<String, PluginLocalFile> _localFiles(
    Map<String, dynamic> json,
    String version,
  ) {
    final raw = json['localFiles'];
    if (raw is Map) {
      final files = <String, PluginLocalFile>{};
      for (final entry in raw.entries) {
        final key = entry.key;
        final file = PluginLocalFile.fromJson(entry.value);
        if (key is String && key.isNotEmpty && file != null) files[key] = file;
      }
      if (files.isNotEmpty) return files;
    }

    final legacy = PluginLocalFile.fromJson(json['localFile']);
    if (legacy == null || version.isEmpty) return const {};
    return {version: legacy};
  }

  /// מיון יורד יציב: האתר כבר מחזיר ממוין, אבל ההכרעה נשענת על הסדר ולכן
  /// אינה סומכת עליו. שוויון שומר על סדר המקור (ה-`sort` של Dart אינו יציב).
  static List<PluginVersionEntry> _sortedDescending(
    List<PluginVersionEntry> entries,
  ) {
    final indexed = [
      for (var i = 0; i < entries.length; i++) (i, entries[i]),
    ]..sort((a, b) {
        final byVersion = comparePluginVersions(b.$2.version, a.$2.version);
        return byVersion != 0 ? byVersion : a.$1 - b.$1;
      });
    return [for (final pair in indexed) pair.$2];
  }

  static String _absolute(String url, String baseUrl) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$baseUrl$url';
  }

  @override
  List<Object?> get props =>
      [id, version, manifestId, localFiles, imagePath, categorySlugs, versions];
}
