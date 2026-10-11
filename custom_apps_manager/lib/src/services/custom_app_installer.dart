import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';
import '../models/custom_install_outcome.dart';
import '../models/custom_installer_kind.dart';
import 'elevated_process.dart';
import 'installer_kind_sniffer.dart';

typedef CustomProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

typedef CustomShellRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required bool elevate,
  required bool rawLastArgument,
});

typedef ElevationCheck = Future<bool> Function();

typedef FileReplacer = Future<void> Function(File source, String target);

class CustomAppInstaller {
  CustomAppInstaller({
    CustomProcessRunner? processRunner,
    CustomShellRunner? shellRunner,
    ElevationCheck? isElevated,
    FileReplacer? replaceFile,
    String? downloadsDir,
  })  : _run = processRunner ?? Process.run,
        _runShell = shellRunner ?? ElevatedProcess.run,
        _isElevated = isElevated ?? ElevatedProcess.isCurrentProcessElevated,
        _replaceFile = replaceFile ?? _renameOver,
        _downloadsDir = downloadsDir;

  final CustomProcessRunner _run;
  final CustomShellRunner _runShell;
  final ElevationCheck _isElevated;
  final FileReplacer _replaceFile;
  final String? _downloadsDir;

  String get downloadsDir => _downloadsDir ?? _defaultDownloadsDir();

  static String _defaultDownloadsDir() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'];
    if (home == null || home.isEmpty) return Directory.current.path;
    return p.join(home, 'Downloads');
  }

  static Future<void> _renameOver(File source, String target) =>
      source.rename(target);

  Future<CustomInstallOutcome> install({
    required AppDescriptor descriptor,
    required String installerPath,
    String? copyToDir,
  }) async {
    final t = AppL10n.strings.customAppsDomain;

    if (!await File(installerPath).exists()) {
      throw AppDescriptorException(t.installerFileMissing(installerPath));
    }

    final kind = descriptor.portableFile
        ? CustomInstallerKind.portableFile
        : await const InstallerKindSniffer().sniff(installerPath) ??
            CustomInstallerKind.interactive;

    if (kind.isCopyOnly) {
      return CustomInstallOutcome(
        kind: kind,
        copiedPath: kind.isArchive
            ? await _copyInto(downloadsDir, installerPath)
            : await _copyInto(
                copyToDir ?? downloadsDir,
                installerPath,
                replacing: _knownFileName(descriptor, installerPath),
              ),
      );
    }

    final command = kind.silentCommand(
      installerPath: installerPath,
      installDir: descriptor.installDir,
    );
    if (command == null) return CustomInstallOutcome(kind: kind);

    if (command.rawLastArgument &&
        ElevatedProcess.needsQuoting(command.arguments.last)) {
      return _installViaShell(kind, command, elevate: false);
    }

    final ProcessResult result;
    try {
      result = await _run(command.executable, command.arguments);
    } on ProcessException catch (e) {
      if (!ElevatedProcess.isElevationRequired(e)) rethrow;
      return _installViaShell(kind, command, elevate: true);
    }
    if (kind.retriesElevatedOn(result.exitCode) && !await _isElevated()) {
      return _installViaShell(
        kind,
        command,
        elevate: true,
        firstExitCode: result.exitCode,
      );
    }
    if (!kind.isSuccessExitCode(result.exitCode)) {
      throw AppDescriptorException(
        t.installerExitCode(
          result.exitCode,
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        ),
      );
    }
    return CustomInstallOutcome(kind: kind);
  }

  Future<CustomInstallOutcome> _installViaShell(
    CustomInstallerKind kind,
    CustomInstallerCommand command, {
    required bool elevate,
    int? firstExitCode,
  }) async {
    final t = AppL10n.strings.customAppsDomain;
    final result = await _runShell(
      command.executable,
      command.arguments,
      elevate: elevate,
      rawLastArgument: command.rawLastArgument,
    );
    if (result.exitCode == ElevatedProcess.cancelledCode) {
      throw AppDescriptorException(
        firstExitCode == null
            ? t.installerElevationDeclined
            : t.installerElevatedRetryDeclined(firstExitCode),
      );
    }
    if (!kind.isSuccessExitCode(result.exitCode)) {
      final output = 'stderr: ${result.stderr}';
      throw AppDescriptorException(
        firstExitCode == null
            ? t.installerExitCode(result.exitCode, output)
            : t.installerElevatedRetryFailed(
                firstExitCode,
                result.exitCode,
                output,
              ),
      );
    }
    return CustomInstallOutcome(kind: kind);
  }

  Future<String> _copyInto(
    String targetDir,
    String sourcePath, {
    String? replacing,
  }) async {
    final t = AppL10n.strings.customAppsDomain;
    try {
      final dir = Directory(targetDir);
      await dir.create(recursive: true);

      if (replacing != null) {
        final target = p.join(dir.path, replacing);
        final temp = File('$target.part');
        try {
          await File(sourcePath).copy(temp.path);
          try {
            await _replaceFile(temp, target);
          } on FileSystemException catch (e) {
            if (await File(target).exists()) {
              final osMessage = e.osError?.message.trim() ?? '';
              throw AppDescriptorException(
                t.portableFileInUse(
                  replacing,
                  osMessage.isEmpty ? e.message : osMessage,
                ),
              );
            }
            rethrow;
          }
        } catch (_) {
          try {
            await temp.delete();
          } catch (_) {}
          rethrow;
        }
        return target;
      }

      final target = _freeNameIn(dir.path, p.basename(sourcePath));
      await File(sourcePath).copy(target);
      return target;
    } on AppDescriptorException {
      rethrow;
    } catch (e) {
      throw AppDescriptorException(t.fileCopyFailed('$e'));
    }
  }

  static String? _knownFileName(AppDescriptor descriptor, String sourcePath) {
    final known = descriptor.detect.exeName;
    if (known == null || known.trim().isEmpty) return null;
    final name = p.windows.basename(known.trim());
    final ext = p.extension(name).toLowerCase();
    if (ext != '.exe' || ext != p.extension(sourcePath).toLowerCase()) {
      return null;
    }
    return name;
  }

  static String _freeNameIn(String dir, String fileName) {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);

    var candidate = p.join(dir, fileName);
    for (var i = 2; File(candidate).existsSync() && i < 1000; i++) {
      candidate = p.join(dir, '$base ($i)$ext');
    }
    return candidate;
  }
}
