import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';
import '../models/app_detect_rules.dart';
import '../models/registry_display_name_pattern.dart';

/// רישום הסרה של ווינדוס, כפי שהלמידה צריכה אותו.
///
/// שקוף למי שקורא את `WindowsInstallRegistry.entries()` בלאנצ'ר — החבילה
/// הזו אינה תלויה ב-`otzaria_manager` ואינה יכולה לקבל את הטיפוס שלו.
class UninstallEntry {
  const UninstallEntry({
    required this.keyName,
    required this.displayName,
    this.installDir,
  });

  /// שם המפתח תחת `…\Uninstall`. **זו הזהות שמשווים לפניה ואחריה** — ה-
  /// `DisplayName` מכיל בדרך כלל את מספר הגרסה, ולכן משתנה עם כל עדכון.
  final String keyName;

  final String displayName;

  /// תיקיית ההתקנה, או `null` כשהמתקין לא רשם אחת שקיימת בפועל.
  final String? installDir;
}

/// כל רישומי ההסרה שיש **כרגע**. מוזרק, כמו שאר התפרים של החבילה: הקריאה
/// דורשת win32, והלאנצ'ר כבר מחזיק אותה.
typedef UninstallEntriesLookup = Future<List<UninstallEntry>> Function();

/// מחזיר את נתיב ההרצה של התוכנה בתוך [dir], או `null`.
///
/// [nameHints] הם רמזים לשם — שם התוכנה ושם קובץ ההתקנה. גם הוא מוזרק, כדי
/// שהמימוש יהיה `OtzariaAppLocator` הקיים והמאומת ולא סורק שני: **"ה-exe
/// הראשון בתיקייה" הוא באג מתועד** בריפו הזה (`crashpad_handler.exe`, שגם
/// מקדים באלף-בית וגם נושא שדה גרסה משל עצמו).
typedef LearnedExeLookup = Future<String?> Function(
  String dir,
  List<String> nameHints,
);

/// לומד **כיצד לזהות** תוכנה נוספת, מיד אחרי שהותקנה בפעם הראשונה.
///
/// זה קיים כדי שהטופס לא ישאל שתי שאלות שאי אפשר לענות עליהן: "לאן התוכנה
/// מותקנת" ו"איך נקרא קובץ ההרצה שלה". במחשב המקוון, שבו מוסיפים את התוכנה,
/// היא בכלל אינה מותקנת — אין על מה להצביע. אחרי ההתקנה במחשב המנותק שתי
/// התשובות שוכבות על הדיסק, וכאן הן נאספות.
///
/// **מה שנלמד נכתב לרשומה, ולכן הוא חייב להיות בלתי-תלוי במחשב:** שם קובץ
/// ההרצה ותבנית ה-`DisplayName` הם עובדות על התוכנה, ונוסעות היטב על הכונן.
/// **תיקיית ההתקנה אינה כזו** — היא נרשמת ל-`locations.json` שהוא פר-מחשב
/// (ראו `KnownLocationsStore`), ולא לרשומה. רשומה שנוסעת ומכריזה על נתיב
/// מוחלט היא בדיוק המחלה של `otzaria_install_state.json`.
class InstallLearner {
  const InstallLearner({
    this.lookupUninstallEntries,
    this.lookupExe,
    this.onStart,
    Future<void> Function(Duration)? sleep,
    this.timeout = defaultTimeout,
    this.firstPollDelay = defaultFirstPollDelay,
    this.maxPollDelay = defaultMaxPollDelay,
  }) : _sleep = sleep;

  /// נקרא כשהלמידה מתחילה בפועל — כלומר יש מה ללמוד ומתחילה ההמתנה לרישום.
  /// הממשק תולה בזה הודעה, כי ההמתנה יכולה להימשך עד [timeout] ובלי הודעה
  /// היא נראית כתקיעה.
  final void Function()? onStart;

  /// `null` בפלטפורמה בלי רג'יסטרי — אז נשארים עם מסלול הגיבוי לפי תיקייה.
  final UninstallEntriesLookup? lookupUninstallEntries;

  final LearnedExeLookup? lookupExe;

