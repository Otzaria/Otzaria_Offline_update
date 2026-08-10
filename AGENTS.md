# AGENTS.md

Instructions for AI coding agents working in this repository. Human-facing docs
(README / CHANGELOG / package READMEs) are written in Hebrew; this file is in
English on purpose, as the shared agent contract.

---

## 1. What this software is for

Otzaria is a Hebrew library / sefarim reading app. Its book database
(`seforim.db`) is large (~1GB) and gets new releases regularly, and Otzaria also
has plugins that need updating. Many Otzaria users have **no internet on the
machine that runs Otzaria** — by choice or by policy.

This repository is the **updater/launcher for those offline users**. The intended
real-world workflow is:

1. The user copies this software onto a USB flash drive ("On-Key").
2. They plug the drive into a computer **that does have internet** and press
   *download* once. It fetches, into a folder **right next to the executable**:
   - library (`seforim.db`) updates for Otzaria — latest full DB + its patches,
   - the Otzaria app installers + their release metadata (the latest stable,
     plus the latest pre-release when it is newer — the offline machine picks),
   - Otzaria plugins (catalog + `.otzplugin` files).
3. They unplug the drive, plug it into **their own offline computer**, run the
   launcher again, and it installs from that folder — no network needed.

**There is exactly one mode: offline.** Otzaria itself already knows how to
update over the network, so this launcher deliberately does *not* offer a
"just update from the internet" path. Every check and every install reads from
the local folder, always — even when the machine is online. The network is
touched by *one* thing only: the download step that fills that folder.

| Step | API | Needs network |
| --- | --- | --- |
| Download library updates + companion files | `LibraryManager.downloadToMirror()` | **yes** (heavy — full DB/patches, Talmud PDFs, catalog, dictionary) |
| Download the Otzaria installers (stable + newer pre-release) | `OtzariaManager.downloadToMirror()` | **yes** (heavy — installer files) |
| Download the plugin store | `PluginsManager.sync()` | **yes** (heavy — images/`.otzplugin` files) |
| Peek the latest library version online | `LibraryManager.peekLatestOnlineVersion()` | **yes** (light — one API call, no asset) |
| Peek the latest Otzaria release online | `OtzariaManager.peekLatestOnlineRelease()` | **yes** (light — one API call, no asset) |
| Check / apply a library update | `LibraryManager.checkForUpdate()` / `.applyUpdate()` | no |
| Check / install the Otzaria app | `OtzariaManager.checkForUpdate()` / `.update()` | no |
| Read the store / install a plugin | `PluginsManager.load()` / `.directInstall()` | no |

The two "peek" methods exist only to power the launcher's optional, one-shot,
auto-on-launch "is there anything new online?" nudge (`AppShell.checkOnline()`,
`AppSettings.autoCheckOnlineUpdates`) — metadata only, never an asset, and a
failure (no network) is a normal, silently-handled outcome, not an error.

`AppPaths.resolve()` (in `launcher_app`) puts the data folder at
`<dir of the executable>/OtzariaData`, and there is **no setting to change it** —
that is what makes the drive self-contained. If that folder is not writable
(e.g. the app was moved into `Program Files`), the launcher shows
`SetupErrorScreen` and refuses to run rather than silently falling back to
`%APPDATA%`, which would leave the data behind on the online machine.

Layout under `OtzariaData/`:

```
mirror/library/   releases.json + assets/   ← LibraryManager.mirrorDir
mirror/companions/ companions.json + the Talmud archive, catalog and dictionary  ← LibraryManager.companionsMirrorDir
mirror/app/       latest-release.json (up to 2 channels) + installers/<tag>/  ← OtzariaAppMirror
mirror/plugins/   catalog.json + files/     ← PluginMirrorStore
otzaria-app/      the managed Otzaria install
```

The download step keeps the last **five** releases, not the whole patch history
(`LibraryMirrorExporter.recentReleases` / `defaultHistoryDepth`) — the full
history reached several gigabytes, which does not belong on a flash drive.
Online Otzaria walks the entire patch graph; five releases cover a machine that
updates occasionally, and anything older falls back to the full-DB route, which
is always present in the mirror.

---

## 2. Repository layout

Six separate Dart/Flutter packages, each with its own `pubspec.yaml`. The main
package sits at the repo root (historical, do not move it).

