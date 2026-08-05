/// ערוץ הגרסאות שממנו נבחרות גרסאות לרכיב. preview דורש בחירה מפורשת
/// (תכנון §2.2) ולכן אינו ברירת המחדל של שום רכיב.
enum UpdateChannel { stable, stableAndPreview }

enum AppThemeMode { system, light, dark }

/// כל ההגדרות של הלאנצ'ר, immutable ובעלות [schemaVersion] — נשמרות
/// לקובץ JSON יחיד (ראו `SettingsStore`), כמפורט בתכנון §10.1.
///
/// **כל אפשרויות האוטומציה כבויות בברירת מחדל** פרט לבדיקת המטא־דאטה,
/// שהיא בדיקה קלה ללא הורדה (תכנון §8.1).
class AppSettings {
  static const int schemaVersion = 1;

  // ── אוטומציה ────────────────────────────────────────────────────────────
  final bool autoMetadataCheck;
  final bool autoDownloadApp;
  final bool autoInstallApp;
  final bool autoDownloadLibrary;
  final bool autoInstallLibrary;
  final bool autoDownloadInstalledPlugins;
  final bool autoInstallInstalledPlugins;
  final bool autoDownloadAllPlugins;
  final bool autoPrepareUsbBundle;

  // ── ערוצים ──────────────────────────────────────────────────────────────
  final UpdateChannel appChannel;
  final UpdateChannel libraryChannel;
  final UpdateChannel pluginsChannel;

  // ── נתיבים ואחסון ───────────────────────────────────────────────────────
  final String? otzariaInstallPath;
  final String? libraryPath;
  final String? pluginsPath;
  final String? preferredUsbPath;
  final int backupsToKeep;

  // ── רשת ─────────────────────────────────────────────────────────────────
  final bool offlineOnly;
  final int networkTimeoutSeconds;

  // ── ממשק ────────────────────────────────────────────────────────────────
  final AppThemeMode themeMode;
  final double textScale;

  const AppSettings({
    this.autoMetadataCheck = true,
    this.autoDownloadApp = false,
    this.autoInstallApp = false,
    this.autoDownloadLibrary = false,
    this.autoInstallLibrary = false,
    this.autoDownloadInstalledPlugins = false,
    this.autoInstallInstalledPlugins = false,
    this.autoDownloadAllPlugins = false,
    this.autoPrepareUsbBundle = false,
    this.appChannel = UpdateChannel.stable,
    this.libraryChannel = UpdateChannel.stable,
    this.pluginsChannel = UpdateChannel.stable,
    this.otzariaInstallPath,
    this.libraryPath,
    this.pluginsPath,
    this.preferredUsbPath,
    this.backupsToKeep = 1,
    this.offlineOnly = false,
    this.networkTimeoutSeconds = 20,
    this.themeMode = AppThemeMode.system,
    this.textScale = 1.0,
  });

