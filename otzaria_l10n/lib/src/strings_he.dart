import 'app_language.dart';
import 'app_strings.dart';
import 'plural.dart';

/// גרסה, כונן או נתיב בתוך משפט עברי: בלי בידוד "0.10.5-beta" מתהפך
/// ל-"beta-0.10.5" ו-"C:" ל-":C". חובה לכל תבנית כזו — `ltr_isolation_test`.
String _ltr(String value) => '\u2066$value\u2069';

/// עברית — ברירת המחדל. הנוסח כאן הוא המקור; האנגלית היא תרגום חופשי שלו.
class HebrewStrings extends AppStrings {
  const HebrewStrings();

  @override
  AppLanguage get language => AppLanguage.hebrew;

  @override
  CommonStrings get common => const _Common();
  @override
  ShellStrings get shell => const _Shell();
  @override
  HomeStrings get home => const _Home();
  @override
  GuidanceStrings get guide => const _Guide();
  @override
  TaskStrings get task => const _Task();
  @override
  PageStrings get pages => const _Pages();
  @override
  AppScreenStrings get appScreen => const _AppScreen();
  @override
  LibraryScreenStrings get libraryScreen => const _LibraryScreen();
  @override
  SettingsScreenStrings get settings => const _Settings();
  @override
  SaferModeStrings get saferMode => const _SaferMode();
  @override
  PluginsStrings get plugins => const _Plugins();
  @override
  FaqStrings get faq => const _Faq();
  @override
  CustomAppsStrings get customApps => const _CustomApps();
  @override
  ErrorReportsStrings get errorReports => const _ErrorReports();
  @override
  AppReportsStrings get appReports => const _AppReports();
  @override
  SetupErrorStrings get setupError => const _SetupError();
  @override
  ReadOnlyDriveStrings get readOnlyDrive => const _ReadOnlyDrive();
  @override
  ElevationStrings get elevation => const _Elevation();
  @override
  PayloadMismatchStrings get payloadMismatch => const _PayloadMismatch();
  @override
  LauncherUpdateStrings get launcherUpdate => const _LauncherUpdate();
  @override
  UnitStrings get units => const _Units();
  @override
  LibraryDomainStrings get libraryDomain => const _LibraryDomain();
  @override
  AppDomainStrings get appDomain => const _AppDomain();
  @override
  PluginsDomainStrings get pluginsDomain => const _PluginsDomain();
  @override
  CustomAppsDomainStrings get customAppsDomain => const _CustomAppsDomain();
  @override
  ErrorReportsDomainStrings get errorReportsDomain =>
      const _ErrorReportsDomain();
}

class _Common extends CommonStrings {
  const _Common();

  @override
  String get confirm => 'אישור';
  @override
  String get cancel => 'ביטול';
  @override
  String get continueAction => 'המשך';
  @override
  String get close => 'סגירה';
  @override
  String get error => 'שגיאה';
  @override
  String get retry => 'נסה שוב';
  @override
  String get errorDetailsButton => 'פרטים';
  @override
  String get errorDetailsTitle => 'פרטי השגיאה';
  @override
  String get install => 'התקנה';
  @override
  String get update => 'עדכון';
  @override
  String get launch => 'הפעלה';
  @override
  String get notCheckedYet => 'טרם נבדק';
  @override
  String get checking => 'בודק…';
  @override
  String get upToDate => 'מעודכן';
  @override
  String get updateAvailable => 'יש עדכון חדש';
  @override
  String get installedIsNewer => 'מותקנת גרסה חדשה יותר';
  @override
  String get installing => 'מתקין…';
  @override
  String get unknownValue => 'לא ידועה';
  @override
  String get lastDownloaded => 'הורד לאחרונה';
  @override
  String get emptyValue => '—';
  @override
  String get copyPathButton => 'העתקת הנתיב';
  @override
  String get pathCopiedSnack => 'הנתיב הועתק';
  @override
  String get closeOtzariaButton => 'סגירת אוצריא';
  @override
  String get closeOtzariaFailedSnack =>
      'אוצריא לא נסגרה — ייתכן שהיא ממתינה לשמירה. יש לסגור אותה ידנית.';
}

class _Shell extends ShellStrings {
  const _Shell();

  @override
  String get appTitle => 'עדכוני אוצריא';
  @override
  String get otzariaLogoLabel => 'אוצריא';
  @override
  String logPathFallback(String path) => 'נתיב יומן הפעילות: ${_ltr(path)}';
  @override
  String folderPathFallback(String path) =>
      'לא הצלחנו לפתוח את התיקייה. היא נמצאת כאן: ${_ltr(path)}';
  @override
  String get closeWhileBusyTitle => 'לסגור באמצע הפעולה?';
  @override
  String get closeWhileDownloadingPrompt =>
      'הורדה רצה כרגע. סגירה עכשיו תבטל אותה: מה שכבר ירד עד הסוף יישאר '
      'בכונן, והחלק שבאמצע יימחק לפני שהתוכנה תיסגר.';
  @override
  String get closeWhileDownloadingConfirm => 'ביטול וסגירה';
  @override
  String get closeWhileInstallingPrompt =>
      'התקנה רצה כרגע. סגירה באמצעה עלולה להשאיר אותה חלקית, ויהיה צורך '
      'להריץ אותה שוב.';
  @override
  String get closeWhileInstallingConfirm => 'סגירה בכל זאת';
  @override
  String get closeWhileBusyKeepGoing => 'המשך';
  @override
  String get helpTooltip => 'עזרה ושאלות נפוצות';
  @override
  String get settingsTooltip => 'הגדרות';
  @override
  String get windowMinimize => 'מזער';
  @override
  String get windowMaximize => 'הגדל';
  @override
  String get windowRestore => 'שחזר';
  @override
  String get windowClose => 'סגור';
  @override
  String get backTooltip => 'חזרה (Esc)';
  @override
  String get breadcrumbHome => 'בית';
}

class _Home extends HomeStrings {
  const _Home();

  @override
  String get otzariaOpenSnack => 'אוצריא פתוחה — יש לסגור אותה ואז לנסות שוב.';

  @override
  String get doNotRemoveDriveWarning => 'אל תנתק את הכונן עד שהעדכון יסתיים.';

  @override
  String get cancelDownloadButton => 'ביטול ההורדה';
  @override
  String get cancelDownloadDialogTitle => 'לבטל את ההורדה?';
  @override
  String get cancelDownloadPrompt =>
      'מה שכבר ירד עד הסוף יישאר בכונן. החלק שבאמצע יימחק, ומה שהיה בכונן '
      'קודם יישאר במקומו.';
  @override
  String get cancelDownloadKeepGoing => 'המשך בהורדה';
  @override
  String get downloadingApp => 'מוריד את תוכנת אוצריא…';
  @override
  String get downloadingLibrary => 'מוריד את ספריית אוצריא…';
  @override
  String get downloadingPlugins => 'מוריד את התוספים…';
  @override
  String get downloadStarting => 'מתחיל הורדה…';

  @override
  String get libraryApplyActive => 'עדכון ספריית אוצריא פעיל';
}

class _Task extends TaskStrings {
  const _Task();

  @override
  String get semanticTitle => 'להוריד גם חיפוש חכם?';
  @override
  String get semanticBody =>
      'חיפוש חכם מוצא מקורות לפי המשמעות, גם כשהמילים שונות ממה שחיפשת.';
  @override
  String get semanticNoTitle => 'לא, רק החיפוש הרגיל (מומלץ)';
  @override
  String get semanticNoBody => 'אפשר להוסיף חיפוש חכם בהורדה הבאה.';
  @override
  String get semanticNoSize => 'בלי תוספת';
  @override
  String get semanticYesTitle => 'כן, גם חיפוש חכם';
  @override
  String get semanticYesBody =>
      'הקבצים תופסים כמה ג׳יגה־בייט, וההורדה תהיה ארוכה יותר. כדי להשתמש בחיפוש החכם באוצריא צריך להסכים לאיסוף נתוני אימון; ההורדה עצמה אינה משנה את ההסכמה.';
  @override
  String get semanticRemember => 'אל תציג שוב';
  @override
  String get semanticRememberBody =>
      'הבחירה תישמר בהגדרות, תחת "חיפוש חכם". אפשר לשנות אותה שם.';
  @override
  String get back => 'חזרה';
  @override
  String get startDownload => 'התחלת ההורדה';
  @override
  String get preparingTitle => 'מתכונן להורדה';
  @override
  String get preparingBody => 'בודק באתר אוצריא מה חדש.';
  @override
  String get downloadingTitle => 'מוריד את העדכונים לכונן';
  @override
  String get downloadingBody => 'אפשר להמשיך לעבוד במחשב בינתיים.';
  @override
  String downloadingStep(String name, int index, int count) =>
      'מוריד את $name · $index מתוך $count';
  @override
  String get componentApp => 'תוכנת אוצריא';
  @override
  String get componentLibrary => 'ספריית אוצריא';
  @override
  String get componentPlugins => 'תוספים';
  @override
  String get stepApp => 'תוכנת אוצריא';
  @override
  String get stepLibrary => 'ספריית אוצריא';
  @override
  String get stepPlugins => 'התוספים';
  @override
  String minutesLeft(int minutes) => plural(
        minutes,
        one: 'נותרה דקה אחת',
        two: 'נותרו שתי דקות',
        many: 'נותרו $minutes דקות',
      );
  @override
  String get lessThanMinuteLeft => 'נותרה פחות מדקה';
  @override
  String get speedPending => 'מחשב מהירות…';
  @override
  String get speedStalled => 'ממתין לנתונים…';
  @override
  String bytesLine(String name, String done, String total) =>
      '$name: ירדו $done מתוך $total';
  @override
  String stageDone(String? size) => size == null ? 'הושלם' : 'הושלם · $size';
  @override
  String get stageWaiting => 'ממתין';
  @override
  String approxSize(String size) => 'כ־$size';
  @override
  String downloadTotal(String size) => 'סך הכול כ־$size';
  @override
  String get sizeChecking => 'בודק כמה ירד…';
  @override
  String get cancelling => 'מבטל…';
  @override
  String get cancelledTitle => 'ההורדה בוטלה';
  @override
  String get cancelledBody =>
      'הכונן נשאר כמו לפני שהתחלת, ואפשר להמשיך להשתמש בו כרגיל.';
  @override
  String cancelledKeptBody(String names) =>
      'מה שירד עד הסוף נשאר בכונן: $names. אפשר להמשיך את ההורדה מאותה נקודה.';
  @override
  String get cancelledRevertFailedBody =>
      'לא כל מה שירד הוסר מהכונן. הורדה חוזרת תמשיך ממנו.';
  @override
  String get downloadAgain => 'הורדה מחדש';
  @override
  String get backHome => 'חזרה לבית';
  @override
  String get retryNothingSnack =>
      'אין עוד מה להתקין מהכונן — המצב העדכני מוצג בבית.';
  @override
  String get doneTitle => 'הכונן מוכן';
  @override
  String get doneBody => 'כל העדכונים ירדו ונשמרו בכונן.';
  @override
  String get doneNothingBody =>
      'באתר אוצריא אין עדכונים חדשים, ולכן לא ירד דבר. הכונן כבר מעודכן.';
  @override
  String doneSkipped(String names) => '$names לא ירדו — באתר אין בהם חדש.';
  @override
  String doneAppValue(String version) => 'אוצריא ${_ltr(version)}';
  @override
  String doneLibraryValue(int version) => 'גרסה $version';
  @override
  String donePluginsValue(int count) => plural(
        count,
        one: 'תוסף אחד בכונן',
        two: 'שני תוספים בכונן',
        many: '$count תוספים בכונן',
      );
  @override
  String get donePluginsUpdated => 'חנות התוספים עודכנה';
  @override
  String get whatNow => 'מה עכשיו?';
  @override
  String get whatNowEject => 'הוצא את הכונן בבטחה';
  @override
  String get whatNowEjectHint => '(סמל הכונן ליד השעון ← הוצאה)';
  @override
  String get whatNowConnect => 'חבר אותו למחשב שבו לומדים עם אוצריא.';
  @override
  String whatNowOpen(String toolName) =>
      'פתח שם את $toolName מתוך הכונן, ולחץ "עדכון המחשב הזה".';
  @override
  String get updateHereToo => 'לעדכן גם במחשב הזה';
  @override
  String get installHereToo => 'להתקין את אוצריא גם כאן';
  @override
  String get finish => 'סיום';
  @override
  String get networkTitle => 'אין חיבור לאינטרנט';
  @override
  String get filterTitle => 'החיבור לאתר אוצריא נחסם';
  @override
  String filterBody(String name) =>
      'ייתכן שמסנן האינטרנט (כמו נטפרי) חוסם את ההורדה של $name. מה שכבר ירד נשמר בכונן. אם זה חוזר, פנה לספק הסינון שלך לאשר את אתר אוצריא, ואז לחץ "נסה שוב".';
  @override
  String networkBody(String name) =>
      'החיבור נקטע באמצע ההורדה של $name. מה שכבר ירד נשמר בכונן. בדוק את החיבור ולחץ "נסה שוב".';
  @override
  String get shabbatTitle => 'אתר אוצריא סגור בשבת ובחג';
  @override
  String get shabbatBody => 'אפשר להוריד במוצאי שבת. מה שכבר ירד נשמר בכונן.';
  @override
  String get spaceTitle => 'אין מספיק מקום בכונן';
  @override
  String spaceBody(String needed, String free) =>
      'נדרשים \u2066$needed\u2069 ופנויים \u2066$free\u2069. פנה מקום בכונן ולחץ "נסה שוב" — מה שכבר ירד נשמר.';
  @override
  String get snapshotTitle => 'ההורדה לא התחילה';
  @override
  String get snapshotBody =>
      'לא הצלחנו לשמור את מצב הכונן לפני ההורדה, ובלי זה אי אפשר לבטל אותה בבטחה. שום דבר לא ירד. בדוק שהכונן מחובר ולחץ "נסה שוב".';
  @override
  String otherTitle(String name) => 'ההורדה של $name לא הושלמה';
  @override
  String get otherBody =>
      'מה שכבר ירד נשמר בכונן, ו"נסה שוב" ימשיך ממנו. אם זה חוזר, הפרטים הטכניים יעזרו למי שמסייע לך.';
  @override
  String get techDetails => 'פרטים טכניים';
  @override
  String get hideTechDetails => 'הסתרת הפרטים הטכניים';
  @override
  String get copyDetails => 'העתקה';
  @override
  String get detailsCopied => 'הפרטים הועתקו';
  @override
  String get otherUserTitle => 'הכלי פועל כמנהל בחשבון אחר';
  @override
  String otherUserBody({required bool firstInstall, String? account}) {
    final who = account == null
        ? 'הכלי הופעל כמנהל בשם חשבון אחר'
        : 'הכלי הופעל כמנהל בשם החשבון \u2068$account\u2069';
    return firstInstall
        ? '$who, ולכן אוצריא תותקן בחשבון של המנהל ולא בחשבון שלך.'
        : '$who, ולכן העדכון ייכנס לחשבון של המנהל ולא לאוצריא שבחשבון שלך.';
  }

  @override
  String get otherUserHint =>
      'מומלץ לסגור את הכלי ולפתוח אותו שוב בלי "הפעל כמנהל".';
  @override
  String get continueAnyway => 'המשך בכל זאת';
  @override
  String get closeTitle => 'צריך לסגור את אוצריא';
  @override
  String get closeBody => 'העדכון מחליף קבצים שאוצריא משתמשת בהם עכשיו.';
  @override
  String closeHint({required bool plugins}) => plugins
      ? 'שום דבר לא הולך לאיבוד: הספרים שפתוחים, הסימניות וההערות יחכו לך בדיוק איפה שהשארת. בסוף העדכון אוצריא תיפתח שוב כדי לאשר את התוספים.'
      : 'שום דבר לא הולך לאיבוד: הספרים שפתוחים, הסימניות וההערות יחכו לך בדיוק איפה שהשארת.';
  @override
  String get closeAfterWizardBody =>
      'אשף ההתקנה פתח את אוצריא. כדי להתקין את ספריית אוצריא צריך לסגור את אוצריא.';
  @override
  String get closeOtzariaAndContinue => 'סגירת אוצריא והמשך';
  @override
  String stepOf(int index, int count) => 'שלב $index מתוך $count';
  @override
  String get installingApp => 'מתקין את אוצריא';
  @override
  String get updatingApp => 'מעדכן את תוכנת אוצריא';
  @override
  String get installingLibrary => 'מתקין את ספריית אוצריא';
  @override
  String get updatingLibrary => 'מעדכן את ספריית אוצריא';
  @override
  String get sendingPlugins => 'שולח את התוספים לאוצריא';
  @override
  String get appWizardFirstBody =>
      'אשף ההתקנה של אוצריא נפתח בחלון נפרד. המשך בו עד הסוף, והכלי ימשיך לבד.';
  @override
  String get appWizardBody =>
      'אשף ההתקנה של אוצריא נפתח בחלון נפרד. בסופו אוצריא תיפתח מעצמה, והכלי ימשיך לבד.';
  @override
  String libraryBody(int? lowMinutes, int? highMinutes) =>
      lowMinutes == null || highMinutes == null
          ? 'זה עשוי להימשך זמן מה, לפי גודל העדכון ומהירות המחשב.'
          : 'צפוי ${_minutesRange(lowMinutes, highMinutes)}, לפי מהירות המחשב.';
  @override
  String get pluginsBody =>
      'הכלי שולח את התוספים לאוצריא, אחד אחד. את ההתקנה מאשרים בחלון של אוצריא.';
  @override
  String get keepDrive => 'אל תנתק את הכונן עד הסוף';
  @override
  String appVersion(String version) => 'גרסה ${_ltr(version)}';
  @override
  String appInstalled(String version) => 'הותקנה · גרסה ${_ltr(version)}';
  @override
  String get appWizardOpen => 'אשף ההתקנה פתוח — המשך בו';
  @override
  String get appStoppedWaiting => 'הפסקנו להמתין · בדוק בבית אם ההתקנה הסתיימה';
  @override
  String get appSkipped => 'לא נדרשה התקנה';
  @override
  String get stopWaiting => 'הפסק להמתין';
  @override
  String get libraryFull => 'ספריית אוצריא המלאה';
  @override
  String libraryVersion(int version) => 'גרסה $version';
  @override
  String libraryDone(String detail) => 'הושלם · $detail';
  @override
  String get libraryWaitingClose => 'ממתין לסגירת אוצריא';
  @override
  String get librarySkipped => 'לא הותקנה עכשיו — אפשר להתקין אחר כך מדף הבית';
  @override
  String pluginsWaiting(int count) => plural(
        count,
        one: 'תוסף אחד · יישלח לאוצריא',
        two: 'שני תוספים · יישלחו לאוצריא',
        many: '$count תוספים · יישלחו לאוצריא',
      );
  @override
  String get pluginsCurrent => 'אשר כל תוסף בחלון של אוצריא';
  @override
  String get pluginsSent => 'נשלחו לאוצריא — אשר שם כל תוסף';
  @override
  String pluginsSentNames(String names) => 'נשלחו: $names';
  @override
  String pluginsNotSent(String names) =>
      'לא נשלחו: $names — אפשר לנסות מדף התוספים';
  @override
  String pluginsStillSending(String names) => 'עוד נשלחים: $names';
  @override
  String get pluginsAfterInstall =>
      'לא נשלחו — שלח אותם מדף התוספים אחרי שההתקנה תסתיים';
  @override
  String get pluginRowSent => 'נשלח לאוצריא';
  @override
  String get pluginRowWaiting => 'ממתין לשליחה';
  @override
  String get pluginRowFailed => 'לא נשלח — אפשר לנסות מדף התוספים';
  @override
  String get finishWithoutWaiting => 'סיום בלי לחכות';
  @override
  String get installedTitle => 'אוצריא מותקנת';
  @override
  String get updatedTitle => 'אוצריא מעודכנת';
  @override
  String doneHereBody({
    required bool firstInstall,
    required bool app,
    required bool library,
    required bool plugins,
    bool libraryNote = false,
  }) {
    if (firstInstall) {
      if (library && libraryNote) {
        return 'תוכנת אוצריא וספריית אוצריא הותקנו במחשב הזה, אבל נשאר דבר אחד לעשות — ראה בשורת הספרייה. אפשר לנתק את הכונן.';
      }
      return library
          ? 'תוכנת אוצריא וספריית אוצריא מותקנות במחשב הזה ומוכנות ללימוד. אפשר לנתק את הכונן.'
          : 'אוצריא מותקנת במחשב הזה. אפשר לנתק את הכונן.';
    }
    final done = app && library
        ? 'התוכנה וספריית אוצריא עודכנו.'
        : app
            ? 'תוכנת אוצריא עודכנה.'
            : library
                ? 'ספריית אוצריא עודכנה.'
                : null;
    return [
      if (done != null) done,
      if (library && libraryNote)
        'נשאר דבר אחד לעשות — ראה בשורת ספריית אוצריא.',
      if (plugins) 'התוספים מחכים לאישור שלך באוצריא.',
      'אפשר לנתק את הכונן.',
    ].join(' ');
  }

  @override
  String get stoppedWaitingTitle => 'הפסקנו להמתין לאשף ההתקנה';
  @override
  String stoppedWaitingBody(
          {required bool firstInstall, required bool libraryDone}) =>
      firstInstall
          ? 'אם האשף עדיין פתוח, סיים בו. אחר כך בדוק בבית שאוצריא הותקנה, ומשם אפשר להתקין גם את ספריית אוצריא.'
          : libraryDone
              ? 'ספריית אוצריא עודכנה. סיים את ההתקנה בחלון האשף, ובדוק בבית שאוצריא עודכנה. אל תנתק את הכונן עד שהאשף יסתיים.'
              : 'סיים את ההתקנה בחלון האשף, ובדוק בבית שאוצריא עודכנה. אל תנתק את הכונן עד שהאשף יסתיים.';
  @override
  String get wizardStillOpenTitle => 'אשף ההתקנה עדיין פתוח';
  @override
  String get wizardStillOpenBody =>
      'סיים את ההתקנה בחלון האשף, ואז בדוק שוב בבית. אל תנתק את הכונן עד שהאשף יסתיים.';
  @override
  String get reindexTitle => 'כדאי לעדכן את אינדקס החיפוש';
  @override
  String get reindexBody =>
      'כך הספרים החדשים יימצאו בחיפוש. אוצריא תיפתח ותעדכן אותו.';
  @override
  String get reindexButton => 'בנייה מחדש';
  @override
  String get toOtzaria => 'מעבר לאוצריא';
  @override
  String get wizardClosedTitle => 'ההתקנה של אוצריא לא הושלמה';
  @override
  String wizardClosedBody(
          {required bool firstInstall, required bool libraryDone}) =>
      firstInstall
          ? 'אשף ההתקנה נסגר לפני הסוף, ואוצריא לא הותקנה. אפשר לנסות שוב בכל עת.'
          : libraryDone
              ? 'אשף ההתקנה נסגר לפני הסוף. אוצריא נשארה בגרסה הקודמת ועובדת כרגיל. ספריית אוצריא שכבר עודכנה נשארת מעודכנת.'
              : 'אשף ההתקנה נסגר לפני הסוף. אוצריא נשארה בגרסה הקודמת ועובדת כרגיל.';
  @override
  String get stoppedTitle => 'העדכון נעצר';
  @override
  String get stoppedBody =>
      'אוצריא נשארה פתוחה, ולכן שאר העדכון לא הותקן. מה שכבר הותקן נשאר.';
  @override
  String get libraryFailedTitle => 'עדכון ספריית אוצריא נכשל';
  @override
  String get libraryInstallFailedTitle => 'התקנת ספריית אוצריא נכשלה';
  @override
  String get appFailedTitle => 'התקנת אוצריא נכשלה';
  @override
  String get libraryFailedKeep => 'אוצריא ממשיכה לעבוד עם הספרייה הקודמת.';
  @override
  String get appFailedKeep => 'אוצריא נשארה בגרסה הקודמת.';
  @override
  String get pluginsFailedTitle => 'שליחת התוספים נכשלה';
  @override
  String pluginsFailedKeep(
          {required bool firstInstall, required bool appDone}) =>
      !appDone
          ? 'התוספים לא נשלחו לאוצריא.'
          : firstInstall
              ? 'אוצריא הותקנה, אבל התוספים לא נשלחו אליה.'
              : 'אוצריא עודכנה, אבל התוספים לא נשלחו אליה.';
  @override
  String get permissionFailedTitle => 'העדכון נכשל';
  @override
  String get permissionInstallFailedTitle => 'ההתקנה נכשלה';
  @override
  String get permissionAppBody =>
      'אין לכלי הרשאה לעדכן את אוצריא, כי היא מותקנת לכל המשתמשים במחשב.';
  @override
  String get permissionAppInstallBody =>
      'אין לכלי הרשאה להתקין את אוצריא במחשב הזה.';
  @override
  String get permissionLibraryBody =>
      'אין לכלי הרשאה לשנות את התיקייה שבה נמצאת ספריית אוצריא.';
  @override
  String get elevateTitle => 'הפעלה מחדש כמנהל';
  @override
  String get elevateBody =>
      'הכלי ייפתח מחדש עם הרשאות מנהל, ואז אפשר לנסות שוב.';
  @override
  String get elevateButton => 'הפעלה מחדש כמנהל';
  @override
  String get toLibraryPage => 'לדף ספריית אוצריא';
  @override
  String get toPluginsPage => 'לדף התוספים';
  @override
  String get showProgress => 'הצג התקדמות';
}

class _Pages extends PageStrings {
  const _Pages();

