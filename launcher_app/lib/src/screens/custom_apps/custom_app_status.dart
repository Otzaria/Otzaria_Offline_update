import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../widgets/widgets_exports.dart';

/// התוויות שמתארות את מצב התוכנה — משותפות לכרטיס ולדף, כדי שהשניים לא
/// יאמרו על אותה תוכנה שני דברים שונים.

/// הערך שליד "מותקנת במחשב הזה": הגרסה, או "לא". "לא" נאמר **רק** כשבאמת
/// חיפשנו — בלי שם קובץ הרצה התשובה היא "לא ידוע", וזה לא אותו דבר.
({String text, bool ltr}) customAppInstalledValue(
  BuildContext context,
  CustomAppView app,
) {
  final t = context.strings.customApps;
  if (!app.canDetect) return (text: t.valueUnknown, ltr: false);
  final installed = app.installed;
  if (installed == null) return (text: t.valueNo, ltr: false);
  final version = installed.version;
  return version == null
      ? (text: t.installedNoVersionValue, ltr: false)
      : (text: version, ltr: true);
}

/// הערך שליד "בכונן": הגרסה, או "עוד לא ירד".
({String text, bool ltr}) customAppStoredValue(
  BuildContext context,
  CustomAppView app,
) {
  final stored = app.storedInstaller;
  return stored == null
      ? (text: context.strings.customApps.notStoredValue, ltr: false)
      : (text: stored.version, ltr: true);
}

/// מאיפה התוכנה: "מאתר המפתחים (GitHub)" או "מקובץ".
String customAppSourceLabel(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  return app.descriptor.sourceKind == AppSourceKind.github
      ? t.sourceGithubShort
      : t.sourceFileShort;
}

/// הגרסה שבכונן, ובלעדיה — המותקנת כאן.
String? customAppVersionOf(CustomAppView app) =>
    app.storedInstaller?.version ?? app.installed?.version;

/// שורת המטא: גרסה, גודל ומקור.
List<String> customAppMeta(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  final version = customAppVersionOf(app);
  final size = app.storedInstaller?.sizeBytes ?? 0;
  return [
    if (version != null && version.isNotEmpty) t.versionLabel(version),
    if (size > 0) formatBytes(size),
    customAppSourceLabel(context, app),
  ];
}

/// ההערה מתחת לפעולה — רק כשאין מה להתקין. "התקנה" כבר אומרת שאינה מותקנת.
String? customAppNoteOf(BuildContext context, CustomAppView app) =>
    !app.canInstall && !app.canLaunch
        ? context.strings.customApps.noStoredInstaller
        : null;

String? customAppOnlineLabel(
  BuildContext context,
  CustomAppsController controller,
  CustomAppView app,
) {
  if (app.descriptor.sourceKind != AppSourceKind.github) return null;
  final t = context.strings.customApps;
  final id = app.descriptor.id;

  if (controller.onlineUnavailable.contains(id)) return t.onlineUnavailable;
  final online = controller.onlineVersions[id];
  if (online == null) return null;
  return customAppOnlineIsNewer(online, app.storedInstaller?.version)
      ? t.onlineVersionAvailable(online)
      : t.onlineUpToDate;
}