| Path | Package | Role |
| --- | --- | --- |
| `otzaria_l10n/` | `otzaria_l10n` | Pure Dart, **no dependencies at all**. Every user-visible string, in Hebrew and English. Everything else depends on it — including the pure-Dart managers, which is why it cannot use Flutter. See §4 "All user-visible text". |
| `.` (root, `lib/`) | `seforim_library_updater` | Flutter package. The client side of the `Otzaria/SeforimLibrary` delta release format: discover releases, plan an update route (delta vs. full), download, verify the logical content hash, apply patches atomically. |
| `otzaria_manager/` | `otzaria_manager` | Pure Dart (no Flutter). Manages the **Otzaria app itself**: check latest release, download, silent install, launch. Windows + macOS. |
| `library_manager/` | `library_manager` | Flutter package. Wires `seforim_library_updater` into the launcher: locate the user's real `seforim.db`, check versions, apply updates to the **live** DB, export/consume the offline mirror. |
| `plugins_manager/` | `plugins_manager` | Pure Dart (no Flutter). The **offline Otzaria plugin store**: syncs the `otzaria.org/api/plugins` catalog (metadata, images, `.otzplugin` files) into the mirror, detects which plugins Otzaria already has installed, and installs via the `otzaria://` protocol. A conversion of `Yehuda-Zakesh/Offline-repository-plugin-store` (itself derived from `Otzaria/Otzaria_Website`). |
| `launcher_app/` | `launcher_app` | The Flutter desktop app (Windows + macOS) that wires the modules into one dashboard. Depends on the other five via relative `path:`, so it must stay a sibling of them. |

Producer vs. consumer: the Kotlin repo `Otzaria/SeforimLibrary` *produces* the DB
and the patches; this repo only *consumes* them.

**The root package is a fork of `Otzaria/otzaria_library_updater`** — the very
package Otzaria itself depends on (by git ref) for its online library update.
Keep the engine (discovery, planner, hasher, `PatchApplier`, `PatchDownloader`)
in step with upstream; our deliberate additions there are the l10n calls, the
offline mirror source/exporter, and `LibraryUpdatePlanner.localReleaseTag`.
Otzaria's consumer side lives in `Otzaria/otzaria` under `lib/library_update/`
— read it before changing how the launcher orchestrates an update, and see
`library_manager/README.md` § "התאמה לעדכון המקוון של אוצריא" for the
point-by-point comparison.

---

## 3. Mandatory workflow after every change

Run these at the end of every change, in the package(s) you touched. This is not
optional and not something to defer to CI.

```bash
# 1. Format
dart format .

# 2. Analyze
flutter analyze --no-fatal-infos   # seforim_library_updater (root), library_manager, launcher_app
dart analyze                      # otzaria_l10n, otzaria_manager, plugins_manager (pure Dart)
```

Notes:

- The root `analysis_options.yaml` **excludes** the sub-packages, so analyzing
  from the root does *not* cover them. `cd` into each package you changed and
  analyze there. Every sub-package now carries its own `analysis_options.yaml`
  for the same reason — without one, the analyzer walks up to the root file,
  inherits its `exclude:` for that very package, and reports "No issues found"
  while checking nothing. `library_manager` and `otzaria_manager` were both in
  that state; do not delete those files.
- `.gitattributes` pins `*.json` to `eol=lf`. `test/patch_tables_contract.json`
  is compared byte-for-byte against the Kotlin side, and with
  `core.autocrlf=true` (the Windows default) it was checked out as CRLF and the
  contract test failed on every Windows machine.
- Run the relevant tests too when logic changed: `flutter test` (root,
  `library_manager`, `launcher_app`) or `dart test` (`otzaria_manager`,
  `plugins_manager`).
- **Real file I/O does not complete inside `testWidgets`** (its fake-async zone
  never resolves `dart:io` futures), so `pumpAndSettle` hangs forever on any
  spinner that is waiting on disk. Drive such work with `tester.runAsync(...)`
  *before* pumping the widget — see the store tests in
  `launcher_app/test/screens_test.dart`.
- Report honestly what you ran and what failed. Do not claim a change is
  verified if only the analyzer passed.

---

## 4. Code style conventions