  @override
  String get advancedTitle => 'מתקדם';
  @override
  String get onThisComputer => 'במחשב הזה';
  @override
  String get onTheDrive => 'בכונן';
  @override
  String get nothingYet => 'אין עדיין';
  @override
  String get onlineAvailable => 'זמין להורדה';
  @override
  String get nothingNewOnline => 'אין חדש';
  @override
  String downloadedOn(String date) => 'ירדה ב-$date';
  @override
  String get chipUpdateOnDrive => 'יש עדכון בכונן';
  @override
  String get chipUpToDate => 'מעודכנת';
  @override
  String get lockedChip => 'נעול בסיסמה';
  @override
  String get appChipNotInstalled => 'לא מותקנת במחשב הזה';
  @override
  String appWhatsNew(String version) => 'מה חדש באוצריא ${_ltr(version)}';
  @override
  String get appInstalledNotesCaption => 'הגרסה שמותקנת במחשב הזה';
  @override
  String get appAdvancedPageTitle => 'אוצריא — מתקדם';
  @override
  String appAwaitsNewer({required bool stable}) => stable
      ? 'מותקנת כאן גרסה ניסיונית, חדשה מהיציבה שבכונן. תעבור לגרסה היציבה כשתצא גרסה יציבה חדשה יותר מזו שמותקנת.'
      : 'מותקנת כאן גרסה יציבה, חדשה מהניסיונית שבכונן. תעבור לגרסה הניסיונית כשתצא גרסה ניסיונית חדשה יותר מזו שמותקנת.';
  @override
  String get pageBusyNote =>
      'משימה אחרת רצה עכשיו, ולכן הפעולות כאן ממתינות לסיומה.';
  @override
  String appAdvancedSummary({required bool channel}) => channel
      ? 'גרסה ניסיונית, התקנה מחדש, מיקום ההתקנה והתיקייה שבכונן'
      : 'התקנה מחדש, מיקום ההתקנה והתיקייה שבכונן';
  @override
  String get appChannelTitle => 'איזו גרסה להתקין';
  @override
  String get appChannelBody =>
      'גרסה ניסיונית מקבלת חידושים לפני כולם, אבל עלולות להיות בה תקלות.';
  @override
  String get appReinstallTitle => 'התקנה מחדש של אותה גרסה';
  @override
  String appReinstallBody(String version) =>
      'מתקינה שוב את אוצריא ${_ltr(version)}. עוזר כשמשהו בתוכנה לא עובד כמו שצריך.';
  @override
  String get appReinstallUnavailable => 'אין בכונן את הגרסה שמותקנת כאן.';
  @override
  String get appLocationTitle => 'מיקום ההתקנה';
  @override
  String get appSourceTitle => 'התיקייה בכונן שממנה מתקינים';
  @override
  String get libSemanticSection => 'חיפוש חכם';
  @override
  String libAdvancedSummary({required bool reindex}) => reindex
      ? 'מיקום ספריית אוצריא, עדכון אינדקס החיפוש, הספרייה המלאה והתיקייה '
          'שבכונן'
      : 'מיקום ספריית אוצריא, הספרייה המלאה והתיקייה שבכונן';
  @override
  String get libMissingFilesTitle => 'חלק מקובצי ספריית אוצריא לא הגיעו לכונן';
  @override
  String libChipCompanions(String names) => 'בכונן: $names';
  @override
  String libVersion(int version) => 'גרסה $version';
  @override
  String get libNotInstalled => 'לא מותקנת';
  @override
  String get libInstallButton => 'התקנת ספריית אוצריא';
  @override
  String get libInstallWithAppButton => 'התקנת התוכנה וספריית אוצריא';
  @override
  String get libInstallWithAppNote =>
      'אוצריא עוד לא מותקנת במחשב הזה. קודם תותקן התוכנה, ואחריה ספריית אוצריא.';
  @override
  String get libInstallNeedsApp =>
      'אוצריא לא מותקנת במחשב הזה, ובכונן אין את התוכנה. כדי להתקין את ספריית אוצריא, הורד קודם את התוכנה במחשב עם אינטרנט.';
  @override
  String get libUpdateNeedsApp =>
      'אוצריא לא מותקנת במחשב הזה. התקן אותה קודם מהבית, ואז אפשר יהיה להתקין כאן את ספריית אוצריא.';
  @override
  String get libUpdateButton => 'עדכון ספריית אוצריא';
  @override
  String get libNotFoundTitle => 'לא מצאנו את ספריית אוצריא במחשב הזה';
  @override
  String get libNotFoundBody =>
      'תוכנת אוצריא מותקנת, אבל הספרייה לא נמצאת במקום הרגיל. אם העברת אותה, בחר איפה היא עכשיו.';
  @override
  String get libPickFolderButton => 'בחירת מיקום ספריית אוצריא';
  @override
  String get libSemanticTitle => 'חיפוש לפי משמעות';
  @override
  String get libSemanticBody =>
      'חיפוש חכם מוצא מקורות גם כשהמילים שונות ממה שחיפשת. כדי להפעיל אותו '
      'צריך להסכים שאוצריא תשמור את מילות החיפוש ואילו תוצאות עזרו לך. הכלי '
      'הזה יעביר אותן למפתחים דרך הכונן, יחד עם הדיווחים.';
  @override
  String get libSemanticGrant => 'הסכמה והפעלה';
  @override
  String get libSemanticClosedNote => 'אוצריא צריכה להיות סגורה כדי להפעיל.';
  @override
  String get libSemanticActive => 'פעיל';
  @override
  String get libSemanticActiveBody =>
      'ההסכמה פעילה. אפשר לבטל אותה בהגדרות של אוצריא.';
  @override
  String get libLocationTitle => 'מיקום ספריית אוצריא במחשב הזה';
  @override
  String get libLocationNone => 'עוד לא נבחר מיקום';
  @override
  String get libFullTitle => 'ספריית אוצריא המלאה במקום עדכון';
  @override
  String libFullBody(String size) =>
      'העדכון הרגיל נכשל. אפשר להתקין במקומו את ספריית אוצריא המלאה שבכונן ($size). זה לוקח יותר זמן, ולא צריך אינטרנט.';
  @override
  String get libFullBodyNoSize =>
      'העדכון הרגיל נכשל. אפשר להתקין במקומו את ספריית אוצריא המלאה שבכונן. זה לוקח יותר זמן, ולא צריך אינטרנט.';
  @override
  String libFullMeta({String? size, int? lowMinutes, int? highMinutes}) => [
        size == null
            ? 'ספריית אוצריא המלאה שבכונן'
            : 'ספריית אוצריא המלאה שבכונן: $size',
        if (lowMinutes != null && highMinutes != null)
          'צפוי ${_minutesRange(lowMinutes, highMinutes)}',
      ].join(' · ');
  @override
  String get libFullUnavailable =>
      'אפשרי רק אחרי שעדכון רגיל נכשל, כשבכונן יש ספריית אוצריא מלאה.';
  @override
  String get libPersonalReadOnly =>
      'הכונן מוגן מפני כתיבה, ולכן אי אפשר לרשום אליו את המחשב הזה.';
  @override
  String get libSourceTitle => 'התיקייה בכונן שממנה מעדכנים';
  @override
  String get repDescription =>
      'כשמשהו לא עובד באוצריא או בתוספים, נשמר דיווח קצר. הכלי מעביר את הדיווחים למפתחים — גם ממחשבים בלי אינטרנט.';
  @override
  String get repSendingTitle => 'שולח את הדיווחים';
  @override
  String repWaitingTitle(int count) =>
      count == 1 ? '1 דיווח ממתין לשליחה' : '$count דיווחים ממתינים לשליחה';
  @override
  String repWaitingBody({required bool withSearch}) => withSearch
      ? 'הם שמורים בכונן, יחד עם נתוני האימון של החיפוש החכם. המחשב הזה מחובר לאינטרנט, אז אפשר לשלוח אותם עכשיו.'
      : 'הם שמורים בכונן. המחשב הזה מחובר לאינטרנט, אז אפשר לשלוח אותם עכשיו.';
  @override
  String repStoredTitle(int count) =>
      count == 1 ? '1 דיווח שמור בכונן' : '$count דיווחים שמורים בכונן';
  @override
  String get repStoredBody =>
      'הם יישלחו כשתחבר את הכונן למחשב עם אינטרנט ותפתח שם את הכלי.';
  @override
  String get repUncheckedBody =>
      'עוד לא נבדק אם המחשב הזה מחובר לאינטרנט. אם הוא מחובר, אפשר לשלוח מכאן.';
  @override
  String get repOnlyOnline => 'אפשר לשלוח רק ממחשב מחובר';
  @override
  String get repCheckConnectionButton => 'בדיקת חיבור';
  @override
  String repAlsoStored(int count) =>
      count == 1 ? 'בכונן כבר שמור 1 דיווח.' : 'בכונן כבר שמורים $count.';
  @override
  String get repNothingTitle => 'אין דיווחים מאוצריא שממתינים';
  @override
  String get repSendButton => 'שליחה עכשיו';
  @override
  String repSendStoredButton(int count) => plural(count,
      one: 'שליחת הדיווח שבכונן', many: 'שליחת $count הדיווחים שבכונן');
  @override
  String get repWhatIsSent => 'מה נשלח?';
  @override
  String repOwnPending(int count) => 'דיווחים מהכלי הזה שממתינים ($count)';
  @override
  String get repOwnTitle => 'דיווחים על הכלי הזה';
  @override
  String get repOwnEmpty => 'עוד אין דיווחים על הכלי הזה.';
  @override
  String get repCrumb => 'דיווחים';
  @override
  String get repProblemSection => 'משהו לא עובד בכלי הזה?';
  @override
  String get repProblemTitle => 'דיווח על בעיה בכלי';
  @override
  String get repProblemBody => 'תאר מה קרה, ואפשר לצרף צילומי מסך.';
  @override
  String get selfCrumb => 'הכלי הזה';
  @override
  String get selfTitle => 'עדכון הכלי הזה';
  @override
  String get selfDescription =>
      'עדכוני אוצריא מעדכנת גם את עצמה. העדכון לוקח פחות מדקה, והכלי נפתח מחדש לבד.';
  @override
  String selfChipOnline(String version) => 'באתר יש גרסה ${_ltr(version)}';
  @override
  String selfChipOnDrive(String version) => 'בכונן יש גרסה ${_ltr(version)}';
  @override
  String get selfChipUpToDate => 'מעודכן';
  @override
  String get selfCurrentVersion => 'הגרסה שפתוחה עכשיו';
  @override
  String get selfNewVersion => 'גרסה חדשה';
  @override
  String get selfDownloadButton => 'הורדה והפעלה מחדש';
  @override
  String selfDownloading(int percent) => 'מוריד את הגרסה החדשה · $percent%';
  @override
  String get selfInstalling => 'מתקין ומפעיל מחדש…';
  @override
  String get selfErrorTitle => 'העדכון של הכלי לא הצליח';
  @override
  String get selfDownloadFailed => 'ההורדה של הגרסה החדשה לא הושלמה.';
  @override
  String get selfCheckFailed => 'לא הצלחנו לקרוא את הגרסה החדשה שבכונן.';
  @override
  String get selfInstallFailed => 'ההתקנה של הגרסה החדשה לא הצליחה.';
  @override
  String get selfErrorKeepsWorking => 'הגרסה הנוכחית ממשיכה לעבוד כרגיל.';
  @override
  String get selfManualTitle => 'צריך להחליף את הכלי ידנית';
  @override
  String get selfOpenFolder => 'פתיחת התיקייה';
  @override
  String get selfAdminTitle => 'צריך הרשאות מנהל';
  @override
  String get selfAdminBody =>
      'הכלי שמור בתיקייה שרק מנהל יכול לשנות. הפעל אותו מחדש כמנהל, ולחץ שוב על "התקנה והפעלה מחדש".';
  @override
  String get selfReadOnly =>
      'הכונן מוגן מפני כתיבה, ולכן אי אפשר להוריד אליו את הגרסה החדשה.';
  @override
  String selfWhatsNew(String version) => 'מה חדש ב-${_ltr(version)}';
}

class _Guide extends GuidanceStrings {
  const _Guide();

  @override
  String get eyebrowOnline => 'המחשב הזה: מחובר לאינטרנט';
  @override
  String get eyebrowOffline => 'המחשב הזה: לא מחובר';
  @override
  String get eyebrowThisComputer => 'המחשב הזה';
  @override
  String eyebrowOtzaria(String version) => 'אוצריא ${_ltr(version)}';
  @override
  String get eyebrowNotInstalled => 'אוצריא עוד לא מותקנת';

  @override
  String get checkingTitle => 'בודק מה יש בכונן ובמחשב הזה';
  @override
  String get checkingBody => 'זה לוקח רגע. אחר כך יופיע כאן מה כדאי לעשות.';
  @override
  String get installHereTitle => 'אוצריא מוכנה להתקנה במחשב הזה';
  @override
  String get installHereBody =>
      'התוכנה וספריית אוצריא כבר בכונן. תוספים מתקינים אחר כך, מדף התוספים.';
  @override
  String get installHereButton => 'התקנת אוצריא במחשב הזה';
  @override
  String get updateHereTitle => 'יש עדכונים בכונן למחשב הזה';
  @override
  String get updateHereBody => 'הספרים, הסימניות וההערות שלך נשמרים כמו שהם.';
  @override
  String get updateHereButton => 'עדכון המחשב הזה';
  @override
  String get whatsNewButton => 'מה חדש?';
  @override
  String get downloadTitle => 'יש עדכונים חדשים באתר אוצריא';
  @override
  String get downloadBody =>
      'מורידים אותם לכונן הזה, ומשם מעדכנים כל מחשב — גם מחשב בלי אינטרנט.';
  @override
  String get downloadButton => 'הורדת הכול לכונן';
  @override
  String updateHereTooNote(String? version) => version == null
      ? 'בכונן כבר יש עדכון שלא הותקן במחשב הזה. אפשר להתקין אותו עכשיו, '
          'או אחרי ההורדה.'
      : 'בכונן כבר יש עדכון שלא הותקן במחשב הזה (אוצריא ${_ltr(version)}). אפשר '
          'להתקין אותו עכשיו, או אחרי ההורדה.';
  @override
  String syncOffNote({
    required bool app,
    required bool library,
    required bool plugins,
  }) {
    final off = [
      if (app) 'התוכנה',
      if (library) 'ספריית אוצריא',
      if (plugins) 'התוספים',
    ];
    if (off.isEmpty) return noSyncSelectionNote;
    if (off.length == 1) {
      return plugins
          ? 'התוספים לא יירדו — הם כבויים בהגדרות.'
          : '${off.single} לא תרד — היא כבויה בהגדרות.';
    }
    final names = '${off.sublist(0, off.length - 1).join(', ')} ו${off.last}';
    return '$names לא יירדו — הם כבויים בהגדרות.';
  }

  @override
  String get noSyncSelectionNote => 'בהגדרות לא נבחר שום דבר להוריד.';
  @override
  String syncOffOnlyNote({
    required bool app,
    required bool library,
    required bool plugins,
    bool libraryFilesOnly = false,
  }) {
    final off = [
      if (app) 'בתוכנה',
      if (library) 'בספריית אוצריא',
      if (plugins) 'בתוספים',
    ];
    if (off.length > 1) {
      final names = '${off.sublist(0, off.length - 1).join(', ')} ו${off.last}';
      return 'באתר יש חדש $names, אבל ההורדה שלהם כבויה בהגדרות.';
    }
    if (plugins) {
      return 'באתר יש עדכונים לתוספים, אבל ההורדה שלהם כבויה בהגדרות.';
    }
    if (app) {
      return 'באתר יש גרסה חדשה של התוכנה, אבל ההורדה שלה כבויה בהגדרות.';
    }
    if (library && libraryFilesOnly) {
      return 'באתר יש קבצים חדשים לספריית אוצריא, אבל ההורדה שלהם כבויה בהגדרות.';
    }
    if (library) {
      return 'באתר יש גרסה חדשה של ספריית אוצריא, אבל ההורדה שלה כבויה בהגדרות.';
    }
    return noSyncSelectionNote;
  }

  @override
  String get downloadBusySnack =>
      'משימה אחרת רצה עכשיו. אפשר להוריד כשהיא תסתיים.';
  @override
  String get changeInSettingsLink => 'שינוי';
  @override
  String get chooseInSettingsLink => 'לבחירה בהגדרות';
  @override
  String get libraryRetryNote =>
      'ההורדה הקודמת של ספריית אוצריא לא הושלמה. הורדה חוזרת תמשיך ממה שכבר ירד.';
  @override
  String get semanticOfferNote => 'חיפוש חכם זמין להורדה';
  @override
  String get semanticOfferLink => 'הורדה';
  @override
  String get recheckNothingTitle => 'בדקתי שוב — אין חדש באתר אוצריא';
  @override
  String recheckNothingBody(String time, {required bool upToDate}) => [
        'באתר אוצריא אין עדכונים חדשים (נבדק ב-${_ltr(time)}), ולכן לא ירד כלום.',
        if (upToDate) 'הכונן והמחשב הזה מעודכנים.',
      ].join(' ');
  @override
  String recheckNothingNote(String time) =>
      'בדקתי שוב — אין חדש באתר אוצריא · נבדק ב-${_ltr(time)}';
  @override
  String get nothingNewTitle => 'אין חדש באתר אוצריא';
  @override
  String nothingNewBody(String time, {required bool upToDate}) => [
        'לפי הבדיקה של ${_ltr(time)} אין עדכונים חדשים, ולכן לא ירד כלום.',
        if (upToDate) 'הכונן והמחשב הזה מעודכנים.',
      ].join(' ');
  @override
  String nothingNewNote(String time) =>
      'אין חדש באתר אוצריא · נבדק ב-${_ltr(time)}';
  @override
  String failedDownloadsNote(String names) => 'לא ירד לכונן: $names.';
  @override
  String get upToDateTitle => 'הכול מעודכן במחשב הזה';
  @override
  String upToDateBody(String? version) => version == null
      ? 'תוכנת אוצריא, ספריית אוצריא והתוספים מעודכנים.'
      : 'תוכנת אוצריא ${_ltr(version)}, ספריית אוצריא והתוספים מעודכנים.';
  @override
  String get driveInstalledTitle => 'כל מה שבכונן כבר מותקן כאן';
  @override
  String driveInstalledBody(String? version) => version == null
      ? 'תוכנת אוצריא, ספריית אוצריא והתוספים מותקנים.'
      : 'תוכנת אוצריא ${_ltr(version)}, ספריית אוצריא והתוספים מותקנים.';
  @override
  String get othersPendingTitle => 'יש עוד עדכונים';
  @override
  String get otherLauncherTitle => 'הכלי הזה';
  @override
  String otherLauncherOnline(String version) =>
      'גרסה ${_ltr(version)} באתר אוצריא';
  @override
  String otherLauncherOnDrive(String version) => 'גרסה ${_ltr(version)} בכונן';
  @override
  String get checkFailedTitle => 'לא הצלחתי לבדוק ברשת';
  @override
  String checkFailedBody({
    required bool appFailed,
    required bool libraryFailed,
    required bool pluginsFailed,
    required bool appChecked,
    required bool libraryChecked,
    required bool pluginsChecked,
  }) {
    String names(bool app, bool library, bool plugins) {
      final all = [
        if (app) 'תוכנת אוצריא',
        if (library) 'ספריית אוצריא',
        if (plugins) 'התוספים',
      ];
      if (all.length < 2) return all.join();
      return '${all.sublist(0, all.length - 1).join(', ')} ו${all.last}';
    }

    final failed = names(appFailed, libraryFailed, pluginsFailed);
    final lead = failed.isEmpty
        ? 'הבדיקה באתר אוצריא לא הצליחה.'
        : 'הבדיקה של $failed באתר אוצריא לא הצליחה.';
    final checked = names(appChecked, libraryChecked, pluginsChecked);
    if (checked.isEmpty) return lead;
    final count =
        [appChecked, libraryChecked, pluginsChecked].where((c) => c).length;
    final verb = pluginsChecked
        ? 'נבדקו ומעודכנים'
        : count == 1
            ? 'נבדקה ומעודכנת'
            : 'נבדקו ומעודכנות';
    return '$lead $checked $verb.';
  }

  @override
  String get launchButton => 'פתיחת אוצריא';
  @override
  String get recheckButton => 'בדוק שוב';
  @override
  String get offlineNote =>
      'עדכונים חדשים מורידים לכונן במחשב המחובר, ואז מחברים אותו לכאן.';
  @override
  String get checkOnlineNowNote =>
      'עוד לא נבדק אם יש באתר אוצריא משהו חדש. "בדוק שוב" בודק עכשיו.';
  @override
  String get newerTitle => 'המחשב הזה מעודכן יותר מהכונן';
  @override
  String newerChannelTitle({required bool stable}) => stable
      ? 'המחשב הזה מעודכן יותר מהגרסה היציבה שבכונן'
      : 'המחשב הזה מעודכן יותר מהגרסה הניסיונית שבכונן';
  @override
  String newerBody(String installed, String onDrive) =>
      'במחשב הזה מותקנת אוצריא ${_ltr(installed)}, ובכונן יש ${_ltr(onDrive)}. אין מה '
      'להתקין מהכונן.';
  @override
  String get newerNote =>
      'עדכונים חדשים יותר מורידים לכונן במחשב המחובר, ואז מחברים אותו לכאן.';
  @override
  String get attentionAppTitle => 'משהו בתוכנת אוצריא צריך בדיקה';
  @override
  String get attentionLibraryTitle => 'משהו בספריית אוצריא צריך בדיקה';
  @override
  String get attentionBody => 'בדף שלה מוסבר מה קרה ומה אפשר לעשות.';
  @override
  String get attentionLibraryButton => 'לדף ספריית אוצריא';
  @override
  String get taskDownloadingTitle => 'מוריד את העדכונים לכונן';
  @override
  String get taskDownloadingBody =>
      'אפשר להמשיך לעבוד במחשב. אל תנתק את הכונן עד שההורדה תסתיים.';
  @override
  String get taskInstallingAppTitle => 'מתקין את אוצריא';
  @override
  String get taskUpdatingLibraryTitle => 'מעדכן את ספריית אוצריא';
  @override
  String get taskBusyTitle => 'פעולה רצה כרגע';
  @override
  String get taskBusyBody =>
      'כשהיא תסתיים, יופיע כאן מה עוד אפשר לעשות במחשב הזה.';
  @override
  String get taskNamedBody =>
      'כשהפעולה תסתיים, יופיע כאן מה עוד אפשר לעשות במחשב הזה.';
  @override
  String get taskSyncingPluginsTitle => 'מוריד את חנות התוספים לכונן';
  @override
  String get taskUpdatingPluginsTitle => 'מעדכן את התוספים';
  @override
  String get taskExportingStoreTitle => 'מעתיק את חנות התוספים';
  @override
  String get taskDownloadingCustomAppsTitle => 'מוריד תוכנות נוספות לכונן';
  @override
  String get taskCustomAppsTitle => 'עובד על תוכנה נוספת';
  @override
  String get taskInstallingLauncherTitle => 'מתקין את הגרסה החדשה של הכלי';
  @override
  String get taskRestartingElevatedTitle => 'מפעיל את הכלי מחדש כמנהל';

  @override
  String itemUpdateTo(String version) => 'עדכון ל-${_ltr(version)}';
  @override
  String itemLibraryUpdateTo(int version) => 'עדכון לגרסה $version';
  @override
  String get itemLibraryUpdate => 'עדכון';
  @override
  String get itemLibraryFull => 'ספריית אוצריא המלאה';
  @override
  String itemPluginUpdates(int count) =>
      count == 1 ? '1 עדכון תוסף' : '$count עדכוני תוספים';
  @override
  String itemPlugins(int count) => count == 1 ? '1 תוסף' : '$count תוספים';
  @override
  String get itemPluginsCatalog => 'רשימת התוספים';
  @override
  String get itemStoreApp => 'עדכון לחנות התוספים';
  @override
  String itemPluginsWithStore(int count) =>
      '${itemPlugins(count)} · עדכון לחנות';
  @override
  String itemUpTo(String size) => 'עד $size';
  @override
  String downloadTotal(
    String size, {
    required bool plusApp,
    required bool plusLibrary,
    required bool plusPlugins,
  }) {
    final plus = [
      if (plusApp) 'התוכנה',
      if (plusLibrary) 'ספריית אוצריא',
      if (plusPlugins) 'התוספים',
    ];
    if (plus.isEmpty) return 'סה״כ עד $size';
    final names = plus.length == 1
        ? plus.single
        : '${plus.sublist(0, plus.length - 1).join(', ')} ו${plus.last}';
    return 'סה״כ עד $size ועוד $names';
  }

  @override
  String driveFree(String size) => 'פנוי בכונן: $size';

