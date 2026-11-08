import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'android_models.dart';

class ApkInspector {
  const ApkInspector();

  static const maxManifestBytes = 2 * 1024 * 1024;
  static const maxDirectoryBytes = 16 * 1024 * 1024;

  Future<AndroidApkInfo> inspect(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      if (length < 22) _invalid();
      final tailSize = length < 65557 ? length : 65557;
      final tail = await _read(file, length - tailSize, tailSize);
      final end = _findEnd(tail);
      final records = _u16(tail, end + 10);
      final directorySize = _u32(tail, end + 12);
      final directoryOffset = _u32(tail, end + 16);
      if (_u16(tail, end + 4) != 0 ||
          _u16(tail, end + 6) != 0 ||
          records == 0 ||
          records == 65535 ||
          _u16(tail, end + 8) != records ||
          directorySize > maxDirectoryBytes ||
          directoryOffset + directorySize > length - tailSize + end) {
        _invalid();
      }
      final directory = await _read(file, directoryOffset, directorySize);
      ({int offset, int compressed, int unpacked, int method})? manifest;
      final abis = <String>{};
      var cursor = 0;
      for (var i = 0; i < records; i++) {
        if (cursor + 46 > directory.length ||
            _u32(directory, cursor) != 0x02014b50) {
          _invalid();
        }
        final nameLength = _u16(directory, cursor + 28);
        final extraLength = _u16(directory, cursor + 30);
        final commentLength = _u16(directory, cursor + 32);
        final next = cursor + 46 + nameLength + extraLength + commentLength;
        if (next > directory.length) _invalid();
        final name = utf8.decode(
          directory.sublist(cursor + 46, cursor + 46 + nameLength),
          allowMalformed: true,
        );
        final abi = RegExp(r'^lib/([a-zA-Z0-9_-]+)/libapp\.so$')
            .firstMatch(name)
            ?.group(1);
        if (abi != null) abis.add(abi);
        if (name == 'AndroidManifest.xml') {
          if (manifest != null || _u16(directory, cursor + 8) & 1 != 0) {
            _invalid();
          }
          manifest = (
            offset: _u32(directory, cursor + 42),
            compressed: _u32(directory, cursor + 20),
            unpacked: _u32(directory, cursor + 24),
            method: _u16(directory, cursor + 10),
          );
        }
        cursor = next;
      }
      if (manifest == null ||
          manifest.compressed > maxManifestBytes ||
          manifest.unpacked > maxManifestBytes ||
          manifest.compressed == 0 ||
          manifest.unpacked == 0 ||
          manifest.offset + 30 > directoryOffset) {
        _invalid();
      }
      final local = await _read(file, manifest.offset, 30);
      if (_u32(local, 0) != 0x04034b50 ||
          _u16(local, 6) & 1 != 0 ||
          _u16(local, 8) != manifest.method ||
          _u16(local, 26) != 'AndroidManifest.xml'.length) {
        _invalid();
      }
      final start = manifest.offset + 30 + _u16(local, 26) + _u16(local, 28);
      if (start + manifest.compressed > directoryOffset) _invalid();
      final localName =
          await _read(file, manifest.offset + 30, _u16(local, 26));
      if (utf8.decode(localName) != 'AndroidManifest.xml') _invalid();
      final compressed = await _read(file, start, manifest.compressed);
      final Uint8List xml;
      if (manifest.method == 0) {
        xml = compressed;
      } else if (manifest.method == 8) {
        final output = _BoundedBytes(maxManifestBytes);
        final decoder = ZLibDecoder(raw: true).startChunkedConversion(output);
        for (var offset = 0; offset < compressed.length; offset += 1024) {
          final end = offset + 1024 < compressed.length
              ? offset + 1024
              : compressed.length;
          decoder.add(Uint8List.sublistView(compressed, offset, end));
        }
        decoder.close();
        xml = output.takeBytes();
      } else {
        _invalid();
      }
      if (xml.length != manifest.unpacked) _invalid();
      return _BinaryManifest(xml).read(abis.toList()..sort());
    } on AndroidUpdateException {
      rethrow;
    } on FormatException catch (error) {
      throw AndroidUpdateException(AndroidUpdateFailure.invalidApk, '$error');
    } on RangeError catch (error) {
      throw AndroidUpdateException(AndroidUpdateFailure.invalidApk, '$error');
    } finally {
      await file.close();
    }
  }

  static int _findEnd(Uint8List bytes) {
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (_u32(bytes, i) == 0x06054b50 &&
          i + 22 + _u16(bytes, i + 20) == bytes.length) {
        return i;
      }
    }
    _invalid();
  }

  static Future<Uint8List> _read(
    RandomAccessFile file,
    int offset,
    int size,
  ) async {
    await file.setPosition(offset);
    final bytes = await file.read(size);
    if (bytes.length != size) _invalid();
    return bytes;
  }
}

Never _invalid() =>
    throw const AndroidUpdateException(AndroidUpdateFailure.invalidApk);

