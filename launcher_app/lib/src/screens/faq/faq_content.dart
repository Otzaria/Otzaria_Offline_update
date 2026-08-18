import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../settings/faq_customization.dart';

/// שאלה ותשובה אחת.
class FaqEntry {
  const FaqEntry(this.id, this.question, this.answer);

  /// מזהה יציב — שם השדה בחוזה המלל לשאלות המובנות, ו-`extra:<אינדקס>`
  /// לשאלות שהמשתמש הוסיף. הוא מה שנשמר כשמסתירים שאלה, ולכן אינו יכול
  /// להיות הנוסח עצמו: זה היה נשבר בהחלפת שפה או בניסוח מחדש.
  final String id;
  final String question;
  final String answer;
}

/// קבוצת שאלות בעלת כותרת.
class FaqGroup {
  const FaqGroup(this.title, this.entries);

  final String title;
  final List<FaqEntry> entries;
}

/// כל ההדרכה, בסדר שבו היא מוצגת. הסדר בכל קבוצה הוא סדר של שיחה: השאלה
/// הראשונה היא זו שנשאלת קודם, וזו שאחריה היא "זה לא עזר, מה עוד".
///
/// נבנה מחדש בכל קריאה ולא מוחזק ב-`const`: המלל תלוי בשפה שנבחרה.
///
/// [custom] מוסיף את שאלות המשתמש ומסנן את מה שהוסתר. `null` — או קריאה
/// ממסך העריכה — מחזיר את הרשימה המלאה, כי שם צריך לראות גם את המוסתרות.
List<FaqGroup> faqGroups(AppStrings strings, {FaqCustomization? custom}) {
  final t = strings.faq;
  final hidden = custom?.hiddenIds ?? const <String>{};

  FaqGroup group(String title, List<FaqEntry> entries) => FaqGroup(title, [
        for (final entry in entries)
          if (!hidden.contains(entry.id)) entry,
      ]);

  final groups = [
    group(t.groupBasics, [
      FaqEntry('qWhatIsThis', t.qWhatIsThis, t.aWhatIsThis),
      FaqEntry('qOfflineFlow', t.qOfflineFlow, t.aOfflineFlow),
      FaqEntry('qNoOtzariaYet', t.qNoOtzariaYet, t.aNoOtzariaYet),
    ]),
    group(t.groupDownload, [
      FaqEntry('qDownloadStopped', t.qDownloadStopped, t.aDownloadStopped),
      FaqEntry('qDownloadTooBig', t.qDownloadTooBig, t.aDownloadTooBig),
      FaqEntry('qOtzariaOpen', t.qOtzariaOpen, t.aOtzariaOpen),
      FaqEntry(
        'qBrokenAfterUpdate',
        t.qBrokenAfterUpdate,
        t.aBrokenAfterUpdate,
      ),
    ]),
    group(t.groupLibrary, [
      FaqEntry('qAppNotDetected', t.qAppNotDetected, t.aAppNotDetected),
      FaqEntry('qDbNotFound', t.qDbNotFound, t.aDbNotFound),
      FaqEntry('qStillNotFound', t.qStillNotFound, t.aStillNotFound),
      FaqEntry(
        'qSearchMissesNewBooks',
        t.qSearchMissesNewBooks,
        t.aSearchMissesNewBooks,
      ),
    ]),
    group(t.groupExtras, [
      FaqEntry('qWhatArePlugins', t.qWhatArePlugins, t.aWhatArePlugins),
      FaqEntry(
        'qWhatAreCustomApps',
        t.qWhatAreCustomApps,
        t.aWhatAreCustomApps,
      ),
    ]),
    group(t.groupGeneral, [
      FaqEntry('qWrongFolder', t.qWrongFolder, t.aWrongFolder),
      FaqEntry(
        'qLauncherSelfUpdate',
        t.qLauncherSelfUpdate,
        t.aLauncherSelfUpdate,
      ),
      FaqEntry('qFree', t.qFree, t.aFree),
      FaqEntry('qNoExpenses', t.qNoExpenses, t.aNoExpenses),
    ]),
    if (custom != null && custom.extras.isNotEmpty)
      FaqGroup(t.myQuestionsTitle, [
        for (var i = 0; i < custom.extras.length; i++)
          FaqEntry(
            extraEntryId(i),
            custom.extras[i].question,
            custom.extras[i].answer,
          ),
      ]),
  ];

  // קבוצה שכל שאלותיה הוסתרו נעלמת אף היא — כותרת בלי תוכן נראית כתקלה.
  return [
    for (final g in groups)
      if (g.entries.isNotEmpty) g,
  ];
}

/// המזהה של שאלה שהמשתמש הוסיף, לפי מקומה ברשימה.
String extraEntryId(int index) => 'extra:$index';
