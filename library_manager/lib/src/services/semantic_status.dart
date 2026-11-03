import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'semantic_vectors_plan.dart';

/// What the smart-search check can honestly say. Only [installedVerified]
/// means "nothing to do"; every other state names who has to act.
enum SmartSearchState {
  /// Matching data is installed and was checked against the installed app.
  installedVerified,

  /// Matching material is on the drive and installing it is the next step.
  readyOnDrive,

  /// The drive holds material the installed Otzaria cannot use (other
  /// generation, shape or version).
  driveNotMatching,

  /// The drive holds nothing usable: a download on a connected computer.
  needsDriveDownload,

  /// This tool, or the installed Otzaria, cannot be matched to any data.
  unsupported,

  /// The check did not run, failed, or found no proof either way.
  unverified,

  /// Some parts are right and others are not.
  partial,

  /// Smart search is not set up here and nothing offers it.
  notInUse,
}

enum SmartSearchReason {
  none,

  /// Nothing proves which model generation the installed Otzaria reads.
  appUnproven,

  /// Otzaria declares vector families this tool does not know.
  appFamilyUnknown,

  /// The drive has no smart-search data for this library version.
  driveEmpty,

  /// The drive has a `semantic.json` this tool cannot (fully) read.
  driveUnreadable,

  /// The drive's data is for an older library version.
  driveOlderVersion,

  /// The drive's files are missing, damaged or not fully downloaded.
  driveIncomplete,

  /// The drive holds another model generation than the installed Otzaria reads.
  driveOtherGeneration,

  /// The drive holds only the other vector shape (anchor/windows).
  driveOtherShape,

  /// The installed set is windows-shaped and the drive offers only anchor.
  keepsWindowsSet,

  /// The published vectors cannot be read by the bundled engine.
  engineIncompatible,

  /// The installed Otzaria is too old, or unproven, for these vectors.
  appCannotRead,

  /// The check threw.
  checkFailed,

  /// A needed part is not installed (see [SmartSearchStatus.missing]).
  partsMissing,

  /// Installed, but the set or model disagree with the app after install.
  verificationFailed,
}

enum SmartSearchPart { model, vectors, preferences }

class SmartSearchStatus {
  const SmartSearchStatus({
    required this.state,
    this.reason = SmartSearchReason.none,
    this.required,
    this.driveGenerations = const {},
    this.installedGeneration,
    this.missing = const {},
    this.present = const {},
    this.incompatibility,
    this.error,
    this.proofKey = '',
  });

  final SmartSearchState state;
  final SmartSearchReason reason;

  /// The generation and shape the installed Otzaria reads; `null` = unproven.
  final SemanticTarget? required;

  /// Generations the drive's `semantic.json` holds.
  final Set<SemanticModelGeneration> driveGenerations;

  /// The generation of the live installed set, when its identity says.
  final SemanticModelGeneration? installedGeneration;

  /// Parts that are not (correctly) installed.
  final Set<SmartSearchPart> missing;

  /// Parts that are installed and match.
  final Set<SmartSearchPart> present;
  final Object? incompatibility;
  final Object? error;

  /// Changes when the app, generation, vector identity or the drive's data
  /// change; a cached "all clear" is only valid for the same key.
  final String proofKey;

  /// The only state in which nothing remains to do.
  bool get allClear =>
      state == SmartSearchState.installedVerified ||
      state == SmartSearchState.notInUse;

  /// Installing from the drive would help now.
  bool get installable => state == SmartSearchState.readyOnDrive;

  /// A download on a connected computer is what is needed.
  bool get needsDownload =>
      state == SmartSearchState.needsDriveDownload ||
      state == SmartSearchState.driveNotMatching;

  SmartSearchStatus copyWith({
    SmartSearchState? state,
    SmartSearchReason? reason,
    Object? incompatibility,
    Object? error,
    Set<SmartSearchPart>? missing,
    Set<SmartSearchPart>? present,
  }) => SmartSearchStatus(
    state: state ?? this.state,
    reason: reason ?? this.reason,
    required: required,
    driveGenerations: driveGenerations,
    installedGeneration: installedGeneration,
    missing: missing ?? this.missing,
    present: present ?? this.present,
    incompatibility: incompatibility ?? this.incompatibility,
    error: error ?? this.error,
    proofKey: proofKey,
  );

  /// A user-facing sentence for the states that need one; `null` when
  /// [state] says it all.
  String? get message {
    final strings = AppL10n.strings.libraryDomain;
    return switch (reason) {
      SmartSearchReason.appUnproven ||
      SmartSearchReason.appFamilyUnknown => strings.semanticStatusAppUnproven,
      SmartSearchReason.driveOtherGeneration ||
      SmartSearchReason.driveOtherShape ||
      SmartSearchReason.keepsWindowsSet ||
      SmartSearchReason.driveOlderVersion ||
      SmartSearchReason.driveIncomplete ||
      SmartSearchReason.driveEmpty => strings.semanticStatusDriveNotMatching,
      SmartSearchReason.driveUnreadable =>
        strings.semanticStatusDriveUnreadable,
      SmartSearchReason.verificationFailed =>
        strings.semanticStatusVerificationFailed,
      _ => null,
    };
  }

  @override
  String toString() =>
      'SmartSearchStatus($state, $reason, required=${required?.generation.id}/${required?.family.id}, '
      'drive=${driveGenerations.map((g) => g.id).join(',')}, '
      'installed=${installedGeneration?.id}, missing=${missing.map((p) => p.name).join(',')})';
}

/// The result of installing: what was verified afterwards.
class SmartSearchInstallOutcome {
  const SmartSearchInstallOutcome({
    required this.baseInstalled,
    required this.status,
  });

  /// A base (not a chain) was written.
  final bool baseInstalled;

  /// Re-checked against the installed app after the write; a successful
  /// write alone is not "done".
  final SmartSearchStatus status;
}

/// Thrown after an install whose result does not match what the installed
/// Otzaria reads.
class SmartSearchVerificationException implements Exception {
  const SmartSearchVerificationException(this.status);

  final SmartSearchStatus status;

  @override
  String toString() =>
      status.message ??
      AppL10n.strings.libraryDomain.semanticStatusVerificationFailed;
}
