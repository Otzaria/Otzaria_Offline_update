import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseAsset.fromJson', () {
    test('מפרסר id/updated_at/digest כשקיימים', () {
      final asset = ReleaseAsset.fromJson({
        'name': 'seforim.db.zst',
        'browser_download_url': 'https://x/seforim.db.zst',
        'size': 1197000000,
        'id': 123456,
        'updated_at': '2026-07-19T10:00:00Z',
        'digest': 'sha256:abc123',
      });
      expect(asset.name, 'seforim.db.zst');
      expect(asset.downloadUrl, 'https://x/seforim.db.zst');
      expect(asset.size, 1197000000);
      expect(asset.id, 123456);
      expect(asset.updatedAt, '2026-07-19T10:00:00Z');
      expect(asset.digest, 'sha256:abc123');
    });

    test('סובל היעדר של id/updated_at/digest (null)', () {
      final asset = ReleaseAsset.fromJson({
        'name': 'seforim.db.zst',
        'browser_download_url': 'https://x/seforim.db.zst',
        'size': 100,
      });
      expect(asset.id, isNull);
      expect(asset.updatedAt, isNull);
      expect(asset.digest, isNull);
    });

    test('השדות החדשים נכללים ב-props (שוויון)', () {
      const a = ReleaseAsset(
        name: 'a',
        downloadUrl: 'u',
        size: 1,
        id: 1,
        updatedAt: 't',
        digest: 'sha256:x',
      );
      const b = ReleaseAsset(
        name: 'a',
        downloadUrl: 'u',
        size: 1,
        id: 2,
        updatedAt: 't',
        digest: 'sha256:x',
      );
      expect(a, isNot(equals(b)));
    });
  });
}