  final Future<void> Function(Duration)? _sleep;

  /// כמה זמן להמתין להופעת רישום ההסרה.
  ///
  /// ⚠️ **קוד יציאה 0 אינו אומר שההתקנה הסתיימה.** `setup.exe` של Inno מחלץ
  /// עותק זמני ומשגר תהליך שני (ובוודאי כשיש הרמת הרשאות), ולכן התהליך
  /// שהרצנו עלול לחזור לפני שהרישום נכתב. צילום בודד מיד אחרי ההרצה היה
  /// קורא מוקדם מדי ולא לומד כלום.
  final Duration timeout;

  /// הסקירה החוזרת מתחילה מהיר ומאטה. סריקת הרג'יסטרי עולה ~200ms, ולולאה
  /// צמודה על פני דקה הייתה שורפת שניות CPU על תשובה שברוב הזמן לא השתנתה.
  final Duration firstPollDelay;
  final Duration maxPollDelay;

  static const Duration defaultTimeout = Duration(seconds: 60);
  static const Duration defaultFirstPollDelay = Duration(milliseconds: 500);
  static const Duration defaultMaxPollDelay = Duration(seconds: 4);

  /// מה שיש **לפני** ההתקנה. רשימה ריקה כשאין תפר — אז [learn] מדלג ישר
  /// למסלול הגיבוי לפי תיקיית ההתקנה המוצהרת.
  Future<List<UninstallEntry>> snapshot() async {
    final lookup = lookupUninstallEntries;
    if (lookup == null) return const [];
    try {
      return await lookup();
    } catch (_) {
      // אין הרשאה, או פלטפורמה אחרת. למידה שלא הצליחה אינה כשל התקנה.
      return const [];
    }
  }

  /// מה שנלמד, ממוזג לתוך כללי הזיהוי הקיימים — או `null` כשלא נלמד כלום.
  ///
  /// **שדה שהמשתמש מילא בעצמו לא נדרס.** הוא ראה את ההתקנה שלו ואנחנו לא;
  /// הלמידה ממלאת חורים, לא מתקנת אנשים.
  Future<AppDetectRules?> learn({
    required AppDescriptor descriptor,
    required List<UninstallEntry> before,
    String? installerFileName,
  }) async {
    final rules = descriptor.detect;
    final needsPattern = _isBlank(rules.registryDisplayName);
    final needsExe = _isBlank(rules.exeName);
    if (!needsPattern && !needsExe) return null;

    onStart?.call();
    final hints = nameHintsFor(
      name: descriptor.name,
      repo: descriptor.github?.repo,
      installerFileName: installerFileName,
    );
    final entry = await _awaitFreshEntry(before, hints);

    final displayName = entry?.displayName;
    final learnedPattern = needsPattern && displayName != null
        ? RegistryDisplayNamePattern.fromDisplayName(displayName)
        : null;

    // התיקייה מהרג'יסטרי קודמת לזו שהמשתמש הצהיר עליה: היא רישום שהמתקין
    // כתב ברגע זה, ולא ניחוש שנרשם בטופס לפני שהתוכנה הייתה קיימת בכלל.
    final dir = entry?.installDir ?? descriptor.installDir;
    final learnedExe =
        needsExe && dir != null ? await _exeIn(dir, hints) : null;

    if (learnedPattern == null && learnedExe == null) return null;
    return AppDetectRules(
      exeName: learnedExe ?? rules.exeName,
      registryDisplayName: learnedPattern ?? rules.registryDisplayName,
      dirs: rules.dirs,
    );
  }

  /// הרישום החדש שהופיע, או `null` כשאף אחד לא הופיע בתוך [timeout].
  ///
  /// "לא הופיע" הוא תוצאה תקינה לגמרי: תוכנה ניידת אינה רושמת הסרה, והמשתמש
  /// עשוי לבטל אשף `interactive` באמצע.
  Future<UninstallEntry?> _awaitFreshEntry(
    List<UninstallEntry> before,
    List<String> hints,
  ) async {
    final lookup = lookupUninstallEntries;
    if (lookup == null) return null;

    var waited = Duration.zero;
    var delay = firstPollDelay;

    while (true) {
      final List<UninstallEntry> now;
      try {
        now = await lookup();
      } catch (_) {
        return null;
      }
      final chosen = pickEntry(now, before, hints);
      if (chosen != null) return chosen;

      if (waited >= timeout) return null;
      await _delay(delay);
      waited += delay;
      final doubled = delay * 2;
      delay = doubled > maxPollDelay ? maxPollDelay : doubled;
    }
  }

