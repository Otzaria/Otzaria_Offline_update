import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/faq_controller.dart';
import 'package:launcher_app/src/services/faq_drive_identity.dart';
import 'package:launcher_app/src/settings/faq_customization.dart';
import 'package:otzaria_downloads/src/atomic_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory machine;
  late Directory driveA;
  late Directory driveB;

  setUp(() {
    root = Directory.systemTemp.createTempSync('readonly-faq');
    machine = Directory(p.join(root.path, 'machine'))..createSync();
    driveA = Directory(p.join(root.path, 'driveA'))..createSync();
    driveB = Directory(p.join(root.path, 'driveB'))..createSync();
  });

  tearDown(() async => root.delete(recursive: true));

  File file(Directory directory) =>
      File(p.join(directory.path, 'faq_customization.json'));

  void writeFaq(Directory directory, String name) =>
      file(directory).writeAsStringSync(
          jsonEncode(FaqCustomization(contactName: name).toJson()));

  FaqController controllerFor(Directory drive) {
    final controller = FaqController(
      dataDir: machine.path,
      readOnlyDriveDir: drive.path,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<FaqController> open(Directory drive) async {
    final controller = controllerFor(drive);
    await controller.load();
    return controller;
  }

  Future<String> contact(Directory drive) async =>
      (await open(drive)).value.contactName;

  Future<void> edit(FaqController controller, String name) =>
      controller.update(controller.value.copyWith(contactName: name));

  File cacheFile() =>
      Directory(p.join(machine.path, 'logs', 'faq')).listSync().single as File;

  test('#289: changed drive FAQ reaches a machine with an older copy',
      () async {
    writeFaq(driveA, 'old');
    final modified = DateTime(2026, 11, 1);
    file(driveA).setLastModifiedSync(modified);
    expect(await contact(driveA), 'old');

    writeFaq(driveA, 'new');
    file(driveA).setLastModifiedSync(modified);

    expect(await contact(driveA), 'new');
  });

  test('unchanged drive keeps local edits even when timestamps drift',
      () async {
    writeFaq(driveA, 'drive');
    file(driveA).setLastModifiedSync(DateTime(2026, 10, 1, 12));
    await edit(await open(driveA), 'local');
    final cache = cacheFile();
    cache.setLastModifiedSync(DateTime(2026, 9, 1));
    final cacheModified = cache.lastModifiedSync();
    file(driveA).setLastModifiedSync(DateTime(2026, 10, 1, 13));

    expect(await contact(driveA), 'local');
    expect(cache.lastModifiedSync(), cacheModified);

    writeFaq(driveA, 'new');
    expect(await contact(driveA), 'new');
  });

  test('a second locked drive cannot borrow or discard local edits for A',
      () async {
    writeFaq(driveA, 'Drive A');
    await edit(await open(driveA), 'Local A');

    expect(await contact(driveB), isEmpty);
    writeFaq(driveB, 'Drive B');
    expect(await contact(driveB), 'Drive B');
    await edit(await open(driveB), 'Local B');

    expect(await contact(driveA), 'Local A');
    expect(await contact(driveB), 'Local B');
    expect(file(driveA).readAsStringSync(), contains('Drive A'));
    expect(file(driveB).readAsStringSync(), contains('Drive B'));
  });

  test('a valid drive version replaces the legacy unscoped copy for display',
      () async {
    writeFaq(machine, 'old unscoped');
    writeFaq(driveA, 'new drive');

    expect(await contact(driveA), 'new drive');
    expect(await contact(driveB), isEmpty);
    expect(file(machine).readAsStringSync(), contains('old unscoped'));

    await edit(await open(driveA), 'local');
    expect(await contact(driveA), 'local');
  });

  test('a legacy copy identical to its drive allows subsequent local changes',
      () async {
    writeFaq(machine, 'same');
    writeFaq(driveA, 'same');

    final controller = await open(driveA);
    expect(controller.value.contactName, 'same');
    await edit(controller, 'local');
    expect(await contact(driveA), 'local');
  });

  test('a failed refresh still saves a later edit with the latest fingerprint',
      () async {
    writeFaq(driveA, 'old');
    expect(await contact(driveA), 'old');
    writeFaq(driveA, 'new');
    final original = atomicTempPathFor;
    addTearDown(() => atomicTempPathFor = original);
    atomicTempPathFor = (_) => p.join(root.path, 'absent-parent', 'failed.tmp');

    final controller = await open(driveA);
    expect(controller.value.contactName, 'new');
    expect(cacheFile().readAsStringSync(), contains('old'));

    atomicTempPathFor = original;
    await edit(controller, 'local');
    expect(await contact(driveA), 'local');
  });

  test('a malformed or unsupported drive FAQ leaves the local cache intact',
      () async {
    writeFaq(driveA, 'Drive A');
    await edit(await open(driveA), 'Local A');

    for (final malformed in [
      '{broken',
      '[]',
      '{"unexpected": true}',
      '{"schemaVersion": 42, "contact": {"name": "unreadable"}}',
      '{"contact":{"name":42,"phone":[]}}',
      '{"hidden":[],"contact":{"name":42}}',
      '{"hidden":[],"contact":null}',
      '{"hidden":[42],"contact":{"name":"unreadable"}}',
      '{"extras":[{"question":42,"answer":"bad"}]}',
    ]) {
      file(driveA).writeAsStringSync(malformed);
      expect(await contact(driveA), 'Local A', reason: malformed);
    }

    file(driveA).writeAsStringSync('{"contact":{"name":"sparse legacy"}}');
    expect(await contact(driveA), 'sparse legacy');
  });

  test('a malformed cache is rebuilt from the current valid drive FAQ',
      () async {
    writeFaq(driveA, 'Drive A');
    expect(await contact(driveA), 'Drive A');
    cacheFile().writeAsStringSync('{broken');

    expect(await contact(driveA), 'Drive A');
    expect(jsonDecode(cacheFile().readAsStringSync()), isA<Map>());

    cacheFile().writeAsBytesSync([0xff]);
    expect(await contact(driveA), 'Drive A');
  });

  test('a temporary cache read failure cannot erase a local edit', () async {
    writeFaq(driveA, 'Drive A');
    await edit(await open(driveA), 'Local A');

    await IOOverrides.runWithIOOverrides(
      () => contact(driveA),
      _UnreadableCacheIOOverrides(cacheFile().path),
    );

    expect(await contact(driveA), 'Local A');
  });

  test('an edit before initial load completes survives that load and flush',
      () async {
    writeFaq(driveA, 'Drive A');
    writeFaq(driveB, 'Drive B');
    final controller = controllerFor(driveA);

    final loading = controller.load();
    controller.updateDeferred(
      const FaqCustomization(contactName: 'edited during load'),
      const Duration(minutes: 1),
    );
    await loading;
    expect(controller.value.contactName, 'edited during load');
    await controller.flush();

    expect(await contact(driveA), 'edited during load');
    expect(await contact(driveB), 'Drive B');
  });

  test('an unavailable location can use the absolute path fallback', () async {
    if (Platform.isWindows) {
      const unc = r'\\unresolvable-faq-server\nonexistent-faq-share\faq';
      expect(faqDriveIdentity(unc), unc);
    } else {
      final missing = p.join(root.path, 'unavailable-volume', '..', 'other');
      expect(faqDriveIdentity(missing), p.normalize(p.absolute(missing)));
    }

    final missing = Directory(p.join(root.path, 'not-present'));
    expect(await contact(missing), isEmpty);
    await edit(await open(missing), 'local');
    expect(await contact(missing), 'local');
    expect(await contact(driveA), isEmpty);
  });
}

final class _UnreadableCacheIOOverrides extends IOOverrides {
  _UnreadableCacheIOOverrides(this.cachePath);

  final String cachePath;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return file.path == cachePath ? _UnreadableCache(file) : file;
  }
}

class _UnreadableCache implements File {
  _UnreadableCache(this.delegate);

  final File delegate;

  @override
  String get path => delegate.path;

  @override
  Future<Uint8List> readAsBytes() async => throw FileSystemException(
      'temporarily locked', path, const OSError('', 5));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