  @override
  String get otzariaOpenTitle => 'אוצריא פתוחה כרגע';
  @override
  String get otzariaOpenBody =>
      'כשתלחץ "עדכון", הכלי יבקש לסגור אותה. הספרים שפתוחים יחכו לך.';
  @override
  String get otzariaOpenIdleBody =>
      'אין כרגע מה להתקין, ואפשר להמשיך לעבוד בה. כשיהיה עדכון, הכלי יבקש לסגור אותה.';
  @override
  String get autoInstallSkippedLead => 'לכן העדכון האוטומטי לא הותקן. ';
  @override
  String newPluginsTitle(int count) =>
      count == 1 ? '1 תוסף חדש בכונן' : '$count תוספים חדשים בכונן';
  @override
  String newPluginsBody(List<String> names, int more) {
    final listed = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} ו${names.last}';
    if (names.length == 1 && more == 0) {
      return '$listed — אפשר להתקין אותו באוצריא.';
    }
    final suffix = more > 0 ? ' ועוד $more' : '';
    return '$listed$suffix — אפשר להתקין אותם באוצריא.';
  }

  @override
  String get toPluginsButton => 'לתוספים';
  @override
  String libraryMissingFilesBody(String names) =>
      'חסר בכונן: $names. הורדה חוזרת לכונן תשלים את החסר, ושאר העדכון יותקן '
      'כרגיל.';
  @override
  String get libraryCompanionsAbsentBody =>
      'בכונן אין את התלמוד הבבלי, רשימת הספרים והמילון, ולכן הם לא יותקנו. '
      'הורדה חוזרת לכונן תביא אותם.';
  @override
  String get semanticConsentBody =>
      'חיפוש חכם נמצא בכונן. כדי להפעיל אותו צריך להסכים שאוצריא תשמור את מילות '
      'החיפוש ואילו תוצאות עזרו לך.';

  @override
  String get tilesLabel => 'מה יש בכונן ובמחשב הזה';
  @override
  String get tileApp => 'תוכנת אוצריא';
  @override
  String get tileLibrary => 'ספריית אוצריא';
  @override
  String get tilePlugins => 'תוספים';
  @override
  String get tileCustomApps => 'תוכנות נוספות';
  @override
  String get tileReports => 'דיווחים על תקלות';
  @override
  String get chipReadyToInstall => 'מוכנה להתקנה';
  @override
  String get chipNewerHere => 'מעודכנת יותר מהכונן';
  @override
  String get chipNotOnDrive => 'עוד לא בכונן';
  @override
  String get chipChecking => 'בודק…';
  @override
  String get chipInstalling => 'מתקינה…';
  @override
  String get chipUpdating => 'מתעדכנת…';
  @override
  String get chipAttention => 'משהו השתבש';
  @override
  String get chipLibraryUpToDate => 'מעודכנת';
  @override
  String chipPluginUpdates(int count) =>
      count == 1 ? '1 עדכון בכונן' : '$count עדכונים בכונן';
  @override
  String chipPluginsInstalled(int count) =>
      count == 1 ? '1 מותקן' : '$count מותקנים';
  @override
  String chipPluginsOnDrive(int count) => '$count בכונן';
  @override
  String get chipNoPlugins => 'אין תוספים בכונן';
  @override
  String chipAppsPending(int count) =>
      count == 1 ? '1 עדכון בכונן' : '$count עדכונים בכונן';
  @override
  String chipAppsInstalled(int count) => '$count בכונן';
  @override
  String chipReportsToSend(int count) =>
      count == 1 ? '1 ממתין לשליחה' : '$count ממתינים לשליחה';
  @override
  String chipReportsToCollect(int count) =>
      count == 1 ? '1 חדש לאיסוף מאוצריא' : '$count חדשים לאיסוף מאוצריא';
  @override
  String get chipReportsSending => 'שולח…';
  @override
  String get chipReportsLocked => 'לא זמין בכונן הזה';
  @override
  String get chipNewOnline => 'יש עדכון להוריד לכונן';
  @override
  String tileFactHere(String value) => 'במחשב: $value';
  @override
  String tileFactDrive(String value) => 'בכונן: $value';
  @override
  String tileFactOnline(String value) => 'ברשת: $value';
  @override
  String tileFactVersion(String version) => 'גרסה ${_ltr(version)}';
  @override
  String get updateAvailableButton => 'עדכון זמין';

  @override
  String launcherOnline(String version) =>
      'יש גרסה חדשה של הכלי הזה (${_ltr(version)})';
  @override
  String launcherOnDrive(String version) =>
      'בכונן יש גרסה חדשה של הכלי הזה (${_ltr(version)})';
  @override
  String get launcherDownloading => 'מוריד את הגרסה החדשה של הכלי';
  @override
  String checkedAt(String time) => 'נבדק ב-$time';
  @override
  String get recheckHint => 'בדיקה חוזרת: Ctrl+R או F5';
  @override
  String get checkNowLink => 'בדוק עכשיו';
  @override
  String drive(String letter) => 'כונן ${_ltr(letter)}';
  @override
  String get driveReadOnlySuffix => 'מוגן מפני כתיבה';
  @override
  String get driveFullSuffix => 'מלא';

  @override
  String get welcomeTitle => 'ברוך הבא לעדכוני אוצריא';
  @override
  String get welcomeLeadOnline =>
      'כך מביאים את אוצריא לכל מחשב, גם בלי אינטרנט:';
  @override
  String get welcomeLeadOffline =>
      'הכונן הזה עוד ריק, והמחשב הזה לא מחובר. כך מתחילים:';
  @override
  String step(int number) => 'שלב $number';
  @override
  String get youAreHere => 'אתה כאן';
  @override
  String get step1Title => 'במחשב מחובר';
  @override
  String get step1BodyOnline => 'מורידים את אוצריא לכונן הזה.';
  @override
  String get step1BodyOffline => 'פותחים שם את הכלי מהכונן ומורידים.';
  @override
  String get step2Title => 'מעבירים את הכונן';
  @override
  String get step2Body => 'מוציאים אותו בבטחה מהמחשב.';
  @override
  String get step3Title => 'במחשב שבו לומדים';
  @override
  String get step3BodyOnline => 'פותחים שם את הכלי ומתקינים בלחיצה.';
  @override
  String get step3BodyOffline => 'חוזרים לכאן ומתקינים בלחיצה.';
  @override
  String get welcomeDownloadButton => 'הורדת אוצריא לכונן';
  @override
  String get welcomeDownloadNote =>
      'הכלי מוריד רק לכונן. הוא לא מתקין כלום במחשב הזה בלי שתבקש.';
  @override
  String get welcomeHelpButton => 'איך מתחילים?';
  @override
  String get welcomeOfflineNote =>
      'אי אפשר להוריד מהמחשב הזה. חבר את הכונן למחשב מחובר ופתח שם את '
      'הכלי.';
  @override
  String get welcomeAlsoOnDrive => 'גם בכונן הזה:';

  @override
  String reportsCollectTitle({
    required int reports,
    required int searchRecords,
  }) {
    final parts = [
      if (reports > 0 || searchRecords <= 0)
        plural(reports, one: '1 דיווח חדש', many: '$reports דיווחים חדשים'),
      if (searchRecords > 0)
        plural(searchRecords,
            one: '1 רשומת נתוני אימון',
            many: '$searchRecords רשומות נתוני אימון'),
    ];
    final single = parts.length == 1 && (reports == 1 || searchRecords == 1);
    return 'באוצריא ${single ? 'מחכה' : 'מחכים'} ${parts.join(' ו-')}';
  }

  @override
  String get reportsCollectBody =>
      'האיסוף מעתיק אותם לכונן, כדי לשלוח אותם מכאן או ממחשב מחובר '
      'לאינטרנט. מה יועתק:';
  @override
  String get reportsDisclosureReports =>
      'דיווחים: מה שכתבת, כתובת הדואר האלקטרוני אם מסרת אותה, קטעים מהיומן של '
      'התוכנה, פרטים טכניים על המחשב ועל אוצריא (כמו גרסאות ומערכת ההפעלה), '
      'צילומי מסך ותמונות שצירפת, ובדיווח על קריסה שאישרת — גם העתק של '
      'זיכרון התוכנה ברגע הקריסה.';
  @override
  String get reportsDisclosureSearch =>
      'נתוני האימון של החיפוש החכם, שנאספו בהסכמתך: נתוני השימוש בחיפוש, כולל מילות '
      'החיפוש, יחד עם המפתח האנונימי שחותם עליהם. הם נמחקים מאוצריא רק אחרי '
      'שנשמרו בכונן, והמפתח נמחק מהכונן כשכל הנתונים נשלחו.';
  @override
  String get reportsDisclosureStorage =>
      'הכול נשמר בכונן כמו שהוא, בלי הצפנה, עד שיישלח — מי שמחזיק בכונן יכול '
      'לקרוא אותו. בשליחה הנתונים עוברים לאוצריא בלבד, ונמחקים מהכונן.';
  @override
  String get reportsCollectButton => 'איסוף מאוצריא';
  @override
  String get reportsNothing => 'כשמשהו לא יעבוד באוצריא, הדיווח יופיע כאן.';
  @override
  String reportsLockedNote({required bool driveFull}) => driveFull
      ? 'הכונן מלא, ולכן אי אפשר לאסוף אליו דיווחים או לשלוח את אלה שבו. '
          'פנה בו מקום ופתח את הכלי מחדש.'
      : 'הכונן מוגן מפני כתיבה, ולכן אי אפשר לאסוף אליו דיווחים או לשלוח את '
          'אלה שבו. הזז את מתג הנעילה ופתח את הכלי מחדש.';
}

class _AppScreen extends AppScreenStrings {
  const _AppScreen();

  @override
  String get readyToInstall => 'מוכן להתקנה';

  @override
  String get installedVersion => 'גרסה מותקנת';
  @override
  String get noInstallDetected => 'לא זוהתה התקנה';
  @override
  String get pickInstallDirButton => 'בחירת מיקום ידנית';
  @override
  String get pickInstallDirDialogTitle => 'בחירת תיקיית ההתקנה של אוצריא';
  @override
  String get installAdoptedSnack => 'נמצאה התקנת אוצריא — הגרסה עודכנה';
  @override
  String get installNotFoundSnack => 'לא נמצאה התקנת אוצריא בתיקייה שנבחרה';

  @override
  String get mirrorEmpty =>
      'אין — הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית';
  @override
  String channelPair(String stable, String prerelease) =>
      '${_ltr(stable)} (יציבה) · ${_ltr(prerelease)} (ניסיונית)';

  @override
  String get channelStable => 'יציבה';
  @override
  String get channelPrerelease => 'ניסיונית';

  @override
  String get launchButton => 'פתיחת אוצריא';

  @override
  String get reinstallButton => 'התקנה מחדש';
}

class _LibraryScreen extends LibraryScreenStrings {
  const _LibraryScreen();

  @override
  String get pickDbButton => 'בחירת קובץ ספריית אוצריא';
  @override
  String get pickDbDialogTitle => 'בחירת קובץ seforim.db';
  @override
  String get dbPathUpdatedSnack => 'מיקום ספריית אוצריא עודכן';

  @override
  String get pickInstallDirButton => 'בחירת תיקייה';
  @override
  String get pickInstallDirDialogTitle =>
      'בחירת התיקייה שאליה תותקן ספריית אוצריא';
  @override
  String get installDirUpdatedSnack => 'מיקום ההתקנה עודכן';
  @override
  String get customLocationDialogTitle => 'מיקום שאוצריא אינה מחפשת בו';
  @override
  String customLocationPrompt(String dbPath) =>
      'המיקום שנבחר:\n${_ltr(dbPath)}\n\n'
      'זה אינו מיקום ברירת המחדל של אוצריא, ולכן היא לא תמצא שם את הספרים '
      'בעצמה. אחרי ההתקנה יש לפתוח את אוצריא, ובהגדרות שלה לבחור את מיקום '
      'ספריית אוצריא — התיקייה הזו. להמשיך עם המיקום הזה?';
  @override
  String get customLocationConfirm => 'המשך עם המיקום שנבחר';

  @override
  String get updatingProgress => 'מעדכן את ספריית אוצריא…';
  @override
  String get changesTitle => 'מה חדש בספריית אוצריא';
  @override
  String changesPendingSubtitle(String version) =>
      'העדכון מוסיף ומתקן ספרים עד גרסה ${_ltr(version)}.';
  @override
  String changesAppliedSubtitle(String version) =>
      'הספרים שנוספו והשתנו עד גרסה ${_ltr(version)}, שהותקנה. '
      'גרסאות אוצריא שתומכות בכך יציגו את הרשימה גם בפתיחה הבאה.';
  @override
  String changesPartial(int shown, int total) =>
      'הרשימה חלקית: יש בה $shown מתוך $total הגרסאות שבטווח.';
  @override
  String get changesButton => 'הרשימה המלאה';
  @override
  String get changesNotFound => 'רשימת השינויים לא נמצאה על הכונן.';

  @override
  String get reindexTitle => 'עדכון אינדקס החיפוש';
  @override
  String get reindexPendingSubtitle =>
      'ספריית אוצריא עודכנה מכאן, ולכן החיפוש בספרים שהשתנו עדיין מחזיר את התוכן הישן. '
      'בלחיצה אחת אוצריא תתקן את זה.';
  @override
  String get reindexButton => 'בנייה מחדש';
  @override
  String get reindexDialogTitle => 'עדכון אינדקס החיפוש';
  @override
  String get reindexDialogContent =>
      'אוצריא תיפתח, תטען את הספרייה מחדש ותעדכן את אינדקס החיפוש בספרים שהשתנו. '
      'העדכון רץ בתוך אוצריא ועשוי להימשך זמן מה, ואפשר להמשיך להשתמש בה בינתיים. '
      'לפתוח עכשיו?';
  @override
  String get reindexDialogConfirm => 'פתיחת אוצריא';
  @override
  String get reindexRequestedSnack => 'אוצריא תעדכן את אינדקס החיפוש';
  @override
  String reindexFailedSnack(String error) =>
      'לא הצלחנו למסור את הבקשה לאוצריא ($error)';

  @override
  String get fullDownloadInsteadButton => 'התקנת ספריית אוצריא המלאה';

  @override
  String get mirrorEmpty =>
      'ריקה — הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית';
  @override
  String get mirrorUnreadable => 'לא ניתן לקרוא';
  @override
  String get mirrorNotChecked =>
      'לא נבדקה: לא ניתן היה לקרוא את ספריית אוצריא במחשב';
  @override
  String mirrorHasVersion(String version) => 'מכילה גרסה ${_ltr(version)}';
  @override
  String get mirrorPresent => 'קיימת';
  @override
  String get personalVersionButton => 'רישום המחשב הזה';
  @override
  String personalVersionCapturedSnack(String version) =>
      'המחשב נרשם, בגרסה ${_ltr(version)}';
  @override
  String get personalVersionNotFoundSnack =>
      'לא נמצאה במחשב הזה ספריית אוצריא לקרוא ממנה את הגרסה';
  @override
  String get personalOtherMachineTitle => 'הכונן הוכן למחשב אחר';
  @override
  String personalOtherMachineSubtitle(String version) =>
      'ספריית אוצריא שבכונן מתאימה רק למחשב שנרשם, מגרסה ${_ltr(version)}. '
      'המחשב הזה לא נרשם, ולכן אין לו כאן עדכון של הספרייה.';
  @override
  String get personalOtherMachineSettingsButton => 'להגדרות';
  @override
  String get personalAskTitle =>
      'האם אתה מעוניין לעדכן מחשבים מרובים, או רק את המחשב שלך?';
  @override
  String get personalAskMultiple => 'מחשבים מרובים';
  @override
  String get personalAskMultipleBody =>
      'הכונן יחזיק כל מה שמחשב כלשהו עשוי לצטרך, כולל ספריית אוצריא המלאה.';
  @override
  String get personalAskMine => 'רק המחשב שלי';
  @override
  String get personalAskMineBody =>
      'יירד רק מה שחסר למחשב שלך, ולכן ההורדה קטנה בהרבה. מחשב אחר לא יתעדכן '
      'מהכונן.';
  @override
  String get personalAskLater => 'אפשר לשנות את הבחירה בכל עת בהגדרות.';
  @override
  String get personalPreparedHere => 'הכונן הוכן למחשב הזה';
  @override
  String get personalPendingNote =>
      'המחשב שבו אוצריא מותקנת ייבחר כשתפעיל את הכלי בו.';
  @override
  String get personalPendingRegisterNote =>
      'הכונן עוד לא הוכן לאף מחשב. אם זה המחשב שרוצים לעדכן מהכונן:';
  @override
  String get personalChipElsewhere => 'הוכן למחשב אחר';
  @override
  String get personalChange => 'שינוי';
  @override
  String personalCardThis(String version) =>
      'הכונן הוכן למחשב הזה, מגרסה ${_ltr(version)}.';
  @override
  String personalCardThisAndOthers(int others, String version) =>
      'הכונן הוכן למחשב הזה ולעוד ${plural(others, one: 'מחשב אחד', two: 'שני מחשבים', many: '$others מחשבים')}, '
      'מגרסה ${_ltr(version)}.';
  @override
  String personalCardOthers(int count, String version) =>
      'הכונן הוכן ל${plural(count, one: 'מחשב אחד שנרשם', two: 'שני מחשבים שנרשמו', many: '-$count מחשבים שנרשמו')}, '
      'מגרסה ${_ltr(version)}.';
  @override
  String get personalCardNone =>
      'אף מחשב עוד לא נרשם, ולכן תרד ספריית אוצריא המלאה.';
  @override
  String personalDownloadItem(int count, String version) =>
      'רק מה שחסר ${plural(count, one: 'למחשב שנרשם', two: 'לשני המחשבים שנרשמו', many: 'ל-$count המחשבים שנרשמו')}, '
      'מגרסה ${_ltr(version)}';
  @override
  String get personalDownloadItemNone =>
      'ספריית אוצריא המלאה, אף מחשב עוד לא נרשם';
  @override
  String personalDownloadNote(int count) =>
      'הכונן מוכן ל${plural(count, one: 'מחשב אחד שנרשם', two: 'שני מחשבים שנרשמו', many: '-$count מחשבים שנרשמו')}.';
}

class _Settings extends SettingsScreenStrings {
  const _Settings();

  @override
  String get title => 'הגדרות';

  @override
  String get groupGeneral => 'כללי';
  @override
  String get groupPrivacy => 'פרטיות ודיווחים';
  @override
  String get groupAbout => 'אודות';
  @override
  String get advancedSummary => 'נעילה בסיסמה, שאלות נפוצות, יומן ואיפוס';

  @override
  String get languageTitle => 'שפה';
  @override
  String get languageSystem => 'כמו במחשב';
  @override
  String languageSystemAs(String language) => 'כמו במחשב ($language)';
  @override
  String get languageHebrew => 'עברית';
  @override
  String get languageEnglish => 'English';

  @override
  String get autoCheckTitle => 'לבדוק עדכונים בכל פתיחה';
  @override
  String get autoCheckSubtitle =>
      'בודק מה יש בכונן, ובמחשב מחובר — גם מה חדש באתר.';
  @override
  String get autoInstallTitle => 'לעדכן לבד בלי לשאול';
  @override
  String get autoInstallSubtitle =>
      'כשיש בכונן עדכון למחשב הזה, הוא מותקן מיד בפתיחה. לא חל על התקנה ראשונה.';
  @override
  String get autoInstallDialogTitle => 'לעדכן לבד בלי לשאול?';
  @override
  String get autoInstallDialogContent =>
      'בכל פעם שהכלי ייפתח במחשב שיש בכונן עדכון בשבילו, העדכון יותקן מיד. '
      'אם אוצריא תהיה פתוחה, העדכון יחכה לפעם הבאה.';
  @override
  String get autoInstallDialogConfirm => 'הפעלה';

  @override
  String get syncTargetsTitle => 'מה להוריד לכונן';
  @override
  String get syncTargetsSubtitle => 'מה שלא מסומן לא יירד, גם אם יש לו עדכון.';
  @override
  String get syncTargetApp => 'תוכנת אוצריא';
  @override
  String get syncTargetLibrary => 'ספריית אוצריא';
  @override
  String get syncTargetPlugins => 'תוספים';
  @override
  String get syncLibraryLockedSubtitle =>
      'ספריית אוצריא נקבעת לפי המחשב שנרשם.';
  @override
  String get semanticDownloadTitle => 'חיפוש חכם';
  @override
  String get semanticDownloadSubtitle =>
      'הקבצים תופסים כמה ג׳יגה־בייט. כשיש הורדה:';
  @override
  String get semanticDownloadAsk => 'לשאול כל פעם';
  @override
  String get semanticDownloadAlways => 'תמיד להוריד';
  @override
  String get semanticDownloadNever => 'לא להוריד';
  @override
  String get semanticConsentRowTitle => 'חיפוש חכם במחשב הזה';
  @override
  String get semanticConsentRowOn =>
      'פועל: ההסכמה לשליחת נתוני אימון פעילה באוצריא. ביטול רק בהגדרות של '
      'אוצריא: "מערכת" ← "חיפוש חכם (ניסיוני)" ← "שיפור המנגנון".';
  @override
  String get semanticConsentRowOff =>
      'כבוי: החיפוש החכם שבכונן יותקן בעדכון הבא רק אחרי הסכמה לשליחת נתוני '
      'אימון. אוצריא צריכה להיות סגורה.';
  @override
  String get semanticConsentRowEnable => 'הפעלת החיפוש החכם';

  @override
  String get personalModeDialogTitle => 'להוריד רק מה שחסר למחשב שלך?';
  @override
  String get personalModeDialogContent =>
      'מעכשיו יירד לכונן רק מה שחסר למחשבים שנרשמו. מחשב שלא נרשם לא יתעדכן '
      'מהכונן, וספריית אוצריא המלאה שבכונן תימחק בהורדה הבאה.';
  @override
  String get personalModeDialogConfirm => 'הפעלה';
  @override
  String get personalGroupTitle => 'בשביל איזה מחשב מורידים את ספריית אוצריא';
  @override
  String get personalMachineThis => 'המחשב הזה';
  @override
  String get personalMachineUnnamed => 'מחשב שנרשם';
  @override
  String personalMachineVersion(String version) => 'גרסה ${_ltr(version)}';
  @override
  String personalMachineFloor(String version) =>
      'גרסה ${_ltr(version)} · ההורדה מתחילה ממנה, כי היא הנמוכה';
  @override
  String get personalMachineRemove => 'הסרה';
  @override
  String get personalMachinesNone =>
      'אף מחשב עוד לא נרשם. המחשב שבו אוצריא מותקנת ייבחר כשתפעיל את הכלי בו.';
  @override
  String personalMachineName(String machineName) => _ltr(machineName);
  @override
  String personalMachineThisSubtitle(String machineName, String version) =>
      '${_ltr(machineName)} · גרסה ${_ltr(version)}';
  @override
  String get personalMachineNotHere => 'המחשב הזה לא נרשם';
  @override
  String get personalMachinesReadOnly =>
      'הכונן מוגן מפני כתיבה, ולכן אי אפשר לשנות בו את רשימת המחשבים.';
  @override
  String get personalRemoveTitle => 'להסיר את המחשב מהרשימה?';
  @override
  String get personalRemoveBody =>
      'ההורדה הבאה כבר לא תביא את מה שחסר לו. אפשר לרשום אותו שוב בכל עת.';
  @override
  String get personalRemoveThisBody =>
      'המחשב הזה לא יתעדכן עוד מהכונן, עד שיירשם שוב.';

  @override
  String get faqEditTitle => 'עריכת השאלות הנפוצות';
  @override
  String get faqEditSubtitle => 'הסתרה, הוספת שאלות ופרטי איש קשר לעזרה במקום';

  @override
  String get logTitle => 'יומן הפעולות';
  @override
  String get logSubtitle => 'לשליחה לתמיכה כשמשהו לא עובד.';
  @override
  String get openLogFolderButton => 'פתיחת התיקייה';

  @override
  String get resetTitle => 'איפוס הגדרות';
  @override
  String get resetSubtitle => 'מחזיר את כל ההגדרות לברירת המחדל. הסיסמה נשארת.';
  @override
  String get resetButton => 'איפוס';
  @override
  String get resetDialogTitle => 'לאפס את כל ההגדרות?';
  @override
  String get resetDialogContent =>
      'כל ההגדרות יחזרו לברירת המחדל. מה שבכונן לא נמחק, והסיסמה נשארת.';
  @override
  String get resetDialogConfirm => 'איפוס ההגדרות';
  @override
  String get resetDoneSnack => 'ההגדרות אופסו';

  @override
  String aboutTitle(String version) => 'עדכוני אוצריא ${_ltr(version)}';
  @override
  String get aboutSubtitle => 'בדיקה אם יש גרסה חדשה';
  @override
  String aboutNewVersion(String version) =>
      'יש גרסה חדשה: ${_ltr(version)} · מה חדש ועדכון';
}

class _SaferMode extends SaferModeStrings {
  const _SaferMode();

  @override
  String get lockTitle => 'נעילה בסיסמה';
  @override
  String get noPasswordSubtitle =>
      'מונעת שינוי הגדרות, בחירת גרסה ניסיונית ועריכת השאלות הנפוצות בלי סיסמה.';
  @override
  String get setPasswordButton => 'קביעת סיסמה';
  @override
  String get lockOnSubtitle => 'פעילה: הכניסה להגדרות תבקש סיסמה.';
  @override
  String get lockOffSubtitle => 'יש סיסמה, אבל הנעילה כבויה.';
  @override
  String get passwordRowTitle => 'הסיסמה';
  @override
  String get passwordRowSubtitle => 'אפשר להחליף או למחוק.';
  @override
  String get passwordRowLockedSubtitle => 'כדי למחוק אותה, כבה קודם את הנעילה.';
  @override
  String get changeButton => 'החלפה';
  @override
  String get clearButton => 'מחיקה';
  @override
  String get enabledSnack => 'הנעילה הופעלה';
  @override
  String get disabledSnack => 'הנעילה כובתה';

  @override
  String get verifyTitle => 'נדרשת סיסמה';
  @override
  String get verifySettingsHint => 'ההגדרות נעולות בסיסמה.';
  @override
  String get verifyFaqHint => 'עריכת השאלות הנפוצות נעולה בסיסמה.';
  @override
  String get verifyEnableHint => 'כדי להפעיל את הנעילה, הקלד את הסיסמה.';
  @override
  String get verifyDisableHint => 'כדי לכבות את הנעילה, הקלד את הסיסמה.';
  @override
  String get enterButton => 'כניסה';
  @override
  String get passwordLabel => 'סיסמה';
  @override
  String get wrongPassword => 'הסיסמה לא נכונה. נסה שוב.';
  @override
  String get passwordRequired => 'יש להקליד סיסמה.';
  @override
  String get showPasswordTooltip => 'הצגת הסיסמה';
  @override
  String get hidePasswordTooltip => 'הסתרת הסיסמה';

  @override
  String get setTitle => 'קביעת סיסמה';
  @override
  String setIntro(int minLength, {bool onThisComputer = false}) =>
      'הסיסמה תידרש לכניסה להגדרות, לבחירת גרסה ניסיונית ולעריכת השאלות '
      'הנפוצות. לפחות $minLength תווים. סיסמה שנשכחה אי אפשר לשחזר — רק '
      'למחוק את קובץ ההגדרות ${onThisComputer ? 'שבמחשב הזה' : 'שבכונן'}.';
  @override
  String get setConfirm => 'שמירה והפעלת הנעילה';
  @override
  String get changeTitle => 'החלפת סיסמה';
  @override
  String get currentPasswordLabel => 'הסיסמה הנוכחית';
  @override
  String get newPasswordLabel => 'סיסמה חדשה';
  @override
  String get confirmPasswordLabel => 'הסיסמה החדשה שוב';
  @override
  String passwordTooShort(int minLength) =>
      'הסיסמה קצרה מדי: לפחות $minLength תווים.';
  @override
  String get passwordsDoNotMatch => 'שתי הסיסמאות לא זהות.';
  @override
  String get passwordSetSnack => 'הסיסמה נקבעה והנעילה פעילה';
  @override
  String get passwordChangedSnack => 'הסיסמה הוחלפה';

  @override
  String get clearDialogTitle => 'למחוק את הסיסמה?';
  @override
  String get clearDialogContent =>
      'בלי סיסמה, כל מי שפותח את הכלי יוכל לשנות הגדרות.';
  @override
  String get passwordRemovedSnack => 'הסיסמה נמחקה';
}

class _Plugins extends PluginsStrings {
  const _Plugins();

  @override
  String get syncFailedSnack => 'העדכון מהאתר נכשל';
  @override
  String syncDoneSnack(int fetched, int total) => fetched == 0
      ? 'רשימת התוספים עודכנה — לא היה חדש ($total תוספים)'
      : 'רשימת התוספים עודכנה — ירדו $fetched מתוך $total';
  @override
  String syncDoneWithWarningsSnack(int count) =>
      'הרשימה עודכנה, אבל $count פריטים לא ירדו. הפרטים ביומן.';
  @override
  String get syncingOverlayStarting => 'מתחיל…';
  @override
  String get syncDirUnknownTooltip => 'התיקייה תיקבע בעדכון הראשון מהאתר';

  @override
  String get saveDialogTitle => 'שמירת התוסף';
  @override
  String get saveDoneSnack => 'הקובץ נשמר';
  @override
  String get saveFailedSnack => 'שמירת הקובץ נכשלה';
  @override
  String installDoneSnack(String pluginName) =>
      'התוסף $pluginName הותקן בהצלחה';
  @override
  String installCancelledSnack(String pluginName) =>
      'התקנת $pluginName בוטלה באוצריא';
  @override
  String installRejectedSnack(String pluginName, String? reason) =>
      'אוצריא לא התקינה את $pluginName${reason == null ? '' : ': $reason'}';
  @override
  String get installFailedSnack => 'ההתקנה נכשלה';