  Future<void> _delay(Duration duration) =>
      (_sleep ?? Future<void>.delayed)(duration);

  Future<String?> _exeIn(String dir, List<String> hints) async {
    final lookup = lookupExe;
    if (lookup == null) return null;
    try {
      final path = await lookup(dir, hints);
      return path == null ? null : p.basename(path);
    } catch (_) {
      return null;
    }
  }

  /// איזה מהרישומים הוא התוכנה שלנו — בשלוש שכבות, מהעדות החזקה לחלשה.
  ///
  /// ⚠️ **התקנה חוזרת אינה יוצרת מפתח חדש.** זה לא מקרה קצה אלא המקרה
  /// הנפוץ: מי שכבר מותקנת אצלו התוכנה ומתקין גרסה חדשה מעדכן את אותו מפתח
  /// בדיוק. גרסה שדרשה מפתח חדש בלבד לא למדה כלום בדיוק אצל מי שהתוכנה
  /// כבר עבדה אצלו (אומת מול `KleiKodesh` על מחשב אמיתי).
  ///
  /// 1. **מפתח שנולד** — העדות החזקה. כאן, ורק כאן, מתקבל גם רישום בודד בלי
  ///    התאמת שם: מפתח הסרה חדש לגמרי מיד אחרי שהרצנו מתקין אינו צירוף
  ///    מקרים. כשיש כמה חדשים ואף אחד אינו מזכיר את התוכנה — מוותרים,
  ///    כי מתקין שגורר VC++ Redistributable מייצר שני רישומים.
  /// 2. **מפתח שהשתנה** — שם או תיקייה שזזו בזמן שהתקנו. דורש התאמת שם:
  ///    דפדפנים ומעדכני מערכת משנים רישומים ברקע בלי קשר אלינו.
  /// 3. **מפתח קיים ששמו מתאים** — התוכנה כבר הייתה רשומה. עדות חלשה יותר,
  ///    אבל היא בדיוק מה שערוץ הרג'יסטרי נועד לו, ודרישת התאמת השם היא מה
  ///    שמונע ממנה לאמץ תוכנה אקראית. גם כאן **אין** קבלה של רישום בודד.
  static UninstallEntry? pickEntry(
    List<UninstallEntry> now,
    List<UninstallEntry> before,
    List<String> hints,
  ) {
    if (now.isEmpty) return null;

    final previous = {
      for (final entry in before) entry.keyName.toLowerCase(): entry,
    };

    final fresh = <UninstallEntry>[];
    final changed = <UninstallEntry>[];
    for (final entry in now) {
      final was = previous[entry.keyName.toLowerCase()];
      if (was == null) {
        fresh.add(entry);
      } else if (was.displayName != entry.displayName ||
          was.installDir != entry.installDir) {
        changed.add(entry);
      }
    }

    // כל התאמת-שם גוברת על ניחוש חסר-שם, ולכן "רישום בודד" הוא אחרון ולא
    // מיד אחרי שכבה 1: מתקין שגרר איתו רישום נלווה יחיד היה נבחר על פני
    // הרישום של התוכנה עצמה, שרק התעדכן במקום להיוולד.
    return _matchByHints(fresh, hints) ??
        _matchByHints(changed, hints) ??
        _matchByHints(now, hints) ??
        (fresh.length == 1 ? fresh.single : null);
  }

