import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/coverage.dart' as coverage;

void main() {
  final directory = Directory.systemTemp;

  test('coverage merges repeated records without double-counting lines', () {
    final parsed = coverage.parseLcov(
        'SF:lib/example.dart\nDA:1,0\nDA:2,3\nend_of_record\nSF:lib/example.dart\nDA:1,2\nDA:2,0\nDA:3,0\nend_of_record\n',
        directory);
    expect(parsed, hasLength(1));
    expect(parsed.values.single, {1: 2, 2: 3, 3: 0});
    expect(coverage.summarize(parsed.values),
        (hit: 2, found: 3, percent: 200 / 3));
  });

  test('coverage uses measurable lines rather than trusting LF and LH headers',
      () {
    final parsed = coverage.parseLcov(
        'SF:lib/example.dart\nDA:7,0\nDA:9,1\nLF:1\nLH:1\nend_of_record\n',
        directory);
    expect(
        coverage.summarize(parsed.values), (hit: 1, found: 2, percent: 50.0));
  });

  test('an empty report does not masquerade as complete coverage', () {
    expect(coverage.summarize([]), (hit: 0, found: 0, percent: 0.0));
  });

  test('absolute and package-relative source paths resolve to the same file',
      () {
    final absolute =
        File.fromUri(directory.uri.resolve('lib/example.dart')).path;
    final parsed = coverage.parseLcov(
        'SF:$absolute\nDA:1,1\nend_of_record\nSF:lib/example.dart\nDA:2,0\nend_of_record\n',
        directory);
    expect(parsed, hasLength(1));
    expect(parsed.values.single, {1: 1, 2: 0});
  });

  for (final record in [
    'DA:1,1',
    'SF:lib/a.dart\nDA:0,1',
    'SF:lib/a.dart\nDA:1,-1',
    'SF:lib/a.dart\nDA:x,1'
  ]) {
    test('invalid coverage data cannot inflate the reported result: $record',
        () {
      expect(
          () => coverage.parseLcov(record, directory), throwsFormatException);
    });
  }

  for (final weakPackage in [false, true]) {
    test(
        'coverage CLI ${weakPackage ? 'rejects a weak package despite a high total' : 'accepts reports meeting both thresholds'}',
        () async {
      final temporary = await Directory.systemTemp.createTemp('coverage-gate-');
      addTearDown(() => temporary.delete(recursive: true));
      for (final package in coverage.packages.keys) {
        final directory = package == '.'
            ? temporary
            : Directory.fromUri(temporary.uri.resolve('$package/'));
        final lib = Directory.fromUri(directory.uri.resolve('lib/'));
        await lib.create(recursive: true);
        final report =
            File.fromUri(directory.uri.resolve('build/coverage/lcov.info'));
        await report.parent.create(recursive: true);
        await report.writeAsString('SF:lib/example.dart\n${[
          for (var line = 1; line <= 10; line++)
            'DA:$line,${weakPackage && package == 'otzaria_downloads' && line > 5 ? 0 : 1}',
        ].join('\n')}\nend_of_record\n');
      }
      final result = await Process.run(
          'dart', [File('tool/coverage.dart').absolute.path],
          workingDirectory: temporary.path, runInShell: Platform.isWindows);
      expect(result.exitCode, weakPackage ? 1 : 0,
          reason: '${result.stdout}\n${result.stderr}');
      expect(
          await File.fromUri(
                  temporary.uri.resolve('build/coverage/summary.json'))
              .exists(),
          isTrue);
      final json = jsonDecode(await File.fromUri(
              temporary.uri.resolve('build/coverage/summary.json'))
          .readAsString()) as Map;
      expect(json['packages'], hasLength(9));
      expect(json['total']['found'], 90);
      expect(json['total']['percent'], greaterThan(80));
      expect(json['minimumPerPackage'], 60);
      expect(json['targetOverall'], 80);
    });
  }
}
