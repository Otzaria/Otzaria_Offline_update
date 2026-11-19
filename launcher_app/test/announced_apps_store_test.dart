import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/announced_apps_store.dart';
import 'package:launcher_app/src/services/known_plugins_store.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:otzaria_downloads/atomic_write_testing.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('announced-apps-');
  });
  tearDown(() => deleteTempDir(directory));

  test('parallel announcements preserve each host and sort merged ids',
      () async {
    final a = AnnouncedAppsStore(directory.path, hostName: 'a');
    final b = AnnouncedAppsStore(directory.path, hostName: 'b');
    await Future.wait([
      a.record(['z', 'a']),
      b.record(['b']),
      a.record(['x', 'a']),
    ]);
    expect(await a.load(), {'a', 'x', 'z'});
    expect(await b.load(), {'b'});
    final file = File(p.join(directory.path, 'custom_apps_announced.json'));
    expect(jsonDecode(await file.readAsString()), {
      'announced': {
        'a': ['a', 'x', 'z'],
        'b': ['b'],
      },
    });
  });

  test('malformed host values are filtered without losing other hosts',
      () async {
    final file = File(p.join(directory.path, 'custom_apps_announced.json'));
    await file.writeAsString(
      '{"announced":{"a":["first",3],"b":["other"],"bad":false}}',
    );
    final store = AnnouncedAppsStore(directory.path, hostName: 'a');
    expect(await store.load(), {'first'});
    await store.record(['next']);
    expect(jsonDecode(await file.readAsString()), {
      'announced': {
        'a': ['first', 'next'],
        'b': ['other'],
      },
    });
  });

  test('empty announcements do not establish or write state', () async {
    final store = AnnouncedAppsStore(directory.path, hostName: 'a');
    expect(await store.load(), isEmpty);
    await store.record(const []);
    expect(directory.listSync(), isEmpty);
  });

  test('unchanged sets in all three stores avoid replacement writes', () async {
    final announced = AnnouncedAppsStore(directory.path, hostName: 'a');
    final known = KnownPluginsStore(directory.path, hostName: 'a');
    final notices = NoticesSeenStore(directory.path, hostName: 'a');
    await announced.record(['first']);
    await known.recordSeen(const []);
    await known.recordNotified(['first']);
    await notices.markSeen('first');

    final original = atomicTempPathFor;
    addTearDown(() => atomicTempPathFor = original);
    var writes = 0;
    atomicTempPathFor = (path) {
      writes++;
      return original(path);
    };
    await announced.record(['first']);
    await known.recordSeen(const []);
    await known.recordNotified(['first']);
    await notices.markSeen('first');
    expect(writes, 0);
  });
}
