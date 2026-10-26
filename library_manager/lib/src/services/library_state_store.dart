import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'atomic_file.dart';
import 'semantic_vectors_plan.dart';

/// מאיזה release הגיע תוכן המסד שעל המחשב הזה, ובאיזו גרסה הוא היה אז.
/// שני השדות יחד — גרסה בלי tag אינה מזהה פרסום-מחדש, ו-tag בלי הגרסה
/// שנרשמה איתו אינו מעיד על המסד שקיים עכשיו.
class AppliedRelease {
  const AppliedRelease({required this.tag, required this.dbVersion});

  final String tag;
  final int dbVersion;
}

/// מחשב שנרשם לעדכון אישי. [name] — שם המחשב לתצוגה; `null` ברשומה ישנה.
class RegisteredMachine {
  const RegisteredMachine({
    required this.key,
    required this.version,
    required this.isThisMachine,
    this.name,
  });

  final String key;
  final String? name;
  final int version;
  final bool isThisMachine;
}

class LibraryStateStore {
  const LibraryStateStore(this.stateFilePath, {this.dataDir});

  LibraryStateStore.inDir(String dir, {this.dataDir})
    : stateFilePath = p.join(dir, fileName);

  static const String fileName = 'library_state.json';

  final String stateFilePath;
  final String? dataDir;

  static Future<String>? _machineKey;
  static final Map<String, Future<void>> _writeTails = {};

  Future<T> _exclusively<T>(Future<T> Function() action) {
    final key = p.normalize(p.absolute(stateFilePath));
    final previous = _writeTails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    final tail = completer.future;
    _writeTails[key] = tail;
    return previous.then((_) => action()).whenComplete(() {
      completer.complete();
      if (identical(_writeTails[key], tail)) _writeTails.remove(key);
    });
  }

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
        return await Isolate.run(readWindowsMachineGuid);
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

  Future<String?> loadCustomDbPath() async =>
      (await loadCustomDbChoice())?.path;

  Future<({String path, bool explicit})?> loadCustomDbChoice() async {
    final json = await _readAll();
    final path = await _loadCustomDbPath(json);
    if (path == null) return null;
    final explicit = await _ownRecord(json['customDbPathsExplicit']);
    return (path: path, explicit: explicit == path);
  }

  Future<String?> _loadCustomDbPath(Map<String, dynamic> json) async {
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

  Future<void> saveCustomDbPath(String dbPath, {bool? explicit}) =>
      _exclusively(() => _saveCustomDbPath(dbPath, explicit));

  Future<void> _saveCustomDbPath(String dbPath, bool? explicit) async {
    final json = await _readAll(forWrite: true);
    final paths = _stringRecords(json['customDbPaths']);
    final explicitPaths = _stringRecords(json['customDbPathsExplicit']);
    final keep =
        explicit == null &&
        await _ownRecord(json['customDbPaths']) == dbPath &&
        await _ownRecord(json['customDbPathsExplicit']) == dbPath;
    await _putOwnRecord(paths, dbPath);
    if (explicit == true || keep) {
      await _putOwnRecord(explicitPaths, dbPath);
    } else {
      explicitPaths
        ..remove(await currentMachineKey())
        ..remove(legacyMachineKey());
    }
    json['customDbPaths'] = paths;
    json['customDbPathsExplicit'] = explicitPaths;
    await _writeAll(json);
  }

  static Map<String, dynamic> _stringRecords(Object? existing) {
    final records = <String, dynamic>{};
    if (existing is Map) {
      existing.forEach((key, value) {
        if (key is String && value is String) records[key] = value;
      });
    }
    return records;
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
  }) => _exclusively(() => _saveAppliedRelease(tag, dbVersion));

  Future<void> _saveAppliedRelease(String tag, int dbVersion) async {
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

  Future<void> saveDeliveredCompanions(Map<String, String> markers) {
    if (markers.isEmpty) return Future<void>.value();
    return _exclusively(() => _saveDeliveredCompanions(markers));
  }

  Future<void> _saveDeliveredCompanions(Map<String, String> markers) async {
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

  /// The smart-search tag a schema-limited download settled on, with what it
  /// was decided from — a fact about the drive, so not per machine.
  Future<Map<String, Object?>?> loadReadableSemanticTarget() async {
    final value = (await _readAll())['readableSemanticTarget'];
    return value is Map ? Map<String, Object?>.from(value) : null;
  }

  Future<void> saveReadableSemanticTarget(Map<String, Object?> target) =>
      _exclusively(() async {
        final json = await _readAll(forWrite: true);
        json['readableSemanticTarget'] = target;
        await _writeAll(json);
      });

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

  /// המחשבים שנרשמו ורשומתם לא פגה, מהגרסה הנמוכה.
  Future<List<RegisteredMachine>> liveRegisteredMachines() async {
    final json = await _readAll();
    final live = await _liveKnownVersions();
    final names = _names(json);
    final own = {await currentMachineKey(), legacyMachineKey()};
    final machines = [
      for (final MapEntry(:key, :value) in live.entries)
        RegisteredMachine(
          key: key,
          version: value,
          name: names[key],
          isThisMachine: own.contains(key),
        ),
    ]..sort((a, b) => a.version.compareTo(b.version));
    return machines;
  }

  /// מוחק רשומה של מחשב אחד, כך שאינו קובע עוד מאיזו גרסה מורידים.
  Future<void> forgetKnownDbVersion(String machineKey) =>
      _exclusively(() async {
        final json = await _readAll(forWrite: true);
        var changed = false;
        for (final field in [
          'knownDbVersions',
          _seenField,
          _localTimeField,
          _namesField,
        ]) {
          final map = json[field];
          if (map is Map && map.remove(machineKey) != null) changed = true;
        }
        if (changed) await _writeAll(json);
      });

  static Map<String, String> _names(Map<String, dynamic> json) {
    final raw = json[_namesField];
    return {
      if (raw is Map)
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && value is String && value.isNotEmpty) key: value,
    };
  }

  static const _seenField = 'knownDbVersionsSeen';
  static const _localTimeField = 'knownDbVersionsLocalTime';
  // מפה נפרדת, כדי שגרסאות ישנות ימשיכו לקרוא את `knownDbVersions` כמספרים.
  static const _namesField = 'knownDbVersionsNames';
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
    name: _hostname(),
  );

