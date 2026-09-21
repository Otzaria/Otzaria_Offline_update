# AGENTS.md

Contract for AI coding agents working in this repository. Human-facing docs
(README, CHANGELOG, package READMEs) are in Hebrew; this file is in English on
purpose, as the shared agent contract.

**How to read it:** §1–§4 before your first change. The part of §5 that covers
the area you are about to touch — every entry there is a bug that already
happened, and the code looks the way it does because of it. §6 says what has
actually been verified on real hardware. Before **adding** anything here, read
["Editing this file"](#editing-this-file).

| § | |
| --- | --- |
| [1](#1-what-this-software-is-for) | What this software is for — the offline workflow, the data folder |
| [2](#2-repository-layout) | Repository layout — seven packages |
| [3](#3-mandatory-workflow-after-every-change) | Format, analyze, test — required after every change |
| [4](#4-code-style) | Comments, module boundaries, UI components, l10n |
| [5](#5-landmines--do-not-break-these) | Landmines, grouped by area |
| [6](#6-verification-status) | What is verified and what is not |
| [7](#7-communication) | Communication |
| [↓](#editing-this-file) | **Editing this file** — read before you add to it |

---

## Editing this file

This file survives only if every agent that adds to it keeps it short. The rules
below are the format, not a suggestion.

**Where it goes.** §1–§4 stay at overview level; every *detail* belongs in the
§5 subsection for its area (Kotlin contract, mirror, drive state, library, app,
plugins, custom apps, packaging, UI). If nothing fits, add a subsection with its
own `###` heading — never append to the end of the file, and never grow §1 with
material that is really a landmine.

**The entry format**, in this order and nothing else:

1. One **bold** sentence stating the rule.
2. One to three sentences of *why* — the incident, with the concrete number,
   issue number or date that makes it credible.
3. The file, class or symbol names a reader needs to find it.

**Eight lines is the budget for one entry.** If it needs more, the extra belongs
in the package README or the CHANGELOG, and this file links to it. Do not write
a chronological account of how the bug was found.

**§5 is for landmines only.** A rule earns its place when breaking it caused a
real bug, or when a reasonable reviewer would "simplify" it away without knowing
better. Anything merely nice to know goes in the package README.

**Say it once.** A fact lives in exactly one place; point at it with "§5.3"
rather than restating it. Duplication here is how the file doubled in size.

**Update, never accumulate.** When behaviour changes, edit the existing entry —
do not add a second one that contradicts it. Delete the entry when its code is
gone. `git log` keeps the history; this file keeps the current truth.

**Verification claims go in §6's table, honestly.** A row moves out of
"unit-tested only" only after someone actually ran it on real hardware.

**Formatting.** English; wrap at ~79 columns; `backticks` for identifiers, paths
and flags; bold for the rule itself. No emoji beyond the one ⚠️ already there.
Keep the table of contents in sync, and keep the `###` numbering stable — other
docs and agents refer to these section numbers.

---

## 1. What this software is for

Otzaria is a Hebrew sefarim-library reading app. Its book database
(`seforim.db`, ~1GB) gets new releases regularly, and it has plugins that need
updating. Many Otzaria users have **no internet on the machine that runs
Otzaria** — by choice or by policy.

This repository is the updater/launcher for those users:

1. Copy this software onto a USB flash drive ("On-Key").
2. Plug it into a computer **that has internet** and press *download* once. It
   fills a folder **right next to the executable** with library updates, the
   Otzaria installers, the plugin store, and — when there is one — a newer
   launcher.
3. Unplug it, plug it into the **offline** computer, run the launcher again. It
   installs from that folder. No network needed.

**There is exactly one mode: offline.** Otzaria already updates itself over the
network, so this launcher deliberately offers no "just update from the internet"
path. Every check and every install reads the local folder, always — even when
the machine is online. One thing touches the network: the download step.

| Step | API | Network |
| --- | --- | --- |
| Download library updates + companions | `LibraryManager.downloadToMirror()` | **yes**, heavy |
| Download the Otzaria installers (stable + newer pre-release) | `OtzariaManager.downloadToMirror()` | **yes**, heavy |
| Download the plugin store | `PluginsManager.sync()` | **yes**, heavy |
| Download a newer launcher | `LauncherSelfUpdater.downloadToMirror()` | **yes** (tens of MB) |
| Peek the latest library / app / launcher / store | `*.peek*()` on all four managers | **yes**, light — one API call, no asset |
| Check / apply a library update | `LibraryManager.checkForUpdate()` / `.applyUpdate()` | no |
| Check / install the Otzaria app | `OtzariaManager.checkForUpdate()` / `.update()` | no |
| Check / install the launcher itself | `LauncherSelfUpdater.checkForUpdate()` / `.applyUpdate()` | no |
| Read the store / install a plugin | `PluginsManager.load()` / `.directInstall()` | no |

The "peek" calls exist only for the optional, one-shot, on-launch "is there
anything new online?" nudge (`AppShell.checkOnline()`,
`AppSettings.autoCheckUpdates`) — metadata only, never an asset, and a failure
(no network) is a normal silent outcome. **All four modules must be in that
call**: the plugin store was missing from it for its whole life, so a new plugin
was announced by nothing while the launcher said "no new updates online".

### The data folder

`AppPaths.resolve()` (`launcher_app`) puts it at
`<dir of the executable>/OtzariaData`, and **there is no setting to change it** —
that is what makes the drive self-contained. If it is not writable (the app was
moved into `Program Files`), the launcher shows `SetupErrorScreen` and refuses to
run rather than falling back to `%APPDATA%`, which would leave the data behind on
the online machine.

```
mirror/library/     releases.json + assets/                               ← LibraryManager.mirrorDir
mirror/companions/  companions.json + Talmud archive, catalog, dictionary ← LibraryManager.companionsMirrorDir
mirror/app/         latest-release.json (≤2 channels) + installers/<tag>/ ← OtzariaAppMirror
mirror/plugins/     catalog.json + files/<id>/plugin-<version>.otzplugin  ← PluginMirrorStore
mirror/store-app/   latest-release.json + files/<tag>/<store>.exe         ← StoreAppMirror
mirror/launcher/    latest-release.json + files/<tag>/                    ← LauncherUpdateMirror
otzaria-app/        legacy — installs made before the target was fixed
```

**Otzaria itself is never installed under `OtzariaData/`.** `otzaria-app/` used to
be the default target, so a launcher run from a stick installed Otzaria *onto the
stick* — it vanished when the stick was pulled.
`OtzariaManager.resolveDefaultInstallDir()` now returns the app's normal location
(§5.5) and `OtzariaInstaller.installFromFile` takes a **required** `installDir`,
so there is no launcher-owned default to fall into. The folder stays first in
`_autoDetectDirs` only so existing installs keep updating in place.

### Read-only drive mode (issue #25)

A write-protected drive that **already carries a mirror** runs read-only: someone
locks the stick and hands it around, and the people it reaches only install from
it. `AppPaths` returns `readOnly: true`, `stateDir` moves to
`%LOCALAPPDATA%\OtzariaOfflineUpdate`, and `dataDir` — the mirror — stays on the
drive.

It works because **no install writes to the drive**: Inno writes to the machine,
the library applier stages next to the existing DB, plugins go into Otzaria's own
folder. What moves to `stateDir` is the log, `launcher_settings.json`,
`faq_customization.json`, `library_state.json`, `otzaria_install_state.json`,
`custom_apps_announced.json` — and the state files belong there anyway ("which
version is installed" describes the machine). Preferences are seeded once
(`AppPaths.seedPreferences`); the state files deliberately are not.

Everything that writes to the drive is off, with no prompt anywhere: `downloadAll`,
the plugin sync, custom-app add/download, and self-update (it replaces the exe *on
the drive*). `checkOnline` is skipped too — "there is something new online" with no
way to bring it is nagging. Detection is free on the normal path: the mirror probe
runs **only** after the write probe failed. An empty locked folder is still
`SetupErrorScreen` — nothing to install from means the wrong place.

---

## 2. Repository layout

Seven Dart/Flutter packages, each with its own `pubspec.yaml`. The main package
sits at the repo root (historical — do not move it).

| Path | Package | Role |
| --- | --- | --- |
| `otzaria_l10n/` | `otzaria_l10n` | Pure Dart, **no dependencies at all**. Every user-visible string, Hebrew + English. Everything depends on it — including the pure-Dart managers, which is why it cannot use Flutter. See §4. |
| `.` (root, `lib/`) | `seforim_library_updater` | Flutter. Client side of the `Otzaria/SeforimLibrary` delta format: discover releases, plan a route (delta vs. full), download, verify the logical hash, apply patches atomically. |
| `otzaria_manager/` | `otzaria_manager` | Pure Dart. The **Otzaria app itself**: check, download, silent install, launch. Windows + macOS. |
| `library_manager/` | `library_manager` | Flutter. Wires the root package into the launcher: locate the real `seforim.db`, check versions, apply to the **live** DB, export/consume the mirror. |
| `plugins_manager/` | `plugins_manager` | Pure Dart. The **offline plugin store**: syncs `otzaria.org/api/plugins` into the mirror, detects what Otzaria has, installs via `otzaria://`. Converted from `Yehuda-Zakesh/Offline-repository-plugin-store` (itself derived from `Otzaria/Otzaria_Website`); details in `plugins_manager/README.md`. |
| `custom_apps_manager/` | `custom_apps_manager` | Pure Dart. **User-added programs**: a record filled in a form (name, GitHub repo *or* local installer, install location, detection rules) so the drive can carry a program that is not Otzaria. Not a plugin system — no runtime, no WebView, no permissions, and **no importing a record from a file**, so every repo and file was chosen by the user. |
| `launcher_app/` | `launcher_app` | The Flutter desktop app (Windows + macOS) wiring the modules into one dashboard. Depends on the other six by relative `path:`, so it must stay their sibling. |

Producer vs. consumer: the Kotlin repo `Otzaria/SeforimLibrary` *produces* the DB
and the patches; this repo only *consumes* them.

**The root package is a fork of `Otzaria/otzaria_library_updater`** — the package
Otzaria itself depends on for its online update. Keep the engine (discovery,
planner, hasher, `PatchApplier`, `PatchDownloader`) in step with upstream; our
deliberate additions are the l10n calls, the offline mirror source/exporter, and
`LibraryUpdatePlanner.localReleaseTag`. Otzaria's consumer side is
`Otzaria/otzaria` under `lib/library_update/` — read it before changing how the
launcher orchestrates an update, and see `library_manager/README.md` §
"התאמה לעדכון המקוון של אוצריא".

---

## 3. Mandatory workflow after every change

Run these in the package(s) you touched. Not optional, not deferred to CI.

```bash
dart format .

flutter analyze --no-fatal-infos   # root, library_manager, launcher_app
dart analyze                       # otzaria_l10n, otzaria_manager, plugins_manager, custom_apps_manager
```

- **Analyze inside each package you changed.** The root `analysis_options.yaml`
  **excludes** the sub-packages, so analyzing from the root covers none of them.
  Every sub-package carries its own file for the same reason — without one the
  analyzer walks up, inherits the root's `exclude:` for that very package, and
  reports "No issues found" while checking nothing. Do not delete those files.
- **Each of the seven includes two things:** its base rule set
  (`flutter_lints` or `lints/recommended`) and the root
  `analysis_options_shared.yaml`, which holds every repo-wide tightening. A rule
  added to one package only silently does not apply to the rest (that is what
  happened to `prefer_single_quotes`); `otzaria_l10n/test/shared_lint_config_test.dart`
  asserts all seven import it. Measure a new rule in **all seven** — one that is
  clean in five and fails in the sixth turns CI red. Note `dart analyze`
  right-aligns severity, so `warning` lines have **no** leading space while `info`
  lines do; a grep assuming indentation misses every warning.
- **Run the tests when logic changed**: `flutter test` (root, `library_manager`,
  `launcher_app`) or `dart test` (the pure-Dart packages).
- **Real file I/O does not complete inside `testWidgets`** — its fake-async zone
  never resolves `dart:io` futures, so `pumpAndSettle` hangs forever on a spinner
  waiting on disk. Drive such work with `tester.runAsync(...)` *before* pumping;
  see the store tests in `launcher_app/test/screens_test.dart`.
- **`.gitattributes` pins `*.json` to `eol=lf`.**
  `test/patch_tables_contract.json` is compared byte-for-byte against the Kotlin
  side; with `core.autocrlf=true` it arrived as CRLF and the contract test failed
  on every Windows machine.
- **Favor layered tests over manual checks.** `.github/workflows/ci.yml` runs the
  full suite across every package on every push and PR — the only trigger (the
  weekly `cron` was removed 2026-08-11).
- **Publishing is a deliberate click, not a push.** A push to `main` only runs
  `ci.yml`. A release comes from Actions → **Release** → *Run workflow* (`main`
  only): `release.yml` runs the whole of `ci.yml` via `workflow_call`, then its
  `publish` job bumps the launcher's version, commits, tags, and uploads *that
  run's* artifacts — so what ships is exactly what was tested. Before 2026-09-21
  every green push published; it does not any more. See `launcher_app/README.md`
  § "עדכון עצמי".
- **`.githooks/pre-commit` runs the same checks locally** on staged packages and
  blocks the commit on failure. Each clone needs
  `git config core.hooksPath .githooks` once.
- **Report honestly what you ran and what failed.** Do not call a change verified
  when only the analyzer passed.

---

## 4. Code style

- **Comments are short — one or two lines.** Explain *why*, not *what*; skip the
  comment when the code says it. Long prose belongs in the package README or
  CHANGELOG. Comments and doc-comments are in Hebrew; keep them so.
- Match the surrounding naming and idiom. Follow `flutter_lints`.
- **Keep the module boundaries.** `otzaria_manager` must not depend on Flutter;
  the root package must not depend on Otzaria app code or on the launcher.
  `otzaria_l10n` is the one package everything may depend on — which is why it has
  no dependencies of its own.
- Do not silently widen scope. Fix what was asked, then say what you left out.

**UI in `launcher_app` follows Otzaria's design system, not its own.**
`launcher_app/lib/src/theme/` and `lib/src/widgets/` are ports of
`otzaria/lib/theme/` and `otzaria/lib/widgets/`. Use the ported components
(`ActionButton`, `SettingsCard`/`SettingsActionTile`, `AppCard`, `UiSnack`, the
`show*Dialog` helpers, `AppSegmentedControl`, `RtlIcon`, `RtlTextField`,
`StatusChip`, `ColorPickerTile`) instead of raw Material widgets, and keep
alpha/hover overrides inside `lib/src/theme/`. The full rule table — including what
deliberately was *not* ported — is in `launcher_app/README.md`; the upstream
contract is `otzaria/AGENTS.md` § "MANDATORY UI Components".

**All user-visible text lives in `otzaria_l10n`, never inline.** The launcher ships
in Hebrew and English, defaulting to the system language
(`AppLanguagePreference.system`). Do not write a literal a user can read — not in a
widget, not in an exception message, not in a progress callback. Add a field to
`otzaria_l10n/lib/src/app_strings.dart` and implement it in **both**
`strings_he.dart` and `strings_en.dart`; the analyzer fails if you forget one.
Hebrew is the source, English a free translation of it.

- In widgets: `context.strings.<section>.<field>` (`AppStringsScope`, exported from
  `widgets_exports.dart`). It is an `InheritedWidget` on purpose — a `const` widget
  would otherwise keep the old language on screen until something else rebuilt it —
  and it is installed in `MaterialApp.builder`, *above* the Navigator, so dialogs
  and pushed routes find it.
- Outside widgets: `AppL10n.strings.<section>.<field>`, set by `SettingsController`.
- **`Isolate.run` does not inherit it.** Statics are per-isolate, so a message built
  inside an isolate falls back to Hebrew. Pass `AppL10n.language` in and call
  `AppL10n.use(...)` first thing — see `LibraryUpdateApplier._isolateApplyPatch`
  and `ZstdFileDecompressor`.
- Content from `otzaria.org` (plugin names, descriptions, tags, categories, store
  home texts) is **never** translated — only the chrome around it, plus the
  store-title fallback for an empty field.
- Direction comes from the locale alone (`GlobalWidgetsLocalizations`); never set
  `Directionality` by hand. Exactly two exceptions, pinned by an allowlist in
  `launcher_app/test/widgets_test.dart`: `UiSnack` (lives in an `Overlay`, reads
  `AppL10n.language.isRtl`) and `SeedColorPalette` (forces RTL so the swatch order
  does not mirror). A third is a bug, not a precedent. For back/forward arrows use
  `context.backArrowIcon` / `context.forwardArrowIcon`: `RtlIcon` mirrors arrows
  under RTL, so those helpers hand it the *opposite* glyph and the result is
  identical in both languages.

---

## 5. Landmines — do not break these

Each entry was a real bug or a verified finding. Changing the surrounding code
without knowing why it looks that way will regress it.

**The overriding invariant: no check path ever falls back to the network.**
`LibraryManager._resolveSource` returns the local mirror or throws
`LibraryMirrorMissingException` — never `GithubLibraryReleaseClient`.
`OtzariaManager.checkForUpdate` reads `OtzariaAppMirror.load()`, never GitHub. An
earlier version did fall back, and the launcher behaved differently depending on
whether the machine happened to be online — the duality this design removes.

[5.1 Kotlin contract](#51-the-contract-with-the-kotlin-producer) ·
[5.2 Filling the mirror](#52-filling-the-mirror-the-online-machine) ·
[5.3 State on the drive](#53-state-that-travels-on-the-drive) ·
[5.4 Updating the library](#54-updating-the-library-the-offline-machine) ·
[5.5 The Otzaria app](#55-the-otzaria-app-detect-install-version) ·
[5.6 Plugins](#56-plugins) ·
[5.7 Custom apps](#57-custom-apps) ·
[5.8 Packaging & self-update](#58-packaging-distribution-and-self-update) ·
[5.9 UI and platform](#59-ui-and-platform)

### 5.1 The contract with the Kotlin producer

**`LogicalContentHasher` and `PatchApplier` are byte-for-byte translations of the
Kotlin logic** (including U+FEFF / BOM handling) and must agree with it exactly.
Change either and every update starts getting rejected. Golden-hash tests guard it.

**An unsupported DB schema is a full-download route, not a failure — and it must be
detected during *planning*.** `kHashTableOrderBySchemaVersion` in
`patch_table_spec.dart` is the single source of truth (`isSupportedSchemaVersion`);
adding a schema is one line. Everything downstream reads it:
`PatchEdge.hasSupportedSchema`, `LibraryUpdateDiscovery.discover` (drops those
edges but still counts them toward `latestVersion`, so a new release never reads
as "up to date"), `LibraryUpdatePlanner`, `LibraryMirrorExporter` (keeps the tiny
`.manifest.json` but not the patch files). Do not move the check back into
`PatchApplier`: SeforimLibrary shipped v26 in schema 4, and a rejection inside
`apply` meant the launcher had already replaced a live v23 DB with the mirror's
v21 one — the user ended up on v22.

**A plan whose final version is not higher than the local one is `blocked`, with a
reason** — never an "update" that installs an older library (`followUpDelta` counts
toward that final version). Skipped only when `hasLocalVersionMeta` is false, where
there is no trustworthy local version and every DB is an improvement.

**Two version axes, never one constant.** `patch_meta.schema_version` is the
**patch.db format** version, not the logical DB schema. They travelled together
until DB schema 5 shipped in patch format 4, so `kSupportedDbSchemaVersion` (5) and
`kSupportedPatchFormatVersion` (4) are separate constants with separate predicates
(`isSupportedSchemaVersion` / `isSupportedPatchFormatVersion`) and separate filters. Collapsing them makes `PatchApplier` silently accept a format
it cannot apply. `patchFormatVersion` stays **optional** in the manifest even where
the producer always writes it: a manifest that fails to parse disappears from the
graph, and with it the version it leads to, so the offline machine reads "up to
date" forever. One download rejected at preflight is the cheaper failure — a
deliberate divergence from upstream, which fails closed.

**Adding a schema is one line in the map — plus the frozen list.** Freeze the
previous order as `kHashTableOrderSchemaN` before extending `kHashTableOrder`, and
keep `test/patch_tables_contract.json` byte-identical to the copy in
`Otzaria/otzaria_library_updater` (whose CI compares it against the producer). The
golden-hash tests pin schemas 2 and 3 by absolute value; if a frozen list drifts,
every historical patch fails preflight.

**`FastSha256` runs the hash through the OS crypto library, and that is not
negotiable.** `package:crypto` is pure Dart at ~50MB/s against ~1,225MB/s native
(CNG on Windows, CommonCrypto on macOS; everything else, including Linux CI, falls
back), and the logical hash reads the whole ~7.4GB DB per patch. Same algorithm,
identical digest — the Kotlin contract covers the **byte stream**, not the SHA
implementation — and a load-time self-test silences the native path if it ever
disagrees, since a wrong implementation would reject *every* update. Do not
"simplify" it back into `sha256.startChunkedConversion`, and do not change what is
fed into it.

**Every `FastSha256` caller must `dispose()` in a `finally`.** The native sink owns
memory the Dart GC knows nothing about — which is why `start` returns
`FastSha256Sink`, not a bare `ByteConversionSink`. `close()` disposes on the
success path; the `finally` covers a cancelled download, a network failure or an
SQLite error mid-scan, each of which otherwise leaks a 1MB buffer plus a CNG hash
object for the life of the process. Adding to a closed sink throws (like
`package:crypto`); without that guard it wrote into freed memory.

**The logical hash is verified once per chain, not per patch — and
`<db>.unverified` is what makes that safe.** The hash covers the whole DB, so
matching the *last* step's `toContentHash` proves every step before it; verifying
each step re-read 7.4GB per patch. `PatchApplier.apply` still defaults to
`verifyToHash: true` (upstream parity) and `LibraryUpdateApplier.applyDelta` turns
it off for every step but the last. The gap: a chain interrupted midway leaves a DB
that applied cleanly but was never verified — so each unverified step records its
version in `<db>.unverified`, and the next apply from that version runs with
`verifyFromHash: true`.

**The hash verification is never removed, never optional and never a setting.**
It is the only thing that stops a wrong database silently. A change that drops
the check in one place must add it in another, or mark the DB as needing a full
download. `PRAGMA synchronous` is untouched for the same reason.

**The verification pass is row reads through FFI — not SHA (2%) and not encoding
(0%).** Measured on the real DB: `link` takes 45s for 184MB (4 MB/s), so the time
goes on the *number of cells*, not the volume. The type bytes are therefore packed
into one integer per row (3 bits per column, 20 columns per int64, decoded in
Dart), which bought 28.3% of the pass with a byte-identical stream. Any further
gain must reduce FFI calls or rows read, not computation — and it needs a
whole-row read API `package:sqlite3` does not have (`||` is a text operator and
truncates at 0x00; `unhex(hex(a)||hex(b))` doubles the volume).

**Do not add an index to speed up the hasher's `ORDER BY`.** The unindexed sort
orders are `version_line(charCount, content, …)` and
`link_anchor(charEnd, charStart, label, …)`; an index must contain its sort
columns, and `content` alone is 749MB. The cheap variant (leading column only,
~25MB) is worth ~15s out of 168s while making every patch apply slower, being
rebuilt after every full download, and mutating a file Otzaria also opens. If it
is ever wanted it belongs in Otzaria's own `CREATE INDEX IF NOT EXISTS` list,
which `MyDatabase.withPath` re-runs on every open — a one-line request to them,
not a change here.

**Parallelising the hash read is blocked by the transaction, not the algorithm.**
`verifyToHash` runs inside the apply's open transaction, and an isolate with its
own connection cannot see uncommitted data. Moving the verification after `COMMIT`
would unlock it and give up the `ROLLBACK` that is the whole value of verifying.

**Measure on the real DB, in alternating rounds, before optimising anything
here.** Three of six planned optimisations rested on assumptions the measurement
disproved (the encoding was free, the sort columns were not the assumed ones,
`quick_check` was not redundant). Two traps cost a wrong answer each: a first pass
over a cold-cache DB reads ~6× slower and looks conclusive, and a benchmark that
computes byte volume inside the SHA step scans twice and reports SHA as 15× slower
than it is. A `PRAGMA` sweep was also run and is **not** usable — the machine
throttled mid-run — so no performance pragma was adopted.

**Blocking work must go to an isolate.** `LogicalContentHasher.compute` and
`PatchApplier.apply` are synchronous and can take tens of seconds. Wrap them in
`Isolate.run`, and have the closure call a **top-level** function taking only
primitives: a closure touching an instance field implicitly captures `this` (and
any live `HttpClient`) and throws `Illegal argument in isolate message: object is
unsendable`. This already caused one crash and one feature rollback.

**A UNIQUE-constraint collision in a patch is not our bug — but being stuck is.**
Ten columns are `UNIQUE` in the SeforimLibrary schema (`tocText.text`,
`author.name`, `source.name`, `topic.name`, `pub_place.name`, `pub_date.date`,
`generation.name`, `connection_type.name`, `book_version(bookId,versionTitle)`,
`alt_toc_structure(bookId,key)`) while `kPatchTablesInFkOrder` knows only the PK,
so `_runUpserts` emits `ON CONFLICT(<pk>)`, which misses a value that moved between
ids — and upserts run before deletes. The producer refuses to publish such a patch
(`assertNoSecondaryUniqueCollisions`); when one shipped anyway (issue #19, v18→v20)
the applier blew up mid-transaction. Do not fix this in the engine: it is
byte-identical to upstream and to the Kotlin applier, the same patch fails
Otzaria's own online update, and a DB that disagreed would fail `verifyToHash`
anyway. What we own is the exit — the message names the table and says a full
download is needed, and `LibraryUpdatePlan.fullDownloadFallback` carries the
mirror's full DB alongside every delta plan so
`applyUpdate(useFullDownloadFallback: true)` can recover. Never automatic: ~1.5GB
copied plus ~5.5GB extracted is the user's decision.

### 5.2 Filling the mirror (the online machine)

**`downloadAll` runs only the components that have something to bring.** It used to
run all three every time, so two new plugins also re-ran the app and library
downloads — minutes of progress bars for nothing. A component is skipped when
`provenUpToDateOnline` (`controllers/online_check.dart`) says the light check
*proved* there is nothing new: checked, no error, no update. A check that never ran
or that failed proves nothing and never skips — "no network" is not "no update".
The library is never skipped in personal-update mode, where the target comes from
the recorded DB version. The skip is announced in a snackbar; a silent one produced
the "why did it not download the plugins" confusion.

**Cancelling a download deletes what *that* download brought.** The button appears
next to the progress row only while a download runs, and `AppShell._cancelDownload`
rides the `isCancelled` callback every layer already takes, so it lands mid-asset.
`MirrorDownloadUndo` snapshots `mirror/library`, `mirror/companions`, `mirror/app`
and `mirror/plugins` before the first byte; on cancel it deletes created files,
restores any rewritten `.json` manifest (a new `releases.json` over deleted assets
is a mirror pointing at nothing), and truncates a resumed partial asset back to its
previous length so it stays resumable. Do **not** simplify this into deleting the
mirror — the ~1.5GB DB from an earlier run is exactly what must survive a cancel.
`mirror/apps` and `mirror/launcher` are deliberately outside the snapshot.

**The mirror keeps the last ten releases, not the whole patch history**
(`LibraryMirrorExporter.recentReleases` / `defaultHistoryDepth`). The full history
reached several gigabytes. Ten releases cover a machine that updates occasionally;
anything older falls back to the full-DB route, always present in the mirror.

**What goes into the mirror is decided by how long the update will take on the
*offline* machine, not by which files are smaller.** A patch pays a full-database
hash scan **per step** on top of the apply; the full route is one decompress.
v27 (September 2026) forced this: the library rewrote the DB end to end, its
patches came out at ~500MB each, and the mirror — which prefers keeping an existing
full DB — pulled **2.15GB** of them instead of a fresh 1.31GB full DB. The user paid
twice: an hour of downloading, then **64 minutes** of applying against ~2 minutes
for a swap. `ApplyTimeEstimate` (calibrated on measured runs) now estimates both
routes, and `LibraryMirrorExporter._dropSlowPatches` keeps a patch out when
applying **that one edge** already costs more than swapping the whole database;
whatever the drop turns into a dead end goes with it (`_dropUselessPatches`), old
full DB included.

- **It is a range, not "whichever is faster".** The patch route may be somewhat
  slower, because it saves ~1.3GB of download; it loses only when it is both more
  than twice as slow **and** at least ten minutes slower. Do not simplify back to a
  size comparison — an 8.5MB patch and a 585MB one start from the same fixed cost,
  which is what a size rule cannot see.
- **The verdict must be re-derivable, not remembered.** The first version measured
  only the cheapest single step into the latest version, so the decision survived in
  nothing but the deleted files; a month later an ordinary patch landed at the end
  of the chain, the measurement came back "in range", and the 585MB edge — with ten
  releases hanging below it — was downloaded again. Measuring the edge itself keeps
  a rejected edge rejected, with no state between runs and nothing to go stale.

**"Personal update" is the one setting that changes what a download brings.**
`AppSettings.personalUpdateMode` → `LibraryManager.personalUpdateMode` →
`LibraryMirrorExporter.export(fromVersion:)`: only the patches from the user's own
DB version upwards, and **no full DB** (`personalReleases`). It exists because
carrying ~1.5GB to update a machine already at v20 is what users objected to (forum
post 33695). Four things hold it together:

- **Default off, confirmed on enable.** Without the full DB the drive cannot serve
  a machine that has no Otzaria, and `LibraryUpdatePlan.fullDownloadFallback` — the
  recovery from a patch that does not fit — is `null`. The toggle warns first.
- **The version is read only on an explicit click**
  (`LibraryManager.captureLocalDbVersion()`, behind the button in `LibraryScreen`).
  A routine `checkForUpdate` deliberately does not record it: the **online** machine
  may hold its own newer Otzaria, and recording that would aim the download at v22
  while the offline machine sat at v20, with no patch route at all.
- **One record per machine, and the lowest wins**
  (`LibraryStateStore.knownDbVersions`, keyed by hostname + account). Someone who
  clicks on two machines gets a download serving both; `applyUpdate` raises that
  machine's entry so a machine that catches up stops dragging the floor down.
- **A machine that never registered is not a failed update.** The mirror is built
  for the registered machines' versions, so the *online* one — which only
  downloaded — has no route and the planner returns `blocked`; shown as a red
  "no continuous delta route", that is exactly what users reported as a broken
  library update. `LibraryModuleController` asks
  `LibraryManager.isRegisteredForPersonalUpdate()` first and reports
  `LibraryModuleStatus.personalTargetElsewhere` — an explanation with a way out,
  not an error. A registered machine still gets the real error.
- **"Nothing newer" does not touch the mirror.** `export` returns `false` and skips
  the manifest write *and* `_pruneStaleAssets` — otherwise an up-to-date machine
  would delete a perfectly good mirror.

**The apply-time rule runs in personal mode too, and it is the one thing that puts
a full DB there.** Skipping the full DB is the mode's entire saving, but skipping it
when the user's own chain costs far more — or when no chain reaches the latest
version — leaves them with the more expensive update. `export` runs the identical
decision with `fromVersion` set, so the route measured is **the user's actual
chain, every step of it**, instead of the per-edge verdict a mirror hands an unknown
machine; when it loses, the full DB is downloaded and the patches dropped. Hence a
release shipping **only** a full DB is no longer invisible to personal mode (it used
to be filtered out while the mode reported "up to date"), and the "turn personal
update off and download again" message now fires only at a real dead end.

**Only the patches are per-release; `seforim.db.zst` is downloaded once**, from the
highest version carrying one — the only full-DB asset `LibraryUpdateDiscovery` ever
selects offline, so a copy per release meant ~7.5GB nothing would read. After a
successful download, anything under `assets/` missing from the new manifest is
deleted (`_pruneStaleAssets`); the `.resume` sidecars of assets that *are* in it
survive, since they let a re-run skip a completed download.

**Every successful download ends with one sweep of the whole mirror**
(`MirrorJunkSweeper`, called from `AppShell.downloadAll`). Each component already
prunes itself, but only inside a download that brought it something: a skipped
component, or an `export` that returned `false`, prunes nothing — which is how a
drive ended up carrying full DBs of v20 *and* v21, and 5GB after a version bump.
A manifest that cannot be read means skipping that area, an empty keep-set being
"delete everything"; the sweep does not run after a failed download (assets the
manifest does not know yet); and `mirror/apps` and `otzaria-app/` are never
touched. It is silent by design — the freed bytes go to the log only.

**A re-run does not re-hash an asset it already proved.** Skipping the download is
not skipping the check: `downloadToFile` still verified `expectedSha256`, and on the
`alreadyComplete` path there is no stream to hash along with, so it read ~1.5GB back
off the flash drive — a minute per press of *download*, on a file nobody touched.
The sidecar's third line carries `sha256|size|mtime`, written when a verification
passes, and a complete asset whose mark still matches skips the hash. Do **not**
turn this into "the file is there, trust it": the skip decision (`_isCompleteOnDisk`)
is size-only on purpose, and the mark is what makes it safe — any write, a
re-published asset, or a different resume token brings full verification back. That
verification must keep happening on the **online** machine, the only place a corrupt
asset can be fetched again.

**Downloads are parallel *across files*, never *within* a file — and that is what
the server allows, not a preference.** Issue #17 asked for a download accelerator,
but GitHub's release CDN (`release-assets.githubusercontent.com`, an Azure Blob SAS
behind a proxy) **strips `Range`**: it answers `200` with the full body to every
`Range` — and `x-ms-range` — while still advertising `Accept-Ranges: bytes`
(verified five ways, August 2026). That is also why resume never works against
GitHub, which the code already knew (`_streamToFile` treats "ignored Range → 200" as
a restart). What the CDN *does* throttle is each connection separately: ~0.7MB/s on
one against ~2.1MB/s aggregate on four.

`DownloadScheduler` (root package, exported) is that pool, and it is a **shared
semaphore on purpose**: `LibraryManager` hands the same instance to
`LibraryMirrorExporter` and `CompanionAssetsMirror` and runs them concurrently (the
~509MB of companions used to queue behind the ~1.55GB DB), so the two stages
together never open more than four connections. `plugins_manager` cannot depend on
the root package (pure Dart vs. Flutter) and carries its own 40-line `runPooled`;
keep them in step conceptually, without a cross-package dependency. Three
load-bearing consequences:

- **The biggest asset starts first** (`jobs.sort` by size, descending) — with the
  ~1.55GB DB last, every other connection idles while it runs alone.
- **The byte counter is one aggregate** (`ByteProgressAggregator`), since in
  parallel there is no "current file". Each download gets a `slot()` that only moves
  **up**: an already-complete asset reports its full size and then re-hashes from
  zero on the same sink, which without the high-water mark dropped the bar.
  `LibraryModuleController` must therefore **not** null the byte fields on
  `onStage` — that blanks a bar which is in fact advancing.
- **The target is known before the first byte.** Both aggregators plan their total
  up front and `announce()` it, and bytes already complete on disk are deducted
  through `slot(existingBytes:)` — not by `markExisting` when the job reaches the
  queue, which in four-way parallelism is minutes in. That is why
  `CompanionAssetsMirror.sync` resolves all three assets (`_plan*`) before it
  downloads any. Without it the total appeared late and moved, and
  `downloadProgress` measured in assets meanwhile: two rulers, swapping mid-
  download. It now returns `null` rather than fall back to assets once bytes have
  flowed. Verification bytes are **not** download bytes — `onVerifyProgress` feeds
  the stage text (`exportVerifying`), never the meter.
- **A failed task stops new ones but still awaits the running ones** before
  rethrowing; a download left running in the background keeps writing into the
  mirror after `MirrorDownloadUndo` has cleaned it.

Deliberately *not* parallelised: `OtzariaAppMirror.sync` (two installers, ~6% of the
bytes, and its `onChannelStart` UI assumes one channel at a time) and the module
ordering in `AppShell.downloadAll`.

### 5.3 State that travels on the drive

State files live in `OtzariaData/`, i.e. on the drive, so anything recorded on one
machine arrives on every machine the drive reaches. The rule: **a fact about a
machine is keyed by that machine; a fact about the program is not.**

**`otzaria_install_state.json` is never trusted as-is.** `checkForUpdate` used to
accept it verbatim, which is why the launcher announced "Otzaria is up to date" on
two machines that had none (issue #19) and `launch()` ran a path that did not exist.
`OtzariaManager._verifyStoredState` checks that `launchPath` still exists *here* — a
**file** on Windows, an `.app` **directory** on macOS, hence
`FileSystemEntity.typeSync` and not `File.existsSync` — and re-reads the version off
the executable. The file is **not** deleted: it may be valid on the machine the
drive returns to.

**An absolute path in `library_state.json` is per-machine.** `customDbPath` was one
global record, so a drive that installed a library under the account `user` arrived
at the next machine still pointing at `C:\Users\user\AppData\Roaming\otzaria\books`;
a standard account cannot create a folder under `C:\Users`, so
`applyFullDownload`'s `createSync(recursive: true)` failed and the only way out was
picking a location by hand (issue #23). `LibraryStateStore` keys it under
`currentMachineKey()` — hostname **and** account name, since two accounts are two
`%APPDATA%` roots. A legacy global record is honoured only when it is absolute *for
this platform* and its parent exists here, which repairs drives in the field without
discarding the choice on the machine that wrote it.

**The applied release tag is per machine too** (`appliedReleases`, keyed the same
way — see §5.4). The legacy global field is ignored on read and deleted on write.

**The data folder is not configurable, and that is load-bearing.** `AppPaths`
resolves it next to the executable and `AppSettings` has **no path fields at all**.
Adding one back (an "advanced" data-dir setting, a USB target picker, an
`otzariaInstallPath`) breaks the premise that the drive carries everything.
`AppPaths.stateDir` is not a way around it: not user-visible, differs from `dataDir`
only when the drive refuses writes, and the mirror never moves off the drive.

**On macOS the folder goes next to the `.app` bundle, not inside `Contents/MacOS`**
(`AppPaths.executableRoot` climbs out of the bundle) — a folder inside the bundle is
invisible in Finder **and** is destroyed by the self-update, which replaces the whole
bundle. `LauncherInstallLayout._resolveMacOS` and `LauncherSelfInstaller` both assume
it. When the drive refuses writes, the machine-local state dir is
`~/Library/Application Support/`; `XDG_DATA_HOME` and `~/.local` are a Linux
convention and hide it from a Mac user.

### 5.4 Updating the library (the offline machine)

**The offline machine picks the fastest route it has, and that route can be the full
database.** `LibraryUpdatePlanner` used to take the delta chain whenever it reached
at least as high as the full route — but by then both assets sit on the drive, so
the only thing left to compare is how long the user waits. On the *same* target
version the `ApplyTimeEstimate` range decides and a far-slower chain loses
(`planFullDbFasterThanPatches` says so on screen); a chain reaching *higher* still
wins — freshness before speed — and with no full DB in the mirror there is nothing to
compare, so the chain stands. A local DB that is not on the mirrored chain lands on
`LibraryUpdatePlanKind.blocked` with a reason (`_fullOrBlocked` → `planNoFullDbEither`).

**DB location is discovered, not assumed — and Otzaria's own setting wins.**
`LibraryDbLocator` checks, in order: a path we saved ourselves; **Otzaria's
settings** (`key-library-path` + `key-library-folder-name` from its
`app_preferences` Hive box, exactly like `DatabaseConstants.getDatabasePath`); a
a library bundled by a legacy FULL install; `%APPDATA%\otzaria\books\`,
`%ProgramData%\otzaria\books\` (Windows) or
`~/Library/Application Support/otzaria/books/` and the system-wide equivalent
(macOS); finally `C:\אוצריא\`. Nothing found → `null`, and the UI must ask. Do not
hardcode a path — a previous confident claim about the "real" location was wrong,
and skipping Otzaria's setting silently updated the wrong file for anyone who had
moved their library. **The Hive box is read from a copy in a temp dir**
(`OtzariaSettingsReader`): opening it in place creates a lock file inside Otzaria's
folder and clashes with a running Otzaria; any failure returns `null` and the search
continues.

**Otzaria does not look in its own default — a fresh install must be written into
its settings.** `DatabaseConstants.getDatabasePath` falls back to `'.'` when
`key-library-path` is empty; `getDefaultLibraryPath` is only used by *its* own
download screen. A library we installed at the platform default was therefore
invisible to it (forum post 39342). `OtzariaSettingsWriter` is the one and only
thing we write into that Hive box, and only after a **fresh** install: the box is
opened in place (there is no other way), `key-library-path` is set to the DB's
folder with an empty `key-library-folder-name` — exactly what `EmptyLibraryBloc`
writes — and **only when the setting is still empty**. An existing value is the
user's choice and is never overwritten; it is also what decided where we
installed, so it already points here unless the user picked a different target.
A failure returns `false`, `applyUpdate` reports it through
`onLibraryLocationNotSet`, and the UI tells the user to point Otzaria at the
folder. Reading stays copy-only — do not turn the reader into an in-place open.
Five things make that in-place open safe, and each one is a bug that the review
of this feature caught before it shipped:

- **`crashRecovery: false`.** Hive's default is to "recover" a box it cannot
  parse by **truncating the file in place**, before a single byte of ours is
  written — on the user's live settings. The reader does not care (it works on a
  copy); here it would silently discard everything Otzaria ever saved. A box that
  does not open cleanly must throw and we give up.
- **Otzaria must be closed**, re-checked with `OtzariaProcessGuard` immediately
  before the write, not just at the start of the long update. Opening in place
  takes an exclusive lock on `app_preferences.lock` inside Otzaria's folder, and
  a failed attempt rewrites — on macOS, deletes — the lock file of a running
  Otzaria.
- **Verify `box.path`.** `Hive.openBox` resolves an already-open box **by name
  alone** and ignores the `path` argument, so a box left open on another root
  hands you the wrong install to write to.
- **One `putAll`, not two `put`s.** A crash between them leaves a new
  `key-library-path` beside a stale `key-library-folder-name`, i.e. a DB path
  that does not exist.
- **The settings root is `otzariaSettingsRoot`, never `otzariaDataRoots.first`.**
  With `%APPDATA%` missing, the first read root is `%ProgramData%` — a place
  Otzaria never reads settings from, so the write would vanish and still report
  success.

**An admin install defaults to `%ProgramData%`, not `%APPDATA%`.**
`LibraryDbLocator.isSystemInstall` mirrors `AppPaths.isWindowsSystemInstall`
(`system_install.marker` next to the exe, or an exe under `Program Files`;
portable never counts) and flips the order of the two Windows defaults. Getting
this wrong installs into a folder Otzaria does not search, with no warning —
`isKnownToOtzaria` considers both defaults known.

**A fresh install lands in those same places — never in the launcher's own folder.**
`resolveInstallDbPath()` answers "where does a *new* library go": the user's own
choice if there is one (**even when the file does not exist yet** — in a fresh
install that path is the *target*, so `resolveDbPath`'s existence check would be
wrong), otherwise Otzaria's setting, otherwise the platform default.
`checkForUpdate` used to point at `<dataDir>/library/seforim.db`, which for a
launcher on a USB drive installed the ~5.5GB library **onto the drive**; `<dataDir>`
survives only as the last-resort fallback. `isKnownToOtzaria(dbPath)` is the inverse
question — will Otzaria find this file by itself? A `false` makes `LibraryScreen`
demand explicit confirmation: any location is allowed, but only after a dialog
saying the user must point Otzaria's own library-location setting at it.

**Portable Otzaria moves everything.** A `portable.marker` next to Otzaria's
executable puts its whole data root in `otzaria_data` beside it. Detecting that needs
Otzaria's launch path, which is why `AppShell.checkAll()` runs the app module's check
**before** the library module's, sequentially.

**There is no backup of `seforim.db`, and no setting for one.**
`LibraryDbRecoveryService` writes a marker (`<db>.applying`) and nothing else. A
second ~1GB copy doubles what the drive must hold while adding no real safety: the
delta route is one SQLite transaction that rolls itself back, and the full route
extracts to `<db>.new`, verifies it (`quick_check` + version), and only then swaps.
Do not reintroduce a copy-before-apply step or a `backupsToKeep` setting.

**The full-download route streams; it must never decompress in memory again.** It
used to hold ~1.1GB as a `Uint8List`, plus a second copy when that was sent to an
isolate to be written. It is now download → file, `ZstdFileDecompressor` →
`<db>.new`, then rename.

**`PRAGMA quick_check` on that route stays, and it is not redundant.** It costs a
measured 111s, and "the sha256 of the compressed asset already proves it" is
false: there is **no** sha256 on the extracted ~7.4GB. Only patches carry
`uncompressedSha256`; a full-DB release ships no manifest at all, just
`ReleaseAsset.digest` of the compressed file — and `_sha256FromDigest` returns
`null` when even that is missing or not in `sha256:` form. So `quick_check` is the
only end-to-end check on the file as written, catching exactly what libzstd cannot:
a disk-write fault. Otzaria's own `applyFullDownload` does the same thing. Buying
the 111s back means asking `Otzaria/SeforimLibrary` to publish
`uncompressedSha256` for the full-DB asset (native sha256 over 7.4GB is ~5s, and
it also catches a single changed byte) — a producer-side request, not a change
here.

**Only `<` counts as a size mismatch after extraction.** The bytes written are
compared against the zstd frame's declared size, which guards the file *as it
landed on disk* (an antivirus that truncated it, a removable filesystem that lied
about success). It must not be `!=`: `contentSizeOf` reads the first frame only,
so a multi-frame archive legitimately produces more. A test pins the distinction.

**The swap is two renames, not delete-then-rename.** `<db>` → `<db>.old`,
`<db>.new` → `<db>`, then delete `<db>.old`. A rename costs nothing and needs no
extra space, and it removes the window in which *no* database exists — an
interrupted `deleteSync` + `renameSync` left the user with no library and an orphaned
`<db>.new` the locator could not find, since it only looks for `seforim.db`. If the
second rename fails the first is rolled back. For the same reason `-wal` / `-shm`
are deleted only *after* the swap: they belong to the old DB, and deleting them
earlier would discard committed transactions from a hot journal if the swap failed.
**The process guard runs again immediately before the swap** — the download and
decompression take many minutes, and on macOS `unlink` on an open file succeeds.

**A DB update can ship without a version bump.** SeforimLibrary sometimes
re-publishes a corrected `seforim.db.zst` under the same `db_version`, which the
version comparison reads as "up to date". `LibraryUpdatePlanner` therefore also
compares the applied release tag (`LibraryStateStore.loadAppliedRelease()`) — but
only when that tag is *known*: a DB not installed by this launcher has none, and
guessing would offer a ~1GB download on every launch. Two traps, both once live:

- The tag must be `LibraryDiscoveryResult.latestContentTag`, the newest release —
  **not** `fullDbReleaseTag`, the release that happens to carry `seforim.db.zst`. A
  patches-only release is the newest while the full DB stays on an older tag, so
  recording the carrier told every up-to-date machine "the content changed" and
  offered ~1.4GB — printed as *"the DB will be updated from version 22 to version 22"*.
- The record is **per machine and carries the `db_version` it was written for**. A
  global tag travelled with the drive, so one machine's tag was compared against
  another machine's DB, and a DB that Otzaria updated by itself kept a tag from a
  version it no longer held.

**The library update is not just `seforim.db`.** Otzaria refreshes three companion
files from the network on every update (`CompanionAssetsService`): the Talmud Bavli
PDFs, the otzar-HB catalog and the fuzzy-search dictionary. An offline machine has no
network, so they ride in `mirror/companions/` and `CompanionAssetsInstaller` writes
them right after the DB — same targets, same version markers, same best-effort
semantics (one failing item never fails the others or the DB update that succeeded).
Sources and markers are tabulated in `library_manager/README.md`.

**A version marker is not the content it stands for — and the completeness check
must never err towards "incomplete".** The Talmud predicate asked only for
`תלמוד בבלי/.version`, so a folder left holding one PDF of the whole Shas read as
up to date forever (issue #33). It now also weighs the folder, against our
`.version.contents` spec or, lacking one, a deliberately crude floor. Erring the
other way is worse than the bug it fixes: "incomplete" means offering a ~450MB
re-extract on every launch. Both rules and their traps are in
`library_manager/README.md`; `CompanionAssetsInstaller._talmudContentsComplete`.

**A DB updated from outside leaves Otzaria's search index stale, and the fix is a
deep link — not a file.** Otzaria re-indexes exactly the books `PatchApplier` reports
in `booksTouched` (or runs `ReconcileIndex` after a full download); neither runs when
*we* write the DB, and startup indexing only adds *new* books, so search in a changed
book returns old content. We asked the developers to read a file; what they shipped
instead (`dev`, `78f395f3`, [issue #734](https://github.com/Otzaria/otzaria/issues/734)) is
**`otzaria://library/reindex`** — parameterless, reloads the catalogue and runs
`StartIndexing` + `ReconcileIndex` even when their "auto index update" setting is off.
Three things about our half:

- **`.otzaria-external-update.json` is our own pending marker**, not a message to
  Otzaria. `applyUpdate` writes it next to the DB, it survives restarts,
  `pendingReindexRequest()` reads it, and `clearReindexRequest()` deletes it **only
  after the request was delivered** — clearing it on the *offer* or on a failed
  launch leaves the index on old content with nobody aware. Hence
  `onLaunchUriDelivered` fires after `launch()` returns.
- **The link is handed to the detected executable as an argument**
  (`otzaria.exe <url>`, `open -a` on macOS), not to the OS protocol handler — a
  portable install never registers the scheme. A running instance receives it through
  Otzaria's single-instance forwarding. `OtzariaModuleController` takes an injectable
  `OtzariaLauncher`: without that seam, any test touching `launch()` starts the real
  Otzaria on the machine running the suite.
- **Every normal "launch Otzaria" carries a pending request along** — a user who
  opens Otzaria from a desktop shortcut never delivers it, and that gap is the
  accepted cost of a link-based fix. Closing it from our side is not an option:
  `booksDone` and the tantivy index are Otzaria's internal structures, and writing
  into them from outside bypasses its mechanism exactly as unpacking an
  `.otzplugin` by hand bypasses the plugin registry.

### 5.5 The Otzaria app: detect, install, version

**Channels map to GitHub's `prerelease` flag** — a plain release is "stable", a
pre-release is not, for both library and app. For the **app** this is not a setting
that picks what to download: the download always fetches **both** — the latest
stable, plus the latest pre-release *only when it is newer than that stable*
(`OtzariaReleaseClient.fetchChannelReleases`). Both installers travel on the drive
and the offline machine picks (`AppSettings.preferAppPrerelease` →
`OtzariaManager.preferPrerelease`) with no network. Do **not** turn this back into a
single-release download. Two consequences to preserve: a pre-release *older* than the
newest stable is never mirrored (no real choice, wasted space — so `OtzariaScreen`
shows the choice only when `hasChannelChoice`), and when the first page of 50
releases holds no plain release at all, only the pre-release is mirrored and is
offered **labelled** as such (replacing the old `NoStableReleaseException`).

**Version strings need normalizing before comparison.** An installed build reports
`0.9.96` while the tag is `0.9.96+736`; `OtzariaUpdateCheckResult` strips a leading
`v` and everything after `+`. Without it every launch saw a phantom update and
re-downloaded ~73MB.

**"Different tag" is not "newer tag".** `updateAvailable` used to be pure inequality,
so a user who had installed 0.9.97+90970 himself while the mirror held 0.9.96+736 was
offered a *downgrade*. `compareVersions` orders base components **numerically** (so
`0.9.9 < 0.9.10`, which a string compare gets backwards) and ranks a pre-release
suffix below the same bare base; `installedIsNewer` suppresses the offer. The one
downgrade left is a deliberate channel switch — when the installed tag *is* the other
mirrored channel's tag, the user asked for it (`OtzariaChannelPair` only ever holds a
prerelease newer than the stable). Two different suffixes on one base are incomparable
and compare as 0.

**The FULL package is gone; a first install now runs the app wizard and then the
library.** `otzaria-<ver>-windows-full.exe` was the ordinary installer with the
library inside — i.e. a second copy of the ~1.5GB already on the drive, for one
saved click. `HomeScreen._confirmAppInstall` offers both when
`otzaria.currentVersion == null && library.isFreshInstall`, and
`_installLibraryAfterApp` runs the second half.

- **App first, never the library first.** Where the DB goes follows what the wizard
  chose: a portable install keeps it beside the exe, an ordinary one under
  `%APPDATA%`. Before the wizard there is no exe for `LibraryDbLocator` to hang the
  portable-marker branch on, so the target would be a guess — and whoever picked
  "portable" would get 1.5GB where Otzaria never looks. Hence the
  `library.checkForUpdate()` between the two halves. A system-wide install cannot
  arise here: `otzaria.iss` sets `PrivilegesRequired=lowest` with overrides allowed
  from the command line only.
- **Otzaria is closed automatically after the wizard.** Its finish page ships a
  checked "launch Otzaria" box, and `/NOLAUNCH=1` cannot clear it — that `[Run]`
  entry has no `Check:`, while `ShouldLaunchAppAfterSilentInstall` gates only the
  silent one on `WizardSilent`. A running Otzaria locks `seforim.db`, so
  `OtzariaProcessCloser` asks it to quit (`taskkill` without `/F`); safe precisely
  here, because it opened two seconds ago with nothing to save. The manual dialog
  appears only if it survives.
- **A stale FULL file on an old drive is swept.** `OtzariaAppMirror.staleFullPackages()`
  finds it, `sync()` deletes it, and `check.hasStaleFullPackage` forces the app module
  to run even when the online check proved nothing is new — otherwise "nothing to
  download" would skip the module and leave 2GB there forever.
- It never solved issue #21 either: it carried only the ~2MB WebView2 *bootstrapper*,
  which downloads the runtime from the internet. See §5.8 for what #21 actually needs.

**When the *user* installs, Otzaria's own wizard opens**
(`update(check, useWizard: true)` → `OtzariaInstaller.installWithWizard`, no flags
but `/LOG=`). Its two pages carry
decisions only the person at the machine can make: which folder, and whether to
create a desktop shortcut. `/VERYSILENT` deleted both pages — that is what the report
"it didn't open the installer's dialog and made no shortcut" was. Do not "fix" it back
with `/MERGETASKS`; overriding that choice is the bug.

**`/DIR=` is different and *is* passed when an install already exists.** Inno's
`/DIR` only sets the *default* on the destination page (hidden anyway on an update),
so the new version lands in the existing folder instead of beside it, and the user can
still change it when the page shows. Inno's own `UsePreviousAppDir` is not enough — it
needs Setup's uninstall record, which a portable or manually-adopted install lacks.
The dir we passed also **outranks detection** when deciding what got installed; only
if no executable is there does detection answer.

**Auto-install stays silent** (`_autoInstallIfEnabled` passes `useWizard: false`): a
wizard waiting for a click is not "install by itself", and that is the only path where
`/MERGETASKS=desktopicon` still does anything.

**A silent install must pass `/NOLAUNCH=1`, and the library goes first.**
`otzaria.iss` carries a *second* `[Run]` entry firing **only** under `WizardSilent`,
compensating for the finish-page one that `skipifsilent` drops — so a silent install
opened Otzaria, which locks `seforim.db`, which blocked the library update right
after it (`OtzariaIsRunningException`). The flag is the iss's own kill switch, and it
gates **only** that entry: the finish-page one has no `Check:`, so an install run with
the wizard launches Otzaria whatever we pass. `_autoInstallIfEnabled` therefore runs
the **library before** the installer and re-probes with `refreshProcessState()` before
each of its two actions — `_otzariaIsRunning` is a value captured earlier, and the
periodic refresh only runs while Otzaria is already open.

**A skipped auto-install is announced.** Otzaria being open blocks both paths, and the
skip used to be silent — which reads as a setting that does not work.
`_autoInstallIfEnabled` collects `skippedWhileRunning` and ends in a
`showSingleActionDialog`; a startup snackbar disappears before it is read, and this one
asks the user to do something.

**Auto-install only ever *updates*; a first install is never automatic.** Both paths
are gated (`!isFreshInstall` for the library, `currentVersion != null` for the app) and
the combined first install is not in `_autoInstallIfEnabled` at all — it opens a wizard
and waits for Otzaria to close, so it is a user click only. The reason is the *target*:
a first install has no certain one. `LibraryDbLocator` finds a moved library only
through Otzaria's `app_preferences.hive`, and `OtzariaSettingsReader` returns `null` on
**any** failure — an unreadable box and "never moved it" are the same answer. That
guess then becomes `saveCustomDbPath` in `_finishDbUpdate`, i.e. recorded as the user's
own choice and checked *before* Otzaria's settings from then on. So one unreadable box
meant ~5.5GB written where Otzaria does not look and a launcher permanently locked onto
the wrong path. The home-screen card already offers the button, which is where that
decision belongs.

**Cancelling the wizard is not a failure.** `OtzariaInstallCancelled` (Inno exit 2/5,
plus 1223 = UAC refused) and `OtzariaWizardStillOpen` (the process returned before the
install is on disk — routine when Inno elevates and hands off to an elevated child)
surface as `OtzariaModuleController.noticeMessage`, a plain snackbar. Never route them
through `errorMessage`: painting the user's own choice red makes people think the
program broke.

**On macOS, refuse to install while Otzaria is running.** The install is a
whole-bundle swap followed by deleting the previous bundle, and `unlink` succeeds on
files a process holds open — so a running Otzaria kept running without its resources
and crashed on the next thing it loaded. `OtzariaManager._refuseIfRunningOnMac` blocks
`update` on that platform only; on Windows Inno decides what to do with a locked file.

**macOS `.app` extraction uses `ditto`, not `unzip`.** Otzaria's macOS build is ad-hoc
signed; `unzip` / `package:archive` destroy the symlinks and xattrs, and therefore the
signature, and macOS refuses to run it.

**Process detection uses exact matching.** `OtzariaProcessGuard` looks for
`otzaria.exe` via `tasklist` and the Hebrew process name `אוצריא` via `pgrep -x`.
`pgrep -f` or a substring match would also match the launcher itself (its path
contains "otzaria") and block every DB update.

**Two packages match that process, and their name lists must agree.**
`OtzariaProcessGuard` (`library_manager`) blocks DB updates while Otzaria is open;
`RunningOtzariaLocator` (`otzaria_manager`) reads that process's *path* to learn where
Otzaria is installed — the authoritative answer, tried before the guesses in
`_autoDetectDirs`. The packages do not depend on each other, so
`launcher_app/test/process_names_test.dart` asserts the two `processNamesFor` lists are
identical; drift gives "we can see Otzaria is running, yet we cannot tell where it is
installed". The locator answers only for the *app* directory — `seforim.db` lives under
`%APPDATA%` regardless and stays `LibraryDbLocator`'s job.

**The Windows uninstall registry beats every guess.** `WindowsInstallRegistry` reads
`InstallLocation` from the Inno entries under `…\CurrentVersion\Uninstall` (HKCU, then
HKLM 64- and 32-bit), so an install in a folder nobody guessed is found *with Otzaria
closed*. Only the **directory** comes from there; the version is still read from the
exe, because `DisplayVersion` records what the installer wrote, not what is on disk
now. The scan costs ~200ms, so `checkForUpdate` builds `_autoDetectDirs` only when
nothing is known yet.

**Only `DisplayName` identifies an entry in that registry.** Matching on
`InstallLocation` too let any third-party program in a path merely mentioning
"otzaria" into `_autoDetectDirs`, where `sharedDir: false` means no further identity
check. Both real Inno entries write a `DisplayName` ("אוצריא גירסה …"), verified on a
real machine. `UninstallString` is only a fallback for the *directory*, and must be
parsed as a command line, not a path: `MsiExec.exe /X{GUID}` through `p.dirname` yields
a **relative** string, because `package:path` treats the `/switch` as a path segment.

**Where a fresh Windows install goes is the installer's call, not ours.**
`installFromFile` passes `/DIR=` only when updating an install we already know about;
for a fresh one it passes none and finds the result through detection. This repo once
recorded `{autopf}\Otzaria` as "the installer's real default, verified with the Otzaria
developers (2026-08-07) — not a guess", while `installer/otzaria.iss` in
`Otzaria/otzaria` says `DefaultDirName=C:\אוצריא`. A copied default drifts from the
thing it copies. `_windowsRealDefaultDirs` (`{autopf}\Otzaria`,
`%ProgramFiles%\Otzaria`, `{Program Files}\אוצריא`, `C:\אוצריא`) is a **detection**
list only, and `resolveDefaultInstallDir()` is a Windows *display* value plus the real
macOS target (`/Applications`, falling back to `~/Applications`) — never an install
argument on Windows. Verify installer facts against **`Otzaria/otzaria`** (what
`OtzariaReleaseClient` downloads); `Sivan22/otzaria` has a similar-but-different
`installer/` folder, and reading the wrong one produces confident wrong answers. This
is a *different* directory from where the library DB lives (`%APPDATA%\otzaria\`) —
don't conflate them when debugging "Otzaria not detected". The manual
"בחירת מיקום ידנית" picker (`adoptInstallDir`) is the fallback for anything the paths
do not cover.

**Never return the first `.exe` in the install folder.** `crashpad_handler.exe` ships
next to `otzaria.exe`, sorts before it, *and* carries its own version resource
(0.15.4) — so reporting the first match produced a confident, completely wrong
"installed version" plus a `launchPath` that ran the crash handler. A name match
(`OtzariaAppLocator.mentionsOtzaria`) wins outright; known Flutter helper exes are
excluded; anything else is only a fallback, kept so a rename of the app's exe does not
break detection.

**A name match must never match the launcher itself.** The Windows stub is
`עדכוני אוצריא.exe`, whose name *contains* `אוצריא` — so the rule above made the
launcher adopt itself the moment a scanned directory contained it (realistic for
`C:\אוצריא` and `%LocalAppData%\Programs\Otzaria`), read its own version resource as
"the installed Otzaria", and re-run itself on `launch()`. **The same file travels
under a second name:** GitHub strips non-ASCII from asset names, erasing an all-Hebrew
name down to `default.exe` (what `V1` and `v0.1.1` published), so the `publish` job
uploads it as `Otzaria-Updates.exe`. Both names are excluded
(`OtzariaAppLocator._ourOwnExeNames`, plus a `Platform.resolvedExecutable` check) and
both are tie-breakers in `LauncherInstallLayout`. This is the file-scan twin of the
`pgrep -f` hazard.

**…and on macOS the same rule is about the bundle.** `PRODUCT_NAME` is
`Otzaria Launcher`, so `Otzaria Launcher.app` contains "otzaria" and
`nameLooksLikeOtzaria` says yes — while `/Applications` is both an auto-detect
directory and where you get an app by dragging it. `_findMacAppBundle` skips any
bundle `isOurOwnExe` matches **and** any bundle `Platform.resolvedExecutable` sits
inside (on Windows it is the same file; here the executable is buried in
`Contents/MacOS`).

**The Windows exe scan is breadth-first and depth-capped**
(`defaultWindowsMaxDepth`), like the macOS one: `Directory.list(recursive: true)` has
no defined order, so a nested exe could beat the one at the install root and the answer
differed between machines; and `C:\אוצריא` is *both* an auto-detect install dir and a
common `seforim.db` location, so an unbounded scan walked a ~1GB books tree on every
`checkForUpdate()`.

**The mirrors are read with a platform filter, because the drive travels.** A drive
filled on Windows carries an Inno `.exe`, and a macOS launcher would hand it to `ditto`
or `Process.run` it and fail with something that explains nothing.
`OtzariaAppMirror.load` drops an entry whose `installerKind.targetPlatform` is not this
one, and `LauncherUpdateMirror.load` drops an asset failing
`LauncherReleaseClient.matchesPlatform` — both then read as "no mirror, run the
download", which the UI already knows how to say. `OtzariaAppMirror` takes
`OtzariaTargetPlatform?` and uses `detectOrNull`: the tests run on Linux in CI, where
`detect` throws.

### 5.6 Plugins

**Install-state matching uses `manifestId`, not the catalog `id`.** The `id` from
`/api/plugins` is the website's database id; Otzaria installs under
`plugins/installed/<manifest.id>/`. `manifestId` comes from the `manifest.json` inside
the downloaded `.otzplugin` (`PluginManifestReader`, BOM-stripped like
`LogicalContentHasher`). Compare by catalog id and *nothing* is ever detected as
installed. A plugin whose file is not downloaded yet correctly reports
`PluginInstallStatus.unknown` — not an error.

**Otzaria has two on-disk layouts, and `InstalledPluginsScanner` must read both.**
Older installs use `installed/<manifest.id>/current/`; newer ones
`installed/<manifest.id>/.release-<hash>/` with no `current`. Reading only `current/`
left every recently installed plugin out of the map, so the store showed it as never
installed and the "only what is not installed" toggle did not hide it. `current` wins
when both exist; among several `.release-` dirs the most recently written is active.

**The mirror carries the plugin build that will *run*, not the newest one published.**
Every build declares `compatibleWith` (minimum Otzaria version) and `maxAppVersion`,
and `/api/plugins` returns the whole `versions[]` history.
`plugins_manager/lib/src/services/plugin_compatibility.dart` is a 1:1 port of the
site's `src/lib/pluginCompatibility.js`: pick the **highest build whose range contains
the app version**. Before this the sync always fetched the live build, so an offline
machine got plugins that would not load — 8 of the 37 plugins on the site required a
newer Otzaria than the latest stable when this was written.

- **The drive's own app versions decide what is downloaded.**
  `PluginsManager.sync(appVersions:)` gets the stable release, the newer pre-release
  when there is one, and whatever Otzaria is installed here, and fetches a build for
  each; the launcher passes them from `OtzariaModuleController`. An **empty** list
  means "nothing to filter against" and falls back to the live build, which is what a
  drive with no app mirror gets.
- **One file per build**, `files/<pluginId>/plugin-<version>.otzplugin`, with
  `StorePlugin.localFiles` a `version -> file` map. A build no longer targeted is
  deleted (`pruneUnusedFiles`) so the drive does not accumulate a layer per Otzaria
  update — but **never on a cancelled sync**, where the catalog is still the old one
  and the cleanup would delete what did come down. A failed download keeps the older
  build: an old build that runs beats nothing.
- **`versions[]` is stored in `catalog.json`.** The resolution must run on the offline
  machine against the Otzaria installed *there* — one drive serves several machines.
  The site's `?appVersion=` would bake one machine's answer into the mirror, so it is
  deliberately unused.
- **None of this is visible to the user** — the store simply shows the version that
  will be installed. The exception is `PluginInstallStatus.incompatible`: with no
  compatible build the install button is disabled, and a disabled button with no word
  reads as a fault. Those plugins go into `PluginSyncOutcome.incompatible`, written
  **to the log only**, so "why is that plugin not on the drive" can be answered.

**A sync plans before it starts, and its counter shows only real work.**
`PluginMirrorSync._plan` decides per plugin what is missing (metadata comparison +
file-existence checks, no network), and only those enter the loop — so
`PluginSyncProgress.total` is "how many are being downloaded", not the size of the
store. `PluginSyncOutcome` carries `fetched`/`skipped`/`failed`, because the catalog
alone reads the same whether nothing needed downloading or everything failed; `failed`
is also what keeps `PluginsModuleController.onlineStatus` honest.

**A sync downloads only what changed — images included.** The `.otzplugin` was always
skipped on a version match, but every image and screenshot of *every* plugin was
re-fetched each sync "because they are small" — over a whole store, that is the store
downloaded again for one plugin that moved. `catalog.json` records where each asset
came from (`remoteImageUrl`, `remoteScreenshotUrls`), and an asset is fetched only when
that URL changed, when `updatedAt` moved (the site can swap an image under the same
URL), or when the file is missing. Screenshots are all-or-nothing — their names are
`screenshot-<index>`, so a changed list must re-fetch the whole series or the contents
shift between indices.

**An empty recorded URL means "old catalog", not "changed"** (`_sameSource`). A mirror
written before those fields existed has none of them, and treating that as a difference
re-downloaded every image on the first sync after the upgrade. The comparison falls
back to `updatedAt` plus the file being on disk, and the URL is written into the
catalog even when nothing is downloaded, so the migration closes itself.

**The store's *structure* sync must never be fatal.** Since the site's redesign
(managed categories, curated "featured" plugins, editable home texts),
`PluginMirrorSync` also fetches `/api/plugins/store-home` and
`/api/plugins/categories/<slug>`. Only `/api/plugins` itself may throw — if the
structure calls fail, the sync emits a `warning` and keeps the categories the mirror
already has. Wiping them would silently degrade an offline machine that had them.

**Installation is protocol-only:** `otzaria://plugin/install-local?path=`. Do **not**
extract the `.otzplugin` ZIP into Otzaria's folders ourselves — Otzaria keeps an
internal registry beyond the `installed/` directory, and a manual unpack bypasses it.
`install-local` reads from disk and needs no network; the older `install?url=` does and
is deliberately unused.

**Everything about plugins hangs off the launch path the launcher already detected**
(`OtzariaModuleController.launchPath`). Two consequences, both load-bearing for a
**portable** Otzaria:

- `InstalledPluginsScanner` derives the plugins folder from it —
  `<exeDir>/otzaria_data/plugins` when `portable.marker` sits next to the executable
  **or that data folder already exists** (deliberately wider than `LibraryDbLocator`,
  which demands the marker), otherwise `%APPDATA%\otzaria\plugins`, then the
  system-wide install. The marker and data-folder names are duplicated in
  `plugins_manager` and `library_manager`;
  `launcher_app/test/portable_paths_test.dart` verifies they never drift.
- `PluginDirectInstaller` hands the `otzaria://…` URL straight to that executable as
  its first argument — exactly what the registry handler would do. A portable install
  never registers the scheme, so going through the OS was a guaranteed "make sure
  Otzaria is installed" failure. Without a known path the OS handler is the fallback.

Because the launch path is known only after `OtzariaManager.checkForUpdate`,
`AppShell.checkAll()` re-scans installed plugins right after it
(`refreshInstalled`), and so does the manual "pick the install folder" flow. Dropping
those calls leaves the store showing a scan of the wrong folder until the next launch.

**The standalone store app's `Data\` is our plugin mirror with one path edit, not a
repack.** `Otzaria/otzaria-plugin-store` is a JS port of this very package — same
`PluginMirrorStore`, same `StorePlugin.toJson` — so `catalog.json` is identical on
both sides. The only difference is where the files sit: ours at
`<mirror>/plugins/files/<id>/…` (catalog paths `files/<id>/…`), its at
`Data\plugins\<id>\…` (paths `<id>/…`). `StoreAppExporter` copies each asset and
rewrites its path relative to `filesDir`; an asset that resolves outside it is
**dropped, not sanitized** (a corrupt catalog is the only way it gets there). The
catalog is written **last**, so an interrupted copy never leaves a store describing
plugins whose files are missing.

**Only the basic `.exe` is mirrored — never the `bundle` tag.** That release carries
109MB of plugins we already have on the drive, one version staler.
`isStoreAppReleaseTag` (`^v?\d+$`) rejects `bundle` outright and
`isBasicAppAsset` rejects `*-Full.exe`.

**The store program has its own peek and its own skip, separate from the catalog's.**
`PluginsManager.syncStoreApp` takes the release `peekStoreApp` already found and
does nothing without one, so a download with nothing new never reaches GitHub at
all. The two cannot share a flag: the catalog comes from otzaria.org and the
program from GitHub, so one being unreachable says nothing about the other, and
`skipPlugins` (dozens of site calls) must not be decided by a 600KB file.
`hasCatalogOnlineUpdate` drives `skipPlugins`, `hasStoreAppOnlineUpdate` drives
`skipStoreApp`, and `hasOnlineUpdate` is the union — the home screen reads the
union, or a new store-program version would not even show the download button.
A failed store-app download is a log line, never a failed download run.

### 5.7 Custom apps

**A custom app learns how to detect itself.** The form cannot ask "where will this
install" or "what is the exe called" — on the online machine, where the record is
created, the program is not installed. `InstallLearner` snapshots the uninstall
registry *before* running the installer and looks for the key that was born. Five
load-bearing details:

- **A re-install does not create a new key**, and that is the common case. The first
  version required a newly-born key, so it learned nothing precisely for the users who
  already had the program working (verified on real hardware against `KleiKodesh`).
  The pick runs in three tiers — a key that was **born**, a key that **changed** while
  we installed, then an **existing** key whose name matches. The last two require a
  name match, since browsers and system updaters rewrite entries in the background;
  and any name match beats a nameless guess, so the "single fresh entry" fallback runs
  *last*, or a companion entry dragged along by the installer would be adopted over
  the program's own updated entry.
- **Exit code 0 does not mean the install finished.** Inno's `setup.exe` extracts a
  temp copy and launches a second process (certainly when it elevates), so the entry
  can be written after the process we ran returned. Hence a **bounded re-poll** (60s,
  backing off from 500ms to 4s, because the scan itself costs ~200ms). "No entry
  appeared" is normal — a portable program registers none.
- **The learned directory is never written to the record.** `descriptor.json` travels
  on the drive, so an absolute path in it is exactly the `otzaria_install_state.json`
  disease (§5.3). It goes to the per-host `locations.json` — for free, because
  `install` calls `detectInstalled` on the freshly-learned record. Only `exeName` and
  `registryDisplayName` — facts about the program, not the machine — reach the record.
- **`registryDisplayName` is a pattern, never the raw `DisplayName`.**
  `MyApp 1.4.2 (x64)` is two bugs at once: parens and dots are regex metacharacters,
  and the embedded version stops matching the moment the program updates.
  `RegistryDisplayNamePattern` cuts the tail from the version on, escapes the rest,
  anchors at the start and adds a lookahead so `Git` does not swallow `GitHub
  Desktop` — the trap `GithubAssetPattern` exists for. Compile through
  `RegistryDisplayNamePattern.compile`, never a bare `RegExp(...)`: a
  `FormatException` inside detection is swallowed upstream, and the result was a
  program reporting "not installed" forever.
- **Both registry seams are needed together.** `installDirs()` throws the
  `DisplayName` away and filters out an entry whose directory does not exist — for a
  before/after diff that entry *is* the evidence. `entries()` keeps both plus the key
  name, the stable identity. `UninstallEntriesLookup` learns the pattern;
  `UninstallDirLookup` turns it into detection. With only one wired, the record
  updates and the app still reports "not installed".

**Never pick the first `.exe` when learning either.** The learned exe name goes
through `OtzariaAppLocator.findIn(nameMatches:)` — the same verified scanner with an
injected name predicate. The form's suggestion used to take the first `.exe` from
`listSync()`: undefined order, no `unins*` exclusion, no Flutter-helper exclusion. In a
real Flutter app folder that returns `crashpad_handler.exe` (§5.5).

**The record carries file *names*, never paths — icons and screenshots
included.** `AppDescriptor.iconFile`/`screenshotFiles` name files inside
`apps/<id>/media/`, and the full path is rebuilt at runtime (`CustomAppMedia`).
An absolute path in a file that travels on the drive is the
`otzaria_install_state.json` disease (§5.3). The names also arrive from another
machine, so `_safeFileName` rejects anything with `..`, a separator or a colon —
the same boundary `AppDescriptorId` draws for the folder name. These fields are
optional additions, so `schemaVersion` deliberately stayed 1, exactly as
`install.portable` did.

**Media is rewritten whole, through a staging directory.** Screenshot names are
their order (`screenshot-1`, `screenshot-2`…), so swapping two images that
already sit in `media/` would overwrite one halfway through.
`CustomAppMedia.save` copies everything into `media/.staging` first, clears the
folder and only then moves them in — which is also why a missing source file
fails *before* anything existing is deleted. `CustomAppsManager.saveMedia`
starts from `descriptor.withoutMedia()`, since `copyWith` cannot clear a field
and a removed icon otherwise stayed recorded, pointing at a deleted file.

**A category is deleted from the apps too, not only from the list.**
`CustomAppsManager.removeCategory` strips the slug from every descriptor;
without it a record kept pointing at a category that no longer exists. The UI
survives such a slug anyway — `CustomAppsController.uncategorizedApps` counts
only *known* slugs, so an app assigned on another machine to a category this
drive does not have is shown rather than hidden. The slug itself never reaches
the user: a Hebrew category name leaves nothing latin, so it falls back to
`category`, `category-2` (`CustomAppCategory.slugFor`).

**`CustomAppsScreen` listens to its own controller**, like `PluginsScreen` and
unlike the version before the card grid: the open category lives in the
controller, and a tap in the side rail rebuilt nothing when the screen relied on
`AppShell` rebuilding it from outside. Both listeners are fine; the screen is
still built lazily on first visit, which is what makes the pending dialog fire
there.

### 5.8 Packaging, distribution and self-update

**There is no Windows installer — the distribution is one self-extracting exe.**
`inno_bundle` and its config were removed in `748accf`; Flutter for Windows cannot
produce a true single-file exe anyway. Both `ci.yml` and `build-exe.yml` run
`flutter build windows --release` then `launcher_app/windows_stub/package.ps1`, whose
output is `launcher_app/build/עדכוני אוצריא.exe` (uploaded via a `build/*.exe` glob,
not by its Hebrew name). Do not reintroduce an installer step without adding the
dependency back first — that mismatch kept CI red from July 24 to August 6, 2026.

**The distributed exe carries the whole file pile inside it.** `launcher_app.exe`
cannot ship alone: `flutter_windows.dll` is a load-time import and `data/` is resolved
relative to the exe's directory. So what ships is a tiny C stub
(`launcher_app/windows_stub/stub.c`) holding the entire Release folder as an `RCDATA`
resource: on first run it extracts to `app-files\` **beside itself** and
`CreateProcessW`s `app-files\launcher_app.exe`; later runs see `app-files\.ready` and
just launch. Five load-bearing details:

- It lives **outside** `windows/`, because CI runs
  `flutter create --platforms=windows .` and overwrites that directory.
- It is compiled **`/MT`**, because a stub outside `app-files` cannot see the
  `vcruntime140.dll` that travels *inside* it.
- Extraction goes next to the exe and **never to `%TEMP%`** — `OtzariaData/` lands
  inside `app-files/` (that is what `Platform.resolvedExecutable` yields, so
  `app_paths.dart` needed no change) and holds ~1GB a temp dir would discard.
- The completion guard is the `.ready` marker, not the presence of
  `launcher_app.exe`, so an interrupted extraction is never mistaken for a finished
  one.
- Its single error message is the **one** user-visible string in this repo that is not
  in `otzaria_l10n` — C cannot depend on a Dart package.

**`package.ps1` must pack the payload before it compiles the stub.** `stub.rc` embeds
`windows_stub/build/payload.otz`, so `rc.exe` needs that file to exist;
`build_stub.ps1` throws if it does not. **Extraction happens inside the stub process**,
through Windows' Compression API (`cabinet.dll`, LZMS) over a container format
`pack_payload.ps1` writes and `stub.c` reads — the two must agree, and
`stub_contract_test.dart` pins the magic and the algorithm. It used to shell out to
`tar.exe` over a zip in `%TEMP%`, which broke extraction in the field: `tar.exe` only
exists from Windows 10 1803, and its ANSI command line mangled a Hebrew path on a drive
without 8.3 names. Do not reintroduce an external process here. Full rationale table in
`launcher_app/README.md`.

**The Visual C++ CRT rides in the payload — Flutter does not put it there.**
`launcher_app.exe`, `window_manager_plugin.dll`,
`screen_retriever_windows_plugin.dll`, `zstandard_windows_plugin.dll` and
`sqlite3_flutter_libs_plugin.dll` carry **load-time** imports on `MSVCP140.dll` /
`VCRUNTIME140.dll` / `VCRUNTIME140_1.dll`, and `flutter build windows --release`
copies none of them. Until this was added, the shipped exe required the machine to
already have the VC++ 2015–2022 Redistributable — wrong in exactly our case, since the
launcher runs on the **online** computer, which is not the one where Otzaria (whose
installer brings the CRT) is installed. `package.ps1` copies `Microsoft.VC*.CRT` out of
the VS redist directory (resolved with `vswhere`, highest toolset, sorted as
`[version]` so `14.44` beats `14.9`) into the staged `app-files\`, and **throws** when
any of the three is absent — the loud failure is the point, since the old behaviour was
a build that succeeded and a program that did not start.

**This does nothing for issue #21, and the resemblance is a trap.** #21 asks the drive
to carry *Otzaria's* dependencies. The CRT bundled above is the **launcher's own** and
is invisible to Otzaria: Windows resolves a load-time import from the directory of the
*importing* executable, so DLLs in `app-files\` are reachable by `launcher_app.exe`
alone. A `dumpbin /dependents` scan over all 18 payload binaries confirms the launcher
needs nothing beyond the OS.

**Issue #21 is now WebView2 and nothing else — and it is deliberately not served.** A
`dumpbin /dependents` scan over an installed Otzaria (Sept 2026) resolves every import
to an app-local file or an OS DLL: Otzaria already ships its whole CRT beside
`otzaria.exe` (`msvcp140*`, `vcruntime140*`, `concrt140`, `vccorlib140`), so the VC++
redistributable is not missing anywhere. The only external component left is the
**WebView2 Runtime**, loaded lazily via COM for the plugin system — Otzaria itself
starts fine without it. Carrying it offline means the Evergreen Standalone Installer,
measured at **212,745,424 bytes**, detected through `pv` under
`EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` and installed with
`/silent /install`; the Fixed Version is larger still and the 2MB bootstrapper needs
the network. 203MB on every drive to serve Windows 10 machines that lack it was judged
not worth it. Do not "finally fix #21" by adding it without asking.

**The launcher updates itself by replacing that stub — and `OtzariaData/` lives
*inside* the folder it re-extracts.** `lib/src/self_update/` downloads a newer packaged
exe into `mirror/launcher/`, copies it over the stub (two renames, rollback on failure
— the `seforim.db` pattern), and re-launches with `--after-update=<pid>`.

- **The stub never deletes anything.** It extracts *over* the existing `app-files\`, so
  `app-files\OtzariaData\` — settings, the ~1GB mirror, the managed Otzaria install —
  is untouched. A "clean install" wiping `app-files` first would delete exactly what
  the drive exists to carry. Cost: files removed in a newer version linger. They are
  inert, and that is the deliberate trade.
- **`.ready` holds the payload version, and that is what triggers a re-extract.** As an
  empty marker, a replaced exe would have skipped extraction and run the *old*
  `launcher_app.exe` forever; an empty marker from an older stub does not match, which
  is what makes the first self-update work at all.
- **The version comes from `pubspec.yaml` only.** `build_stub.ps1` generates
  `windows_stub/build/version.h` from it (`PAYLOAD_VERSION_A`,
  `PAYLOAD_VERSION_COMMAS`); `launcherVersion` in `launcher_version.dart` must match
  numerically, and a test asserts it. A tag disagreeing with those two would ship a
  launcher that reports the old number and offers itself the same update forever, so
  nothing sets them by hand: `tool/set_launcher_version.sh` writes both, and CI runs it
  in the build jobs *and* in `publish` with the same value, before tagging.
- **Versions have two parts (`0.2` → `0.3`); only the second moves.** `pubspec.yaml`
  holds `0.2.0` because pub rejects anything that is not MAJOR.MINOR.PATCH — that
  trailing `.0` never reaches the user or `launcherVersion`. Hence `PayloadCheck`
  compares numerically, not as strings.
- **⚠️ The git tag stays three-part (`v0.2.0`) even though the version shown is `0.2`.**
  Every launcher in the field rejects a tag that is not `vX.Y.Z` exactly
  (`LauncherVersion.isReleaseTag` in the *released* build, not this tree), so a `v0.2`
  release is invisible to all of them — it happened once, and the fix was to tag
  `vX.Y.0`. `LauncherRelease.version` drops the trailing `.0` for display.
- **Only a strict `vX.Y.Z` tag counts, and the highest version wins — not the first
  listed.** This repo carries a hand-made release tagged **`V1`** ("גירסת בדיקה", with
  a `default.exe`); `normalize('V1')` is `1`, newer than every 0.x forever, so a
  first-match-wins client would eventually hand users that stale test build. Taking the
  maximum also removes the dependence on GitHub's ordering.
- **The stub waits for the old process before extracting** — `launcher_app.exe` and
  `flutter_windows.dll` are locked while it runs. Hence `--after-update=<pid>` and
  `WaitForProcessExit`. If extraction fails anyway *and* a launcher exists on disk, the
  stub runs it instead of erroring: the marker still holds the old version, so the next
  launch retries. The error box is only for "nothing to run at all".
- **`Platform.resolvedExecutable` is the wrong file** — it points into `app-files\`,
  while what must be replaced is the stub beside it. The stub passes its own path in
  `OTZARIA_LAUNCHER_STUB`, and `LauncherInstallLayout` falls back to "the single `.exe`
  next to `app-files`" for older stubs. `launcher_app/test/stub_contract_test.dart`
  pins every shared name (`app-files`, the env var, the flag, the packaged exe name)
  across `stub.c`, `package.ps1` and the Dart side — they have no compile-time link,
  like the `processNamesFor` pair.
- **Replacing the exe is refused while a long task runs.** `LauncherSelfInstaller` ends
  in `exit(0)`, so an install pressed during a mirror download killed the process
  mid-asset: `MirrorDownloadUndo` never ran and partial assets stayed next to an
  already-rewritten manifest. `AppShell._longTaskRunning` (download, library `updating`,
  Otzaria `installing`) disables the card's button **and** guards
  `installLauncherUpdate` itself — the button is not enough, since
  `downloadLauncherUpdate` offers the install straight after a download.

**On macOS the same code replaces the whole `.app` bundle** (`ditto`, never `unzip`)
and does **not** restart: `open` on a bundle swapped under a running app is unreliable,
so the user is asked to reopen it. Two things are easy to drop: `cleanupLeftovers` must
delete the macOS leftovers, which are **directories**
(`.launcher-update-staging/` and `<app>.previous`) and not the two Windows files — each
is a full bundle, so an interrupted update parked hundreds of megabytes on the drive
forever; and the new bundle gets `xattr -dr com.apple.quarantine`, because a zip that
reached the drive through a browser or AirDrop carries the flag and Gatekeeper then
blocks the launcher on a machine with no internet to fix it.

### 5.9 UI and platform

**`launcher_app/macos/` is tracked in git** with non-default settings (product name,
bundle id, sandbox disabled). Never run `flutter create --platforms=macos .` — it
overwrites them. **The launcher's macOS process name must not be `אוצריא`**:
`PRODUCT_NAME` is `Otzaria Launcher` for exactly that reason (table in
`launcher_app/README.md`).

**`launcher_app/windows/runner/` is tracked too, with two non-default edits.**
`main.cpp` sets a Hebrew window title and sizes the window to the monitor's work area;
`win32_window.cpp`'s `Show()` uses `SW_SHOWMAXIMIZED`. Doing it in the runner rather
than from Dart is deliberate: the runner shows the window only once the first frame is
ready, so a `windowManager.maximize()` before `runApp` reveals an empty window early
and is then undone by the runner's own `Show()`. `flutter create --platforms=windows .`
— which CI still runs — only fills in missing files and leaves these alone (verified
2026-08-12), but it drops the `macos` entry from `.metadata`; check `git diff` after.

**The custom title bar is Windows-shaped, and macOS needs the other half.**
`WindowCaption` is, by its own documentation, "a widget to simulate the title bar of
windows 11". So on macOS `main.dart` passes `windowButtonVisibility: true` and lets the
system draw its three round buttons, `AppTitleBar` renders no `WindowCaption`, and the
row reserves `_kMacTrafficLightsWidth` on the **physical** left
(`EdgeInsets.only(left:)`, never `EdgeInsetsDirectional` — under Hebrew RTL the logical
start is the right edge). Matching it, `MainFlutterWindow` sizes the window to the
screen's `visibleFrame`, the macOS counterpart of the Windows work-area sizing.

**Permission failures are diagnosed, not just printed.** Otzaria under `Program Files`
means the launcher's *own* writes fail — the DB apply, the companion assets — while the
Otzaria installer is fine (Inno elevates itself, which is why exit code 1223 is "the
user refused UAC"). `Elevation` recognises that by **OS error code** (5 / `EACCES`),
never by message text: a Hebrew Windows says "הגישה נדחתה". A file merely *in use*
(error 32, Otzaria open on the DB) is deliberately **not** counted — elevating fixes
nothing. The sqlite path has no `OSError` at all, so a read-only DB is matched on
sqlite's own untranslated `readonly database`. `AppShell` offers the restart once per
run, from the shared listener, so the offer lives in one place.

**`Elevation` has two pieces of advice, and only one is actionable per platform.**
macOS has no "run as administrator" — an app cannot elevate itself (`osascript … with
administrator privileges` runs a *shell command* as root, not the app, behind a prompt
indistinguishable from phishing). So `restartElevated` refuses there, `AppShell` never
offers it, and `describe` appends `macHint` (pick a writable location, or grant Full
Disk Access). Detection differs too: macOS returns `EPERM` (1) as well as `EACCES` (13)
for a protected directory, while Windows counts only 5.

**Progress callbacks must not reach `setState` unthrottled.** `PatchDownloader` reports
per chunk — tens of thousands of calls for a 1GB download, each of which used to
rebuild the whole widget tree and cost more CPU than the download itself. Module
controllers route progress through `ProgressNotifier.notifyProgress()` (coalesced to
~10/s, last value always delivered). Use plain `notifyListeners` for *state* only.

**`AppShell` builds screens lazily.** `IndexedStack` builds every child, so the plugin
store — a card grid with one `Image.file` per plugin — was built and decoded at launch,
before the user opened that tab. Screens are created on first visit (`_builtScreens`)
and kept after. Consequence: the "plugin updates available" dialog fires on first visit
to the plugins tab, not at launch.

**Store images must pass `cacheWidth`.** Without it Flutter decodes at source
resolution; a 1200×800 catalogue image is ~3.8MB of RAM, times every plugin. See
`decodeWidthFor` in `screens/plugins/plugin_visuals.dart`. Related: the grid is a
`SliverGrid` inside `PluginStoreBody`'s `CustomScrollView` — it was a
`GridView(shrinkWrap: true)` inside a `ListView`, and `shrinkWrap` disables
virtualisation, so every card was built regardless of the viewport.

**Store cards live in a fixed-height grid, so nothing inside may grow.**
`mainAxisExtent` is computed from `_cardContentHeight`, and the card's two `Wrap` rows
(metadata badges, tags) silently wrap to another line when a chip gets longer or the
column narrows — which overflowed the card. Both rows have a fixed height budget with
`Clip.hardEdge`, the install chip is shortened inside cards
(`PluginInstallChip(compact: true)`), and the "כרטיס עמוס" test in `screens_test.dart`
renders the heaviest card in the narrowest column at two text scales.

**`PluginStoreBody` takes slivers only, and nothing nests a scrollable inside it.** A
`SliverList` with a fixed child list builds every child up front, re-creating the
eager-image problem. The category sidebar therefore lives *outside* the
`CustomScrollView` (it also stays put while the content scrolls, like the site's sticky
aside), and the website's mobile-style horizontal card rows were deliberately not
ported — a nested horizontal scrollable swallows the mouse wheel and makes the page
feel frozen.

---

## 6. Verification status

Read this before claiming something works. The package READMEs each carry a "what was
actually verified" section — trust those over assumptions, and update them when you
verify something new.

| Area | Status |
| --- | --- |
| `WindowsExeVersionReader`, `WindowsInstallRegistry` | **Run against a real install** (`otzaria.exe` 0.9.96+90960, Windows 11, 2026-08-10) |
| `otzaria_manager` on macOS + launcher build/run there | **Verified** against a real `otzaria-macos.zip` — but that predates the custom title bar and `RunningOtzariaLocator._probeMac` |
| `ZstdFileDecompressor` | Verified against real libzstd on Windows (`library_manager/test/zstd_file_decompressor_test.dart`, self-skipping) — **not** on a full ~1GB DB |
| `LibraryUpdateApplier` on Windows | Not verified on real hardware (full ~1GB download, delta chains, `tasklist`) |
| `RunningOtzariaLocator` FFI half (`QueryFullProcessImageNameW`), Windows `.db` picker filter | Not verified |
| Plugin store round trip | Unit-tested only — never a real `sync()` against `otzaria.org`, a USB trip, and `install-local` against a real Otzaria |
| Launcher self-update | Dart side unit-tested end to end (GitHub client against a mock, mirror round trip, location fallbacks, a real swap in a temp dir asserting `OtzariaData/` survives); `stub.c` compiles clean at `/W4`. **Never run for real**: a published tag found by a shipped exe, the `--after-update=<pid>` wait, the re-extract over a live `app-files\`, the macOS bundle swap |
| Offline-only rework (single mode, exe-adjacent data folder, app mirror, `prerelease` channels) | Unit-tested and analyzer-clean only. Not run on a real removable drive, a genuinely read-only folder, or `OtzariaAppMirror.sync()` against real GitHub; whether the trimmed mirror suffices for a real offline apply is unconfirmed |
| Read-only drive mode (issue #25) | Same — write paths traced and unit-tested, never run from a drive with its lock switch on |
| Two-channel download (stable + newer pre-release, chosen offline) | Unit-tested only. Not verified what `fetchChannelReleases` returns against the real repo today, nor whether both installers fit comfortably on a typical drive |
| Companion assets (mirror against the three real repos, installer into a real library folder) | Unit-tested only |
| `OtzariaSettingsReader` against a real `app_preferences.hive` | Unit-tested only |
| Combined first install (app wizard → auto-close → library), replacing the FULL package | Unit-tested only — the dialogs and the ordering are covered, but never run against a real wizard on a machine with no Otzaria, and the auto-close path has not been seen working. `otzaria.iss` was read to confirm `/NOLAUNCH=1` cannot clear the finish-page box |
| Custom title bar (`window_manager` with the native frame hidden) | Unit-tested only, on either platform |

**The macOS pass of 2026-09-14 is analyzer-clean and unit-tested only.** It closed six
places where a Windows fix had no macOS twin — the data folder landing inside the
`.app`, the launcher adopting its own bundle as Otzaria, Windows-11 caption buttons
drawn on a Mac, a window opening below its own minimum size, a bundle swap under a
running Otzaria, and Windows-only advice on a permission failure — plus the self-update
leftovers and the cross-platform mirror reads. Every one is covered by tests that run on
any host (the platform is injected), and **not one has run on real Apple hardware.**
Treat the whole list as "should be right", not "was seen working".

---

## 7. Communication

Reply to the user in Hebrew (per their global preference). Code, identifiers, commands
and this file stay in English.
