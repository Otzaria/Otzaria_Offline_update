// הכוונת דף הבית: פונקציה טהורה מעובדות למשפט אחד ולפעולה אחת. בלי
// Flutter ובלי קונטרולרים, כדי שכל מצב ייבדק בטבלה.

/// מקביל ל-`OtzariaModuleStatus` בשם ובסדר — ראו
/// `guidanceFactsFromSession`.
enum AppStatusFact {
  idle,
  checking,
  upToDate,
  updateAvailable,
  installing,
  error,
  needsDownload,
  installedIsNewer,
}

/// מקביל ל-`LibraryModuleStatus` בשם ובסדר.
enum LibraryStatusFact {
  idle,
  checking,
  upToDate,
  updateAvailable,
  updating,
  error,
  needsManualPath,
  needsDownload,
  personalTargetElsewhere,
}

/// רכיב שנכלל בפעולה — בסדר הביצוע שלה.
enum GuidanceItem { app, library, plugins }

enum GuidancePrimary {
  checking,
  welcome,
  installHere,
  updateHere,
  downloadToDrive,
  upToDate,
  newerHereThanDrive,

  /// המחשב מחובר, אבל הבדיקה של רכיב שנבחר נכשלה — "לא הצלחתי לבדוק".
  checkFailed,
  attention,
  taskInProgress,
}

/// מה הבדיקה ברשת אומרת על רכיב אחד.
enum OnlineProof {
  /// הצליחה, בתוך `onlineCheckMaxAge`.
  proven,

  /// הצליחה, אבל ישנה. עדיין התשובה שמוצגת — אין רענון בלי לחיצה.
  stale,
  failed,
  unchecked;

  bool get succeeded => this == proven || this == stale;
}

/// עדכון שאינו של אוצריא, הספרייה או התוספים — ואסור ל"הכול מעודכן" להסתיר.
enum OtherUpdate { launcher, customApps }

/// "הורדה" שלא מצאה מה להביא — מה הבית אומר במקום מסך משימה.
enum FoundNothing {
  /// בדיקה ברשת רצה ממש לפני ההחלטה.
  rechecked,

  /// הבדיקות היו טריות, וההחלטה נשענה עליהן.
  earlierCheck,
}

enum GuidanceSecondary {
  none,
  updateHereToo,

  /// "בדוק עכשיו": משהו עוד לא נבדק — ברשת, או מקומית כשהבדיקה
  /// האוטומטית כבויה.
  checkOnlineNow,
  offlineHint,
  noSyncSelection,

  /// באתר יש חדש רק ברכיבים שההורדה שלהם כבויה, ורכיב אחר כן מסומן.
  syncOff,

  /// רק התוספים לא נבדקו, כי אתר אוצריא סגור בשבת — לא "בדוק עכשיו".
  siteClosedForShabbat,
}

/// מה האריח אומר על הרכיב שלו.
enum TileStatus {
  unknown,
  checking,
  working,
  upToDate,
  newerHere,
  installHere,
  updateHere,
  needsConsent,
  nothingOnDrive,
  attention,

  /// הכונן הוכן ב"רק המחשב שלי" למחשב אחר — מצב תקין, לא תקלה.
  preparedElsewhere,

  /// באתר יש חדש שההורדה לכונן תביא — כמו "מה ייכלל" בגיבור.
  onlineAvailable,

  /// מה שבכונן מותקן, אבל הבדיקה ברשת של הרכיב נכשלה (`checkFailed`).
  notCheckedOnline,
}

class GuidanceFacts {
  const GuidanceFacts({
    this.readOnly = false,
    this.driveFull = false,
    this.otzariaStatus = AppStatusFact.upToDate,
    this.otzariaInstalled = true,
    this.otzariaMirrorVersion,
    this.otzariaRunning = false,
    this.libraryApplyActive = false,
    this.libraryStatus = LibraryStatusFact.upToDate,
    this.libraryFreshInstall = false,
    this.semanticConsentRequired = false,
    this.pluginsLoading = false,
    this.pluginUpdatesOnDrive = 0,
    this.online,
    this.appProof,
    this.libraryProof,
    this.pluginsProof,
    this.onlineApp = false,
    this.onlineLibrary = false,
    this.onlinePlugins = false,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.autoCheckUpdates = false,
    this.isCheckingOnline = false,
    this.longTaskRunning = false,
    this.hereDuringDownload,
    this.installing = false,
    this.launcherUpdate = false,
    this.customAppsPending = false,
    this.pluginsClosedForShabbat = false,
  });

