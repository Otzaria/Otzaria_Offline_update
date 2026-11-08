import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'android_models.dart';

class AndroidCommandResult {
  const AndroidCommandResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
}

abstract interface class AndroidCommandRunner {
  Future<AndroidCommandResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required AndroidCancellation cancellation,
  });
}

class AndroidProcessRunner implements AndroidCommandRunner {
  const AndroidProcessRunner();

  @override
  Future<AndroidCommandResult> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required AndroidCancellation cancellation,
  }) async {
    cancellation.check();
    final stop = Completer<AndroidUpdateFailure>();
    var finished = false;
    void requestStop(AndroidUpdateFailure why) {
      if (!finished && !stop.isCompleted) stop.complete(why);
    }

    final timer = Timer(
      timeout,
      () => requestStop(AndroidUpdateFailure.timeout),
    );
    unawaited(
      cancellation.whenCancelled.then(
        (_) => requestStop(AndroidUpdateFailure.cancelled),
      ),
    );
    Process? process;
    var exited = false;
    final subscriptions = <StreamSubscription<String>>[];
    final output = StringBuffer();
    void collect(String chunk) {
      const limit = 1024 * 1024;
      final remaining = limit - output.length;
      if (remaining > 0) {
        output.write(
          chunk.substring(
            0,
            chunk.length < remaining ? chunk.length : remaining,
          ),
        );
      }
    }

    try {
      final starting = Process.start(executable, arguments, runInShell: false);
      final started = await Future.any<Object>([starting, stop.future]);
      if (started is! Process) {
        unawaited(starting.then(_stop).catchError((Object _) {}));
        throw AndroidUpdateException(started as AndroidUpdateFailure);
      }
      process = started;
      final drains = <Future<void>>[];
      for (final stream in [process.stdout, process.stderr]) {
        final done = Completer<void>();
        subscriptions.add(
          stream.transform(const Utf8Decoder(allowMalformed: true)).listen(
            collect,
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object _) {
              if (!done.isCompleted) done.complete();
            },
          ),
        );
        drains.add(done.future);
      }
      final result = await Future.any<Object>([process.exitCode, stop.future]);
      if (result is! int) {
        throw AndroidUpdateException(result as AndroidUpdateFailure);
      }
      exited = true;
      await Future.wait(drains)
          .timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      cancellation.check();
      return AndroidCommandResult(result, output.toString());
    } on ProcessException catch (error) {
      throw AndroidUpdateException(AndroidUpdateFailure.adbFailed, '$error');
    } finally {
      finished = true;
      timer.cancel();
      if (process != null && !exited) await _stop(process);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  static Future<void> _stop(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    }
  }
}

class AdbClient {
  AdbClient({
    required this.executable,
    AndroidCommandRunner? runner,
    this.commandTimeout = const Duration(seconds: 20),
    this.installTimeout = const Duration(minutes: 5),
  }) : _runner = runner ?? const AndroidProcessRunner();

  final String executable;
  final AndroidCommandRunner _runner;
  final Duration commandTimeout;
  final Duration installTimeout;

  Future<List<AndroidDevice>> devices(AndroidCancellation cancel) async {
    final result = await _run(['devices', '-l'], cancel);
    final devices = <AndroidDevice>[];
    for (final line in result.output.split('\n')) {
      final match = RegExp(
        r'^(\S+)\s+(device|unauthorized|offline|no permissions)\b(.*)$',
      ).firstMatch(line.trim());
      if (match == null) continue;
      final serial = match.group(1)!;
      if (!_validSerial(serial)) continue;
      final model =
          RegExp(r'\bmodel:(\S+)').firstMatch(match.group(3)!)?.group(1);
      devices.add(
        AndroidDevice(
          serial: serial,
          state: match.group(2)!,
          model: model?.replaceAll('_', ' ') ?? serial,
        ),
      );
    }
    return devices;
  }

