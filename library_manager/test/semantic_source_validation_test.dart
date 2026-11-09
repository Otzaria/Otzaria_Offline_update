import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/testing.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticVectorsInstallInput;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

void main() {
  late Directory temp;
  late String mirror;
  late String machine;
  late String db;
  late String vectors;
  late Map<String, File> sources;
  late SemanticSearchAssets assets;
  late FakeVectorsEngine engine;
  var requests = 0;
  var openedEngines = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-source-validation-');
    mirror = p.join(temp.path, 'mirror');
    machine = p.join(temp.path, 'machine');
    db = p.join(machine, 'books', 'seforim.db');
    vectors = p.join(machine, 'vectors');
    final tag = libraryTagOf(30);
    final modelDir = p.join(mirror, tag, SemanticSearchAssets.modelFolder);
    await installModels(modelDir);
    final manifest = FakeVectorsGithub.manifestOf(
      kind: 'base',
      from: 0,
      to: 30,
      file: 'segment.oxv.zst',
      segment: [1, 2, 3],
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    sources = {
      'model': File(p.join(modelDir, fakeModels.first.name)),
      'manifest': File(p.join(mirror, tag, 'vectors', legacyManifestName(30))),
      'vectors': File(p.join(mirror, tag, 'vectors', 'segment.oxv.zst')),
    };
    await sources['manifest']!.parent.create(recursive: true);
    await sources['manifest']!.writeAsBytes(manifestBytes);
    await sources['vectors']!.writeAsBytes([1, 2, 3]);
    await File(
      p.join(mirror, SemanticSearchAssets.manifestFileName),
    ).writeAsString(
      jsonEncode({
        'libraryTag': tag,
        'libraryVersion': 30,
        'manifestName': legacyManifestName(30),
        'manifestSize': manifestBytes.length,
        'manifestSha256': Sha256Stream.ofBytes(manifestBytes),
      }),
    );
    await installModels(
      p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
    );
    await File(db).writeAsString('live library');
    await writeInstalledSet(vectors, version: 29, windows: false);
    requests = 0;
    openedEngines = 0;
    engine = FakeVectorsEngine(version: 29);
    assets = SemanticSearchAssets(
      models: fakeModels,
      freeBytesFor: (_) => null,
      engineFactory: (_) async {
        openedEngines++;
        return engine;
      },
      httpClient: MockClient((request) async {
        requests++;
        fail('offline install sent a request to ${request.url}');
      }),
    );
  });

  tearDown(() async {
    assets.dispose();
    await temp.delete(recursive: true);
  });

  Future<Map<String, List<int>>> snapshot() async => {
    await for (final file in Directory(machine).list(recursive: true))
      if (file is File)
        p.relative(file.path, from: machine): await file.readAsBytes(),
  };

  Future<void> install() => assets.install(
    mirrorDir: mirror,
    dbPath: db,
    libraryVersion: 30,
    generation: SemanticModelGeneration.round2,
  );

  Future<void> rejectsWithoutChanges(
    Matcher error, {
    Future<void> Function()? action,
  }) async {
    final before = await snapshot();
    await expectLater((action ?? install)(), throwsA(error));
    expect(await snapshot(), before);
    expect(openedEngines, 0);
    expect(engine.installs, isEmpty);
    expect(requests, 0);
  }

  for (final kind in ['model', 'manifest', 'vectors']) {
    test('a missing $kind source names the local file', () async {
      final source = sources[kind]!;
      await source.delete();
      await rejectsWithoutChanges(
        isA<FormatException>().having(
          (error) => error.message,
          'local failure',
          AppL10n.strings.libraryDomain.localSourceNotFound(source.path),
        ),
      );
    });

    test('a truncated $kind source preserves the size mismatch', () async {
      final source = sources[kind]!;
      final bytes = await source.readAsBytes();
      await source.writeAsBytes(bytes.sublist(1));
      await rejectsWithoutChanges(
        isA<FormatException>().having(
          (error) => error.message,
          'local failure',
          AppL10n.strings.libraryDomain.localFileSizeMismatch(
            bytes.length,
            bytes.length - 1,
            source.path,
          ),
        ),
      );
    });

    test('a same-size damaged $kind source preserves the hash failure and '
        'leaves the drive asking for a new download', () async {
      final source = sources[kind]!;
      final bytes = await source.readAsBytes();
      bytes[0] ^= 1;
      await source.writeAsBytes(bytes);
      await rejectsWithoutChanges(
        isA<FormatException>().having(
          (error) => error.message,
          'local failure',
          AppL10n.strings.libraryDomain.localFileHashMismatch(source.path),
        ),
      );
      expect(await source.exists(), isFalse);
      // No longer offered here; the online re-fetch is in the delta test.
      expect(
        await assets.pending(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          generation: SemanticModelGeneration.round2,
        ),
        isFalse,
      );
    });

    test('a damaged $kind source on a read-only drive still reports the '
        'hash failure', () async {
      final source = sources[kind]!;
      final bytes = await source.readAsBytes();
      bytes[0] ^= 1;
      await source.writeAsBytes(bytes);
      await rejectsWithoutChanges(
        isA<FormatException>().having(
          (error) => error.message,
          'local failure',
          AppL10n.strings.libraryDomain.localFileHashMismatch(source.path),
        ),
        action: () => IOOverrides.runZoned(
          install,
          createFile: (path) {
            final real = Zone.root.run(() => File(path));
            return path == source.path ? _UndeletableFile(real) : real;
          },
        ),
      );
      expect(await source.exists(), isTrue);
    });

    for (final operation in ['length', 'read']) {
      test('$kind source $operation failure preserves the I/O error', () async {
        final source = sources[kind]!;
        final failure = FileSystemException(
          'source read failed',
          source.path,
          const OSError('test I/O failure', 1234),
        );
        await rejectsWithoutChanges(
          same(failure),
          action: () => IOOverrides.runZoned(
            install,
            createFile: (path) {
              final real = Zone.root.run(() => File(path));
              return path == source.path
                  ? _UnreadableFile(real, failure, operation)
                  : real;
            },
          ),
        );
      });
    }
  }

  test('a damaged source drive keeps its storage classification', () async {
    final source = sources['vectors']!;
    final failure = FileSystemException(
      'source read failed',
      source.path,
      OSError('damaged media', Platform.isWindows ? 1392 : 5),
    );
    await rejectsWithoutChanges(
      isA<StorageCorruptException>().having(
        (error) => error.cause,
        'original failure',
        same(failure),
      ),
      action: () => IOOverrides.runZoned(
        install,
        createFile: (path) {
          final real = Zone.root.run(() => File(path));
          return path == source.path
              ? _UnreadableFile(real, failure, 'read')
              : real;
        },
      ),
    );
  });

  test('a damaged copy on this computer leaves the drive file alone', () async {
    final source = sources['model']!;
    final target = p.join(
      p.dirname(db),
      SemanticSearchAssets.modelFolder,
      fakeModels.first.name,
    );
    await File(target).delete();
    await expectLater(
      IOOverrides.runZoned(
        install,
        createFile: (path) {
          final real = Zone.root.run(() => File(path));
          return path == '$target.tmp' ? _GarbledCopyFile(real) : real;
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'local failure',
          AppL10n.strings.libraryDomain.localFileHashMismatch('$target.tmp'),
        ),
      ),
    );
    expect(await source.exists(), isTrue);
    expect(engine.installs, isEmpty);
  });

  test('a drive manifest the tool cannot use is named as drive data', () async {
    final source = sources['manifest']!;
    final bytes = utf8.encode(jsonEncode({'kind': 'base'}));
    await source.writeAsBytes(bytes);
    final pointer = File(p.join(mirror, SemanticSearchAssets.manifestFileName));
    final meta = jsonDecode(await pointer.readAsString()) as Map;
    meta['manifestSize'] = bytes.length;
    meta['manifestSha256'] = Sha256Stream.ofBytes(bytes);
    await pointer.writeAsString(jsonEncode(meta));
    await rejectsWithoutChanges(
      isA<FormatException>().having(
        (error) => error.message,
        'local failure',
        AppL10n.strings.libraryDomain.semanticStatusDriveUnreadable,
      ),
    );
    expect(await source.exists(), isTrue);
  });

  test('an engine that applies another version is reported as drive data '
      'rather than a missing website file', () async {
    final wrong = _WrongVersionEngine(version: 29);
    final installer = SemanticSearchAssets(
      models: fakeModels,
      freeBytesFor: (_) => null,
      engineFactory: (_) async => wrong,
      httpClient: MockClient((request) async {
        fail('offline install sent a request to ${request.url}');
      }),
    );
    addTearDown(installer.dispose);
    await expectLater(
      installer.install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        generation: SemanticModelGeneration.round2,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'local failure',
          AppL10n.strings.libraryDomain.semanticStatusDriveUnreadable,
        ),
      ),
    );
    for (final source in sources.values) {
      expect(await source.exists(), isTrue);
    }
  });

  test('a missing mirror is reported as missing data on the drive', () async {
    await File(p.join(mirror, SemanticSearchAssets.manifestFileName)).delete();
    await rejectsWithoutChanges(
      isA<FormatException>().having(
        (error) => error.message,
        'local failure',
        AppL10n.strings.libraryDomain.semanticStatusNeedsDriveDownload,
      ),
    );
  });

  for (final operation in ['exists', 'read']) {
    for (final damaged in [false, true]) {
      test('mirror pointer $operation ${damaged ? 'media' : 'I/O'} failure '
          'preserves the check result and the install error', () async {
        final path = p.join(mirror, SemanticSearchAssets.manifestFileName);
        final failure = FileSystemException(
          'pointer access failed',
          path,
          OSError(
            'test pointer failure',
            damaged
                ? Platform.isWindows
                      ? 1392
                      : 5
                : 1234,
          ),
        );
        Future<T> unreadable<T>(Future<T> Function() action) =>
            IOOverrides.runZoned(
              action,
              createFile: (sourcePath) {
                final real = Zone.root.run(() => File(sourcePath));
                return sourcePath == path
                    ? _UnreadableFile(real, failure, operation)
                    : real;
              },
            );
        final status = await unreadable(
          () => assets.assess(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            support: const SemanticAppSupport(
              generation: SemanticModelGeneration.round2,
              basis: SemanticSupportBasis.declared,
            ),
          ),
        );
        expect(
          status.state,
          operation == 'read'
              ? SmartSearchState.unverified
              : SmartSearchState.readyOnDrive,
        );
        if (operation == 'read') {
          expect(status.reason, SmartSearchReason.driveUnreadable);
        }
        await rejectsWithoutChanges(
          damaged
              ? isA<StorageCorruptException>().having(
                  (error) => error.cause,
                  'original pointer failure',
                  same(failure),
                )
              : same(failure),
          action: () => unreadable(install),
        );
      });
    }
  }

  test('the local check does not hash the vector archive', () async {
    final source = sources['vectors']!;
    var reads = 0;
    final pending = await IOOverrides.runZoned(
      () => assets.pending(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        generation: SemanticModelGeneration.round2,
      ),
      createFile: (path) {
        final real = Zone.root.run(() => File(path));
        return path == source.path
            ? _UnreadableFile(
                real,
                FileSystemException('unexpected vector hash', path),
                'read',
                onRead: () => reads++,
              )
            : real;
      },
    );
    expect(pending, isTrue);
    expect(reads, 0);
    expect(requests, 0);
  });

  test(
    'an unreadable installed model remains repairable from the drive',
    () async {
      final target = p.join(
        p.dirname(db),
        SemanticSearchAssets.modelFolder,
        fakeModels.last.name,
      );
      await IOOverrides.runZoned(
        install,
        createFile: (path) {
          final real = Zone.root.run(() => File(path));
          return path == target
              ? _UnreadableFile(
                  real,
                  FileSystemException('unreadable', path),
                  'read',
                )
              : real;
        },
      );
      expect(engine.installs, hasLength(1));
      expect(
        Sha256Stream.ofBytes(await File(target).readAsBytes()),
        fakeModels.last.sha256,
      );
      expect(requests, 0);
    },
  );
}

