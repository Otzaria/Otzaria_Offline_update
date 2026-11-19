import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  void write(List<Object> lines) =>
      File(p.join(temp.path, PluginInstallResults.fileName)).writeAsStringSync(
        '${lines.map((l) => l is String ? l : jsonEncode(l)).join('\n')}\n',
      );

  Map<String, Object?> entry(String path, String outcome, DateTime at) => {
        'path': path,
        'pluginId': 'x',
        'version': '1.0.0',
        'outcome': outcome,
        'message': null,
        'at': at.toUtc().toIso8601String(),
      };

  test('אין קובץ — אין תוצאות', () async {
    expect(await PluginInstallResults.read(temp.path), isEmpty);
  });

  test('שורות פגומות מדולגות, והתוצאה האחרונה לנתיב אחרי המסירה נבחרת',
      () async {
    final handoff = DateTime.utc(2026, 10, 12, 10);
    final path = p.join(temp.path, 'a.otzplugin');
    write([
      entry(path, 'failed', handoff.subtract(const Duration(minutes: 5))),
      '{not json',
      {'path': path},
      entry(p.join(temp.path, 'other.otzplugin'), 'installed', handoff),
      entry(path, 'cancelled', handoff.add(const Duration(seconds: 3))),
      entry(path, 'installed', handoff.add(const Duration(seconds: 9))),
    ]);

    final reports = await PluginInstallResults.read(temp.path);
    final latest = PluginInstallResults.latestFor(reports, path, handoff);

    expect(reports, hasLength(4));
    expect(latest?.outcome, 'installed');
    expect(latest?.succeeded, isTrue);
  });

  test('תוצאה ממסירה קודמת של אותו נתיב אינה נחשבת', () async {
    final handoff = DateTime.utc(2026, 10, 12, 10);
    final path = p.join(temp.path, 'a.otzplugin');
    write([
      entry(path, 'cancelled', handoff.subtract(const Duration(minutes: 1)))
    ]);

    final reports = await PluginInstallResults.read(temp.path);

    expect(PluginInstallResults.latestFor(reports, path, handoff), isNull);
  });

  group('indexed reader', () {
    final at = DateTime.utc(2026, 10, 12, 10);
    late PluginInstallResultsReader reader;
    late File file;
    late String path;
    late _ResultIo io;

    setUp(() {
      reader = PluginInstallResultsReader();
      file = File(p.join(temp.path, PluginInstallResults.fileName));
      path = p.join(temp.path, 'a.otzplugin');
      io = _ResultIo(file.path);
    });

    Future<PluginInstallResultsSnapshot> read() =>
        IOOverrides.runWithIOOverrides(() => reader.read(temp.path), io);

    Future<void> append(String text) =>
        file.writeAsString(text, mode: FileMode.append);

    test('unchanged polls reuse the index without rereading content', () async {
      write([entry(path, 'installed', at)]);
      await IOOverrides.runWithIOOverrides(() async {
        await PluginInstallResults.read(temp.path);
        await PluginInstallResults.read(temp.path);
      }, io);
      final bytes = await file.length();
      expect(io.bytesRead, bytes * 2);
      io.bytesRead = 0;

      final first = await read();
      expect(first.latestFor(path, at)?.succeeded, isTrue);
      expect(await read(), same(first));
      expect(await read(), same(first));
      expect(io.bytesRead, bytes);
      expect(io.reads, 3);
      expect(io.stats, 4);
    });

    test('an appended result does not mutate the previous snapshot', () async {
      write([entry(path, 'installed', at)]);
      final first = await read();
      final other = p.join(temp.path, 'b.otzplugin');
      await append('${jsonEncode(entry(other, 'cancelled', at))}\n');

      final second = await read();
      expect(second.latestFor(path, at)?.succeeded, isTrue);
      expect(second.latestFor(other, at)?.cancelled, isTrue);
      expect(first.latestFor(other, at), isNull);
    });

    test('large lines keep their full message after an append', () async {
      final message = '${'x' * 70000}עברית🙂';
      write([
        {...entry(path, 'installed', at), 'message': message},
      ]);
      final first = await read();
      expect(first.latestFor(path, at)?.message, message);
      final other = p.join(temp.path, 'b.otzplugin');
      await append('${jsonEncode(entry(other, 'cancelled', at))}\n');
      final second = await read();
      expect(second.latestFor(path, at)?.succeeded, isTrue);
      expect(second.latestFor(other, at)?.cancelled, isTrue);
      expect(second.latestFor(path, at)?.message, message);
    });

    test('an unfinished multibyte line resumes across polls', () async {
      final line = utf8.encode(jsonEncode({
        ...entry(path, 'rejected', at),
        'message': 'עברית 🙂',
      }));
      final split = line.indexOf(0xf0) + 2;
      await file.writeAsBytes(line.sublist(0, split));
      expect((await read()).latestFor(path, at), isNull);
      await file.writeAsBytes(line.sublist(split), mode: FileMode.append);
      expect((await read()).latestFor(path, at)?.message, 'עברית 🙂');
      await append('\n');
      expect((await read()).latestFor(path, at)?.message, 'עברית 🙂');
    });

    test('a provisional final line is withdrawn when an append invalidates it',
        () async {
      write([entry(path, 'cancelled', at)]);
      await append(jsonEncode(entry(path, 'installed', at)));
      expect((await read()).latestFor(path, at)?.succeeded, isTrue);
      await append(' invalid');
      expect((await read()).latestFor(path, at)?.cancelled, isTrue);
      await append('\n${jsonEncode(entry(path, 'updated', at))}\n');
      expect((await read()).latestFor(path, at)?.outcome, 'updated');
    });

    test('path equivalence, skew and same-time ordering match the static API',
        () async {
      final alias = p.join(temp.path, 'nested', '..', 'a.otzplugin');
      write([
        entry(path, 'installed', at.subtract(const Duration(seconds: 2))),
        entry(alias, 'cancelled', at.subtract(const Duration(seconds: 2))),
        entry(path, 'failed', at.subtract(const Duration(seconds: 3))),
      ]);
      final indexed = await read();
      final reference = await PluginInstallResults.read(temp.path);
      expect(
        indexed.latestFor(path, at)?.outcome,
        PluginInstallResults.latestFor(reference, path, at)?.outcome,
      );
      expect(indexed.latestFor(alias, at)?.cancelled, isTrue);
      expect(
          indexed.latestFor(path, at.add(const Duration(seconds: 1))), isNull);
    });

    test('bad JSON and blank lines do not hide later CRLF results', () async {
      await file.writeAsBytes([
        ...utf8.encode('\n{bad}\r\n'),
        ...utf8.encode('${jsonEncode({'path': path})}\r'),
        ...utf8.encode('${jsonEncode(entry(path, 'updated', at))}\r\n'),
      ]);
      expect((await read()).latestFor(path, at)?.outcome, 'updated');
    });

    test('same-size replacement discards the old result', () async {
      write([entry(path, 'installed', at)]);
      await read();
      final size = await file.length();
      final replacement = File('${file.path}.new');
      await replacement
          .writeAsString('${jsonEncode(entry(path, 'cancelled', at))}\n');
      await file.delete();
      await replacement.rename(file.path);
      await file.setLastModified(at);

      expect(await file.length(), size);
      expect((await read()).latestFor(path, at)?.cancelled, isTrue);
    });

    test('a larger replacement discards all previous results', () async {
      final first = p.join(temp.path, 'first.otzplugin');
      final last = p.join(temp.path, 'last.otzplugin');
      write([
        entry(first, 'installed', at),
        entry(path, 'installed', at),
        entry(last, 'installed', at),
      ]);
      await read();
      write([
        entry(first, 'installed', at),
        entry(path, 'cancelled', at),
        entry(last, 'installed', at),
        entry(p.join(temp.path, 'extra.otzplugin'), 'installed', at),
      ]);

      expect((await read()).latestFor(path, at)?.cancelled, isTrue);
    });

    test('truncation and deletion clear cached successes', () async {
      final other = p.join(temp.path, 'b.otzplugin');
      write([entry(path, 'installed', at), entry(other, 'updated', at)]);
      await read();
      write([entry(other, 'cancelled', at)]);
      final truncated = await read();
      expect(truncated.latestFor(path, at), isNull);
      expect(truncated.latestFor(other, at)?.cancelled, isTrue);
      await file.delete();
      expect((await read()).latestFor(other, at), isNull);
      write([entry(path, 'failed', at)]);
      expect((await read()).latestFor(path, at)?.outcome, 'failed');
    });

    test('changing data roots does not reuse reports from another installation',
        () async {
      write([entry(path, 'installed', at)]);
      await read();
      final root = Directory(p.join(temp.path, 'other'));
      await root.create();
      await File(p.join(root.path, PluginInstallResults.fileName))
          .writeAsString('${jsonEncode(entry(path, 'cancelled', at))}\n');
      final other = await reader.read(root.path);
      expect(other.latestFor(path, at)?.cancelled, isTrue);
      expect((await read()).latestFor(path, at)?.succeeded, isTrue);
    });

    test('reads the physical parent of a linked data root', () async {
      final physical = p.join(temp.path, 'physical');
      final child = await Directory(p.join(physical, 'child')).create(
        recursive: true,
      );
      final link = await Link(p.join(temp.path, 'link')).create(child.path);
      final dataRoot = p.join(link.path, '..');
      write([entry(path, 'installed', at)]);
      await File(p.join(physical, PluginInstallResults.fileName))
          .writeAsString('${jsonEncode(entry(path, 'cancelled', at))}\n');

      final reports = await PluginInstallResults.read(dataRoot);
      expect(
          PluginInstallResults.latestFor(reports, path, at)?.cancelled, isTrue);
      expect(
          (await reader.read(dataRoot)).latestFor(path, at)?.cancelled, isTrue);
    }, skip: Platform.isWindows);

    test('an unreadable file returns no cached success and can recover',
        () async {
      write([entry(path, 'installed', at)]);
      await read();
      io.statError = FileSystemException('unreadable', file.path);
      expect((await read()).latestFor(path, at), isNull);
      io.statError = null;
      expect((await read()).latestFor(path, at)?.succeeded, isTrue);
      expect(io.reads, 2);
    });

    test('a read failure clears old successes', () async {
      write([entry(path, 'installed', at)]);
      await read();
      await append('\n');
      io.beforeRead =
          () async => throw FileSystemException('removed', file.path);
      expect((await read()).latestFor(path, at), isNull);
      expect(io.reads, 2);
      io.beforeRead = null;
      expect((await read()).latestFor(path, at)?.succeeded, isTrue);
    });

    test('a single mutation during reading retries within the same poll',
        () async {
      write([entry(path, 'installed', at)]);
      io.beforeRead = () async {
        io.beforeRead = null;
        await append('${jsonEncode(entry(path, 'cancelled', at))}\n');
      };
      expect((await read()).latestFor(path, at)?.cancelled, isTrue);
    });

    test('truncation during reading returns no stale success', () async {
      write([entry(path, 'installed', at)]);
      await read();
      await append('\n');
      io.beforeRead = () async {
        io.beforeRead = null;
        await file.writeAsString('');
      };
      expect((await read()).latestFor(path, at), isNull);
      expect(io.reads, 3);
      expect((await read()).latestFor(path, at), isNull);
    });

    test('concurrent polls share one read', () async {
      write([entry(path, 'installed', at)]);
      final started = Completer<void>();
      final release = Completer<void>();
      io.beforeRead = () async {
        started.complete();
        await release.future;
      };
      final first = read();
      await started.future;
      final second = read();
      expect(second, same(first));
      release.complete();
      expect(await second, same(await first));
      expect(io.reads, 1);
    });

    test('clearing during a read prevents the old result being republished',
        () async {
      write([entry(path, 'installed', at)]);
      final started = Completer<void>();
      final release = Completer<void>();
      io.beforeRead = () async {
        io.beforeRead = null;
        started.complete();
        await release.future;
      };
      final stale = read();
      await started.future;
      reader.clear();
      final fresh = read();
      release.complete();
      expect((await stale).latestFor(path, at), isNull);
      expect((await fresh).latestFor(path, at)?.succeeded, isTrue);
      expect(io.reads, 2);
    });
  });
}

final class _ResultIo extends IOOverrides {
  _ResultIo(this.path);

  final String path;
  var bytesRead = 0;
  var reads = 0;
  var stats = 0;
  FileSystemException? statError;
  Future<void> Function()? beforeRead;

  @override
  File createFile(String path) {
    final real = super.createFile(path);
    return p.equals(path, this.path) ? _ResultFile(real, this) : real;
  }
}

class _ResultFile implements File {
  _ResultFile(this.real, this.io);

  final File real;
  final _ResultIo io;

  @override
  String get path => real.path;

  @override
  Future<FileStat> stat() async {
    io.stats++;
    if (io.statError case final error?) throw error;
    return real.stat();
  }

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async {
    io.reads++;
    await io.beforeRead?.call();
    io.bytesRead += await real.length();
    return real.readAsLines(encoding: encoding);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
