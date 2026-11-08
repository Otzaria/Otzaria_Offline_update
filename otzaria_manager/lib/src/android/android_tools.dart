import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:path/path.dart' as p;

import 'adb_client.dart';
import 'android_models.dart';

class AndroidTools {
  AndroidTools({
    required this.mirrorDir,
    required this.stateDir,
    this.readOnly = false,
    String? operatingSystem,
    String? machineKey,
    AndroidCommandRunner? runner,
  })  : operatingSystem = operatingSystem ?? Platform.operatingSystem,
        _machineKey = machineKey ??
            crypto.sha256
                .convert(
                  utf8.encode(
                    '${Platform.operatingSystem}|${Platform.localHostname}|'
                    '${Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? ''}',
                  ),
                )
                .toString(),
        _runner = runner ?? const AndroidProcessRunner();

  static const downloadUrl =
      'https://developer.android.com/tools/releases/platform-tools';
  final String mirrorDir;
  final String stateDir;
  final bool readOnly;
  final String operatingSystem;
  final String _machineKey;
  final AndroidCommandRunner _runner;

  String get _binary => operatingSystem == 'windows' ? 'adb.exe' : 'adb';
  String get _toolsDir => p.join(mirrorDir, 'platform-tools', operatingSystem);
  String get _stateFile => p.join(stateDir, 'android_tools.json');

  Future<String?> resolve() async {
    final state = await _readState();
    final selected = state[_machineKey];
    if (selected is String &&
        p.isAbsolute(selected) &&
        p.basename(selected) == _binary &&
        await File(selected).exists()) {
      return selected;
    }
    final portable = p.join(_toolsDir, _binary);
    return await File(portable).exists() ? portable : null;
  }

  Future<String> select(String directory, AndroidCancellation cancel) async {
    final executable = await _validate(directory, cancel);
    await _remember(executable);
    return executable;
  }

  Future<String> copyToDrive(
    String directory,
    AndroidCancellation cancel,
  ) async {
    if (readOnly) {
      throw const AndroidUpdateException(AndroidUpdateFailure.readOnly);
    }
    final source = await Directory(directory).resolveSymbolicLinks();
    await _validate(source, cancel);
    if (p.equals(p.absolute(source), p.absolute(_toolsDir))) {
      final executable = p.join(_toolsDir, _binary);
      await _remember(executable);
      return executable;
    }
    if (p.equals(source, p.absolute(mirrorDir)) ||
        p.isWithin(source, p.absolute(mirrorDir)) ||
        p.isWithin(p.absolute(mirrorDir), source)) {
      throw const AndroidUpdateException(AndroidUpdateFailure.adbMissing);
    }
    final stage = Directory('$_toolsDir.staging-$pid');
    final previous = Directory('$_toolsDir.previous-$pid');
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create(recursive: true);
    try {
      var total = 0;
      var count = 0;
      await for (final entry in Directory(
        source,
      ).list(recursive: true, followLinks: false)) {
        cancel.check();
        if (++count > 500 || entry is Link) {
          throw const AndroidUpdateException(AndroidUpdateFailure.adbMissing);
        }
        final destination = p.join(
          stage.path,
          p.relative(entry.path, from: source),
        );
        if (entry is Directory) {
          await Directory(destination).create(recursive: true);
        } else if (entry is File) {
          total += await entry.length();
          if (total > 128 * 1024 * 1024) {
            throw const AndroidUpdateException(AndroidUpdateFailure.adbMissing);
          }
          await File(destination).parent.create(recursive: true);
          await entry.copy(destination);
        }
      }
      cancel.check();
      if (operatingSystem != 'windows') {
        final chmod = await _runner.run(
          '/bin/chmod',
          ['u+x', p.join(stage.path, _binary)],
          timeout: const Duration(seconds: 10),
          cancellation: cancel,
        );
        if (chmod.exitCode != 0) {
          throw AndroidUpdateException(
            AndroidUpdateFailure.adbFailed,
            chmod.output,
          );
        }
      }
      await _validate(stage.path, cancel);
      cancel.check();
      final target = Directory(_toolsDir);
      if (await previous.exists()) await previous.delete(recursive: true);
      final replacing = await target.exists();
      if (replacing) await target.rename(previous.path);
      try {
        await stage.rename(target.path);
      } catch (_) {
        if (replacing) await previous.rename(target.path);
        rethrow;
      }
      if (await previous.exists()) await previous.delete(recursive: true);
      final executable = p.join(_toolsDir, _binary);
      await _remember(executable);
      return executable;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  Future<String> _validate(String directory, AndroidCancellation cancel) async {
    final executable = p.absolute(p.join(directory, _binary));
    final files = [
      _binary,
      if (operatingSystem == 'windows') ...[
        'AdbWinApi.dll',
        'AdbWinUsbApi.dll',
      ],
    ];
    for (final name in files) {
      if (!await File(p.join(directory, name)).exists()) {
        throw const AndroidUpdateException(AndroidUpdateFailure.adbMissing);
      }
    }
    final version = await _runner.run(
      executable,
      ['version'],
      timeout: const Duration(seconds: 10),
      cancellation: cancel,
    );
    if (version.exitCode != 0 ||
        !version.output.contains('Android Debug Bridge version')) {
      throw AndroidUpdateException(
        AndroidUpdateFailure.adbFailed,
        version.output,
      );
    }
    return executable;
  }

  Future<Map<String, dynamic>> _readState() async {
    final file = File(_stateFile);
    if (!await file.exists()) return {};
    if (await file.length() > 64 * 1024) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _remember(String executable) async {
    final state = await _readState();
    state[_machineKey] = executable;
    await Directory(stateDir).create(recursive: true);
    await writeStringAtomically(_stateFile, jsonEncode(state));
  }
}
