import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';

/// התוויות שמתארות את מצב התוכנה — משותפות לכרטיס שברשת ולדף התוכנה,
/// כדי שהשניים לא יאמרו על אותה תוכנה שני דברים שונים.

StatusKind customAppStatusKind(CustomAppView app) {
  if (!app.canDetect) return StatusKind.unknown;
  if (app.installed == null) return StatusKind.needsAction;
  // מותקנת, ועל הכונן יושבת גרסה חדשה יותר.
  if (app.pending == CustomAppPending.newerOnDrive) {
    return StatusKind.updateAvailable;
  }
  return StatusKind.ok;
}

/// "אינה מותקנת" נאמר **רק** כשבאמת חיפשנו. בלי שם קובץ הרצה התשובה
/// הנכונה היא "לא ניתן לדעת", וזה לא אותו דבר.
String customAppInstalledLabel(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  if (!app.canDetect) return t.noDetectRules;

  final installed = app.installed;
  if (installed == null) return t.notInstalled;
  final version = installed.version;
  return version == null
      ? t.installedUnknownVersion
      : t.installedVersion(version);
}

String customAppStoredLabel(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  final stored = app.storedInstaller;
  return stored == null
      ? t.noStoredInstaller
      : t.storedInstaller(stored.version);
}

/// מה שנמצא ברשת, כשנבדק. `null` כשלא נבדק — לא ממציאים מצב.
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
  return online == app.storedInstaller?.version
      ? t.onlineUpToDate
      : t.onlineVersionAvailable(online);
}
