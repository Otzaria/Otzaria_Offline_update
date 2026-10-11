import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'atomic_file.dart';

/// מאיזה release הגיע תוכן המסד שעל המחשב הזה, ובאיזו גרסה הוא היה אז.
/// שני השדות יחד — גרסה בלי tag אינה מזהה פרסום-מחדש, ו-tag בלי הגרסה
/// שנרשמה איתו אינו מעיד על המסד שקיים עכשיו.
class AppliedRelease {
  const AppliedRelease({required this.tag, required this.dbVersion});

  final String tag;
  final int dbVersion;
}

class LibraryStateStore {
  const LibraryStateStore(this.stateFilePath, {this.dataDir});

  LibraryStateStore.inDir(String dir) : stateFilePath = p.join(dir, fileName);

  static const String fileName = 'library_state.json';

  final String stateFilePath;
  final String? dataDir;

  static Future<String>? _machineKey;

  static Future<String> currentMachineKey() =>
      _machineKey ??= _resolveMachineKey();

  static String legacyMachineKey() => '${_hostname()}|${_account()}';

  static String _hostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }

  static String _account() {
    final env = Platform.environment;
    return env['USERNAME'] ?? env['USER'] ?? '';
  }

  static Future<String> _resolveMachineKey() async => machineKeyFor(
    machineId: await _readMachineId(),
    hostname: _hostname(),
    account: _account(),
    hostnameIsStable: !Platform.isMacOS,
  );

  static String machineKeyFor({
    required String? machineId,
    required String hostname,
    required String account,
    required bool hostnameIsStable,
  }) {
    if (machineId == null || machineId.trim().isEmpty) {
      return '$hostname|$account';
    }
    final digest = machineIdDigest(
      machineId,
      hostname: hostnameIsStable ? hostname : null,
    );
    return '$digest|$account';
  }

  static String machineIdDigest(String machineId, {String? hostname}) {
    final source = [
      machineId.trim().toLowerCase(),
      if (hostname != null) hostname.trim().toLowerCase(),
    ].join('\n');
    return sha256.convert(utf8.encode(source)).toString().substring(0, 16);
  }

  static final RegExp _digestKeyPattern = RegExp(r'^[0-9a-f]{16}\|');

  static bool isHostnameKey(String key) => !_digestKeyPattern.hasMatch(key);

  static Duration staleAfter(String key) =>
      Duration(days: isHostnameKey(key) ? 180 : 365);

  static final RegExp _machineIdPattern = RegExp(
    r'(?:MachineGuid\s+REG_SZ\s+|"IOPlatformUUID"\s*=\s*")'
    r'([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})',
  );

  static String? parseMachineId(String output) =>
      _machineIdPattern.firstMatch(output)?.group(1);

  static Future<String?> _readMachineId() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
          '/reg:64',
        ]);
        if (result.exitCode != 0) return null;
        return parseMachineId(result.stdout.toString());
      }
      if (Platform.isMacOS) {
        final result = await Process.run('/usr/sbin/ioreg', [
          '-rd1',
          '-c',
          'IOPlatformExpertDevice',
        ]);
        if (result.exitCode != 0) return null;
        return parseMachineId(result.stdout.toString());
      }
      for (final path in ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
        final file = File(path);
        if (!await file.exists()) continue;
        final id = (await file.readAsString()).trim();
        if (id.isNotEmpty) return id;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _readAll({bool forWrite = false}) async {
    final file = File(stateFilePath);
    if (!await file.exists()) return {};
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (forWrite) rethrow;
      return {};
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      json = null;
    }
    if (json is Map<String, dynamic>) return json;
    try {
      await file.rename('$stateFilePath.corrupt');
    } catch (_) {}
    return {};
  }

  Future<void> _writeAll(Map<String, dynamic> json) async {
    await File(stateFilePath).parent.create(recursive: true);
    await writeStringAtomically(stateFilePath, jsonEncode(json));
  }

  static Future<Object?> _ownRecord(Object? all) async {
    if (all is! Map) return null;
    return all[await currentMachineKey()] ?? all[legacyMachineKey()];
  }

  static Future<void> _putOwnRecord(
    Map<String, dynamic> records,
    Object value,
  ) async {
    final key = await currentMachineKey();
    final legacy = legacyMachineKey();
    if (legacy != key) records.remove(legacy);
    records[key] = value;
  }

  Future<String?> loadCustomDbPath() async {
    final json = await _readAll();

    final own = await _ownRecord(json['customDbPaths']);
    if (own is String && own.isNotEmpty) return own;

    final legacy = json['customDbPath'];
    if (legacy is! String || legacy.isEmpty || !p.isAbsolute(legacy)) {
      return null;
    }
    if (isInsideDataDir(legacy)) return null;
    return await Directory(p.dirname(legacy)).exists() ? legacy : null;
  }

  bool isInsideDataDir(String path) {
    final root = dataDir ?? p.dirname(stateFilePath);
    final context = Platform.isWindows ? p.windows : p.posix;
    try {
      return context.equals(root, path) ||
          context.isWithin(root, context.normalize(path));
    } catch (_) {
      return false;
    }
  }

  Future<void> saveCustomDbPath(String dbPath) async {
    final json = await _readAll(forWrite: true);
    final paths = <String, dynamic>{};
    final existing = json['customDbPaths'];
    if (existing is Map) {
      existing.forEach((key, value) {
        if (key is String && value is String) paths[key] = value;
      });
    }
    await _putOwnRecord(paths, dbPath);
    json['customDbPaths'] = paths;
    await _writeAll(json);
  }

  Future<AppliedRelease?> loadAppliedRelease() async {
    final json = await _readAll();
    final own = await _ownRecord(json['appliedReleases']);
    if (own is! Map) return null;
    final tag = own['tag'];
    final version = own['dbVersion'];
    if (tag is! String || tag.isEmpty || version is! int) return null;
    return AppliedRelease(tag: tag, dbVersion: version);
  }

  Future<void> saveAppliedRelease({
    required String tag,
    required int dbVersion,
  }) async {
    final json = await _readAll(forWrite: true);
    final records = <String, dynamic>{};
    final existing = json['appliedReleases'];
    if (existing is Map) {
      existing.forEach((key, value) {
        if (key is String && value is Map) records[key] = value;
      });
    }
    await _putOwnRecord(records, {'tag': tag, 'dbVersion': dbVersion});
    json['appliedReleases'] = records;
    json.remove('appliedReleaseTag');
    await _writeAll(json);
  }

  Future<Map<String, String>> loadDeliveredCompanions() async {
    final json = await _readAll();
    final own = await _ownRecord(json['deliveredCompanions']);
    if (own is! Map) return const {};
    final markers = <String, String>{};
    own.forEach((key, value) {
      if (key is String && value is String) markers[key] = value;
    });
    return markers;
  }

  Future<void> saveDeliveredCompanions(Map<String, String> markers) async {
    if (markers.isEmpty) return;
    final json = await _readAll(forWrite: true);
    final records = <String, dynamic>{};
    final existing = json['deliveredCompanions'];
    if (existing is Map) {
      existing.forEach((key, value) {
        if (key is String && value is Map) records[key] = value;
      });
    }
    final own = <String, dynamic>{};
    final previous = await _ownRecord(records);
    if (previous is Map) {
      previous.forEach((key, value) {
        if (key is String && value is String) own[key] = value;
      });
    }
    own.addAll(markers);
    await _putOwnRecord(records, own);
    json['deliveredCompanions'] = records;
    await _writeAll(json);
  }

  Future<Map<String, int>> loadKnownDbVersions() async =>
      _knownVersions(await _readAll());

  static Map<String, int> _knownVersions(Map<String, dynamic> json) {
    final raw = json['knownDbVersions'];
    if (raw is! Map) return const {};
    final versions = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is int && value > 0) versions[key] = value;
    });
    return versions;
  }

  Future<Map<String, int>> _liveKnownVersions() async {
    final json = await _readAll();
    final versions = _knownVersions(json);
    final seen = _stamps(json, _seenField);
    final clock = _newest(versions.keys.map((key) => seen[key]));
    if (clock == null) return versions;
    return Map.fromEntries(
      versions.entries.where((e) => !_isStale(e.key, seen[e.key], clock)),
    );
  }

  Future<int?> lowestKnownDbVersion() async {
    final live = (await _liveKnownVersions()).values;
    if (live.isEmpty) return null;
    return live.reduce((a, b) => a < b ? a : b);
  }

  static const _seenField = 'knownDbVersionsSeen';
  static const _localTimeField = 'knownDbVersionsLocalTime';
  static const maxClockStep = Duration(days: 30);

  static Map<String, DateTime> _stamps(
    Map<String, dynamic> json,
    String field,
  ) {
    final raw = json[field];
    final stamps = <String, DateTime>{};
    if (raw is! Map) return stamps;
    raw.forEach((key, value) {
      if (key is! String || value is! String) return;
      final parsed = DateTime.tryParse(value);
      if (parsed != null) stamps[key] = parsed.toUtc();
    });
    return stamps;
  }

  static DateTime? _newest(Iterable<DateTime?> stamps) {
    DateTime? newest;
    for (final stamp in stamps) {
      if (stamp != null && (newest == null || stamp.isAfter(newest))) {
        newest = stamp;
      }
    }
    return newest;
  }

  static bool _isStale(String key, DateTime? seen, DateTime clock) =>
      seen != null && clock.difference(seen) > staleAfter(key);

  static DateTime _logicalNow({
    required DateTime? clock,
    required DateTime? ownSeen,
    required DateTime? ownLocalTime,
    required DateTime now,
  }) {
    if (clock == null) return now;
    if (ownSeen == null || ownLocalTime == null) return clock;
    var elapsed = now.difference(ownLocalTime);
    if (elapsed.isNegative) elapsed = Duration.zero;
    if (elapsed > maxClockStep) elapsed = maxClockStep;
    final advanced = ownSeen.add(elapsed);
    return advanced.isAfter(clock) ? advanced : clock;
  }

  Future<bool> hasOwnKnownDbVersion() async =>
      await _ownRecord(await _liveKnownVersions()) != null;

  Future<void> recordOwnDbVersion(int version) async => recordKnownDbVersion(
    await currentMachineKey(),
    version,
    aliases: [legacyMachineKey()],
  );

  Future<void> recordKnownDbVersion(
    String machineKey,
    int version, {
    Iterable<String> aliases = const [],
  }) async {
    final json = await _readAll(forWrite: true);
    final existing = _knownVersions(json);
    final previousSeen = _stamps(json, _seenField);
    final previousLocalTime = _stamps(json, _localTimeField);
    final ownKeys = [machineKey, ...aliases];
    final ownPrevious = ownKeys.firstWhere(
      (key) => previousSeen[key] != null && previousLocalTime[key] != null,
      orElse: () => machineKey,
    );
    final now = DateTime.now().toUtc();
    final logicalNow = _logicalNow(
      clock: _newest(existing.keys.map((key) => previousSeen[key])),
      ownSeen: previousSeen[ownPrevious],
      ownLocalTime: previousLocalTime[ownPrevious],
      now: now,
    );
    final own = ownKeys.toSet();
    final hosts = own.map((key) => key.split('|').first).toSet();
    final versions = <String, dynamic>{};
    final seen = <String, dynamic>{};
    final localTime = <String, dynamic>{};
    existing.forEach((key, value) {
      if (own.contains(key) || _isLegacyPathKey(key, hosts)) return;
      final stamp = previousSeen[key] ?? logicalNow;
      if (_isStale(key, stamp, logicalNow)) return;
      versions[key] = value;
      seen[key] = stamp.toIso8601String();
      final writerTime = previousLocalTime[key];
      if (writerTime != null) localTime[key] = writerTime.toIso8601String();
    });
    versions[machineKey] = version;
    seen[machineKey] = logicalNow.toIso8601String();
    localTime[machineKey] = now.toIso8601String();
    json['knownDbVersions'] = versions;
    json[_seenField] = seen;
    json[_localTimeField] = localTime;
    await _writeAll(json);
  }

  static bool _isLegacyPathKey(String key, Set<String> hosts) {
    final separator = key.indexOf('|');
    if (separator < 0) return false;
    if (!hosts.contains(key.substring(0, separator))) return false;
    final rest = key.substring(separator + 1);
    return rest.contains('/') ||
        rest.contains(r'\') ||
        rest.toLowerCase().endsWith('.db');
  }
}
