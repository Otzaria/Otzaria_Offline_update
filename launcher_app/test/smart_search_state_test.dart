// מצבי החיפוש החכם בממשק: רק `allClear` מאפשר "הכול מעודכן"; כל מצב אחר
// נאמר במפורש, בבית, באריח, בדף הספרייה ובסוף ההחלה.

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/shell_module_ports.dart';
import 'package:launcher_app/src/flows/update_here_flow.dart';
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart'
    show SemanticDownloadPreference;
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/home_guidance_session.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';
import 'test_support.dart';

/// מחזיר בדיקה מקומית שנקבעת מבחוץ, ומדמה התקנה שמשנה אותה.
class _StatusManager extends LibraryManager {
  _StatusManager(String directory, this.status, {this.consent = false})
      : super(dataDir: directory, environment: const {});

  SmartSearchStatus? status;
  bool consent;
  Object? warning;
  SmartSearchStatus? afterApply;
  bool semanticPeek = false;
  int peeks = 0;
  Object? checkError;
  bool failCheckAfterApply = false;
  Future<void> Function()? onPeek;
  SemanticEngineIncompatibleException? onlineIncompatibility;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    if (checkError case final error?) throw error;
    return LibraryUpdateCheckResult(
      dbPath: p.join(dataDir, 'books', 'seforim.db'),
      semanticPending: status?.installable ?? false,
      semanticConsentGranted: consent,
      semanticStatus: status,
    );
  }

  @override
  Future<ExternalUpdateNoticeData?> pendingReindexRequest(
          {String? dbPath}) async =>
      null;

  @override
  Future<int> peekLatestOnlineVersion() async => 0;

  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async => const {};

  @override
  Future<bool> peekPendingSemanticSearch() async {
    peeks++;
    await onPeek?.call();
    return semanticPeek;
  }

  @override
  SemanticEngineIncompatibleException? get peekedSemanticIncompatibility =>
      onlineIncompatibility;

  @override
  Future<bool> isReadableMirrorCurrent() async => false;

  @override
  Future<int?> peekedDownloadBytesBound() async => null;

  @override
  Future<Set<int>> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
    void Function(String reason)? onLibraryLocationFailure,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    if (afterApply case final next?) status = next;
    if (failCheckAfterApply) checkError = StateError('db is locked');
    if (warning case final error?) {
      onCompanionWarning?.call(
        AppL10n.strings.libraryDomain.companionSemanticName,
        error,
      );
    }
    return {};
  }
}

SmartSearchStatus _status(
  SmartSearchState state, {
  SmartSearchReason reason = SmartSearchReason.none,
  Set<SmartSearchPart> missing = const {},
  Set<SmartSearchPart> present = const {},
  String proofKey = 'k1',
}) =>
    SmartSearchStatus(
      state: state,
      reason: reason,
      missing: missing,
      present: present,
      proofKey: proofKey,
    );

const _open = [
  SmartSearchFact.readyOnDrive,
  SmartSearchFact.notMatching,
  SmartSearchFact.needsDriveDownload,
  SmartSearchFact.unsupported,
  SmartSearchFact.unverified,
  SmartSearchFact.partial,
];

GuidanceFacts _facts(
  SmartSearchFact fact, {
  bool? online = true,
  bool consentRequired = false,
  LibraryStatusFact library = LibraryStatusFact.upToDate,
}) =>
    GuidanceFacts(
      smartSearch: fact,
      online: online,
      semanticConsentRequired: consentRequired,
      libraryStatus: library,
      appProof: OnlineProof.proven,
      libraryProof: OnlineProof.proven,
      pluginsProof: OnlineProof.proven,
    );

