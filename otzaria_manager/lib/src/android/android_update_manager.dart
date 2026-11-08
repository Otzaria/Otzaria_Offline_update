import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'adb_client.dart';
import 'android_models.dart';
import 'android_tools.dart';
import 'apk_inspector.dart';

class AndroidUpdateManager {
  AndroidUpdateManager({
    required String dataDir,
    required String stateDir,
    this.readOnly = false,
    http.Client? httpClient,
    AndroidCommandRunner? runner,
    String? operatingSystem,
    String? machineKey,
    ApkInspector inspector = const ApkInspector(),
  })  : mirrorDir = p.join(dataDir, 'mirror', 'android'),
        _http = httpClient ?? http.Client(),
        _runner = runner ?? const AndroidProcessRunner(),
        _inspector = inspector {
    tools = AndroidTools(
      mirrorDir: mirrorDir,
      stateDir: stateDir,
      readOnly: readOnly,
      operatingSystem: operatingSystem,
      machineKey: machineKey,
      runner: _runner,
    );
  }

  final String mirrorDir;
  final bool readOnly;
  final http.Client _http;
  final AndroidCommandRunner _runner;
  final ApkInspector _inspector;
  late final AndroidTools tools;
  AndroidCancellation? _active;
  bool _disposed = false;

  Future<T> _run<T>(
    AndroidCancellation cancellation,
    Future<T> Function() action,
  ) async {
    if (_active != null) {
      throw const AndroidUpdateException(AndroidUpdateFailure.busy);
    }
    if (_disposed) {
      throw const AndroidUpdateException(AndroidUpdateFailure.cancelled);
    }
    cancellation.check();
    _active = cancellation;
    try {
      return await action();
    } finally {
      _active = null;
    }
  }

  Future<AndroidMirroredRelease?> loadMirror() async {
    final file = File(p.join(mirrorDir, 'latest-release.json'));
    if (!await file.exists()) return null;
    final json = await _readJson(file);
    final apk = json['apk'];
    final metadata = json['metadata'];
    final tag = json['tagName'];
    if (json['schemaVersion'] != 1 ||
        json['source'] != 'github-latest' ||
        apk is! Map<String, dynamic> ||
        metadata is! Map<String, dynamic> ||
        tag is! String ||
        tag.isEmpty) {
      _invalid();
    }
    final relative = apk['path'];
    final size = apk['size'];
    final digest = apk['sha256'];
    if (relative is! String ||
        size is! int ||
        size <= 0 ||
        !_isSha256(digest) ||
        relative.contains('\\') ||
        p.posix.isAbsolute(relative) ||
        relative
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        !relative.startsWith('files/')) {
      _invalid();
    }
    final path = p.joinAll([mirrorDir, ...relative.split('/')]);
    final apkFile = File(path);
    if (!await apkFile.exists()) return null;
    final realRoot = await Directory(mirrorDir).resolveSymbolicLinks();
    final realApk = await apkFile.resolveSymbolicLinks();
    if (!p.isWithin(realRoot, realApk) || await apkFile.length() != size) {
      _invalid();
    }
    return AndroidMirroredRelease(
      tagName: tag,
      apkPath: path,
      size: size,
      sha256: (digest as String).toLowerCase(),
      info: AndroidApkInfo.fromJson(metadata),
    );
  }

