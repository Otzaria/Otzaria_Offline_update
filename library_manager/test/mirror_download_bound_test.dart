import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/mirror_download_bound.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

const _mb = 1 << 20;
const _manifest = 500;

ReleaseAsset _asset(String name, int size) =>
    ReleaseAsset(name: name, downloadUrl: 'https://x/$name', size: size);

LibraryRelease _release(String tag, Map<String, int> assets) => LibraryRelease(
  tag: tag,
  isPrerelease: false,
  isDraft: false,
  publishedAt: null,
  assets: [for (final e in assets.entries) _asset(e.key, e.value)],
);

DeltaManifest _parsed(String name) {
  final m = RegExp(r'patch-v(\d+)-v(\d+)').firstMatch(name)!;
  return DeltaManifest(
    fromVersion: int.parse(m[1]!),
    toVersion: int.parse(m[2]!),
    fromSchemaVersion: kSupportedDbSchemaVersion,
    toSchemaVersion: kSupportedDbSchemaVersion,
    patchFormatVersion: kSupportedPatchFormatVersion,
    fromContentHash: 'a',
    toContentHash: 'b',
    patchFiles: [
      PatchFileEntry(
        file: name.replaceAll('.manifest.json', ''),
        compression: 'zstd',
        sha256: 's',
        size: _mb,
        uncompressedSha256: 'u',
        uncompressedSize: _mb,
      ),
    ],
  );
}

void main() {
  // 1→3 קצר מ-1→2→3, ולכן 1→2 אינו נבחר לאף גרסה מקומית.
  final relevant = [
    _release('v3', {
      'seforim.db.zst': 1000 * _mb,
      'patch-v2-v3.db.zst': _mb,
      'patch-v2-v3.db.zst.manifest.json': _manifest,
      'patch-v1-v3.db.zst': _mb,
      'patch-v1-v3.db.zst.manifest.json': _manifest,
    }),
    _release('v2', {
      'seforim.db.zst': 900 * _mb,
      'patch-v1-v2.db.zst': _mb,
      'patch-v1-v2.db.zst.manifest.json': _manifest,
    }),
  ];

  int? bound({required bool manifestsRead}) => mirrorDownloadBytesBound(
    relevant: relevant,
    supportedDbSchemaVersion: kSupportedDbSchemaVersion,
    applyTime: const ApplyTimeEstimate(),
    complete: (_, _) => false,
    heldManifest: (_, asset) => manifestsRead ? _parsed(asset.name) : null,
  );

  test('with every manifest read, an edge no version picks is not counted', () {
    expect(bound(manifestsRead: true), 1000 * _mb + 2 * _mb + 3 * _manifest);
  });

  test('an unread manifest may be a barrier, so nothing is pruned', () {
    expect(bound(manifestsRead: false), 1000 * _mb + 3 * _mb + 3 * _manifest);
  });

  test('an older full DB on the drive stops the pruning, as in the export', () {
    // v1 has no way up, so the bound still has a number; 0→2 is unpicked.
    final withOlder = [
      _release('v3', {
        'seforim.db.zst': 1000 * _mb,
        'patch-v2-v3.db.zst': _mb,
        'patch-v2-v3.db.zst.manifest.json': _manifest,
        'patch-v0-v3.db.zst': _mb,
        'patch-v0-v3.db.zst.manifest.json': _manifest,
      }),
      _release('v2', {
        'seforim.db.zst': 900 * _mb,
        'patch-v0-v2.db.zst': _mb,
        'patch-v0-v2.db.zst.manifest.json': _manifest,
      }),
      _release('v1', {'seforim.db.zst': 900 * _mb}),
    ];
    int? withDrive(bool olderOnDrive) => mirrorDownloadBytesBound(
      relevant: withOlder,
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      applyTime: const ApplyTimeEstimate(),
      complete: (release, _) => olderOnDrive && release.tag == 'v1',
      heldManifest: (_, asset) => _parsed(asset.name),
    );
    expect(withDrive(false), 1000 * _mb + 2 * _mb + 3 * _manifest);
    expect(withDrive(true), 1000 * _mb + 3 * _mb + 3 * _manifest);
  });

  test('an edge of a release with no full DB is kept, as the export may', () {
    final noFull = [
      relevant.first,
      _release('v2', {
        'patch-v1-v2.db.zst': _mb,
        'patch-v1-v2.db.zst.manifest.json': _manifest,
      }),
    ];
    expect(
      mirrorDownloadBytesBound(
        relevant: noFull,
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        applyTime: const ApplyTimeEstimate(),
        complete: (_, _) => false,
        heldManifest: (_, asset) => _parsed(asset.name),
      ),
      1000 * _mb + 3 * _mb + 3 * _manifest,
    );
  });

  test(
    'a patch file two manifests share stops the pruning, as in the export',
    () {
      DeltaManifest held(String name) {
        final m = _parsed(name);
        if (m.toVersion != 3 || m.fromVersion != 2) return m;
        return DeltaManifest(
          fromVersion: 2,
          toVersion: 3,
          fromSchemaVersion: m.fromSchemaVersion,
          toSchemaVersion: m.toSchemaVersion,
          patchFormatVersion: m.patchFormatVersion,
          fromContentHash: m.fromContentHash,
          toContentHash: m.toContentHash,
          patchFiles: [
            for (final f in m.patchFiles)
              PatchFileEntry(
                file: 'patch-v1-v3.db.zst',
                compression: f.compression,
                sha256: f.sha256,
                size: f.size,
                uncompressedSha256: f.uncompressedSha256,
                uncompressedSize: f.uncompressedSize,
              ),
          ],
        );
      }

      expect(
        mirrorDownloadBytesBound(
          relevant: relevant,
          supportedDbSchemaVersion: kSupportedDbSchemaVersion,
          applyTime: const ApplyTimeEstimate(),
          complete: (_, _) => false,
          heldManifest: (_, asset) => held(asset.name),
        ),
        1000 * _mb + 3 * _mb + 3 * _manifest,
      );
    },
  );
}
