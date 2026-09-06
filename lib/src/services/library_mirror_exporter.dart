import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/delta_manifest.dart';
import '../models/library_release.dart';
import '../models/library_update_plan.dart';
import '../models/patch_table_spec.dart';
import 'apply_time_estimate.dart';
import 'disk_space_probe.dart';
import 'download_scheduler.dart';
import 'github_library_release_client.dart';
import 'library_update_discovery.dart';
import 'local_mirror_library_release_client.dart';
import 'patch_downloader.dart';

/// בונה "מראה" (mirror) מקומית מלאה של כל עדכוני הספרייה מ-GitHub,
/// לתיקייה על הדיסק (USB / תיקייה משותפת) — כדי שמחשבים **בלי אינטרנט
/// בכלל** יוכלו לעדכן את ה-DB אחר-כך דרך [LocalMirrorLibraryReleaseClient],
/// בלי לגעת ב-GitHub בכלל.
///
/// מריצים את [export] פעם אחת במחשב **עם** אינטרנט; אחר-כך מעתיקים את
/// התיקייה שנוצרה (USB וכו') ופותחים אותה במחשבים האחרים דרך "עדכן מתיקייה
/// מקומית" בלאנצ'ר.
///
/// **הערה על גודל:** המראה נושאת **עותק אחד** של ה-DB המלא (~1.5GB דחוס) ואת
/// ה-patches של [historyDepth] ה-releases האחרונים (עשרות MB כל אחד), לא את
/// כל ההיסטוריה. ראו [recentReleases]. המסד המלא הזה אינו בהכרח של הגרסה
/// האחרונה: מסד שכבר יושב במראה נשמר כל עוד יש ממנו מסלול patches ל-latest,
/// כדי שעדכון שוטף יעלה עשרות MB ולא ~1.1GB — ראו [_chooseFullDbCarrier].
/// שינוי סכמה שובר את החישוב הזה: קובצי ה-patch שחוצים אותו אינם ניתנים
/// להחלה, ולכן הם אינם נכנסים למראה והמסד המלא **החדש** מורד במקומם.
/// גם הרחבה שכתבה את המסד מחדש שוברת אותו — שם החלת קובצי העדכון אצל
/// המשתמש ארוכה בהרבה מהחלפת המסד המלא, והמראה מתאפסת למסד המלא בלבד.
/// ראו [_fullDbBeatsPatches] ו-[ApplyTimeEstimate].
///
/// `fromVersion` ב-[export] מחליף את שני אלה במצב "עדכון אישי": patches
/// מהגרסה שמותקנת אצל המשתמש ומעלה בלבד, בלי המסד המלא — ראו
/// [personalReleases]. **גם שם אותו כלל זמן חל:** כששרשרת ה-patches של
/// המשתמש ארוכה בהרבה מהמסד המלא, או שאינה קיימת כלל, המסד המלא כן יורד.
/// המצב הזה נועד לחסוך אותו, לא להשאיר את המשתמש עם העדכון היקר מבין
/// השניים.
///
/// **הנכסים יורדים במקביל, הגדול ראשון** — ראו [DownloadScheduler]. זה כל
/// ה"מאיץ" שאפשר לבנות מול GitHub: פיצול קובץ בודד לכמה חיבורים אינו עובד
/// שם, אבל קובצי ה-patch רצים לצד המסד הגדול במקום לחכות לו.
class LibraryMirrorExporter {
  LibraryMirrorExporter({
    GithubLibraryReleaseClient? client,
    http.Client? httpClient,
    this.historyDepth = defaultHistoryDepth,
    this.applyTime = const ApplyTimeEstimate(),
    DownloadScheduler? scheduler,
  })  : _scheduler = scheduler ?? DownloadScheduler(),
        _client = client ?? GithubLibraryReleaseClient(),
        _ownsClient = client == null,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    _downloader = PatchDownloader(
      httpClient: _httpClient,
      // הייצוא רק מוריד לדיסק ואינו מחלץ דבר — `downloadAndExtract` לא נקרא
      // כאן, ולכן אין למי לספק פונקציית חילוץ.
      decompress: _neverDecompress,
    );
  }

  /// כמה releases אחרונים נשמרים במראה — ראו [recentReleases]. עשרה מכסים
  /// בפועל מחשב שלא עודכן כמה חודשים, בעלות של כמה עשרות MB.
  static const int defaultHistoryDepth = 10;

  /// עומק היסטוריית ה-patches שנשמרת במראה.
  final int historyDepth;

  /// אומדן זמן העדכון אצל המשתמש, שלפיו נבחר בין היסטוריית patches לבין מסד
  /// מלא — ראו [_fullDbBeatsPatches]. ניתן להזרקה כדי שהבדיקות לא יידרשו
  /// לייצר גיגה-בייטים אמיתיים.
  final ApplyTimeEstimate applyTime;

  final GithubLibraryReleaseClient _client;
  final bool _ownsClient;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  /// מה שמריץ את הנכסים במקביל — ראו [DownloadScheduler] להסבר למה זו
  /// ההאצה היחידה שאפשרית מול GitHub. ניתן להזרקה כדי שהקבצים הנלווים
  /// יחלקו את אותה תקרת חיבורים ולא יפתחו תקרה משלהם.
  final DownloadScheduler _scheduler;

  /// ההורדה עוברת דרך [PatchDownloader] ולא דרך `http` ישר. זה לא ניקיון קוד:
  /// המוריד הזה כבר מביא זמן קצוב, אימות גודל ו-sha256, חידוש הורדה (Range +
  /// If-Range) ומחיקה של קובץ חלקי שאינו ניתן לחידוש. בלעדיו הורדת ה-DB המלא
  /// (~1GB) על חיבור שנפל התחילה מאפס בכל פעם, ושרת שנשתק תלה את הייצוא בלי
  /// גבול — וזה בדיוק המסלול שהמשתמש מריץ פעם אחת על מחשב מקוון.
  late final PatchDownloader _downloader;

  /// בונה מראה מלאה תחת [destDir] (נוצרת אם חסרה). מוריד את כל ה-releases
  /// הרלוונטיים (כאלה עם delta manifests ו/או DB מלא), כולל כל קובצי ה-patch
  /// שכל manifest מצביע עליהם, וכותב `releases.json` בסוף.
  ///
  /// [fromVersion] — מצב "עדכון אישי": מורידים רק patches מהגרסה הזו ומעלה,
  /// **בלי** המסד המלא. ראו [personalReleases].
  ///
  /// מחזיר `false` במצב אישי שבו אין גרסה חדשה מ-[fromVersion] — ואז המראה
  /// הקיימת אינה נגעת בכלל: היא עדיין תקפה, ומחיקת נכסיה הייתה מוחקת מראה
  /// שלמה רק בגלל שהמחשב הזה מעודכן.
  Future<bool> export({
    required String destDir,
    bool allowPrerelease = true,
    int? fromVersion,
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String warning)? onWarning,
    bool Function()? isCancelled,
  }) async {
    final strings = AppL10n.strings.libraryDomain;

    onStage?.call(strings.exportLoadingReleases);
    final all = await _client.fetchReleases();
    final eligible = LibraryUpdateDiscovery.eligibleReleases(
      all,
      allowPrerelease: allowPrerelease,
    );
    final personal = fromVersion != null;
    final relevant = personal
        ? personalReleases(eligible, fromVersion)
        : recentReleases(eligible);

    // הגרסה הגבוהה ביותר שקיימת בכלל, וה-release שנושא את המסד המלא שלה.
    // במצב אישי `relevant` מסנן החוצה releases בלי קובצי עדכון, ולכן שניהם
    // נגזרים מ-[eligible] — אחרת גרסה שיצאה עם מסד מלא בלבד הייתה נעלמת.
    final latestEligible = _latestVersionOf(eligible);
    final personalCarrier =
        personal ? _newestFullDbCarrier(eligible, latestEligible) : null;

    if (relevant.isEmpty) {
      if (!personal) throw StateError(strings.exportNoReleases);
      // release שיצא בלי קובצי עדכון כלל אינו "אין גרסה חדשה": המסד המלא
      // הוא כל המסלול אליו, וזה בדיוק המקרה שבו גם מצב אישי מוריד אותו.
      if (personalCarrier == null || latestEligible <= fromVersion) {
        onStage?.call(strings.exportPersonalUpToDate(fromVersion));
        return false;
      }
    }

    final root = Directory(destDir);
    await root.create(recursive: true);
    final assetsRoot = Directory(p.join(destDir, 'assets'));
    await assetsRoot.create(recursive: true);

    if (personal) onStage?.call(strings.exportPersonalFrom(fromVersion));

    // עבור כל release: אילו assets בפועל נדרשים — ה-manifests עצמם וקובצי
    // ה-patch שהם מצביעים עליהם. ה-DB המלא נוסף אחר כך, כי בחירת הנשא שלו
    // תלויה ב-edges שנאספים כאן. משתמשים ב-Map לפי שם כדי לא להוריד את אותו
    // asset פעמיים אם כמה manifests מצביעים עליו.
    final neededByRelease = <LibraryRelease, Map<String, ReleaseAsset>>{};
    final edges = <({int from, int to})>[];
    // הסכמה הגבוהה שנראתה ואיננו יודעים להחיל, 0 אם אין כזו. [blockingFormat]
    // הוא אותו דבר על ציר פורמט ה-`patch.db`.
    var blockingSchema = 0;
    var blockingFormat = 0;
    // הנכסים של כל קשת קבילה, כדי שאפשר יהיה להסיר קשת שאין בה תועלת —
    // ראו [_dropUselessPatches]. ה-manifests של קשתות שנפסלו אינם נכנסים
    // לכאן, ולכן הם נשארים במראה כהסבר.
    final mirroredEdges = <MirroredEdge>[];
    for (final release in relevant) {
      _throwIfCancelled(isCancelled);
      final needed = <String, ReleaseAsset>{};
      for (final manifestAsset in release.deltaManifestAssets) {
        needed[manifestAsset.name] = manifestAsset;
        final manifest = await _fetchManifestOrNull(
          manifestAsset,
          onWarning: onWarning,
        );
        if (manifest == null) continue;
        // patch שסכמתו אינה מוכרת ייכשל ב-preflight של `PatchApplier`, ולכן
        // קובציו (מאות MB) אינם נכנסים למראה ו-`_pruneStaleAssets` מוציא גם
        // כאלה שכבר עליה. ה-manifest עצמו (מאות בתים) כן נשמר — בלעדיו
        // הגרסה החדשה נעלמת מהמראה ונראית באופליין כ"מעודכן".
        if (!_schemaAppliable(manifest)) {
          final schema = _unsupportedSchemaOf(manifest);
          if (schema > blockingSchema) blockingSchema = schema;
          onWarning?.call(strings.exportSkippingUnappliablePatch(
            release.tag,
            manifest.patchFiles.first.file,
            schema,
          ));
          continue;
        }
        // הציר השני: הסכמה מוכרת אבל פורמט ה-`patch.db` אינו.
        if (!_patchFormatAppliable(manifest)) {
          final format = manifest.patchFormatVersion!;
          if (format > blockingFormat) blockingFormat = format;
          onWarning?.call(strings.exportSkippingUnsupportedPatchFormat(
            release.tag,
            manifest.patchFiles.first.file,
            format,
          ));
          continue;
        }
        var complete = true;
        final fileNames = <String>[];
        for (final patchFile in manifest.patchFiles) {
          final asset = release.assetByName(patchFile.file);
          if (asset != null) {
            needed[asset.name] = asset;
            fileNames.add(asset.name);
          } else {
            complete = false;
            // ה-manifest מצביע על קובץ שאינו ברשימת הנכסים: או שהוא עוד עולה
            // (סונן לפי `state`), או שהמפיק הסיר אותו. בשני המקרים ה-edge
            // יעלם באופליין, ולכן זה נאמר במקום להיעלם בשקט.
            onWarning?.call(strings.exportPatchAssetMissing(
              release.tag,
              patchFile.file,
            ));
          }
        }
        // רק edge שכל קבציו יורדים ייבנה גם באופליין — ראו
        // `LibraryUpdateDiscovery._buildEdge`. ספירת edge חסר כאן הייתה
        // משאירה את המסד המלא הישן על סמך מסלול שאינו קיים.
        if (complete) {
          edges.add((from: manifest.fromVersion, to: manifest.toVersion));
          mirroredEdges.add((
            release: release,
            from: manifest.fromVersion,
            to: manifest.toVersion,
            assetNames: [manifestAsset.name, ...fileNames],
          ));
        }
      }
      neededByRelease[release] = needed;
    }

    // ה-DB המלא נדרש **פעם אחת** לכל המראה, לא לכל release: המסלול המלא
    // באופליין בוחר תמיד את הנכס של הגרסה הגבוהה ביותר שנושאת אותו (ראו
    // LibraryUpdateDiscovery.discover), ולכן עותק לכל release היה מוסיף כ-1.5GB
    // מתים לכל אחד מהם. במצב אישי הוא נשמט לגמרי — זה כל החיסכון שבמצב הזה.
    if (blockingSchema > 0 || blockingFormat > 0) {
      final latestSeen = _latestVersionOf(relevant);
      // המסלול לגרסה כזו הוא המסד המלא ולא קובצי עדכון, בדיוק כמו באוצריא
      // המקוונת. במצב אישי ההכרזה נדחית לענף שלהלן: אם יש מסד מלא הוא ירד
      // (למרות שהמצב הזה נבנה כדי לדלג עליו), ואם אין — זו אזהרה.
      if (personal) {
        if (personalCarrier == null) {
          onWarning?.call(
              strings.exportPersonalNoFullDbEither(fromVersion, latestSeen));
        }
      } else if (blockingSchema > 0) {
        onStage?.call(
            strings.exportFullDbRequiredBySchema(blockingSchema, latestSeen));
      } else {
        onStage?.call(strings.exportFullDbRequiredByPatchFormat(
          blockingFormat,
          latestSeen,
        ));
      }
    }

    final fullDbCarrier = personal
        ? null
        : _chooseFullDbCarrier(relevant, edges, assetsRoot.path, onStage);
    if (fullDbCarrier != null) {
      final full = fullDbCarrier.fullDbAsset!;
      neededByRelease[fullDbCarrier]![full.name] = full;

      // **קובצי עדכון שהמסד המלא כבר עוקף אינם נשמרים.** אחרי מעבר סכמה
      // השרשרת נקטעת מתחת לגרסת המסד המלא, ואז ה-planner באופליין בוחר בו
      // בכל מקרה — עשרה releases של patches הם מאות MB מתים על הכונן. ראו
      // `LibraryUpdatePlanner.plan`: דלתא נבחרת רק כשהיא מגיעה גבוה לפחות
      // כמו המסלול המלא.
      final latestVersion = _latestVersionOf(relevant);
      final dropped = _dropUselessPatches(
        neededByRelease: neededByRelease,
        mirroredEdges: mirroredEdges,
        edges: edges,
        carrier: fullDbCarrier,
        latestVersion: latestVersion,
      );
      if (dropped > 0) {
        onStage?.call(strings.exportSkippingPatchesFullDbWins(
          dropped,
          LibraryUpdateDiscovery.releaseVersionOf(fullDbCarrier),
        ));
      }

      // **הרחבה שכתבה מחדש את המסד:** החלת קובצי העדכון אצל המשתמש ארוכה
      // בהרבה מהחלפת המסד המלא — ואז ההעדפה לשמור מסד ישן ולהוריד patches
      // עובדת נגד מי שמעדכן. ראו [_fullDbBeatsPatches].
      final beaten = _fullDbBeatsPatches(
        relevant,
        neededByRelease,
        mirroredEdges,
        latestVersion: latestVersion,
      );
      if (beaten != null) {
        _switchToFullDbOnly(
          beaten,
          neededByRelease: neededByRelease,
          onStage: onStage,
        );
      }
    }

    // **אותו כלל בדיוק במצב אישי.** המצב הזה בנוי כדי לדלג על המסד המלא —
    // זה כל החיסכון שבו — אבל דילוג עליו כשהשרשרת של המשתמש ארוכה בהרבה
    // ממנו (או שאינה קיימת בכלל) מותיר אותו עם העדכון היקר משניהם. הנשא
    // מגיע מ-[eligible] ולא מ-`relevant`, כי `personalReleases` מסנן החוצה
    // release שאין בו קובצי עדכון.
    if (personal && personalCarrier != null) {
      final beaten = _fullDbBeatsPatches(
        [personalCarrier],
        neededByRelease,
        mirroredEdges,
        latestVersion: latestEligible,
        fromVersion: fromVersion,
      );
      if (beaten != null) {
        _switchToFullDbOnly(
          beaten,
          neededByRelease: neededByRelease,
          onStage: onStage,
        );
      }
    }

    // release שנשאר בלי נכסים **נשאר ברשימה**: `_pruneStaleAssets` ירוקן את
    // תיקייתו, אבל הגרסה שלו עדיין נספרת ל-latest באופליין (`releaseVersionOf`
    // נופל ל-tag). הסרתו הייתה מעלימה גרסה שקיימת.
    final plannedByRelease = <LibraryRelease, List<ReleaseAsset>>{
      for (final entry in neededByRelease.entries)
        entry.key: entry.value.values.toList(growable: false),
    };

    final totalAssets =
        plannedByRelease.values.fold<int>(0, (n, l) => n + l.length);

    // בודקים מקום פנוי לפי מה שנשאר להוריד בפועל, לא לפי גודל המראה: נכס
    // שכבר יושב שלם על הכונן אינו צורך מקום נוסף. שיא התפוסה גבוה מהמראה
    // הסופית, כי ה-prune רץ רק בסוף — כלומר בזמן מיזוג release חדש יש על
    // הכונן שני עותקים של המסד הדחוס.
    _ensureSpaceForPlan(destDir, assetsRoot, plannedByRelease);

    var doneAssets = 0;
    // מדווחים את היעד עוד לפני הנכס הראשון: אחרת מד ההתקדמות אינו יודע לכמה
    // נכסים לחכות עד שהראשון (המסד המלא, ~1GB) מסתיים.
    onAssetProgress?.call(0, totalAssets);

    // רשימה שטוחה של כל ההורדות, **הגדולה ראשונה**: המסד המלא (~1.5GB) הוא
    // ארוך פי עשרות מכל השאר, ואם הוא יתחיל אחרון כל שאר החיבורים יעמדו
    // בטלים בזמן שהוא לבדו רץ. פתיחה בו נותנת לקובצי ה-patch לרוץ לצידו.
    final jobs =
        <({LibraryRelease release, ReleaseAsset asset, String dest})>[];
    for (final entry in plannedByRelease.entries) {
      final tagDir =
          Directory(p.join(assetsRoot.path, _safeDirName(entry.key.tag)));
      await tagDir.create(recursive: true);
      for (final asset in entry.value) {
        jobs.add((
          release: entry.key,
          asset: asset,
          dest: p.join(tagDir.path, asset.name),
        ));
      }
    }
    jobs.sort((a, b) => b.asset.size.compareTo(a.asset.size));

    // מונה בייטים אחד לכל התוכנית: בהורדה מקבילה אין "הקובץ הנוכחי", וגם
    // אין טעם באחד — מד שמתאר את כל ההורדה גם לא מתאפס בין נכס לנכס.
    final bytes = ByteProgressAggregator(
      totalBytes: jobs.fold<int>(
        0,
        (sum, job) => sum + (job.asset.size > 0 ? job.asset.size : 0),
      ),
      onProgress: onBytesProgress,
    );

    await _scheduler.run<void>([
      for (final job in jobs)
        () async {
          _throwIfCancelled(isCancelled);
          onStage?.call(
              strings.exportDownloading(job.release.tag, job.asset.name));
          final progress = bytes.slot();
          // נכס שכבר יושב שלם על הדיסק מדלג על ההורדה ורק מאומת — אימות
          // sha256 של 1.1GB מכונן נייד לוקח דקה, וללא הכרזה הוא נראה כתקיעה.
          var announcedVerify = false;
          await _downloader.downloadToFile(
            url: job.asset.downloadUrl,
            destPath: job.dest,
            // ה-manifests נכתבים ע"י GitHub ללא `size` אמין בכל המקרים; `size`
            // של asset אמיתי כן מדויק, ואי-התאמה שלו היא הורדה שנקטעה.
            expectedSize: job.asset.size > 0 ? job.asset.size : null,
            expectedSha256: _sha256FromDigest(job.asset.digest),
            // מזהה ה-asset הוא הזהות היציבה שמאפשרת לחדש הורדה שנקטעה במקום
            // להתחיל מאפס — ראו PatchDownloader.downloadToFile.
            resumeToken: job.asset.id?.toString(),
            onProgress: progress,
            onVerifyProgress: (verified, total) {
              if (!announcedVerify) {
                announcedVerify = true;
                onStage?.call(
                    strings.exportVerifying(job.release.tag, job.asset.name));
              }
              progress(verified, total);
            },
            isCancelled: isCancelled,
          );
          doneAssets++;
          onAssetProgress?.call(doneAssets, totalAssets);
        },
    ]);

    // נבנה רק אחרי שכל ההורדות הצליחו — כשל של אחת זורק, ולכן כל נכס
    // שברשימה אכן יושב שלם בדיסק.
    final mirroredReleases = <LibraryRelease>[
      for (final entry in plannedByRelease.entries)
        LibraryRelease(
          tag: entry.key.tag,
          isPrerelease: entry.key.isPrerelease,
          isDraft: entry.key.isDraft,
          publishedAt: entry.key.publishedAt,
          assets: [
            for (final asset in entry.value)
              ReleaseAsset(
                name: asset.name,
                downloadUrl: p.relative(
                  p.join(
                    assetsRoot.path,
                    _safeDirName(entry.key.tag),
                    asset.name,
                  ),
                  from: destDir,
                ),
                size: asset.size,
                id: asset.id,
                updatedAt: asset.updatedAt,
                digest: asset.digest,
              ),
          ],
        ),
    ];

    onStage?.call(
      strings.exportWritingManifest(
        LocalMirrorLibraryReleaseClient.manifestFileName,
      ),
    );
    // כתיבה אטומית: קובץ זמני, flush, ואז rename. `writeAsString` ישיר מקצץ
    // מיד את המניפסט התקין, וקטיעה (שליפת הכונן) הייתה משאירה JSON פגום —
    // שהמחשב הלא-מקוון קורא כ"מראה שבורה" למרות שכל הנכסים שלמים עליו.
    final manifestPath =
        p.join(destDir, LocalMirrorLibraryReleaseClient.manifestFileName);
    final manifestTmp = File('$manifestPath.tmp');
    await manifestTmp.writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'releases': mirroredReleases.map((r) => r.toMirrorJson()).toList(),
      }),
      flush: true,
    );
    await manifestTmp.rename(manifestPath);

    // רק אחרי שהמניפסט החדש בתוקף: נכסים שאינם בו לא ייקראו לעולם ורק תופסים
    // מקום. בלי הניקוי כל release שנפל מחלון ההיסטוריה נשאר על הכונן לעד.
    await _pruneStaleAssets(assetsRoot, plannedByRelease);

    onStage?.call(strings.exportDone);
    return true;
  }

  /// זורק כשידוע בוודאות שאין מקום להורדה שנותרה. מדידה שנכשלה אינה חוסמת —
  /// ראו [DiskSpaceProbe]. נכס שכבר על הדיסק נספר לפי מה שחסר בו בלבד.
  void _ensureSpaceForPlan(
    String destDir,
    Directory assetsRoot,
    Map<LibraryRelease, List<ReleaseAsset>> planned,
  ) {
    var needed = 0;
    for (final entry in planned.entries) {
      final tagDir = p.join(assetsRoot.path, _safeDirName(entry.key.tag));
      for (final asset in entry.value) {
        if (asset.size <= 0) continue;
        final existing = File(p.join(tagDir, asset.name));
        final have = existing.existsSync() ? existing.lengthSync() : 0;
        final missing = asset.size - have;
        if (missing > 0) needed += missing;
      }
    }
    if (needed == 0) return;
    if (!DiskSpaceProbe.isKnownInsufficient(destDir, needed)) return;
    final free = DiskSpaceProbe.freeBytesFor(destDir) ?? 0;
    throw StateError(AppL10n.strings.libraryDomain.mirrorNotEnoughDiskSpace(
      destDir,
      _formatBytes(needed),
      _formatBytes(free),
    ));
  }

  static String _formatBytes(int bytes) {
    const gb = 1 << 30;
    const mb = 1 << 20;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).round()} MB';
  }

  /// מספר הניסיונות לשליפת manifest. הם קבצים של מאות בתים, ולכן ניסיון חוזר
  /// זול — ובלעדיו בקשה אחת רועדת מתוך ~13 מוחקת edge שלם מהמראה.
  static const int _manifestAttempts = 3;

  /// שולף manifest, ומבחין בין שני כשלים שאינם דומים:
  /// **manifest פגום** ([FormatException]) — נתון קבוע, מדלגים על ה-edge בדיוק
  /// כמו `LibraryUpdateDiscovery._buildEdge` באופליין; **כשל רשת/HTTP** — נתון
  /// חולף, ולכן מנסים שוב ואם גם זה נכשל **זורקים**. בליעה שקטה שלו כתבה
  /// `releases.json` בלי קובצי ה-patch, ואז `_pruneStaleAssets` מחק patch תקין
  /// שריצה קודמת הורידה — מראה שנראית שלמה וחסר בה edge.
  Future<DeltaManifest?> _fetchManifestOrNull(
    ReleaseAsset manifestAsset, {
    void Function(String warning)? onWarning,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _manifestAttempts; attempt++) {
      try {
        return await _client.fetchManifest(manifestAsset.downloadUrl);
      } on FormatException catch (e) {
        onWarning?.call(AppL10n.strings.libraryDomain
            .exportManifestUnreadable(manifestAsset.name, e.message));
        return null;
      } catch (e) {
        lastError = e;
        if (attempt < _manifestAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
    throw StateError(AppL10n.strings.libraryDomain
        .exportManifestFetchFailed(manifestAsset.name, '$lastError'));
  }

  /// מוחק מתוך [assetsRoot] כל תיקיית tag ונכס שאינם בתוכנית — best-effort:
  /// כשל מחיקה (קובץ נעול) אינו מפיל ייצוא שכבר הצליח.
  Future<void> _pruneStaleAssets(
    Directory assetsRoot,
    Map<LibraryRelease, List<ReleaseAsset>> planned,
  ) async {
    final keepByDir = <String, Set<String>>{};
    for (final entry in planned.entries) {
      keepByDir[_safeDirName(entry.key.tag)] = {
        for (final asset in entry.value) ...[
          asset.name,
          // קובץ הצד הוא חלק מזהות הנכס: בלעדיו הריצה הבאה מוחקת נכס שלם
          // ומורידה 1.5GB מחדש. ראו PatchDownloader.resumeSidecarPath.
          p.basename(PatchDownloader.resumeSidecarPath(asset.name)),
        ],
      };
    }

    await for (final entity in assetsRoot.list(followLinks: false)) {
      try {
        final name = p.basename(entity.path);
        final keep = keepByDir[name];
        if (entity is Directory) {
          if (keep == null) {
            await entity.delete(recursive: true);
            continue;
          }
          await for (final file in entity.list(followLinks: false)) {
            if (!keep.contains(p.basename(file.path))) {
              await file.delete(recursive: true);
            }
          }
        } else {
          // קובץ ישר תחת assets/ — לא נוצר על ידי הייצוא הזה.
          await entity.delete();
        }
      } catch (_) {
        // מקום מבוזבז בלבד; לא סיבה להכשיל את ההורדה.
      }
    }
  }

  /// [historyDepth] ה-releases האחרונים שנושאים תוכן מסד, ואיתם — אם אף אחד
  /// מהם לא נושא `seforim.db.zst` — האחרון שכן נושא כזה, כדי שתמיד יהיה
  /// מסלול הורדה מלאה במראה.
  ///
  /// **למה לא כל ההיסטוריה:** אוצריא המקוונת בוחרת מסלול patches מתוך הגרף
  /// המלא, אבל מראה מלאה הגיעה לכמה ג'יגה-בייט והיעד הוא כונן נייד. עומק של
  /// כמה גרסאות מכסה בפועל את מי שמעדכן מדי פעם — קובצי patch הם עשרות MB
  /// לעומת ~1.1GB של המסד המלא — ומי שרחוק יותר נופל להורדה המלאה, שקיימת
  /// במראה תמיד.
  List<LibraryRelease> recentReleases(List<LibraryRelease> eligible) {
    final withDbContent = eligible
        .where((r) => r.deltaManifestAssets.isNotEmpty || r.fullDbAsset != null)
        .toList()
      ..sort((a, b) => LibraryUpdateDiscovery.releaseVersionOf(b)
          .compareTo(LibraryUpdateDiscovery.releaseVersionOf(a)));
    if (withDbContent.isEmpty) return const [];

    final kept = <LibraryRelease>{
      ...withDbContent.take(historyDepth < 1 ? 1 : historyDepth),
    };
    if (!kept.any((r) => r.fullDbAsset != null)) {
      for (final release in withDbContent) {
        if (release.fullDbAsset != null) {
          kept.add(release);
          break;
        }
      }
    }
    return kept.toList(growable: false);
  }

  /// מצב "עדכון אישי": כל ה-releases שגרסתם **גבוהה** מ-[fromVersion], בלי
  /// חסימת עומק ובלי המסד המלא. ריק פירושו "המחשב הזה מעודכן", לא שגיאה.
  ///
  /// ה-edge `patch-vN-vM` יושב ב-release שגרסתו M, ולכן "גבוה מ-[fromVersion]"
  /// שומר בדיוק את השרשרת מהגרסה המקומית ולמעלה — עשרות MB לכל צעד, לעומת
  /// ~1.5GB של המסד המלא. אין כאן מרווח ביטחון: גרסה מקומית שאינה מה שנרשם
  /// תיתקל ב-`blocked` מנומק במחשב היעד, ולא בעדכון שקט של הקובץ הלא נכון.
  List<LibraryRelease> personalReleases(
    List<LibraryRelease> eligible,
    int fromVersion,
  ) {
    return eligible
        .where((r) =>
            r.deltaManifestAssets.isNotEmpty &&
            LibraryUpdateDiscovery.releaseVersionOf(r) > fromVersion)
        .toList(growable: false);
  }

  /// ה-release שממנו מורידים את ה-DB המלא. ברירת המחדל היא הגרסה הגבוהה
  /// שנושאת `seforim.db.zst`, אבל **מסד מלא ישן שכבר יושב במראה מנצח אותה**
  /// כל עוד יש ממנו מסלול patches לגרסה האחרונה: כל release ב-SeforimLibrary
  /// נושא מסד מלא משלו, ולכן בלי ההעדפה הזו כל עדכון היה מוריד ~1.1GB מחדש
  /// בשביל תוצאה שקובצי עדכון של עשרות MB מגיעים אליה בדיוק באותה מידה.
  ///
  /// המחיר: התקנה על מחשב ריק מקבלת את המסד הישן ואז את שרשרת ה-patches —
  /// ראו `LibraryUpdatePlanner.plan` ו-`LibraryManager.applyUpdate`, שמריצים
  /// את שני הצעדים ברצף.
  ///
  /// [edges] מגיע **מסונן** מ-patches שסכמתם אינה מוכרת, ולכן מסד ישן שהמסלול
  /// ממנו חוצה שינוי סכמה אינו "מגיע" ל-latest ומפנה את מקומו למסד המלא החדש.
  /// זה מה שמונע את המצב שבו מסד v21 נשמר בשביל שרשרת שנפסלת בהחלה.
  LibraryRelease? _chooseFullDbCarrier(
    List<LibraryRelease> releases,
    List<({int from, int to})> edges,
    String assetsRootPath,
    void Function(String stage)? onStage,
  ) {
    final carriers = releases.where((r) => r.fullDbAsset != null).toList()
      ..sort((a, b) => LibraryUpdateDiscovery.releaseVersionOf(b)
          .compareTo(LibraryUpdateDiscovery.releaseVersionOf(a)));
    if (carriers.isEmpty) return null;

    final newest = carriers.first;
    // כבר על הדיסק — אין מה לחסוך, וגם אין טעם לרדת לגרסה ישנה יותר.
    if (_isCompleteOnDisk(assetsRootPath, newest)) return newest;

    var latest = LibraryUpdateDiscovery.releaseVersionOf(newest);
    for (final edge in edges) {
      if (edge.to > latest) latest = edge.to;
    }

    for (final candidate in carriers.skip(1)) {
      if (!_isCompleteOnDisk(assetsRootPath, candidate)) continue;
      final version = LibraryUpdateDiscovery.releaseVersionOf(candidate);
      if (!_reaches(edges, version, latest)) continue;
      onStage?.call(AppL10n.strings.libraryDomain
          .exportReusingFullDb(version, candidate.tag));
      return candidate;
    }
    return newest;
  }

  /// האם שני קצות ה-patch בסכמות שאפשר להחיל — אותו כלל בדיוק שמסנן קשתות
  /// ב-`LibraryUpdateDiscovery`, כדי שהמראה לא תישא patch שהמחשב הלא-מקוון
  /// יפסול. ראו [PatchEdge.hasSupportedSchema].
  bool _schemaAppliable(DeltaManifest manifest) =>
      isSupportedSchemaVersion(manifest.fromSchemaVersion) &&
      isSupportedSchemaVersion(manifest.toSchemaVersion);

  /// הציר השני של אותה פסילה — ראו [PatchEdge.hasSupportedPatchFormat].
  bool _patchFormatAppliable(DeltaManifest manifest) {
    final format = manifest.patchFormatVersion;
    return format == null || isSupportedPatchFormatVersion(format);
  }

  /// הסכמה שבגללה ה-patch נפסל — היעד קודם, כי הוא החדשה מהשתיים.
  int _unsupportedSchemaOf(DeltaManifest manifest) =>
      isSupportedSchemaVersion(manifest.toSchemaVersion)
          ? manifest.fromSchemaVersion
          : manifest.toSchemaVersion;

  /// מוציא מהתוכנית קשתות שאין בהן תועלת מול המסד המלא, ומחזיר כמה נכסים
  /// הוסרו. 0 = לא נגענו בכלום.
  ///
  /// **הכלל:** אחרי שמחילים קשת, חייבת להישאר דרך להגיע לפחות לאן שהמסלול
  /// המלא מגיע — אחרת `LibraryUpdatePlanner` יבחר במסד המלא ממילא, והקשת
  /// היא מאות MB מתים על הכונן. לכן קשת נשמרת רק כש-`maxReach(edge.to)`
  /// מגיע ליעד ההוא.
  ///
  /// שני מצבים שהכלל תופס, ושניהם קרו בשטח (ספטמבר 2026, latest=26):
  /// כשאין קשתות אל 26 כלל — כל 411MB של v15–v23 מיותרים; וכשיש — הקשתות
  /// שנכנסות ל-23 הן עדיין מבוי סתום, כי מ-23 אין המשך.
  int _dropUselessPatches({
    required Map<LibraryRelease, Map<String, ReleaseAsset>> neededByRelease,
    required List<MirroredEdge> mirroredEdges,
    required List<({int from, int to})> edges,
    required LibraryRelease carrier,
    required int latestVersion,
  }) {
    final carrierVersion = LibraryUpdateDiscovery.releaseVersionOf(carrier);
    // היעד של המסלול המלא: המסד המלא, ועוד ההשלמה ב-patches אם היא מגיעה
    // ל-latest בדיוק (זה מה ש-`LibraryUpdatePlanner._followUpDelta` דורש).
    final fullRouteTarget = _reaches(edges, carrierVersion, latestVersion)
        ? latestVersion
        : carrierVersion;

    final reach = _maxReachByVersion(edges);
    var dropped = 0;
    for (final edge in mirroredEdges) {
      if ((reach[edge.to] ?? edge.to) >= fullRouteTarget) continue;
      final needed = neededByRelease[edge.release];
      if (needed == null) continue;
      for (final name in edge.assetNames) {
        if (needed.remove(name) != null) dropped++;
      }
    }
    return dropped;
  }

  /// האם עדיף לוותר על היסטוריית ה-patches ולהחזיק מסד מלא בלבד — ואם כן,
  /// מאיזה release להוריד אותו. `null` = לא נוגעים בכלום.
  ///
  /// **הכלל הוא זמן, לא גודל:** מה שהמשתמש משלם אינו הבייטים שבמראה אלא
  /// כמה זמן העדכון רץ אצלו, ושני המסלולים אינם מתומחרים לפי אותו דבר —
  /// החלת patch משלמת סריקת-hash של **כל** המסד בכל צעד, בנוסף להחלה עצמה.
  /// ראו [ApplyTimeEstimate], שהקבועים בו מכוילים על מדידות אמיתיות.
  ///
  /// **מה נמדד:** [_chooseFullDbCarrier] מעדיף מסד מלא שכבר יושב במראה, כי
  /// בחודש רגיל קובצי העדכון הם עשרות MB לעומת ~1.3GB — ובזמן, זה עדכון של
  /// כ-6 דקות מול כ-4. בהרחבה שכתבה את המסד מקצה לקצה (ספטמבר 2026, v27)
  /// היחס התהפך: המראה שמרה מסד של v23 והורידה 2.15GB של patches, ואצל
  /// המשתמש ההחלה ארכה **64 דקות** מול כשתי דקות של החלפת מסד מלא.
  ///
  /// **הטווח:** מסלול הדלתא אינו חייב להיות מהיר יותר — הוא חוסך ~1.3GB
  /// בהורדה במחשב המקוון, ולכן מותר לו להיות איטי במקצת. הוא מפסיד רק
  /// כשהוא יוצא מהטווח של [ApplyTimeEstimate.isOutOfRange] — גם ביחס וגם
  /// בהפרש מוחלט.
  ///
  /// **מה נמדד:** הזמן של המסלול שהמראה הזו באמת מציעה למשתמש. במצב אישי
  /// ידוע מאיזו גרסה הוא מתחיל ([fromVersion]), ולכן נמדדת **השרשרת שלו**
  /// על כל צעדיה; במראה רגילה אין משתמש אחד, ולכן נמדד הצעד הזול ביותר אל
  /// הגרסה האחרונה — מי שמעדכן באופן שוטף. אם אפילו הוא יצא מהטווח, כל מי
  /// שרחוק יותר גרוע ממנו.
  ///
  /// **`null` כשאין מסלול קובצי עדכון בכלל** מתפרש לפי המצב: במראה רגילה
  /// המסד המלא כבר בתוכנית ומה שמיותר הוסר ב-[_dropUselessPatches], ולכן
  /// אין מה לעשות; במצב אישי אין שם מסד מלא כלל, ולכן זו בדיוק הסיבה
  /// להוריד אותו — ראו [_personalRouteIsFullDb].
  ///
  /// דרישה בשני המצבים: המסד המלא חייב להגיע **לבדו** ל-latest, אחרת מחיקת
  /// הקשתות הייתה עוצרת את המראה מתחת לגרסה האחרונה.
  ({LibraryRelease carrier, double? routeSeconds, int? fromVersion})?
      _fullDbBeatsPatches(
    List<LibraryRelease> candidates,
    Map<LibraryRelease, Map<String, ReleaseAsset>> neededByRelease,
    List<MirroredEdge> mirroredEdges, {
    required int latestVersion,
    int? fromVersion,
  }) {
    final carrier = _newestFullDbCarrier(candidates, latestVersion);
    if (carrier == null) return null;
    final fullBytes = carrier.fullDbAsset!.size;
    if (fullBytes <= 0) return null;

    final route = _cheapestRouteSeconds(
      to: latestVersion,
      from: fromVersion,
      neededByRelease: neededByRelease,
      mirroredEdges: mirroredEdges,
    );
    if (route == null) {
      return fromVersion == null
          ? null
          : (carrier: carrier, routeSeconds: null, fromVersion: fromVersion);
    }
    if (!applyTime.isOutOfRange(route, applyTime.fullRouteSeconds(fullBytes))) {
      return null;
    }
    return (carrier: carrier, routeSeconds: route, fromVersion: fromVersion);
  }

  /// מחליף את התוכנית ל**מסד מלא בלבד** ומכריז על כך. אותה החלטה ואותה
  /// הודעה בשני המצבים — ההבדל היחיד הוא שבמצב אישי יש גם מקרה של "אין
  /// מסלול קובצי עדכון כלל", שאין לו זמן לדווח עליו.
  void _switchToFullDbOnly(
    ({
      LibraryRelease carrier,
      double? routeSeconds,
      int? fromVersion
    }) decision, {
    required Map<LibraryRelease, Map<String, ReleaseAsset>> neededByRelease,
    required void Function(String stage)? onStage,
  }) {
    final strings = AppL10n.strings.libraryDomain;
    final carrier = decision.carrier;
    final version = LibraryUpdateDiscovery.releaseVersionOf(carrier);
    final route = decision.routeSeconds;
    final files = _keepOnlyFullDb(neededByRelease, carrier);
    onStage?.call(route == null
        ? strings.exportPersonalNeedsFullDb(decision.fromVersion!, version)
        : strings.exportFullDbInsteadOfSlowPatches(
            files,
            ApplyTimeEstimate.minutesOf(route),
            ApplyTimeEstimate.minutesOf(
                applyTime.fullRouteSeconds(carrier.fullDbAsset!.size)),
            version,
          ));
  }

  /// הגרסה הגבוהה ביותר מבין [releases], 0 כשאין אף אחת.
  int _latestVersionOf(List<LibraryRelease> releases) {
    var latest = 0;
    for (final release in releases) {
      final version = LibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > latest) latest = version;
    }
    return latest;
  }

  /// ה-release הגבוה ביותר מבין [candidates] שנושא מסד מלא — ורק אם הוא
  /// עצמו בגרסה [latestVersion]. מסד שאינו שם היה משאיר את המשתמש מתחתיה
  /// בלי שרשרת שתשלים, אחרי שהקשתות נמחקו.
  LibraryRelease? _newestFullDbCarrier(
    List<LibraryRelease> candidates,
    int latestVersion,
  ) {
    LibraryRelease? newest;
    var newestVersion = -1;
    for (final release in candidates) {
      if (release.fullDbAsset == null) continue;
      final version = LibraryUpdateDiscovery.releaseVersionOf(release);
      if (version > newestVersion) {
        newestVersion = version;
        newest = release;
      }
    }
    return newestVersion < latestVersion ? null : newest;
  }

  /// זמן המסלול הזול ביותר בקובצי עדכון אל [to], בשניות. [from] נתון
  /// במצב אישי — ואז זו השרשרת מהגרסה שלו; בלעדיו זהו הצעד הבודד הזול
  /// ביותר שנכנס ל-[to]. `null` = אין מסלול כזה בתוכנית.
  double? _cheapestRouteSeconds({
    required int to,
    required int? from,
    required Map<LibraryRelease, Map<String, ReleaseAsset>> neededByRelease,
    required List<MirroredEdge> mirroredEdges,
  }) {
    final steps = <({int from, int to, int bytes})>[];
    for (final edge in mirroredEdges) {
      if (edge.to <= edge.from) continue; // רק קדימה
      final bytes = _plannedEdgeBytes(edge, neededByRelease);
      if (bytes == null) continue; // קשת שהוסרה מהתוכנית אינה מסלול
      steps.add((from: edge.from, to: edge.to, bytes: bytes));
    }

    if (from == null) {
      double? cheapest;
      for (final step in steps) {
        if (step.to != to) continue;
        final seconds = applyTime.deltaRouteSeconds([step.bytes]);
        if (cheapest == null || seconds < cheapest) cheapest = seconds;
      }
      return cheapest;
    }

    // הקשתות מתקדמות תמיד קדימה, ולכן מעבר על הגרסאות בסדר עולה הוא סדר
    // טופולוגי תקין — אין צורך ב-Dijkstra.
    final best = <int, double>{from: 0};
    final starts = steps.map((s) => s.from).toSet().toList()..sort();
    for (final version in starts) {
      final base = best[version];
      if (base == null) continue;
      for (final step in steps) {
        if (step.from != version) continue;
        final cost = base + applyTime.deltaRouteSeconds([step.bytes]);
        final known = best[step.to];
        if (known == null || cost < known) best[step.to] = cost;
      }
    }
    return best[to];
  }

  /// הגודל הדחוס של קשת שנשארה בתוכנית, או `null` אם נכס שלה כבר אינו בה.
  int? _plannedEdgeBytes(
    MirroredEdge edge,
    Map<LibraryRelease, Map<String, ReleaseAsset>> neededByRelease,
  ) {
    final needed = neededByRelease[edge.release];
    if (needed == null) return null;
    var bytes = 0;
    for (final name in edge.assetNames) {
      final asset = needed[name];
      if (asset == null) return null;
      if (asset.size > 0) bytes += asset.size;
    }
    return bytes;
  }

  /// משאיר בתוכנית את המסד המלא של [carrier] בלבד, ומחזיר כמה נכסים ירדו
  /// ממנה. מה שיצא נמחק מהכונן ב-[_pruneStaleAssets] — כולל המסד המלא הישן,
  /// שאין בו יותר צורך.
  int _keepOnlyFullDb(
    Map<LibraryRelease, Map<String, ReleaseAsset>> neededByRelease,
    LibraryRelease carrier,
  ) {
    var dropped = 0;
    for (final needed in neededByRelease.values) {
      dropped += needed.values.where((a) => !a.isFullDbArchive).length;
      needed.clear();
    }
    final full = carrier.fullDbAsset!;
    // במצב אישי הנשא כלל אינו ברשימת ה-releases שנבחרו — `personalReleases`
    // מסנן החוצה release שאין בו קובצי עדכון — ולכן הוא נוסף כאן.
    neededByRelease.putIfAbsent(carrier, () => {})[full.name] = full;
    return dropped;
  }

  /// לכל גרסה — הגרסה הגבוהה ביותר שאפשר להגיע אליה ממנה דרך [edges].
  /// רלקסציה חוזרת עד התייצבות; הגרף כאן הוא עשרות קשתות.
  Map<int, int> _maxReachByVersion(List<({int from, int to})> edges) {
    final reach = <int, int>{};
    for (final edge in edges) {
      reach[edge.from] = edge.from > (reach[edge.from] ?? 0)
          ? edge.from
          : (reach[edge.from] ?? edge.from);
      reach[edge.to] = reach[edge.to] ?? edge.to;
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final edge in edges) {
        if (edge.to <= edge.from) continue; // רק קדימה
        final candidate = reach[edge.to] ?? edge.to;
        if (candidate > (reach[edge.from] ?? edge.from)) {
          reach[edge.from] = candidate;
          changed = true;
        }
      }
    }
    return reach;
  }

  /// האם ה-DB המלא של [release] כבר יושב **שלם** במראה. גודל בלבד: אימות
  /// ה-sha256 ממילא רץ ב-[PatchDownloader], ו-1.1GB מכונן נייד לוקח דקה —
  /// יותר מדי בשביל החלטה שנופלת לפני שהורדה בכלל התחילה.
  bool _isCompleteOnDisk(String assetsRootPath, LibraryRelease release) {
    final asset = release.fullDbAsset;
    if (asset == null || asset.size <= 0) return false;
    final file = File(p.join(
      assetsRootPath,
      _safeDirName(release.tag),
      asset.name,
    ));
    return file.existsSync() && file.lengthSync() == asset.size;
  }

  /// האם יש מסלול patches מ-[from] ל-[to] מעל [edges]. BFS פשוט — הגרף כאן
  /// הוא עשרות edges לכל היותר, וכל מה שנדרש הוא כן/לא.
  bool _reaches(List<({int from, int to})> edges, int from, int to) {
    if (from == to) return true;
    final visited = <int>{from};
    final queue = <int>[from];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final edge in edges) {
        if (edge.from != current || edge.to <= edge.from) continue;
        if (edge.to == to) return true;
        if (visited.add(edge.to)) queue.add(edge.to);
      }
    }
    return false;
  }

  String _safeDirName(String tag) =>
      tag.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  /// ה-`digest` שמגיע מ-GitHub הוא בצורת `sha256:<hex>`; פורמט אחר (או היעדר
  /// שדה) פירושו "אין hash לאמת מולו", ולא כשל.
  String? _sha256FromDigest(String? digest) {
    const prefix = 'sha256:';
    if (digest == null || !digest.startsWith(prefix)) return null;
    return digest.substring(prefix.length);
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw StateError(AppL10n.strings.libraryDomain.exportCancelled);
    }
  }

  /// סוגר משאבי HTTP פנימיים אם נוצרו על-ידי המחלקה עצמה. ה-[_downloader]
  /// אינו הבעלים של ה-client (הוא הוזרק אליו), ולכן אין לסגור אותו כאן.
  void dispose() {
    if (_ownsClient) _client.dispose();
    if (_ownsHttpClient) _httpClient.close();
  }
}

/// ה-`decompress` ש-[PatchDownloader] דורש. הייצוא מוריד בלבד ואינו מחלץ,
/// ולכן אם מישהו יקרא בעתיד ל-`downloadAndExtract` מכאן — מוטב שייכשל בקול
/// מלהחזיר `null` שיתפרש כ"חילוץ נכשל".
Future<Uint8List?> _neverDecompress(Uint8List _) => throw UnsupportedError(
      AppL10n.strings.libraryDomain.exporterDoesNotExtract,
    );

/// קשת שנכנסת למראה: ה-release שנושא אותה, שתי הגרסאות שהיא מחברת, ושמות
/// הנכסים שלה — ה-manifest וקובצי ה-patch. הגדלים נקראים מהתוכנית עצמה, כי
/// קשת שהוסרה ממנה אינה מסלול שקיים במראה.
typedef MirroredEdge = ({
  LibraryRelease release,
  int from,
  int to,
  List<String> assetNames,
});