  Future<AndroidMirroredRelease> downloadLatest(
    AndroidCancellation cancellation, {
    void Function(int received, int total)? onProgress,
  }) =>
      _run(cancellation, () async {
        if (readOnly) {
          throw const AndroidUpdateException(AndroidUpdateFailure.readOnly);
        }
        final json = await githubGetJson(
          _http,
          Uri.parse(
              'https://api.github.com/repos/Otzaria/otzaria/releases/latest'),
          timeout: const Duration(seconds: 20),
          statusError: (_) =>
              const AndroidUpdateException(AndroidUpdateFailure.noRelease),
        );
        cancellation.check();
        if (json is! Map<String, dynamic> ||
            json['draft'] == true ||
            json['prerelease'] == true ||
            json['assets'] is! List ||
            json['tag_name'] is! String) {
          throw const AndroidUpdateException(AndroidUpdateFailure.noRelease);
        }
        final assets =
            (json['assets'] as List).whereType<Map<String, dynamic>>().toList();
        Map<String, dynamic>? find(String name) {
          final matches = assets
              .where(
                (a) =>
                    a['name'] == name &&
                    GithubReleaseAsset.tryParse(a)?.isReady == true,
              )
              .toList();
          if (matches.length > 1) _invalid();
          return matches.isEmpty ? null : matches.single;
        }

        final raw = find('otzaria-android.apk') ?? find('app-release.apk');
        if (raw == null || raw['id'] is! int || (raw['id'] as int) <= 0) {
          throw const AndroidUpdateException(AndroidUpdateFailure.noRelease);
        }
        final asset = GithubReleaseAsset.tryParse(raw)!;
        if (asset.size > 1024 * 1024 * 1024 ||
            (asset.sha256 != null && !_isSha256(asset.sha256))) {
          _invalid();
        }
        final directory = p.join(mirrorDir, 'files', '${raw['id']}');
        final apkPath = p.join(directory, asset.name);
        final digest = await _download(
          asset,
          apkPath,
          cancellation,
          onProgress: onProgress,
        );
        cancellation.check();
        final info = await _inspector.inspect(apkPath);
        final rawSidecar = find('otzaria-android.json');
        if (rawSidecar != null) {
          final sidecar = GithubReleaseAsset.tryParse(rawSidecar)!;
          if (sidecar.size > 64 * 1024) _invalid();
          final metadataPath = p.join(directory, sidecar.name);
          await _download(sidecar, metadataPath, cancellation);
          final metadata = await _readJson(File(metadataPath));
          final describedApk = metadata['apk'];
          if (metadata['schemaVersion'] != 1 ||
              describedApk is! Map<String, dynamic> ||
              describedApk['name'] != asset.name ||
              describedApk['size'] != asset.size ||
              describedApk['sha256'] != digest ||
              !info.matches(AndroidApkInfo.fromJson(metadata))) {
            _invalid();
          }
        }
        cancellation.check();
        await writeStringAtomically(
          p.join(mirrorDir, 'latest-release.json'),
          jsonEncode({
            'schemaVersion': 1,
            'source': 'github-latest',
            'tagName': json['tag_name'],
            'apk': {
              'path':
                  p.relative(apkPath, from: mirrorDir).replaceAll('\\', '/'),
              'size': asset.size,
              'sha256': digest,
            },
            'metadata': info.toJson(),
          }),
        );
        await _prunePrevious(directory);
        return AndroidMirroredRelease(
          tagName: json['tag_name'] as String,
          apkPath: apkPath,
          size: asset.size,
          sha256: digest,
          info: info,
        );
      });

  Future<void> _prunePrevious(String current) async {
    try {
      await for (final entry
          in Directory(p.join(mirrorDir, 'files')).list(followLinks: false)) {
        if (entry is Directory &&
            RegExp(r'^[0-9]+$').hasMatch(p.basename(entry.path)) &&
            !p.equals(entry.path, current)) {
          try {
            await entry.delete(recursive: true);
          } on FileSystemException {
            // A locked old APK can be removed after a later download.
          }
        }
      }
    } on FileSystemException {
      // A completed download remains usable if cleanup is interrupted.
    }
  }

  Future<String> _download(
    GithubReleaseAsset asset,
    String destination,
    AndroidCancellation cancellation, {
    void Function(int, int)? onProgress,
  }) async {
    final url = Uri.tryParse(asset.downloadUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        !url.path.startsWith('/Otzaria/otzaria/releases/download/')) {
      _invalid();
    }
    final current = File(destination);
    if (asset.sha256 != null &&
        await current.exists() &&
        await current.length() == asset.size &&
        await androidFileSha256(current, cancellation) == asset.sha256) {
      onProgress?.call(asset.size, asset.size);
      return asset.sha256!;
    }
    final result = await downloadFile(
      client: _http,
      url: asset.downloadUrl,
      destinationPath: destination,
      expectedSize: asset.size,
      calculateSha256: true,
      keepPartialOnCancel: true,
      checkCancelled: cancellation.check,
      onProgress: onProgress,
      statusError: (_) =>
          const AndroidUpdateException(AndroidUpdateFailure.noRelease),
      sizeError: (_, __) =>
          const AndroidUpdateException(AndroidUpdateFailure.digestMismatch),
    );
    final digest =
        result.sha256 ?? await androidFileSha256(current, cancellation);
    if (asset.sha256 != null && asset.sha256 != digest) {
      await current.delete();
      throw const AndroidUpdateException(AndroidUpdateFailure.digestMismatch);
    }
    return digest;
  }