int _u16(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint16(offset, Endian.little);
int _u32(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint32(offset, Endian.little);

class _BoundedBytes implements Sink<List<int>> {
  _BoundedBytes(this.limit);
  final int limit;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (_bytes.length + data.length > limit) _invalid();
    _bytes.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}

class _BinaryManifest {
  _BinaryManifest(this.data);
  final Uint8List data;
  List<String> strings = const [];

  AndroidApkInfo read(List<String> abis) {
    if (data.length < 8 || _u16(data, 0) != 3 || _u32(data, 4) != data.length) {
      _invalid();
    }
    final values = <String, dynamic>{'minSdk': 1, 'targetSdk': 1, 'abis': abis};
    var foundManifest = false;
    var foundSdk = false;
    var cursor = _u16(data, 2);
    if (cursor < 8) _invalid();
    while (cursor < data.length) {
      if (cursor + 8 > data.length) _invalid();
      final kind = _u16(data, cursor);
      final headerSize = _u16(data, cursor + 2);
      final size = _u32(data, cursor + 4);
      if (headerSize < 8 || size < headerSize || cursor + size > data.length) {
        _invalid();
      }
      if (kind == 1) {
        if (strings.isNotEmpty) _invalid();
        strings = _stringPool(cursor, headerSize, size);
      } else if (kind == 0x0102) {
        if (headerSize != 16 || size < 36) _invalid();
        final tag = _string(_u32(data, cursor + 20));
        if (tag == 'manifest' || tag == 'uses-sdk') {
          final attrs = _attributes(cursor, size);
          if (tag == 'manifest') {
            if (foundManifest || (attrs['split'] ?? '') != '') _invalid();
            foundManifest = true;
            final code = attrs['android:versionCode'];
            final major = attrs['android:versionCodeMajor'] ?? 0;
            if (code is! int || major is! int || major > 0x7fffffff) _invalid();
            values.addAll({
              'applicationId': attrs['package'],
              'versionCode': (major << 32) | code,
              'versionName': attrs['android:versionName'],
            });
          } else {
            if (foundSdk) _invalid();
            foundSdk = true;
            values['minSdk'] = attrs['android:minSdkVersion'] ?? 1;
            values['targetSdk'] =
                attrs['android:targetSdkVersion'] ?? values['minSdk'];
          }
        }
      }
      cursor += size;
    }
    if (!foundManifest) _invalid();
    return AndroidApkInfo.fromJson(values);
  }

  Map<String, Object?> _attributes(int offset, int size) {
    final start = _u16(data, offset + 24);
    final stride = _u16(data, offset + 26);
    final count = _u16(data, offset + 28);
    if (start < 20 || stride < 20 || 16 + start + count * stride > size) {
      _invalid();
    }
    final attrs = <String, Object?>{};
    for (var i = 0; i < count; i++) {
      final pos = offset + 16 + start + i * stride;
      final namespace = _u32(data, pos);
      final name = _string(_u32(data, pos + 4));
      final ns = namespace == 0xffffffff ? '' : _string(namespace);
      if (ns.isNotEmpty && ns != 'http://schemas.android.com/apk/res/android') {
        continue;
      }
      final key = ns.isEmpty ? name : 'android:$name';
      if (attrs.containsKey(key)) _invalid();
      final raw = _u32(data, pos + 8);
      final type = data[pos + 15];
      final value = _u32(data, pos + 16);
      attrs[key] = switch (type) {
        0x10 || 0x11 => value,
        0x03 => _string(value),
        _ => raw == 0xffffffff ? null : _string(raw),
      };
    }
    return attrs;
  }

  String _string(int index) {
    if (index >= strings.length) _invalid();
    return strings[index];
  }

  List<String> _stringPool(int offset, int header, int size) {
    if (header < 28) _invalid();
    final count = _u32(data, offset + 8);
    final styles = _u32(data, offset + 12);
    final start = _u32(data, offset + 20);
    if (count > 100000 ||
        start < header + (count + styles) * 4 ||
        start > size) {
      _invalid();
    }
    final utf8Pool = _u32(data, offset + 16) & 0x100 != 0;
    final end = offset + size;
    var decodedBytes = 0;
    return List.generate(count, (index) {
      var cursor = offset + start + _u32(data, offset + header + index * 4);
      if (cursor >= end) _invalid();
      int readLength8() {
        if (cursor >= end) _invalid();
        final first = data[cursor++];
        if (first & 0x80 == 0) return first;
        if (cursor >= end) _invalid();
        return ((first & 0x7f) << 8) | data[cursor++];
      }

      int readLength16() {
        if (cursor + 2 > end) _invalid();
        final first = _u16(data, cursor);
        cursor += 2;
        if (first & 0x8000 == 0) return first;
        if (cursor + 2 > end) _invalid();
        final second = _u16(data, cursor);
        cursor += 2;
        return ((first & 0x7fff) << 16) | second;
      }

      if (utf8Pool) {
        readLength8();
        final bytes = readLength8();
        decodedBytes += bytes;
        if (decodedBytes > ApkInspector.maxManifestBytes) _invalid();
        if (cursor + bytes >= end || data[cursor + bytes] != 0) _invalid();
        return utf8.decode(data.sublist(cursor, cursor + bytes));
      }
      final units = readLength16();
      decodedBytes += units * 2;
      if (decodedBytes > ApkInspector.maxManifestBytes) _invalid();
      if (cursor + units * 2 + 2 > end || _u16(data, cursor + units * 2) != 0) {
        _invalid();
      }
      return String.fromCharCodes(
        List.generate(units, (i) => _u16(data, cursor + i * 2)),
      );
    });
  }
}
