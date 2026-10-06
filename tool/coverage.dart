import 'dart:convert';
import 'dart:io';

const packages = <String, bool>{
  '.': true,
  'otzaria_downloads': false,
  'otzaria_l10n': false,
  'otzaria_manager': false,
  'plugins_manager': false,
  'custom_apps_manager': false,
  'error_reports_manager': false,
  'library_manager': true,
  'launcher_app': true,
};

// מיזוג לפי שורה מונע ספירה כפולה של אותו קובץ בכמה דוחות.
Map<String, Map<int, int>> parseLcov(String text, Directory package) {
  final files = <String, Map<int, int>>{};
  Map<int, int>? current;
  for (final line in const LineSplitter().convert(text)) {
    if (line.startsWith('SF:')) {
      final source = line.substring(3).replaceAll('\\', '/');
      final uri = Uri.file(source);
      final absolute = uri.hasAbsolutePath
          ? File.fromUri(uri).absolute.path
          : File.fromUri(package.absolute.uri.resolveUri(uri)).path;
      current = files.putIfAbsent(absolute, () => {});
    } else if (line.startsWith('DA:')) {
      if (current == null) throw const FormatException('DA without SF');
      final fields = line.substring(3).split(',');
      final number = int.parse(fields[0]);
      final hits = int.parse(fields[1]);
      if (number < 1 || hits < 0) throw const FormatException('invalid DA');
      final previous = current[number] ?? 0;
      current[number] = hits > previous ? hits : previous;
    } else if (line == 'end_of_record') {
      current = null;
    }
  }
  return files;
}

({int hit, int found, double percent}) summarize(
  Iterable<Map<int, int>> files,
) {
  var found = 0;
  var hit = 0;
  for (final lines in files) {
    found += lines.length;
    hit += lines.values.where((hits) => hits > 0).length;
  }
  return (hit: hit, found: found, percent: found == 0 ? 0 : hit * 100 / found);
}

Future<void> command(
    Directory directory, String executable, List<String> args) async {
  final process = await Process.start(executable, args,
      workingDirectory: directory.path, runInShell: Platform.isWindows);
  final log = File.fromUri(directory.uri.resolve('build/coverage/run.log'));
  await log.parent.create(recursive: true);
  final sink = log.openWrite(mode: FileMode.append);
  try {
    await Future.wait([
      process.stdout.forEach(sink.add),
      process.stderr.forEach(sink.add),
    ]);
  } finally {
    await sink.close();
  }
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln(await log.readAsString());
    throw ProcessException(executable, args, 'see ${log.path}', code);
  }
}

Future<void> collect(Directory directory, bool flutter) async {
  final output = Directory.fromUri(directory.uri.resolve('build/coverage/'));
  if (await output.exists()) await output.delete(recursive: true);
  await output.create(recursive: true);
  await command(directory, flutter ? 'flutter' : 'dart', ['pub', 'get']);
  final inventory =
      File.fromUri(directory.uri.resolve('test/coverage_inventory_test.dart'));
  if (await inventory.exists()) {
    throw StateError('${inventory.path} already exists');
  }
  final libraries = await Directory.fromUri(directory.uri.resolve('lib/'))
      .list(recursive: true)
      .where((entity) => entity is File && entity.path.endsWith('.dart'))
      .cast<File>()
      .toList();
  libraries.sort((a, b) => a.path.compareTo(b.path));
  final pubspec =
      await File.fromUri(directory.uri.resolve('pubspec.yaml')).readAsString();
  final packageName =
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
  final imports = libraries.map((file) {
    final relative =
        file.absolute.uri.path.substring(directory.absolute.uri.path.length);
    return "import 'package:$packageName/${relative.substring(4)}';";
  });
  // טעינה בלבד: קוד שלא נבדק נכלל במכנה באפס פגיעות; אינו מופעל כאן.
  await inventory.writeAsString([
    '// ignore_for_file: unused_import',
    "import 'package:${flutter ? 'flutter_test/flutter_test' : 'test/test'}.dart';",
    ...imports,
    "void main() { test('coverage inventory (instrumentation only)', () {}); }",
    '',
  ].join('\n'));
  try {
    stdout.writeln('בדיקות וכיסוי: ${directory.path}');
    if (flutter) {
      await command(directory, 'flutter', [
        'test',
        '--concurrency=1',
        '--coverage',
        '--coverage-path=build/coverage/lcov.info',
        '--reporter=expanded'
      ]);
    } else {
      await command(directory, 'dart',
          ['test', '--coverage=build/coverage/raw', '--reporter=expanded']);
      await command(directory, 'dart', [
        'pub',
        'global',
        'run',
        'coverage:format_coverage',
        '--lcov',
        '--in=build/coverage/raw',
        '--out=build/coverage/lcov.info',
        '--report-on=lib',
        '--package=.'
      ]);
    }
  } finally {
    await inventory.delete();
  }
}

