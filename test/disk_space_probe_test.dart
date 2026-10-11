import 'dart:io';

import 'package:seforim_library_updater/src/services/disk_space_probe.dart';
import 'package:test/test.dart';

void main() {
  group('isFatFileSystemName', () {
    test('FAT32 בשמות של Windows/macOS/Linux מזוהה', () {
      for (final name in ['FAT32', 'FAT', 'FAT16', 'msdos', 'vfat', ' fat ']) {
        expect(DiskSpaceProbe.isFatFileSystemName(name), isTrue, reason: name);
      }
    });

    test('exFAT, NTFS ו-APFS אינם FAT — אין להם מגבלת 4GB', () {
      for (final name in ['exFAT', 'exfat', 'NTFS', 'apfs', 'ext4', 'hfs']) {
        expect(DiskSpaceProbe.isFatFileSystemName(name), isFalse, reason: name);
      }
    });
  });

  group('fileSystemFromMountTable', () {
    const macOs = '/dev/disk3s1s1 on / (apfs, sealed, local, read-only)\n'
        '/dev/disk4s1 on /Volumes/NO NAME (msdos, local, nodev, nosuid)\n'
        '/dev/disk5s1 on /Volumes/BIG (exfat, local, nodev, nosuid)\n';
    const linux = '/dev/sda2 on / type ext4 (rw,relatime)\n'
        '/dev/sdb1 on /media/u/STICK type vfat (rw,nosuid,nodev)\n';

    test('macOS: הסוג הוא הראשון בסוגריים', () {
      expect(
        DiskSpaceProbe.fileSystemFromMountTable(macOs, '/dev/disk4s1'),
        'msdos',
      );
      expect(
        DiskSpaceProbe.fileSystemFromMountTable(macOs, '/dev/disk5s1'),
        'exfat',
      );
    });

    test('Linux: הסוג הוא מה שאחרי type', () {
      expect(
        DiskSpaceProbe.fileSystemFromMountTable(linux, '/dev/sdb1'),
        'vfat',
      );
      expect(
        DiskSpaceProbe.fileSystemFromMountTable(linux, '/dev/sda2'),
        'ext4',
      );
    });

    test('התקן שאינו בטבלה, או קידומת של התקן אחר → null', () {
      expect(
          DiskSpaceProbe.fileSystemFromMountTable(macOs, '/dev/disk9'), isNull);
      expect(
          DiskSpaceProbe.fileSystemFromMountTable(linux, '/dev/sdb'), isNull);
    });
  });

  test('isKnownFat על תיקיית temp רגילה אינו זורק ואינו מזהה FAT', () {
    final tmp = Directory.systemTemp.createTempSync('fat_probe_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    expect(DiskSpaceProbe.isKnownFat('${tmp.path}/seforim.db'), isFalse);
  });

  test('המגבלה היא 4GiB פחות בית', () {
    expect(DiskSpaceProbe.fatMaxFileBytes, (1 << 32) - 1);
  });
}
