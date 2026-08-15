import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// שם סוג ההתקנה כפי שהוא נאמר למשתמש.
///
/// שלושת הראשונים הם שמות מוצר וזהים בשתי השפות; השניים האחרונים מתארים
/// **מה יקרה** ולא מי בנה את הקובץ, כי זה מה שמעניין את מי שעומד לחיצה
/// לפני ההתקנה.
String installerKindLabelOf(CustomInstallerKind kind, CustomAppsStrings t) =>
    switch (kind) {
      CustomInstallerKind.innoSetup => t.kindInno,
      CustomInstallerKind.nsis => t.kindNsis,
      CustomInstallerKind.msi => t.kindMsi,
      CustomInstallerKind.zipPortable => t.kindZip,
      CustomInstallerKind.portableFile => t.kindPortableFile,
      CustomInstallerKind.interactive => t.kindInteractive,
    };
