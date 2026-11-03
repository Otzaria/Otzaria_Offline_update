import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void useLibraryUpdaterL10n() =>
    LibraryUpdaterMessages.current = const L10nLibraryUpdaterMessages();

class L10nLibraryUpdaterMessages implements LibraryUpdaterMessages {
  const L10nLibraryUpdaterMessages();

  LibraryDomainStrings get _s => AppL10n.strings.libraryDomain;

  @override
  String megabytes(String amount) => AppL10n.strings.units.megabytes(amount);

  @override
  String gigabytes(String amount) => AppL10n.strings.units.gigabytes(amount);

  @override
  String unsupportedPatchCompression(String compression) =>
      _s.unsupportedPatchCompression(compression);

  @override
  String get manifestMissingPatchFiles => _s.manifestMissingPatchFiles;

  @override
  String manifestMissingField(String key) => _s.manifestMissingField(key);

  @override
  String get manifestMissingPatchFormatVersion =>
      _s.manifestMissingPatchFormatVersion;

  @override
  String manifestInvalidOptionalField(String key) =>
      _s.manifestInvalidOptionalField(key);

  @override
  String manifestInvalidHashMap(String key) => _s.manifestInvalidHashMap(key);

  @override
  String releasesRequestFailed(int statusCode) =>
      _s.releasesRequestFailed(statusCode);

  @override
  String get releasesResponseNotList => _s.releasesResponseNotList;

  @override
  String manifestDownloadFailed(String url, int statusCode) =>
      _s.manifestDownloadFailed(url, statusCode);

  @override
  String manifestNotJsonObject(String url) => _s.manifestNotJsonObject(url);

  @override
  String splitManifestDownloadFailed(String name, int statusCode) =>
      _s.splitManifestDownloadFailed(name, statusCode);

  @override
  String mirrorManifestMissing(String fileName, String mirrorDir) =>
      _s.mirrorManifestMissing(fileName, mirrorDir);

  @override
  String mirrorManifestCorrupt(
    String fileName,
    String mirrorDir,
    String error,
  ) => _s.mirrorManifestCorrupt(fileName, mirrorDir, error);

  @override
  String mirrorManifestUnexpectedShape(String fileName, String mirrorDir) =>
      _s.mirrorManifestUnexpectedShape(fileName, mirrorDir);

  @override
  String mirrorPatchManifestMissing(String url) =>
      _s.mirrorPatchManifestMissing(url);

  @override
  String mirrorPatchManifestCorrupt(String url, String error) =>
      _s.mirrorPatchManifestCorrupt(url, error);

  @override
  String mirrorPatchManifestNotJson(String url) =>
      _s.mirrorPatchManifestNotJson(url);

  @override
  String get interruptedUpdateFound => _s.interruptedUpdateFound;

  @override
  String get interruptedUpdateWithoutBackup =>
      _s.interruptedUpdateWithoutBackup;

  @override
  String get interruptedUpdateRestored => _s.interruptedUpdateRestored;

  @override
  String get localDbLocked => _s.localDbLocked;

  @override
  String get localDbInterruptedWrite => _s.localDbInterruptedWrite;

  @override
  String get localDbReadOnlyLocation => _s.localDbReadOnlyLocation;

  @override
  String get planLocalVersionUnknown => _s.planLocalVersionUnknown;

  @override
  String planNoDeltaRoute(int localVersion, int latestVersion) =>
      _s.planNoDeltaRoute(localVersion, latestVersion);

  @override
  String planNoFullDbEither(String reason) => _s.planNoFullDbEither(reason);

  @override
  String planSchemaNeedsAppUpdate(int schemaVersion, int supportedSchema) =>
      _s.planSchemaNeedsAppUpdate(schemaVersion, supportedSchema);

  @override
  String planSchemaBarrierNeedsFullDownload(int schemaVersion) =>
      _s.planSchemaBarrierNeedsFullDownload(schemaVersion);