Future<void> main(List<String> args) async {
  final unknown = args.where((arg) =>
      arg != '--collect' &&
      !arg.startsWith('--min=') &&
      !arg.startsWith('--target='));
  if (unknown.isNotEmpty) {
    stderr.writeln(
        'dart tool/coverage.dart [--collect] [--min=60] [--target=80]');
    exitCode = 64;
    return;
  }
  double option(String name, double fallback) {
    final values = args.where((arg) => arg.startsWith('$name='));
    final value =
        values.isEmpty ? fallback : double.parse(values.single.split('=').last);
    if (!value.isFinite || value < 0 || value > 100) throw ArgumentError(name);
    return value;
  }

  final minimum = option('--min', 60);
  final target = option('--target', 80);
  final root = Directory.current.absolute;
  final rows = <Map<String, Object?>>[];
  final all = <String, Map<int, int>>{};
  var failed = false;
  for (final entry in packages.entries) {
    final directory = entry.key == '.'
        ? root
        : Directory.fromUri(root.uri.resolve('${entry.key}/'));
    if (args.contains('--collect')) await collect(directory, entry.value);
    final report =
        File.fromUri(directory.uri.resolve('build/coverage/lcov.info'));
    if (!await report.exists()) {
      throw StateError('Missing ${report.path}; run with --collect');
    }
    final files = parseLcov(await report.readAsString(), directory);
    final lib = directory.uri.resolve('lib/').toFilePath();
    files.removeWhere((path, _) => !path.startsWith(lib));
    final summary = summarize(files.values);
    failed |= summary.found == 0 || summary.percent < minimum;
    final unreported = <String>[];
    await for (final entity in Directory(lib).list(recursive: true)) {
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !files.containsKey(entity.absolute.path)) {
        unreported.add(entity.absolute.path);
      }
    }
    rows.add({
      'package': entry.key,
      'hit': summary.hit,
      'found': summary.found,
      'percent': summary.percent,
      'filesWithoutMeasurableLines': unreported
    });
    stdout.writeln(
        '${entry.key.padRight(24)} ${summary.percent.toStringAsFixed(2)}% (${summary.hit}/${summary.found})');
    all.addAll(files);
  }
  final total = summarize(all.values);
  final withoutL10n = summarize(all.entries
      .where((entry) => !entry.key
          .startsWith(root.uri.resolve('otzaria_l10n/lib/').toFilePath()))
      .map((entry) => entry.value));
  stdout.writeln(
      'כל הפרויקט: ${total.percent.toStringAsFixed(2)}%; ללא תרגומים: ${withoutL10n.percent.toStringAsFixed(2)}%');
  failed |= total.percent < target;
  final report = File.fromUri(root.uri.resolve('build/coverage/summary.json'));
  await report.parent.create(recursive: true);
  await report.writeAsString(const JsonEncoder.withIndent('  ').convert({
    'packages': rows,
    'total': {'hit': total.hit, 'found': total.found, 'percent': total.percent},
    'withoutL10n': {
      'hit': withoutL10n.hit,
      'found': withoutL10n.found,
      'percent': withoutL10n.percent
    },
    'minimumPerPackage': minimum,
    'targetOverall': target
  }));
  if (failed) {
    stderr.writeln('הכיסוי נמוך מהרף: $minimum% לחבילה, $target% לפרויקט.');
    exitCode = 1;
  }
}