  AppSettings copyWith({
    bool? autoMetadataCheck,
    bool? autoDownloadApp,
    bool? autoInstallApp,
    bool? autoDownloadLibrary,
    bool? autoInstallLibrary,
    bool? autoDownloadInstalledPlugins,
    bool? autoInstallInstalledPlugins,
    bool? autoDownloadAllPlugins,
    bool? autoPrepareUsbBundle,
    UpdateChannel? appChannel,
    UpdateChannel? libraryChannel,
    UpdateChannel? pluginsChannel,
    String? otzariaInstallPath,
    String? libraryPath,
    String? pluginsPath,
    String? preferredUsbPath,
    int? backupsToKeep,
    bool? offlineOnly,
    int? networkTimeoutSeconds,
    AppThemeMode? themeMode,
    double? textScale,
  }) {
    return AppSettings(
      autoMetadataCheck: autoMetadataCheck ?? this.autoMetadataCheck,
      autoDownloadApp: autoDownloadApp ?? this.autoDownloadApp,
      autoInstallApp: autoInstallApp ?? this.autoInstallApp,
      autoDownloadLibrary: autoDownloadLibrary ?? this.autoDownloadLibrary,
      autoInstallLibrary: autoInstallLibrary ?? this.autoInstallLibrary,
      autoDownloadInstalledPlugins:
          autoDownloadInstalledPlugins ?? this.autoDownloadInstalledPlugins,
      autoInstallInstalledPlugins:
          autoInstallInstalledPlugins ?? this.autoInstallInstalledPlugins,
      autoDownloadAllPlugins:
          autoDownloadAllPlugins ?? this.autoDownloadAllPlugins,
      autoPrepareUsbBundle: autoPrepareUsbBundle ?? this.autoPrepareUsbBundle,
      appChannel: appChannel ?? this.appChannel,
      libraryChannel: libraryChannel ?? this.libraryChannel,
      pluginsChannel: pluginsChannel ?? this.pluginsChannel,
      otzariaInstallPath: otzariaInstallPath ?? this.otzariaInstallPath,
      libraryPath: libraryPath ?? this.libraryPath,
      pluginsPath: pluginsPath ?? this.pluginsPath,
      preferredUsbPath: preferredUsbPath ?? this.preferredUsbPath,
      backupsToKeep: backupsToKeep ?? this.backupsToKeep,
      offlineOnly: offlineOnly ?? this.offlineOnly,
      networkTimeoutSeconds:
          networkTimeoutSeconds ?? this.networkTimeoutSeconds,
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'automation': {
          'metadataCheck': autoMetadataCheck,
          'downloadApp': autoDownloadApp,
          'installApp': autoInstallApp,
          'downloadLibrary': autoDownloadLibrary,
          'installLibrary': autoInstallLibrary,
          'downloadInstalledPlugins': autoDownloadInstalledPlugins,
          'installInstalledPlugins': autoInstallInstalledPlugins,
          'downloadAllPlugins': autoDownloadAllPlugins,
          'prepareUsbBundle': autoPrepareUsbBundle,
        },
        'channels': {
          'app': appChannel.name,
          'library': libraryChannel.name,
          'plugins': pluginsChannel.name,
        },
        'paths': {
          'otzariaInstall': otzariaInstallPath,
          'library': libraryPath,
          'plugins': pluginsPath,
          'preferredUsb': preferredUsbPath,
          'backupsToKeep': backupsToKeep,
        },
        'network': {
          'offlineOnly': offlineOnly,
          'timeoutSeconds': networkTimeoutSeconds,
        },
        'ui': {
          'themeMode': themeMode.name,
          'textScale': textScale,
        },
      };

  /// קורא הגדרות מ-JSON. שדה חסר או פגום נופל לברירת המחדל שלו — קובץ
  /// מקולקל חלקית לא מאבד את כל ההגדרות.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? value : const {};
    }

    final automation = section('automation');
    final channels = section('channels');
    final paths = section('paths');
    final network = section('network');
    final ui = section('ui');
    const defaults = AppSettings();

    bool flag(Map<String, dynamic> from, String key, bool fallback) {
      final value = from[key];
      return value is bool ? value : fallback;
    }

    UpdateChannel channel(String key) {
      final name = channels[key];
      return UpdateChannel.values.firstWhere(
        (c) => c.name == name,
        orElse: () => UpdateChannel.stable,
      );
    }

    String? path(String key) {
      final value = paths[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return AppSettings(
      autoMetadataCheck: flag(
        automation,
        'metadataCheck',
        defaults.autoMetadataCheck,
      ),
      autoDownloadApp: flag(automation, 'downloadApp', false),
      autoInstallApp: flag(automation, 'installApp', false),
      autoDownloadLibrary: flag(automation, 'downloadLibrary', false),
      autoInstallLibrary: flag(automation, 'installLibrary', false),
      autoDownloadInstalledPlugins:
          flag(automation, 'downloadInstalledPlugins', false),
      autoInstallInstalledPlugins:
          flag(automation, 'installInstalledPlugins', false),
      autoDownloadAllPlugins: flag(automation, 'downloadAllPlugins', false),
      autoPrepareUsbBundle: flag(automation, 'prepareUsbBundle', false),
      appChannel: channel('app'),
      libraryChannel: channel('library'),
      pluginsChannel: channel('plugins'),
      otzariaInstallPath: path('otzariaInstall'),
      libraryPath: path('library'),
      pluginsPath: path('plugins'),
      preferredUsbPath: path('preferredUsb'),
      backupsToKeep: paths['backupsToKeep'] is int
          ? paths['backupsToKeep'] as int
          : defaults.backupsToKeep,
      offlineOnly: flag(network, 'offlineOnly', false),
      networkTimeoutSeconds: network['timeoutSeconds'] is int
          ? network['timeoutSeconds'] as int
          : defaults.networkTimeoutSeconds,
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == ui['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      textScale:
          ui['textScale'] is num ? (ui['textScale'] as num).toDouble() : 1.0,
    );
  }
}
