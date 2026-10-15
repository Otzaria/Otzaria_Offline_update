import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/download_connections.dart';
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
}