  @override
  String planDeltaNeedsAppUpdate(
    int latestVersion,
    int supportedSchema,
    int supportedPatchFormat,
  ) => _s.planDeltaNeedsAppUpdate(
    latestVersion,
    supportedSchema,
    supportedPatchFormat,
  );

  @override
  String planHeavyDelta(String deltaSize, String localDbSize) =>
      _s.planHeavyDelta(deltaSize, localDbSize);

  @override
  String planContentChangedWithoutVersionBump(String releaseTag) =>
      _s.planContentChangedWithoutVersionBump(releaseTag);

  @override
  String planFullDbFasterThanPatches(
    int stepCount,
    int patchMinutes,
    int fullDbMinutes,
  ) => _s.planFullDbFasterThanPatches(stepCount, patchMinutes, fullDbMinutes);

  @override
  String planPatchSchemaTooNew(int schemaVersion, int latestVersion) =>
      _s.planPatchSchemaTooNew(schemaVersion, latestVersion);

  @override
  String planPatchFormatTooNew(int patchFormatVersion, int latestVersion) =>
      _s.planPatchFormatTooNew(patchFormatVersion, latestVersion);

  @override
  String planFullDbWouldNotProgress(
    int reachableVersion,
    int localVersion,
    int latestVersion,
  ) => _s.planFullDbWouldNotProgress(
    reachableVersion,
    localVersion,
    latestVersion,
  );

  @override
  String planNewSchemaNeedsFullDb(int latestVersion, int schemaVersion) =>
      _s.planNewSchemaNeedsFullDb(latestVersion, schemaVersion);

  @override
  String planPartialDeltaSchemaStop(
    int reachedVersion,
    int latestVersion,
    int schemaVersion,
  ) => _s.planPartialDeltaSchemaStop(
    reachedVersion,
    latestVersion,
    schemaVersion,
  );

  @override
  String planPartialDeltaFormatStop(
    int reachedVersion,
    int latestVersion,
    int patchFormatVersion,
  ) => _s.planPartialDeltaFormatStop(
    reachedVersion,
    latestVersion,
    patchFormatVersion,
  );

  @override
  String unsupportedSchemaForHashOrder(int schemaVersion) =>
      _s.unsupportedSchemaForHashOrder(schemaVersion);

  @override
  String localVersionMismatch(int? localVersion, int expected) =>
      _s.localVersionMismatch(localVersion, expected);

  @override
  String localSchemaMismatch(int localSchema, int expected) =>
      _s.localSchemaMismatch(localSchema, expected);

  @override
  String get contentHashMismatchNeedsFullDownload =>
      _s.contentHashMismatchNeedsFullDownload;

  @override
  String patchUniqueConflictNeedsFullDownload(String table, String detail) =>
      _s.patchUniqueConflictNeedsFullDownload(table, detail);

  @override
  String foreignKeyViolationsGrew(int before, int after) =>
      _s.foreignKeyViolationsGrew(before, after);

  @override
  String resultHashMismatch(String actual, String expected) =>
      _s.resultHashMismatch(actual, expected);

  @override
  String tableHashMismatch(String tables) => _s.tableHashMismatch(tables);

  @override
  String patchOpenFailed(String path, String detail) =>
      _s.patchOpenFailed(path, detail);

  @override
  String get patchMetaSchemaVersionMissing => _s.patchMetaSchemaVersionMissing;

  @override
  String patchFormatTooNew(int patchFormatVersion, int supported) =>
      _s.patchFormatTooNew(patchFormatVersion, supported);

  @override
  String patchFormatMismatch(int inPatch, int inManifest) =>
      _s.patchFormatMismatch(inPatch, inManifest);

  @override
  String patchVersionRangeMismatch(
    int? from,
    int? to,
    int manifestFrom,
    int manifestTo,
  ) => _s.patchVersionRangeMismatch(from, to, manifestFrom, manifestTo);