class _WrongVersionEngine extends FakeVectorsEngine {
  _WrongVersionEngine({super.version});

  @override
  Future<({int libraryVersion, bool alreadyApplied})> install(
    SemanticVectorsInstallInput input, {
    bool Function()? isCancelled,
  }) async {
    final report = await super.install(input, isCancelled: isCancelled);
    return (libraryVersion: report.libraryVersion + 1, alreadyApplied: false);
  }
}

class _UndeletableFile implements File {
  _UndeletableFile(this._real);

  final File _real;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => _real.exists();

  @override
  Future<int> length() => _real.length();

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _real.openRead(start, end);

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _real.readAsString(encoding: encoding);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _real.open(mode: mode);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => Future.error(
    FileSystemException('read-only drive', path, const OSError('denied', 5)),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not forwarded');
}

/// Reads back one flipped byte, as a copy damaged on its way here would.
class _GarbledCopyFile implements File {
  _GarbledCopyFile(this._real);

  final File _real;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => _real.exists();

  @override
  Future<int> length() => _real.length();

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    var first = true;
    await for (final chunk in _real.openRead(start, end)) {
      if (first && chunk.isNotEmpty) {
        first = false;
        yield [chunk.first ^ 1, ...chunk.skip(1)];
      } else {
        yield chunk;
      }
    }
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _real.open(mode: mode);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => _real.delete();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not forwarded');
}

class _UnreadableFile implements File {
  _UnreadableFile(this._real, this._failure, this._operation, {this.onRead});

  final File _real;
  final FileSystemException _failure;
  final String _operation;
  final void Function()? onRead;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() =>
      _operation == 'exists' ? Future.error(_failure) : _real.exists();

  @override
  Future<int> length() =>
      _operation == 'length' ? Future.error(_failure) : _real.length();

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    onRead?.call();
    return Stream.error(_failure);
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _operation == 'read'
      ? Future.error(_failure)
      : _real.readAsString(encoding: encoding);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not forwarded');
}
