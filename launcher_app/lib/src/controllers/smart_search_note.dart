import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// The sentence for a smart-search state that is not "nothing to do"; `null`
/// when [status] needs none.
String? smartSearchNote(SmartSearchStatus status) {
  final t = AppL10n.strings.libraryDomain;
  return switch (status.state) {
    SmartSearchState.installedVerified || SmartSearchState.notInUse => null,
    SmartSearchState.readyOnDrive => t.semanticStatusReadyOnDrive,
    SmartSearchState.needsDriveDownload => t.semanticStatusNeedsDriveDownload,
    SmartSearchState.driveNotMatching =>
      status.message ?? t.semanticStatusDriveNotMatching,
    SmartSearchState.partial => _partial(status),
    SmartSearchState.unsupported => switch (status.reason) {
        SmartSearchReason.engineIncompatible
            when status.incompatibility != null =>
          '${status.incompatibility}',
        SmartSearchReason.appUnproven ||
        SmartSearchReason.appFamilyUnknown =>
          t.semanticStatusAppUnproven,
        _ => t.semanticStatusAppCannotRead,
      },
    SmartSearchState.unverified =>
      status.message ?? t.semanticStatusCheckFailed,
  };
}

String _partial(SmartSearchStatus status) {
  final t = AppL10n.strings.libraryDomain;
  final names = [
    for (final part in SmartSearchPart.values)
      if (status.missing.contains(part))
        switch (part) {
          SmartSearchPart.model => t.semanticPartModel,
          SmartSearchPart.vectors => t.semanticPartVectors,
          SmartSearchPart.preferences => t.semanticPartPreferences,
        },
  ];
  final head = status.reason == SmartSearchReason.verificationFailed
      ? '${t.semanticStatusVerificationFailed} '
      : '';
  return names.isEmpty
      ? status.message ?? t.semanticStatusVerificationFailed
      : '$head${t.semanticStatusPartial(names.join(', '))}';
}

/// Whether the drive cannot serve this computer's smart search, so only a
/// download on a connected computer helps.
bool smartSearchNeedsDriveDownload(SmartSearchStatus? status) =>
    status != null && status.needsDownload;
