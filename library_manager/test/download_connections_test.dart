import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/download_connections.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  // הנלווים חולקים את משבצות הייצוא, ולכן גם את חלוקת החיבורים שלו.
  test('החלוקה זהה לזו של הייצוא בכל גודל של תור', () {
    for (final slots in [1, 2, 3, 4, 8, 16]) {
      final scheduler = DownloadScheduler(maxConcurrent: slots);
      final exporter = LibraryMirrorExporter(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        scheduler: scheduler,
      );
      addTearDown(exporter.dispose);

      expect(
        connectionsPerFile(scheduler),
        exporter.connectionsPerFile,
        reason: '$slots משבצות',
      );
    }
  });

  test('הנלווים והחיפוש החכם מורידים בחלוקה הזו', () {
    final scheduler = DownloadScheduler(maxConcurrent: 4);
    final companions = CompanionAssetsMirror(scheduler: scheduler);
    addTearDown(companions.dispose);
    final semantic = SemanticSearchAssets(scheduler: scheduler);
    addTearDown(semantic.dispose);
    final downloader = semantic.newDownloader();
    addTearDown(downloader.dispose);

    expect(connectionsPerFile(scheduler), 2);
    expect(companions.maxConnectionsPerFile, 2);
    expect(downloader.maxConnections, 2);
  });
}
