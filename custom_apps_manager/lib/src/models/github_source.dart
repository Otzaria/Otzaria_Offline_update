/// ריפו GitHub שממנו מגיעות הגרסאות של תוכנה מותאמת.
///
/// המשתמש מדביק כתובת, ואנחנו מביאים את ה-release ומציגים לו את **רשימת
/// הקבצים האמיתית** שילחץ על הנכון. ל-release טיפוסי יש 5–10 קבצים
/// (x64/x86/portable/setup/sha), ובחירת "הראשון" היא באג מובטח — בדיוק
/// סוג הבאג שכבר תועד בריפו הזה (`crashpad_handler.exe`, חבילות ה-FULL).
class GithubSource {
  const GithubSource({
    required this.owner,
    required this.repo,
    required this.assetPattern,
  });

  final String owner;
  final String repo;

  /// ביטוי רגולרי שמזהה את הקובץ הנכון בכל release עתידי. **אינו** שם
  /// הקובץ שנבחר: שם עם מספר גרסה בתוכו היה מתאים ל-release אחד בלבד.
  /// ראו [GithubAssetPattern].
  final String assetPattern;

  /// כתובת ה-API של רשימת ה-releases.
  String get releasesApiUrl =>
      'https://api.github.com/repos/$owner/$repo/releases';

  /// הכתובת שהמשתמש רואה — גם מה שהוא הדביק מלכתחילה.
  String get webUrl => 'https://github.com/$owner/$repo';

  factory GithubSource.fromJson(Map<String, dynamic> json) => GithubSource(
        owner: json['owner'] as String,
        repo: json['repo'] as String,
        assetPattern: json['asset'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        'asset': assetPattern,
      };

  /// מפרק כתובת GitHub שהמשתמש הדביק. מקבל גם `https://github.com/a/b`,
  /// גם עם `/releases` בסוף, גם עם `.git`, וגם `a/b` יבש — כי זה מה
  /// שאנשים מדביקים בפועל.
  static ({String owner, String repo})? parseUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    text = text.replaceFirst(RegExp(r'^https?://'), '');
    text = text.replaceFirst(RegExp(r'^(www\.)?github\.com/'), '');
    text = text.replaceFirst(RegExp(r'\.git$'), '');

    final parts = text
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return null;

    // הכול שאחרי `owner/repo` (releases, tree/main…) אינו מעניין אותנו.
    final owner = parts[0];
    final repo = parts[1];
    if (owner.isEmpty || repo.isEmpty) return null;
    return (owner: owner, repo: repo);
  }
}

/// הופך **שם קובץ שהמשתמש בחר** לתבנית שתמשיך להתאים גם בגרסה הבאה.
///
/// `MyApp-Setup-1.4.2.exe` שנשמר כמות שהוא היה מתאים ל-release אחד בלבד,
/// ובגרסה הבאה התוכנה הייתה מדווחת "אין קובץ מתאים".
abstract final class GithubAssetPattern {
  /// ספרות שקודם להן **אות** אינן מספר גרסה אלא חלק מהשם: `x64`, `win32`,
  /// `amd64`. רק ספרות שאחרי מפריד או בתחילת השם מוחלפות.
  ///
  /// זו ההבחנה שמונעת מתבנית של x64 להתאים גם ל-x86.
  ///
  /// ⚠️ ה-`v` האופציונלי הוא תיקון לבאג שנמצא מול ריפו אמיתי
  /// (`KleiKodesh/KleiKodeshProject`): בשם `KleiKodeshSetup-v9.0.1-x64.exe`
  /// הספרה `9` באה אחרי האות `v`, ולכן הכלל לעיל שימר אותה — התבנית קפאה על
  /// `v9`, ובגרסה 10 התוכנה הייתה מדווחת "אין קובץ מתאים" לנצח. ה-`v` עצמו
  /// חייב לבוא אחרי מפריד, כדי ש-`Rev9` יישאר חלק מהשם.
  static final RegExp _versionDigits =
      RegExp(r'(?<![A-Za-z\d])(v)?(\d+)', caseSensitive: false);

  /// תבנית מעוגנת שמתאימה לאותו קובץ בכל גרסה.
  static String fromAssetName(String assetName) {
    final buffer = StringBuffer('^');
    var index = 0;

    for (final match in _versionDigits.allMatches(assetName)) {
      buffer.write(RegExp.escape(assetName.substring(index, match.start)));
      // ה-`v` נשמר כמות שהוא — הוא חלק מהשם, ורק המספר שאחריו משתנה.
      if (match[1] case final prefix?) buffer.write(RegExp.escape(prefix));
      buffer.write(r'\d+');
      index = match.end;
    }
    buffer
      ..write(RegExp.escape(assetName.substring(index)))
      ..write(r'$');
    return buffer.toString();
  }

  /// האם [assetName] תואם ל-[pattern]. תבנית פגומה אינה מפילה את הבדיקה —
  /// היא פשוט לא מתאימה לכלום, והמשתמש יראה "אין קובץ מתאים".
  static bool matches(String pattern, String assetName) {
    if (pattern.isEmpty) return false;
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(assetName);
    } catch (_) {
      return false;
    }
  }
}