  @override
  String get networkInterrupted => _s.networkInterrupted;

  @override
  String get compressedFileSizeLabel => _s.compressedFileSizeLabel;

  @override
  String get compressedFileHashLabel => _s.compressedFileHashLabel;

  @override
  String get extractedFileSizeLabel => _s.extractedFileSizeLabel;

  @override
  String get extractedFileHashLabel => _s.extractedFileHashLabel;

  @override
  String get patchExtractionFailed => _s.patchExtractionFailed;

  @override
  String get deleteExistingWithoutResumeIdentityFailed =>
      _s.deleteExistingWithoutResumeIdentityFailed;

  @override
  String get deletePartialFromPreviousVersionFailed =>
      _s.deletePartialFromPreviousVersionFailed;

  @override
  String get deletePartialWithoutValidatorFailed =>
      _s.deletePartialWithoutValidatorFailed;

  @override
  String get deletePartialFromPreviousRepresentationFailed =>
      _s.deletePartialFromPreviousRepresentationFailed;

  @override
  String get deletePartialBeforeRetryFailed =>
      _s.deletePartialBeforeRetryFailed;

  @override
  String get deletePreviousArchiveFailed => _s.deletePreviousArchiveFailed;

  @override
  String fullDbSizeMismatch(int downloaded, int expected) =>
      _s.fullDbSizeMismatch(downloaded, expected);

  @override
  String get fullDbHashMismatch => _s.fullDbHashMismatch;

  @override
  String joinedArchiveSizeMismatch(int written, int expected) =>
      _s.joinedArchiveSizeMismatch(written, expected);

  @override
  String get joinedArchiveHashMismatch => _s.joinedArchiveHashMismatch;

  @override
  String resumeRoundLimit(int maxRounds, String url) =>
      _s.resumeRoundLimit(maxRounds, url);

  @override
  String contentLengthMismatch(int responseLength, int expectedSize) =>
      _s.contentLengthMismatch(responseLength, expectedSize);

  @override
  String truncatedBody(int declared, int received) =>
      _s.truncatedBody(declared, received);

  @override
  String downloadHttpError(int statusCode, String url) =>
      _s.downloadHttpError(statusCode, url);

  @override
  String resumeMadeNoProgress(String url) => _s.resumeMadeNoProgress(url);

  @override
  String resumeFailedAfterRetry(String url) => _s.resumeFailedAfterRetry(url);

  @override
  String downloadExceedsExpectedSize(int expectedSize) =>
      _s.downloadExceedsExpectedSize(expectedSize);

  @override
  String saveDownloadedFileFailed(String error) =>
      _s.saveDownloadedFileFailed(error);

  @override
  String tooManyRedirects(String url) => _s.tooManyRedirects(url);

  @override
  String writeResumeSidecarFailed(String path, String error) =>
      _s.writeResumeSidecarFailed(path, error);

  @override
  String destinationBusy(String path) => _s.destinationBusy(path);

  @override
  String checksumMismatchDetailed(
    String label,
    String expected,
    String actual,
  ) => _s.checksumMismatchDetailed(label, expected, actual);

  @override
  String checksumMismatch(String label) => _s.checksumMismatch(label);

  @override
  String localFileNotFound(String path) => _s.localFileNotFound(path);

  @override
  String localFileTooLarge(int maxBytes, String path) =>
      _s.localFileTooLarge(maxBytes, path);

  @override
  String localSourceNotFound(String url) => _s.localSourceNotFound(url);

  @override
  String localFileSizeMismatch(int expected, int actual, String url) =>
      _s.localFileSizeMismatch(expected, actual, url);

  @override
  String localFileHashMismatch(String url) => _s.localFileHashMismatch(url);

  @override
  String get exportLoadingReleases => _s.exportLoadingReleases;

  @override
  String get exportNoReleases => _s.exportNoReleases;

