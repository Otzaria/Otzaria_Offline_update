import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

abstract final class ZstdFileDecompressor {
  static Future<bool> decompressFileToFile(
    String sourcePath,
    String destPath, {
    void Function(int bytesRead, int totalBytes)? onProgress,
    void Function(String sha256Hex)? onSourceDigest,
    void Function(String sha256Hex, int bytesWritten)? onOutputDigest,
    bool Function()? isCancelled,
    int? maxOutputBytes,
  }) async {
    final language = AppL10n.language;
    final outputLimit = maxOutputBytes ?? -1;
    final hashSource = onSourceDigest != null;
    final hashOutput = onOutputDigest != null;
    if (onProgress == null &&
        !hashSource &&
        !hashOutput &&
        isCancelled == null) {
      final (ok, _, _, _) = await _runDecompressIsolate(
        sourcePath,
        destPath,
        language,
        false,
        false,
        0,
        outputLimit,
        null,
      );
      return ok;
    }

    final port = ReceivePort();
    final sub = port.listen((msg) {
      if (msg is (int, int)) onProgress?.call(msg.$1, msg.$2);
    });
    final cancelFlag = isCancelled == null
        ? nullptr
        : malloc.allocate<Uint8>(1);
    if (isCancelled != null) cancelFlag.value = isCancelled() ? 1 : 0;
    final poll = isCancelled == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 200), (_) {
            if (isCancelled()) cancelFlag.value = 1;
          });
    try {
      final (
        ok,
        sourceDigest,
        outputDigest,
        written,
      ) = await _runDecompressIsolate(
        sourcePath,
        destPath,
        language,
        hashSource,
        hashOutput,
        cancelFlag.address,
        outputLimit,
        port.sendPort,
      );
      if (sourceDigest != null) onSourceDigest?.call(sourceDigest);
      if (outputDigest != null) onOutputDigest?.call(outputDigest, written);
      return ok;
    } finally {
      poll?.cancel();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      port.close();
      if (cancelFlag != nullptr) malloc.free(cancelFlag);
    }
  }

  static Future<(bool, String?, String?, int)> _runDecompressIsolate(
    String sourcePath,
    String destPath,
    AppLanguage language,
    bool hashSource,
    bool hashOutput,
    int cancelFlagAddress,
    int maxOutputBytes,
    SendPort? sendPort,
  ) {
    return Isolate.run(
      () => _decompressInIsolate((
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
  String toString() => 'ZstdStreamException: $message';
}

class ZstdOutputLimitExceeded extends ZstdStreamException {
  const ZstdOutputLimitExceeded(this.limit, super.message);
  final int limit;
  @override
  String toString() => 'ZstdOutputLimitExceeded: $message';
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

/// גבול חלון הפענוח. 31 הוא המקסימום שהפורמט מגדיר, ומרווח הוא כל העניין:
/// קלט שנדחס ב-`--long` היה נדחה בברירת המחדל (27).
const int _maxWindowLog = 31;

(bool, String?, String?, int) _decompressInIsolate(
  (String, String, AppLanguage, bool, bool, int, int, SendPort?) args,
) {
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

  try {
    hasher = args.$4 ? Sha256Stream() : null;
    outHasher = args.$5 ? Sha256Stream() : null;

    final inCapacity = zstd.ZSTD_DStreamInSize();
    final outCapacity = zstd.ZSTD_DStreamOutSize();

    dctx = zstd.ZSTD_createDCtx();
    if (dctx == nullptr) {
      throw ZstdStreamException(strings.zstdContextCreationFailed);
    }
    inPtr = malloc.allocate<Uint8>(inCapacity);
    outPtr = malloc.allocate<Uint8>(outCapacity);
    inBuffer = malloc<ZSTD_inBuffer>();
    outBuffer = malloc<ZSTD_outBuffer>();

    final input = File(args.$1).openSync();
    source = input;
    final totalBytes = input.lengthSync();
    final output = File(args.$2).openSync(mode: FileMode.write);
    dest = output;
    final inView = inPtr.asTypedList(inCapacity);
    final outView = outPtr.asTypedList(outCapacity);

    final init = zstd.ZSTD_initDStream(dctx);
    if (zstd.ZSTD_isError(init) != 0) {
      throw ZstdStreamException(strings.zstdContextCreationFailed);
    }
    zstd.ZSTD_DCtx_setParameter(
      dctx,
      ZSTD_dParameter.ZSTD_d_windowLogMax,
      _maxWindowLog,
    );
    inBuffer.ref.src = inPtr.cast();
    outBuffer.ref.dst = outPtr.cast();

    var lastResult = 0;
    var sawInput = false;
    var bytesRead = 0;
    var bytesWritten = 0;
    while (true) {
      if (cancelFlag != nullptr && cancelFlag.value != 0) {
        throw ZstdStreamException(strings.updateCancelled);
      }
      final read = input.readIntoSync(inView, 0, inCapacity);
      if (read == 0) break;
      sawInput = true;
      bytesRead += read;
      hasher?.addSlice(inView, 0, read);
      progressPort?.send((bytesRead, totalBytes));

      inBuffer.ref.size = read;
      inBuffer.ref.pos = 0;

      while (inBuffer.ref.pos < inBuffer.ref.size) {
        outBuffer.ref.size = outCapacity;
        outBuffer.ref.pos = 0;
        lastResult = zstd.ZSTD_decompressStream(dctx, outBuffer, inBuffer);
        if (zstd.ZSTD_isError(lastResult) != 0) {
          throw ZstdStreamException(
            strings.zstdDecompressionFailed(_errorName(zstd, lastResult)),
          );
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
          output.writeFromSync(outView, 0, produced);
          outHasher?.addSlice(outView, 0, produced);
          bytesWritten += produced;
        }
      }
    }

    if (!sawInput) {
      throw ZstdStreamException(strings.zstdEmptyInput);
    }
    if (lastResult != 0) {
      throw ZstdStreamException(strings.zstdTruncatedFrame);
    }
    output.flushSync();
    return (true, hasher?.close(), outHasher?.close(), bytesWritten);
  } finally {
    hasher?.dispose();
    outHasher?.dispose();
    source?.closeSync();
    dest?.closeSync();
    if (inBuffer != nullptr) malloc.free(inBuffer);
    if (outBuffer != nullptr) malloc.free(outBuffer);
    if (inPtr != nullptr) malloc.free(inPtr);
    if (outPtr != nullptr) malloc.free(outPtr);
    if (dctx != nullptr) zstd.ZSTD_freeDCtx(dctx);
  }
}

String _errorName(ZstandardNativeBindings zstd, int code) {
  try {
    return zstd.ZSTD_getErrorName(code).cast<Utf8>().toDartString();
  } catch (_) {
    return 'code $code';
  }
}
