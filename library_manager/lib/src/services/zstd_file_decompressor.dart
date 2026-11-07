import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

abstract final class ZstdFileDecompressor {
  static Future<bool> decompressFileToFile(
    String sourcePath,
    String destPath, {
    void Function(int bytesRead, int totalBytes)? onProgress,
    void Function(int bytesWritten)? onOutputProgress,
    void Function(String sha256Hex)? onSourceDigest,
    void Function(String sha256Hex, int bytesWritten)? onOutputDigest,
    bool Function()? isCancelled,
    int? maxOutputBytes,
  }) async {
    if (maxOutputBytes != null && maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    if (p.equals(p.absolute(sourcePath), p.absolute(destPath)) ||
        (File(sourcePath).existsSync() &&
            File(destPath).existsSync() &&
            FileSystemEntity.identicalSync(
              File(sourcePath).resolveSymbolicLinksSync(),
              File(destPath).resolveSymbolicLinksSync(),
            ))) {
      throw ArgumentError('Source and destination must be distinct files');
    }
    if (isCancelled?.call() == true) {
      throw ZstdCancelledException(
        AppL10n.strings.libraryDomain.updateCancelled,
      );
    }
    final language = AppL10n.language;
    final outputLimit = maxOutputBytes ?? kDefaultMaxExtractedBytes;
    final hashSource = onSourceDigest != null;
    final hashOutput = onOutputDigest != null;
    if (onProgress == null &&
        onOutputProgress == null &&
        !hashSource &&
        !hashOutput &&
        isCancelled == null) {
      final outcome = await _runDecompressIsolate(
        sourcePath,
        destPath,
        language,
        false,
        false,
        0,
        outputLimit,
        null,
      );
      return outcome.unwrap().$1;
    }

    final port = ReceivePort();
    final progressDrained = Completer<void>();
    final cancelFlag = malloc.allocate<Uint8>(1);
    cancelFlag.value = 0;
    Object? callbackError;
    StackTrace? callbackStack;
    final sub = port.listen((msg) {
      try {
        if (msg == _progressComplete) {
          progressDrained.complete();
        } else if (callbackError == null && cancelFlag.value == 0) {
          if (msg is (int, int)) onProgress?.call(msg.$1, msg.$2);
          if (msg is int) onOutputProgress?.call(msg);
        }
        if (isCancelled?.call() == true) cancelFlag.value = 1;
      } catch (error, stack) {
        callbackError ??= error;
        callbackStack ??= stack;
        cancelFlag.value = 1;
      }
    });
    final poll = isCancelled == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 50), (_) {
            try {
              if (isCancelled()) cancelFlag.value = 1;
            } catch (error, stack) {
              callbackError ??= error;
              callbackStack ??= stack;
              cancelFlag.value = 1;
            }
          });
    var completed = false;
    var producedOutput = false;
    try {
      final outcome = await _runDecompressIsolate(
        sourcePath,
        destPath,
        language,
        hashSource,
        hashOutput,
        cancelFlag.address,
        outputLimit,
        port.sendPort,
      );
      producedOutput = outcome.result?.$1 == true;
      // Same-port ordering guarantees the final progress callback is observed
      // before the result can be accepted, including callback errors/cancel.
      await progressDrained.future;
      if (callbackError != null) {
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      }
      if (cancelFlag.value != 0 || isCancelled?.call() == true) {
        throw ZstdCancelledException(
          AppL10n.strings.libraryDomain.updateCancelled,
        );
      }
      final (ok, sourceDigest, outputDigest, written) = outcome.unwrap();
      if (sourceDigest != null) onSourceDigest?.call(sourceDigest);
      if (outputDigest != null) onOutputDigest?.call(outputDigest, written);
      if (isCancelled?.call() == true) {
        throw ZstdCancelledException(
          AppL10n.strings.libraryDomain.updateCancelled,
        );
      }
      completed = true;
      return ok;
    } catch (_) {
      if (callbackError != null) {
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      }
      rethrow;
    } finally {
      poll?.cancel();
      await sub.cancel();
      port.close();
      malloc.free(cancelFlag);
      if (!completed && producedOutput) {
        try {
          await File(destPath).delete();
        } on FileSystemException {
          // הקובץ כבר נוקה ב-isolate או שהכונן אינו זמין.
        }
      }
    }
  }

  static Future<_ZstdWorkerOutcome> _runDecompressIsolate(
    String sourcePath,
    String destPath,
    AppLanguage language,
    bool hashSource,
    bool hashOutput,
    int cancelFlagAddress,
    int maxOutputBytes,
    SendPort? sendPort,
  ) {
    return Isolate.run(() async {
      try {
        return _ZstdWorkerOutcome(
          result: await _decompressInIsolate((
            sourcePath,
            destPath,
            language,
            hashSource,
            hashOutput,
            cancelFlagAddress,
            maxOutputBytes,
            sendPort,
          )),
        );
      } catch (error, stack) {
        return _ZstdWorkerOutcome(error: error, stack: stack);
      } finally {
        sendPort?.send(_progressComplete);
      }
    });
  }

  static ZstandardNativeBindings? bindingsOrNull() {
    final library = _openLibrary();
    return library == null ? null : ZstandardNativeBindings(library);
  }

  static int? contentSizeOf(String sourcePath) {
    final bindings = bindingsOrNull();
    if (bindings == null) return null;
    final file = File(sourcePath);
    if (!file.existsSync()) return null;

    const headerMax = 18;
    final raf = file.openSync();
    final buffer = malloc.allocate<Uint8>(headerMax);
    try {
      final view = buffer.asTypedList(headerMax);
      final read = raf.readIntoSync(view, 0, headerMax);
      if (read <= 0) return null;
      final size = bindings.ZSTD_getFrameContentSize(buffer.cast(), read);
      if (size < 0) return null;
      return size;
    } catch (_) {
      return null;
    } finally {
      malloc.free(buffer);
      raf.closeSync();
    }
  }
}