  final bool readOnly;
  final bool driveFull;
  final AppStatusFact otzariaStatus;
  final bool otzariaInstalled;
  final String? otzariaMirrorVersion;
  final bool otzariaRunning;
  final bool libraryApplyActive;
  final LibraryStatusFact libraryStatus;
  final bool libraryFreshInstall;

  /// חיפוש חכם בכונן מחכה להסכמה, והחלון עליו עוד לא נענה (לא הסכמה חסרה
  /// סתם — אחרי תשובה הבית שקט).
  final bool semanticConsentRequired;
  final bool pluginsLoading;

  /// תוספים מותקנים שבכונן יש להם גרסה חדשה יותר.
  final int pluginUpdatesOnDrive;

  /// החיבור, לשורת המצב: `null` = לא נבדק; `true` = לפחות בדיקה אחת הצליחה
  /// (גם של הכלי עצמו); `false` = כולן נכשלו.
  final bool? online;

  /// מה הבדיקה ברשת הוכיחה על כל רכיב. `null` — לפי [online] (לטבלאות).
  final OnlineProof? appProof;
  final OnlineProof? libraryProof;
  final OnlineProof? pluginsProof;

  /// יש ברשת משהו שעוד אינו בכונן (`hasOnlineUpdate` של כל מודול).
  final bool onlineApp;
  final bool onlineLibrary;
  final bool onlinePlugins;

  /// מה מסומן להורדה בהגדרות (`downloadsLibrary` לספרייה).
  final bool syncApp;
  final bool syncLibrary;
  final bool syncPlugins;
  final bool autoCheckUpdates;
  final bool isCheckingOnline;

  /// הורדה, סנכרון, ייצוא, תוכנה מותאמת — `AppSession.longTaskRunning`.
  final bool longTaskRunning;

  /// ההורדה לכונן היא המשימה היחידה, והיא ברקע: מה מותר להתקין כאן בינתיים —
  /// שלבים שהמראה שלהם כבר אינה נכתבת. `null` — אין כזו.
  final Set<GuidanceItem>? hereDuringDownload;
  final bool installing;

  /// שורת הכלי בתחתית מציעה עדכון (`HomeViewModel.launcher`).
  final bool launcherUpdate;

  /// בכונן תוכנות נוספות שממתינות להתקנה או לעדכון כאן.
  final bool customAppsPending;

  /// בדיקת התוספים לא רצה כי האתר סגור בשבת ([pluginsProof] — לא נבדק).
  final bool pluginsClosedForShabbat;

  bool get hasSyncSelection => syncApp || syncLibrary || syncPlugins;

  OnlineProof proofOf(GuidanceItem item) =>
      switch (item) {
        GuidanceItem.app => appProof,
        GuidanceItem.library => libraryProof,
        GuidanceItem.plugins => pluginsProof,
      } ??
      switch (online) {
        true => OnlineProof.proven,
        false => OnlineProof.failed,
        null => OnlineProof.unchecked,
      };
}

class HomeGuidance {
  const HomeGuidance({
    required this.primary,
    this.secondary = GuidanceSecondary.none,
    this.hereItems = const [],
    this.downloadItems = const [],
    this.attentionItem,
    this.uncheckedItems = const [],
    this.checkedItems = const [],
    this.onlineProven = false,
    this.otherUpdates = const [],
    this.showOtzariaOpenBanner = false,
    this.otzariaOpenBlocksUpdate = false,
    this.readOnly = false,
    this.driveFull = false,
  });

  final GuidancePrimary primary;
  final GuidanceSecondary secondary;

  /// מה יותקן במחשב הזה, בסדר ההתקנה.
  final List<GuidanceItem> hereItems;

  /// מה יורד לכונן, בסדר ההורדה.
  final List<GuidanceItem> downloadItems;

  /// הרכיב שהדף שלו מסביר מה לא בסדר, כש-[primary] הוא `attention`.
  final GuidanceItem? attentionItem;

  /// ב-`checkFailed`: הרכיבים שהבדיקה שלהם נכשלה, ואלה שנבדקו בלי חדש.
  final List<GuidanceItem> uncheckedItems;
  final List<GuidanceItem> checkedItems;

  /// כל רכיב שנבחר נבדק ברשת בהצלחה — רק אז "הכול מעודכן". אחרת (מחשב לא
  /// מחובר, כונן מוגן, טרם נבדק) נאמר רק מה שידוע: מה שבכונן מותקן.
  final bool onlineProven;

