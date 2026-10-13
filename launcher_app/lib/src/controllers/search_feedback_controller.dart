import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
import '../services/offer_decline.dart';
import 'dispose_guard.dart';

class SearchFeedbackController extends ChangeNotifier
    with DisposeGuard, SilentAfterDispose {
  static const Duration _probeCacheTtl = Duration(seconds: 2);

  SearchFeedbackController({
    required this.transport,
    required this.resolveSource,
    Future<bool> Function()? grantConsent,
  }) : _grantConsent = grantConsent;

  factory SearchFeedbackController.forDrive({
    required String dataDir,
    required String stateDir,
    String? stateFilesDir,
    required Future<String?> Function() launchPath,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
  }) {
    final transport = SearchFeedbackTransport(
      SearchFeedbackTransport.dirIn(dataDir),
    );
    bool? cachedRunning;
    var cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
    Future<bool> isRunning({bool fresh = false}) async {
      if (!fresh &&
          cachedRunning != null &&
          DateTime.now().difference(cachedAt) < _probeCacheTtl) {
        return cachedRunning!;
      }
      final running = (await runningLocator.probe()).isRunning;
      cachedRunning = running;
      cachedAt = DateTime.now();
      return running;
    }

    Future<({LibraryDbLocator locator, String root})?> locate({
      bool fresh = false,
    }) async {
      if (await isRunning(fresh: fresh)) return null;
      final launch = await launchPath();
      if (launch == null) return null;
      final locator = LibraryDbLocator.forLaunch(
        stateDir: stateFilesDir ?? stateDir,
        launchPath: launch,
        dataDir: dataDir,
      );
      final root = await locator.otzariaSettingsRoot(launch);
      return root == null ? null : (locator: locator, root: root);
    }

    return SearchFeedbackController(
      transport: transport,
      resolveSource: () async {
        final location = await locate(fresh: true);
        if (location == null) return null;
        final settings = await location.locator.settingsReader.read(
          location.root,
        );
        if (settings?.searchFeedbackGranted != true) return null;
        return p.join(location.root, 'search_feedback');
      },
      grantConsent: () async {
        final location = await locate(fresh: true);
        if (location == null) return false;
        if (!await transport.resumeAfterConsent(
          p.join(location.root, 'search_feedback'),
        )) {
          return false;
        }
        if (await isRunning(fresh: true)) return false;
        return const OtzariaSettingsWriter().grantSearchFeedbackConsent(
          dataRootPath: location.root,
        );
      },
    );
  }

  final SearchFeedbackTransport transport;
  final Future<String?> Function() resolveSource;
  final Future<bool> Function()? _grantConsent;
  final OfferDecline _decline = OfferDecline();
  bool isCollecting = false;
  bool isUploading = false;
  int outboxCount = 0;

  Future<bool> grantConsent() async {
    if (isDisposed || isCollecting || isUploading) return false;
    try {
      return await _grantConsent?.call() ?? false;
    } catch (error) {
      AppLogger.maybeInstance?.error('כתיבת הסכמת החיפוש נכשלה', error);
      return false;
    }
  }

  Future<void> refreshOutbox() async {
    try {
      outboxCount = await transport.count();
    } catch (error) {
      AppLogger.maybeInstance?.error('קריאת תיבת משוב החיפוש נכשלה', error);
      outboxCount = 0;
    }
    notifyListeners();
  }

  Future<int> pendingToOffer() async {
    if (isDisposed || isUploading || isCollecting) return 0;
    try {
      final source = await resolveSource();
      if (source == null) return 0;
      final count = await transport.pendingForCollection(source);
      return _decline.filter(count);
    } catch (error) {
      AppLogger.maybeInstance?.error('קריאת משוב החיפוש באוצריא נכשלה', error);
      return 0;
    }
  }

  void markDeclined(int count) => _decline.mark(count);

  Future<int> collect() async {
    if (isCollecting || isUploading || isDisposed) return 0;
    isCollecting = true;
    notifyListeners();
    try {
      final source = await resolveSource();
      if (source == null) return 0;
      return await transport.collect(
        source,
        mayCollect: () async => await resolveSource() == source,
      );
    } finally {
      isCollecting = false;
      await refreshOutbox();
    }
  }

  Future<SearchFeedbackUploadResult?> upload() async {
    if (isCollecting || isUploading || isDisposed) return null;
    isUploading = true;
    notifyListeners();
    try {
      return await transport.upload();
    } finally {
      isUploading = false;
      await refreshOutbox();
    }
  }

  void stop() => transport.stop();

  @override
  void dispose() {
    transport.close();
    super.dispose();
  }
}
