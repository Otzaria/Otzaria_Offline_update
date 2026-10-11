import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

class CustomAppDetectionSnapshot {
  CustomAppDetectionSnapshot({
    required List<String> Function() runningImagePaths,
    required List<InstallRegistryEntry> Function() uninstallEntries,
  })  : _runningImagePaths = runningImagePaths,
        _uninstallEntries = uninstallEntries;

  factory CustomAppDetectionSnapshot.live() => CustomAppDetectionSnapshot(
        runningImagePaths: RunningOtzariaLocator.windowsRunningImagePaths,
        uninstallEntries: () => const WindowsInstallRegistry()
            .entries(matchesDisplayName: (_) => true),
      );

  final List<String> Function() _runningImagePaths;
  final List<InstallRegistryEntry> Function() _uninstallEntries;

  List<String>? _processes;
  List<InstallRegistryEntry>? _entries;

  Future<String?> runningProcess(String exeName) async {
    final target = exeName.toLowerCase();
    for (final path in _processes ??= _quietly(_runningImagePaths)) {
      if (p.basename(path).toLowerCase() == target) return path;
    }
    return null;
  }

  List<String> uninstallDirs(RegExp displayName) {
    final dirs = <String>[];
    final seen = <String>{};
    for (final entry in _entries ??= _quietly(_uninstallEntries)) {
      final dir = entry.installDir;
      if (dir == null || !displayName.hasMatch(entry.displayName)) continue;
      if (seen.add(dir.toLowerCase())) dirs.add(dir);
    }
    return dirs;
  }

  static List<T> _quietly<T>(List<T> Function() read) {
    try {
      return read();
    } catch (_) {
      return const [];
    }
  }
}
