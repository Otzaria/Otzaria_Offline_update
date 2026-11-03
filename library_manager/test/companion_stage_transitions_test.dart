import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// The dictionary alone, served with a strong ETag and Range, through the real
/// download engine: resuming verifies the prefix before the rest arrives.
void main() {
  const name = 'lexical.db';
  final body = Uint8List.fromList(utf8.encode('payload:$name:${'x' * 400}'));
  late Directory temp;
  late String destDir;
  late List<String?> ranges;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('companion-stage-');
    destDir = p.join(temp.path, 'companions');
    ranges = [];
  });

  tearDown(() => temp.delete(recursive: true));

  CompanionAssetsMirror build() {
    final client = MockClient.streaming((request, _) async {
      final url = request.url.toString();
      Stream<List<int>> json(Object value) =>
          Stream.value(utf8.encode(jsonEncode(value)));
      if (url.contains('/repos/Otzaria/SeforimMagicIndexer/')) {
        return http.StreamedResponse(
          json({
            'tag_name': 'dict-v7',
            'assets': [
              {
                'name': name,
                'browser_download_url': 'https://x/$name',
                'size': body.length,
                'id': 7,
                'updated_at': '2026-08-01T00:00:00Z',
                'digest': 'sha256:${sha256.convert(body)}',
              },
            ],
          }),
          200,
        );
      }
      if (url.contains('/repos/Otzaria/')) {
        return http.StreamedResponse(
          json({'tag_name': 'none', 'assets': <Object>[]}),
          200,
        );
      }
      final range = request.headers['Range'];
      ranges.add(range);
      final partial = range != null && request.headers['If-Range'] == '"v1"';
      final from = partial
          ? int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!)
          : 0;
      final chunk = body.sublist(from);
      return http.StreamedResponse(
        Stream.value(chunk),
        partial ? 206 : 200,
        contentLength: chunk.length,
        headers: {
          'etag': '"v1"',
          if (partial)
            'content-range': 'bytes $from-${body.length - 1}/${body.length}',
        },
      );
    });
    return CompanionAssetsMirror(httpClient: client);
  }

  Future<({List<String?> stages, List<String> atBytes})> sync() async {
    final mirror = build();
    addTearDown(mirror.dispose);
    final stages = <String?>[];
    final atBytes = <String>[];
    String? stage;
    var last = 0;
    await mirror.sync(
      destDir: destDir,
      onStage: (value) {
        stage = value;
        stages.add(value);
      },
      onBytesProgress: (done, _) {
        if (done > last) atBytes.add(stage ?? '');
        last = done;
      },
    );
    return (stages: stages, atBytes: atBytes);
  }

  String dest() => p.join(destDir, name);

  test(
    'prefix verified, then the rest arrives: stage is downloading',
    () async {
      await sync();
      await File(dest()).writeAsBytes(body.sublist(0, 6));
      ranges.clear();

      final run = await sync();

      expect(ranges, ['bytes=6-']);
      expect(run.stages.whereType<String>().any(isLocalWorkStage), isTrue);
      expect(run.atBytes, isNotEmpty);
      expect(run.atBytes.where(isLocalWorkStage), isEmpty, reason: '$run');
      expect(File(dest()).readAsBytesSync(), body);
      expect(run.stages.last, isNull);
    },
  );

  test('a corrupt whole file: verified, dropped, then downloaded', () async {
    await sync();
    final corrupt = Uint8List.fromList(body)..[3] ^= 0xff;
    await File(dest()).writeAsBytes(corrupt);
    ranges.clear();

    final run = await sync();

    expect(run.atBytes.where(isLocalWorkStage), isEmpty, reason: '$run');
    expect(File(dest()).readAsBytesSync(), body);
    expect(run.stages.last, isNull);
  });
}
