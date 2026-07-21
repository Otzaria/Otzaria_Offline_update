import 'dart:convert';

import 'package:test/test.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';

void main() {
  group('DeltaManifest.fromJson', () {
    // manifest אמיתי מתוך patch-v1-v2.db.zst.manifest.json
    const validJson = '''
    {
      "fromVersion": 1,
      "toVersion": 2,
      "fromSchemaVersion": 1,
      "toSchemaVersion": 1,
      "fromContentHash": "35d499985cc1c37fd02904682d4f67a8c915625ef3768c0e856d3f79a4fc96c1",
      "toContentHash": "2be5318d73e4ffa6b32c5d265699e6000cd84f776c304db4a9b192e7d67b3d06",
      "patchFiles": [
        {
          "file": "patch-v1-v2.db.zst",
          "compression": "zstd",
          "sha256": "c4eb8984f9c45d0e61463f7474133b66461f82320039327acfaf7ba288ee0d9b",
          "size": 1040075,
          "uncompressedSha256": "c02ccccd132e2b331e24ee60ca7886c4ee35b122d2b602d3690176e633c8ea05",
          "uncompressedSize": 5726208
        }
      ]
    }
    ''';

    test('מפענח manifest תקין', () {
      final m =
          DeltaManifest.fromJson(jsonDecode(validJson) as Map<String, dynamic>);
      expect(m.fromVersion, 1);
      expect(m.toVersion, 2);
      expect(m.fromSchemaVersion, 1);
      expect(m.toSchemaVersion, 1);
      expect(m.fromContentHash, startsWith('35d49998'));
      expect(m.toContentHash, startsWith('2be5318d'));
      expect(m.patchFiles, hasLength(1));
      expect(m.patchFiles.first.file, 'patch-v1-v2.db.zst');
      expect(m.patchFiles.first.size, 1040075);
      expect(m.totalCompressedSize, 1040075);
    });

    test('סלחני לשדות לא מוכרים', () {
      final json = jsonDecode(validJson) as Map<String, dynamic>;
      json['someFutureField'] = {'a': 1};
      json['booksTouched'] = [10, 20, 30];
      final m = DeltaManifest.fromJson(json);
      expect(m.toVersion, 2);
      expect(m.booksTouched, [10, 20, 30]);
    });

    test('זורק כשחסר שדה חובה (fromContentHash)', () {
      final json = jsonDecode(validJson) as Map<String, dynamic>;
      json.remove('fromContentHash');
      expect(() => DeltaManifest.fromJson(json), throwsFormatException);
    });

    test('זורק כשחסר patchFiles', () {
      final json = jsonDecode(validJson) as Map<String, dynamic>;
      json.remove('patchFiles');
      expect(() => DeltaManifest.fromJson(json), throwsFormatException);
    });

    test('זורק כש-patchFiles ריק', () {
      final json = jsonDecode(validJson) as Map<String, dynamic>;
      json['patchFiles'] = [];
      expect(() => DeltaManifest.fromJson(json), throwsFormatException);
    });

    test('זורק על compression שאינו zstd', () {
      final json = jsonDecode(validJson) as Map<String, dynamic>;
      (json['patchFiles'] as List).first['compression'] = 'gzip';
      expect(() => DeltaManifest.fromJson(json), throwsFormatException);
    });
  });
}