class ZstdStreamException implements Exception {
  const ZstdStreamException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZstdCancelledException extends ZstdStreamException {
  const ZstdCancelledException(super.message);
}

class ZstdOutputLimitExceeded extends ZstdStreamException {
  const ZstdOutputLimitExceeded(this.limit, super.message);
  final int limit;
  @override
  String toString() => message;
}

/// כשל משאבים (הקשר שלא נוצר, זיכרון) — לא פגם בקובץ שמחולץ.
class ZstdResourceException extends ZstdStreamException {
  const ZstdResourceException(super.message);
}

DynamicLibrary? _openLibrary() {
  final plugin = _tryOpen(switch (Platform.operatingSystem) {
    'windows' => 'zstandard_windows.dll',
    'macos' => 'zstandard_macos.framework/zstandard_macos',
    'linux' => 'libzstandard_linux.so',
    _ => null,
  });
  if (plugin != null) return plugin;
  for (final name in [
    Platform.environment['ZSTD_LIBRARY_PATH'],
    switch (Platform.operatingSystem) {
      'macos' => 'libzstd.1.dylib',
      'linux' => 'libzstd.so.1',
      _ => null,
    },
  ]) {
    final library = _tryOpen(name);
    if (library != null && library.providesSymbol('ZSTD_DCtx_setParameter')) {
      return library;
    }
  }
  return null;
}

DynamicLibrary? _tryOpen(String? name) {
  if (name == null || name.isEmpty) return null;
  try {
    return DynamicLibrary.open(name);
  } catch (_) {
    return null;
  }
}

// Preserve long-window archives. libzstd supports at most 30 on 32-bit
// processes and 31 on 64-bit processes; the native window may use 1/2 GiB.
int get _maxWindowLog => sizeOf<IntPtr>() == 4 ? 30 : 31;

const _progressComplete = 'zstd.progress.complete';

class _ZstdWorkerOutcome {
  const _ZstdWorkerOutcome({this.result, this.error, this.stack});
  final (bool, String?, String?, int)? result;
  final Object? error;
  final StackTrace? stack;

