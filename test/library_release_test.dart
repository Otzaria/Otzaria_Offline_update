import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseAsset.fromJson', () {
    test('מפרסר id/updated_at/digest כשקיימים', () {
      final asset = ReleaseAsset.fromJson(const {
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
      final asset = ReleaseAsset.fromJson(const {
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

    test('שדות חסרים לגמרי → ברירות מחדל ריקות, בלי זריקה', () {
      final asset = ReleaseAsset.fromJson(const {});
      expect(asset.name, '');
      expect(asset.downloadUrl, '');
      expect(asset.size, 0);
    });
  });

  group('זיהוי סוגי assets', () {
    ReleaseAsset named(String name) =>
        ReleaseAsset(name: name, downloadUrl: 'u', size: 1);

    test('isDeltaManifest רק לשם המלא של manifest דלתאי', () {
      expect(named('patch-v1-v2.db.zst.manifest.json').isDeltaManifest, isTrue);
      expect(named('patch-v1-v2.db.zst').isDeltaManifest, isFalse);
      expect(named('seforim.db.zst.manifest.json').isDeltaManifest, isFalse);
      expect(named('patch-v1-v2.manifest.json').isDeltaManifest, isFalse);
    });

    test('isFullDbArchive רק ל-seforim.db.zst בדיוק', () {
      expect(named('seforim.db.zst').isFullDbArchive, isTrue);
      expect(named('seforim.db').isFullDbArchive, isFalse);
      expect(named('old-seforim.db.zst').isFullDbArchive, isFalse);
    });
  });

  group('LibraryRelease.fromJson', () {
    test('מפענח release מלא', () {
      final release = LibraryRelease.fromJson(const {
        'tag_name': 'v15',
        'prerelease': true,
        'draft': false,
        'published_at': '2026-06-27T21:00:00Z',
        'unknown_future_field': 1,
        'assets': [
          {
            'name': 'seforim.db.zst',
            'browser_download_url': 'https://x/seforim.db.zst',
            'size': 5,
          },
          {
            'name': 'patch-v14-v15.db.zst.manifest.json',
            'browser_download_url': 'https://x/m.json',
            'size': 6,
          },
        ],
      });
      expect(release.tag, 'v15');
      expect(release.isPrerelease, isTrue);
      expect(release.isDraft, isFalse);
      expect(release.publishedAt, DateTime.utc(2026, 6, 27, 21));
      expect(release.assets, hasLength(2));
      expect(release.deltaManifestAssets.map((a) => a.name),
          ['patch-v14-v15.db.zst.manifest.json']);
      expect(release.fullDbAsset?.name, 'seforim.db.zst');
      expect(release.assetByName('seforim.db.zst')?.size, 5);
      expect(release.assetByName('nope'), isNull);
    });

    test('שדות חסרים → ברירות מחדל שקטות', () {
      final release = LibraryRelease.fromJson(const {});
      expect(release.tag, '');
      expect(release.isPrerelease, isFalse);
      expect(release.isDraft, isFalse);
      expect(release.publishedAt, isNull);
      expect(release.assets, isEmpty);
      expect(release.fullDbAsset, isNull);
      expect(release.deltaManifestAssets, isEmpty);
    });

    test('published_at לא תקין → null', () {
      final release =
          LibraryRelease.fromJson(const {'published_at': 'לא תאריך'});
      expect(release.publishedAt, isNull);
    });

    test('assets שאינו רשימה → רשימה ריקה', () {
      final release = LibraryRelease.fromJson(const {'assets': 'nope'});
      expect(release.assets, isEmpty);
    });
  });

  // הפורמט המקומי (offline) שונה מזה של GitHub; שבירת הסימטריה בין
  // toMirrorJson ל-fromMirrorJson הופכת מראה קיימת לבלתי-קריאה.
  group('סריאליזציה של המראה המקומית', () {
    test('round-trip שומר על כל השדות', () {
      final release = LibraryRelease(
        tag: 'v15',
        isPrerelease: true,
        isDraft: false,
        publishedAt: DateTime.utc(2026, 6, 27, 21),
        assets: const [
          ReleaseAsset(
            name: 'seforim.db.zst',
            downloadUrl: 'assets/v15/seforim.db.zst',
            size: 5,
            id: 77,
            updatedAt: '2026-06-27T21:00:00Z',
            digest: 'sha256:abc',
          ),
        ],
      );
      final restored = LibraryRelease.fromMirrorJson(release.toMirrorJson());
      expect(restored, release);
    });

    test('שדות null אינם נכתבים כלל', () {
      const asset = ReleaseAsset(name: 'a', downloadUrl: 'u', size: 1);
      final json = asset.toMirrorJson();
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('updatedAt'), isFalse);
      expect(json.containsKey('digest'), isFalse);
      expect(ReleaseAsset.fromMirrorJson(json), asset);
    });

    test('publishedAt חסר → null אחרי round-trip', () {
      const release = LibraryRelease(
        tag: 'v1',
        isPrerelease: false,
        isDraft: false,
        publishedAt: null,
        assets: [],
      );
      final json = release.toMirrorJson();
      expect(json.containsKey('publishedAt'), isFalse);
      expect(LibraryRelease.fromMirrorJson(json).publishedAt, isNull);
    });

    // מפתחות ה-GitHub שונים בכוונה ממפתחות המראה — ערבוב ביניהם נותן ריק.
    test('קריאת JSON של GitHub כאילו הוא של המראה מחזירה ערכים ריקים', () {
      final asset = ReleaseAsset.fromMirrorJson(const {
        'name': 'a',
        'browser_download_url': 'https://x/a',
        'size': 5,
      });
      expect(asset.downloadUrl, '');
    });
  });
}