  Future<AndroidDeviceInfo> inspect(
    String serial,
    AndroidCancellation cancel,
  ) async {
    _requireSerial(serial);
    final connected = await devices(cancel);
    final matches = connected.where((d) => d.serial == serial).toList();
    if (matches.length != 1) {
      throw const AndroidUpdateException(
        AndroidUpdateFailure.deviceUnavailable,
      );
    }
    final device = matches.single;
    if (!device.authorized) {
      throw AndroidUpdateException(
        device.state == 'unauthorized'
            ? AndroidUpdateFailure.unauthorized
            : AndroidUpdateFailure.deviceUnavailable,
      );
    }
    final props = (await _run([
      '-s',
      serial,
      'shell',
      'getprop',
    ], cancel))
        .output;
    String? property(String name) => RegExp(
          '^\\[${RegExp.escape(name)}\\]: \\[(.*)\\]\\r?\$',
          multiLine: true,
        ).firstMatch(props)?.group(1)?.trim();
    final sdk = int.tryParse(property('ro.build.version.sdk') ?? '');
    final abis = (property('ro.product.cpu.abilist') ??
            property('ro.product.cpu.abi') ??
            '')
        .split(',')
        .where((v) => v.isNotEmpty)
        .toList();
    final user = (await _run([
      '-s',
      serial,
      'shell',
      'am',
      'get-current-user',
    ], cancel))
        .output;
    final userId = int.tryParse(user.trim());
    if (sdk == null ||
        sdk < 1 ||
        abis.isEmpty ||
        userId == null ||
        userId < 0) {
      throw const AndroidUpdateException(
        AndroidUpdateFailure.verificationFailed,
      );
    }
    final package = (await _run([
      '-s',
      serial,
      'shell',
      'dumpsys',
      'package',
      otzariaAndroidApplicationId,
    ], cancel))
        .output;
    final userMatch = RegExp(
      '^\\s*User $userId:([^\\r\\n]*)',
      multiLine: true,
    ).firstMatch(package);
    final missing = package.contains(
          'Unable to find package: $otzariaAndroidApplicationId',
        ) ||
        package.contains('Unable to find package $otzariaAndroidApplicationId');
    if (!missing && userMatch == null) {
      throw const AndroidUpdateException(
        AndroidUpdateFailure.verificationFailed,
      );
    }
    final installed = userMatch?.group(1)?.contains('installed=true') ?? false;
    final code = installed
        ? int.tryParse(
            RegExp(r'\bversionCode=(\d+)').firstMatch(package)?.group(1) ?? '',
          )
        : null;
    final name = installed
        ? RegExp(r'\bversionName=([^\r\n]+)')
            .firstMatch(package)
            ?.group(1)
            ?.trim()
        : null;
    if (installed && code == null) {
      throw const AndroidUpdateException(
        AndroidUpdateFailure.verificationFailed,
      );
    }
    return AndroidDeviceInfo(
      device: device,
      userId: userId,
      sdk: sdk,
      abis: abis,
      versionCode: code,
      versionName: name,
    );
  }

  Future<void> install(
    String serial,
    int userId,
    String apk,
    AndroidCancellation cancel,
  ) async {
    _requireSerial(serial);
    final result = await _run(
      ['-s', serial, 'install', '-r', '--user', '$userId', apk],
      cancel,
      timeout: installTimeout,
    );
    if (!RegExp(r'^Success\s*$', multiLine: true).hasMatch(result.output)) {
      throw failureFor(result.output);
    }
  }

  Future<AndroidCommandResult> _run(
    List<String> args,
    AndroidCancellation cancel, {
    Duration? timeout,
  }) async {
    final result = await _runner.run(
      executable,
      args,
      timeout: timeout ?? commandTimeout,
      cancellation: cancel,
    );
    if (result.exitCode != 0) throw failureFor(result.output);
    return result;
  }

  static AndroidUpdateException failureFor(String output) {
    final failure = switch (output) {
      _
          when output.contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE') ||
              output.contains('INSTALL_FAILED_SHARED_USER_INCOMPATIBLE') ||
              output.contains(
                'INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES',
              ) =>
        AndroidUpdateFailure.signatureMismatch,
      _ when output.contains('INSTALL_FAILED_VERSION_DOWNGRADE') =>
        AndroidUpdateFailure.downgrade,
      _ when output.contains('INSTALL_FAILED_INSUFFICIENT_STORAGE') =>
        AndroidUpdateFailure.insufficientSpace,
      _
          when output.contains('INSTALL_FAILED_OLDER_SDK') ||
              output.contains('INSTALL_FAILED_DEPRECATED_SDK_VERSION') =>
        AndroidUpdateFailure.incompatibleSdk,
      _ when output.contains('INSTALL_FAILED_NO_MATCHING_ABIS') =>
        AndroidUpdateFailure.incompatibleAbi,
      _
          when output.contains('INSTALL_FAILED_USER_RESTRICTED') ||
              output.contains('INSTALL_FAILED_ABORTED') ||
              output.contains('INSTALL_FAILED_VERIFICATION_FAILURE') =>
        AndroidUpdateFailure.installationBlocked,
      _ when output.contains('unauthorized') =>
        AndroidUpdateFailure.unauthorized,
      _
          when output.contains('device offline') ||
              output.contains('no devices') ||
              output.contains('not found') ||
              output.contains('disconnected') ||
              output.contains('no permissions') =>
        AndroidUpdateFailure.deviceUnavailable,
      _ => AndroidUpdateFailure.adbFailed,
    };
    return AndroidUpdateException(failure, output.trim());
  }

  static bool _validSerial(String serial) =>
      RegExp(r'^[a-zA-Z0-9._:-]{1,200}$').hasMatch(serial);

  static void _requireSerial(String serial) {
    if (!_validSerial(serial)) {
      throw const AndroidUpdateException(
        AndroidUpdateFailure.deviceUnavailable,
      );
    }
  }
}