- **Comments are short — one or two lines.** Explain *why*, not *what*; skip
  the comment entirely when the code already says it. Long explanatory prose
  belongs in the package README or CHANGELOG, not inline. Existing comments and
  doc-comments are in Hebrew; keep writing them in Hebrew to match.
- Match the surrounding code's naming and idiom. Follow `flutter_lints`.
- Keep the module boundaries: `otzaria_manager` must not depend on Flutter;
  the root package must not depend on Otzaria app code or on the launcher.
  `otzaria_l10n` is the one package everything may depend on — which is exactly
  why it has no dependencies of its own.
- Do not silently widen scope. Fix what was asked, then say what you left out.

**UI code in `launcher_app` follows Otzaria's design system, not its own.**
`launcher_app/lib/src/theme/` and `lib/src/widgets/` are ports of
`otzaria/lib/theme/` and `otzaria/lib/widgets/`. Use the ported components
(`ActionButton`, `SettingsCard`/`SettingsActionTile`, `AppCard`, `UiSnack`,
the `show*Dialog` helpers, `AppSegmentedControl`, `RtlIcon`, `RtlTextField`,
`StatusChip`) instead of raw Material widgets, and keep alpha/hover overrides
inside `lib/src/theme/`. The full rule table — including what deliberately was
*not* ported — is in `launcher_app/README.md`; the upstream contract is
`otzaria/AGENTS.md` § "MANDATORY UI Components". When touching UI, read the
Otzaria original before inventing something new.

**All user-visible text lives in `otzaria_l10n`, never inline.** The launcher
ships in Hebrew (the default) and English. Do not write a literal that a user
can read — not in a widget, not in an exception message, not in a progress
callback. Add a field to the right section of
`otzaria_l10n/lib/src/app_strings.dart` and implement it in **both**
`strings_he.dart` and `strings_en.dart`; the analyzer fails if you forget one.
Hebrew is the source, English is a free translation of it — matching meaning
and register, not word order.

- In widgets: `context.strings.<section>.<field>` (`AppStringsScope`, exported
  from `widgets_exports.dart`). It is an `InheritedWidget` on purpose — a
  `const` widget would otherwise keep the previous language on screen until it
  rebuilt for some other reason. It is installed in `MaterialApp.builder`, i.e.
  *above* the Navigator, so dialogs and pushed routes find it too.
- Outside widgets (controllers, and every one of the manager packages):
  `AppL10n.strings.<section>.<field>`. `SettingsController` is what sets it.
- **`Isolate.run` does not inherit it.** Statics are per-isolate, so a message
  built inside an isolate falls back to Hebrew. Pass `AppL10n.language` in as
  an argument and call `AppL10n.use(...)` first thing — see
  `LibraryUpdateApplier._isolateApplyPatch` and `ZstdFileDecompressor`.
- Content that comes from `otzaria.org` — plugin names, descriptions, tags,
  category names, the store's home texts — is **never** translated. Only the
  chrome around it is, plus the store-title fallback used when the site left
  the field empty.
- Direction is driven by the locale alone (`GlobalWidgetsLocalizations`); do
  not set `Directionality` by hand. `UiSnack` is the one exception — it lives
  in an `Overlay` and reads `AppL10n.language.isRtl` directly. For back/forward
  arrows use `context.backArrowIcon` / `context.forwardArrowIcon`: `RtlIcon`
  mirrors arrows under RTL, so those helpers hand it the *opposite* glyph and
  the rendered arrow ends up identical in both languages.

---

## 5. Landmines — do not break these

Each of these was a real bug or a verified finding. Changing the surrounding code
without knowing why it looks that way will regress it.

**Contract with the Kotlin producer.** `LogicalContentHasher` and
`PatchApplier` are byte-for-byte translations of the Kotlin logic and must agree
with it exactly (including the U+FEFF / BOM handling). Change either one and
every update starts getting rejected. There are golden-hash tests guarding this.

**Blocking work must go to an isolate.** `LogicalContentHasher.compute` and
`PatchApplier.apply` are synchronous and can take tens of seconds. Wrap them in
`Isolate.run` — and the closure must call a **top-level** function taking only
primitives / plain data. A closure that touches an instance field implicitly
captures `this` (and any live `HttpClient`), which throws
`Illegal argument in isolate message: object is unsendable`. This already caused
one crash and one feature rollback; see `LibraryUpdateApplier`.

