import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

String faqDriveIdentity(String directory) {
  final path = p.normalize(p.absolute(directory));
  if (Platform.isWindows) {
    final normalized = path.toLowerCase();
    // SMB does not supply a Windows volume GUID.
    if (normalized.startsWith(r'\\?\unc\') ||
        (normalized.startsWith(r'\\') && !normalized.startsWith(r'\\?\'))) {
      return normalized;
    }
    return _windowsIdentity(path) ?? normalized;
  }
  if (Platform.isMacOS) return _macIdentity(path) ?? path;
  return path;
}

String? _windowsIdentity(String path) => using((arena) {
      final mount = arena<Uint16>(MAX_PATH + 1).cast<Utf16>();
      if (GetVolumePathName(
              path.toNativeUtf16(allocator: arena), mount, MAX_PATH + 1) ==
          0) {
        return null;
      }
      const volumeNameLength = 50;
      final volume = arena<Uint16>(volumeNameLength).cast<Utf16>();
      if (GetVolumeNameForVolumeMountPoint(mount, volume, volumeNameLength) ==
          0) {
        return null;
      }
      final root = mount.toDartString().toLowerCase();
      return _onVolume(
          volume.toDartString().toLowerCase(), root, path.toLowerCase());
    });

String? _macIdentity(String path) => using((arena) {
      const attrVolInfo = 0x80000000;
      const attrVolUuid = 0x00040000;
      const attrVolMountPoint = 0x00001000;
      final attrs = arena<_MacAttrList>();
      attrs.ref
        ..bitmapCount = 5
        ..volume = attrVolInfo | attrVolUuid | attrVolMountPoint;

      const resultCapacity = 4096;
      final result = arena<Uint8>(resultCapacity);
      if (_getattrlist(path.toNativeUtf8(allocator: arena), attrs, result,
              resultCapacity, 0) !=
          0) {
        return null;
      }

      // The mount path reference is relative to itself, before the UUID.
      final fields = result.cast<_MacVolumeAttrs>().ref;
      final offset = 4 + fields.mountOffset;
      final length = fields.mountLength;
      if (offset < sizeOf<_MacVolumeAttrs>() ||
          length < 2 ||
          offset + length > fields.length ||
          fields.length > resultCapacity) {
        return null;
      }
      final uuid = [for (var i = 0; i < 16; i++) fields.uuid[i]];
      if (uuid.every((byte) => byte == 0)) return null;
      final root = utf8.decode(
        (result + offset).asTypedList(length - 1),
        allowMalformed: true,
      );
      final id =
          uuid.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      return _onVolume(id, root, path);
    });

String? _onVolume(String id, String root, String path) {
  if (!p.equals(root, path) && !p.isWithin(root, path)) return null;
  return 'volume:$id/${p.relative(path, from: root)}';
}

final _getattrlist = DynamicLibrary.process().lookupFunction<
    Int32 Function(Pointer<Utf8>, Pointer<_MacAttrList>, Pointer<Uint8>, Size,
        UnsignedLong),
    int Function(Pointer<Utf8>, Pointer<_MacAttrList>, Pointer<Uint8>, int,
        int)>('getattrlist');

final class _MacAttrList extends Struct {
  @Uint16()
  external int bitmapCount;

  @Uint16()
  external int reserved;

  @Uint32()
  external int common;

  @Uint32()
  external int volume;

  @Uint32()
  external int directory;

  @Uint32()
  external int file;

  @Uint32()
  external int fork;
}

final class _MacVolumeAttrs extends Struct {
  @Uint32()
  external int length;

  @Int32()
  external int mountOffset;

  @Uint32()
  external int mountLength;

  @Array(16)
  external Array<Uint8> uuid;
}
