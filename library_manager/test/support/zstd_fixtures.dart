import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:zstandard/zstandard.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';
import 'package:zstandard_platform_interface/zstandard_platform_interface.dart';

ZstandardNativeBindings? nativeZstd() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();
  if (bindings == null) {
    if (Platform.environment['REQUIRE_NATIVE_ZSTD'] == '1') {
      throw StateError(
        'REQUIRE_NATIVE_ZSTD=1 אבל libzstd לא נטענה — הגדירו ZSTD_LIBRARY_PATH',
      );
    }
    return null;
  }
  Zstandard().instance;
  ZstandardPlatform.instance = _BindingsZstandard(bindings);
  return bindings;
}

class _BindingsZstandard extends ZstandardPlatform {
  _BindingsZstandard(this._zstd);

  final ZstandardNativeBindings _zstd;

  @override
  Future<Uint8List?> compress(Uint8List data, int compressionLevel) async =>
      compressWithZstd(_zstd, data);

  @override
  Future<Uint8List?> decompress(Uint8List data) async {
    final srcSize = data.lengthInBytes;
    final src = malloc.allocate<Uint8>(srcSize);
    src.asTypedList(srcSize).setAll(0, data);
    final expected = _zstd.ZSTD_getFrameContentSize(src.cast(), srcSize);
    final dstCapacity = expected > 0 ? expected : srcSize * 20;
    final dst = malloc.allocate<Uint8>(dstCapacity);
    try {
      final size = _zstd.ZSTD_decompress(
        dst.cast(),
        dstCapacity,
        src.cast(),
        srcSize,
      );
      if (size < 0) return null;
      return Uint8List.fromList(dst.asTypedList(size));
    } finally {
      malloc.free(src);
      malloc.free(dst);
    }
  }
}

Uint8List compressWithZstd(ZstandardNativeBindings zstd, Uint8List data) {
  final srcSize = data.lengthInBytes;
  final src = malloc.allocate<Uint8>(srcSize);
  src.asTypedList(srcSize).setAll(0, data);
  final dstCapacity = zstd.ZSTD_compressBound(srcSize);
  final dst = malloc.allocate<Uint8>(dstCapacity);
  try {
    final size = zstd.ZSTD_compress(
      dst.cast<Void>(),
      dstCapacity,
      src.cast<Void>(),
      srcSize,
      3,
    );
    if (size <= 0) throw StateError('הדחיסה עצמה נכשלה (code $size)');
    return Uint8List.fromList(dst.asTypedList(size));
  } finally {
    malloc.free(src);
    malloc.free(dst);
  }
}

Uint8List pseudoRandomBytes(int length) {
  final bytes = Uint8List(length);
  var state = 0x2545F491;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    bytes[i] = ((state >> 16) & 0xFF) & (i % 97 == 0 ? 0xFF : 0x3F);
  }
  return bytes;
}