**macOS `.app` extraction uses `ditto`, not `unzip`.** Otzaria's macOS build is
ad-hoc signed; `unzip` / `package:archive` destroy the symlinks and xattrs and
therefore the signature, and macOS then refuses to run it.

**Process detection uses exact matching.** `OtzariaProcessGuard` looks for
`otzaria.exe` via `tasklist` on Windows and the Hebrew process name `אוצריא` via
`pgrep -x` on macOS. Exact match is deliberate: `pgrep -f` or a substring match
would also match the launcher itself (its path contains "otzaria") and block
every DB update.

**Two packages match that same process, and their name lists must agree.**
`OtzariaProcessGuard` (`library_manager`) blocks DB updates while Otzaria is
open; `RunningOtzariaLocator` (`otzaria_manager`) reads the *path* of that same
process to learn where Otzaria is installed — the authoritative answer, tried
before the guessed default directories in `OtzariaManager._autoDetectDirs`. The
packages do not depend on each other, so `launcher_app/test/process_names_test.dart`
asserts the two `processNamesFor` lists are identical. Drift there produces the
exact bug this was built to fix: "we can see Otzaria is running, yet we cannot
tell where it is installed". Note the locator answers only for the *app*
directory — `seforim.db` lives under `%APPDATA%` regardless, and stays
`LibraryDbLocator`'s job.

**The launcher's macOS process name must not be `אוצריא`.** `PRODUCT_NAME` is
`Otzaria Launcher` for exactly that reason — see the table in
`launcher_app/README.md`.

**`launcher_app/macos/` is tracked in git** and contains non-default settings
(product name, bundle id, sandbox disabled). Never run
`flutter create --platforms=macos .` — it overwrites them. `windows/` is the
opposite: it is generated in CI.

**There is no Windows installer — the distribution is a portable ZIP.**
`inno_bundle` and its config were removed in `748accf`; Flutter for Windows
cannot produce a true single-file exe anyway. Both `ci.yml` and
`build-exe.yml` run `flutter build windows --release` and then
`launcher_app/windows_stub/package.ps1`. Do not reintroduce an installer step
without adding the dependency back first — that mismatch is exactly what kept
CI red from July 24 to August 6, 2026.

**The Windows ZIP has the exe at the root and everything else one level down.**
`package.ps1` produces `עדכוני אוצריא.exe` next to `app-files/`, where the real
`launcher_app.exe`, the DLLs and `data/` live. `launcher_app.exe` cannot simply
be moved up: `flutter_windows.dll` is a load-time import (resolved before any
of our code runs) and `data/` is resolved relative to the exe's directory. What
sits at the root is therefore a tiny C stub, `launcher_app/windows_stub/stub.c`,
that `CreateProcessW`s the real one. Three things there are load-bearing: it
lives **outside** `windows/` because CI runs `flutter create --platforms=windows .`
and overwrites that directory; it is compiled with **`/MT`** because a stub
outside `app-files` cannot see the `vcruntime140.dll` that Flutter copies into
the Release folder; and its single error message is the **one** user-visible
string in this repo that is not in `otzaria_l10n` — C cannot depend on a Dart
package. `OtzariaData/` deliberately lands inside `app-files/` (that is what
`Platform.resolvedExecutable` yields), so `app_paths.dart` needed no change.
The full rationale table is in `launcher_app/README.md`.

**Version strings need normalizing before comparison.** An installed build
reports `0.9.96` while the release tag is `0.9.96+736`. `OtzariaUpdateCheckResult`
strips a leading `v` and everything after `+`; without that, every launch sees a
phantom update and re-downloads ~73MB.

**Plugin install-state matching uses `manifestId`, not the catalog `id`.** The
`id` that `otzaria.org/api/plugins` returns is the website's database id;
Otzaria installs under `plugins/installed/<manifest.id>/`. `manifestId` is
extracted from the `manifest.json` inside the already-downloaded `.otzplugin`
(`PluginManifestReader`, BOM-stripped like `LogicalContentHasher`). Compare by
the catalog id and *nothing* is ever detected as installed. A plugin whose file
has not been downloaded yet correctly reports
`PluginInstallStatus.unknown` — that is not an error state.

