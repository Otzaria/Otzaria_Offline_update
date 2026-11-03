import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/mirror_download_undo.dart';
import 'package:launcher_app/src/services/mirror_junk_sweeper.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

Future<String> _download(String url, String dest) async {
  File(dest).parent.createSync(recursive: true);
  final downloader = PatchDownloader(decompress: (_) async => null);
  try {
    await downloader.downloadToFile(url: url, destPath: dest, expectedSize: 8);
    return 'success';
  } on PatchDownloadException catch (error) {
    final busy = LibraryUpdaterMessages.current
        .destinationBusy('\u0000')
        .split('\u0000')
        .first;
    if (!error.message.contains(busy)) rethrow;
    return 'locked';
  } finally {
    downloader.dispose();
  }
}

void _worker(List<Object> args) async {
  final port = args[0] as SendPort;
  try {
    port.send(await _download(args[1] as String, args[2] as String));
  } catch (error) {
    port.send('error: $error');
  }
}

Future<String> _isolatedDownload(String url, String dest) async {
  final port = ReceivePort();
  try {
    await Isolate.spawn(_worker, [port.sendPort, url, dest]);
    return await port.first as String;
  } finally {
    port.close();
  }
}

void main() {
  for (final cleanup in [
    'sweep',
    'undo-existing',
    'undo-new-root',
    'semantic'
  ]) {
    for (final relative in cleanup == 'semantic'
        ? ['companions/semantic/v29-20260920000000/nested/asset']
        : [
            'library/assets/old/nested/asset',
            'companions/obsolete/nested/asset',
          ]) {
      test('$cleanup preserves a live lock outside the manifest: $relative',
          () async {
        final temp = Directory.systemTemp.createTempSync('mirror-lock');
        await AppLogger.init(temp.path);
        final root = p.join(temp.path, 'mirror', relative.split('/').first);
        final dest = p.join(temp.path, 'mirror', relative);
        final entered = Completer<void>();
        final release = Completer<void>();
        final secondRequest = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        server.listen((request) async {
          requests++;
          if (requests == 2) secondRequest.complete();
          if (!entered.isCompleted) entered.complete();
          await release.future;
          request.response.contentLength = 8;
          request.response.add(List.filled(8, 65));
          await request.response.close();
        });
        final url = 'http://127.0.0.1:${server.port}/asset';
        Future<String>? first;
        try {
          if (cleanup != 'undo-new-root') {
            Directory(root).createSync(recursive: true);
          }
          final undo = await MirrorDownloadUndo.capture([root]);
          first = _download(url, dest);
          await Future.any([
            entered.future,
            first.then((value) => throw StateError('owner finished: $value'))
          ]);
          final lock = File('$dest.lock');
          expect(lock.existsSync(), isTrue);
          if (cleanup == 'sweep') {
            final libraryManifest =
                File(p.join(temp.path, 'mirror', 'library', 'releases.json'));
            libraryManifest.parent.createSync(recursive: true);
            libraryManifest.writeAsStringSync(jsonEncode({
              'formatVersion': 1,
              'releases': [
                {
                  'tag': 'current',
                  'assets': [
                    {
                      'name': 'asset',
                      'downloadUrl': 'assets/current/asset',
                      'size': 8
                    }
                  ],
                }
              ],
            }));
            final companionManifest = File(
                p.join(temp.path, 'mirror', 'companions', 'companions.json'));
            companionManifest.parent.createSync(recursive: true);
            companionManifest.writeAsStringSync(jsonEncode({
              'catalog': {
                'fileName': 'catalog.pb',
                'size': 8,
                'sha256': 'hash'
              },
            }));
            await MirrorJunkSweeper(dataDir: temp.path).sweep();
          } else if (cleanup == 'semantic') {
            final assets = SemanticSearchAssets();
            try {
              await assets.pruneOldGenerations(
                  p.join(root, 'semantic'), 'v30-20261018000000');
            } finally {
              assets.dispose();
            }
          } else {
            await undo.revert();
          }
          final second = _isolatedDownload(url, dest);
          final outcome = await Future.any([
            second,
            secondRequest.future.then((_) => 'second HTTP request')
          ]);
          release.complete();
          expect(await first, 'success');
          expect(await second, 'locked');
          expect(outcome, 'locked');
          expect(lock.existsSync(), isTrue);
          expect(requests, 1);
        } finally {
          if (!release.isCompleted) release.complete();
          if (first != null) await first;
          await server.close(force: true);
          await AppLogger.maybeInstance?.flush();
          AppLogger.resetForTest();
          temp.deleteSync(recursive: true);
        }
      });
    }
  }
}