  Future<void> recordKnownDbVersion(
    String machineKey,
    int version, {
    Iterable<String> aliases = const [],
    String? name,
  }) => _exclusively(
    () => _recordKnownDbVersion(machineKey, version, aliases, name),
  );

  Future<void> _recordKnownDbVersion(
    String machineKey,
    int version,
    Iterable<String> aliases,
    String? name,
  ) async {
    final json = await _readAll(forWrite: true);
    final existing = _knownVersions(json);
    final previousNames = _names(json);
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
    final names = <String, dynamic>{};
    existing.forEach((key, value) {
      if (own.contains(key) || _isLegacyPathKey(key, hosts)) return;
      final stamp = previousSeen[key] ?? logicalNow;
      if (_isStale(key, stamp, logicalNow)) return;
      versions[key] = value;
      seen[key] = stamp.toIso8601String();
      final writerTime = previousLocalTime[key];
      if (writerTime != null) localTime[key] = writerTime.toIso8601String();
      if (previousNames[key] case final keptName?) names[key] = keptName;
    });
    versions[machineKey] = version;
    seen[machineKey] = logicalNow.toIso8601String();
    localTime[machineKey] = now.toIso8601String();
    final ownName =
        name ?? ownKeys.map((key) => previousNames[key]).nonNulls.firstOrNull;
    if (ownName != null) names[machineKey] = ownName;
    json['knownDbVersions'] = versions;
    json[_seenField] = seen;
    json[_localTimeField] = localTime;
    json[_namesField] = names;
    await _writeAll(json);
  }

  static const _semanticField = 'semanticMachines';

  static Map<String, Map> _semanticRecords(Map<String, dynamic> json) {
    final raw = json[_semanticField];
    final records = <String, Map>{};
    if (raw is! Map) return records;
    raw.forEach((key, value) {
      if (key is String && value is Map) records[key] = value;
    });
    return records;
  }

  static DateTime? _stampOf(Map record, String field) {
    final value = record[field];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  /// The smart-search state of every machine whose record has not expired,
  /// by the same logical clock as [lowestKnownDbVersion].
  Future<List<SemanticMachineState>> liveSemanticStates({
    bool excludeOwn = false,
  }) async {
    final records = _semanticRecords(await _readAll());
    final clock = _newest(records.values.map((r) => _stampOf(r, 'seen')));
    if (excludeOwn) {
      records
        ..remove(await currentMachineKey())
        ..remove(legacyMachineKey());
    }
    return [
      for (final MapEntry(:key, :value) in records.entries)
        if (clock == null || !_isStale(key, _stampOf(value, 'seen'), clock))
          ?SemanticMachineState.fromJson(value),
    ];
  }

  Future<SemanticMachineState?> loadOwnSemanticState() async =>
      SemanticMachineState.fromJson(
        await _ownRecord(_semanticRecords(await _readAll())),
      );

  /// Records this machine's state; `null` removes it, so a machine that
  /// stopped using smart search no longer shapes the download.
  Future<void> recordOwnSemanticState(SemanticMachineState? state) =>
      _exclusively(() => _recordOwnSemanticState(state));

  Future<void> _recordOwnSemanticState(SemanticMachineState? state) async {
    final json = await _readAll(forWrite: true);
    final records = _semanticRecords(json);
    final key = await currentMachineKey();
    final legacy = legacyMachineKey();
    final previous = records[key] ?? records[legacy];
    records
      ..remove(key)
      ..remove(legacy);
    final now = DateTime.now().toUtc();
    final logicalNow = _logicalNow(
      clock: _newest(records.values.map((r) => _stampOf(r, 'seen'))),
      ownSeen: previous == null ? null : _stampOf(previous, 'seen'),
      ownLocalTime: previous == null ? null : _stampOf(previous, 'localTime'),
      now: now,
    );
    records.removeWhere(
      (k, r) => _isStale(k, _stampOf(r, 'seen') ?? logicalNow, logicalNow),
    );
    if (state != null) {
      records[key] = {
        ...state.toJson(),
        'seen': logicalNow.toIso8601String(),
        'localTime': now.toIso8601String(),
      };
    }
    json[_semanticField] = records;
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

/// `MachineGuid` ישר מהרג'יסטרי (תצוגת 64 סיביות), במקום `reg.exe` שעולה
/// כשנייה במחשבים מסוננים.
String? readWindowsMachineGuid() {
  final subKey = r'SOFTWARE\Microsoft\Cryptography'.toNativeUtf16();
  final value = 'MachineGuid'.toNativeUtf16();
  const capacity = 128;
  final data = calloc<Uint16>(capacity);
  final size = calloc<Uint32>()..value = capacity * 2;
  try {
    final status = RegGetValue(
      HKEY_LOCAL_MACHINE,
      subKey,
      value,
      RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
      nullptr,
      data,
      size,
    );
    if (status != ERROR_SUCCESS) return null;
    final id = data.cast<Utf16>().toDartString().trim();
    return id.isEmpty ? null : id;
  } finally {
    free(subKey);
    free(value);
    free(data);
    free(size);
  }
}