**The plugin store's *structure* sync must never be fatal.** Since the website's
store redesign (managed categories, curated "featured" plugins, editable home
texts), `PluginMirrorSync` also fetches `/api/plugins/store-home` and
`/api/plugins/categories/<slug>`. Only `/api/plugins` itself is allowed to throw
— if the structure calls fail (older site, flaky request), the sync emits a
`warning` and keeps whatever categories the mirror already has. Wiping them
would silently degrade an offline machine that had them.

**Plugin installation is protocol-only:** `otzaria://plugin/install-local?path=`.
Do **not** extract the `.otzplugin` ZIP into Otzaria's folders ourselves —
Otzaria keeps an internal registry of installed plugins beyond the `installed/`
directory, and a manual unpack bypasses it. `install-local` reads the file from
disk, so it needs no network at all; the older `install?url=` does need one and
is deliberately unused here.

**The data folder is not configurable, and that is load-bearing.** `AppPaths`
resolves it next to the executable and `AppSettings` has **no path fields at
all**. Adding one back (an "advanced" data-dir setting, a USB target picker, an
`otzariaInstallPath`) breaks the premise that the drive carries everything.
On macOS the folder goes next to the `.app` bundle, not inside
`Contents/MacOS`, so the user can actually see it.

**There is no backup of `seforim.db`, and no setting for one.**
`LibraryDbRecoveryService` writes a marker (`<db>.applying`) and nothing else.
A second ~1GB copy doubled what the drive must hold while adding no real
safety: the delta route is one SQLite transaction that rolls itself back, and
the full-download route extracts to `<db>.new`, verifies it (`quick_check` +
version), and only then swaps. Do not reintroduce a copy-before-apply step or a
`backupsToKeep`-style setting.

**The swap itself is two renames, not delete-then-rename.** `<db>` is renamed
aside to `<db>.old`, `<db>.new` is renamed into place, and only then is
`<db>.old` removed. A rename costs nothing and needs no extra space (it is not
a second copy), and it removes the window in which *no* database exists at all
— an interrupted `deleteSync` + `renameSync` left the user with no library and
an orphaned `<db>.new` that the locator could not find, because it only ever
looks for `seforim.db`. If the second rename fails, the first is rolled back.
For the same reason `-wal` / `-shm` are deleted only *after* the swap
succeeded: they belong to the old DB, and deleting them earlier would discard
committed transactions from a hot journal if the swap then failed.

The process guard runs a second time immediately before the swap. The download
and decompression take many minutes, and on macOS `unlink` on an open file
succeeds — without the re-check the DB could be replaced underneath a running
Otzaria.

**Progress callbacks must not reach `setState` unthrottled.** `PatchDownloader`
reports `onProgress` per chunk — tens of thousands of calls for a 1GB download.
Each one used to become `notifyListeners()` → `setState` on `AppShell` → a
rebuild of the whole widget tree, which cost more CPU than the download. The
module controllers route progress through `ProgressNotifier.notifyProgress()`
(coalesced to ~10/s, last value always delivered). Use plain `notifyListeners`
for *state* changes only.

**`AppShell` builds screens lazily.** `IndexedStack` builds every child, so the
plugin store — a card grid with one `Image.file` per plugin — was built and had
all its images decoded at launch, before the user ever opened that tab. Screens
are now created on first visit (`_builtScreens`) and kept in the tree after.
Consequence: the "plugin updates available" dialog fires on first visit to the
plugins tab, not at launch.

**Store images must pass `cacheWidth`.** Without it Flutter decodes at source
resolution; a 1200×800 catalogue image is ~3.8MB of RAM, times every plugin.
See `decodeWidthFor` in `screens/plugins/plugin_visuals.dart`. Related: the
grid is a `SliverGrid` inside `PluginStoreBody`'s `CustomScrollView` — it was a
`GridView(shrinkWrap: true)` inside a `ListView`, and `shrinkWrap` disables
virtualisation, so every card was built regardless of the viewport.

**Store cards live in a fixed-height grid, so nothing inside them may grow.**
`SliverGrid`'s `mainAxisExtent` is computed from `_cardContentHeight`, and the
card's two `Wrap` rows (metadata badges, tags) silently wrap to another line
when a chip gets longer or the column narrows — which overflowed the card. Both
rows now have a fixed height budget with `Clip.hardEdge`, the install chip is
shortened inside cards (`PluginInstallChip(compact: true)`), and the
"כרטיס עמוס" test in `screens_test.dart` renders the heaviest possible card in
the narrowest column, at two text scales, to catch a regression.

