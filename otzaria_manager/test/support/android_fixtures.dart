import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria_manager/otzaria_manager.dart';

Uint8List androidApk({
  String applicationId = otzariaAndroidApplicationId,
  int versionCode = 20,
  int minSdk = 24,
  int targetSdk = 36,
  List<String> abis = const ['arm64-v8a'],
  bool compressed = true,
  bool utf8Pool = true,
}) {
  final names = [
    'manifest',
    'uses-sdk',
    'package',
    'versionCode',
    'versionName',
    'minSdkVersion',
    'targetSdkVersion',
    'http://schemas.android.com/apk/res/android',
    applicationId,
    '1.0.0',
  ];
  final strings = _Bytes();
  final offsets = <int>[];
  for (final name in names) {
    offsets.add(strings.length);
    if (utf8Pool) {
      final bytes = utf8.encode(name);
      strings.u8(name.length);
      strings.u8(bytes.length);
      strings.bytes(bytes);
      strings.u8(0);
    } else {
      strings.u16(name.length);
      for (final unit in name.codeUnits) {
        strings.u16(unit);
      }
      strings.u16(0);
    }
  }
  while (strings.length % 4 != 0) {
    strings.u8(0);
  }
  final pool = _Bytes();
  pool.u16(1);
  pool.u16(28);
  pool.u32(28 + offsets.length * 4 + strings.length);
  pool.u32(names.length);
  pool.u32(0);
  pool.u32(utf8Pool ? 0x100 : 0);
  pool.u32(28 + offsets.length * 4);
  pool.u32(0);
  for (final offset in offsets) {
    pool.u32(offset);
  }
  pool.bytes(strings.take());
  final manifest =
      _element(0, [(2, 8, false), (3, versionCode, true), (4, 9, false)]);
  final sdk = _element(1, [(5, minSdk, true), (6, targetSdk, true)]);
  final body = [...pool.take(), ...manifest, ...sdk, ..._end(1), ..._end(0)];
  final xml = _Bytes();
  xml.u16(3);
  xml.u16(8);
  xml.u32(8 + body.length);
  xml.bytes(body);
  return zipEntries({
    'AndroidManifest.xml': xml.take(),
    for (final abi in abis) 'lib/$abi/libapp.so': Uint8List.fromList([1, 2, 3]),
  }, compressed: compressed);
}

Uint8List _element(int name, List<(int, int, bool)> attributes) {
  final b = _Bytes();
  b.u16(0x102);
  b.u16(16);
  b.u32(36 + 20 * attributes.length);
  b.u32(1);
  b.u32(0xffffffff);
  b.u32(0xffffffff);
  b.u32(name);
  b.u16(20);
  b.u16(20);
  b.u16(attributes.length);
  b.u16(0);
  b.u16(0);
  b.u16(0);
  for (final (key, value, integer) in attributes) {
    b.u32(key == 2 ? 0xffffffff : 7);
    b.u32(key);
    b.u32(integer ? 0xffffffff : value);
    b.u16(8);
    b.u8(0);
    b.u8(integer ? 0x10 : 3);
    b.u32(value);
  }
  return b.take();
}

Uint8List _end(int name) {
  final b = _Bytes();
  b.u16(0x103);
  b.u16(16);
  b.u32(24);
  b.u32(1);
  b.u32(0xffffffff);
  b.u32(0xffffffff);
  b.u32(name);
  return b.take();
}

Uint8List zipEntries(Map<String, Uint8List> entries, {bool compressed = true}) {
  final output = _Bytes();
  final directory = _Bytes();
  for (final entry in entries.entries) {
    final name = utf8.encode(entry.key);
    final bytes =
        compressed ? ZLibEncoder(raw: true).convert(entry.value) : entry.value;
    final offset = output.length;
    final method = compressed ? 8 : 0;
    output.u32(0x04034b50);
    output.u16(20);
    output.u16(0);
    output.u16(method);
    output.u16(0);
    output.u16(0);
    output.u32(0);
    output.u32(bytes.length);
    output.u32(entry.value.length);
    output.u16(name.length);
    output.u16(0);
    output.bytes(name);
    output.bytes(bytes);
    directory.u32(0x02014b50);
    directory.u16(20);
    directory.u16(20);
    directory.u16(0);
    directory.u16(method);
    directory.u16(0);
    directory.u16(0);
    directory.u32(0);
    directory.u32(bytes.length);
    directory.u32(entry.value.length);
    directory.u16(name.length);
    directory.u16(0);
    directory.u16(0);
    directory.u16(0);
    directory.u16(0);
    directory.u32(0);
    directory.u32(offset);
    directory.bytes(name);
  }
  final offset = output.length;
  final size = directory.length;
  output.bytes(directory.take());
  output.u32(0x06054b50);
  output.u16(0);
  output.u16(0);
  output.u16(entries.length);
  output.u16(entries.length);
  output.u32(size);
  output.u32(offset);
  output.u16(0);
  return output.take();
}

class _Bytes {
  final BytesBuilder _builder = BytesBuilder();
  int get length => _builder.length;
  void u8(int v) => _builder.addByte(v);
  void u16(int v) => _builder.add([(v & 255), (v >> 8) & 255]);
  void u32(int v) =>
      _builder.add(List.generate(4, (i) => (v >> (8 * i)) & 255));
  void bytes(List<int> v) => _builder.add(v);
  Uint8List take() => _builder.takeBytes();
}

class FakeAndroidRunner implements AndroidCommandRunner {
  final List<List<String>> calls = [];
  int installedVersion = 10;
  int sdk = 36;
  String abi = 'arm64-v8a';
  String? installFailure;
  String devicesOutput =
      'List of devices attached\nfirst device model:Tablet\nsecond device model:Tablet_2\n';

  @override
  Future<AndroidCommandResult> run(String executable, List<String> arguments,
      {required Duration timeout,
      required AndroidCancellation cancellation}) async {
    cancellation.check();
    calls.add([executable, ...arguments]);
    if (arguments.singleOrNull == 'version') {
      return const AndroidCommandResult(
          0, 'Android Debug Bridge version 1.0.41');
    }
    if (executable == '/bin/chmod') return const AndroidCommandResult(0, '');
    if (arguments.first == 'devices') {
      return AndroidCommandResult(0, devicesOutput);
    }
    if (arguments.contains('getprop')) {
      return AndroidCommandResult(0,
          '[ro.build.version.sdk]: [$sdk]\n[ro.product.cpu.abilist]: [$abi]\n');
    }
    if (arguments.contains('get-current-user')) {
      return const AndroidCommandResult(0, '0\n');
    }
    if (arguments.contains('dumpsys')) {
      return AndroidCommandResult(
          0,
          'Packages:\n  Package [org.otzaria.otzaria]:\n'
          '    versionCode=$installedVersion minSdk=24 targetSdk=36\n'
          '    versionName=1.0.0\n    User 0: installed=true hidden=false\n');
    }
    if (arguments.contains('install')) {
      if (installFailure != null) {
        return AndroidCommandResult(1, 'Failure [$installFailure]');
      }
      installedVersion = 20;
      return const AndroidCommandResult(
          0, 'Performing Streamed Install\nSuccess\n');
    }
    throw StateError('Unexpected command: $arguments');
  }
}
