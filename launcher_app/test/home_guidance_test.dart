import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/home_guidance_session.dart';

typedef _Case = ({
  String name,
  GuidanceFacts facts,
  GuidancePrimary primary,
  GuidanceSecondary secondary,
  List<GuidanceItem> here,
  List<GuidanceItem> download,
  bool banner,
  bool blocks,
});

_Case _case(
  String name,
  GuidanceFacts facts,
  GuidancePrimary primary, {
  GuidanceSecondary secondary = GuidanceSecondary.none,
  List<GuidanceItem> here = const [],
  List<GuidanceItem> download = const [],
  bool banner = false,
  bool? blocks,
}) =>
    (
      name: name,
      facts: facts,
      primary: primary,
      secondary: secondary,
      here: here,
      download: download,
      banner: banner,
      // "עדכון כאן" יבקש לסגור אותה — בדרך כלל כשיש פס.
      blocks: blocks ?? banner,
    );

const _app = GuidanceItem.app;
const _library = GuidanceItem.library;
const _plugins = GuidanceItem.plugins;

void main() {
  group('ששת התרחישים של המוקאפ', () {
    final cases = [
      _case(
        'offline-with-updates: מחשב מנותק, בכונן תוכנה וספרייה חדשות',
        const GuidanceFacts(
          online: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.updateAvailable,
          pluginUpdatesOnDrive: 2,
        ),
        GuidancePrimary.updateHere,
        here: [_library, _app, _plugins],
      ),
      _case(
        'online-new-updates: מחשב מחובר, ברשת חדש שאין בכונן',
        const GuidanceFacts(
          online: true,
          onlineApp: true,
          onlineLibrary: true,
          onlinePlugins: true,
        ),
        GuidancePrimary.downloadToDrive,
        download: [_app, _library, _plugins],
      ),
      _case(
        'up-to-date: הכול מעודכן ואין חדש ברשת',
        const GuidanceFacts(online: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'first-time-empty-drive: אוצריא לא מותקנת והכונן ריק',
        const GuidanceFacts(
          online: true,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.needsDownload,
          libraryStatus: LibraryStatusFact.needsDownload,
          onlineApp: true,
          onlineLibrary: true,
        ),
        GuidancePrimary.welcome,
        download: [_app, _library],
      ),
      _case(
        'otzaria-open: יש מה לעדכן ואוצריא פתוחה',
        const GuidanceFacts(
          online: false,
          otzariaRunning: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
        banner: true,
      ),
      _case(
        'read-only: כונן מוגן עם עדכון — התקנה מותרת',
        const GuidanceFacts(
          readOnly: true,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_app],
      ),
    ];
    _runCases(cases);
  });

  group('קצוות', () {
    final cases = [
      _case(
        'הבדיקה המקומית עוד לא הסתיימה',
        const GuidanceFacts(otzariaStatus: AppStatusFact.checking),
        GuidancePrimary.checking,
      ),
      _case(
        'בדיקה ברשת ראשונה רצה ואין מה להתקין',
        const GuidanceFacts(isCheckingOnline: true),
        GuidancePrimary.checking,
      ),
      _case(
        'בדיקה ברשת רצה אבל יש מה להתקין כאן — לא מחכים לה',
        const GuidanceFacts(
          isCheckingOnline: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'הורדה רצה',
        const GuidanceFacts(
            longTaskRunning: true, online: true, onlineApp: true),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'התקנה רצה',
        const GuidanceFacts(
          installing: true,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'החלת ספרייה פעילה',
        const GuidanceFacts(libraryApplyActive: true),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'גם להוריד וגם לעדכן כאן — ההורדה ראשית',
        const GuidanceFacts(
          online: true,
          onlineLibrary: true,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.downloadToDrive,
        secondary: GuidanceSecondary.updateHereToo,
        here: [_app],
        download: [_library],
      ),
      _case(
        'המותקן חדש מהכונן — בלי פעולה',
        const GuidanceFacts(
          online: true,
          otzariaStatus: AppStatusFact.installedIsNewer,
        ),
        GuidancePrimary.newerHereThanDrive,
      ),
      _case(
        'המותקן חדש מהכונן, אבל לספרייה יש עדכון',
        const GuidanceFacts(
          online: false,
          otzariaStatus: AppStatusFact.installedIsNewer,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'מחשב מנותק ומעודכן — רמז, לא תקלה',
        const GuidanceFacts(online: false),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.offlineHint,
      ),
      _case(
        'כונן כתיב שעוד לא נבדק ברשת',
        const GuidanceFacts(),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'כונן מוגן שלא נבדק — אין הצעה לבדוק',
        const GuidanceFacts(readOnly: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'חדש ברשת אבל שום דבר לא מסומן להורדה',
        const GuidanceFacts(
          online: true,
          onlineApp: true,
          syncApp: false,
          syncLibrary: false,
          syncPlugins: false,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.noSyncSelection,
      ),
      // רכיבים אחרים מסומנים, ולכן לא "לא נבחר שום דבר".
      _case(
        'חדש ברשת רק ברכיב שאינו מסומן',
        const GuidanceFacts(
            online: true, onlineLibrary: true, syncLibrary: false),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.syncOff,
      ),
      _case(
        'חדש ברשת בספרייה ובתוספים, ורק התוכנה מסומנת',
        const GuidanceFacts(
          online: true,
          onlineLibrary: true,
          onlinePlugins: true,
          syncLibrary: false,
          syncPlugins: false,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.syncOff,
      ),
      _case(
        'רכיב כבוי בלי חדש ברשת — שקט',
        const GuidanceFacts(online: true, syncLibrary: false),
        GuidancePrimary.upToDate,
      ),
      _case(
        'רק רכיב מסומן נכלל בהורדה',
        const GuidanceFacts(
          online: true,
          onlineApp: true,
          onlinePlugins: true,
          syncPlugins: false,
        ),
        GuidancePrimary.downloadToDrive,
        download: [_app],
      ),
      // בכונן מוגן אין בדיקה ברשת (`AppSession.checkOnline`): online נשאר null,
      // ואין שורה משנית — לא "בדוק עכשיו" ולא הורדה.
      _case(
        'כונן מוגן עם עדכון כאן — עדכון כאן, בלי שורה משנית',
        const GuidanceFacts(
          readOnly: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'כונן מלא והכול מעודכן — בלי "בדוק עכשיו"',
        const GuidanceFacts(readOnly: true, driveFull: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'כונן מוגן, גם אם הגיעה עובדה מקוונת — לא מציע הורדה',
        const GuidanceFacts(
          readOnly: true,
          online: true,
          onlineApp: true,
        ),
        GuidancePrimary.upToDate,
      ),
      _case(
        'התקנה ראשונה: תוכנה ואז ספרייה, בלי תוספים',
        const GuidanceFacts(
          online: false,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.updateAvailable,
          libraryFreshInstall: true,
          pluginUpdatesOnDrive: 3,
        ),
        GuidancePrimary.installHere,
        here: [_app, _library],
      ),
      _case(
        'רק תוספים לעדכן — מותר גם בכונן מוגן',
        const GuidanceFacts(readOnly: true, pluginUpdatesOnDrive: 1),
        GuidancePrimary.updateHere,
        here: [_plugins],
      ),
      _case(
        'אוצריא פתוחה בלי מה לעדכן — פס עם "סגירת אוצריא"',
        const GuidanceFacts(online: true, otzariaRunning: true),
        GuidancePrimary.upToDate,
        banner: true,
        blocks: false,
      ),
      _case(
        'אוצריא פתוחה בזמן משימה — בלי פס',
        const GuidanceFacts(otzariaRunning: true, longTaskRunning: true),
        GuidancePrimary.taskInProgress,
      ),
      _case(
        'אוצריא לא מותקנת אבל בכונן יש אותה — לא "ברוך הבא"',
        const GuidanceFacts(
          online: true,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          otzariaMirrorVersion: 'v1.0.0',
          libraryStatus: LibraryStatusFact.needsDownload,
        ),
        GuidancePrimary.installHere,
        here: [_app],
      ),
      _case(
        'כונן ריק ומחשב מנותק בהרצה ראשונה',
        const GuidanceFacts(
          online: false,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.needsDownload,
          libraryStatus: LibraryStatusFact.needsDownload,
        ),
        GuidancePrimary.welcome,
        secondary: GuidanceSecondary.offlineHint,
      ),
      _case(
        'בדיקה אוטומטית כבויה: הספרייה לא נבדקה — רגוע, עם "בדוק עכשיו"',
        const GuidanceFacts(
          online: false,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'כונן מוגן, הספרייה לא נבדקה — גם כאן מציעים לבדוק',
        const GuidanceFacts(
          readOnly: true,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'הספרייה לא נבדקה אבל לתוכנה יש עדכון — הפעולה קודמת',
        const GuidanceFacts(
          online: false,
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.updateHere,
        here: [_app],
      ),
      _case(
        'בדיקה אוטומטית דולקת ועוד לא נבדק ברשת — בודק',
        const GuidanceFacts(
          autoCheckUpdates: true,
          libraryStatus: LibraryStatusFact.idle,
        ),
        GuidancePrimary.checking,
      ),
      _case(
        'התוספים עוד נטענים — לא "הכול מעודכן"',
        const GuidanceFacts(online: true, pluginsLoading: true),
        GuidancePrimary.checking,
      ),
      _case(
        'אוצריא פתוחה ורק תוספים לעדכן — הפס לא חוסם את העדכון',
        const GuidanceFacts(
          online: false,
          otzariaRunning: true,
          pluginUpdatesOnDrive: 2,
        ),
        GuidancePrimary.updateHere,
        here: [_plugins],
        banner: true,
        blocks: false,
      ),
      _case(
        'אוצריא פתוחה, תוכנה ותוספים לעדכן — פס',
        const GuidanceFacts(
          online: false,
          otzariaRunning: true,
          otzariaStatus: AppStatusFact.updateAvailable,
          pluginUpdatesOnDrive: 1,
        ),
        GuidancePrimary.updateHere,
        here: [_app, _plugins],
        banner: true,
      ),
      _case(
        'עדכון ספרייה בזמן שממתינה הסכמה — נכלל בעדכון כאן',
        const GuidanceFacts(
          online: false,
          libraryStatus: LibraryStatusFact.updateAvailable,
          semanticConsentRequired: true,
        ),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      // גם אחרי עדכון לבד: הוא מחיל רק "עדכון", והחלון נפתח רק בלחיצה.
      _case(
        'רק החיפוש החכם מחכה לתשובה — "עדכון המחשב הזה" על הספרייה',
        const GuidanceFacts(online: false, semanticConsentRequired: true),
        GuidancePrimary.updateHere,
        here: [_library],
      ),
      _case(
        'הסכמה חסרה בלי אוצריא מותקנת — אין לאן לכתוב, לא בגיבור',
        const GuidanceFacts(
          online: false,
          otzariaInstalled: false,
          otzariaStatus: AppStatusFact.needsDownload,
          semanticConsentRequired: true,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.offlineHint,
      ),
    ];
    _runCases(cases);
  });

  group('מה הבדיקה ברשת הוכיחה', () {
    const failed = OnlineProof.failed;
    final cases = [
      _case(
        'מחשב לא מחובר (כל הבדיקות נכשלו) — מה שבכונן מותקן, ורמז',
        const GuidanceFacts(
          online: false,
          appProof: failed,
          libraryProof: failed,
          pluginsProof: failed,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.offlineHint,
      ),
      _case(
        'כשל חלקי — "לא הצלחתי לבדוק"',
        const GuidanceFacts(online: true, libraryProof: failed),
        GuidancePrimary.checkFailed,
      ),
      // רק בדיקת הכלי הצליחה: המחשב מחובר, ולכן זה כשל — לא "מעודכן".
      _case(
        'רק בדיקת הכלי הצליחה — לא "הכול מעודכן"',
        const GuidanceFacts(
          online: true,
          appProof: failed,
          libraryProof: failed,
          pluginsProof: failed,
        ),
        GuidancePrimary.checkFailed,
      ),
      _case(
        'כשל ברכיב שאינו מסומן אינו כשל',
        const GuidanceFacts(
          online: true,
          libraryProof: failed,
          syncLibrary: false,
        ),
        GuidancePrimary.upToDate,
      ),
      _case(
        'בדיקה ישנה בלי חדש — עדיין "מעודכן", בלי רענון',
        const GuidanceFacts(online: true, libraryProof: OnlineProof.stale),
        GuidancePrimary.upToDate,
      ),
      _case(
        'בדיקה ישנה שמצאה חדש — ההורדה נשארת',
        const GuidanceFacts(
          online: true,
          libraryProof: OnlineProof.stale,
          onlineLibrary: true,
        ),
        GuidancePrimary.downloadToDrive,
        download: [_library],
      ),
      _case(
        'רכיב שנבחר עוד לא נבדק במחשב מחובר — "בדוק עכשיו"',
        const GuidanceFacts(
          online: true,
          pluginsProof: OnlineProof.unchecked,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.checkOnlineNow,
      ),
      _case(
        'כשל חלקי, אבל יש מה להתקין כאן — הפעולה קודמת',
        const GuidanceFacts(
          online: true,
          libraryProof: failed,
          otzariaStatus: AppStatusFact.updateAvailable,
        ),
        GuidancePrimary.updateHere,
        here: [_app],
      ),
      _case(
        'כשל חלקי, ויש חדש ברכיב אחר — ההורדה קודמת',
        const GuidanceFacts(
          online: true,
          libraryProof: failed,
          onlineApp: true,
        ),
        GuidancePrimary.downloadToDrive,
        download: [_app],
      ),
      _case(
        'בדיקת הכלי חזרה ושל הספרייה עוד רצה — בודק, לא "מעודכן"',
        const GuidanceFacts(
          online: true,
          isCheckingOnline: true,
          libraryProof: OnlineProof.unchecked,
        ),
        GuidancePrimary.checking,
      ),
      _case(
        'בדיקה חוזרת אחרי תשובה קודמת — התשובה נשארת עד שמתחלפת',
        const GuidanceFacts(online: true, isCheckingOnline: true),
        GuidancePrimary.upToDate,
      ),
      _case(
        'שבת: רק התוספים לא נבדקו — הערת השבת, לא "לא הצלחתי לבדוק"',
        const GuidanceFacts(
          online: true,
          pluginsProof: OnlineProof.unchecked,
          pluginsClosedForShabbat: true,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.siteClosedForShabbat,
      ),
      _case(
        'שבת ובדיקה חוזרת — לא "בודק" בגלל התוספים',
        const GuidanceFacts(
          online: true,
          isCheckingOnline: true,
          pluginsProof: OnlineProof.unchecked,
          pluginsClosedForShabbat: true,
        ),
        GuidancePrimary.upToDate,
        secondary: GuidanceSecondary.siteClosedForShabbat,
      ),
      _case(
        'שום רכיב לא נבחר ואין חדש — בלי "בדוק עכשיו"',
        const GuidanceFacts(
          online: true,
          syncApp: false,
          syncLibrary: false,
          syncPlugins: false,
        ),
        GuidancePrimary.upToDate,
      ),
      _case(
        'כונן מוגן — אין "לא הצלחתי לבדוק"',
        const GuidanceFacts(readOnly: true, online: true, libraryProof: failed),
        GuidancePrimary.upToDate,
      ),
    ];
    _runCases(cases);

    test('"הכול מעודכן" רק כשכל רכיב שנבחר הוכח', () {
      bool proven(GuidanceFacts f) => deriveHomeGuidance(f).onlineProven;
      expect(proven(const GuidanceFacts(online: true)), isTrue);
      expect(
        proven(
          const GuidanceFacts(
            online: true,
            appProof: OnlineProof.stale,
            libraryProof: OnlineProof.proven,
            pluginsProof: OnlineProof.proven,
          ),
        ),
        isTrue,
      );
      expect(proven(const GuidanceFacts(online: false)), isFalse);
      // בלי בחירה אין מה שהוכח — הגוף לא יטען "מעודכנים".
      expect(
        proven(
          const GuidanceFacts(
            online: true,
            syncApp: false,
            syncLibrary: false,
            syncPlugins: false,
          ),
        ),
        isFalse,
      );
      expect(
        proven(
          const GuidanceFacts(
            online: true,
            pluginsProof: OnlineProof.unchecked,
            pluginsClosedForShabbat: true,
          ),
        ),
        isFalse,
      );
      expect(proven(const GuidanceFacts()), isFalse);
      expect(
          proven(const GuidanceFacts(readOnly: true, online: true)), isFalse);
      expect(
        proven(
          const GuidanceFacts(
              online: true, libraryProof: OnlineProof.unchecked),
        ),
        isFalse,
      );
    });

    test('כשל חלקי: מה לא נבדק ומה כן, והאריח אומר "טרם נבדק"', () {
      const f = GuidanceFacts(online: true, libraryProof: failed);
      final g = deriveHomeGuidance(f);
      expect(g.uncheckedItems, [_library]);
      expect(g.checkedItems, [_app, _plugins]);
      expect(
        deriveTileStatus(_library, f, unchecked: g.uncheckedItems),
        TileStatus.notCheckedOnline,
      );
      expect(
        deriveTileStatus(_app, f, unchecked: g.uncheckedItems),
        TileStatus.upToDate,
      );
      // עדכון בכונן גובר — האריח אומר מה לעשות.
      const here = GuidanceFacts(
        online: true,
        libraryProof: failed,
        libraryStatus: LibraryStatusFact.updateAvailable,
      );
      expect(
        deriveTileStatus(_library, here, unchecked: const [_library]),
        TileStatus.updateHere,
      );
    });
  });

  group('עקביות עם שורת הכלי ועם התוכנות הנוספות', () {
    test('"הכול מעודכן" אינו מסתיר עדכון של הכלי או תוכנה שמחכה', () {
      final g = deriveHomeGuidance(
        const GuidanceFacts(
          online: true,
          launcherUpdate: true,
          customAppsPending: true,
        ),
      );
      expect(g.primary, GuidancePrimary.upToDate);
      expect(g.otherUpdates, [OtherUpdate.launcher, OtherUpdate.customApps]);
      // גם במחשב לא מחובר: "כל מה שבכונן מותקן" אינו נכון כשתוכנה מחכה.
      expect(
        deriveHomeGuidance(
          const GuidanceFacts(online: false, customAppsPending: true),
        ).otherUpdates,
        [OtherUpdate.customApps],
      );
      expect(deriveHomeGuidance(const GuidanceFacts()).otherUpdates, isEmpty);
    });

    test('במצב שיש בו פעולה — הם לא נכנסים לגיבור', () {
      final g = deriveHomeGuidance(
        const GuidanceFacts(
          online: false,
          launcherUpdate: true,
          libraryStatus: LibraryStatusFact.updateAvailable,
        ),
      );
      expect(g.primary, GuidancePrimary.updateHere);
      expect(g.otherUpdates, isEmpty);
    });
  });

  group('onlineProofOf', () {
    final now = DateTime(2026, 10, 25, 12);
    test('כשל גובר, ואחריו "לא נבדק", "ישנה" ו"הוכח"', () {
      final fresh = now.subtract(const Duration(minutes: 5));
      final old = now.subtract(const Duration(hours: 2));
      expect(onlineProofOf([(fresh, null)], now: now), OnlineProof.proven);
      expect(onlineProofOf([(old, null)], now: now), OnlineProof.stale);
      expect(onlineProofOf([(null, null)], now: now), OnlineProof.unchecked);
      expect(onlineProofOf([(fresh, 'down')], now: now), OnlineProof.failed);
      // התוספים: קטלוג וחנות — שתי הבדיקות יחד.
      expect(
        onlineProofOf([(fresh, null), (old, 'down')], now: now),
        OnlineProof.failed,
      );
      expect(
        onlineProofOf([(fresh, null), (null, null)], now: now),
        OnlineProof.unchecked,
      );
      expect(
        onlineProofOf([(fresh, null), (old, null)], now: now),
        OnlineProof.stale,
      );
    });
  });

  test('הסכמה ממתינה: האריח והגיבור מסכימים על העדכון', () {
    const facts = GuidanceFacts(
      online: false,
      libraryStatus: LibraryStatusFact.updateAvailable,
      semanticConsentRequired: true,
    );
    expect(deriveHomeGuidance(facts).hereItems, contains(_library));
    expect(deriveTileStatus(_library, facts), TileStatus.updateHere);
  });

  group('דורש תשומת לב', () {
    for (final (status, item) in [
      (const GuidanceFacts(libraryStatus: LibraryStatusFact.error), _library),
      (
        const GuidanceFacts(libraryStatus: LibraryStatusFact.needsManualPath),
        _library,
      ),
      (
        const GuidanceFacts(
          libraryStatus: LibraryStatusFact.personalTargetElsewhere,
        ),
        _library,
      ),
      (const GuidanceFacts(otzariaStatus: AppStatusFact.error), _app),
    ]) {
      test('${status.otzariaStatus.name}/${status.libraryStatus.name}', () {
        final g = deriveHomeGuidance(status);
        expect(g.primary, GuidancePrimary.attention);
        expect(g.attentionItem, item);
      });
    }

    test('פעולה זמינה גוברת על תקלה ברכיב אחר', () {
      final g = deriveHomeGuidance(
        const GuidanceFacts(
          otzariaStatus: AppStatusFact.updateAvailable,
          libraryStatus: LibraryStatusFact.error,
        ),
      );
      expect(g.primary, GuidancePrimary.updateHere);
      expect(g.hereItems, [_app]);
    });
  });

  test('מצב הכונן עובר כמו שהוא', () {
    final g = deriveHomeGuidance(
      const GuidanceFacts(readOnly: true, driveFull: true),
    );
    expect(g.readOnly, isTrue);
    expect(g.driveFull, isTrue);
  });

  group('deriveTileStatus', () {
    // התוכנה והספרייה מדברות מאותה נקודת מבט: מה בכונן מול המחשב ומול הרשת.
    test('התוכנה והספרייה מקבלות אותו מצב לאותן עובדות', () {
      final cases = <(AppStatusFact, LibraryStatusFact, bool, TileStatus)>[
        (
          AppStatusFact.needsDownload,
          LibraryStatusFact.needsDownload,
          false,
          TileStatus.nothingOnDrive,
        ),
        (
          AppStatusFact.needsDownload,
          LibraryStatusFact.needsDownload,
          true,
          TileStatus.onlineAvailable,
        ),
        (
          AppStatusFact.updateAvailable,
          LibraryStatusFact.updateAvailable,
          false,
          TileStatus.updateHere,
        ),
        (
          AppStatusFact.upToDate,
          LibraryStatusFact.upToDate,
          true,
          TileStatus.onlineAvailable,
        ),
        (
          AppStatusFact.upToDate,
          LibraryStatusFact.upToDate,
          false,
          TileStatus.upToDate,
        ),
      ];
      for (final (app, library, online, expected) in cases) {
        final f = GuidanceFacts(
          otzariaStatus: app,
          libraryStatus: library,
          online: online,
          onlineApp: online,
          onlineLibrary: online,
        );
        final download = deriveHomeGuidance(f).downloadItems;
        expect(
          deriveTileStatus(_app, f, download: download),
          expected,
          reason: '$app online=$online',
        );
        expect(
          deriveTileStatus(_library, f, download: download),
          expected,
          reason: '$library online=$online',
        );
      }
    });

    test('תוכנה', () {
      TileStatus app(AppStatusFact s, {bool installed = true}) =>
          deriveTileStatus(
            _app,
            GuidanceFacts(otzariaStatus: s, otzariaInstalled: installed),
          );
      expect(app(AppStatusFact.idle), TileStatus.unknown);
      expect(app(AppStatusFact.checking), TileStatus.checking);
      expect(app(AppStatusFact.installing), TileStatus.working);
      expect(app(AppStatusFact.upToDate), TileStatus.upToDate);
      expect(app(AppStatusFact.installedIsNewer), TileStatus.newerHere);
      expect(app(AppStatusFact.updateAvailable), TileStatus.updateHere);
      expect(
        app(AppStatusFact.updateAvailable, installed: false),
        TileStatus.installHere,
      );
      expect(app(AppStatusFact.needsDownload), TileStatus.nothingOnDrive);
      expect(app(AppStatusFact.error), TileStatus.attention);
    });

    test('ספרייה', () {
      TileStatus library(
        LibraryStatusFact s, {
        bool consent = false,
        bool applying = false,
        bool fresh = false,
      }) =>
          deriveTileStatus(
            _library,
            GuidanceFacts(
              libraryStatus: s,
              semanticConsentRequired: consent,
              libraryApplyActive: applying,
              libraryFreshInstall: fresh,
            ),
          );
      expect(library(LibraryStatusFact.updating), TileStatus.working);
      expect(
        library(LibraryStatusFact.upToDate, applying: true),
        TileStatus.working,
      );
      // רק החיפוש החכם מחכה לתשובה: כמו הגיבור, "עדכון המחשב הזה".
      expect(
        library(LibraryStatusFact.upToDate, consent: true),
        TileStatus.updateHere,
      );
      expect(
        library(LibraryStatusFact.error, consent: true),
        TileStatus.needsConsent,
      );
      expect(
        library(LibraryStatusFact.updating, consent: true),
        TileStatus.working,
      );
      expect(
        library(LibraryStatusFact.updateAvailable, consent: true),
        TileStatus.updateHere,
      );
      expect(library(LibraryStatusFact.idle), TileStatus.unknown);
      expect(library(LibraryStatusFact.updateAvailable), TileStatus.updateHere);
      expect(
        library(LibraryStatusFact.updateAvailable, fresh: true),
        TileStatus.installHere,
      );
      expect(
          library(LibraryStatusFact.needsDownload), TileStatus.nothingOnDrive);
      for (final s in [
        LibraryStatusFact.error,
        LibraryStatusFact.needsManualPath,
      ]) {
        expect(library(s), TileStatus.attention, reason: s.name);
      }
      // כונן שהוכן למחשב אחר אינו תקלה.
      expect(
        library(LibraryStatusFact.personalTargetElsewhere),
        TileStatus.preparedElsewhere,
      );
    });

    test('תוספים', () {
      expect(
        deriveTileStatus(_plugins, const GuidanceFacts(pluginsLoading: true)),
        TileStatus.checking,
      );
      expect(
        deriveTileStatus(
            _plugins, const GuidanceFacts(pluginUpdatesOnDrive: 2)),
        TileStatus.updateHere,
      );
      expect(
        deriveTileStatus(_plugins, const GuidanceFacts()),
        TileStatus.upToDate,
      );
    });

    test('רכיב שההורדה מביאה — "יש עדכון להוריד לכונן", גם כשהוא חסר בכונן',
        () {
      TileStatus tile(GuidanceItem item, GuidanceFacts f) =>
          deriveTileStatus(item, f, download: [item]);
      expect(
        tile(_app, const GuidanceFacts()),
        TileStatus.onlineAvailable,
      );
      expect(
        tile(
          _library,
          const GuidanceFacts(libraryStatus: LibraryStatusFact.needsDownload),
        ),
        TileStatus.onlineAvailable,
      );
      expect(
        tile(_plugins, const GuidanceFacts(pluginUpdatesOnDrive: 2)),
        TileStatus.onlineAvailable,
      );
      // מה שלא נכלל בהורדה — כמו קודם.
      expect(
        deriveTileStatus(_library, const GuidanceFacts(), download: [_app]),
        TileStatus.upToDate,
      );
    });

    test('פעולה רצה, בדיקה, תקלה והסכמה גוברות על "יש עדכון להוריד לכונן"', () {
      TileStatus app(AppStatusFact s) => deriveTileStatus(
            _app,
            GuidanceFacts(otzariaStatus: s),
            download: const [_app],
          );
      expect(app(AppStatusFact.installing), TileStatus.working);
      expect(app(AppStatusFact.checking), TileStatus.checking);
      expect(app(AppStatusFact.error), TileStatus.attention);
      expect(
        deriveTileStatus(
          _library,
          const GuidanceFacts(
            semanticConsentRequired: true,
            otzariaInstalled: false,
            libraryStatus: LibraryStatusFact.needsDownload,
          ),
          download: const [_library],
        ),
        TileStatus.needsConsent,
      );
    });

    test('הגיבור והאריח מסכימים: כל מה שבהורדה מסומן באריח', () {
      const f = GuidanceFacts(
        online: true,
        onlineApp: true,
        onlineLibrary: true,
        libraryStatus: LibraryStatusFact.needsDownload,
      );
      final g = deriveHomeGuidance(f);
      expect(g.downloadItems, [_app, _library]);
      for (final item in g.downloadItems) {
        expect(
          deriveTileStatus(item, f, download: g.downloadItems),
          TileStatus.onlineAvailable,
        );
      }
    });
  });

  test('עדכון כאן: סדר השלבים', () {
    expect(
      updateHereStages(
          firstInstall: true, app: true, library: true, plugins: true),
      [_app, _library],
    );
    expect(
      updateHereStages(
          firstInstall: false, app: true, library: true, plugins: true),
      [_library, _app, _plugins],
    );
    expect(
      updateHereStages(
        firstInstall: false,
        app: false,
        library: false,
        plugins: true,
      ),
      [_plugins],
    );
  });

  test('העובדות מקבילות בשמן למצבי הקונטרולרים — המתאם נשען על זה', () {
    expect(
      AppStatusFact.values.map((v) => v.name),
      OtzariaModuleStatus.values.map((v) => v.name),
    );
    expect(
      LibraryStatusFact.values.map((v) => v.name),
      LibraryModuleStatus.values.map((v) => v.name),
    );
  });

  test('home_guidance.dart טהור: בלי Flutter ובלי ייבוא מקומי', () {
    final source = File('lib/src/shell/home_guidance.dart').readAsStringSync();
    expect(RegExp(r'^import ', multiLine: true).hasMatch(source), isFalse);
  });
}

void _runCases(List<_Case> cases) {
  for (final c in cases) {
    test(c.name, () {
      final g = deriveHomeGuidance(c.facts);
      expect(g.primary, c.primary, reason: '$g');
      expect(g.secondary, c.secondary, reason: '$g');
      expect(g.hereItems, c.here, reason: '$g');
      expect(g.downloadItems, c.download, reason: '$g');
      expect(g.showOtzariaOpenBanner, c.banner, reason: '$g');
      expect(g.otzariaOpenBlocksUpdate, c.blocks, reason: '$g');
    });
  }
}