  @override
  String get loadingCatalog => 'טוען את רשימת התוספים…';

  @override
  String get noResultsTitle => 'לא נמצאו תוספים לפי הסינון שבחרת';
  @override
  String get noResultsBody => 'נסה מילה אחרת, או חפש בכל הקטגוריות.';

  @override
  String get filterStatusLabel => 'יציבות';
  @override
  String get filterSortLabel => 'מיון';
  @override
  String get sortRecommended => 'מומלצים';
  @override
  String get sortNewest => 'החדשים ביותר';
  @override
  String get sortUpdated => 'עודכנו לאחרונה';
  @override
  String get filterTagsLabel => 'תגיות';
  @override
  String get showMoreTags => 'הצג עוד';
  @override
  String get showFewerTags => 'הצג פחות';

  @override
  String pluginVersionBadge(String version) => 'גרסה ${_ltr(version)}';

  @override
  String ratingBadge(String average, int count) => '$average ($count)';
  @override
  String ratingTooltip(int count) => 'דירוג ממוצע מתוך $count מדרגים';
  @override
  String get ratingPanelTitle => 'דירוג המשתמשים';
  @override
  String ratingCountLabel(int count) =>
      count == 1 ? '$count מדרג' : '$count מדרגים';
  @override
  String ratingVerifiedLabel(int count) => '$count התקינו בפועל';
  @override
  String get ratingVerifiedTooltip => 'מדרגים שהתקנת התוסף אצלם נרשמה בפועל';
  @override
  String get ratingEmpty => 'התוסף עדיין לא דורג';
  @override
  String ratingStarsLabel(String average) => 'דירוג $average מתוך 5';
  @override
  String get sourcePageButton => 'עמוד המקור';

  @override
  String get statusStable => 'יציב';
  @override
  String get statusExperimental => 'ניסיוני';
  @override
  String get statusUnknown => 'לא ידוע';

  @override
  String get infoPanelTitle => 'מידע כללי';
  @override
  String get tagsPanelTitle => 'קטגוריות ותגיות';
  @override
  String get screenshotsPanelTitle => 'צילומי מסך';
  @override
  String get infoVersion => 'גרסה';
  @override
  String get infoStatus => 'יציבות';
  @override
  String get infoAuthor => 'מפתח';
  @override
  String get infoUpdated => 'עודכן';
  @override
  String get infoNetwork => 'חיבור אינטרנט';
  @override
  String get infoNetworkRequired => 'נדרש';
  @override
  String get infoNetworkNotRequired => 'לא נדרש';
  @override
  String get valueUnspecifiedMasculine => 'לא צוין';

  @override
  String get screenshotPrevious => 'הקודם';
  @override
  String get screenshotNext => 'הבא';

  @override
  String get storeAppButton => 'העתקת החנות למחשב';
  @override
  String get storeAppDialogTitle => 'חנות התוספים כתוכנה למחשב';
  @override
  String get storeAppDialogBody =>
      'תוכנה נפרדת למחשבי Windows, שכל התוספים שבכונן ייארזו לתוכה. אפשר '
      'להעתיק אותה לכונן נייד, לעיין בתוספים ולהתקין אותם ישירות לאוצריא — '
      'גם במחשב שאין בו חיבור לאינטרנט.';
  @override
  String get storeAppHighlightBundled => 'כל התוספים שבכונן ייארזו בפנים';
  @override
  String get storeAppHighlightOffline => 'עובדת גם בלי חיבור לאינטרנט';
  @override
  String get storeAppHighlightDirect => 'מתקינה ישירות לתוך אוצריא';
  @override
  String get storeAppChipWindows => 'מיועדת ל-Windows';
  @override
  String storeAppChipSize(String size) => 'גודל $size';
  @override
  String storeAppChipUpdated(String date) => 'עודכנה ב-$date';
  @override
  String get storeAppChooseFolder => 'בחירת תיקייה…';
  @override
  String get storeAppUnavailableTooltip =>
      'תוכנת החנות עדיין לא בכונן. הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית.';
  @override
  String get storeAppNoPluginsTooltip =>
      'אין תוספים בכונן. הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית.';
  @override
  String get storeAppPickFolderTitle => 'לאן להעתיק את חנות התוספים?';
  @override
  String get storeAppOverwriteTitle => 'כבר יש כאן חנות';
  @override
  String storeAppOverwriteContent(String path) =>
      'בתיקייה ${_ltr(path)} כבר יש חנות תוספים. העדכון יחליף את קובץ התוכנה ואת '
      'התוספים, ולא ייגע בשאר מה שיש שם.';
  @override
  String get storeAppOverwriteConfirm => 'עדכון';
  @override
  String get storeAppUpdateButton => 'עדכון החנות';
  @override
  String get storeAppUpdateHereTitle => 'עדכון חנות התוספים';
  @override
  String storeAppUpdateHereContent(String path) =>
      'החנות שהועתקה אל ${_ltr(path)} אינה מעודכנת. לעדכן אותה שם?';
  @override
  String get storeAppChooseOtherFolder => 'בחירת תיקייה אחרת';
  @override
  String get storeAppInUseSnack => 'החנות פתוחה כרגע. סגור אותה ונסה שוב.';
  @override
  String get storeAppCopyingTitle => 'מעתיק את חנות התוספים';
  @override
  String get storeAppDoneTitle => 'החנות הועתקה';
  @override
  String storeAppDoneContent(int plugins, String size) =>
      'החנות הועתקה עם $plugins תוספים ($size).';
  @override
  String storeAppDoneSkipped(int count) =>
      'ל-$count תוספים חסר קובץ בכונן והם הושמטו.';
  @override
  String get storeAppOpenFolder => 'פתיחת התיקייה';
  @override
  String get storeAppLaunch => 'הפעלת החנות';
  @override
  String storeAppFailedSnack(String error) => 'ההעתקה נכשלה: $error';
  @override
  String storeAppLaunchFailedSnack(String error) => 'הפעלת החנות נכשלה: $error';

  @override
  String get storeTitle => 'תוספים';
  @override
  String get storeSubtitle =>
      'תוספים שמרחיבים את אוצריא. כל מה שכאן כבר בכונן, ומותקן גם בלי אינטרנט.';
  @override
  String asOfDate(String date) => 'נכון ל-$date.';
  @override
  String get refreshButton => 'רענון';
  @override
  String get syncingTitle => 'מעדכן את רשימת התוספים מהאתר';
  @override
  String get syncingHint =>
      'יורדים רק תוספים חדשים ומעודכנים. אפשר להמשיך לעיין בינתיים.';
  @override
  String get syncStopButton => 'עצירה';
  @override
  String get syncStoppedSnack => 'העדכון נעצר. מה שכבר ירד נשמר בכונן.';
  @override
  String get emptyTitle => 'עוד אין תוספים בכונן';
  @override
  String get emptyBodyOnline =>
      'תוספים יורדים לכונן יחד עם עדכוני אוצריא. "רענון" מוריד אותם עכשיו.';
  @override
  String get emptyBodyOffline =>
      'תוספים יורדים לכונן יחד עם עדכוני אוצריא. במחשב עם אינטרנט לחץ "הורדת הכול לכונן" בדף הבית, והם יופיעו כאן.';
  @override
  String get searchHint => 'חפש תוסף לפי שם או נושא';
  @override
  String get clearSearchTooltip => 'ניקוי';
  @override
  String get filterAll => 'הכול';
  @override
  String get filterInstalled => 'מותקנים';
  @override
  String get filterNotInstalled => 'לא מותקנים';
  @override
  String get moreFilters => 'עוד סינון';
  @override
  String moreFiltersCount(int count) => 'עוד סינון ($count)';
  @override
  String noResultsForQuery(String query) => 'לא נמצאו תוספים ל"$query"';
  @override
  String get clearFiltersButton => 'ניקוי החיפוש והסינון';
  @override
  String updatesAvailable(int count) =>
      plural(count, one: 'עדכון זמין', many: '$count עדכונים זמינים');
  @override
  String updatesBarNames(String names) =>
      '$names · יישלחו לאוצריא, ושם מאשרים כל אחד';
  @override
  String joinNames(List<String> names) => names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} ו${names.last}';
  @override
  String get updateAllButton => 'עדכון הכול';
  @override
  String updatingAllLabel(int current, int total) =>
      'שולח לאוצריא $current מתוך $total…';
  @override
  String updatesSentSnack(int count) => plural(count,
      one: 'העדכון נשלח לאוצריא — אשר שם',
      many: '$count עדכונים נשלחו לאוצריא — אשר שם');
  @override
  String updateAllNoneSentSnack(String names) => 'לא נשלחו לאוצריא: $names';
  @override
  String updateAllPartlySentSnack(int sent, String names) => plural(sent,
      one: 'עדכון אחד נשלח לאוצריא — אשר שם. לא נשלחו: $names',
      many: '$sent עדכונים נשלחו לאוצריא — אשר שם. לא נשלחו: $names');
  @override
  String updateAllStoppedSnack(int sent) => plural(sent,
      one: 'העדכון נעצר. עדכון אחד נשלח לאוצריא — אשר שם',
      many: 'העדכון נעצר. $sent עדכונים נשלחו לאוצריא — אשר שם');
  @override
  String get updateAllStoppedNoneSnack => 'העדכון נעצר. לא נשלח דבר לאוצריא.';
  @override
  String get updateAllStoppedPrefix => 'העדכון נעצר.';
  @override
  String get updateAllStoppingLabel => 'עוצר אחרי התוסף הנוכחי…';
  @override
  String get actionsBlockedSyncing =>
      'בזמן העדכון מהאתר אי אפשר להתקין או לשמור תוספים.';
  @override
  String get actionsBlockedExporting =>
      'בזמן העתקת החנות אי אפשר להתקין או לשמור תוספים.';
  @override
  String get actionsBlockedUpdatingAll =>
      'בזמן "עדכון הכול" אי אפשר להתקין או לשמור תוספים אחרים.';
  @override
  String get actionsBlockedElsewhere =>
      'משימה אחרת רצה עכשיו. בינתיים אי אפשר להתקין או לשמור תוספים.';
  @override
  String get howItWorksButton => 'איך זה עובד?';
  @override
  String get updatesSentTitle => 'העדכונים נשלחו לאוצריא — אשר שם';
  @override
  String get updatesSentBody =>
      'הרשימה כאן מתעדכנת מעצמה ברגע שההתקנה מסתיימת באוצריא.';
  @override
  String installSentSnack(String pluginName) =>
      '$pluginName נשלח לאוצריא — אשר שם';
  @override
  String get newChip => 'חדש';
  @override
  String get networkChip => 'דורש אינטרנט';
  @override
  String get installInOtzariaButton => 'התקנה באוצריא';
  @override
  String updateToButton(String version) => 'עדכון ל-${_ltr(version)}';
  @override
  String get saveFileButton => 'שמירת קובץ התוסף…';
  @override
  String get sendingLabel => 'שולח לאוצריא…';
  @override
  String get sentLabel => 'נשלח לאוצריא — אשר שם';
  @override
  String get developmentLabel => 'בפיתוח במחשב הזה';
  @override
  String get incompatibleLabel => 'לא מתאים לאוצריא שלך';
  @override
  String get disabledLabel => 'מושבת באוצריא';
  @override
  String get installedLabel => 'מותקן';
  @override
  String get noteIncompatible => 'אין גרסה שמתאימה לאוצריא שבמחשב הזה';
  @override
  String noteNeedsApp(String version) => 'צריך אוצריא ${_ltr(version)} ומעלה';
  @override
  String get noteNeedsOtzaria => 'קודם מתקינים את אוצריא';
  @override
  String get noteSaveOnly => 'אין התקנה ישירה — שומרים את הקובץ';
  @override
  String get noteDisabled => 'מושבת באוצריא';
  @override
  String get noteFileMissing =>
      'הקובץ עוד לא בכונן — יירד בהתקנה (צריך אינטרנט)';
  @override
  String get noteFileMissingOnline => 'הקובץ עוד לא בכונן — יירד עכשיו מהאתר';
  @override
  String get fileNotOnDriveLabel => 'הקובץ לא ירד לכונן';
  @override
  String get noteNextDriveDownload => 'יירד בהורדה הבאה לכונן';
  @override
  String get incompatibleTitle => 'התוסף לא מתאים לאוצריא שבמחשב הזה';
  @override
  String incompatibleBodyVersions(String needs, String here) =>
      'הוא צריך אוצריא ${_ltr(needs)} ומעלה, ובמחשב הזה מותקנת ${_ltr(here)}. אחרי שתעדכן את אוצריא אפשר יהיה להתקין אותו.';
  @override
  String get incompatibleBody =>
      'אין לו גרסה שמתאימה לאוצריא שבמחשב הזה. אחרי שתעדכן את אוצריא אפשר יהיה להתקין אותו.';
  @override
  String get disabledTitle => 'התוסף מושבת באוצריא';
  @override
  String get disabledBody =>
      'הוא מותקן אבל לא פעיל. אפשר להפעיל אותו מחדש בהגדרות התוספים של אוצריא.';
  @override
  String get disabledUpdateBody => 'העדכון יותקן גם כשהוא מושבת.';
  @override
  String get developmentTitle => 'תוסף בפיתוח';
  @override
  String get developmentBody =>
      'אוצריא טוענת אותו מהתיקייה שלו במחשב הזה, ולכן הכלי לא מעדכן אותו.';
  @override
  String get fileMissingTitle => 'הקובץ של התוסף עוד לא ירד לכונן';
  @override
  String get fileMissingBody =>
      'הוא יירד בפעם הבאה שתוריד עדכונים לכונן במחשב עם אינטרנט. במחשב מחובר ההתקנה מורידה אותו עכשיו.';
  @override
  String get factRating => 'דירוג';
  @override
  String get factCompatible => 'מתאים לאוצריא שלך';
  @override
  String get factYes => 'כן';
  @override
  String get factNo => 'לא';
  @override
  String factOtzariaVersion(String version) => 'אוצריא ${_ltr(version)}';
  @override
  String get factVersionLatest => 'העדכנית';
  @override
  String get factVersionInstalled => 'מותקנת אצלך';
  @override
  String factVersionInstalledAt(String version) =>
      'מותקנת אצלך ${_ltr(version)}';
  @override
  String get factNetworkAny => 'עובד בכל מחשב';
  @override
  String get factNetworkSome => 'לחלק מהיכולות';
  @override
  String get factSize => 'גודל';
  @override
  String get factOnDrive => 'בכונן';
  @override
  String get factNotOnDrive => 'לא בכונן';
  @override
  String get descriptionTitle => 'תיאור';
  @override
  String get versionsTitle => 'גרסאות';
  @override
  String get versionLatestTag => 'העדכנית';
  @override
  String get versionInstalledTag => 'מותקנת אצלך';
  @override
  String get infoDownloads => 'הורדות';
  @override
  String get infoSource => 'מקור';
  @override
  String get copyAddressTooltip => 'העתקת הכתובת';
  @override
  String get addressCopiedSnack => 'הכתובת הועתקה';
  @override
  String get ratingSourceNote => 'מדרגים באתר אוצריא.';
  @override
  String ratingAsOfNote(String date) =>
      'נכון ל-$date, היום שבו הורדת לכונן. מדרגים באתר אוצריא.';
  @override
  String get screenshotZoom => 'הגדלת צילום המסך';
  @override
  String screenshotNumber(int index, int total) => 'צילום $index מתוך $total';
  @override
  String get advancedSummary => 'העתקת חנות התוספים למחשב';
  @override
  String get storeAppCopyButton => 'העתקה…';
  @override
  String get storeAppRowBody =>
      'תוכנה קטנה שמציגה את התוספים שבכונן ומתקינה אותם גם בלי הכונן (Windows).';
  @override
  String get reloadRowTitle => 'טעינה מחדש מהכונן';
  @override
  String get reloadButton => 'טעינה מחדש';
}

class _Faq extends FaqStrings {
  const _Faq();

  @override
  String get title => 'שאלות נפוצות';
  @override
  String get intro => 'תשובות קצרות לשאלות שחוזרות על עצמן.';

  @override
  String get groupBasics => 'איך זה עובד';
  @override
  String get groupDownload => 'הורדה והתקנה';
  @override
  String get groupLibrary => 'הספרים לא נמצאים';
  @override
  String get groupExtras => 'תוספים ותוכנות נוספות';
  @override
  String get groupGeneral => 'שאלות כלליות';

  @override
  String get qWhatIsThis => 'מה עושים עם התוכנה הזאת?';
  @override
  String get aWhatIsThis =>
      'בפתיחת התוכנה יופיעו במרכז המסך אריחים, ביניהם תוכנת אוצריא וספריית אוצריא. '
      'כשיש בכונן עדכון, יופיע על האריח הכיתוב "יש עדכון בכונן". מעדכנים קודם '
      'את התוכנה, ורק אחר כך את ספריית אוצריא.';
  @override
  String get qOfflineFlow => 'המחשב שלי אינו מחובר לאינטרנט — איך אעדכן אותו?';
  @override
  String get aOfflineFlow =>
      'בשביל זה התוכנה נבנתה. מעתיקים את תיקיית התוכנה כולה לכונן נייד '
      '(דיסק און קי), מחברים אותו למחשב שיש בו אינטרנט, פותחים את התוכנה '
      'ולוחצים "הורדת הכול לכונן" — היא אוספת את כל העדכונים אל אותה תיקייה שעל הכונן. '
      'אחר כך מוציאים את הכונן, מחברים אותו למחשב שלך, פותחים את התוכנה '
      'משם ומתקינים. בשלב הזה אין צורך באינטרנט כלל.';
  @override
  String get qNoOtzariaYet => 'אין לי אוצריא במחשב בכלל — התוכנה מתאימה לי?';
  @override
  String get aNoOtzariaYet =>
      'בהחלט. בלחיצה על התקנה תופיע האפשרות לבחור בחבילת ההתקנה המלאה, וזו '
      'האפשרות המומלצת: היא מביאה בפעולה אחת גם את התוכנה וגם את הספרים. '
      'התקנה רגילה במחשב שאין בו אוצריא עלולה לגרום לשיבושים בשימוש. שים לב '
      'שהחבילה המלאה גדולה (כ-\u20662 GB\u2069) ולכן אינה יורדת מעצמה — יש לסמן אותה '
      'בהגדרות לפני ההורדה.';

  @override
  String get qDownloadStopped => 'ההורדה נעצרה באמצע — צריך להתחיל מהתחלה?';
  @override
  String get aDownloadStopped =>
      'לא. ההורדה זוכרת מה הספיקה להביא, ולחיצה נוספת על "הורדת הכול לכונן" ממשיכה '
      'מאותה נקודה. גם ביטול ההורדה שומר את מה שכבר ירד עד הסוף ואת מה שירד '
      'בהורדות קודמות — הוא מוחק רק את החלק שהיה באמצע.';
  @override
  String get qDownloadTooBig =>
      'ההורדה גדולה מאוד, ואני רק רוצה לעדכן את ספריית אוצריא שיש לי';
  @override
  String get aDownloadTooBig =>
      'בהגדרות, בקבוצה "בשביל איזה מחשב מורידים את ספריית אוצריא", בחר "רק '
      'המחשב שלי". מעכשיו מורידים רק את ההשלמות מהגרסה שיש אצלך ומעלה, במקום את '
      'ספריית אוצריא המלאה — נפח קטן בהרבה. המחשב שלך נרשם מעצמו בפעם הראשונה '
      'שהכלי נפתח בו. חשוב לדעת: כונן כזה אינו יכול לשמש להתקנה במחשב שאין בו '
      'אוצריא, ולכן מי שמעדכן כמה מחשבים יבחר "מחשבים מרובים".';
  @override
  String get qOtzariaOpen => 'כתוב שאוצריא פתוחה ואי אפשר לעדכן';
  @override
  String get aOtzariaOpen =>
      'העדכון מחליף קבצים שאוצריא משתמשת בהם, ולכן יש לסגור אותה קודם. '
      'סוגרים את אוצריא לגמרי, והתוכנה תבחין בזה מעצמה בתוך כמה שניות, '
      'והכפתורים יחזרו לפעול.';
  @override
  String get qBrokenAfterUpdate => 'עדכנתי, והכול יצא משובש או שאינו עובד';
  @override
  String get aBrokenAfterUpdate =>
      'אוצריא היא תוכנה בפיתוח, ולפעמים המעבר מגרסה לגרסה משאיר קבצים שאינם '
      'תואמים. במקרה כזה: להסיר את אוצריא, למחוק כל תיקייה בשם אוצריא או '
      'otzaria (מומלץ לחפש את השם במחשב), ואז להתקין מחדש את החבילה המלאה.';

  @override
  String get qAppNotDetected => 'אוצריא מותקנת אצלי, אבל התוכנה אינה מזהה אותה';
  @override
  String get aAppNotDetected =>
      'אם בחרת בשעת ההתקנה מקום אחר מברירת המחדל, התוכנה אינה מוצאת אותה '
      'לבד. הפתרון פשוט: להפעיל את אוצריא בזמן שתוכנת העדכונים פתוחה — היא '
      'תזהה אותה מעצמה, ומאותו רגע תזכור את המקום.';
  @override
  String get qDbNotFound => 'כתוב שספריית אוצריא לא נמצאה, אבל היא קיימת אצלי';
  @override
  String get aDbNotFound =>
      'גם הספרייה אינה מזוהה כשהיא יושבת במקום שאינו ברירת המחדל. בדף '
      '"ספריית אוצריא", תחת "מתקדם", בוחרים את המקום ידנית. אם אינך יודע איפה היא, אוצריא '
      'עצמה תגיד לך: היכנס אליה להגדרות, ושם בלשונית "ספרייה" לחץ על '
      '"העתק נתיב".';
  @override
  String get qStillNotFound =>
      'בחרתי את המקום ידנית, והוא עדיין אינו מוצא כלום';
  @override
  String get aStillNotFound =>
      'ככל הנראה יש לך גרסת אוצריא ישנה מאוד (0.9.74 ומטה). מאז עברה אוצריא '
      'לשיטת אחסון ספרים חדשה, שהתוכנה הזאת אינה יודעת לעדכן. מומלץ להסיר את '
      'אוצריא ולהתקין מחדש את החבילה המלאה.';
  @override
  String get qSearchMissesNewBooks =>
      'עדכנתי את ספריית אוצריא, אבל החיפוש באוצריא אינו מוצא את הספרים החדשים';
  @override
  String get aSearchMissesNewBooks =>
      'החיפוש באוצריא נעזר באינדקס חיפוש שנבנה מראש, והאינדקס אינו מתעדכן מעצמו אחרי '
      'שהספרים הוחלפו. מיד לאחר עדכון של ספריית אוצריא, התוכנה מציעה לבקש מאוצריא לעדכן '
      'את אינדקס החיפוש — כדאי לאשר. מי שדחה את ההצעה יקבל אותה שוב בהפעלה '
      'הבאה של אוצריא.';

  @override
  String get qWhatArePlugins => 'מה זו לשונית "תוספים"?';
  @override
  String get aWhatArePlugins =>
      'תוספים הם תוכנות עזר לאוצריא. אפשר להתקין אותם ישירות מכאן, או ללחוץ '
      'על "שמירת קובץ התוסף…" ואז להתקין אותם בכל מחשב שיש בו אוצריא, בלחיצה כפולה על '
      'הקובץ.';
  @override
  String get qWhatAreCustomApps => 'מה זה "תוכנות נוספות"?';
  @override
  String get aWhatAreCustomApps =>
      'מקום להוסיף תוכנות עזר שאינן אוצריא — כאלה שמסייעות בלימוד. '
      'ממלאים פעם אחת מאיפה להביא את התוכנה, והכונן נושא אותה ומתקין אותה גם '
      'במחשב שאין בו אינטרנט.';

  @override
  String get qWrongFolder => 'נפתחה הודעה שהתוכנה נמצאת במקום שאינו מתאים';
  @override
  String get aWrongFolder =>
      'התוכנה שומרת כל מה שהיא מורידה בתיקייה שצמודה אליה, כדי שהכול ייסע '
      'יחד על הכונן. אם היא הועברה למקום שאין בו הרשאת כתיבה — למשל '
      'Program Files — אין לה לאן לשמור, והיא נעצרת במקום להשאיר את הקבצים '
      'במחשב הלא נכון. הפתרון: להעביר את תיקיית התוכנה כולה לדיסק און קי או '
      'לכונן חיצוני, ולהפעיל אותה משם.';
  @override
  String get qLauncherSelfUpdate => 'והתוכנה הזאת עצמה מתעדכנת?';
  @override
  String get aLauncherSelfUpdate =>
      'כן. כשיש לה גרסה חדשה היא מציעה להוריד אותה במחשב שיש בו אינטרנט, ואז '
      'מחליפה את עצמה ונפתחת מחדש. ההגדרות, הספרים והתוספים שכבר על הכונן '
      'נשארים כמו שהם. אם ההחלפה נקטעה (למשל בכיבוי המחשב) והקובץ של התוכנה '
      'נעלם, יש להפעיל את ‎.launcher-previous.exe שלצידו — הוא משחזר את '
      'הגרסה הקודמת בשמה הרגיל.';
  @override
  String get qFree => 'הכול באמת בחינם?';
  @override
  String get aFree =>
      'כן. אוצריא נבנתה בידי אנשים ששמו לעצמם למטרה להרבות תורה בישראל, ולכן '
      'הם מנגישים אותה בחינם לכל דורש.';
  @override
  String get qNoExpenses => 'בכל זאת, איך זה יכול להיות — אין להם הוצאות?';
  @override
  String get aNoExpenses =>
      'הוצאות הפיתוח אדירות. המפתחים עצמם אינם מקבלים כל תמורה, אבל הפיתוח '
      'עצמו עולה כסף רב. מי שמעוניין להיות שותף לדבר הגדול הזה יכול לתרום '
      'בנדרים פלוס: נכנסים ל"קופות נוספות", משם ל"צרכי רבים־קרנות", ושם '
      'בוחרים "אוצריא".';

  @override
  String get contactTitle => 'לעזרה במקום';

  @override
  String get contactLead => 'לעזרה במקום:';

  @override
  String get editButton => 'עריכה';
  @override
  String get editDoneButton => 'סיום עריכה';
  @override
  String get editTitle => 'עריכת השאלות הנפוצות';
  @override
  String get editIntro => 'שאלות מוסתרות לא יוצגו. השינויים נשמרים בכונן.';
  @override
  String get editIntroThisComputer =>
      'שאלות מוסתרות לא יוצגו. השינויים נשמרים במחשב הזה.';

  @override
  String get hideTooltip => 'הסתרה';
  @override
  String get restoreTooltip => 'הצגה';
  @override
  String get hiddenLabel => 'מוסתרת';

