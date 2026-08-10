import 'package:equatable/equatable.dart';

import '../services/plugin_version_compare.dart';
import 'plugin_install_status.dart';

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
class StorePlugin extends Equatable {
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
    this.imagePath,
    this.screenshotPaths = const [],
    this.categorySlugs = const [],
    this.localFile,
    this.manifestId,
  });

  /// מזהה מסד-הנתונים של האתר. **אינו** המזהה שאוצריא משתמשת בו לתיקיית
  /// ההתקנה — לשם כך יש [manifestId].
  final String id;
  final String name;
  final String shortDescription;
  final String description;
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

  /// "תוסף נבחר" — האצירה הידנית של דף הבית בחנות. באתר השדה עדיין נקרא
  /// `isPinned` (תאימות לאחור), ומשמעותו כיום featured.
  final bool isFeatured;

  /// כתובת מוחלטת להורדת קובץ התוסף — נשמרת בקטלוג כדי שהתקנה ישירה תוכל
  /// להשלים קובץ חסר גם בלי סנכרון מלא מחדש.
  final String remoteDownloadUrl;

  final String? imagePath;
  final List<String> screenshotPaths;

  /// ה-slug של כל קטגוריה שהתוסף משובץ בה. אינו מגיע מ-`/api/plugins`
  /// אלא מחושב בסנכרון מתוך רשימות החברות של הקטגוריות.
  final List<String> categorySlugs;

  final PluginLocalFile? localFile;

  /// ה-id האמיתי מתוך `manifest.json` שבקובץ ה-`.otzplugin`. זהו המפתח
  /// היחיד שמותר להשוות מולו את התוספים המותקנים (`installed/<manifestId>/`).
  final String? manifestId;

  /// מצב התוסף מול מפת המותקנים (`manifestId -> גרסה מותקנת`).
  PluginInstallStatus statusAgainst(Map<String, String> installed) {
    final key = manifestId;
    if (key == null || key.isEmpty) return PluginInstallStatus.unknown;
    final installedVersion = installed[key];
    if (installedVersion == null) return PluginInstallStatus.notInstalled;
    return comparePluginVersions(version, installedVersion) > 0
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
    PluginLocalFile? localFile,
    String? manifestId,
    // הגרסה נדרסת רק כשהורדת הקובץ נכשלה: הקטלוג מתאר את מה שבמראה בפועל,
    // ראו `PluginMirrorSync._syncPluginFile`.
    String? version,
  }) {
    return StorePlugin(
      id: id,
      name: name,
      shortDescription: shortDescription,
      description: description,
      version: version ?? this.version,
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
      imagePath: imagePath ?? this.imagePath,
      screenshotPaths: screenshotPaths ?? this.screenshotPaths,
      categorySlugs: categorySlugs ?? this.categorySlugs,
      localFile: localFile ?? this.localFile,
      manifestId: manifestId ?? this.manifestId,
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
      remoteDownloadUrl: _absolute(_string(json['downloadUrl']), baseUrl),
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
        'remoteDownloadUrl': remoteDownloadUrl,
        'image': imagePath,
        'screenshots': screenshotPaths,
        'categories': categorySlugs,
        'localFile': localFile?.toJson(),
        'manifestId': manifestId,
      };

  /// קורא רשומה מהקטלוג השמור. שדה חסר או פגום נופל לברירת המחדל שלו,
  /// כדי שקטלוג שנפגם חלקית לא יאבד את כל התוספים.
  factory StorePlugin.fromJson(Map<String, dynamic> json) {
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
      // `isPinned` — קטלוג שנכתב לפני שהאתר שינה את המשמעות ל"נבחר".
      isFeatured: json['isFeatured'] == true || json['isPinned'] == true,
      remoteDownloadUrl: _string(json['remoteDownloadUrl']),
      imagePath: json['image'] is String ? json['image'] as String : null,
      screenshotPaths: _stringList(json['screenshots']),
      categorySlugs: _stringList(json['categories']),
      localFile: PluginLocalFile.fromJson(json['localFile']),
      manifestId: json['manifestId'] is String &&
              (json['manifestId'] as String).isNotEmpty
          ? json['manifestId'] as String
          : null,
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const <String>[];

  static String _absolute(String url, String baseUrl) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$baseUrl$url';
  }

  @override
  List<Object?> get props =>
      [id, version, manifestId, localFile, imagePath, categorySlugs];
}
