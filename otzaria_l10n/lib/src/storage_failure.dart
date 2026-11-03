import 'dart:io';

import 'app_l10n.dart';

/// אין מקום בכונן, כסוג ולא כטקסט. [neededBytes] ו-[freeBytes] `null` כשאיש
/// לא מדד אותם (errno 112 באמצע כתיבה אינו מספק אותם) — אין להמציא ערך.
class StorageFullException implements IOException {
  const StorageFullException({
    this.dir,
    this.neededBytes,
    this.freeBytes,
    this.message,
    this.cause,
  });

  final String? dir;
  final int? neededBytes;
  final int? freeBytes;

  /// ההודעה המתורגמת כשהזורק מדד בעצמו (`notEnoughDiskSpace` וכד').
  final String? message;
  final Object? cause;

  @override
  String toString() {
    final text = message;
    if (text != null) return text;
    final where = dir;
    final strings = AppL10n.strings.common;
    return where == null
        ? strings.storageFullUnknownDir
        : strings.storageFullNoDetails(where);
  }
}

/// כשל "הכונן מלא": [StorageFullException], או errno מתאים ב-[FileSystemException]
/// / [OSError]. "גישה נדחתה" ושגיאות כתיבה אחרות אינן נכללות.
bool isStorageFull(Object? error, {bool? windows}) {
  if (error is StorageFullException) return true;
  final os = switch (error) {
    FileSystemException(:final osError) => osError,
    OSError() => error,
    _ => null,
  };
  if (os == null) return false;
  return isStorageFullErrno(os.errorCode, windows: windows);
}

/// Windows: 112 `ERROR_DISK_FULL`, 39 `ERROR_HANDLE_DISK_FULL`. אחרות: 28
/// `ENOSPC`, ומכסה — 122 בלינוקס, 69 ב-macOS.
bool isStorageFullErrno(int errno, {bool? windows}) {
  if (windows ?? Platform.isWindows) return errno == 112 || errno == 39;
  return errno == 28 || errno == 122 || errno == 69;
}

/// קובץ או כונן פגומים ואינם קריאים, כסוג ולא כטקסט: לא מחסור במקום ולא רשת,
/// ו"נסה שוב" לבדו לא יעזור.
class StorageCorruptException implements IOException {
  StorageCorruptException({
    this.dir,
    this.cause,
    this.errno,
    DriveCheckTool? tool,
  }) : tool = tool ?? DriveCheckTool.forPlatform();

  final String? dir;
  final Object? cause;

  /// הקוד האמיתי שהמערכת דיווחה; `null` כשלא ידוע.
  final int? errno;
  final DriveCheckTool tool;

  @override
  String toString() {
    final where = dir;
    final strings = AppL10n.strings.common;
    return where == null
        ? strings.storageDamagedUnknownDir(tool, errno)
        : strings.storageDamagedNoDetails(where, tool, errno);
  }
}

/// הכלי שבודק כונן במערכת שבה קרה הכשל.
enum DriveCheckTool {
  chkdsk,
  diskUtility,
  fsck;

  static DriveCheckTool forPlatform({bool? windows, bool? macos}) {
    if (windows ?? Platform.isWindows) return chkdsk;
    return (macos ?? Platform.isMacOS) ? diskUtility : fsck;
  }
}

/// [StorageCorruptException], או errno של נזק/שגיאת נתונים ב-[FileSystemException]
/// / [OSError].
bool isStorageCorrupt(Object? error, {bool? windows}) {
  if (error is StorageCorruptException) return true;
  final os = switch (error) {
    FileSystemException(:final osError) => osError,
    OSError() => error,
    _ => null,
  };
  if (os == null) return false;
  return isStorageCorruptErrno(os.errorCode, windows: windows);
}

/// Windows: 1392 `ERROR_FILE_CORRUPT`, 1393 `ERROR_DISK_CORRUPT`, 23 `ERROR_CRC`;
/// לא 1117/483 — הם מופיעים גם כשהכונן נשלף. אחרות: 5 `EIO`, 117 `EUCLEAN`.
bool isStorageCorruptErrno(int errno, {bool? windows}) {
  if (windows ?? Platform.isWindows) {
    return const {1392, 1393, 23}.contains(errno);
  }
  return errno == 5 || errno == 117;
}
