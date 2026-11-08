import 'dart:async';

import 'package:otzaria_l10n/otzaria_l10n.dart';

const otzariaAndroidApplicationId = 'org.otzaria.otzaria';

enum AndroidUpdateFailure {
  busy,
  cancelled,
  timeout,
  adbMissing,
  adbFailed,
  deviceUnavailable,
  unauthorized,
  invalidApk,
  digestMismatch,
  noMirror,
  noRelease,
  signatureMismatch,
  downgrade,
  insufficientSpace,
  incompatibleSdk,
  incompatibleAbi,
  installationBlocked,
  verificationFailed,
  readOnly,
  exportTarget,
}

class AndroidUpdateException implements Exception {
  const AndroidUpdateException(this.failure, [this.details]);

  final AndroidUpdateFailure failure;
  final String? details;

  @override
  String toString() {
    final t = AppL10n.strings.android;
    return switch (failure) {
      AndroidUpdateFailure.busy => t.busy,
      AndroidUpdateFailure.cancelled => t.cancelled,
      AndroidUpdateFailure.timeout => t.timeout,
      AndroidUpdateFailure.adbMissing => t.adbMissing,
      AndroidUpdateFailure.adbFailed => t.adbFailed,
      AndroidUpdateFailure.deviceUnavailable => t.deviceUnavailable,
      AndroidUpdateFailure.unauthorized => t.unauthorized,
      AndroidUpdateFailure.invalidApk => t.invalidApk,
      AndroidUpdateFailure.digestMismatch => t.digestMismatch,
      AndroidUpdateFailure.noMirror => t.noMirror,
      AndroidUpdateFailure.noRelease => t.noRelease,
      AndroidUpdateFailure.signatureMismatch => t.signatureMismatch,
      AndroidUpdateFailure.downgrade => t.downgrade,
      AndroidUpdateFailure.insufficientSpace => t.insufficientSpace,
      AndroidUpdateFailure.incompatibleSdk => t.incompatibleSdk,
      AndroidUpdateFailure.incompatibleAbi => t.incompatibleAbi,
      AndroidUpdateFailure.installationBlocked => t.installationBlocked,
      AndroidUpdateFailure.verificationFailed => t.verificationFailed,
      AndroidUpdateFailure.readOnly => t.readOnly,
      AndroidUpdateFailure.exportTarget => t.exportTarget,
    };
  }
}

class AndroidCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) {
      throw const AndroidUpdateException(AndroidUpdateFailure.cancelled);
    }
  }
}

class AndroidApkInfo {
  const AndroidApkInfo({
    required this.applicationId,
    required this.versionCode,
    required this.versionName,
    required this.minSdk,
    required this.targetSdk,
    required this.abis,
  });

  final String applicationId;
  final int versionCode;
  final String versionName;
  final int minSdk;
  final int targetSdk;
  final List<String> abis;

  Map<String, Object> toJson() => {
        'applicationId': applicationId,
        'versionCode': versionCode,
        'versionName': versionName,
        'minSdk': minSdk,
        'targetSdk': targetSdk,
        'abis': abis,
      };

  factory AndroidApkInfo.fromJson(Map<String, dynamic> json) {
    final id = json['applicationId'];
    final code = json['versionCode'];
    final name = json['versionName'];
    final min = json['minSdk'];
    final target = json['targetSdk'];
    final abis = json['abis'];
    if (id != otzariaAndroidApplicationId ||
        code is! int ||
        code <= 0 ||
        name is! String ||
        name.isEmpty ||
        name.length > 200 ||
        min is! int ||
        min < 1 ||
        target is! int ||
        target < min ||
        abis is! List ||
        abis.isEmpty ||
        abis.length > 16 ||
        abis.any(
          (a) => a is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,32}$').hasMatch(a),
        )) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidApk);
    }
    return AndroidApkInfo(
      applicationId: id as String,
      versionCode: code,
      versionName: name,
      minSdk: min,
      targetSdk: target,
      abis: List<String>.unmodifiable(abis.cast<String>()),
    );
  }

  bool matches(AndroidApkInfo other) =>
      applicationId == other.applicationId &&
      versionCode == other.versionCode &&
      versionName == other.versionName &&
      minSdk == other.minSdk &&
      targetSdk == other.targetSdk &&
      abis.toSet().containsAll(other.abis) &&
      other.abis.toSet().containsAll(abis);
}

class AndroidMirroredRelease {
  const AndroidMirroredRelease({
    required this.tagName,
    required this.apkPath,
    required this.size,
    required this.sha256,
    required this.info,
  });

  final String tagName;
  final String apkPath;
  final int size;
  final String sha256;
  final AndroidApkInfo info;
}

class AndroidDevice {
  const AndroidDevice({
    required this.serial,
    required this.state,
    required this.model,
  });

  final String serial;
  final String state;
  final String model;
  bool get authorized => state == 'device';
}

class AndroidDeviceInfo {
  const AndroidDeviceInfo({
    required this.device,
    required this.userId,
    required this.sdk,
    required this.abis,
    this.versionCode,
    this.versionName,
  });

  final AndroidDevice device;
  final int userId;
  final int sdk;
  final List<String> abis;
  final int? versionCode;
  final String? versionName;

  void requireCompatible(AndroidApkInfo apk) {
    if (!device.authorized) {
      throw const AndroidUpdateException(AndroidUpdateFailure.unauthorized);
    }
    if (sdk < apk.minSdk) {
      throw const AndroidUpdateException(AndroidUpdateFailure.incompatibleSdk);
    }
    if (!abis.any(apk.abis.contains)) {
      throw const AndroidUpdateException(AndroidUpdateFailure.incompatibleAbi);
    }
    if (versionCode != null && apk.versionCode < versionCode!) {
      throw const AndroidUpdateException(AndroidUpdateFailure.downgrade);
    }
  }
}