  @override
  String get myQuestionsTitle => 'השאלות שהוספתי';
  @override
  String get noExtrasYet => 'עדיין לא הוספת שאלות.';
  @override
  String get addQuestionButton => 'הוספת שאלה';
  @override
  String get editQuestionTooltip => 'עריכת השאלה';
  @override
  String get deleteQuestionTooltip => 'מחיקת השאלה';

  @override
  String get formAddTitle => 'שאלה חדשה';
  @override
  String get formEditTitle => 'עריכת שאלה';
  @override
  String get formQuestionLabel => 'השאלה';
  @override
  String get formAnswerLabel => 'התשובה';
  @override
  String get formSave => 'שמירה';
  @override
  String get formIncompleteSnack => 'יש למלא גם שאלה וגם תשובה.';

  @override
  String get deleteConfirmTitle => 'למחוק את השאלה?';
  @override
  String get deleteConfirmContent =>
      'השאלה והתשובה יימחקו מהשאלות הנפוצות. אפשר להוסיף אותן שוב בכל עת.';

  @override
  String get contactAutoSaveNote => 'נשמר מעצמו.';
  @override
  String get contactNameLabel => 'שם איש הקשר';
  @override
  String get contactPhoneLabel => 'טלפון';
}

class _SetupError extends SetupErrorStrings {
  const _SetupError();

  @override
  String get title => 'התוכנה נמצאת במקום שאינו מתאים';
  @override
  String get explanation =>
      'התוכנה שומרת את כל הנתונים — ספריית אוצריא, התוספים וגרסת אוצריא — בתיקייה '
      'שצמודה לה, כדי שהכול יישמר יחד בכונן. התיקייה הנוכחית חסומה לכתיבה '
      '(בגלל הרשאות, או כי הכונן מוגן מפני כתיבה), ועדיין אין בה עדכונים '
      'שאפשר להתקין מהם, ולכן אין לאן לשמור.';
  @override
  String get whatToDo =>
      'מה לעשות: אם הכונן עצמו מוגן מפני כתיבה (מתג נעילה על הכונן, כונן '
      'צריבה, או הרשאות לקריאה בלבד) — לשחרר את ההגנה, להוריד את העדכונים, '
      'ואז אפשר לנעול אותו שוב ולהתקין ממנו בכל מחשב. אחרת — להעביר את '
      'תיקיית התוכנה כולה לדיסק און קי או לכונן חיצוני, ולהפעיל אותה '
      'משם.';
  @override
  String get attemptedDirTitle => 'התיקייה שנוסתה';
  @override
  String cannotWriteToDataDir(String osMessage) =>
      'לא ניתן לכתוב לתיקייה שלצד התוכנה: $osMessage';
  @override
  String get driveFull =>
      'הכונן מלא — אין בו מקום אפילו לקובץ בדיקה קטן. יש לפנות מקום בכונן '
      'ולהפעיל את התוכנה שוב.';
  @override
  String get driveFullTitle => 'אין מקום פנוי בכונן';
  @override
  String get appTranslocated =>
      'macOS מריץ את התוכנה מעותק זמני לקריאה בלבד, כי היא סומנה כהורדה '
      'מהאינטרנט, ולכן היא לא רואה את התיקייה שלצידה. יש להעביר ב-Finder את '
      'התוכנה לתיקייה אחרת ובחזרה, או להריץ במסוף: '
      'xattr -dr com.apple.quarantine ולגרור אחריו את התוכנה — ואז לפתוח '
      'אותה שוב.';
  @override
  String get appTranslocatedTitle => 'macOS מריץ את התוכנה מעותק זמני';
  @override
  String get runningFromTemp =>
      'התוכנה הופעלה מתוך קובץ ZIP או מתיקייה זמנית, וכל מה שהיא תוריד משם '
      'יימחק יחד עם התיקייה הזמנית. יש לחלץ את הקובץ לדיסק און קי או לכונן '
      'חיצוני ולהפעיל אותו משם.';
  @override
  String get runningFromTempTitle => 'יש לחלץ את הקובץ לכונן לפני ההפעלה';
  @override
  String get systemDrive =>
      'התוכנה נושאת את העדכונים ממחשב למחשב, ולכן היא צריכה להימצא על דיסק '
      'און קי או על כונן חיצוני — לא על הכונן הראשי של המחשב. יש להעתיק את '
      'כל תיקיית התוכנה (כולל התיקייה app-files) לכונן הנייד ולהפעיל אותה '
      'משם.';
  @override
  String get systemDriveTitle => 'יש להפעיל את התוכנה מכונן נייד';
  @override
  String get macVolumeAccessDenied =>
      'macOS לא אישר לתוכנה לכתוב לתיקייה שלצידה. יש לפתוח את הגדרות '
      'המערכת ← פרטיות ואבטחה ← קבצים ותיקיות (או גישה מלאה לדיסק), לאפשר '
      'לעדכוני אוצריא גישה למיקום הזה — כונן נשלף, מסמכים, שולחן העבודה או '
      'הורדות — ולפתוח את התוכנה מחדש.';
}

class _ReadOnlyDrive extends ReadOnlyDriveStrings {
  const _ReadOnlyDrive();

  @override
  String get bannerTitle => 'הכונן מוגן מפני כתיבה';
  @override
  String get bannerSubtitle =>
      'אפשר לעדכן ממנו את המחשב הזה, אבל אי אפשר לשמור בו עדכונים חדשים או '
      'דיווחים. כדי לשנות, הזז את מתג הנעילה שבצד הכונן ופתח את הכלי '
      'מחדש.';
  @override
  String get downloadsDisabledSnack =>
      'הכונן מוגן מפני כתיבה — אין לאן להוריד. אפשר להתקין ממה שכבר יש בו.';
  @override
  String get customAppsManageDisabled =>
      'הכונן מוגן מפני כתיבה, ולכן אי אפשר להוסיף, לערוך או להסיר כאן '
      'תוכנות. התקנה של תוכנות שכבר יש בכונן עובדת כרגיל.';
  @override
  String get bannerTitleDriveFull => 'הכונן מלא';
  @override
  String get bannerSubtitleDriveFull =>
      'נשאר בו מעט מאוד מקום, ולכן אי אפשר להוריד אליו עדכונים או לשמור בו '
      'דיווחים. פנה מקום בכונן, או העבר את התיקייה לכונן גדול יותר, ופתח '
      'את הכלי מחדש.';
  @override
  String get downloadsDisabledSnackDriveFull =>
      'הכונן מלא — אין לאן להוריד. יש לפנות בו מקום ולהפעיל את התוכנה מחדש; '
      'אפשר להתקין ממה שכבר יש בו.';
  @override
  String get customAppsManageDisabledDriveFull =>
      'הכונן מלא, ולכן אי אפשר להוסיף, לערוך או להסיר כאן תוכנות עד שיתפנה '
      'בו מקום. התקנה של תוכנות שכבר יש בכונן עובדת כרגיל.';
}

class _Elevation extends ElevationStrings {
  const _Elevation();

  @override
  String get hint =>
      'נראה שהתיקייה מוגנת ודרושות לה הרשאות מנהל — כך זה כשאוצריא מותקנת '
      'תחת Program Files. אפשר לסגור את התוכנה ולהפעיל אותה שוב בלחיצה ימנית '
      'על קובץ התוכנה ← "הפעל כמנהל", ולנסות שוב.';
  @override
  String get macHint =>
      'נראה שאין הרשאת כתיבה לתיקייה. ב-macOS אפשר לנסות שלושה דברים: '
      'להתקין את אוצריא אל "Applications" שבתיקיית הבית (~/Applications) '
      'במקום אל /Applications של כל המחשב; לבחור לספריית אוצריא מיקום בתוך תיקיית '
      'הבית; או לתת לתוכנה גישה מלאה לדיסק בהגדרות המערכת ← פרטיות ואבטחה '
      '← גישה מלאה לדיסק, ואז לפתוח אותה מחדש.';
  @override
  String get bannerTitle => 'צריך הרשאות מנהל';
  @override
  String get bannerContent =>
      'התיקייה מוגנת מפני שינויים. הכלי ייפתח מחדש כמנהל, ואז אפשר לנסות '
      'שוב.';
  @override
  String get bannerConfirm => 'הפעלה מחדש כמנהל';
  @override
  String get bannerDismiss => 'לא עכשיו';
  @override
  String restartFailedSnack(String error) =>
      'ההפעלה מחדש כמנהל נכשלה: $error. אפשר לסגור את התוכנה ולהפעיל אותה '
      'שוב בלחיצה ימנית על קובץ התוכנה ← "הפעל כמנהל".';
  @override
  String get busyNotice =>
      'ההפעלה מחדש כמנהל סוגרת את התוכנה, ולכן היא תוצע שוב בסיום ההורדה '
      'או ההתקנה שרצה כרגע.';
}

class _PayloadMismatch extends PayloadMismatchStrings {
  const _PayloadMismatch();

  @override
  String get title => 'קבצי התוכנה אינם תואמים זה לזה';
  @override
  String get explanation =>
      'קובץ ההרצה הוא מגרסה אחת, והקבצים שבתיקייה app-files שלצידו הם מגרסה '
      'אחרת. זה קורה כשעדכון לא הושלם, או כשהתיקייה הועתקה בין מחשבים בלי '
      'כל הקבצים. הפעלה במצב הזה עלולה להיתקע או להיסגר מעצמה, ולכן היא '
      'נעצרה כאן.';
  @override
  String get whatToDo =>
      'מה לעשות: לסגור את התוכנה ולפתוח אותה שוב. היא תשלים את הקבצים '
      'החסרים בעצמה — זה עשוי לקחת עד דקה, ובזמן הזה ייפתח חלון שחור שאין '
      'לסגור אותו. אם ההודעה חוזרת גם אחרי הפתיחה מחדש, יש להעתיק את קובץ '
      'ההרצה לתיקייה חדשה וריקה על הכונן הקשיח ולהפעיל אותו משם.';
  @override
  String get runningVersionTitle => 'הגרסה שרצה בפועל';
  @override
  String get expectedVersionTitle => 'הגרסה של קובץ ההרצה';
  @override
  String get closeButton => 'סגירת התוכנה';
}

class _LauncherUpdate extends LauncherUpdateStrings {
  const _LauncherUpdate();

  @override
  String installedVersion(String version) => 'הגרסה המותקנת: ${_ltr(version)}';

  @override
  String get installButton => 'התקנה והפעלה מחדש';

  @override
  String get readyDialogTitle => 'הגרסה החדשה מוכנה';
  @override
  String readyDialogContent(String version) =>
      'גרסה ${_ltr(version)} הורדה. להתקין אותה עכשיו? התוכנה תיסגר ותיפתח מחדש '
      'בגרסה החדשה, באותו מיקום בדיוק, והנתונים וההגדרות יישארו כמו שהם.';
  @override
  String get readyDialogConfirm => 'התקנה והפעלה מחדש';

  @override
  String downloadedSnack(String version) =>
      'גרסה ${_ltr(version)} ירדה לתיקייה שלצד התוכנה';
  @override
  String get installingSnack => 'הגרסה החדשה מותקנת — התוכנה תיפתח מחדש מיד';
  @override
  String get manualRestartNotice =>
      'הגרסה החדשה הוחלפה. יש לסגור את התוכנה ולפתוח אותה מחדש כדי לעבוד '
      'איתה.';
  @override
  String get busyNotice =>
      'התקנת הגרסה החדשה סוגרת את התוכנה ופותחת אותה מחדש, ולכן היא ממתינה '
      'לסיום ההורדה או ההתקנה שרצה כרגע.';
  @override
  String get installUnavailableNotice =>
      'סגור את הכלי, העתק את הקובץ החדש מהתיקייה שלמטה, ושים אותו במקום '
      'הקובץ הישן של הכלי.';

  @override
  String get whatsNewHeading => 'מה התחדש:';

  @override
  String get changelogButton => 'יומן שינויים';

  @override
  String get changelogDialogTitle => 'יומן שינויים בתוכנה';

  @override
  String get changelogNotFound => 'לא נמצא קובץ יומן שינויים.';

  @override
  String get executableNotFound =>
      'לא ניתן לאתר את קובץ ההרצה שממנו התוכנה פועלת, ולכן אין מה להחליף. '
      'יש להוריד את הגרסה החדשה ולהחליף את הקובץ ידנית.';
  @override
  String get mirrorMissing =>
      'הגרסה החדשה עדיין לא ירדה לתיקייה שלצד התוכנה. הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית.';
  @override
  String unsupportedPlatform(String operatingSystem) =>
      'עדכון עצמי של התוכנה נתמך ב-Windows וב-macOS בלבד '
      '(זוהה: $operatingSystem).';
  @override
  String downloadFailed(int statusCode) =>
      'הורדת הגרסה החדשה נכשלה (קוד שגיאה $statusCode)';
  @override
  String sizeMismatch(int received, int expected) =>
      'הקובץ שהורד לא בגודל הצפוי (התקבלו $received בייטים, צפוי $expected) — '
      'כנראה שההורדה נקטעה.';
  @override
  String replaceFailed(String error) =>
      'החלפת קובץ התוכנה נכשלה: $error. הקובץ הקודם הוחזר למקומו.';
  @override
  String replaceFailedNotRestored(
    String error,
    String previousPath,
    String executableName,
  ) =>
      'החלפת קובץ התוכנה נכשלה: $error, וגם החזרת הקובץ הקודם נכשלה. הוא '
      'שמור ב-${_ltr(previousPath)} — יש לשנות את שמו בחזרה ל-$executableName.';
  @override
  String restartFailed(String error) =>
      'הפעלת הגרסה החדשה נכשלה: $error. יש לסגור את התוכנה ולהפעיל אותה '
      'מחדש ידנית — ההחלפה עצמה כבר הושלמה.';
  @override
  String restartFailedRolledBack(String error) =>
      'הפעלת הגרסה החדשה נכשלה: $error. הגרסה הקודמת הוחזרה למקומה.';
  @override
  String get digestMismatch =>
      'קובץ הגרסה החדשה שבתיקייה פגום — הוא אינו תואם לחתימה שגיטהאב מפרסם '
      'לו. יש להוריד אותו מחדש במחשב שיש בו אינטרנט.';
}

const _hebrewMonths = [
  'ינואר',
  'פברואר',
  'מרץ',
  'אפריל',
  'מאי',
  'יוני',
  'יולי',
  'אוגוסט',
  'ספטמבר',
  'אוקטובר',
  'נובמבר',
  'דצמבר',
];

class _Units extends UnitStrings {
  const _Units();

  @override
  String bytes(int count) => '$count בייט';
  @override
  String progressOf(String received, String total) => '$received מתוך $total';
  @override
  String kilobytes(String amount) => '\u2066$amount\u00a0KB\u2069';
  @override
  String megabytes(String amount) => '\u2066$amount\u00a0MB\u2069';
  @override
  String gigabytes(String amount) => '\u2066$amount\u00a0GB\u2069';
  @override
  String perSecond(String size) => '\u2066$size/s\u2069';
  @override
  String longDate(int day, int month, int year) =>
      '$day ב${_hebrewMonths[(month - 1) % 12]} $year';
}

class _LibraryDomain extends LibraryDomainStrings {
  const _LibraryDomain();

  @override
  String unsupportedPatchCompression(String compression) =>
      'דחיסה לא נתמכת ב-patch: $compression';
  @override
  String get manifestMissingPatchFiles =>
      'שדה חובה חסר או ריק ב-manifest: patchFiles';
  @override
  String manifestMissingField(String key) =>
      'שדה חובה חסר או לא תקין ב-manifest: $key';
  @override
  String releasesRequestFailed(int statusCode) =>
      'שגיאה בקבלת רשימת הגרסאות: $statusCode';
  @override
  String get releasesResponseNotList => 'התשובה מגיטהאב אינה רשימת גרסאות';
  @override
  String manifestDownloadFailed(String url, int statusCode) =>
      'שגיאה בהורדת manifest (${_ltr(url)}): $statusCode';
  @override
  String manifestNotJsonObject(String url) =>
      'manifest אינו אובייקט JSON תקין: ${_ltr(url)}';

  @override
  String get interruptedUpdateFound =>
      'נמצא עדכון של ספריית אוצריא שלא הושלם — יש לבדוק שהיא תקינה';

  @override
  String get exportLoadingReleases => 'טוען את רשימת הגרסאות מהאתר';
  @override
  String get exportNoReleases => 'לא נמצאו עדכונים של ספריית אוצריא להורדה.';
  @override
  String exportPersonalFrom(int localVersion) =>
      'רק המחשב שלי: מוריד קובצי עדכון מגרסה $localVersion ומעלה, בלי ספריית אוצריא המלאה';
  @override
  String exportPersonalUpToDate(int localVersion) =>
      'אין גרסה חדשה מ-$localVersion — לא הורד דבר';
  @override
  String get exportPersonalVersionUnknown =>
      'לא זוהתה גרסת ספריית אוצריא במחשב — מוריד את הספרייה המלאה';
  @override
  String get exportPersonalMirrorDamaged =>
      'עדכוני הספרייה שבתיקייה פגומים — מוריד את המסד המלא';
  @override
  String exportReusingFullDb(int version, String tag) =>
      'ספריית אוצריא המלאה שכבר בכונן (גרסה $version, ${_ltr(tag)}) נשמרת — אפשר לעדכן '
      'אותה לגרסה האחרונה בקובצי עדכון, ולכן אין צורך להוריד אותה שוב';
  @override
  String exportDownloading(String tag, String asset) =>
      'מוריד ${_ltr(tag)} / ${_ltr(asset)}';
  @override
  String exportVerifying(String tag, String asset, int percent) =>
      'מאמת ${_ltr(tag)} / ${_ltr(asset)} — $percent%';
  @override
  String exportAssembling(String tag, String asset, int percent) =>
      'מרכיב ${_ltr(tag)} / ${_ltr(asset)} מחלקיו — $percent%';
  @override
  String exportSplitFullDbSkipped(String tag, String detail) =>
      'ספריית אוצריא המלאה של ${_ltr(tag)} פורסמה בחלקים, אבל רשימת החלקים פגומה או אינה '
      'תואמת להם — ולכן היא לא ירדה ($detail)';
  @override
  String exportSplitPartCorrupted(String asset, String parts) =>
      'חלקים של ${_ltr(asset)} נקראו מהכונן שונים ממה שירד ($parts) — ייתכן שהכונן '
      'פגום. החלקים האלה נמחקו ולא נכתב דבר לכונן; נסה שוב, והם יורדו מחדש.';
  @override
  String exportAssembledReplaceFailed(String path, String detail) =>
      'לא ניתן היה לשמור את ${_ltr(path)} אחרי שהורכב מחלקיו — ייתכן שתוכנה אחרת '
      '(למשל אנטי-וירוס) מחזיקה אותו. נסה שוב. ($detail)';
  @override
  String exportWritingManifest(String fileName) => 'כותב ${_ltr(fileName)}';
  @override
  String get exportDone => 'הושלם';
  @override
  String get exportCancelled => 'הייצוא בוטל';
  @override
  String get exporterDoesNotExtract =>
      'LibraryMirrorExporter מוריד קבצים בלבד ואינו מחלץ אותם';
  @override
  String exportManifestUnreadable(String asset, String detail) =>
      'קובץ פרטי העדכון ${_ltr(asset)} אינו קריא ולכן דולג ($detail)';
  @override
  String exportManifestFetchFailed(String asset, String detail) =>
      'הורדת קובץ פרטי העדכון ${_ltr(asset)} נכשלה גם אחרי ניסיונות חוזרים. ההורדה '
      'נעצרה כדי לא להשאיר בכונן עדכון חסר — נסה שוב כשהחיבור יציב. ($detail)';
  @override
  String exportPatchAssetMissing(String tag, String file) =>
      'הקובץ $file של ${_ltr(tag)} אינו זמין להורדה כרגע (ייתכן שהוא עוד עולה), '
      'ולכן הוא לא יירד לכונן';
  @override
  String exportSkippingUnappliablePatch(
    String tag,
    String file,
    int schemaVersion,
  ) =>
      'קובץ העדכון $file של ${_ltr(tag)} בנוי במבנה $schemaVersion של ספריית אוצריא, שהכלי '
      'אינו יודע להתקין, ולכן הוא אינו מועתק לכונן';
  @override
  String exportSkippingUnsupportedPatchFormat(
    String tag,
    String file,
    int patchFormatVersion,
  ) =>
      'קובץ העדכון $file של ${_ltr(tag)} בנוי במבנה $patchFormatVersion, שהכלי '
      'אינו יודע להתקין, ולכן הוא אינו מועתק לכונן';
  @override
  String exportFullDbRequiredBySchema(int schemaVersion, int latestVersion) =>
      'גרסה $latestVersion של ספריית אוצריא בנויה במבנה חדש ($schemaVersion): '
      'מוריד את הספרייה המלאה במקום קובצי העדכון';
  @override
  String exportFullDbRequiredByPatchFormat(
    int patchFormatVersion,
    int latestVersion,
  ) =>
      'קובצי העדכון של גרסה $latestVersion בנויים במבנה חדש '
      '($patchFormatVersion): מוריד את ספריית אוצריא המלאה במקומם';
  @override
  String exportFullDbSchemaUnsupported(String tag, int schemaVersion) =>
      'ספריית אוצריא המלאה של ${_ltr(tag)} פורסמה רק במבנה $schemaVersion, שגרסה זו של '
      'הכלי אינה יודעת להתקין — היא לא ירדה, והמחשב שאין בו אינטרנט יציג '
      'שצריך לעדכן את הכלי';
  @override
  String exportSkippingPatchesFullDbWins(int fileCount, int fullDbVersion) =>
      'מדלג על $fileCount קובצי עדכון: ספריית אוצריא המלאה (גרסה $fullDbVersion) חדשה '
      'יותר ממה שהם מגיעים אליו, ולכן אין בהם צורך';
  @override
  String exportFullDbInsteadOfSlowPatches(
    int fileCount,
    int patchMinutes,
    int fullDbMinutes,
    int toVersion,
  ) =>
      'העדכון לגרסה $toVersion שינה את ספריית אוצריא כולה: התקנת קובצי העדכון שלו '
      'תארך כ-$patchMinutes דקות במחשב שמתעדכן, לעומת כ-$fullDbMinutes דקות '
      'להחלפת הספרייה המלאה. מדלג על $fileCount הקבצים האלה ומוריד את הספרייה '
      'המלאה במקומם';
  @override
  String exportPersonalNeedsFullDb(int fromVersion, int latestVersion) =>
      'אין קובצי עדכון שמעבירים את גרסה $fromVersion לגרסה '
      '$latestVersion, ולכן מוריד את ספריית אוצריא המלאה — אף שבדרך כלל היא אינה '
      'יורדת כשמורידים רק בשביל המחשב שלך';
  @override
  String exportPersonalNoFullDbEither(int fromVersion, int latestVersion) =>
      'אין קובצי עדכון מגרסה $fromVersion לגרסה $latestVersion, וגם '
      'אין ספריית אוצריא מלאה בגרסה האחרונה. בחר "מחשבים מרובים" בהגדרות והורד '
      'שוב.';

  @override
  String get planLocalVersionUnknown =>
      'גרסת ספריית אוצריא שבמחשב אינה ידועה (חסר schema_meta.db_version)';
  @override
  String planContentChangedWithoutVersionBump(String releaseTag) =>
      'תוכן ספריית אוצריא עודכן ב-${_ltr(releaseTag)} בלי שמספר הגרסה השתנה';
  @override
  String planNoDeltaRoute(int localVersion, int latestVersion) =>
      'אין רצף קובצי עדכון מגרסה $localVersion לגרסה $latestVersion';
  @override
  String planFullDbFasterThanPatches(
    int stepCount,
    int patchMinutes,
    int fullDbMinutes,
  ) =>
      'התקנת $stepCount קובצי העדכון תארך כ-$patchMinutes דקות, לעומת כ-'
      '$fullDbMinutes דקות להחלפת ספריית אוצריא המלאה — ולכן היא מוחלפת';
  @override
  String planNoFullDbEither(String reason) =>
      '$reason, ואין ספריית אוצריא מלאה זמינה';
  @override
  String planPatchSchemaTooNew(int schemaVersion, int latestVersion) =>
      'הגרסה האחרונה של ספריית אוצריא ($latestVersion) בנויה במבנה '
      '$schemaVersion, שגרסה זו של הכלי אינה יודעת להתקין בקובצי עדכון';
  @override
  String planOtzariaTooOldForLibrary(int readableSchema, int latestVersion) =>
      'גרסת ספריית אוצריא $latestVersion דורשת גרסה חדשה יותר של אוצריא: הגרסה '
      'המותקנת יודעת לקרוא ספרייה עד מבנה $readableSchema בלבד. יש לעדכן קודם את '
      'אוצריא, ואחר כך את הספרייה.';
  @override
  String planStopsBeforeOtzariaSchema(int reachedVersion, int latestVersion) =>
      'ספריית אוצריא תעודכן עד גרסה $reachedVersion. גרסה $latestVersion דורשת '
      'גרסה חדשה יותר של אוצריא — אחרי עדכון אוצריא אפשר להמשיך.';
  @override
  String libraryNeedsOtzariaUpdateFromDrive(String otzariaVersion) =>
      'בכונן יש את אוצריא ${_ltr(otzariaVersion)}, שקוראת את ספריית אוצריא החדשה: יש לעדכן '
      'קודם את אוצריא, ואחר כך את הספרייה.';
  @override
  String planPatchFormatTooNew(int patchFormatVersion, int latestVersion) =>
      'קובצי העדכון של הגרסה האחרונה ($latestVersion) בנויים במבנה '
      '$patchFormatVersion, שגרסה זו של הכלי אינה יודעת להתקין';
  @override
  String planFullDbWouldNotProgress(
    int reachableVersion,
    int localVersion,
    int latestVersion,
  ) =>
      'ספריית אוצריא המלאה הזמינה מגיעה רק לגרסה $reachableVersion, שאינה חדשה '
      'מהגרסה שכבר מותקנת ($localVersion) — התקנתו תחליף את הספרייה בגרסה '
      'ישנה יותר במקום לעדכן אותה לגרסה $latestVersion. לכן העדכון לא בוצע: '
      'נדרשת ספריית אוצריא מלאה חדשה יותר, או גרסה חדשה יותר של הכלי.';
  @override
  String planNewSchemaNeedsFullDb(int latestVersion, int schemaVersion) =>
      'גרסה $latestVersion של ספריית אוצריא עברה למבנה חדש ($schemaVersion), ולכן '
      'הספרייה כולה יורדת מחדש במקום קובצי עדכון';
  @override
  String planPartialDeltaSchemaStop(
    int reachedVersion,
    int latestVersion,
    int schemaVersion,
  ) =>
      'העדכון מגיע לגרסה $reachedVersion. גרסה $latestVersion עברה למבנה '
      'חדש ($schemaVersion) שאין אליו קובצי עדכון — כדי להגיע '
      'אליה נדרשת ספריית אוצריא מלאה חדשה.';
  @override
  String planPartialDeltaFormatStop(
    int reachedVersion,
    int latestVersion,
    int patchFormatVersion,
  ) =>
      'העדכון מגיע לגרסה $reachedVersion. קובצי העדכון של גרסה $latestVersion '
      'בנויים במבנה $patchFormatVersion שהכלי אינו יודע להתקין — כדי '
      'להגיע אליה נדרשת ספריית אוצריא מלאה חדשה.';