  /// ב-`upToDate`: מה שעוד מחכה, כדי שהגיבור לא יאמר "הכול מעודכן" לצד
  /// "עדכון זמין" בשורת המצב.
  final List<OtherUpdate> otherUpdates;

  /// אוצריא פתוחה — נאמר בבית גם כשאין מה להתקין.
  final bool showOtzariaOpenBanner;

  /// "עדכון כאן" יבקש לסגור אותה, ולכן בפס אין כפתור סגירה שמתחרה בו.
  final bool otzariaOpenBlocksUpdate;
  final bool readOnly;
  final bool driveFull;

  @override
  String toString() => 'HomeGuidance($primary, $secondary, here: $hereItems, '
      'download: $downloadItems, attention: $attentionItem, '
      'unchecked: $uncheckedItems, proven: $onlineProven, '
      'others: $otherUpdates, banner: $showOtzariaOpenBanner, '
      'blocks: $otzariaOpenBlocksUpdate)';
}

/// סדר שלבי "עדכון כאן": התקנה ראשונה — תוכנה ואז ספרייה, בלי תוספים;
/// עדכון — ספרייה, תוכנה, ותוספים אחרונים.
List<GuidanceItem> updateHereStages({
  required bool firstInstall,
  required bool app,
  required bool library,
  required bool plugins,
}) =>
    firstInstall
        ? [if (app) GuidanceItem.app, if (library) GuidanceItem.library]
        : [
            if (library) GuidanceItem.library,
            if (app) GuidanceItem.app,
            if (plugins) GuidanceItem.plugins,
          ];

List<GuidanceItem> _hereItems(GuidanceFacts f) => updateHereStages(
      firstInstall: !f.otzariaInstalled,
      app: f.otzariaStatus == AppStatusFact.updateAvailable,
      library: f.libraryStatus == LibraryStatusFact.updateAvailable ||
          semanticOnlyHere(f),
      plugins: f.pluginUpdatesOnDrive > 0,
    );

/// הספרייה מעודכנת, ורק החיפוש החכם מחכה לתשובה: "עדכון המחשב הזה" הוא
/// שמציג את החלון, ובלעדיו ההסכמה הייתה רק הודעה שלא שמים לב אליה.
bool semanticOnlyHere(GuidanceFacts f) =>
    f.otzariaInstalled &&
    f.semanticConsentRequired &&
    f.libraryStatus == LibraryStatusFact.upToDate &&
    !f.libraryApplyActive;

/// מה יש ברשת שעוד אינו בכונן, בלי להתחשב בבחירה בהגדרות.
List<GuidanceItem> _onlineItems(GuidanceFacts f) => [
      if (f.onlineApp) GuidanceItem.app,
      if (f.onlineLibrary) GuidanceItem.library,
      if (f.onlinePlugins) GuidanceItem.plugins,
    ];

bool _selected(GuidanceFacts f, GuidanceItem item) => switch (item) {
      GuidanceItem.app => f.syncApp,
      GuidanceItem.library => f.syncLibrary,
      GuidanceItem.plugins => f.syncPlugins,
    };

GuidanceItem? _attentionItem(GuidanceFacts f) {
  if (f.otzariaStatus == AppStatusFact.error) return GuidanceItem.app;
  return switch (f.libraryStatus) {
    LibraryStatusFact.error ||
    LibraryStatusFact.needsManualPath ||
    LibraryStatusFact.personalTargetElsewhere =>
      GuidanceItem.library,
    _ => null,
  };
}