  (bool, String?, String?, int) unwrap() {
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return result!;
  }
}

Future<(bool, String?, String?, int)> _decompressInIsolate(
  (String, String, AppLanguage, bool, bool, int, int, SendPort?) args,
) async {
  AppL10n.use(args.$3);
  final progressPort = args.$8;
  final maxOutputBytes = args.$7;
  final cancelFlag = args.$6 == 0
      ? nullptr
      : Pointer<Uint8>.fromAddress(args.$6);
  final strings = AppL10n.strings.libraryDomain;
  final library = _openLibrary();
  if (library == null) return (false, null, null, 0);
  final zstd = ZstandardNativeBindings(library);

  Sha256Stream? hasher;
  Sha256Stream? outHasher;
  Pointer<ZSTD_DCtx> dctx = nullptr;
  Pointer<Uint8> inPtr = nullptr;
  Pointer<Uint8> outPtr = nullptr;
  Pointer<ZSTD_inBuffer> inBuffer = nullptr;
  Pointer<ZSTD_outBuffer> outBuffer = nullptr;
  RandomAccessFile? source;
  RandomAccessFile? dest;
  var createdOutput = false;
  var completed = false;
  void checkCancellation() {
    if (cancelFlag != nullptr && cancelFlag.value != 0) {
      throw ZstdCancelledException(strings.updateCancelled);
    }
  }

  try {
    hasher = args.$4 ? Sha256Stream() : null;
    outHasher = args.$5 ? Sha256Stream() : null;

    final inCapacity = zstd.ZSTD_DStreamInSize();
    final outCapacity = zstd.ZSTD_DStreamOutSize();

    dctx = zstd.ZSTD_createDCtx();
    if (dctx == nullptr) {
      throw ZstdResourceException(strings.zstdContextCreationFailed);
    }
    inPtr = malloc.allocate<Uint8>(inCapacity);
    outPtr = malloc.allocate<Uint8>(outCapacity);
    inBuffer = malloc<ZSTD_inBuffer>();
    outBuffer = malloc<ZSTD_outBuffer>();

    checkCancellation();
    final input = await File(args.$1).open();
    source = input;
    final totalBytes = await input.length();
    checkCancellation();
    final output = await File(args.$2).open(mode: FileMode.write);
    createdOutput = true;
    dest = output;
    final inView = inPtr.asTypedList(inCapacity);
    final outView = outPtr.asTypedList(outCapacity);

    final init = zstd.ZSTD_initDStream(dctx);
    if (zstd.ZSTD_isError(init) != 0) {
      throw ZstdResourceException(strings.zstdContextCreationFailed);
    }
    final windowLimit = zstd.ZSTD_DCtx_setParameter(
      dctx,
      ZSTD_dParameter.ZSTD_d_windowLogMax,
      _maxWindowLog,
    );
    if (zstd.ZSTD_isError(windowLimit) != 0) {
      throw ZstdResourceException(strings.zstdContextCreationFailed);
    }
    inBuffer.ref.src = inPtr.cast();
    outBuffer.ref.dst = outPtr.cast();

    var lastResult = 0;
    var sawInput = false;
    var bytesRead = 0;
    var bytesWritten = 0;
    final progressClock = Stopwatch()..start();
    var lastProgressMs = -100;
    var lastInputProgress = -1;
    var lastOutputProgress = -1;
    void reportProgress() {
      if (bytesRead != lastInputProgress) {
        progressPort?.send((bytesRead, totalBytes));
        lastInputProgress = bytesRead;
      }
      if (bytesWritten != lastOutputProgress) {
        progressPort?.send(bytesWritten);
        lastOutputProgress = bytesWritten;
      }
    }

    while (true) {
      checkCancellation();
      final read = await input.readInto(inView, 0, inCapacity);
      checkCancellation();
      if (read == 0) break;
      sawInput = true;
      bytesRead += read;
      hasher?.addSlice(inView, 0, read);

      inBuffer.ref.size = read;
      inBuffer.ref.pos = 0;

      while (inBuffer.ref.pos < inBuffer.ref.size ||
          (lastResult != 0 && outBuffer.ref.pos == outCapacity)) {
        checkCancellation();
        outBuffer.ref.size = outCapacity;
        outBuffer.ref.pos = 0;
        lastResult = zstd.ZSTD_decompressStream(dctx, outBuffer, inBuffer);
        if (zstd.ZSTD_isError(lastResult) != 0) {
          final message = strings.zstdDecompressionFailed(
            _errorName(zstd, lastResult),
          );
          throw _isResourceError(zstd, lastResult)
              ? ZstdResourceException(message)
              : ZstdStreamException(message);
        }
        final produced = outBuffer.ref.pos;
        if (produced > 0) {
          if (maxOutputBytes >= 0 && bytesWritten + produced > maxOutputBytes) {
            throw ZstdOutputLimitExceeded(
              maxOutputBytes,
              strings.checksumMismatchDetailed(
                strings.extractedFileSizeLabel,
                '$maxOutputBytes',
                '> $maxOutputBytes',
              ),
            );
          }
          checkCancellation();
          await output.writeFrom(outView, 0, produced);
          checkCancellation();
          outHasher?.addSlice(outView, 0, produced);
          bytesWritten += produced;
          final elapsed = progressClock.elapsedMilliseconds;
          if (elapsed - lastProgressMs >= 100) {
            reportProgress();
            lastProgressMs = elapsed;
          }
        }
      }
    }

    if (!sawInput) {
      throw ZstdStreamException(strings.zstdEmptyInput);
    }
    if (lastResult != 0) {
      throw ZstdStreamException(strings.zstdTruncatedFrame);
    }
    checkCancellation();
    await output.flush();
    checkCancellation();
    await output.close();
    dest = null;
    await input.close();
    source = null;
    reportProgress();
    final result = (true, hasher?.close(), outHasher?.close(), bytesWritten);
    completed = true;
    return result;
  } finally {
    hasher?.dispose();
    outHasher?.dispose();
    for (final file in [source, dest]) {
      try {
        await file?.close();
      } on FileSystemException {
        // שומרים את שגיאת החילוץ המקורית; הפלט החלקי יימחק בהמשך.
      }
    }
    if (inBuffer != nullptr) malloc.free(inBuffer);
    if (outBuffer != nullptr) malloc.free(outBuffer);
    if (inPtr != nullptr) malloc.free(inPtr);
    if (outPtr != nullptr) malloc.free(outPtr);
    if (dctx != nullptr) zstd.ZSTD_freeDCtx(dctx);
    if (!completed && createdOutput) {
      try {
        await File(args.$2).delete();
      } on FileSystemException {
        // כונן שנעלם אינו יכול לעכב שחרור זיכרון ומשאבים.
      }
    }
  }
}

// קוד שגיאה שה-bindings אינם מכירים (libzstd חדשה יותר) זורק ב-`fromValue`.
bool _isResourceError(ZstandardNativeBindings zstd, int code) {
  try {
    final error = zstd.ZSTD_getErrorCode(code);
    return error == ZSTD_ErrorCode.ZSTD_error_memory_allocation ||
        error == ZSTD_ErrorCode.ZSTD_error_frameParameter_windowTooLarge;
  } catch (_) {
    return false;
  }
}

String _errorName(ZstandardNativeBindings zstd, int code) {
  try {
    return zstd.ZSTD_getErrorName(code).cast<Utf8>().toDartString();
  } catch (_) {
    return 'code $code';
  }
}