  @override
  String mirrorManifestMissing(String fileName, String mirrorDir) =>
      'לא נמצא קובץ ${_ltr(fileName)} בתיקייה: ${_ltr(mirrorDir)}. ודא שזו '
      'התיקייה שבכונן, שאליה ירדו העדכונים מדף הבית.';
  @override
  String mirrorManifestCorrupt(
    String fileName,
    String mirrorDir,
    String error,
  ) =>
      'קובץ ${_ltr(fileName)} בתיקייה ${_ltr(mirrorDir)} פגום: $error';
  @override
  String mirrorManifestUnexpectedShape(String fileName, String mirrorDir) =>
      'קובץ ${_ltr(fileName)} בתיקייה ${_ltr(mirrorDir)} אינו בפורמט הצפוי.';
  @override
  String mirrorPatchManifestMissing(String url) =>
      'קובץ פרטי העדכון חסר בכונן: ${_ltr(url)}';
  @override
  String mirrorPatchManifestCorrupt(String url, String error) =>
      'קובץ פרטי העדכון פגום (${_ltr(url)}): $error';
  @override
  String mirrorPatchManifestNotJson(String url) =>
      'manifest אינו אובייקט JSON תקין: ${_ltr(url)}';

  @override
  String unsupportedSchemaForHashOrder(int schemaVersion) =>
      'גרסת סכמה $schemaVersion אינה נתמכת להחלת קובצי עדכון — נדרשת '
      'הורדה של המסד המלא';
  @override
  String localVersionMismatch(int? localVersion, int expected) =>
      'גרסת ספריית אוצריא שבמחשב ($localVersion) אינה מתאימה לקובץ העדכון (נדרשת $expected)';
  @override
  String localSchemaMismatch(int localSchema, int expected) =>
      'מבנה ספריית אוצריא שבמחשב ($localSchema) אינו מתאים לקובץ העדכון (נדרש $expected)';
  @override
  String get contentHashMismatchNeedsFullDownload =>
      'ספריית אוצריא שבמחשב שונה מהצפוי, ולכן קובץ העדכון לא מתאים לה '
      '(fromContentHash). נדרשת הורדה של הספרייה המלאה.';
  @override
  String patchUniqueConflictNeedsFullDownload(String table, String detail) =>
      'קובץ העדכון אינו מתאים לספריית אוצריא שבמחשב: התנגשות ערך ייחודי בטבלה "$table". '
      'העדכון בוטל והספרייה לא השתנתה. נדרשת הורדה מלאה שלה. '
      '($detail)';
  @override
  String foreignKeyViolationsGrew(int before, int after) =>
      'מספר הפרות מפתח זר גדל ($before→$after) — ה-patch אינו תקין';
  @override
  String resultHashMismatch(String actual, String expected) =>
      'ה-hash אחרי apply ($actual) אינו תואם ל-toContentHash ($expected)';
  @override
  String get patchMetaSchemaVersionMissing =>
      'patch_meta.schema_version חסר ב-patch';
  @override
  String patchFormatTooNew(int patchFormatVersion, int supported) =>
      'פורמט קובץ העדכון ($patchFormatVersion) אינו בטווח הנתמך '
      '(1–$supported) — צריך לעדכן את הכלי';
  @override
  String patchFormatMismatch(int inPatch, int inManifest) =>
      'פורמט קובץ העדכון ($inPatch) אינו תואם למה שה-manifest הצהיר '
      '($inManifest)';
  @override
  String patchVersionRangeMismatch(
    int? from,
    int? to,
    int manifestFrom,
    int manifestTo,
  ) =>
      'גרסאות ה-patch ($from→$to) אינן תואמות ל-manifest '
      '($manifestFrom→$manifestTo)';

  @override
  String get compressedFileSizeLabel => 'גודל הקובץ הדחוס';
  @override
  String get compressedFileHashLabel => 'sha256 של הקובץ הדחוס';
  @override
  String get extractedFileSizeLabel => 'גודל הקובץ המחולץ';
  @override
  String get extractedFileHashLabel => 'sha256 של הקובץ המחולץ';
  @override
  String get patchExtractionFailed =>
      'חילוץ קובץ העדכון נכשל, או שהתקבל קובץ ריק';
  @override
  String get deleteExistingWithoutResumeIdentityFailed =>
      'מחיקת קובץ קיים ללא זהות resume נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialFromPreviousVersionFailed =>
      'מחיקת קובץ חלקי מגרסה קודמת נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialWithoutValidatorFailed =>
      'מחיקת קובץ חלקי ללא validator נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialFromPreviousRepresentationFailed =>
      'מחיקת קובץ חלקי מייצוג קודם נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialBeforeRetryFailed =>
      'מחיקת קובץ חלקי לפני ניסיון חוזר נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String fullDbSizeMismatch(int downloaded, int expected) =>
      'גודל ספריית אוצריא שהורדה ($downloaded) אינו תואם לצפוי ($expected)';
  @override
  String get fullDbHashMismatch =>
      'הקובץ שהורד נפגם (sha256 אינו תואם) ונמחק — יש להוריד שוב. אם זה '
      'חוזר, ייתכן שהכונן תקול: כדאי לבדוק אותו לשגיאות או להחליף אותו.';
  @override
  String resumeRoundLimit(int maxRounds, String url) =>
      'חידוש ההורדה חרג ממספר הסבבים המרבי ($maxRounds): ${_ltr(url)}';
  @override
  String contentLengthMismatch(int responseLength, int expectedSize) =>
      'Content-Length של ההורדה ($responseLength) אינו תואם לגודל הצפוי '
      '($expectedSize)';
  @override
  String truncatedBody(int declared, int received) =>
      'גוף ההורדה נקטע: Content-Length הצהיר $declared בייטים, '
      'אך התקבלו $received';
  @override
  String downloadHttpError(int statusCode, String url) =>
      'שגיאה בהורדה ($statusCode): ${_ltr(url)}';
  @override
  String resumeMadeNoProgress(String url) =>
      'חידוש ההורדה לא התקדם: ${_ltr(url)}';
  @override
  String resumeFailedAfterRetry(String url) =>
      'חידוש ההורדה נכשל לאחר ניסיון חוזר: ${_ltr(url)}';
  @override
  String downloadExceedsExpectedSize(int expectedSize) =>
      'ההורדה חורגת מהגודל הצפוי ($expectedSize בייטים)';
  @override
  String saveDownloadedFileFailed(String error) =>
      'שמירת הקובץ שהורד לדיסק נכשלה: $error';
  @override
  String tooManyRedirects(String url) => 'יותר מדי הפניות: ${_ltr(url)}';
  @override
  String writeResumeSidecarFailed(String path, String error) =>
      'כתיבת קובץ הזהות להמשך ההורדה נכשלה (${_ltr(path)}): $error';
  @override
  String checksumMismatchDetailed(
    String label,
    String expected,
    String actual,
  ) =>
      '$label אינו תואם: צפוי $expected, התקבל $actual';
  @override
  String checksumMismatch(String label) => '$label אינו תואם';
  @override
  String localFileNotFound(String path) => 'קובץ מקומי לא נמצא: ${_ltr(path)}';
  @override
  String localFileTooLarge(int maxBytes, String path) =>
      'הקובץ המקומי חורג מהגודל הצפוי ($maxBytes בייטים): ${_ltr(path)}';
  @override
  String localSourceNotFound(String url) =>
      'קובץ מקור מקומי לא נמצא: ${_ltr(url)}';
  @override
  String localFileSizeMismatch(int expected, int actual, String url) =>
      'גודל הקובץ המקומי אינו תואם: צפוי $expected, בפועל $actual (${_ltr(url)})';
  @override
  String localFileHashMismatch(String url) =>
      'הקובץ שבכונן פגום ולא ניתן להשתמש בו: ${_ltr(url)} — יש להוריד שוב במחשב עם '
      'חיבור לאינטרנט. אם זה חוזר, ייתכן שהכונן תקול.';
  @override
  String get manifestMissingPatchFormatVersion =>
      'שדה חובה חסר במניפסט של schema 4+: patchFormatVersion';
  @override
  String manifestInvalidOptionalField(String key) =>
      'שדה אופציונלי לא תקין במניפסט: $key';
  @override
  String manifestInvalidHashMap(String key) =>
      'ערך לא תקין במפת ה-hash במניפסט: $key';
  @override
  String splitManifestDownloadFailed(String name, int statusCode) =>
      'שגיאה בהורדת רשימת החלקים ($name): $statusCode';
  @override
  String get interruptedUpdateWithoutBackup =>
      'נמצא עדכון של ספריית אוצריא שלא הושלם ואין לו גיבוי — יש לבדוק שהיא תקינה';
  @override
  String get interruptedUpdateRestored =>
      'נמצא עדכון של ספריית אוצריא שנקטע — הספרייה שוחזרה מהגיבוי';
  @override
  String planSchemaNeedsAppUpdate(int schemaVersion, int supportedSchema) =>
      'ספריית אוצריא עברה למבנה $schemaVersion, '
      'חדש מזה שהכלי מכיר ($supportedSchema) — צריך לעדכן את הכלי';
  @override
  String planSchemaBarrierNeedsFullDownload(int schemaVersion) =>
      'ספריית אוצריא עברה למבנה $schemaVersion; המעבר מחייב הורדה של הספרייה המלאה';
  @override
  String planDeltaNeedsAppUpdate(
    int latestVersion,
    int supportedSchema,
    int supportedPatchFormat,
  ) =>
      'העדכון לגרסה $latestVersion דורש מבנה של ספריית אוצריא או קובצי עדכון '
      'חדשים ממה שהכלי מכיר (מבנה $supportedSchema, '
      'קובצי עדכון $supportedPatchFormat) — צריך לעדכן את הכלי';
  @override
  String planHeavyDelta(String deltaSize, String localDbSize) =>
      'קובצי העדכון גדולים ($deltaSize) ביחס לספריית אוצריא שבמחשב '
      '($localDbSize), והתקנתם עלולה להימשך זמן רב';
  @override
  String tableHashMismatch(String tables) =>
      'ה-hash אחרי apply אינו תואם ל-toTableContentHashes בטבלאות: $tables';
  @override
  String patchOpenFailed(String path, String detail) =>
      'לא ניתן לפתוח את קובץ העדכון (${_ltr(path)}): $detail';
  @override
  String get networkInterrupted => 'החיבור לרשת נקטע במהלך ההורדה';
  @override
  String get deletePreviousArchiveFailed =>
      'מחיקת ארכיון קודם נכשלה — לא ניתן לחבר את חלקי ההורדה';
  @override
  String joinedArchiveSizeMismatch(int written, int expected) =>
      'גודל הארכיון המחובר ($written) אינו תואם לצפוי ($expected)';
  @override
  String get joinedArchiveHashMismatch => 'sha256 של הארכיון המחובר אינו תואם';

  @override
  String get mirrorMissing =>
      'עדיין לא ירדו עדכונים של ספריית אוצריא לתיקייה שבכונן. הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית.';
  @override
  String get mirrorDamaged =>
      'עדכוני הספרייה שבתיקייה המקומית פגומים ולא ניתן לקרוא אותם — בדרך כלל '
      'כונן שנשלף בלי "הוצאה בטוחה" או כונן תקול. יש להריץ הורדה שוב במחשב '
      'עם חיבור לאינטרנט; אם זה חוזר, כדאי לבדוק את הכונן לשגיאות או להחליף '
      'אותו.';
  @override
  String interruptedUpdateCorruptDb(String detail) =>
      '$detail — בבדיקה נמצא שספריית אוצריא פגומה, ולכן יש להחליף אותה '
      'בספרייה המלאה.';
  @override
  String get interruptedUpdateDefaultDetail => 'עדכון של ספריית אוצריא שנקטע';
  @override
  String get blockedNeedsManualAction => 'מצב חסום — נדרשת פעולה ידנית';
  @override
  String get blockedNeedsManualActionWithPeriod =>
      'מצב חסום — נדרשת פעולה ידנית.';
  @override
  String patchUrlMissing(String fileName) =>
      'לא נמצא URL להורדת ${_ltr(fileName)}';
  @override
  String get fullDbAssetMissingFromPlan =>
      'בתוכנית העדכון חסר קובץ ספריית אוצריא המלאה';
  @override
  String get fullDbExtractionFailed =>
      'חילוץ ספריית אוצריא המלאה נכשל, או שהתקבל קובץ ריק';
  @override
  String get fullDbNeedsNativeZstd =>
      'חילוץ ספריית אוצריא המלאה דורש רכיב (zstd) שאינו זמין במחשב הזה';
  @override
  String get patchNeedsNativeZstd =>
      'חילוץ קובץ העדכון דורש רכיב (zstd) שאינו זמין במחשב הזה';
  @override
  String versionMismatchAfterWrite(int? actual, int? expected) =>
      'אחרי כתיבת ספריית אוצריא המלאה, הגרסה שנקראה ($actual) לא תואמת ליעד '
      '($expected) — בוצע שחזור.';
  @override
  String get updateCancelled => 'העדכון בוטל';
  @override
  String notEnoughDiskSpace(String dir, String needed, String free) =>
      'אין מספיק מקום פנוי ב-${_ltr(dir)}: נדרשים $needed ופנויים $free. פנה מקום '
      'בכונן הזה ונסה שוב, או בחר מיקום אחר לספריית אוצריא.';
  @override
  String fileTooLargeForVolume(String dir) =>
      'הכונן שבו נמצא ${_ltr(dir)} מפורמט ב-FAT32, שאינו יכול להכיל קבצים גדולים '
      'מ-\u20664\u00a0GB\u2069, וספריית אוצריא גדולה מזה. בחר לה מיקום בכונן NTFS או exFAT.';
  @override
  String installDirNotWritable(String dir, String detail) =>
      'לא ניתן ליצור את התיקייה ${_ltr(dir)} ($detail). בחר מיקום אחר לספריית אוצריא דרך '
      '"בחירת מיקום ידנית" בדף ספריית אוצריא.';
  @override
  String mirrorNotEnoughDiskSpace(String dir, String needed, String free) =>
      'אין מספיק מקום פנוי ב-${_ltr(dir)} להורדה: נדרשים $needed ופנויים $free. '
      'פנה מקום בכונן ונסה שוב — מה שכבר ירד נשמר.';
  @override
  String get otzariaIsRunning =>
      'אוצריא פתוחה כרגע — יש לסגור אותה לפני עדכון ספריית אוצריא, כדי למנוע נעילת '
      'קובץ.';
  @override
  String get localDbLocked =>
      'לא ניתן לקרוא את גרסת ספריית אוצריא שבמחשב כי קובץ הספרייה נעול, כנראה מפני '
      'שאוצריא פתוחה. יש לסגור את אוצריא ולבדוק שוב.';
  @override
  String get localDbInterruptedWrite =>
      'לא ניתן לקרוא את גרסת ספריית אוצריא שבמחשב: קובץ הספרייה נשאר באמצע כתיבה שנקטעה. '
      'יש לפתוח את אוצריא ולסגור אותה, ואז לבדוק שוב.';
  @override
  String get localDbReadOnlyLocation =>
      'לא ניתן לקרוא את גרסת ספריית אוצריא שבמחשב, כי התיקייה שלה מוגנת מפני '
      'כתיבה. יש לאפשר כתיבה לתיקייה ולבדוק שוב.';
  @override
  String get zstdContextCreationFailed => 'יצירת הקשר החילוץ (DCtx) נכשלה';
  @override
  String zstdDecompressionFailed(String errorName) =>
      'חילוץ הקובץ הדחוס נכשל: $errorName';
  @override
  String get zstdEmptyInput => 'הקובץ הדחוס ריק';
  @override
  String get zstdTruncatedFrame => 'הקובץ הדחוס קטוע ואינו שלם';

  @override
  String dbIntegrityCheckFailed(String result) =>
      'בדיקת התקינות של ספריית אוצריא שהורדה נכשלה: $result';

  @override
  String get companionTalmudName => 'תלמוד בבלי';
  @override
  String get companionCatalogName => 'רשימת הספרים של אוצר החכמה והיברובוקס';
  @override
  String get companionDictionaryName => 'מילון החיפוש המקורב';
  @override
  String get companionSemanticName => 'החיפוש החכם';
  @override
  String get libraryChangesNotesName => 'רשימת "מה חדש בספריית אוצריא"';
  @override
  String get semanticDownloading => 'מוריד את קובצי החיפוש החכם';
  @override
  String get semanticInstalling => 'מתקין את החיפוש החכם';
  @override
  String get semanticConsentTitle => 'שיפור החיפוש החכם';
  @override
  String get semanticConsentTerms =>
      'זהו חיפוש ניסיוני, והחיפושים בו עוזרים לשפר אותו. לכן השימוש בו מותנה בהסכמה לשליחת נתוני שימוש: מילות החיפוש, התוצאות שהוצגו ודירוגן, הקטעים שנפתחו או שסומנו (אהבתי / לא אהבתי) וזמן העיון בהם, וכן גרסת התוכנה ומערכת ההפעלה. תוכן מספרים אישיים אינו נשלח. כתובות דוא"ל ונתיבי קבצים מזוהים מוסווים בטקסט החיפוש, אך פרטים אישיים אחרים עלולים להישלח. אין לכלול פרטים אישיים בטקסט החיפוש. אפשר לבטל את ההסכמה בכל עת בהגדרות של אוצריא, והביטול חוסם את מצב החיפוש הזה.';
  @override
  String get semanticConsentText =>
      'זהו חיפוש ניסיוני, והחיפושים בו עוזרים לשפר אותו. לכן השימוש בו מותנה בהסכמה לשליחת נתוני שימוש: מילות החיפוש, התוצאות שהוצגו ודירוגן, הקטעים שנפתחו או שסומנו (אהבתי / לא אהבתי) וזמן העיון בהם, וכן גרסת התוכנה ומערכת ההפעלה. תוכן מספרים אישיים אינו נשלח. כתובות דוא"ל ונתיבי קבצים מזוהים מוסווים בטקסט החיפוש, אך פרטים אישיים אחרים עלולים להישלח. אין לכלול פרטים אישיים בטקסט החיפוש. אפשר לבטל את ההסכמה בכל עת בהגדרות, והביטול חוסם את מצב החיפוש הזה.\n\nהאישור מפעיל את ההסכמה בהגדרות אוצריא. מרגע זה התוכנה אוספת את הנתונים לכונן ושולחת אותם לאוצריא כשיש חיבור לאינטרנט, אוטומטית וללא הודעות. הנתונים, כולל מילות החיפוש, נשמרים בכונן ללא הצפנה עד שליחתם, יחד עם המפתח האנונימי שחותם עליהם.';
  @override
  String get semanticAskTitle => 'חיפוש חכם במחשב הזה';
  @override
  String get semanticAskIntro =>
      'בכונן יש גם חיפוש חכם: חיפוש לפי משמעות, שמוצא מקורות גם כשהמילים '
      'שונות ממה שחיפשת. אפשר להתקין אותו עכשיו, יחד עם העדכון.';
  @override
  String get semanticAskLater =>
      'השאלה לא תחזור במחשב הזה. אפשר להפעיל אחר כך בהגדרות של הכלי הזה; '
      'הביטול — בהגדרות של אוצריא.';
  @override
  String get semanticConsentNotSaved =>
      'לא הצלחתי לשמור את ההסכמה בהגדרות אוצריא — החיפוש החכם לא הותקן. אפשר '
      'לנסות שוב.';
  @override
  String get semanticConsentBlocked =>
      'שרת אוצריא חסם את שליחת נתוני האימון מהמחשב הזה, ולכן אי אפשר להפעיל '
      'כאן את החיפוש החכם.';
  @override
  String get semanticAskApprove => 'הסכמה והתקנת החיפוש החכם';
  @override
  String get semanticAskDecline => 'המשך בלי חיפוש חכם';
  @override
  String get semanticConsentConfirm => 'אישור ההסכמה';
  @override
  String get semanticFeedbackFailed =>
      'שליחת נתוני האימון לא הושלמה. אפשר לנסות שוב; הפרטים נשמרו ביומן.';
  @override
  String get semanticConsentRequired =>
      'קובצי החיפוש החכם נמצאים בכונן. לפני התקנתם יש לאשר איסוף נתוני אימון. אפשר לאשר כאן כשאוצריא סגורה, או להפעיל את ההסכמה בהגדרות אוצריא ולבדוק שוב.';
  @override
  String get semanticFullDownloadNeeded =>
      'החיפוש החכם במחשב זה אינו בגרסה שהעדכון החלקי שבכונן ממשיך ממנה, ולכן לא הותקן. בהורדה הבאה במחשב המקוון תירד חבילת החיפוש החכם המלאה.';
  @override
  String companionChecking(String name) => 'בודק $name...';
  @override
  String companionDownloading(String name) => 'מוריד $name…';
  @override
  String companionInstalling(String name) => 'מתקין $name…';
  @override
  String companionAssetMissingInRelease(String name) =>
      'לא נמצא קובץ של $name בגרסה האחרונה באתר';
  @override
  String companionAssetHttpFailure(String name, int status) =>
      'לא נמצא קובץ של $name בגרסה האחרונה באתר (HTTP $status)';
  @override
  String companionExtractionFailed(String name) => 'חילוץ $name נכשל';
  @override
  String get companionsMirrorMissing => 'הקבצים הנלווים עוד לא הורדו לכונן';
  @override
  String companionStillPendingAfterInstall(String name) =>
      'ההתקנה של $name הסתיימה אך הפריט עדיין מסומן כלא מעודכן';
  @override
  String companionsInstallFailed(String names) =>
      'ספריית אוצריא עודכנה, אך התקנת הקבצים הנלווים ($names) נכשלה — ולכן ההצעה לעדכן '
      'את ספריית אוצריא תחזור.';
  @override
  String libraryLocationNeedsManualSetting(String dbPath) =>
      'ספריית אוצריא הותקנה ב-${_ltr(dbPath)}, אך לא ניתן היה לעדכן את ההגדרות של אוצריא. '
      'יש לפתוח את אוצריא ולהצביע על התיקייה הזו במסך שבו בוחרים את מיקום הספרייה באוצריא.';
  @override
  String companionsMissingFromMirror(String names) =>
      'חסר בכונן: $names. כנראה ההורדה נקטעה. כדי לקבל אותו, הורד שוב במחשב '
      'עם אינטרנט. שאר העדכון יותקן כרגיל.';
  @override
  String get companionsAbsentFromMirror =>
      'בכונן אין את התלמוד הבבלי, רשימת הספרים והמילון, ולכן הם לא יותקנו. כדי '
      'לקבל אותם, הורד שוב במחשב עם אינטרנט.';

  @override
  String applyDownloadingPatch(String step) => 'מוריד עדכון$step…';
  @override
  String applyApplyingPatch(String step) => 'מעדכן את ספריית אוצריא$step…';
  @override
  String applyPatchStage(String stage, String step) {
    switch (stage) {
      case 'preflight':
        return 'בודק תאימות$step…';
      case 'verifyFromHash':
        return 'מאמת את ספריית אוצריא הקיימת$step…';
      case 'attach':
        return 'פותח את קובץ העדכון$step…';
      case 'migrations':
        return 'מעדכן את מבנה ספריית אוצריא$step…';
      case 'upserts':
        return 'כותב את השינויים$step…';
      case 'deletes':
        return 'מסיר רשומות שנמחקו$step…';
      case 'foreignKeyCheck':
        return 'בודק שהשינויים שלמים$step…';
      case 'verifyToHash':
        return 'מאמת את תוצאת העדכון$step…';
      case 'commit':
        return 'שומר את השינויים$step…';
      default:
        return applyApplyingPatch(step);
    }
  }

  @override
  String get applyDownloadingFullDb => 'מוריד את ספריית אוצריא המלאה…';
  @override
  String get applyDecompressingFullDb => 'מחלץ את ספריית אוצריא…';
  @override
  String get applyDecompressingAndVerifyingFullDb =>
      'מחלץ את ספריית אוצריא ומאמת את חתימתה…';
  @override
  String get applyWritingFullDb => 'כותב את ספריית אוצריא…';
  @override
  String get applyVerifying => 'מוודא תקינות…';
  @override
  String applyVerifyStage(String stage) {
    switch (stage) {
      case 'sourceHash':
        return 'מאמת את חתימת קובץ ספריית אוצריא…';
      case 'dbIntegrity':
        return 'בודק את שלמות ספריית אוצריא שחולצה (סריקה מלאה, עשוי לקחת דקות)…';
      case 'dbVersion':
        return 'מאמת את גרסת ספריית אוצריא שחולצה…';
      default:
        return applyVerifying;
    }
  }

  @override
  String applyStageElapsed(String stage, String elapsed) => '$stage — $elapsed';
  @override
  String get applyInstallingCompanions => 'מתקין קבצים נלווים…';
  @override
  String get applyDone => 'הושלם.';
}

class _AppDomain extends AppDomainStrings {
  const _AppDomain();

  @override
  String get channelStable => 'יציבה';
  @override
  String get channelPrerelease => 'ניסיונית';
  @override
  String downloadingChannel(String channelLabel) =>
      'מוריד את תוכנת אוצריא (גרסה $channelLabel)…';
  @override
  String get downloadCancelled => 'ההורדה בוטלה.';
  @override
  String get installCancelledByUser => 'ההתקנה בוטלה באשף ההתקנה.';
  @override
  String get wizardStillOpen =>
      'אשף ההתקנה של אוצריא נפתח. כשתסיים בו, לחץ "בדוק שוב" כדי שהכלי '
      'יזהה את ההתקנה.';
  @override
  String get wizardEndedWithoutInstall =>
      'אשף ההתקנה נסגר, אבל הגרסה החדשה לא נמצאה במחשב. אם התקנת לתיקייה '
      'אחרת, אפשר לבחור אותה ב"בחירת מיקום ידנית"; אחרת יש להתקין שוב.';
  @override
  String get setupContinuesElsewhere =>
      'אשף ההתקנה ממשיך לעדכן את אוצריא בחלון משלו — ממתינים לסיומו…';