**`PluginStoreBody` takes slivers only, and nothing nests a scrollable inside
it.** Same reason as above: a `SliverList` with a fixed child list builds every
child up front, which re-creates the eager-image problem for any card grid put
there. The category sidebar therefore lives *outside* the `CustomScrollView`
(it also stays put while the content scrolls, like the site's sticky aside),
and the mobile-style horizontal card rows the website uses were deliberately
not ported — a nested horizontal scrollable swallows the mouse wheel and makes
the page feel frozen.

**There is no network fallback in the check path.** `LibraryManager._resolveSource`
returns the local mirror or throws `LibraryMirrorMissingException`; it must never
fall back to `GithubLibraryReleaseClient`. An earlier version did fall back, and
the result was a launcher that behaved differently depending on whether the
machine happened to be online — the exact duality this design removes.
`OtzariaManager.checkForUpdate` is the same: it reads `OtzariaAppMirror.load()`,
never GitHub.

**Channels map to GitHub's `prerelease` flag.** A plain release is "stable", a
pre-release is "not stable" — for both the library and the app.

For the **app** this is not a setting that picks *what to download*: the
download always fetches **both** — the latest stable, plus the latest
pre-release *only when it is newer than that stable*
(`OtzariaReleaseClient.fetchChannelReleases`, newest-first ordering from the
API). Both installers travel on the drive, and the offline machine picks
between them (`AppSettings.preferAppPrerelease` →
`OtzariaManager.preferPrerelease`), with no network involved in switching.
Do **not** turn this back into a single-release download: the whole point is
that the offline machine can change its mind without going back online.

Two consequences to preserve:
- A pre-release *older* than the newest stable is never mirrored — there is no
  real choice there, and it would waste space on the drive. The choice UI
  (`OtzariaScreen`) therefore only appears when `hasChannelChoice` is true.
- When the first page (50 releases) holds no plain release at all, only the
  pre-release is mirrored and it is offered as the only version, labelled as
  such. That is not a silent fallback — the label says which channel it is.
  (This replaces the older `NoStableReleaseException`, which existed when a
  channel was a download-time choice.)

**A DB update can ship without a version bump.** SeforimLibrary sometimes
re-publishes a corrected `seforim.db.zst` under the same `db_version`. The
version comparison alone reports "up to date", so `LibraryUpdatePlanner` also
compares the applied release tag (`LibraryStateStore.appliedReleaseTag`, written
by `applyUpdate`). It only does so when that tag is *known* — a DB that was not
installed by this launcher has no tag, and guessing there would offer a ~1GB
download on every single launch.

**DB location is discovered, not assumed — and Otzaria's own setting wins.**
`LibraryDbLocator` checks, in order: a path we saved ourselves, then
**Otzaria's settings** (`key-library-path` + `key-library-folder-name` read out
of its `app_preferences` Hive box, exactly like `DatabaseConstants.getDatabasePath`),
then a bundled FULL-package library, then `%APPDATA%\otzaria\books\`,
`%ProgramData%\otzaria\books\` (Windows) or
`~/Library/Application Support/otzaria/books/` and the system-wide equivalent
(macOS), and finally `C:\אוצריא\`. If nothing is found it returns `null` and the
UI must ask the user to point at the file. Do not hardcode a path here — a
previous confident claim about the "real" location was simply wrong, and
skipping Otzaria's setting silently updated the wrong file for anyone who had
moved their library.

The Hive box is read **from a copy** in a temp dir (`OtzariaSettingsReader`):
opening it in place creates a lock file inside Otzaria's own folder and clashes
with a running Otzaria. Any failure returns `null` and the search continues.

**Portable Otzaria moves everything.** A `portable.marker` next to Otzaria's
executable puts its whole data root in `otzaria_data` beside it. Detecting that
needs Otzaria's launch path, which is why `AppShell.checkAll()` runs the app
module's check **before** the library module's, sequentially.

**The library update is not just `seforim.db`.** Otzaria refreshes three
companion files from the network on every library update
(`CompanionAssetsService`): the Talmud Bavli PDFs, the otzar-HB catalog and the
fuzzy-search dictionary. An offline machine has no network, so they ride along
in `mirror/companions/` and are installed by `CompanionAssetsInstaller` right
after the DB — same targets, same version markers, same best-effort semantics
(one failing item never fails the others or the DB update that already
succeeded). The exact sources and markers are tabulated in
`library_manager/README.md`.

**A DB updated from outside leaves Otzaria's search index stale.** Otzaria
re-indexes exactly the books `PatchApplier` reports in `booksTouched` (or runs
`ReconcileIndex` after a full download); neither path runs when *we* write the
DB, and startup indexing only adds *new* books. `applyUpdate` therefore writes
`.otzaria-external-update.json` next to the DB with the route, version and book
ids. Nothing reads it yet — it is the concrete proposal to the Otzaria
developers, spelled out in `library_manager/README.md`.

**The Otzaria *app*'s real default install directory, verified against the
Otzaria developers (2026-08-07) — not a guess:** the Windows Inno Setup
installer's default is `{autopf}\Otzaria`, i.e. `%LocalAppData%\Programs\Otzaria`
for a per-user install (the installer's default) or `%ProgramFiles%\Otzaria`
for a per-machine install; older installs may sit at `C:\אוצריא` or
`{Program Files}\אוצריא`. `OtzariaManager._windowsRealDefaultDirs` checks all
of these, after the launcher's own managed folder. This is a *different*
directory from where the library DB lives (`%APPDATA%\otzaria\`, see above) —
don't conflate the two when debugging "Otzaria not detected" reports. Before
this was added, `OtzariaManager._autoDetectDirs` on Windows checked **only**
the launcher's own managed install folder, so any Otzaria installed
independently (via the real installer, or before the "data folder next to the
executable" rework moved that managed folder) was invisible to auto-detect —
the manual "בחירת מיקום ידנית" picker (`OtzariaModuleController.adoptInstallDir`)
is the fallback for anything these paths don't cover.

---

## 6. Verification status (read before claiming something works)

The package READMEs each carry a "what was actually verified" section — trust
those over assumptions, and update them when you verify something new.

Also **not** verified end-to-end: the plugin store's real round trip — an actual
`sync()` against `otzaria.org`, carrying `OtzariaData/` on a USB drive to an
offline machine, and `otzaria://plugin/install-local` against a real Otzaria
install. Unit-tested logic only; see `plugins_manager/README.md`.