  @override
  String exportPersonalFrom(int localVersion) =>
      _s.exportPersonalFrom(localVersion);

  @override
  String exportPersonalUpToDate(int localVersion) =>
      _s.exportPersonalUpToDate(localVersion);

  @override
  String exportReusingFullDb(int version, String tag) =>
      _s.exportReusingFullDb(version, tag);

  @override
  String exportDownloading(String tag, String asset) =>
      _s.exportDownloading(tag, asset);

  @override
  String exportVerifying(String tag, String asset, int percent) =>
      _s.exportVerifying(tag, asset, percent);

  @override
  String exportAssembling(String tag, String asset, int percent) =>
      _s.exportAssembling(tag, asset, percent);

  @override
  String exportSplitFullDbSkipped(String tag, String detail) =>
      _s.exportSplitFullDbSkipped(tag, detail);

  @override
  String exportSplitPartCorrupted(String asset, String parts) =>
      _s.exportSplitPartCorrupted(asset, parts);

  @override
  String exportAssembledReplaceFailed(String path, String detail) =>
      _s.exportAssembledReplaceFailed(path, detail);

  @override
  String exportWritingManifest(String fileName) =>
      _s.exportWritingManifest(fileName);

  @override
  String get exportDone => _s.exportDone;

  @override
  String get exportCancelled => _s.exportCancelled;

  @override
  String get exporterDoesNotExtract => _s.exporterDoesNotExtract;

  @override
  String exportManifestUnreadable(String asset, String detail) =>
      _s.exportManifestUnreadable(asset, detail);

  @override
  String exportManifestFetchFailed(String asset, String detail) =>
      _s.exportManifestFetchFailed(asset, detail);

  @override
  String exportPatchAssetMissing(String tag, String file) =>
      _s.exportPatchAssetMissing(tag, file);

  @override
  String exportSkippingUnappliablePatch(
    String tag,
    String file,
    int schemaVersion,
  ) => _s.exportSkippingUnappliablePatch(tag, file, schemaVersion);

  @override
  String exportSkippingUnsupportedPatchFormat(
    String tag,
    String file,
    int patchFormatVersion,
  ) => _s.exportSkippingUnsupportedPatchFormat(tag, file, patchFormatVersion);

  @override
  String exportFullDbRequiredBySchema(int schemaVersion, int latestVersion) =>
      _s.exportFullDbRequiredBySchema(schemaVersion, latestVersion);

  @override
  String exportFullDbRequiredByPatchFormat(
    int patchFormatVersion,
    int latestVersion,
  ) => _s.exportFullDbRequiredByPatchFormat(patchFormatVersion, latestVersion);

  @override
  String exportFullDbSchemaUnsupported(String tag, int schemaVersion) =>
      _s.exportFullDbSchemaUnsupported(tag, schemaVersion);

  @override
  String exportSkippingPatchesFullDbWins(int fileCount, int fullDbVersion) =>
      _s.exportSkippingPatchesFullDbWins(fileCount, fullDbVersion);

  @override
  String exportFullDbInsteadOfSlowPatches(
    int fileCount,
    int patchMinutes,
    int fullDbMinutes,
    int toVersion,
  ) => _s.exportFullDbInsteadOfSlowPatches(
    fileCount,
    patchMinutes,
    fullDbMinutes,
    toVersion,
  );

  @override
  String exportPersonalNeedsFullDb(int fromVersion, int latestVersion) =>
      _s.exportPersonalNeedsFullDb(fromVersion, latestVersion);

  @override
  String exportPersonalNoFullDbEither(int fromVersion, int latestVersion) =>
      _s.exportPersonalNoFullDbEither(fromVersion, latestVersion);

  @override
  String mirrorNotEnoughDiskSpace(String dir, String needed, String free) =>
      _s.mirrorNotEnoughDiskSpace(dir, needed, free);
}