  @override
  String get noInstallableReleaseForPlatform =>
      'לא נמצאה גרסת אוצריא שאפשר להתקין במערכת ההפעלה הזו.';
  @override
  String get mirrorEmptyRunDownload =>
      'אין בכונן גרסת אוצריא. הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית.';
  @override
  String get noOtzariaInstallFound =>
      'לא נמצאה התקנה של אוצריא במחשב — יש להתקין אותה, או לבחור את תיקיית '
      'ההתקנה הקיימת.';
  @override
  String get corruptReleaseMetadata => 'פרטי גרסת אוצריא פגומים';
  @override
  String unsupportedPlatform(String operatingSystem) =>
      'הכלי תומך בהתקנת אוצריא ב-Windows וב-macOS בלבד '
      '(זוהה: $operatingSystem).';
  @override
  String noAssetForPlatform(
    String tagName,
    String platform,
    List<String> expectedSuffixes,
  ) {
    final suffixes = expectedSuffixes.map((s) => '"$s"').join(' או ');
    return 'לגרסה "${_ltr(tagName)}" אין קובץ התקנה מתאים ל-$platform '
        '(מצפים לשם שמסתיים ב-$suffixes).';
  }

  @override
  String installerDownloadFailed(int statusCode) =>
      'הורדת קובץ ההתקנה נכשלה (קוד שגיאה $statusCode)';
  @override
  String installerSizeMismatch(int received, int expected) =>
      'קובץ ההתקנה שהורד לא בגודל הצפוי (התקבלו $received בייטים, '
      'צפוי $expected) — כנראה שהורדה נקטעה.';
  @override
  String get installerDigestMismatch =>
      'קובץ ההתקנה של אוצריא שבתיקייה פגום — הוא אינו תואם לחתימה שגיטהאב '
      'מפרסם לו. יש להוריד אותו מחדש במחשב שיש בו אינטרנט.';
  @override
  String installerExitCode(int exitCode, String output) =>
      'אשף ההתקנה הסתיים בשגיאה (קוד $exitCode).\n$output';
  @override
  String installerLogTail(String tail) => 'סוף יומן ההתקנה:\n$tail';
  @override
  String get macAppNotFoundInArchive =>
      'לא נמצאה חבילת .app בתוך חבילת ההתקנה שחולצה — ייתכן שמבנה קובץ ההתקנה '
      'של אוצריא ל-macOS השתנה.';
  @override
  String macReplaceFailed(String error) =>
      'החלפת חבילת ה-.app בתיקיית ההתקנה נכשלה: $error';
  @override
  String get macCloseOtzariaBeforeInstall =>
      'אוצריא פתוחה כרגע. ב-macOS ההתקנה מחליפה את חבילת האפליקציה כולה, '
      'ואוצריא שרצה תישאר בלי הקבצים שלה ותקרוס — יש לסגור אותה ולנסות שוב.';
  @override
  String dittoExtractFailed(int exitCode, String output) =>
      'חילוץ חבילת ההתקנה (ditto) נכשל בקוד $exitCode.\n$output';
  @override
  String hdiutilAttachFailed(int exitCode, String output) =>
      'הרכבת דמות הדיסק (hdiutil attach) נכשלה בקוד $exitCode.\n$output';
  @override
  String get macAppNotFoundInDmg =>
      'לא נמצאה חבילת .app בתוך דמות הדיסק שהורכבה.';
  @override
  String dittoCopyFailed(int exitCode, String output) =>
      'העתקת ה-.app מדמות הדיסק (ditto) נכשלה בקוד $exitCode.\n$output';
  @override
  String installNotDetected(String installDir, int timeoutSeconds) =>
      'לא נמצאה התקנה של אוצריא בתוך ${_ltr(installDir)} תוך $timeoutSeconds שניות '
      'מסיום אשף ההתקנה. ייתכן שההתקנה עדיין רצה ברקע, או שמיקום ההתקנה '
      'השתנה בגרסה חדשה של אוצריא.';
  @override
  String installNotDetectedAnywhere(int timeoutSeconds) =>
      'ההתקנה הסתיימה, אבל אוצריא לא נמצאה במחשב תוך $timeoutSeconds שניות — '
      'לא ברשימת התוכנות המותקנות ולא במיקומים המוכרים. אם היא כן הותקנה, '
      'בחר את תיקיית ההתקנה ידנית בדף "אוצריא — מתקדם".';
  @override
  String launchFileMissing(String launchPath) =>
      'קובץ ההפעלה לא נמצא בנתיב: ${_ltr(launchPath)}';
  @override
  String launchFailed(int exitCode, String stderr) =>
      'הפעלת אוצריא נכשלה (open החזיר $exitCode): $stderr';
  @override
  String githubStatus(int statusCode, String uri) =>
      'גיטהאב החזיר שגיאה $statusCode עבור $uri';
  @override
  String githubRateLimited(int? retryAfterMinutes) {
    final retry = switch (retryAfterMinutes) {
      null => 'יש לנסות שוב מאוחר יותר.',
      1 => 'יש לנסות שוב בעוד כ-1 דקה.',
      final minutes => 'יש לנסות שוב בעוד כ-$minutes דקות.',
    };
    return 'גיטהאב הגביל זמנית את מספר הבקשות מהרשת הזאת. $retry';
  }

  @override
  String networkBlockedByFilter(int statusCode, String host) =>
      'הגישה אל $host נחסמה (סטטוס $statusCode). כנראה סינון האינטרנט '
      '(למשל נטפרי) חוסם את הכתובת — יש לבקש לפתוח אותה בסינון, או להוריד '
      'ממחשב אחר.';
  @override
  String networkCertificateRejected(String host) =>
      'החיבור המאובטח אל $host נכשל: האישור (תעודת האבטחה) שהתקבל אינו '
      'מוכר. אם המחשב מחובר דרך סינון כמו נטפרי, יש להתקין את תעודת הסינון '
      'במחשב, או להוריד ממחשב אחר.';

  @override
  String noReleasesAtAll(String repo) => 'לא נמצאו גרסאות כלל ב-$repo.';
  @override
  String get windowsOnlyReader => 'WindowsExeVersionReader עובד רק בווינדוס.';
  @override
  String get macOnlyReader => 'MacAppVersionReader עובד רק ב-macOS.';
}

class _PluginsDomain extends PluginsDomainStrings {
  const _PluginsDomain();

  @override
  String get fileNotAvailableSyncFirst =>
      'הקובץ עוד לא בכונן. יש להוריד את התוספים לכונן במחשב עם אינטרנט.';
  @override
  String saveFailed(String error) => 'שמירת הקובץ נכשלה: $error';
  @override
  String get pluginFileNotAvailable =>
      'קובץ התוסף עוד לא בכונן. יש להוריד את התוספים לכונן במחשב עם אינטרנט.';
  @override
  String get noCompatibleBuild =>
      'אין לתוסף גרסה שמתאימה לגרסת אוצריא שבמחשב הזה.';
  @override
  String get localPluginFileMissing =>
      'קובץ התוסף חסר בכונן. יש להוריד שוב את התוספים לכונן במחשב עם אינטרנט.';
  @override
  String get localPluginFileCorrupt =>
      'קובץ התוסף שבכונן פגום או אינו הגרסה שנבחרה. יש להוריד את התוספים מחדש במחשב עם אינטרנט.';
  @override
  String get badPluginExtension => 'קובץ התוסף אינו בסיומת otzplugin תקינה.';
  @override
  String get otzariaOpenFailedHint =>
      'פתיחת אוצריא נכשלה. ודא שאוצריא מותקנת במחשב זה. ';
  @override
  String otzariaOpenFailed(String error) => 'פתיחת אוצריא נכשלה: $error';
  @override
  String get directInstallUnsupportedPlatform =>
      'התקנה ישירה נתמכת ב-Windows וב-macOS בלבד.';

  @override
  String get syncLoadingCatalog => 'טוען את רשימת התוספים מהאתר…';
  @override
  String syncPlugin(String name, int done, int total) =>
      'מעדכן: $name ($done/$total)';
  @override
  String syncDoneCounts(int fetched, int skipped) =>
      'רשימת התוספים עודכנה: $fetched תוספים עודכנו, $skipped כבר היו מעודכנים';
  @override
  String get syncCategories => 'מעדכן את קטגוריות החנות…';
  @override
  String syncStructureFailed(String error) =>
      'לא ניתן לטעון את מבנה החנות מהאתר ($error) — נשמר המבנה הקודם';
  @override
  String get syncStructureEmpty => 'האתר לא החזיר קטגוריות';
  @override
  String get syncEmptyCatalogRejected =>
      'האתר החזיר רשימת תוספים ריקה — החנות שכבר ירדה נשמרה כמות שהיא. '
      'כדאי לנסות שוב מאוחר יותר.';
  @override
  String syncCategoryFailed(String name, String error) =>
      'לא ניתן לטעון את הקטגוריה $name: $error';
  @override
  String syncImageFailed(String name, String error) =>
      'לא ניתן להוריד תמונה עבור $name: $error';
  @override
  String syncScreenshotFailed(String name, String error) =>
      'לא ניתן להוריד צילום מסך עבור $name: $error';
  @override
  String syncPluginFileFailed(String name, String error) =>
      'לא ניתן להוריד את קובץ התוסף $name: $error';
  @override
  String get downloadedFileNotPlugin => 'הקובץ שירד אינו קובץ תוסף תקין';
  @override
  String get downloadedFileNotImage =>
      'הקובץ שירד אינו תמונה (ייתכן שזה דף חסימה של סינון)';
  @override
  String get downloadedFileHashMismatch =>
      'הקובץ שירד אינו תואם לחתימה שהאתר פרסם';
  @override
  String get downloadedFileWrongBuild =>
      'הקובץ שירד אינו הגרסה שנבחרה של התוסף';
  @override
  String get siteClosedForShabbat =>
      'אתר אוצריא סגור בשבת ובימים טובים. החנות שכבר בכונן ממשיכה לעבוד, ואפשר להוריד עדכונים אחרי צאת השבת.';

  @override
  String get whatPluginList => 'רשימת התוספים';
  @override
  String get whatStoreStructure => 'מבנה החנות';
  @override
  String whatCategory(String slug) => 'הקטגוריה $slug';
  @override
  String get responseNotPluginList => 'תשובת האתר אינה רשימת תוספים תקינה';
  @override
  String get networkTimedOut => 'האתר לא השיב בזמן';
  @override
  String siteUnreachable(String error) => 'לא ניתן להתחבר לאתר אוצריא: $error';
  @override
  String loadFailed(String what, int statusCode) =>
      'לא ניתן לטעון את $what (HTTP $statusCode)';
  @override
  String responseNotJson(String what) => 'תשובת האתר עבור $what אינה תקינה';
  @override
  String get responseUnexpectedShape => 'תשובת האתר אינה במבנה הצפוי';
  @override
  String httpStatusFor(int statusCode, String url) =>
      'HTTP $statusCode עבור ${_ltr(url)}';

  @override
  String get exportPreparing => 'מכין את ההעתקה…';
  @override
  String get exportAppMissing =>
      'תוכנת החנות אינה בכונן. הורד עדכונים לכונן במחשב עם אינטרנט, מדף הבית.';
  @override
  String get exportCopyingApp => 'מעתיק את תוכנת החנות…';
  @override
  String exportAppCopyFailed(String error) =>
      'לא ניתן לשמור את קובץ התוכנה בתיקייה שנבחרה: $error. ייתכן שתוכנת אנטי-וירוס '
      'חוסמת אותו, או שאין הרשאת כתיבה לתיקייה שנבחרה.';
  @override
  String exportAppVanished(String path) =>
      'קובץ ההרצה של החנות נעלם מ-${_ltr(path)}. כמעט תמיד זו תוכנת אנטי-וירוס '
      'שמחקה קובץ הרצה לא-חתום (ב-Windows Defender: אבטחת Windows ← הגנה '
      'מפני וירוסים ← היסטוריית הגנה, ומשם "אפשר במכשיר").';
  @override
  String get exportAppRemovedFromMirror =>
      'תוכנת החנות הורדה לכונן ואינה שם יותר. הורדה חוזרת לא תעזור — כנראה '
      'תוכנת אנטי-וירוס מוחקת אותה; יש לאשר אותה שם ואז להוריד שוב.';
  @override
  String get exportAppDamaged =>
      'תוכנת החנות שבכונן פגומה — היא אינה תואמת לחתימה שגיטהאב מפרסם לה. '
      'יש להוריד אותה מחדש במחשב שיש בו אינטרנט.';
  @override
  String exportPlugin(String name, int done, int total) =>
      'מעתיק את $name ($done מתוך $total)';
  @override
  String get exportWritingCatalog => 'כותב את רשימת התוספים…';
  @override
  String exportDone(int plugins) => 'הועתקו $plugins תוספים';
}

class _CustomAppsDomain extends CustomAppsDomainStrings {
  const _CustomAppsDomain();

  @override
  String get descriptorNotJson => 'קובץ התוסף אינו קובץ JSON תקין';
  @override
  String descriptorUnsupportedSchema(int found, int supported) =>
      'התוסף נכתב עבור גרסת פורמט $found, והתוכנה יודעת לקרוא עד $supported. '
      'יש לעדכן את התוכנה';
  @override
  String descriptorMissingField(String field) =>
      'חסר בתוסף השדה "$field", או שהוא ריק';
  @override
  String descriptorInvalidId(String id) =>
      'המזהה "$id" אינו תקין. מותרים אותיות לועזיות קטנות, ספרות, נקודה, '
      'מקף וקו תחתון בלבד';
  @override
  String descriptorUnknownSourceKind(String found, String allowed) =>
      'מקור הגרסאות "$found" אינו נתמך. המקורות הנתמכים: $allowed';

  @override
  String appAlreadyRegistered(String name) => 'התוכנה $name כבר קיימת ברשימה';
  @override
  String appNotRegistered(String id) => 'לא נמצאה תוכנה עם המזהה $id';

  @override
  String get noInstallerInMirror =>
      'אין קובץ התקנה שמור לתוכנה הזו — יש להוסיף אותו במחשב שיש בו הקובץ';
  @override
  String installerFileMissing(String path) =>
      'קובץ ההתקנה אינו נמצא: ${_ltr(path)}';
  @override
  String installerUnsupportedFile(String fileName) =>
      'הקובץ "${_ltr(fileName)}" אינו חבילת התקנה נתמכת. יש לבחור מתקין Windows מסוג EXE או MSI, או ארכיון ZIP להעתקה. ארכיון קוד מקור אינו מתקין את התוכנה. אפשר לשנות את הקובץ בעריכת התוכנה.';
  @override
  String installerExitCode(int exitCode, String output) =>
      'ההתקנה הסתיימה בשגיאה (קוד $exitCode).\n$output';
  @override
  String installerElevatedRetryFailed(
    int firstExitCode,
    int elevatedExitCode,
    String output,
  ) =>
      'ההתקנה הסתיימה בשגיאה (קוד $firstExitCode), וגם הניסיון החוזר '
      'בהרשאות מנהל נכשל (קוד $elevatedExitCode).\n$output';
  @override
  String installerElevatedRetryDeclined(int firstExitCode) =>
      'ההתקנה הסתיימה בשגיאה (קוד $firstExitCode). ניסיון חוזר בהרשאות '
      'מנהל לא בוצע: הבקשה נדחתה בחלון ההרשאות של ווינדוס, או שהגישה נחסמה.';
  @override
  String get installerCancelled =>
      'ההתקנה בוטלה באשף ההתקנה. התוכנה לא הותקנה.';
  @override
  String get installerElevationDeclined =>
      'ההתקנה דורשת הרשאות מנהל, והבקשה נדחתה או שהגישה נחסמה. כדי להתקין, '
      'יש לאשר את חלון ההרשאות של ווינדוס.';
  @override
  String get installerDigestMismatch =>
      'קובץ ההתקנה שעל הכונן פגום — הוא אינו זהה לקובץ שנשמר. יש להוריד '
      'או לצרף אותו מחדש במחשב שיש בו אינטרנט';
  @override
  String get installerUnverified =>
      'לקובץ ההתקנה אין סימן זיהוי שמור, ולכן אי אפשר לוודא שלא שונה. יש '
      'לאשר אותו לפני ההתקנה';
  @override
  String get appNotTrustedHere =>
      'התוכנה נוספה במחשב אחר. יש לאשר אותה במחשב הזה לפני ההתקנה';
  @override
  String get appNotTrustedForLaunch =>
      'פרטי התוכנה נוספו או שונו במחשב אחר. יש לאשר אותה במחשב הזה '
      'לפני ההפעלה';
  @override
  String fileCopyFailed(String error) => 'העתקת הקובץ נכשלה: $error';
  @override
  String portableFileInUse(String fileName, String error) =>
      'לא ניתן להחליף את ${_ltr(fileName)}, כנראה כי התוכנה פתוחה כרגע. יש לסגור '
      'אותה ולנסות שוב.${error.isEmpty ? '' : '\n$error'}';
  @override
  String launchFileMissing(String launchPath) =>
      'קובץ ההרצה אינו נמצא: ${_ltr(launchPath)}';
  @override
  String get launchElevationDeclined =>
      'התוכנה דורשת הרשאות מנהל, והבקשה נדחתה או שהגישה נחסמה.';

  @override
  String mediaFileMissing(String path) =>
      'קובץ התמונה אינו נמצא: ${_ltr(path)}';
  @override
  String mediaNotAnImage(String fileName) =>
      '${_ltr(fileName)} אינו קובץ תמונה. ניתן לבחור PNG, JPG, GIF, WEBP או BMP.';

  @override
  String githubStatus(int statusCode, String uri) =>
      'גיטהאב החזיר שגיאה $statusCode עבור $uri';
  @override
  String get githubBadResponse => 'התשובה מגיטהאב אינה במבנה הצפוי';
  @override
  String get githubNoReleases => 'לא נמצאו גרסאות של התוכנה באתר המפתחים';
  @override
  String githubNoMatchingAsset(String tagName) =>
      'בגרסה ${_ltr(tagName)} אין קובץ שתואם למה שנבחר. ייתכן ששם הקובץ השתנה — '
      'יש לבחור אותו מחדש';
  @override
  String downloadFailed(int statusCode) => 'ההורדה נכשלה (שגיאה $statusCode)';
  @override
  String downloadDigestMismatch(String fileName) =>
      'הקובץ ${_ltr(fileName)} שהורד אינו תואם לחתימה שגיטהאב מפרסם לו — ההורדה '
      'השתבשה. יש לנסות שוב';
  @override
  String get sourceIsNotGithub =>
      'התוכנה הזו לא נוספה מאתר המפתחים, ולכן אין מה לבדוק ברשת';
}

class _CustomApps extends CustomAppsStrings {
  const _CustomApps();

  @override
  String get screenTitle => 'תוכנות נוספות';

  // ── רשת הכרטיסים וסרגל הקטגוריות ──
  @override
  String get categoriesTitle => 'קטגוריות';
  @override
  String get allAppsItem => 'כל התוכנות';
  @override
  String get uncategorizedItem => 'ללא קטגוריה';

  // ── דף התוכנה ──
  @override
  String get aboutPanelTitle => 'על התוכנה';
  @override
  String get infoPanelTitle => 'מידע כללי';
  @override
  String get screenshotsPanelTitle => 'צילומי מסך';
  @override
  String get infoSource => 'מקור';
  @override
  String get infoSourceFile => 'קובץ שנבחר ידנית';
  @override
  String get infoInstalled => 'מותקנת במחשב הזה';
  @override
  String get infoStored => 'בכונן';
  @override
  String get infoOnline => 'ברשת';
  @override
  String get infoStoredSize => 'גודל הקובץ השמור';
  @override
  String get infoStoredAdded => 'נוסף לכונן';
  @override
  String get valueUnknown => 'לא ידוע';
  @override
  String get valueNo => 'לא';
  @override
  String get installedNoVersionValue => 'כן, הגרסה לא ידועה';
  @override
  String get notStoredValue => 'עוד לא ירד';

  // ── מצבים ריקים ──
  @override
  String get emptyCategoryTitle => 'אין כאן עדיין תוכנות';
  @override
  String get emptyCategoryBody =>
      'אפשר לשייך תוכנות לקטגוריה הזו בעריכת התוכנה, בניהול התוכנות שבהגדרות.';
  @override
  String get emptyUncategorizedTitle => 'כל התוכנות משויכות';
  @override
  String get emptyUncategorizedBody => 'אין תוכנה שאינה בקטגוריה כלשהי.';
  @override
  String categoryAppCount(int count) =>
      count == 1 ? '$count תוכנה' : '$count תוכנות';

  // ── ניהול הקטגוריות ──
  @override
  String get categoriesDialogHint =>
      'הקטגוריות נשמרות בכונן יחד עם התוכנות, ומוצגות ככפתורים מעל הרשימה.';
  @override
  String get categoryNameLabel => 'שם הקטגוריה';
  @override
  String get categoryNameHint => 'למשל: כלי לימוד';
  @override
  String get categoryDescriptionLabel => 'תיאור (לא חובה)';
  @override
  String get addCategoryButton => 'הוספת קטגוריה';
  @override
  String get editCategoryTitle => 'עריכת הקטגוריה';
  @override
  String get noCategoriesHint =>
      'עוד לא הוגדרו קטגוריות. בלעדיהן המסך מציג את כל התוכנות יחד.';
  @override
  String get removeCategoryTooltip => 'מחיקת הקטגוריה';
  @override
  String removeCategoryDialogTitle(String name) => 'למחוק את "$name"?';
  @override
  String removeCategoryDialogContent(String name, int count) =>
      'הקטגוריה "$name" תימחק. $count תוכנות ישויכו שוב ל"ללא קטגוריה" — '
      'שום תוכנה אינה נמחקת ושום קובץ אינו נמחק מהכונן.';
  @override
  String categoryRemovedSnack(String name) => 'הקטגוריה "$name" נמחקה';

  // ── מדיה וקטגוריות בטופס ──
  @override
  String get appCategoriesLabel => 'קטגוריות';
  @override
  String get appCategoriesHint =>
      'אפשר לשייך את התוכנה לכמה קטגוריות, או לאף אחת.';
  @override
  String get longDescriptionLabel => 'תיאור מלא (לא חובה)';
  @override
  String get longDescriptionHint =>
      'מה התוכנה עושה, למי היא מיועדת וכל מה שכדאי לדעת. מוצג בדף התוכנה.';
  @override
  String get iconLabel => 'סמל';
  @override
  String get pickIconButton => 'בחירת תמונה';
  @override
  String get pickIconDialogTitle => 'בחירת תמונה לסמל';
  @override
  String get removeIconTooltip => 'הסרת הסמל';
  @override
  String get extractIconButton => 'חילוץ מהקובץ';
  @override
  String extractedIconSnack(String fileName) =>
      'הסמל חולץ מתוך ${_ltr(fileName)}';
  @override
  String get extractIconFailedSnack =>
      'לא נמצא סמל בקובץ. אפשר לבחור תמונה ידנית.';
  @override
  String get moveScreenshotBackTooltip => 'הזזה אחורה';
  @override
  String get moveScreenshotForwardTooltip => 'הזזה קדימה';
  @override
  String get screenshotsLabel => 'צילומי מסך';
  @override
  String get addScreenshotsButton => 'הוספת צילומי מסך';
  @override
  String get pickScreenshotsDialogTitle => 'בחירת צילומי מסך';
  @override
  String get removeScreenshotTooltip => 'הסרת התמונה';
  @override
  String screenshotsChosen(int count) =>
      count == 1 ? '$count תמונה' : '$count תמונות';

  @override
  String get settingsCardTitle => 'תוכנות נוספות';
  @override
  String get manageRowTitle => 'ניהול';
  @override
  String manageRowSubtitle(int count) =>
      '${count == 1 ? '$count תוכנה' : '$count תוכנות'} בכונן · הוספה, עריכה, סידור וקטגוריות';
  @override
  String get emptyHint => 'עוד לא נוספו תוכנות · הוספה, עריכה, סידור וקטגוריות';
  @override
  String get addButton => 'הוספת תוכנה';
  @override
  String get openManagerButton => 'ניהול התוכנות';

  // ── מסך הניהול ──
  @override
  String get manageDialogTitle => 'ניהול התוכנות הנוספות';
  @override
  String get manageDialogHint => 'התוכנות שנשמרות בכונן, הסדר שלהן והקטגוריות.';
  @override
  String get orderHint =>
      'גרור שורה בידית אל מקומה של שורה אחרת, או השתמש בחיצים. זה הסדר שבו התוכנות מוצגות, והוא נשמר בכונן.';
  @override
  String get moveAppEarlierTooltip => 'הזזה למקום הקודם';
  @override
  String get moveAppLaterTooltip => 'הזזה למקום הבא';
  @override
  String get dragToReorderTooltip => 'גרירה לשינוי הסדר';

  @override
  String get addDialogTitle => 'הוספת תוכנה';
  @override
  String get editDialogTitle => 'עריכת התוכנה';
  @override
  String get nameLabel => 'שם התוכנה';
  @override
  String get nameHint => 'כפי שיוצג לך ברשימה';
  @override
  String get descriptionLabel => 'תיאור קצר';
  @override
  String get descriptionHint => 'שורה קצרה שתזכיר לך מה זה';
  @override
  String get installDirLabel => 'תיקיית ההתקנה';
  @override
  String get installDirHint =>
      'אפשר להשאיר ריק — אחרי ההתקנה הראשונה המיקום יימצא לבד.';
  @override
  String get pickInstallDirButton => 'בחירה…';
  @override
  String get pickInstallDirDialogTitle => 'בחירת תיקיית ההתקנה';

  @override
  String get githubUrlLabel => 'כתובת התוכנה באתר המפתחים';
  @override
  String get githubUrlHint => 'למשל github.com/owner/repo';
  @override
  String get githubUrlInvalid => 'זו לא כתובת של תוכנה באתר המפתחים (GitHub)';
  @override
  String get fetchAssetsButton => 'הצגת הקבצים';
  @override
  String get assetHint =>
      'בגרסה אחת יש בדרך כלל כמה קבצים. בחר את זה שמתאים למחשב שלך.';
  @override
  String get noAssetsFound => 'אין קבצים להורדה בגרסה הזו';
  @override
  String assetsFromRelease(String tagName) => 'הקבצים בגרסה ${_ltr(tagName)}:';