  /// הרמזים נבדקים **מהארוך לקצר**, ולא הרישומים מהראשון לאחרון: רמז קצר
  /// היה מאמץ את הרישום הראשון שבמקרה מכיל אותו.
  ///
  /// ההשוואה דו-כיוונית — `DisplayName` הוא לעיתים קרובות קידומת של הרמז
  /// ולא להפך: הרישום `KleiKodesh` מול הרמז `kleikodeshproject` שנגזר משם
  /// הריפו. בדיקה בכיוון אחד בלבד הייתה מחמיצה אותו.
  static UninstallEntry? _matchByHints(
    List<UninstallEntry> candidates,
    List<String> hints,
  ) {
    if (candidates.isEmpty) return null;
    final ordered = [...hints]..sort((a, b) => b.length.compareTo(a.length));

    for (final hint in ordered) {
      for (final entry in candidates) {
        final name = normalize(entry.displayName);
        if (name.isEmpty) continue;
        if (name.contains(hint) || hint.contains(name)) return entry;
      }
    }
    return null;
  }

  /// הרמזים שמזהים את התוכנה בטקסט חופשי: השם שהמשתמש נתן לה, שם הריפו, וגם
  /// שם קובץ ההתקנה — `MyApp-Setup-1.4.2.exe` מזכיר את `MyApp` גם כשהמשתמש
  /// קרא לתוכנה בעברית.
  ///
  /// מקבל מחרוזות ולא [AppDescriptor], כדי שגם הטופס יוכל לבנות את אותם
  /// רמזים בזמן שהמשתמש מקליד — לפני שיש רשומה בכלל.
  static List<String> nameHintsFor({
    required String name,
    String? repo,
    String? installerFileName,
  }) {
    final tokens = <String>{
      ..._tokensOf(name),
      if (repo != null) ..._tokensOf(repo),
      if (installerFileName != null)
        ..._tokensOf(p.basenameWithoutExtension(installerFileName)),
    };
    return tokens.toList(growable: false);
  }

  /// אורך מינימלי לטוקן שנחשב עדות. `My` או `7z` היו תופסים חצי מהרג'יסטרי.
  static const int _minTokenLength = 3;

  /// טוקנים שאינם מזהים שום תוכנה מסוימת — הם מופיעים בשם קובץ ההתקנה של
  /// כולן. `x64` שנגזר מ-`MyApp-Setup-x64.exe` היה מאמץ בשמחה את
  /// `Microsoft Visual C++ 2015 Redistributable (x64)`.
  ///
  /// הרשימה מכוונת למוסכמות של **שמות קובצי התקנה** בלבד. `app` או
  /// `windows` אינם כאן: הם באים מהשם שהמשתמש הקליד, ותוכנה בשם "App 2024"
  /// הייתה נשארת בלי שום רמז.
  static const Set<String> _noiseTokens = {
    'x64',
    'x86',
    'win32',
    'win64',
    'amd64',
    'arm64',
    'setup',
    'install',
    'installer',
    'portable',
    'exe',
    'msi',
    'zip',
  };

  /// כל מה שאינו אות או ספרה, בכל שפה.
  ///
  /// דרך `\p{L}` ולא דרך טווח `a-z` ועוד טווח לעברית: שם התוכנה נכתב בעברית
  /// לא פחות מבאנגלית, וטווח שנשמט בו סוף הבלוק היה הופך כל אות עברית
  /// למפריד — כלומר שם עברי היה מתנרמל למחרוזת ריקה ומפסיק לזהות בשקט.
  static final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  /// מפרק שם לטוקנים שאפשר להשוות: מפרידים נחתכים, ומספרי גרסה נזרקים.
  static List<String> _tokensOf(String raw) {
    final parts = raw.toLowerCase().split(_separators);
    return [
      for (final part in parts)
        if (part.length >= _minTokenLength &&
            !_digitsOnly.hasMatch(part) &&
            !_noiseTokens.contains(part))
          part,
    ];
  }

  /// אותו נירמול שעברו הטוקנים, כדי שההשוואה תהיה בין שווים: `MyApp Pro 1.4`
  /// הופך ל-`myapppro14`, ולכן הוא מכיל את הטוקן `myapp`.
  static String normalize(String text) =>
      text.toLowerCase().replaceAll(_separators, '');

  static bool _isBlank(String? value) => value == null || value.isEmpty;
}
