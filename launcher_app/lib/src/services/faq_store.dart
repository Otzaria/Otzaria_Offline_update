import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart'
    show writeStringAtomically;
import 'package:path/path.dart' as p;

import '../settings/faq_customization.dart';
import 'app_paths.dart';
import 'faq_drive_identity.dart';

class FaqStore {
  FaqStore({required String stateDir, String? readOnlyDriveDir})
      : _local = File(p.join(stateDir, _fileName)),
        _readOnlyDriveDir = readOnlyDriveDir;

  static const _fileName = 'faq_customization.json';
  final File _local;
  final String? _readOnlyDriveDir;
  late final Future<_DriveFaq>? _drive =
      _readOnlyDriveDir == null ? null : _openDrive(_readOnlyDriveDir);

  Future<FaqCustomization?> load() async {
    final drive = await _drive;
    if (drive != null) return drive.value;
    if (!await _local.exists()) return null;
    final json = jsonDecode(await _local.readAsString());
    return json is Map<String, dynamic>
        ? FaqCustomization.fromJson(json)
        : null;
  }

  Future<void> save(FaqCustomization value) async {
    final drive = await _drive;
    if (drive == null) {
      await _write(_local, value.toJson());
      return;
    }
    await _writeDrive(drive.file, drive.sourceSha256, value);
  }

  Future<_DriveFaq> _openDrive(String directory) async {
    final identity = sha256.convert(utf8.encode(faqDriveIdentity(directory)));
    final file = File(
      p.join(_local.parent.path, AppPaths.logsDirName, 'faq', '$identity.json'),
    );
    final cached = await _readCache(file);
    try {
      final bytes = await File(p.join(directory, _fileName)).readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (cached.sourceSha256 == digest) return cached;
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic> || !_validFaq(json)) return cached;
      final value = FaqCustomization.fromJson(json);
      try {
        await _writeDrive(file, digest, value);
      } on FileSystemException {
        // A later local edit can still save this version and its digest together.
      }
      return (file: file, sourceSha256: digest, value: value);
    } on FileSystemException {
      return cached;
    } on FormatException {
      return cached;
    }
  }

  static bool _validFaq(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (json.containsKey('schemaVersion') &&
        (version is! int || version != FaqCustomization.schemaVersion)) {
      return false;
    }

    final hidden = json['hidden'];
    if (json.containsKey('hidden') &&
        (hidden is! List || hidden.any((id) => id is! String))) {
      return false;
    }
    final extras = json['extras'];
    if (json.containsKey('extras') &&
        (extras is! List ||
            extras.any((entry) =>
                entry is! Map ||
                entry['question'] is! String ||
                entry['answer'] is! String))) {
      return false;
    }
    final contact = json['contact'];
    if (json.containsKey('contact') &&
        (contact is! Map ||
            (contact.containsKey('name') && contact['name'] is! String) ||
            (contact.containsKey('phone') && contact['phone'] is! String))) {
      return false;
    }
    return hidden != null || extras != null || contact != null;
  }

  static Future<_DriveFaq> _readCache(File file) async {
    try {
      final json = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (json
          case {
            'sourceSha256': final String? digest,
            'faq': final Map<String, dynamic> faq,
          } when _validFaq(faq)) {
        return (
          file: file,
          sourceSha256: digest,
          value: FaqCustomization.fromJson(faq),
        );
      }
    } on PathNotFoundException {
      // A read error other than absence must not replace local edits.
    } on FormatException {
      // A damaged cache is replaced by the next valid version from the drive.
    }
    return (file: file, sourceSha256: null, value: null);
  }

  static Future<void> _writeDrive(
    File file,
    String? digest,
    FaqCustomization value,
  ) =>
      _write(file, {'sourceSha256': digest, 'faq': value.toJson()});

  static Future<void> _write(File file, Map<String, dynamic> json) async {
    await file.parent.create(recursive: true);
    await writeStringAtomically(
      file.path,
      const JsonEncoder.withIndent('  ').convert(json),
    );
  }
}

typedef _DriveFaq = ({
  File file,
  String? sourceSha256,
  FaqCustomization? value,
});
