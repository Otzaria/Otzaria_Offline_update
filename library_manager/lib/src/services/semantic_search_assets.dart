import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

typedef SemanticAsset = ({String name, int size, String sha256});

/// מתקין את נתוני החיפוש בנתיבי אוצריא, בלי לשנות את ההסכמה שלה.
class SemanticSearchAssets {
  SemanticSearchAssets({
    http.Client? httpClient,
    ExternalLibrary? nativeLibrary,
  }) : _client = httpClient ?? http.Client(),
       _nativeLibrary = nativeLibrary,
       _ownsClient = httpClient == null;

  final http.Client _client;
  final bool _ownsClient;
  final ExternalLibrary? _nativeLibrary;
  static Future<void>? _nativeInitialization;
  static const manifestFileName = 'semantic.json';
  static const modelFolder = 'meivin-round2-onnx';
  static const modelBaseUrl =
      'https://github.com/Otzaria/otzaria-semantic-search/releases/download/model-meivin-round2-int8-v1';
  static const modelFiles = <SemanticAsset>[
    (
      name: 'seforim-embed-round2-int8.onnx',
      size: 42489219,
      sha256:
          '659226865abd3a1bc833565ae6b2e2f48abdd7136285824a12966d4d3294cbf8',
    ),
    (
      name: 'tokenizer.json',
      size: 2191362,
      sha256:
          '0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9',
    ),
    (
      name: 'model.json',
      size: 656,
      sha256:
          'a27b103ea5dc50be674e6e6696d8f8ea09639ac3808cd1a48dcf2d70a0b47d1c',
    ),
    (
      name: 'LICENSE',
      size: 3992,
      sha256:
          '92267258dabd9077849cc5ab63a5b0b0b3ca9849e1112fd0d13d9691df7e0739',
    ),
  ];
  static const tokenizerZip = (
    name: 'tokenizer.json.zip',
    size: 445252,
    sha256: '07353eea8a9e5036f5a50691424b7818fa7768a3f5220a8daf8505f4b8bd3da0',
  );

  String get _name => AppL10n.strings.libraryDomain.companionSemanticName;
  Never _invalid() => throw FormatException(
    AppL10n.strings.libraryDomain.companionAssetMissingInRelease(_name),
  );

  /// כשל HTTP עם הקוד בהודעה — בלי זה 403 של מגבלת קצב נראה כמו "אין קובץ".
  Never _httpFailure(int status) => throw FormatException(
    '${AppL10n.strings.libraryDomain.companionAssetMissingInRelease(_name)}'
    ' (HTTP $status)',
  );

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static void _cancel(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
  }

  static bool _plain(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(name);

  static bool _sha(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  Uri _url(Object? value, String tag) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.pathSegments.length != 6 ||
        uri.pathSegments.take(5).join('/') !=
            'Otzaria/SeforimLibrary/releases/download/vectors-$tag' ||
        !_plain(uri.pathSegments.last)) {
      _invalid();
    }
    return uri;
  }

  String _publishedManifestSha(Map asset, Object? releaseBody) {
    final name = asset['name'] as String;
    final body = releaseBody is String ? releaseBody.toLowerCase() : '';
    final at = body.indexOf(name.toLowerCase());
    final hashes = RegExp(r'\b[0-9a-f]{64}\b');
    final all = hashes.allMatches(body).map((match) => match.group(0)!).toSet();
    final after = at >= 0
        ? hashes.firstMatch(body.substring(at + name.length))?.group(0)
        : null;
    final notes = after ?? (all.length == 1 ? all.single : null);
    final assetDigest = asset['digest'];
    final digest = assetDigest is String && assetDigest.startsWith('sha256:')
        ? assetDigest.substring(7).toLowerCase()
        : null;
    if ((notes == null && digest == null) ||
        (digest != null && !_sha(digest)) ||
        (notes != null && digest != null && notes != digest)) {
      _invalid();
    }
    return notes ?? digest!;
  }

