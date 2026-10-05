import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';

/// איסוף נעשה רק על סמך הסכמה עדכנית באוצריא וכשהיא סגורה.
class SearchFeedbackController extends ChangeNotifier {
  SearchFeedbackController({
    required this.transport,
    required this.resolveSource,
    Future<bool> Function()? grantConsent,
  }) : _grantConsent = grantConsent;

  factory SearchFeedbackController.forDrive({
    required String dataDir,
    required String stateDir,
    required Future<String?> Function() launchPath,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
  }) {
    final transport =
        SearchFeedbackTransport(SearchFeedbackTransport.dirIn(dataDir));
    Future<({LibraryDbLocator locator, String root})?> locate() async {
      if ((await runningLocator.probe()).isRunning) return null;
      final launch = await launchPath();
      if (launch == null) return null;
      final locator = LibraryDbLocator(
        stateStore: LibraryStateStore(p.join(stateDir, 'library_state.json')),
        otzariaLaunchPath: () async => launch,
      );
      final root = await locator.otzariaSettingsRoot(launch);
      return root == null ? null : (locator: locator, root: root);
    }

    return SearchFeedbackController(
      transport: transport,
      resolveSource: () async {
        final location = await locate();
        if (location == null) return null;
        final settings =
            await location.locator.settingsReader.read(location.root);
        if (settings?.searchFeedbackGranted != true) return null;
        return p.join(location.root, 'search_feedback');
      },
      grantConsent: () async {
        final location = await locate();
        if (location == null) return false;
        if (!await transport.resumeAfterConsent(
          p.join(location.root, 'search_feedback'),
        )) {
          return false;
        }
        if ((await runningLocator.probe()).isRunning) return false;
        return const OtzariaSettingsWriter().grantSearchFeedbackConsent(
          dataRootPath: location.root,
        );
      },
    );
  }

  final SearchFeedbackTransport transport;
  final Future<String?> Function() resolveSource;
  final Future<bool> Function()? _grantConsent;
  bool _offered = false;
  bool _disposed = false;
  bool isCollecting = false;
  bool isUploading = false;
  int outboxCount = 0;

  /// הקורא מציג קודם את תנאי ההסכמה; מפתח שנחסם אינו ניתן להפעלה.
  Future<bool> grantConsent() async {
    if (_disposed || isCollecting || isUploading) return false;
    try {
      return await _grantConsent?.call() ?? false;
    } catch (error) {
      AppLogger.maybeInstance?.error('כתיבת הסכמת החיפוש נכשלה', error);
      return false;
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
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
    if (_offered || _disposed) return 0;
    _offered = true;
    try {
      final source = await resolveSource();
      return source == null ? 0 : await transport.pending(source);
    } catch (error) {
      AppLogger.maybeInstance?.error('קריאת משוב החיפוש באוצריא נכשלה', error);
      return 0;
    }
  }

  Future<int> collect() async {
    if (isCollecting || isUploading || _disposed) return 0;
    isCollecting = true;
    notifyListeners();
    try {
      final source = await resolveSource();
      if (source == null) return 0;
      return await transport.collect(source,
          mayCollect: () async => await resolveSource() == source);
    } finally {
      isCollecting = false;
      await refreshOutbox();
    }
  }

  Future<SearchFeedbackUploadResult?> upload() async {
    if (isCollecting || isUploading || _disposed) return null;
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
    _disposed = true;
    transport.close();
    super.dispose();
  }
}