  @override
  String get pickInstallerButton => 'בחירה…';
  @override
  String get pickInstallerDialogTitle => 'בחירת קובץ ההתקנה';
  @override
  String installerKindSniffed(String kind) => 'זוהה: $kind';
  @override
  String get portableFileLabel => 'הקובץ הוא התוכנה עצמה';
  @override
  String get interactiveInstallLabel => 'התקנה רגילה במקום התקנה מהירה';
  @override
  String get interactiveInstallHint =>
      'לתוכנות שאינן תומכות בהתקנה שקטה. ייפתח אשף התקנה שבו תבחרו את מיקום ההתקנה ותסיימו את השלבים בעצמכם.';
  @override
  String get portableFileHint =>
      'סמן כשהקובץ אינו מתקין אלא התוכנה עצמה. בהתקנה תישאל לאן להעתיק '
      'אותו, במקום להריץ אותו.';
  @override
  String get portableDestinationHint =>
      'איפה לשמור את התוכנה בכל מחשב — בזמן ההתקנה תתבקש לבחור תיקייה.';
  @override
  String get pickCopyTargetDialogTitle => 'לאן להעתיק את הקובץ';
  @override
  String copiedFileSnack(String path) => 'הקובץ הועתק אל ${_ltr(path)}';
  @override
  String get exeNameLabel => 'שם קובץ ההרצה';
  @override
  String get exeNameHint =>
      'אפשר להשאיר ריק — אחרי ההתקנה הראשונה נלמד את השם לבד';

  @override
  String get githubAssetKept =>
      'הקובץ שנבחר כאן בעבר יישאר. להחלפה — הצג את הקבצים ובחר אחר.';
  @override
  String installerKept(String fileName) =>
      'הקובץ השמור, ${_ltr(fileName)}, יישאר. להחלפה — בחר קובץ אחר.';

  @override
  String get saveButton => 'הוספה לכונן';
  @override
  String get saveEditButton => 'שמירה';
  @override
  String get nameRequired => 'יש להזין שם לתוכנה';
  @override
  String get sourceRequired => 'יש לבחור קובץ, או כתובת וקובץ מתוכה';
  @override
  String addedSnack(String name) => '$name נוספה';
  @override
  String updatedSnack(String name) => '$name עודכנה';

  @override
  String get kindInno => 'קובץ התקנה רגיל';
  @override
  String get kindNsis => 'קובץ התקנה רגיל';
  @override
  String get kindMsi => 'קובץ התקנה רגיל';
  @override
  String get kindZip => 'קובץ דחוס (ZIP)';
  @override
  String get kindPortableFile => 'הקובץ עצמו, ללא התקנה';
  @override
  String get kindInteractive =>
      'קובץ התקנה מסוג לא מוכר — ייפתח חלון התקנה רגיל';

  @override
  String get noStoredInstaller => 'עוד לא הורד קובץ התקנה';

  @override
  String get downloadButton => 'הורדה לכונן';
  @override
  String get downloadingLabel => 'מוריד…';
  @override
  String get checkOnlineButton => 'בדיקה ברשת';
  @override
  String get checkAllOnlineButton => 'בדיקה ברשת לכל התוכנות';
  @override
  String checkingAllOnlineLabel(int done, int total) =>
      'בודק ברשת… ($done/$total)';
  @override
  String checkAllOnlineSummary(int updates, int checked) =>
      'נבדקו $checked תוכנות — ל-$updates יש ברשת גרסה חדשה יותר';
  @override
  String checkAllOnlineNoUpdates(int checked) =>
      'נבדקו $checked תוכנות — מה שעל הכונן מעודכן';
  @override
  String get checkAllOnlineAllFailed =>
      'הבדיקה לא הצליחה לאף תוכנה — כנראה אין חיבור לרשת';
  @override
  String checkAllOnlineSomeFailed(int failed) =>
      'ל-$failed תוכנות הבדיקה לא הצליחה.';
  @override
  String get downloadAllButton => 'הורדת כל העדכונים';
  @override
  String downloadingAllLabel(int done, int total) =>
      'מוריד עדכונים… ($done/$total)';
  @override
  String downloadAllDoneSnack(int downloaded) =>
      'הורדו לכונן עדכונים ל-$downloaded תוכנות';
  @override
  String downloadAllNothingNew(int checked) =>
      'נבדקו $checked תוכנות — אין מה להוריד, מה שעל הכונן מעודכן';
  @override
  String downloadAllSomeFailed(int failed) =>
      'ל-$failed תוכנות ההורדה לא הצליחה.';
  @override
  String onlineVersionAvailable(String version) =>
      'ברשת יש גרסה ${_ltr(version)}';
  @override
  String get onlineUpToDate => 'מה שעל הכונן הוא הגרסה האחרונה';
  @override
  String get onlineUnavailable => 'אין חיבור לרשת כרגע';
  @override
  String get pickLocationButton => 'בחירת מיקום ידנית';
  @override
  String locationAdoptedSnack(String dir) => 'התוכנה נמצאה ב-${_ltr(dir)}';
  @override
  String get locationNotFoundSnack =>
      'לא נמצאה שם התקנה של התוכנה. בדוק שבחרת את התיקייה הנכונה.';

  @override
  String installedSnack(String name) => '$name הותקנה';
  @override
  String get trustDialogTitle => 'להתקין תוכנה שלא נבדקה?';
  @override
  String trustDialogContent(String name, String source) =>
      '"$name" נוספה לכונן במחשב אחר, ואין לה אישור מהמחשב הזה. '
      'התקן רק אם אתה סומך על מי שהוסיף אותה${source == name ? '' : ' ($source)'}.';
  @override
  String get trustDialogConfirm => 'התקנה בכל זאת';
  @override
  String get unverifiedDialogTitle => 'להתקין קובץ שלא נבדק?';
  @override
  String unverifiedDialogContent(String fileName) =>
      'לא שמרנו לקובץ ${_ltr(fileName)} סימן זיהוי, ולכן אי אפשר לוודא שהוא לא שונה. '
      'אם תמשיך, הסימן יחושב ויישמר, ומכאן כל שינוי בקובץ ייחסם.';
  @override
  String get unverifiedDialogConfirm => 'התקנה בכל זאת';
  @override
  String get learningLabel => 'מזהה את ההתקנה…';
  @override
  String learnedDetectionSnack(String exeName) =>
      'מעתה נזהה את התוכנה לבד, לפי ${_ltr(exeName)}';
  @override
  String archiveInDownloadsSnack(String path) =>
      'הקובץ הועתק לתיקיית ההורדות: ${_ltr(path)}';
  @override
  String downloadedSnack(String version) => 'גרסה ${_ltr(version)} ירדה לכונן';

  @override
  String get editTooltip => 'עריכה';
  @override
  String get removeTooltip => 'הסרה מהכונן';
  @override
  String removeDialogTitle(String name) => 'להסיר את "$name" מהכונן?';
  @override
  String removeDialogContent(String name) =>
      '"$name" תוסר מהרשימה והקובץ שבכונן יימחק. '
      'התוכנה לא תוסר ממחשבים שכבר התקינו אותה.';
  @override
  String get removeDialogConfirm => 'הסרה';
  @override
  String removedSnack(String name) => '$name הוסרה';

  @override
  String get screenSubtitle =>
      'תוכנות שנשמרו בכונן כדי להתקין אותן גם במחשבים בלי אינטרנט.';
  @override
  String get showAllAppsButton => 'הצגת כל התוכנות';
  @override
  String get sourceGithubShort => 'מאתר המפתחים (GitHub)';
  @override
  String get sourceFileShort => 'מקובץ';
  @override
  String versionLabel(String version) => 'גרסה ${_ltr(version)}';
  @override
  String updateToButton(String version) => 'עדכון ל-${_ltr(version)}';
  @override
  String get onlineNotChecked => 'עוד לא נבדק';
  @override
  String get emptyReadOnlyBody =>
      'הכונן הזה מוגן מכתיבה, ולכן אי אפשר להוסיף אליו תוכנות.';
  @override
  String get manageEmptyTitle => 'עוד לא נוספו תוכנות';
  @override
  String get manageEmptyBody =>
      'אפשר לשמור בכונן תוכנה שתרצה להתקין גם במחשבים בלי אינטרנט — מקובץ שיש במחשב, או מאתר המפתחים (GitHub) כדי שתתעדכן לבד.';
  @override
  String get noCategoriesTitle => 'אין קטגוריות';
  @override
  String get orderSectionTitle => 'התוכנות לפי הסדר שבו הן מוצגות';
  @override
  String get formStepSource => 'מאיפה התוכנה?';
  @override
  String get formStepGithubFile => 'איזה קובץ?';
  @override
  String get formStepLocalFile => 'בחירת הקובץ';
  @override
  String get formStepDetails => 'פרטי התוכנה';
  @override
  String get sourceGithubOption => 'מאתר המפתחים — GitHub (מומלץ)';
  @override
  String get sourceGithubOptionHint => 'התוכנה תתעדכן לבד בכל הורדה לכונן.';
  @override
  String get sourceFileOption => 'קובץ שיש במחשב הזה';
  @override
  String get sourceFileOptionHint => 'קובץ התקנה, או תוכנה שלא צריך להתקין.';
  @override
  String get fileLabel => 'הקובץ';
}

String _reports(int count) => count == 1 ? '1 דיווח' : '$count דיווחים';

class _ErrorReports extends ErrorReportsStrings {
  const _ErrorReports();

  @override
  String get collectDialogTitle => 'דיווחים שלא נשלחו';
  @override
  String collectDialogContent(int count) =>
      'נמצאו באוצריא ${_reports(count)} על ספרים, התוכנה ותוספים שעדיין לא נשלחו.\n\n'
      'לאסוף אותם לכונן, כדי לשלוח אותם לאוצריא מהמחשב המחובר לרשת?\n\n'
      'שימו לב: הדיווחים נשמרים בכונן כמו שהם, בלי הצפנה, עד שיישלחו — '
      'כתובת המייל, הטקסט שכתבתם, קטעי יומן, צילומי מסך, ובדיווח על קריסה '
      'שאישרתם גם תמונת זיכרון (dump). מי שמחזיק בכונן יכול לקרוא אותם.';
  @override
  String get collectConfirm => 'איסוף';
  @override
  String get collectLater => 'לא עכשיו';
  @override
  String collectedSnack(int count) =>
      'נאספו לכונן ${_reports(count)}. הם יישלחו מהמחשב המחובר לרשת';
  @override
  String collectPartialSnack(int count, String error) =>
      'נאספו ${_reports(count)}, אבל לא כולם: $error';
  @override
  String collectFailedSnack(String error) => 'איסוף הדיווחים נכשל: $error';
  @override
  String get collectDisclosureRefreshedSnack =>
      'נמצא מידע נוסף לאיסוף — עיין בפירוט שמעל הכפתור ולחץ שוב.';
  @override
  String get collectOtzariaOpenSnack =>
      'אוצריא פתוחה, ולכן הדיווחים לא נאספו. השאלה תחזור כשאוצריא תיסגר';
  @override
  String get legacyReportsDialogTitle => 'נמצאו דיווחים ישנים שאי אפשר לשלוח';
  @override
  String get legacyReportsDialogContent =>
      'גרסה ישנה של אוצריא שמרה אותם בצורה שכבר לא נשלחת. שאר הדיווחים נשלחים '
      'כרגיל.';

  @override
  String get introDialogTitle => 'דיווחים לאוצריא ולמפתחי התוספים';
  @override
  String get introDialogContent =>
      'אוצריא שומרת דיווחי טעויות בספרים, תקלות בתוכנה ודיווחים על תוספים '
      'שלא נשלחו כשאין רשת.\n\n'
      'התוכנה יכולה לאסוף אותם לכונן, ולשלוח אותם לאוצריא מהמחשב המחובר '
      'לרשת.';
  @override
  String get introDialogContentReadOnly =>
      'אוצריא שומרת דיווחי טעויות בספרים, תקלות בתוכנה ודיווחים על תוספים '
      'שלא נשלחו כשאין רשת.\n\n'
      'הכונן הזה מוגן מפני כתיבה, ולכן אי אפשר לאסוף דרכו דיווחים.';
  @override
  String get introDialogContentReadOnlyDriveFull =>
      'אוצריא שומרת דיווחי טעויות בספרים, תקלות בתוכנה ודיווחים על תוספים '
      'שלא נשלחו כשאין רשת.\n\n'
      'הכונן הזה מלא, ולכן אי אפשר לאסוף אליו דיווחים עד שיתפנה בו מקום.';
  @override
  String get introDialogConfirm => 'הבנתי';

  @override
  String get uploadLongDialogTitle => 'שליחת הדיווחים';
  @override
  String uploadLongDialogContent(int count, int perMinute, int minutes) =>
      'בכונן ${_reports(count)}. אוצריא מקבלת עד $perMinute דיווחים '
      'בדקה, ולכן השליחה תימשך כ-$minutes דקות.\n\n'
      'אפשר לעצור באמצע, ובפעם הבאה השליחה תמשיך מהמקום שבו נעצרה.';
  @override
  String get uploadLongDialogConfirm => 'התחלה';
  @override
  String uploadingStage(int done, int total) =>
      'שולח דיווחים · $done מתוך $total';
  @override
  String uploadWaitingStage(int seconds) =>
      'ממתין לאתר אוצריא — ממשיך בעוד $seconds שניות';
  @override
  String get uploadStopButton => 'עצירה';
  @override
  String uploadPendingOffline(int count) =>
      '${count == 1 ? 'ממתין' : 'ממתינים'} להעלאה ${_reports(count)}. אין חיבור לרשת, ולכן אין כפתור העלאה';
  @override
  String uploadPendingUnchecked(int count) =>
      '${count == 1 ? 'ממתין' : 'ממתינים'} להעלאה ${_reports(count)}. טרם נבדק חיבור לרשת — בדקו חיבור כדי להעלות';
  @override
  String get uploadingFeedbackStage => 'שולח את נתוני השיפור של החיפוש החכם…';
  @override
  String get uploadCollectingBusy =>
      'איסוף דיווחים מתבצע כעת. נסה שוב בעוד רגע';
  @override
  String get uploadUnexpectedFailure => 'השליחה נכשלה. הפרטים ביומן הפעילות';
  @override
  String uploadSummary(int sent, int rejected, int remaining) => [
        sent == 1 ? 'נשלח 1 דיווח' : 'נשלחו $sent דיווחים',
        if (rejected > 0)
          rejected == 1
              ? 'אחד נדחה באתר אוצריא ונמחק'
              : '$rejected נדחו באתר אוצריא ונמחקו',
        if (remaining > 0)
          remaining == 1
              ? 'אחד ממתין לפעם הבאה'
              : '$remaining ממתינים לפעם הבאה',
      ].join(', ');
  @override
  String uploadFailedSnack(String error) => 'השליחה נעצרה: $error';
}

class _ErrorReportsDomain extends ErrorReportsDomainStrings {
  const _ErrorReportsDomain();

  @override
  String get queueUnreadable => 'לא ניתן היה לקרוא את תור הדיווחים של אוצריא';
  @override
  String get someNotCollected => 'הדיווחים שלא נאספו נשארו באוצריא';

  @override
  String uploadHttpStatus(int statusCode) =>
      'אתר אוצריא השיב בקוד שגיאה $statusCode';
  @override
  String get uploadShabbat =>
      'אתר אוצריא סגור בשבת ובימים טובים. הדיווחים נשמרו בכונן ויישלחו בפעם הבאה, אחרי צאת השבת.';
  @override
  String get uploadTimedOut => 'אתר אוצריא לא השיב בזמן';
  @override
  String uploadNetworkError(String error) => 'אין חיבור לאתר אוצריא: $error';
  @override
  String outboxUnreadable(String error) =>
      'לא ניתן לקרוא את הדיווחים שעל הכונן: $error';
}

class _AppReports extends AppReportsStrings {
  const _AppReports();

  @override
  String get crashModeTitle => 'אחרי סגירה לא צפויה של הכלי';
  @override
  String get crashModeSubtitle =>
      'דיווח קצר למפתחים: פרטי הגרסה והמערכת, קטע מיומן הפעילות וכתובת הדואר '
      'ששמרת בטופס, אם יש. נתיבים ושם המשתמש מוסתרים.';
  @override
  String get crashModeAsk => 'לשאול';
  @override
  String get crashModeAlways => 'לשלוח תמיד';
  @override
  String get crashModeNever => 'לא לשלוח';
  @override
  String get manageTileTitle => 'דיווחים על תקלות';
  @override
  String manageTileSubtitle(int pending, int sent) => pending == 0
      ? 'אין דיווחים שמורים בתור · $sent נשלחו'
      : '$pending שמורים בתור · $sent נשלחו';

  @override
  String get manageDialogIntro =>
      'דיווחים על הכלי הזה עצמו. התיאור מתפרסם באתר המפתחים ואפשר לקרוא אותו, '
      'וקובצי האבחון גלויים למפתחים בלבד.';
  @override
  String get sendNowButton => 'שליחה עכשיו';
  @override
  String get clearPendingButton => 'מחיקת הכול';
  @override
  String get sendOneButton => 'שליחה';
  @override
  String get deleteButton => 'מחיקה';
  @override
  String get detailsButton => 'פרטים';
  @override
  String get sentSectionTitle => 'דיווחים שנשלחו';
  @override
  String sentSummary(int shown, int total) => shown == total
      ? (total == 1 ? 'נשלח $total דיווח' : 'נשלחו $total דיווחים')
      : 'נשלחו $total דיווחים; מוצגים $shown האחרונים';
  @override
  String get clearSentButton => 'ניקוי ההיסטוריה';
  @override
  String openIssueButton(int? number) =>
      number == null ? 'פתיחת הדיווח' : 'פתיחת דיווח #$number';
  @override
  String get mergedLabel => 'צורף לדיווח קיים';
  @override
  String get detailsPendingTitle => 'פרטי דיווח שמור';
  @override
  String get detailsSentTitle => 'פרטי דיווח שנשלח';
  @override
  String get stepsHeading => 'מה הוביל לתקלה:';
  @override
  String get clearPendingDialogTitle => 'למחוק את הדיווחים השמורים?';
  @override
  String get clearPendingDialogContent =>
      'הדיווחים שבתור לא יישלחו. אי אפשר לבטל את הפעולה.';
  @override
  String get clearSentDialogTitle => 'לנקות את היסטוריית הדיווחים?';
  @override
  String get clearSentDialogContent =>
      'הפעולה לא מוחקת דיווחים שכבר נשלחו למפתחים.';
  @override
  String flushSentSnack(int count) =>
      count == 1 ? 'נשלח $count דיווח' : 'נשלחו $count דיווחים';
  @override
  String flushFailedSnack(int pending) => pending == 1
      ? 'לא ניתן לשלוח כרגע. $pending דיווח עדיין שמור בתור, והוא יישלח '
          'אוטומטית כשיהיה חיבור.'
      : 'לא ניתן לשלוח כרגע. עדיין שמורים בתור $pending דיווחים, והם יישלחו '
          'אוטומטית כשיהיה חיבור.';
  @override
  String flushErrorSnack(int failed) => failed == 1
      ? 'השליחה נכשלה בגלל שגיאה במחשב הזה ($failed דיווח). הדיווח נשאר '
          'בתור, והפרטים ביומן.'
      : 'השליחה נכשלה בגלל שגיאה במחשב הזה ($failed דיווחים). הדיווחים נשארו '
          'בתור, והפרטים ביומן.';
  @override
  String flushPartialSnack(int sent, int failed) =>
      '${flushSentSnack(sent)}. ${failed == 1 ? '$failed דיווח לא נשלח בגלל '
          'שגיאה במחשב הזה ונשאר בתור' : '$failed דיווחים לא נשלחו בגלל שגיאה '
          'במחשב הזה ונשארו בתור'}; הפרטים ביומן.';
  @override
  String flushDroppedSnack(int sent, int dropped) =>
      '${flushSentSnack(sent)}. ${dropped == 1 ? '$dropped דיווח נדחה '
          'והוסר מהתור' : '$dropped דיווחים נדחו והוסרו '
          'מהתור'}.';
  @override
  String flushRemainingSnack(int sent, int remaining) =>
      '${flushSentSnack(sent)}. ${remaining == 1 ? 'נשאר עוד $remaining '
          'דיווח בתור — הוא יישלח' : 'נשארו עוד $remaining דיווחים בתור — הם '
          'יישלחו'} אוטומטית, או שאפשר ללחוץ שוב.';
  @override
  String get notPendingSnack =>
      'הדיווח כבר אינו בתור (נשלח או הוסר), ולכן לא נשלח שוב.';
  @override
  String get removedFromQueueSnack => 'הדיווח הוסר מהתור';
  @override
  String get deletedFromHistorySnack => 'הדיווח נמחק מההיסטוריה';
  @override
  String get pendingClearedSnack => 'הדיווחים השמורים נמחקו';
  @override
  String get historyClearedSnack => 'ההיסטוריה נוקתה';

  @override
  String get typeBug => 'תקלה';
  @override
  String get typeCrash => 'קריסה';
  @override
  String get typePerformance => 'ביצועים';
  @override
  String get typeSuggestion => 'הצעה';

  @override
  String get dialogTitle => 'דיווח על תקלה בתוכנה';
  @override
  String get dialogSubtitle =>
      'ככל שהתיאור מדויק יותר, כך קל יותר לאתר את התקלה ולתקן אותה';
  @override
  String get typeLabel => 'סוג הדיווח';
  @override
  String get titleLabel => 'כותרת';
  @override
  String get titleHint => 'משפט אחד שמתאר את הבעיה';
  @override
  String get titleRequired => 'יש למלא כותרת';
  @override
  String get descriptionLabel => 'מה קרה?';
  @override
  String get descriptionHint => 'מה ציפית שיקרה, ומה קרה בפועל';
  @override
  String get descriptionRequired => 'יש לתאר את התקלה';
  @override
  String get stepsLabel => 'מה הוביל לתקלה';
  @override
  String get stepsHint => 'מה עשית לפני שהתקלה הופיעה';
  @override
  String get optionalHint => '(לא חובה)';
  @override
  String get emailLabel => 'דואר אלקטרוני לחזרה אליך';
  @override
  String get emailInvalid => 'נדרשת כתובת תקינה';
  @override
  String get sendButton => 'שליחה';

  @override
  String get imagesPrompt => 'לחץ כאן לבחירת צילום מסך';
  @override
  String get imagesPickDialogTitle => 'בחירת צילומי מסך לדיווח';
  @override
  String get removeImageTooltip => 'הסרת התמונה';
  @override
  String imageTooLarge(int megabytes) =>
      'תמונה גדולה מ-\u2066$megabytes\u00a0MB\u2069 לא צורפה.';
  @override
  String tooManyImages(int count) => 'ניתן לצרף עד $count תמונות לדיווח.';
  @override
  String imagesTotalTooLarge(int megabytes) =>
      'הגודל הכולל של התמונות מוגבל ל-\u2066$megabytes\u00a0MB\u2069.';

  @override
  String get imageReadFailed => 'לא ניתן היה לקרוא את התמונה.';

  @override
  String get attachmentsHeading => 'מה נשלח יחד עם הדיווח';
  @override
  String get includeDiagnostics => 'לצרף מידע אבחון על התוכנה והמערכת';
  @override
  String get diagnosticsUnavailable => 'לא ניתן היה לאסוף מידע אבחון';
  @override
  String get includeLog => 'לצרף קטע מיומן הפעילות';
  @override
  String get logEmpty => 'אין רשומות ביומן הפעילות';
  @override
  String get showPreviewButton => 'הצגת מה שיישלח';
  @override
  String get hidePreviewButton => 'הסתרת מה שיישלח';
  @override
  String get privacyNote =>
      'הכותרת, התיאור, פרטי הגרסה וצילומי המסך נכנסים למעקב התקלות של '
      'התוכנה באתר המפתחים (GitHub). מידע האבחון, יומן הפעילות וכתובת הדואר נשארים אצל '
      'צוות אוצריא בלבד. נתיבים, שם המשתמש וכתובות דואר מוסתרים לפני השליחה.';

  @override
  String sentSnack(int? issueNumber) => issueNumber == null
      ? 'הדיווח נקלט. תודה!'
      : 'הדיווח נקלט ונפתח עבורו דיווח מספר $issueNumber. תודה!';
  @override
  String mergedSnack(int? issueNumber) => issueNumber == null
      ? 'הדיווח צורף לדיווח קיים על אותה תקלה. תודה!'
      : 'הדיווח צורף לדיווח קיים מספר $issueNumber על אותה תקלה. תודה!';
  @override
  String get queuedSnack =>
      'לא ניתן לשלוח כעת. הדיווח נשמר ויישלח אוטומטית כשיהיה חיבור. '
      'ניתן לנהל את הדיווחים השמורים בהגדרות.';
  @override
  String rejectedSnack(String? field) => field == null
      ? 'הדיווח נדחה, ולכן הוא לא נשמר לשליחה חוזרת.'
      : 'הדיווח נדחה בגלל השדה "$field", ולכן הוא לא נשמר לשליחה '
          'חוזרת.';
  @override
  String get titleRequiredSnack => 'יש למלא כותרת לדיווח.';
  @override
  String get descriptionRequiredSnack => 'יש לתאר את התקלה כדי שנוכל לטפל בה.';
  @override
  String get emailRequiredSnack =>
      'יש למלא כתובת דואר אלקטרוני תקינה — בלעדיה לא נוכל לחזור אליך.';
  @override
  String get invalidEmailSnack => 'כתובת הדואר האלקטרוני אינה תקינה.';
  @override
  String get cannotOpenIssueSnack => 'לא ניתן לפתוח את הדיווח בדפדפן.';
  @override
  String get sendFailedSnack => 'שליחת הדיווח נכשלה.';

  @override
  String get crashTitle => 'התוכנה נסגרה באופן לא צפוי';
  @override
  String get crashBody =>
      'בהפעלה הקודמת התוכנה נסגרה בלי סגירה מסודרת. שליחת דיווח תעזור לנו '
      'למצוא את הסיבה ולתקן אותה.';
  @override
  String get crashDescriptionLabel => 'מה עשית לפני הסגירה? (לא חובה)';
  @override
  String get crashEmailLabel => 'דואר אלקטרוני (לא חובה)';
  @override
  String get crashNextTimeLabel => 'בפעם הבאה שזה יקרה:';
  @override
  String get crashNextAsk => 'לשאול אותי';
  @override
  String get crashNextAlways => 'תמיד לשלוח אוטומטית';
  @override
  String get crashNextNever => 'לא לשאול שוב';
  @override
  String get crashDismissButton => 'לא לשלוח';
  @override
  String get crashSendButton => 'שליחת דיווח';
  @override
  String get crashDismissedSnack =>
      'הדיווח על הקריסה לא נשלח. ניתן לדווח בכל עת דרך ההגדרות.';
  @override
  String get crashFallbackTitle => 'סגירה לא צפויה';
  @override
  String get crashAutoSentSnack =>
      'הכלי נסגר בפעם הקודמת באופן לא צפוי. דיווח קצר נשלח למפתחים, או יישלח '
      'כשיהיה חיבור. אפשר לשנות זאת בהגדרות.';
}

/// "כ-3 עד 5 דקות"; טווח שהתמזג — "כשתי דקות", לא "כ-2 עד 2 דקות".
String _minutesRange(int low, int high) => low == high
    ? plural(low, one: 'כדקה', two: 'כשתי דקות', many: 'כ-$low דקות')
    : 'כ-$low עד $high דקות';
