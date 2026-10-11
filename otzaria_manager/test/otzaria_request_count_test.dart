import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _releasesPath = '/repos/Otzaria/otzaria/releases';

class _FakeGithub {
  final requests = <Uri>[];

  int get releaseListCalls => requests
      .where((u) => u.host == 'api.github.com' && u.path == _releasesPath)
      .length;

  int get changelogCalls =>
      requests.where((u) => u.host == 'raw.githubusercontent.com').length;

  int get installerDownloads =>
      requests.where((u) => u.host == 'dl.example').length;

  int get apiCalls => requests.where((u) => u.host == 'api.github.com').length;

  static Uint8List _installer(String tag) =>
      Uint8List.fromList(utf8.encode('installer:$tag'));

  static Map<String, dynamic> _release(String tag, {required bool pre}) {
    final name = 'otzaria-$tag-windows.exe';
    return {
      'tag_name': tag,
      'name': 'Otzaria $tag',
      'prerelease': pre,
      'draft': false,
      'published_at': '2026-01-01T00:00:00Z',
      'assets': [
        {
          'name': name,
          'browser_download_url': 'https://dl.example/$tag/$name',
          'size': _installer(tag).length,
          'state': 'uploaded',
        },
      ],
    };
  }

  late final MockClient client = MockClient((request) async {
    requests.add(request.url);
    final url = request.url;
    if (url.host == 'api.github.com' && url.path == _releasesPath) {
      return http.Response(
        jsonEncode([
          _release('0.9.97', pre: true),
          _release('0.9.96', pre: false),
        ]),
        200,
      );
    }
    if (url.host == 'dl.example') {
      return http.Response.bytes(_installer(url.pathSegments.first), 200);
    }
    return http.Response('', 404);
  });
}

class _NotRunning extends RunningOtzariaLocator {
  const _NotRunning();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

class _EmptyRegistry extends WindowsInstallRegistry {
  const _EmptyRegistry();

  @override
  List<String> installDirs({
    bool Function(String displayName)? matchesDisplayName,
  }) =>
      const [];
}

void main() {
  late Directory temp;
  late _FakeGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-request-count-');
    github = _FakeGithub();
  });

  tearDown(() async => temp.delete(recursive: true));

  Future<void> online(Future<void> Function(OtzariaManager manager) body) =>
      http.runWithClient(() async {
        final manager = OtzariaManager(
          dataDir: p.join(temp.path, 'OtzariaData'),
          platform: OtzariaTargetPlatform.windows,
          environment: const {},
          runningLocator: const _NotRunning(),
          installRegistry: const _EmptyRegistry(),
        );
        try {
          await body(manager);
        } finally {
          manager.dispose();
        }
      }, () => github.client);

  test('the offline check never touches the network', () async {
    await online((manager) async {
      await manager.checkForUpdate();
      await manager.downloadToMirror();
      final before = github.requests.length;

      final check = await manager.checkForUpdate();

      expect(check.latestRelease, isNotNull);
      expect(github.requests.length, before);
    });
  });

  test('the light check is one release-list call', () async {
    await online((manager) async {
      final channels = await manager.peekOnlineChannels();

      expect(channels.stable!.tagName, '0.9.96');
      expect(channels.prerelease!.tagName, '0.9.97');
      expect(github.releaseListCalls, 1);
      expect(github.apiCalls, 1);
      expect(github.changelogCalls, lessThanOrEqualTo(2));
      expect(github.installerDownloads, 0);
    });
  });

  test('check + download stays within one list call per step', () async {
    await online((manager) async {
      await manager.peekOnlineChannels();
      await manager.downloadToMirror();

      expect(github.releaseListCalls, lessThanOrEqualTo(2));
      expect(github.apiCalls, github.releaseListCalls);
      expect(github.changelogCalls, lessThanOrEqualTo(4));
      expect(github.installerDownloads, 2);
    });
  });

  test('a second download brings no installer bytes again', () async {
    await online((manager) async {
      await manager.downloadToMirror();
      await manager.downloadToMirror();

      expect(github.installerDownloads, 2);
      expect(github.releaseListCalls, lessThanOrEqualTo(2));
    });
  });
}
