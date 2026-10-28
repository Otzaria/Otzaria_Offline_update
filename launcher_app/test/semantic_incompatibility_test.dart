// חיפוש חכם שהמנוע אינו קורא: ההסבר מגיע למשתמש לפי הסיבה — במסלול המקוון
// ובמראה שעל הכונן — ואינו נראה כ"אין רשת", כ"מעודכן" או כהצעה להורדה.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';
import 'test_support.dart';

SemanticEngineIncompatibleException _incompatible(
  SemanticIncompatibilityReason reason,
) =>
    SemanticEngineIncompatibleException(
      lineTextVersion: 1,
      keyVersion: 1,
      reason: reason,
    );

class _Manager extends LibraryManager {
  _Manager(String dir, {this.online, this.mirror})
      : super(dataDir: dir, environment: const {});

  final SemanticEngineIncompatibleException? online;
  final SemanticEngineIncompatibleException? mirror;

  @override
  Future<int?> peekLatestOnlineVersion() async => 34;
  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async => {};
  @override
  Future<bool> peekPendingSemanticSearch() async => false;
  @override
  SemanticEngineIncompatibleException? get peekedSemanticIncompatibility =>
      online;
  @override
  int? get peekedSemanticBytes => 0;
  @override
  Future<bool> isReadableMirrorCurrent() async => true;
  @override
  Future<int?> peekedDownloadBytesBound() async => 0;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async =>
      LibraryUpdateCheckResult(
        dbPath: p.join(dataDir, 'books', 'seforim.db'),
        semanticIncompatibility: mirror,
      );

  @override
  Future<ExternalUpdateNoticeData?> pendingReindexRequest(
          {String? dbPath}) async =>
      null;
}

void main() {
  late Directory temporary;
  LibraryModuleController? controller;
  final t = stringsOf().libraryDomain;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('semantic-incompat-');
    AppLogger.resetForTest();
    await AppLogger.init(temporary.path);
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  final texts = {
    SemanticIncompatibilityReason.updateTool: t.semanticIncompatibleUpdateTool,
    SemanticIncompatibilityReason.updateOtzaria:
        t.semanticIncompatibleUpdateOtzaria,
    SemanticIncompatibilityReason.republishAssets:
        t.semanticIncompatibleRepublish,
    SemanticIncompatibilityReason.otzariaUnproven:
        t.semanticIncompatibleOtzariaUnproven,
  };

  for (final reason in SemanticIncompatibilityReason.values) {
    test('בדיקה מקוונת, $reason: הסבר מתורגם, לא "אין רשת" ולא הצעה', () async {
      final c = controller = LibraryModuleController(
        dataDir: temporary.path,
        manager: _Manager(temporary.path, online: _incompatible(reason)),
      )
        ..targetVersion = 34
        ..semanticPreference = SemanticDownloadPreference.always;
      await c.checkOnline();
      expect(c.downloadNotes, contains(texts[reason]));
      expect(c.onlineAnswerError, isNull);
      expect(c.onlineSemanticCheckError, isNull);
      expect(c.onlineSemanticPending, isFalse);
      expect(c.shouldOfferSemanticDownload, isFalse);
      expect(c.hasDownloadFailures, isFalse);
    });

    test('מראה קיימת בלא-מקוון, $reason: ההסבר מגיע מהבדיקה המקומית', () async {
      final c = controller = LibraryModuleController(
        dataDir: temporary.path,
        manager: _Manager(temporary.path, mirror: _incompatible(reason)),
      );
      await c.checkForUpdate();
      expect(c.mirrorSemanticIncompatibility?.reason, reason);
      expect(c.downloadNotes, contains(texts[reason]));
    });
  }

  test('בלי אי-תאימות אין הערה, ובדיקה חדשה מוחקת את הישנה', () async {
    final c = controller = LibraryModuleController(
      dataDir: temporary.path,
      manager: _Manager(temporary.path),
    )
      ..onlineSemanticIncompatibility =
          _incompatible(SemanticIncompatibilityReason.updateTool)
      ..mirrorSemanticIncompatibility =
          _incompatible(SemanticIncompatibilityReason.updateTool)
      ..targetVersion = 34
      ..semanticPreference = SemanticDownloadPreference.always;
    await c.checkOnline();
    await c.checkForUpdate();
    expect(c.semanticIncompatibility, isNull);
    expect(c.downloadNotes, isEmpty);
  });

  testWidgets('מסך הספרייה מציג את ההסבר', (tester) async {
    final c = controller = LibraryModuleController(dataDir: temporary.path)
      ..status = LibraryModuleStatus.upToDate
      ..mirrorSemanticIncompatibility =
          _incompatible(SemanticIncompatibilityReason.updateOtzaria);
    await pumpScreen(
      tester,
      LibraryScreen(
        library: c,
        otzariaIsRunning: false,
        onCloseOtzaria: () async => true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
        onGoToSettings: () {},
      ),
      size: const Size(1000, 1800),
    );
    expect(
      find.textContaining(t.semanticIncompatibleUpdateOtzaria),
      findsOneWidget,
    );
  });
}