  Future<List<AndroidDevice>> devices(AndroidCancellation cancellation) =>
      _run(cancellation, () async => (await _adb()).devices(cancellation));

  Future<AndroidDeviceInfo> inspectDevice(
    String serial,
    AndroidCancellation cancellation,
  ) =>
      _run(
        cancellation,
        () async => (await _adb()).inspect(serial, cancellation),
      );

  Future<AndroidDeviceInfo> install(
    String serial,
    AndroidCancellation cancellation, {
    void Function(String stage)? onStage,
  }) =>
      _run(cancellation, () async {
        final release = await loadMirror();
        if (release == null) {
          throw const AndroidUpdateException(AndroidUpdateFailure.noMirror);
        }
        onStage?.call(AppL10n.strings.android.verifying);
        await _verify(release, cancellation);
        final adb = await _adb();
        final device = await adb.inspect(serial, cancellation);
        device.requireCompatible(release.info);
        cancellation.check();
        onStage?.call(AppL10n.strings.android.installing);
        await adb.install(serial, device.userId, release.apkPath, cancellation);
        onStage?.call(AppL10n.strings.android.verifyingInstalled);
        final updated = await adb.inspect(serial, cancellation);
        if (updated.userId != device.userId ||
            updated.versionCode != release.info.versionCode) {
          throw const AndroidUpdateException(
            AndroidUpdateFailure.verificationFailed,
          );
        }
        return updated;
      });

  Future<void> exportApk(
    String destination,
    AndroidCancellation cancellation,
  ) =>
      _run(cancellation, () async {
        final release = await loadMirror();
        if (release == null) {
          throw const AndroidUpdateException(AndroidUpdateFailure.noMirror);
        }
        final parent = await File(destination).parent.resolveSymbolicLinks();
        final root = await Directory(mirrorDir).resolveSymbolicLinks();
        if (p.equals(parent, root) || p.isWithin(root, parent)) {
          throw const AndroidUpdateException(AndroidUpdateFailure.exportTarget);
        }
        await _verify(release, cancellation);
        final temp = File(
          p.join(
            parent,
            '.otzaria-android-export-$pid-${DateTime.now().microsecondsSinceEpoch}.apk',
          ),
        );
        try {
          final sink = temp.openWrite();
          try {
            await sink.addStream(
              File(release.apkPath).openRead().map((bytes) {
                cancellation.check();
                return bytes;
              }),
            );
            await sink.flush();
          } finally {
            await sink.close();
          }
          if (await androidFileSha256(temp, cancellation) != release.sha256) {
            throw const AndroidUpdateException(
                AndroidUpdateFailure.digestMismatch);
          }
          cancellation.check();
          await temp.rename(destination);
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      });

  Future<String> selectTools(
    String directory,
    AndroidCancellation cancellation, {
    bool copyToDrive = false,
  }) =>
      _run(
        cancellation,
        () => copyToDrive
            ? tools.copyToDrive(directory, cancellation)
            : tools.select(directory, cancellation),
      );

  Future<AdbClient> _adb() async {
    final executable = await tools.resolve();
    if (executable == null) {
      throw const AndroidUpdateException(AndroidUpdateFailure.adbMissing);
    }
    return AdbClient(executable: executable, runner: _runner);
  }

  Future<void> _verify(
    AndroidMirroredRelease release,
    AndroidCancellation cancel,
  ) async {
    final file = File(release.apkPath);
    if (await file.length() != release.size ||
        await androidFileSha256(file, cancel) != release.sha256) {
      throw const AndroidUpdateException(AndroidUpdateFailure.digestMismatch);
    }
    cancel.check();
    if (!release.info.matches(await _inspector.inspect(release.apkPath))) {
      _invalid();
    }
  }

  static Future<Map<String, dynamic>> _readJson(File file) async {
    if (await file.length() > 64 * 1024) _invalid();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) _invalid();
      return json;
    } on FormatException {
      _invalid();
    }
  }

  static bool _isSha256(Object? value) =>
      value is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  static Never _invalid() =>
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidApk);

  void dispose() {
    _disposed = true;
    _active?.cancel();
    _http.close();
  }
}

Future<String> androidFileSha256(File file, AndroidCancellation cancel) async {
  final stream = file.openRead().map((bytes) {
    cancel.check();
    return bytes;
  });
  return (await crypto.sha256.bind(stream).first).toString();
}