HomeGuidance deriveHomeGuidance(GuidanceFacts f) {
  final selected = [
    for (final item in GuidanceItem.values)
      if (_selected(f, item)) item,
  ];
  final unchecked = [
    for (final item in selected)
      if (f.proofOf(item) == OnlineProof.failed) item,
  ];
  // בלי שום רכיב נבחר אין מה שהוכח — לא טוענים "מעודכנים" על אף אחד.
  final onlineProven = !f.readOnly &&
      f.online == true &&
      selected.isNotEmpty &&
      selected.every((item) => f.proofOf(item).succeeded);
  final notChecked = [
    for (final item in selected)
      if (f.proofOf(item) == OnlineProof.unchecked) item,
  ];
  final closedForShabbat = f.pluginsClosedForShabbat &&
      notChecked.length == 1 &&
      notChecked.single == GuidanceItem.plugins;

  HomeGuidance result(
    GuidancePrimary primary, {
    GuidanceSecondary secondary = GuidanceSecondary.none,
    List<GuidanceItem> here = const [],
    List<GuidanceItem> download = const [],
    GuidanceItem? attention,
    List<OtherUpdate> others = const [],
  }) {
    final failed = primary == GuidancePrimary.checkFailed;
    final open = f.otzariaRunning &&
        f.otzariaInstalled &&
        primary != GuidancePrimary.taskInProgress;
    return HomeGuidance(
      primary: primary,
      secondary: secondary,
      hereItems: here,
      downloadItems: download,
      attentionItem: attention,
      uncheckedItems: failed ? unchecked : const [],
      checkedItems: failed
          ? [
              for (final item in selected)
                if (f.proofOf(item).succeeded) item,
            ]
          : const [],
      onlineProven: onlineProven,
      otherUpdates: others,
      showOtzariaOpenBanner: open,
      otzariaOpenBlocksUpdate:
          open && here.any((i) => i != GuidanceItem.plugins),
      readOnly: f.readOnly,
      driveFull: f.driveFull,
    );
  }

  if (f.longTaskRunning || f.installing || f.libraryApplyActive) {
    final allowed = f.hereDuringDownload ?? const {};
    final hereNow = [
      for (final item in _hereItems(f))
        if (allowed.contains(item)) item,
    ];
    // בהתקנה ראשונה הספרייה תלויה בתוכנה שלפניה.
    final installable =
        f.otzariaInstalled || hereNow.contains(GuidanceItem.app);
    return result(
      GuidancePrimary.taskInProgress,
      here: installable ? hereNow : const [],
    );
  }

  final here = _hereItems(f);
  final onlineItems = _onlineItems(f);
  final canDownload = !f.readOnly && f.online == true;
  final download = canDownload
      ? [
          for (final item in onlineItems)
            if (_selected(f, item)) item,
        ]
      : const <GuidanceItem>[];

  // idle = לא נבדק (הבדיקה האוטומטית כבויה) — לא "בודק", אחרת הגיבור נתקע.
  final localChecking = f.otzariaStatus == AppStatusFact.checking ||
      f.libraryStatus == LibraryStatusFact.checking ||
      f.pluginsLoading;
  final localUnchecked = f.otzariaStatus == AppStatusFact.idle ||
      f.libraryStatus == LibraryStatusFact.idle;
  // גם כשבדיקת הכלי כבר חזרה ושל רכיב שנבחר עוד לא: אחרת "מעודכן" לרגע.
  final onlinePending = !f.readOnly &&
      ((f.online == null && (f.isCheckingOnline || f.autoCheckUpdates)) ||
          (f.isCheckingOnline && notChecked.isNotEmpty && !closedForShabbat));
  if (localChecking || (onlinePending && here.isEmpty)) {
    return result(GuidancePrimary.checking);
  }

  final driveEmpty = f.otzariaMirrorVersion == null &&
      f.otzariaStatus == AppStatusFact.needsDownload &&
      f.libraryStatus == LibraryStatusFact.needsDownload;
  if (!f.otzariaInstalled && driveEmpty) {
    return result(
      GuidancePrimary.welcome,
      secondary: _quietSecondary(
          f, onlineItems, download, onlineProven, closedForShabbat),
      download: download,
    );
  }

  if (here.isNotEmpty && download.isNotEmpty) {
    return result(
      GuidancePrimary.downloadToDrive,
      secondary: GuidanceSecondary.updateHereToo,
      here: here,
      download: download,
    );
  }
  if (here.isNotEmpty) {
    return result(
      f.otzariaInstalled
          ? GuidancePrimary.updateHere
          : GuidancePrimary.installHere,
      here: here,
    );
  }
  if (download.isNotEmpty) {
    return result(GuidancePrimary.downloadToDrive, download: download);
  }

  if (_attentionItem(f) case final item?) {
    return result(GuidancePrimary.attention, attention: item);
  }
  // רק כשל חלקי: כשכל הבדיקות נכשלו המחשב פשוט לא מחובר, וזה מצב רגיל.
  if (!f.readOnly && f.online == true && unchecked.isNotEmpty) {
    return result(GuidancePrimary.checkFailed);
  }
  if (f.otzariaStatus == AppStatusFact.installedIsNewer) {
    return result(
      GuidancePrimary.newerHereThanDrive,
      secondary: localUnchecked
          ? GuidanceSecondary.checkOnlineNow
          : _quietSecondary(
              f, onlineItems, download, onlineProven, closedForShabbat),
    );
  }
  return result(
    GuidancePrimary.upToDate,
    secondary: localUnchecked
        ? GuidanceSecondary.checkOnlineNow
        : _quietSecondary(
            f, onlineItems, download, onlineProven, closedForShabbat),
    others: [
      if (f.launcherUpdate) OtherUpdate.launcher,
      if (f.customAppsPending) OtherUpdate.customApps,
    ],
  );
}