  /// בודק מטא־נתונים בלבד; גם מניפסט הווקטורים אינו יורד בבדיקה הזאת.
  Future<bool> peekPending({
    required String mirrorDir,
    required String libraryTag,
  }) async {
    final version = int.tryParse(
      RegExp(r'^v(\d+)-[A-Za-z0-9._+-]+$').firstMatch(libraryTag)?.group(1) ??
          '',
    );
    if (version == null) {
      _invalid();
    }
    final response = await _client
        .get(
          Uri.parse(
            'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/tags/vectors-$libraryTag',
          ),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'otzaria-offline-update',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return false;
    if (response.statusCode != 200) {
      _invalid();
    }
    final Object? release;
    try {
      release = jsonDecode(response.body);
    } on FormatException {
      _invalid();
    }
    if (release is! Map ||
        release['tag_name'] != 'vectors-$libraryTag' ||
        release['assets'] is! List) {
      _invalid();
    }
    final manifests = <Map>[];
    final assets = <String, Map>{};
    for (final asset in release['assets'] as List) {
      if (asset is! Map ||
          asset['name'] is! String ||
          !_plain(asset['name'] as String) ||
          asset['size'] is! int ||
          (asset['size'] as int) < 0 ||
          assets.containsKey(asset['name'])) {
        _invalid();
      }
      final name = asset['name'] as String;
      assets[name] = asset;
      if (name.startsWith('otzaria-vectors-') &&
          name.endsWith('.manifest.json')) {
        manifests.add(asset);
      }
    }
    if (manifests.length != 1) {
      _invalid();
    }
    final remote = manifests.single;
    final digest = _publishedManifestSha(remote, release['body']);
    final local = await _load(mirrorDir, version);
    if (local == null ||
        local.metadata['libraryTag'] != libraryTag ||
        local.metadata['manifestName'] != remote['name'] ||
        local.metadata['manifestSize'] != remote['size'] ||
        local.metadata['manifestSha256'] != digest) {
      return true;
    }
    for (final file in local.files) {
      final asset = assets[file.name];
      if (asset == null || asset['size'] != file.size) {
        _invalid();
      }
      final published = asset['digest'];
      if (published is String &&
          published.startsWith('sha256:') &&
          published.substring(7).toLowerCase() != file.sha256) {
        _invalid();
      }
    }
    return false;
  }

  Future<void> sync({
    required String mirrorDir,
    required String libraryTag,
    void Function(String)? onStage,
    void Function(int, int?)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    _cancel(isCancelled);
    final version = int.tryParse(
      RegExp(r'^v(\d+)-[A-Za-z0-9._+-]+$').firstMatch(libraryTag)?.group(1) ??
          '',
    );
    if (version == null) {
      _invalid();
    }
    onStage?.call(AppL10n.strings.libraryDomain.semanticDownloading);
    final response = await _client
        .get(
          Uri.parse(
            'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/tags/vectors-$libraryTag',
          ),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'otzaria-offline-update',
          },
        )
        .timeout(const Duration(seconds: 30));
    _cancel(isCancelled);
    if (response.statusCode != 200) {
      _httpFailure(response.statusCode);
    }
    final release = jsonDecode(response.body);
    if (release is! Map ||
        release['tag_name'] != 'vectors-$libraryTag' ||
        release['assets'] is! List) {
      _invalid();
    }
    final assets = <String, Map>{};
    for (final asset in release['assets'] as List) {
      if (asset is Map && asset['name'] is String) {
        assets[asset['name'] as String] = asset;
      }
    }
    final manifests = assets.keys.where(
      (name) =>
          name.startsWith('otzaria-vectors-') &&
          name.endsWith('.manifest.json'),
    );
    if (manifests.length != 1) {
      _invalid();
    }
    final manifestName = manifests.single;
    final manifestAsset = assets[manifestName]!;
    final manifestResponse = await _client
        .get(
          _url(manifestAsset['browser_download_url'], libraryTag),
          headers: const {'User-Agent': 'otzaria-offline-update'},
        )
        .timeout(const Duration(seconds: 30));
    _cancel(isCancelled);
    if (manifestResponse.statusCode != 200) {
      _httpFailure(manifestResponse.statusCode);
    }
    final manifestBytes = manifestResponse.bodyBytes;
    if (manifestAsset['size'] != manifestBytes.length) {
      _invalid();
    }
    final digest = Sha256Stream.ofBytes(manifestBytes);
    if (_publishedManifestSha(manifestAsset, release['body']) != digest) {
      _invalid();
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    final files = _vectors(manifest, libraryTag, version);
    final vectorUrls = <String, String>{};
    for (final file in files) {
      final asset = assets[file.name];
      if (asset == null || asset['size'] != file.size) {
        _invalid();
      }
      final publishedSha = asset['digest'];
      if (publishedSha is String &&
          publishedSha.startsWith('sha256:') &&
          publishedSha.substring(7).toLowerCase() != file.sha256) {
        _invalid();
      }
      vectorUrls[file.name] = _url(
        asset['browser_download_url'],
        libraryTag,
      ).toString();
    }
    final metadata = <String, Object?>{
      'libraryTag': libraryTag,
      'libraryVersion': version,
      'manifestName': manifestName,
      'manifestSize': manifestBytes.length,
      'manifestSha256': digest,
    };
    final generation = p.join(mirrorDir, libraryTag);
    // קובץ מודל זהה מדור קודם מועתק במקום להוריד שוב (~43MB בכל גרסה).
    final reused = <String, String>{};
    for (final file in modelFiles) {
      final source = await reusableModelSource(
        mirrorDir: mirrorDir,
        libraryTag: libraryTag,
        file: file,
        isCancelled: isCancelled,
      );
      if (source != null) reused[file.name] = source;
    }
    final downloadModels = [
      for (final file in modelFiles)
        if (!reused.containsKey(file.name))
          file.name == 'tokenizer.json' ? tokenizerZip : file,
    ];
    final progress = ByteProgressAggregator(
      totalBytes: [
        ...downloadModels,
        ...files,
      ].fold<int>(0, (sum, file) => sum + file.size),
      onProgress: onBytesProgress,
    );
    progress.announce();
    final downloader = PatchDownloader(
      httpClient: _client,
      decompress: (_) async => null,
    );
    try {
      _cancel(isCancelled);
      await Directory(p.join(generation, modelFolder)).create(recursive: true);
      await Directory(p.join(generation, 'vectors')).create(recursive: true);
      for (final entry in reused.entries) {
        final target = p.join(generation, modelFolder, entry.key);
        if (p.equals(entry.value, target)) continue;
        _cancel(isCancelled);
        final temporary = '$target.tmp';
        await File(entry.value).copy(temporary);
        await File(temporary).rename(target);
      }
      for (final file in downloadModels) {
        final slot = progress.slot();
        _cancel(isCancelled);
        await downloader.downloadToFile(
          url: '$modelBaseUrl/${file.name}',
          destPath: p.join(generation, modelFolder, file.name),
          expectedSize: file.size,
          expectedSha256: file.sha256,
          resumeToken: file.sha256,
          onProgress: slot.report,
          onExistingBytes: slot.markExisting,
          isCancelled: isCancelled,
        );
        if (file.name == tokenizerZip.name) {
          _cancel(isCancelled);
          final zipped = ZipDecoder().decodeBytes(
            await File(
              p.join(generation, modelFolder, file.name),
            ).readAsBytes(),
          );
          if (zipped.files.length != 1 ||
              zipped.files.single.name != 'tokenizer.json' ||
              !zipped.files.single.isFile ||
              zipped.files.single.size != modelFiles[1].size) {
            _invalid();
          }
          final bytes = zipped.files.single.content;
          if (Sha256Stream.ofBytes(bytes) != modelFiles[1].sha256) {
            _invalid();
          }
          final target = File(
            p.join(generation, modelFolder, 'tokenizer.json'),
          );
          final temporary = File('${target.path}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          _cancel(isCancelled);
          await temporary.rename(target.path);
        }
      }
      for (final file in files) {
        final slot = progress.slot();
        await downloader.downloadToFile(
          url: vectorUrls[file.name]!,
          destPath: p.join(generation, 'vectors', file.name),
          expectedSize: file.size,
          expectedSha256: file.sha256,
          resumeToken: file.sha256,
          onProgress: slot.report,
          onExistingBytes: slot.markExisting,
          isCancelled: isCancelled,
        );
      }
      _cancel(isCancelled);
      await File(
        p.join(generation, 'vectors', manifestName),
      ).writeAsBytes(manifestBytes, flush: true);
      final metadataFile = File(p.join(mirrorDir, '$manifestFileName.tmp'));
      await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
      _cancel(isCancelled);
      await metadataFile.rename(p.join(mirrorDir, manifestFileName));
      await pruneOldGenerations(mirrorDir, libraryTag);
    } finally {
      downloader.dispose();
    }
  }

  static final _generationName = RegExp(r'^v\d+-[A-Za-z0-9._+-]+$');

  /// קובץ מודל תקין (גודל+sha) בדור הנוכחי או בדור קודם, או `null`. פומבי לטסטים.
  Future<String?> reusableModelSource({
    required String mirrorDir,
    required String libraryTag,
    required SemanticAsset file,
    bool Function()? isCancelled,
  }) async {
    final root = Directory(mirrorDir);
    if (!await root.exists()) return null;
    final names = <String>[libraryTag];
    await for (final entry in root.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is Directory &&
          name != libraryTag &&
          _generationName.hasMatch(name)) {
        names.add(name);
      }
    }
    for (final name in names) {
      final path = p.join(mirrorDir, name, modelFolder, file.name);
      if (await _matches(path, file, isCancelled)) return path;
    }
    return null;
  }

  /// מוחק דורות ישנים אחרי sync מוצלח; כשל מחיקה (כונן לקריאה בלבד) אינו כשל.
  /// פומבי לטסטים.
  Future<void> pruneOldGenerations(String mirrorDir, String keepTag) async {
    try {
      await for (final entry in Directory(mirrorDir).list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (entry is! Directory ||
            name == keepTag ||
            !_generationName.hasMatch(name)) {
          continue;
        }
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return;
    }
  }

  List<SemanticAsset> _vectors(Object? manifest, String tag, int version) {
    if (manifest is! Map ||
        manifest['kind'] != 'base' ||
        manifest['toLibraryVersion'] != version ||
        manifest['libraryReleaseTag'] != tag ||
        manifest['files'] is! List ||
        manifest['segment'] is! Map ||
        (manifest['segment'] as Map)['size'] is! int) {
      _invalid();
    }
    final files = <SemanticAsset>[];
    for (final entry in manifest['files'] as List) {
      if (entry is! Map ||
          entry['file'] is! String ||
          entry['size'] is! int ||
          entry['sha256'] is! String) {
        _invalid();
      }
      final name = entry['file'] as String;
      final size = entry['size'] as int;
      final sha = (entry['sha256'] as String).toLowerCase();
      if (!_plain(name) ||
          size < 0 ||
          !_sha(sha) ||
          files.any((f) => f.name == name)) {
        _invalid();
      }
      files.add((name: name, size: size, sha256: sha));
    }
    if (files.isEmpty) {
      _invalid();
    }
    final identity = manifest['identity'];
    final model = identity is Map ? identity['model'] : null;
    if (model is! Map ||
        model['family_id'] !=
            'ArieLLL123/judaic-semantic-round2-onnx-zayit@1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca' ||
        model['tokenizer_checksum'] != modelFiles[1].sha256) {
      _invalid();
    }
    return files;
  }

  Future<Map<String, dynamic>?> _metadata(String mirrorDir) async {
    try {
      final value = jsonDecode(
        await File(p.join(mirrorDir, manifestFileName)).readAsString(),
      );
      if (value is! Map<String, dynamic> ||
          value['libraryTag'] is! String ||
          !_plain(value['libraryTag'] as String) ||
          value['libraryVersion'] is! int ||
          value['manifestName'] is! String ||
          !_plain(value['manifestName'] as String) ||
          value['manifestSize'] is! int ||
          value['manifestSha256'] is! String ||
          !_sha(value['manifestSha256'] as String)) {
        return null;
      }
      if (int.tryParse(
            RegExp(
                  r'^v(\d+)-',
                ).firstMatch(value['libraryTag'] as String)?.group(1) ??
                '',
          ) !=
          value['libraryVersion']) {
        return null;
      }
      return value;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<int?> mirroredVersion(String mirrorDir) async =>
      (await _metadata(mirrorDir))?['libraryVersion'] as int?;

  Future<bool> _matches(
    String path,
    SemanticAsset file, [
    bool Function()? isCancelled,
  ]) async {
    _cancel(isCancelled);
    final source = File(path);
    if (!await source.exists() || await source.length() != file.size) {
      return false;
    }
    final hash = Sha256Stream();
    try {
      await for (final chunk in source.openRead()) {
        _cancel(isCancelled);
        hash.add(chunk);
      }
      return hash.close() == file.sha256;
    } finally {
      hash.dispose();
    }
  }

  Future<({Map<String, dynamic> metadata, List<SemanticAsset> files})?> _load(
    String mirrorDir,
    int version,
  ) async {
    final meta = await _metadata(mirrorDir);
    if (meta == null || meta['libraryVersion'] != version) return null;
    final tag = meta['libraryTag'] as String;
    final manifestFile = (
      name: meta['manifestName'] as String,
      size: meta['manifestSize'] as int,
      sha256: meta['manifestSha256'] as String,
    );
    final path = p.join(mirrorDir, tag, 'vectors', manifestFile.name);
    if (!await _matches(path, manifestFile)) return null;
    try {
      final files = _vectors(
        jsonDecode(await File(path).readAsString()),
        tag,
        version,
      );
      for (final group in [(modelFolder, modelFiles), ('vectors', files)]) {
        for (final file in group.$2) {
          final source = File(p.join(mirrorDir, tag, group.$1, file.name));
          if (!await source.exists() || await source.length() != file.size) {
            return null;
          }
        }
      }
      return (metadata: meta, files: [...files, manifestFile]);
    } on FormatException {
      return null;
    }
  }

  Future<bool> pending({
    required String mirrorDir,
    required String dbPath,
    required int libraryVersion,
    String? vectorsRootPath,
    bool preferencesReady = true,
  }) async {
    final data = await _load(mirrorDir, libraryVersion);
    if (data == null) return false;
    if (!preferencesReady) return true;
    final root = vectorsRootPath ?? p.dirname(p.dirname(dbPath));
    final active = await _activeMatches(p.join(root, 'vectors'), data.metadata);
    for (final file in modelFiles) {
      if (!await _matches(
        p.join(p.dirname(dbPath), modelFolder, file.name),
        file,
      )) {
        return true;
      }
    }
    return !active;
  }

  /// מצביע הדור והמניפסט תואמים למבנה segment_set של מנוע אוצריא.
  Future<bool> _activeMatches(String vectors, Map<String, dynamic> meta) async {
    for (final pointerName in const ['CURRENT', 'PREVIOUS']) {
      try {
        final pointer = jsonDecode(
          await File(p.join(vectors, pointerName)).readAsString(),
        );
        if (pointer is! Map ||
            pointer['set'] is! String ||
            pointer['set_sha256'] is! String ||
            pointer['generation'] is! int ||
            !RegExp(
              r'^gen-[0-9]+/set\.json$',
            ).hasMatch(pointer['set'] as String)) {
          continue;
        }
        final bytes = await File(
          p.join(vectors, pointer['set'] as String),
        ).readAsBytes();
        if (Sha256Stream.ofBytes(bytes) != pointer['set_sha256']) continue;
        final set = jsonDecode(utf8.decode(bytes));
        if (set is! Map ||
            set['format'] != 'otzaria-vector-set' ||
            set['format_version'] != 1 ||
            set['generation'] != pointer['generation'] ||
            set['library_version'] != meta['libraryVersion'] ||
            set['library_release_tag'] != meta['libraryTag'] ||
            set['segments'] is! List ||
            (set['segments'] as List).isEmpty) {
          continue;
        }
        var complete = true;
        for (final segment in set['segments'] as List) {
          if (segment is! Map ||
              segment['file'] is! String ||
              !RegExp(
                r'^segments/[0-9a-f]{32}\.oxv$',
              ).hasMatch(segment['file'] as String) ||
              segment['size'] is! int) {
            complete = false;
            break;
          }
          final file = File(p.join(vectors, segment['file'] as String));
          if (!await file.exists() || await file.length() != segment['size']) {
            complete = false;
            break;
          }
        }
        if (complete) {
          return true;
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return false;
  }

  Future<void> _ensureOwnedDirectory(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      var owned = false;
      for (final marker in const ['.otzaria-semantic', 'CURRENT', 'PREVIOUS']) {
        if (await File(p.join(path, marker)).exists()) owned = true;
      }
      if (!owned && !await directory.list().isEmpty) {
        throw FileSystemException(
          AppL10n.strings.libraryDomain.companionsInstallFailed(_name),
          path,
        );
      }
    }
    await directory.create(recursive: true);
    await File(p.join(path, '.otzaria-semantic')).writeAsString('');
  }

  Future<void> install({
    required String mirrorDir,
    required String dbPath,
    required int libraryVersion,
    String? vectorsRootPath,
    Future<void> Function()? beforeActivate,
    void Function(String)? onStage,
    bool Function()? isCancelled,
  }) async {
    _cancel(isCancelled);
    final data = await _load(mirrorDir, libraryVersion);
    if (data == null) {
      _invalid();
    }
    onStage?.call(AppL10n.strings.libraryDomain.semanticInstalling);
    final root = vectorsRootPath ?? p.dirname(p.dirname(dbPath));
    final generation = p.join(mirrorDir, data.metadata['libraryTag'] as String);
    // כל המקורות מאומתים לפני ששינוי כלשהו נוגע להתקנה הפעילה.
    for (final group in [(modelFolder, modelFiles), ('vectors', data.files)]) {
      for (final file in group.$2) {
        _cancel(isCancelled);
        final source = p.join(generation, group.$1, file.name);
        if (!await _matches(source, file, isCancelled)) {
          _invalid();
        }
      }
    }
    await beforeActivate?.call();
    final modelDirectory = p.join(p.dirname(dbPath), modelFolder);
    await _ensureOwnedDirectory(modelDirectory);
    await _ensureOwnedDirectory(p.join(root, 'vectors'));
    for (final file in modelFiles) {
      _cancel(isCancelled);
      final source = p.join(generation, modelFolder, file.name);
      final target = p.join(p.dirname(dbPath), modelFolder, file.name);
      if (await _matches(target, file, isCancelled)) continue;
      await Directory(p.dirname(target)).create(recursive: true);
      final temporary = '$target.tmp';
      await File(source).copy(temporary);
      _cancel(isCancelled);
      if (!await _matches(temporary, file, isCancelled)) {
        _invalid();
      }
      await File(temporary).rename(target);
    }
    _cancel(isCancelled);
    await File(
      p.join(p.dirname(dbPath), modelFolder, '.otzaria-semantic'),
    ).writeAsString('');
    final manifestJson = await File(
      p.join(generation, 'vectors', data.metadata['manifestName'] as String),
    ).readAsString();
    final parts = data.files
        .where((file) => file.name != data.metadata['manifestName'])
        .toList();
    final work = await Directory.systemTemp.createTemp(
      'otzaria-semantic-install-',
    );
    SearchEngine? engine;
    SemanticCancellationToken? cancellation;
    Timer? poll;
    try {
      var segmentPath = p.join(generation, 'vectors', parts.first.name);
      if (parts.length > 1) {
        final name = parts.first.name.replaceFirst(RegExp(r'\.part-\d+$'), '');
        segmentPath = p.join(work.path, name);
        final sink = File(segmentPath).openWrite();
        try {
          for (final part in parts) {
            await for (final chunk in File(
              p.join(generation, 'vectors', part.name),
            ).openRead()) {
              _cancel(isCancelled);
              sink.add(chunk);
              await sink.flush();
            }
          }
        } finally {
          await sink.close();
        }
      }
      await (_nativeInitialization ??= RustLib.init(
        externalLibrary: _nativeLibrary,
      ));
      _cancel(isCancelled);
      final index = await Directory(p.join(work.path, 'index')).create();
      engine = await SearchEngine.newInstance(path: index.path);
      cancellation = SemanticCancellationToken();
      final token = cancellation;
      poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (isCancelled?.call() ?? false) token.cancel();
      });
      await beforeActivate?.call();
      _cancel(isCancelled);
      await engine.installSemanticVectors(
        input: SemanticVectorsInstallInput(
          vectorsDir: p.join(root, 'vectors'),
          segmentPath: segmentPath,
          manifestJson: manifestJson,
          publishedManifestSha256: data.metadata['manifestSha256'] as String,
          modelIdentityJson: await File(
            p.join(p.dirname(dbPath), modelFolder, 'model.json'),
          ).readAsString(),
        ),
        cancellation: token,
      );
    } on SemanticError catch (error) {
      if (error.kind == SemanticErrorKind.cancelled) {
        throw const PatchDownloadCancelled();
      }
      rethrow;
    } finally {
      poll?.cancel();
      cancellation?.dispose();
      engine?.dispose();
      await work.delete(recursive: true);
    }
  }
}