The offline-only rework (single mode, exe-adjacent data folder, app mirror,
`prerelease`-based channels) is **unit-tested and analyzer-clean only**. Not yet
run on real hardware: `AppPaths` on a real removable drive, the refusal path in
a genuinely read-only folder, `OtzariaAppMirror.sync()` against real GitHub, and
whether the trimmed mirror is in fact enough for a real offline apply.

The two-channel download (stable + newer pre-release in one mirror, with the
choice made offline) is likewise **unit-tested only**. Not verified against the
real repo: what `fetchChannelReleases` actually returns there today, and whether
both installers together fit comfortably on a typical drive.

Currently **not** verified on real hardware: the Windows path of
`LibraryUpdateApplier` (full ~1GB download, delta chains, `tasklist` behaviour),
`WindowsExeVersionReader` and `RunningOtzariaLocator` (both FFI via
`package:win32`), and the Windows `.db` file picker filter. The macOS path of
`otzaria_manager` and the launcher build/run on macOS **were** verified against a
real `otzaria-macos.zip` — but that predates the custom title bar and
`RunningOtzariaLocator._probeMac`, neither of which has run on a Mac.

Also unit-tested only, never on real hardware: the companion assets
(`CompanionAssetsMirror` against the three real GitHub repos, and
`CompanionAssetsInstaller` writing into a real Otzaria library folder),
`OtzariaSettingsReader` against a real `app_preferences.hive` written by
Otzaria, and the custom title bar (`window_manager` with the native frame
hidden) on either platform.

The fullDownload route used to decompress in memory (~1.1GB, plus another copy
when that `Uint8List` was sent to an isolate to be written). It now streams:
download → file, `ZstdFileDecompressor` → `<db>.new`, then `rename`. The
streaming decompressor is verified against real libzstd on Windows
(`library_manager/test/zstd_file_decompressor_test.dart`, self-skipping when the
library can't be loaded) but **not** yet on a full ~1GB DB.

---

## 7. Communication

Reply to the user in Hebrew (per their global preference). Code, identifiers,
commands and this file stay in English.