/// השורה המשנית כשאין מה לעשות: מחשב לא מחובר הוא רמז, לא תקלה.
GuidanceSecondary _quietSecondary(
  GuidanceFacts f,
  List<GuidanceItem> onlineItems,
  List<GuidanceItem> download,
  bool onlineProven,
  bool closedForShabbat,
) {
  // בכונן מוגן אין בדיקה ברשת (`AppSession.checkOnline`), ולכן אין מה לומר.
  if (f.readOnly) return GuidanceSecondary.none;
  return switch (f.online) {
    false => GuidanceSecondary.offlineHint,
    null => GuidanceSecondary.checkOnlineNow,
    true when onlineItems.isNotEmpty && download.isEmpty => f.hasSyncSelection
        ? GuidanceSecondary.syncOff
        : GuidanceSecondary.noSyncSelection,
    true when closedForShabbat => GuidanceSecondary.siteClosedForShabbat,
    // רכיב שנבחר עוד לא נבדק, אף שהמחשב מחובר.
    true when !onlineProven && f.hasSyncSelection =>
      GuidanceSecondary.checkOnlineNow,
    true => GuidanceSecondary.none,
  };
}

/// [download] — `HomeGuidance.downloadItems`: רכיב שההורדה מביאה מוצג כך גם
/// באריח, אחרת האריח ("מעודכנת", "עוד לא בכונן") סותר את הגיבור. [unchecked]
/// — `HomeGuidance.uncheckedItems`, מאותה סיבה.
TileStatus deriveTileStatus(
  GuidanceItem item,
  GuidanceFacts f, {
  List<GuidanceItem> download = const [],
  List<GuidanceItem> unchecked = const [],
}) {
  final local = _localTileStatus(item, f);
  if (unchecked.contains(item) && local == TileStatus.upToDate) {
    return TileStatus.notCheckedOnline;
  }
  if (!download.contains(item)) return local;
  return switch (local) {
    TileStatus.working ||
    TileStatus.checking ||
    TileStatus.attention ||
    TileStatus.preparedElsewhere ||
    TileStatus.needsConsent =>
      local,
    _ => TileStatus.onlineAvailable,
  };
}

TileStatus _localTileStatus(GuidanceItem item, GuidanceFacts f) =>
    switch (item) {
      GuidanceItem.app => switch (f.otzariaStatus) {
          AppStatusFact.idle => TileStatus.unknown,
          AppStatusFact.checking => TileStatus.checking,
          AppStatusFact.installing => TileStatus.working,
          AppStatusFact.upToDate => TileStatus.upToDate,
          AppStatusFact.installedIsNewer => TileStatus.newerHere,
          AppStatusFact.updateAvailable =>
            f.otzariaInstalled ? TileStatus.updateHere : TileStatus.installHere,
          AppStatusFact.needsDownload => TileStatus.nothingOnDrive,
          AppStatusFact.error => TileStatus.attention,
        },
      GuidanceItem.library => switch (f.libraryStatus) {
          _ when f.libraryApplyActive => TileStatus.working,
          LibraryStatusFact.updating => TileStatus.working,
          // העדכון קודם להסכמה, כמו בגיבור שכולל אותו ב"עדכון כאן".
          LibraryStatusFact.updateAvailable => f.libraryFreshInstall
              ? TileStatus.installHere
              : TileStatus.updateHere,
          _ when semanticOnlyHere(f) => TileStatus.updateHere,
          _ when f.semanticConsentRequired => TileStatus.needsConsent,
          LibraryStatusFact.idle => TileStatus.unknown,
          LibraryStatusFact.checking => TileStatus.checking,
          LibraryStatusFact.upToDate => TileStatus.upToDate,
          LibraryStatusFact.needsDownload => TileStatus.nothingOnDrive,
          LibraryStatusFact.error ||
          LibraryStatusFact.needsManualPath =>
            TileStatus.attention,
          LibraryStatusFact.personalTargetElsewhere =>
            TileStatus.preparedElsewhere,
        },
      GuidanceItem.plugins => f.pluginsLoading
          ? TileStatus.checking
          : f.otzariaInstalled && f.pluginUpdatesOnDrive > 0
              ? TileStatus.updateHere
              : TileStatus.upToDate,
    };