void main() {
  group('הכוונת הבית', () {
    test('נקי: "הכול מעודכן" כבעבר', () {
      final g = deriveHomeGuidance(_facts(SmartSearchFact.clear));
      expect(g.primary, GuidancePrimary.upToDate);
      expect(g.smartSearch, SmartSearchFact.clear);
    });

    for (final fact in _open) {
      for (final online in [true, false]) {
        test('$fact online=$online אינו "מעודכן"', () {
          final g = deriveHomeGuidance(_facts(fact, online: online));
          expect(g.primary, GuidancePrimary.smartSearch);
          expect(g.smartSearch, fact);
          expect(g.secondary,
              online ? GuidanceSecondary.none : GuidanceSecondary.offlineHint);
          expect(g.hereItems, isEmpty);
        });
      }

      test('$fact: האריח אינו "מעודכנת"', () {
        final f = _facts(fact);
        expect(deriveTileStatus(GuidanceItem.library, f),
            TileStatus.smartSearchOpen);
        expect(deriveTileStatus(GuidanceItem.app, f), TileStatus.upToDate);
      });

      test('$fact: עדכון ספרייה קודם, והחיפוש החכם אינו מוצג כגיבור', () {
        final g = deriveHomeGuidance(
            _facts(fact, library: LibraryStatusFact.updateAvailable));
        expect(g.primary, GuidancePrimary.updateHere);
        expect(g.smartSearch, SmartSearchFact.clear);
      });
    }

    test('חומר בכונן שמחכה להסכמה נשאר פעולת "עדכון כאן"', () {
      final g = deriveHomeGuidance(
          _facts(SmartSearchFact.readyOnDrive, consentRequired: true));
      expect(g.primary, GuidancePrimary.updateHere);
      expect(g.hereItems, [GuidanceItem.library]);
    });

    test('כשל חלקי בבדיקה ברשת עדיין גובר', () {
      final g = deriveHomeGuidance(const GuidanceFacts(
        smartSearch: SmartSearchFact.unverified,
        online: true,
        appProof: OnlineProof.proven,
        libraryProof: OnlineProof.failed,
        pluginsProof: OnlineProof.proven,
      ));
      expect(g.primary, GuidancePrimary.checkFailed);
    });

    test('אוצריא כאן חדשה מהכונן: החיפוש החכם הפתוח נאמר, לא נבלע', () {
      GuidanceFacts newer(SmartSearchFact fact) => GuidanceFacts(
            otzariaStatus: AppStatusFact.installedIsNewer,
            smartSearch: fact,
            online: true,
            appProof: OnlineProof.proven,
            libraryProof: OnlineProof.proven,
            pluginsProof: OnlineProof.proven,
          );
      final open = deriveHomeGuidance(newer(SmartSearchFact.unsupported));
      expect(open.primary, GuidancePrimary.newerHereThanDrive);
      expect(open.smartSearch, SmartSearchFact.unsupported);
      final clear = deriveHomeGuidance(newer(SmartSearchFact.clear));
      expect(clear.smartSearch, SmartSearchFact.clear);
    });

    test('ספרייה בשגיאה: הדף שלה מסביר, לא החיפוש החכם', () {
      final g = deriveHomeGuidance(_facts(SmartSearchFact.unsupported,
          library: LibraryStatusFact.error));
      expect(g.primary, GuidancePrimary.attention);
      expect(g.smartSearch, SmartSearchFact.clear);
    });
  });

  group('קונטרולר הספרייה', () {
    late Directory temporary;
    late LibraryModuleController controller;
    late _StatusManager manager;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('smart-search-state-');
      AppLogger.resetForTest();
      await AppLogger.init(temporary.path);
    });

    tearDown(() async {
      controller.dispose();
      await AppLogger.maybeInstance?.flush();
      AppLogger.resetForTest();
      AppL10n.use(AppLanguage.hebrew);
      await deleteTempDir(temporary);
    });

    Future<void> check(
      SmartSearchStatus? status, {
      bool consent = false,
      SemanticDownloadPreference preference = SemanticDownloadPreference.ask,
      String? mirroredAppVersion,
    }) async {
      manager = _StatusManager(temporary.path, status, consent: consent);
      controller = LibraryModuleController(
        dataDir: temporary.path,
        manager: manager,
        mirroredOtzariaUpdate: () async => mirroredAppVersion,
      )..semanticPreference = preference;
      await controller.checkForUpdate();
    }

    for (final state in [
      SmartSearchState.installedVerified,
      SmartSearchState.notInUse,
    ]) {
      test('$state: הכול מעודכן מותר', () async {
        await check(_status(state));
        expect(controller.status, LibraryModuleStatus.upToDate);
        expect(controller.semanticAllClear, isTrue);
        expect(controller.semanticOpen, isFalse);
        expect(controller.semanticNote, isNull);
        expect(smartSearchFactOf(controller), SmartSearchFact.clear);
      });
    }

    final cases = <(String, SmartSearchStatus?, SmartSearchFact)>[
      (
        'ready',
        _status(SmartSearchState.readyOnDrive),
        SmartSearchFact.readyOnDrive
      ),
      (
        'not matching',
        _status(SmartSearchState.driveNotMatching,
            reason: SmartSearchReason.driveOtherGeneration),
        SmartSearchFact.notMatching
      ),
      (
        'needs drive download',
        _status(SmartSearchState.needsDriveDownload,
            reason: SmartSearchReason.driveEmpty),
        SmartSearchFact.needsDriveDownload
      ),
      (
        'app cannot read',
        _status(SmartSearchState.unsupported,
            reason: SmartSearchReason.appCannotRead),
        SmartSearchFact.unsupported
      ),
      (
        'app unproven',
        _status(SmartSearchState.unsupported,
            reason: SmartSearchReason.appUnproven),
        SmartSearchFact.unsupported
      ),
      (
        'check failed',
        _status(SmartSearchState.unverified,
            reason: SmartSearchReason.checkFailed),
        SmartSearchFact.unverified
      ),
      (
        'unreadable drive file',
        _status(SmartSearchState.unverified,
            reason: SmartSearchReason.driveUnreadable),
        SmartSearchFact.unverified
      ),
      ('check did not run', null, SmartSearchFact.unverified),
      (
        'partial',
        _status(SmartSearchState.partial,
            reason: SmartSearchReason.partsMissing,
            missing: {SmartSearchPart.vectors},
            present: {SmartSearchPart.model}),
        SmartSearchFact.partial
      ),
    ];

    for (final (name, status, fact) in cases) {
      for (final language in AppLanguage.values) {
        test('$name ($language): לא "מעודכן", עם הסבר', () async {
          AppL10n.use(language);
          await check(status);
          expect(controller.status, LibraryModuleStatus.upToDate,
              reason: 'המסד עצמו מעודכן');
          expect(controller.semanticAllClear, isFalse);
          expect(controller.semanticOpen, isTrue);
          expect(controller.semanticNote, isNotEmpty);
          expect(smartSearchFactOf(controller), fact);
          expect(
              deriveHomeGuidance(_facts(smartSearchFactOf(controller))).primary,
              GuidancePrimary.smartSearch);
        });
      }
    }

    test('unreadable drive file: the note names it, in both languages',
        () async {
      for (final language in AppLanguage.values) {
        AppL10n.use(language);
        await check(_status(SmartSearchState.unverified,
            reason: SmartSearchReason.driveUnreadable));
        expect(controller.semanticNote,
            AppL10n.strings.libraryDomain.semanticStatusDriveUnreadable);
        expect(controller.semanticNote,
            isNot(AppL10n.strings.libraryDomain.semanticStatusCheckFailed));
      }
    });

    group('סירוב להסכמה', () {
      test('חומר מוכן בכונן אחרי סירוב: הבית שקט, והדף שומר את ההערה',
          () async {
        await check(_status(SmartSearchState.readyOnDrive));
        expect(controller.semanticConsentRequired, isTrue);
        expect(smartSearchFactOf(controller), SmartSearchFact.readyOnDrive);
        expect(
            deriveHomeGuidance(_facts(smartSearchFactOf(controller))).primary,
            GuidancePrimary.smartSearch);

        final declined = smartSearchFactOf(controller, consentDeclined: true);
        expect(declined, SmartSearchFact.clear);
        expect(deriveHomeGuidance(_facts(declined)).primary,
            GuidancePrimary.upToDate);
        expect(controller.semanticOpen, isTrue);
        expect(controller.semanticNote,
            AppL10n.strings.libraryDomain.semanticStatusReadyOnDrive);
      });

      for (final (name, status, fact) in cases.skip(1)) {
        test('סירוב אינו משקיט מצב שההסכמה אינה פותרת: $name', () async {
          await check(status);
          expect(smartSearchFactOf(controller, consentDeclined: true), fact);
        });
      }
    });

    test('המצב הישן: QA491 נדרש והמראה Round2 בלבד', () async {
      await check(_status(SmartSearchState.driveNotMatching,
          reason: SmartSearchReason.driveOtherGeneration));
      expect(controller.semanticPending, isFalse,
          reason: 'אין מה להתקין מהכונן');
      expect(controller.semanticAllClear, isFalse);
      expect(controller.semanticNote,
          AppL10n.strings.libraryDomain.semanticStatusDriveNotMatching);
      expect(deriveHomeGuidance(_facts(smartSearchFactOf(controller))).primary,
          isNot(GuidancePrimary.upToDate));
    });

    for (final language in AppLanguage.values) {
      for (final target in ['0.9.98.3+809', '0.9.99']) {
        test('עדכון אוצריא מהכונן קודם לדרישת הורדה ($language, $target)',
            () async {
          AppL10n.use(language);
          await check(
            const SmartSearchStatus(
              state: SmartSearchState.driveNotMatching,
              reason: SmartSearchReason.driveOtherGeneration,
              required: (
                generation: SemanticModelGeneration.round2,
                family: SemanticVectorsFamily.legacy,
              ),
              driveGenerations: {SemanticModelGeneration.qa491},
            ),
            preference: SemanticDownloadPreference.always,
            mirroredAppVersion: target,
          );
          await controller.checkOnline();
          controller.downloadStatus = MirrorDownloadStatus.done;

          expect(controller.awaitsOtzariaUpdate, isTrue);
          expect(controller.semanticAllClear, isFalse);
          expect(controller.semanticState, SmartSearchState.driveNotMatching);
          expect(controller.semanticPending, isFalse);
          expect(
              controller.semanticNote,
              AppL10n.strings.libraryDomain
                  .libraryNeedsOtzariaUpdateFromDrive(target));
          expect(controller.libraryDownloadPending, isFalse);
          expect(controller.hasOnlineUpdate, isFalse);
          expect(controller.downloadNotes, isEmpty);
          expect(controller.shouldOfferSemanticDownload, isFalse);

          controller.semanticPreference = SemanticDownloadPreference.ask;
          expect(controller.onlineSemanticOffer, isFalse);

          manager.semanticPeek = true;
          await controller.checkOnline();
          expect(controller.onlineSemanticOffer, isTrue,
              reason: 'צורך אמיתי של צי המחשבים עדיין מצדיק הורדה');
        });
      }
    }

    test('אותו דור בכונן אינו מסתיר חומר חסר לחיפוש החכם', () async {
      await check(
        const SmartSearchStatus(
          state: SmartSearchState.driveNotMatching,
          reason: SmartSearchReason.driveOtherGeneration,
          required: (
            generation: SemanticModelGeneration.round2,
            family: SemanticVectorsFamily.legacy,
          ),
          driveGenerations: {SemanticModelGeneration.qa491},
        ),
        mirroredAppVersion: '0.9.98.2',
      );
      await controller.checkOnline();
      expect(controller.awaitsOtzariaUpdate, isFalse);
      expect(controller.libraryDownloadPending, isTrue);
      expect(controller.onlineSemanticOffer, isTrue);
      expect(controller.semanticNote,
          AppL10n.strings.libraryDomain.semanticStatusDriveNotMatching);
    });

    for (final ready in [false, true]) {
      test('אחרי התקנת אוצריא נבדק מחדש מה יש בכונן (ready=$ready)', () async {
        String? appUpdate = '0.9.98.3';
        manager = _StatusManager(
          temporary.path,
          const SmartSearchStatus(
            state: SmartSearchState.driveNotMatching,
            reason: SmartSearchReason.driveOtherGeneration,
            required: (
              generation: SemanticModelGeneration.round2,
              family: SemanticVectorsFamily.legacy,
            ),
          ),
          consent: true,
        );
        controller = LibraryModuleController(
          dataDir: temporary.path,
          manager: manager,
          mirroredOtzariaUpdate: () async => appUpdate,
        );
        await controller.checkForUpdate();
        expect(controller.awaitsOtzariaUpdate, isTrue);

        appUpdate = null;
        manager.status = SmartSearchStatus(
          state: ready
              ? SmartSearchState.readyOnDrive
              : SmartSearchState.driveNotMatching,
          reason: ready
              ? SmartSearchReason.partsMissing
              : SmartSearchReason.driveOtherGeneration,
          required: (
            generation: SemanticModelGeneration.qa491,
            family: SemanticVectorsFamily.legacy,
          ),
          proofKey: 'after-app-update',
        );
        await controller.checkForUpdate(fresh: true);
        expect(controller.awaitsOtzariaUpdate, isFalse);
        expect(controller.semanticAllClear, isFalse);
        expect(controller.semanticPending, ready);
        expect(controller.libraryDownloadPending, !ready);
        expect(
          controller.semanticNote,
          ready
              ? AppL10n.strings.libraryDomain.semanticStatusReadyOnDrive
              : AppL10n.strings.libraryDomain.semanticStatusDriveNotMatching,
        );
      });
    }

    test('שדרוג אוצריא עם ספרייה 36: הוכחה ישנה אינה נשארת', () async {
      await check(_status(SmartSearchState.installedVerified, proofKey: 'old'));
      expect(controller.semanticAllClear, isTrue);
      manager.status = _status(SmartSearchState.needsDriveDownload,
          reason: SmartSearchReason.driveEmpty, proofKey: 'new');
      await controller.checkForUpdate(fresh: true);
      expect(controller.status, LibraryModuleStatus.upToDate);
      expect(controller.semanticAllClear, isFalse);
      expect(controller.semanticNote,
          AppL10n.strings.libraryDomain.semanticStatusNeedsDriveDownload);
    });

    test('שדרוג דור החיפוש החכם מקדים את הספרייה גם בלי שינוי סכמה', () async {
      await check(
        const SmartSearchStatus(
          state: SmartSearchState.readyOnDrive,
          required: (
            generation: SemanticModelGeneration.round2,
            family: SemanticVectorsFamily.windows,
          ),
        ),
        consent: true,
        mirroredAppVersion: '0.9.98.3+809',
      );
      expect(controller.awaitsOtzariaUpdate, isTrue);
    });

    test('דור שכבר הותקן נבדק שוב אחרי שדרוג אוצריא', () async {
      await check(
        const SmartSearchStatus(
          state: SmartSearchState.installedVerified,
          required: (
            generation: SemanticModelGeneration.round2,
            family: SemanticVectorsFamily.windows,
          ),
        ),
        mirroredAppVersion: '0.9.98.3+809',
      );
      expect(controller.awaitsOtzariaUpdate, isTrue);
    });

    test('שדרוג בתוך אותו דור אינו משנה את סדר ההחלה', () async {
      await check(
        const SmartSearchStatus(
          state: SmartSearchState.readyOnDrive,
          required: (
            generation: SemanticModelGeneration.round2,
            family: SemanticVectorsFamily.windows,
          ),
        ),
        mirroredAppVersion: '0.9.98.2+807',
      );
      expect(controller.awaitsOtzariaUpdate, isFalse);
    });

    test('דור מותקן שלא זוהה נבדק אחרי התקנת אוצריא עם דור מוכר', () async {
      await check(
        _status(SmartSearchState.unverified,
            reason: SmartSearchReason.appUnproven),
        mirroredAppVersion: '0.9.98.3+809',
      );
      expect(controller.awaitsOtzariaUpdate, isTrue);
    });

    test('במחשב לא מחובר: "להוריד לכונן במחשב מחובר", בלי נפילה לרשת',
        () async {
      await check(_status(SmartSearchState.needsDriveDownload,
          reason: SmartSearchReason.driveEmpty));
      expect(controller.onlineCheckedAt, isNull);
      expect(controller.semanticNote,
          AppL10n.strings.libraryDomain.semanticStatusNeedsDriveDownload);
      expect(manager.peeks, 0);
    });

    group('בדיקה ברשת', () {
      test('חיפוש חכם שהכונן לא יכול לשרת אינו "הוכח מעודכן"', () async {
        await check(_status(SmartSearchState.needsDriveDownload,
            reason: SmartSearchReason.driveEmpty));
        await controller.checkOnline();
        expect(controller.onlineSemanticPending, isFalse);
        expect(controller.semanticChecked, isTrue);
        expect(controller.shouldOfferSemanticDownload, isTrue);
        expect(controller.libraryDownloadPending, isTrue);
        expect(controller.onlineSemanticOffer, isTrue);
      });

      test('נקי ומוכח: אין הצעה', () async {
        await check(_status(SmartSearchState.installedVerified));
        await controller.checkOnline();
        expect(controller.shouldOfferSemanticDownload, isFalse);
        expect(controller.libraryDownloadPending, isFalse);
        expect(controller.onlineSemanticOffer, isFalse);
      });

      test('"תמיד": ההורדה נחשבת עדכון', () async {
        await check(
            _status(SmartSearchState.driveNotMatching,
                reason: SmartSearchReason.driveOtherGeneration),
            preference: SemanticDownloadPreference.always);
        await controller.checkOnline();
        expect(controller.hasOnlineUpdate, isTrue);
        expect(controller.onlinePendingCompanionNames, isNotEmpty);
      });

      test('"אף פעם": ההורדה אינה מוצעת, ההסבר נשאר', () async {
        await check(
            _status(SmartSearchState.driveNotMatching,
                reason: SmartSearchReason.driveOtherGeneration),
            preference: SemanticDownloadPreference.never);
        await controller.checkOnline();
        expect(controller.libraryDownloadPending, isFalse);
        expect(controller.onlineSemanticOffer, isFalse);
        expect(controller.semanticNote, isNotNull);
      });

      test('החלפת הוכחה (אפליקציה/דור/נתונים) מבטלת תשובה חיובית', () async {
        await check(
            _status(SmartSearchState.installedVerified, proofKey: 'app-1'));
        await controller.checkOnline();
        expect(controller.semanticChecked, isTrue);
        expect(controller.shouldOfferSemanticDownload, isFalse);

        manager.status =
            _status(SmartSearchState.installedVerified, proofKey: 'app-2');
        await controller.checkForUpdate(fresh: true);
        expect(controller.semanticChecked, isFalse);
        expect(controller.shouldOfferSemanticDownload, isTrue);
      });

      test('אותה הוכחה: התשובה נשמרת', () async {
        await check(_status(SmartSearchState.installedVerified));
        await controller.checkOnline();
        await controller.checkForUpdate(fresh: true);
        expect(controller.semanticChecked, isTrue);
        expect(controller.shouldOfferSemanticDownload, isFalse);
      });

      test('החלפת דור מבטלת גם כשל בדיקה של הדור הקודם', () async {
        await check(_status(SmartSearchState.installedVerified, proofKey: 'a'),
            preference: SemanticDownloadPreference.always);
        manager.onPeek = () async => throw StateError('old generation offline');
        await controller.checkOnline();
        expect(controller.onlineSemanticCheckError, isNotNull);

        manager.status =
            _status(SmartSearchState.installedVerified, proofKey: 'b');
        await controller.checkForUpdate(fresh: true);
        expect(controller.semanticChecked, isFalse);
        expect(controller.onlineSemanticCheckError, isNull);
        expect(controller.onlineAnswerError, isNull);
      });

      test('החלפת דור מבטלת גם אי תאימות של הדור הקודם', () async {
        await check(_status(SmartSearchState.installedVerified, proofKey: 'a'));
        manager.onlineIncompatibility =
            const SemanticEngineIncompatibleException(
          lineTextVersion: 1,
          keyVersion: 1,
          reason: SemanticIncompatibilityReason.updateTool,
        );
        await controller.checkOnline();
        expect(controller.semanticIncompatibility, isNotNull);

        manager.status =
            _status(SmartSearchState.installedVerified, proofKey: 'b');
        await controller.checkForUpdate(fresh: true);
        expect(controller.semanticChecked, isFalse);
        expect(controller.semanticIncompatibility, isNull);
      });

      test('בדיקה ברשת שהחלה לפני הבדיקה המקומית: התשובה לא מוכחת', () async {
        manager = _StatusManager(
          temporary.path,
          _status(SmartSearchState.installedVerified),
        )..semanticPeek = true;
        controller = LibraryModuleController(
          dataDir: temporary.path,
          manager: manager,
        );
        manager.onPeek = () => controller.checkForUpdate();
        await controller.checkOnline();
        expect(controller.semanticStatus, isNotNull);
        expect(controller.semanticChecked, isFalse);
        expect(controller.onlineSemanticPending, isFalse);
        expect(controller.shouldOfferSemanticDownload, isTrue);
      });

      test('שחזור תשובות שמורות בהוכחה אחרת מבטל אותן', () async {
        await check(_status(SmartSearchState.installedVerified, proofKey: 'a'));
        await controller.checkOnline();
        final saved = controller.onlineAnswers;
        manager.status =
            _status(SmartSearchState.installedVerified, proofKey: 'b');
        await controller.checkForUpdate(fresh: true);
        controller.restoreOnlineAnswers(saved);
        expect(controller.semanticChecked, isFalse);
      });
    });

    group('סוף ההחלה', () {
      test('אימות שנכשל אחרי כתיבה: חלקי, עם מה שחסר, לא "הושלם"', () async {
        await check(_status(SmartSearchState.readyOnDrive), consent: true);
        final partial = _status(SmartSearchState.partial,
            reason: SmartSearchReason.verificationFailed,
            missing: {SmartSearchPart.vectors},
            present: {SmartSearchPart.model});
        manager
          ..afterApply = partial
          ..warning = SmartSearchVerificationException(partial);
        await controller.update();
        final t = AppL10n.strings.libraryDomain;
        expect(controller.status, LibraryModuleStatus.error);
        expect(controller.errorMessage,
            contains(t.semanticStatusPartial(t.semanticPartVectors)));
        expect(controller.errorMessage,
            contains(t.semanticStatusVerificationFailed));
        expect(
            controller.errorMessage,
            isNot(
                contains(t.companionsInstallFailed(t.companionSemanticName))));
        expect(controller.applyNote, controller.errorMessage);
        expect(controller.lastApplyCompleted, isTrue);
      });

      test('הצלחה מלאה: בלי הערה', () async {
        await check(_status(SmartSearchState.readyOnDrive), consent: true);
        manager.afterApply = _status(SmartSearchState.installedVerified);
        await controller.update();
        expect(controller.status, LibraryModuleStatus.upToDate);
        expect(controller.applyNote, isNull);
        expect(controller.errorMessage, isNull);
        expect(controller.semanticAllClear, isTrue);
      });

      test('המסד עודכן והחיפוש החכם לא נבדק: נאמר, בלי שגיאה אדומה', () async {
        await check(_status(SmartSearchState.readyOnDrive), consent: true);
        manager.afterApply = _status(SmartSearchState.unverified,
            reason: SmartSearchReason.checkFailed);
        await controller.update();
        expect(controller.status, LibraryModuleStatus.upToDate);
        expect(controller.errorMessage, isNull);
        expect(controller.applyNote,
            AppL10n.strings.libraryDomain.semanticStatusCheckFailed);
        expect(controller.lastApplyCompleted, isTrue);
      });

      test('חיפוש חכם שאינו נתמך אחרי ההחלה: הערה, לא "הושלם"', () async {
        await check(_status(SmartSearchState.readyOnDrive), consent: true);
        manager.afterApply = _status(SmartSearchState.unsupported,
            reason: SmartSearchReason.appCannotRead);
        await controller.update();
        expect(controller.applyNote,
            AppL10n.strings.libraryDomain.semanticStatusAppCannotRead);
      });

      test('הבדיקה שאחרי ההחלה נכשלה: "לא אומת", לא הצלחה שקטה', () async {
        await check(_status(SmartSearchState.readyOnDrive), consent: true);
        manager.failCheckAfterApply = true;
        final port = LibraryModulePort(controller);
        expect(await port.apply(), LibraryApplyResult.appliedWithNote);
        expect(controller.lastApplyCompleted, isTrue);
        expect(controller.applyNote,
            AppL10n.strings.libraryDomain.semanticStatusCheckFailed);
        expect(port.applyNote, controller.applyNote);
      });

      test('ממתין להסכמה אינו הערה — זה תהליך ההסכמה', () async {
        await check(_status(SmartSearchState.readyOnDrive));
        manager.afterApply = _status(SmartSearchState.readyOnDrive);
        await controller.update();
        expect(controller.applyNote, isNull);
      });
    });
  });

  group('עדכון כאן אחרי אוצריא חדשה', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('smart-search-flow-');
      AppLogger.resetForTest();
      await AppLogger.init(temporary.path);
    });

    tearDown(() async {
      await AppLogger.maybeInstance?.flush();
      AppLogger.resetForTest();
      await deleteTempDir(temporary);
    });

    Future<(UpdateHereTask, LibraryModuleController)> run(
      SmartSearchStatus status,
    ) async {
      final manager = _StatusManager(temporary.path, status);
      final library = LibraryModuleController(
        dataDir: temporary.path,
        manager: manager,
      );
      addTearDown(library.dispose);
      await library.checkForUpdate();
      library.awaitsOtzariaUpdate = true;
      final host = _FlowHost();
      addTearDown(host.tasks.dispose);
      await UpdateHereFlow(
        app: _FlowApp(),
        library: LibraryModulePort(library),
        plugins: _FlowPlugins(),
        host: host,
      ).run(const [GuidanceItem.app, GuidanceItem.library]);
      return (host.tasks.updateTask!, library);
    }

    test('הספרייה מעודכנת והחיפוש החכם פתוח: דילוג עם הסיבה, לא וי שקט',
        () async {
      final (task, library) = await run(
        _status(SmartSearchState.driveNotMatching,
            reason: SmartSearchReason.driveOtherGeneration),
      );
      expect(library.status, LibraryModuleStatus.upToDate);
      expect(task.phase, UpdateHereTaskPhase.done);
      expect(task.outcomes[GuidanceItem.library], StageOutcome.skipped);
      expect(task.libraryNote,
          AppL10n.strings.libraryDomain.semanticStatusDriveNotMatching);
    });

    test('החיפוש החכם סגור: דילוג בלי הערה, כבעבר', () async {
      final (task, _) = await run(_status(SmartSearchState.installedVerified));
      expect(task.outcomes[GuidanceItem.library], StageOutcome.skipped);
      expect(task.libraryNote, isNull);
    });
  });

  group('מסכים', () {
    final he = stringsOf();

    for (final language in AppLanguage.values) {
      final s = stringsOf(language);
      final titles = {
        SmartSearchFact.readyOnDrive: s.guide.smartSearchReadyTitle,
        SmartSearchFact.notMatching: s.guide.smartSearchNotMatchingTitle,
        SmartSearchFact.needsDriveDownload: s.guide.smartSearchNotMatchingTitle,
        SmartSearchFact.unsupported: s.guide.smartSearchUnsupportedTitle,
        SmartSearchFact.unverified: s.guide.smartSearchUnverifiedTitle,
        SmartSearchFact.partial: s.guide.smartSearchPartialTitle,
      };
      for (final fact in _open) {
        testWidgets('גיבור הבית $fact ($language)', (tester) async {
          const note = 'הסבר-לבדיקה';
          await pumpScreen(
            tester,
            HomePage(
              model: HomeViewModel(
                guidance: deriveHomeGuidance(_facts(fact, online: false)),
                installedVersion: '0.10.3',
                smartSearchNote: note,
                libraryTile: TileStatus.smartSearchOpen,
              ),
            ),
            language: language,
          );
          final hero = find.byKey(ShellKeys.hero);
          expect(find.descendant(of: hero, matching: find.text(titles[fact]!)),
              findsOneWidget);
          expect(find.descendant(of: hero, matching: find.text(note)),
              findsOneWidget);
          expect(find.text(s.guide.upToDateTitle), findsNothing);
          expect(find.text(s.guide.driveInstalledTitle), findsNothing);
          expect(find.text(s.guide.chipSmartSearchOpen), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('אוצריא כאן חדשה מהכונן: הגיבור אומר מה פתוח בחיפוש החכם',
        (tester) async {
      const note = 'הסבר-לבדיקה';
      await pumpScreen(
        tester,
        HomePage(
          model: HomeViewModel(
            guidance: deriveHomeGuidance(const GuidanceFacts(
              otzariaStatus: AppStatusFact.installedIsNewer,
              smartSearch: SmartSearchFact.unsupported,
              online: false,
            )),
            installedVersion: '0.10.4',
            driveAppVersion: '0.10.3',
            smartSearchNote: note,
            libraryTile: TileStatus.smartSearchOpen,
          ),
        ),
      );
      final hero = find.byKey(ShellKeys.hero);
      expect(
          find.descendant(of: hero, matching: find.text(note)), findsOneWidget);
      expect(
          find.descendant(
              of: hero,
              matching: find.byIcon(FluentIcons.checkmark_24_regular)),
          findsNothing);
    });

    testWidgets('דף הספרייה: שבב והסבר כשהחיפוש החכם פתוח', (tester) async {
      final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('smart-search-screen-'),
      ))!;
      addTearDown(() {
        try {
          temporary.deleteSync(recursive: true);
        } on FileSystemException {
          // best effort
        }
      });
      final manager = _StatusManager(
        temporary.path,
        _status(SmartSearchState.driveNotMatching,
            reason: SmartSearchReason.driveOtherGeneration),
      );
      final library = LibraryModuleController(
        dataDir: temporary.path,
        manager: manager,
      );
      addTearDown(library.dispose);
      await tester.runAsync(() async {
        AppLogger.resetForTest();
        await AppLogger.init(temporary.path);
        await library.checkForUpdate();
      });
      addTearDown(AppLogger.resetForTest);
      LibraryScreen screen() => LibraryScreen(
            library: library,
            otzariaIsRunning: false,
            isDownloading: false,
            onProcessStateChanged: () async => false,
            onCloseOtzaria: () async => true,
            onRequestReindex: () async {},
            onGoToSettings: () {},
            onGrantSemanticConsent: () async {},
          );
      await pumpScreen(tester, screen());
      expect(library.status, LibraryModuleStatus.upToDate);
      expect(find.text(he.guide.chipSmartSearchOpen), findsOneWidget);
      expect(find.text(he.pages.chipUpToDate), findsNothing);
      expect(find.byKey(ShellKeys.librarySemanticNote), findsOneWidget);
      expect(find.text(he.libraryDomain.semanticStatusDriveNotMatching),
          findsOneWidget);

      manager.status = _status(SmartSearchState.installedVerified);
      await tester.runAsync(() => library.checkForUpdate(fresh: true));
      await tester.pumpWidget(wrap(screen()));
      expect(find.text(he.pages.chipUpToDate), findsOneWidget);
      expect(find.byKey(ShellKeys.librarySemanticNote), findsNothing);
    });
  });
}

class _FlowApp implements UpdateHereApp {
  @override
  bool isInstalled = true;
  @override
  bool hasUpdateAvailable = true;
  @override
  bool elevatedAsOtherUser = false;
  @override
  String? adminAccount;
  @override
  String? versionToInstall = '0.10.4';
  @override
  String? errorMessage;
  @override
  bool needsElevation = false;
  @override
  bool canReinstall = false;

  @override
  Future<AppInstallOutcome> installWithWizard() async {
    hasUpdateAvailable = false;
    return AppInstallOutcome.installed;
  }

  @override
  void stopWaiting() {}
}

class _FlowPlugins implements UpdateHerePlugins {
  @override
  List<String> get deliverableUpdates => const [];

  @override
  Future<void> deliver(void Function(List<PluginDelivery> rows) onRow) async {}
}

class _FlowHost implements UpdateHereHost {
  @override
  final tasks = ShellTasks();

  @override
  bool get isActive => true;

  @override
  Future<bool> isOtzariaRunning() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected host call: ${invocation.memberName}');
}
