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
| Download library updates + companion files | `LibraryManager.downloadToMirror()` | **yes** (heavy — full DB/patches, Talmud PDFs, catalog, dictionary; patches only in "personal update" mode, see below) |
| Download the Otzaria installers (stable + newer pre-release) | `OtzariaManager.downloadToMirror()` | **yes** (heavy — installer files, plus the ~2GB FULL package when asked) |
| Download the plugin store | `PluginsManager.sync()` | **yes** (heavy — images/`.otzplugin` files) |
| Download a newer **launcher** (this program itself) | `LauncherSelfUpdater.downloadToMirror()` | **yes** (the packaged exe, tens of MB) |
| Peek the latest library version online | `LibraryManager.peekLatestOnlineVersion()` | **yes** (light — one API call, no asset) |
| Peek the latest Otzaria release online | `OtzariaManager.peekLatestOnlineRelease()` | **yes** (light — one API call, no asset) |
| Peek the latest launcher release online | `LauncherSelfUpdater.peekLatestOnline()` | **yes** (light — one API call, no asset) |
| Peek what is new in the plugin store online | `PluginsManager.peekOnlineUpdates()` | **yes** (light — one API call, no asset) |
| Check / apply a library update | `LibraryManager.checkForUpdate()` / `.applyUpdate()` | no |
| Check / install the Otzaria app | `OtzariaManager.checkForUpdate()` / `.update()` | no |
| Check / install the launcher itself | `LauncherSelfUpdater.checkForUpdate()` / `.applyUpdate()` | no |
| Read the store / install a plugin | `PluginsManager.load()` / `.directInstall()` | no |

**`downloadAll` runs only the components that have something to bring.**
`AppShell.downloadAll()` used to run all three downloads whenever the button
was pressed, so a store with two new plugins also re-ran the app and library
downloads — minutes of progress bars for nothing, and it read as "it downloads
everything again". A component is now skipped when `provenUpToDateOnline`
(`controllers/online_check.dart`) says the light check *proved* there is
nothing new: checked, no error, no update. A check that never ran or that
failed proves nothing and never skips — "no network" is not "no update". The
library is additionally never skipped in personal-update mode, where the target
comes from the recorded DB version rather than from the newest release online.
The skip is announced in a snackbar; a silent one is what produced the "why
did it not download the plugins" confusion in the first place.

**A running download can be cancelled, and cancelling deletes what *that*
download brought.** The button lives next to the progress row on the home
screen and only appears while a download runs; `AppShell._cancelDownload` is
read through the `isCancelled` callback that every download layer already
takes, so it takes effect mid-asset. The cleanup is
`MirrorDownloadUndo` (`launcher_app/lib/src/services/`): it snapshots
`mirror/library`, `mirror/companions`, `mirror/app` and `mirror/plugins`
before the first byte, and on cancel deletes files that were created, restores
any `.json` manifest that was rewritten (a new `releases.json` over deleted
assets is a mirror pointing at nothing), and truncates a resumed partial asset
back to its previous length so it stays resumable. Do **not** "simplify" this
into deleting the mirror: the ~1.5GB compressed DB sitting there from an
earlier run is exactly what must survive a cancel. `mirror/apps` and
`mirror/launcher` are deliberately outside the snapshot — no download from
this button writes there.

The "peek" methods exist only to power the launcher's optional, one-shot,
auto-on-launch "is there anything new online?" nudge (`AppShell.checkOnline()`,
`AppSettings.autoCheckOnlineUpdates`) — metadata only, never an asset, and a
failure (no network) is a normal, silently-handled outcome, not an error.
**All four modules must be in that call.** The plugin store was missing from it
for its whole life, so a new plugin — or a new version of one already in the
mirror — was announced by exactly nothing: the launcher said "no new updates
online" while the store had them. `PluginsManager.peekOnlineUpdates()` compares
`/api/plugins` against the mirrored `catalog.json`, and it must keep agreeing
with what a real `sync()` would download (see `plugins_manager/README.md`).
**That includes looking at the disk**: the catalog is not evidence that the
file exists — a deleted `.otzplugin`, a half-copied drive or a failed download
all leave a complete-looking record behind, and the metadata-only version of
this check answered "everything is up to date" for a folder that was missing
plugins.

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
mirror/launcher/  latest-release.json + files/<tag>/  ← LauncherUpdateMirror (the launcher itself)
otzaria-app/      **legacy** — Otzaria installs made before the install target was fixed
```

**Otzaria itself is never installed under `OtzariaData/`.** The whole point of
this program is that the *drive* is portable and the *installed app* is not:
`otzaria-app/` used to be the default install target, which meant a launcher run
from a USB stick installed Otzaria **onto the stick** — it vanished from the
machine the moment the stick was pulled, and ate space on the stick instead.
`OtzariaManager.resolveDefaultInstallDir()` now returns the app's own normal
location (see §5), and `OtzariaInstaller.installFromFile` takes a **required**
`installDir` so there is no launcher-owned default to fall back into. The folder
stays first in `_autoDetectDirs` only so installs already sitting there keep
being found and keep updating in place.

The download step keeps the last **ten** releases, not the whole patch history
(`LibraryMirrorExporter.recentReleases` / `defaultHistoryDepth`) — the full
history reached several gigabytes, which does not belong on a flash drive.
Online Otzaria walks the entire patch graph; ten releases cover a machine that
updates occasionally, and anything older falls back to the full-DB route, which
is always present in the mirror.

**The FULL package is opt-in, stable-only, and invisible to everyone else.**
`AppSettings.syncFullPackage` (default **off**) → `OtzariaManager.downloadFullPackage`
→ `OtzariaAppMirror.sync(includeFullPackage:)` adds
`otzaria-<ver>-windows-full.exe` (~2GB — the installer with the library inside
it) to the mirror. Four things hold it together:

- **Stable channel only.** It is a *first install* package; two of them, one per
  channel, would be 4GB on a flash drive for no gain.
- **Recommended only on a machine with no Otzaria at all**
  (`OtzariaUpdateCheckResult.fullPackageRecommended` = no `currentState` **and**
  the file is really on the drive). Where Otzaria already exists it is 2GB that
  the regular installer makes redundant, so it is never offered there.
- **Nothing appears for a user who did not tick it.** The card in the app screen
  is drawn only when `fullPackage != null` — i.e. only when the file was
  actually downloaded — and the one-per-run dialog needs the same evidence.
- **Turning it off deletes the file** on the next download, and turning it *on*
  forces the app module to run even when the online check proved there is no new
  version (`fullPackagePending` in `AppShell.downloadAll`). Without that, a drive
  that was already up to date would have skipped the module and never fetched the
  package.
- **When the *user* installs, Otzaria's own wizard opens** — the full package
  and the ordinary install alike (`installFullPackage(useWizard: true)` /
  `update(check, useWizard: true)` → `OtzariaInstaller.installWithWizard`, no
  flags but `/LOG=`). The wizard's two pages carry decisions only the person
  standing there can make: which folder (a flash drive? one user's profile?) and
  whether to create a desktop shortcut. `/VERYSILENT` deleted both pages, which
  is what the report "it didn't open the installer's dialog and made no
  shortcut" actually was. Do not "fix" this back by passing `/MERGETASKS` here
  — overriding that choice is the bug. `/DIR=` is different and **is** passed
  when an install already exists: Inno's `/DIR` only sets the *default* shown
  on the destination page (hidden anyway on an update), so the new version
  lands in the existing folder instead of beside it, and the user can still
  change it when the page does show. Inno's own `UsePreviousAppDir` is not
  enough — it needs Setup's own uninstall record, which a portable or
  manually-adopted install does not have. The dir we passed also **outranks
  detection** when deciding what got installed; only if no executable is there
  (the user retargeted in the wizard) does detection answer. **Auto-install stays
  silent** (`_autoInstallIfEnabled` passes `useWizard: false` on both paths): a
  wizard waiting for a click is not "install by itself", and that is the only
  path where `/MERGETASKS=desktopicon` still does anything.
- **Cancelling the wizard is not a failure.** `OtzariaInstallCancelled` (Inno
  exit 2/5, plus 1223 = UAC refused) and `OtzariaWizardStillOpen` (the process
  returned before the install is on disk — routine when Inno elevates and the
  process we ran hands off to an elevated child) surface as
  `OtzariaModuleController.noticeMessage`, a plain snackbar. Never route them
  through `errorMessage`: painting the user's own choice red is what makes
  people think the program broke.

It does **not** solve issue #21. The FULL installer carries only the ~2MB
WebView2 *bootstrapper*, which downloads the runtime from the internet at install
time — useless on the offline machine. VC++ is a non-issue in both installers
since May 2026 (the CRT DLLs are bundled app-local beside `otzaria.exe`).

**"Personal update" is the one setting that changes what a download brings.**
`AppSettings.personalUpdateMode` → `LibraryManager.personalUpdateMode` →
`LibraryMirrorExporter.export(fromVersion:)`: only the patches from the user's
own DB version upwards, and **no full DB at all** (`personalReleases`). It
exists because carrying ~1.5GB to update a machine that already holds v20 is
what users actually objected to (forum post 33695). Four things hold it
together:

- **Default off, and confirmed on enable.** The drive is a distribution tool
  first; without the full DB it cannot serve a machine that has no Otzaria, and
  `LibraryUpdatePlan.fullDownloadFallback` — the recovery from a patch that does
  not fit (issue #19) — is `null`. The settings toggle says so in a warning
  dialog before turning it on.
- **The version is read only on an explicit click**, never automatically:
  `LibraryManager.captureLocalDbVersion()`, behind the button in
  `LibraryScreen`. A routine `checkForUpdate` deliberately does *not* record it.
  The drive travels, and the **online** machine may hold its own (newer)
  Otzaria — recording that one would have aimed the download at v22 while the
  offline machine sat at v20, leaving it with no patch route at all.
- **One record per machine, and the lowest wins**
  (`LibraryStateStore.knownDbVersions`, keyed by hostname + DB path;
  `lowestKnownDbVersion`). Someone who clicks on two machines gets a download
  that serves both. `applyUpdate` raises that machine's entry, so a machine that
  catches up stops dragging the floor down.
- **"Nothing newer" does not touch the mirror.** `export` returns `false` and
  skips the manifest write *and* `_pruneStaleAssets` — otherwise an up-to-date
  machine would have deleted a perfectly good mirror.

A local DB that is not on the mirrored chain is **not** silently mis-updated: it
lands on `LibraryUpdatePlanKind.blocked` with a reason, since the planner already
tolerates a missing full-DB asset (`_fullOrBlocked` → `planNoFullDbEither`).

Within that window only the **patches** are per-release. `seforim.db.zst`
(~1.5GB) is downloaded **once**, from the highest version that carries one —
that is the only full-DB asset `LibraryUpdateDiscovery` ever selects offline, so
a copy per release meant ~7.5GB of assets nothing would ever read. At the end of
a successful download, anything under `assets/` that is not in the new manifest
is deleted (`_pruneStaleAssets`); the `.resume` sidecars of assets that *are* in
it survive, since they are what lets a re-run skip a completed download.

---

## 2. Repository layout

Seven separate Dart/Flutter packages, each with its own `pubspec.yaml`. The main
package sits at the repo root (historical, do not move it).

| Path | Package | Role |
| --- | --- | --- |
| `otzaria_l10n/` | `otzaria_l10n` | Pure Dart, **no dependencies at all**. Every user-visible string, in Hebrew and English. Everything else depends on it — including the pure-Dart managers, which is why it cannot use Flutter. See §4 "All user-visible text". |
| `.` (root, `lib/`) | `seforim_library_updater` | Flutter package. The client side of the `Otzaria/SeforimLibrary` delta release format: discover releases, plan an update route (delta vs. full), download, verify the logical content hash, apply patches atomically. |
| `otzaria_manager/` | `otzaria_manager` | Pure Dart (no Flutter). Manages the **Otzaria app itself**: check latest release, download, silent install, launch. Windows + macOS. |
| `library_manager/` | `library_manager` | Flutter package. Wires `seforim_library_updater` into the launcher: locate the user's real `seforim.db`, check versions, apply updates to the **live** DB, export/consume the offline mirror. |
| `plugins_manager/` | `plugins_manager` | Pure Dart (no Flutter). The **offline Otzaria plugin store**: syncs the `otzaria.org/api/plugins` catalog (metadata, images, `.otzplugin` files) into the mirror, detects which plugins Otzaria already has installed, and installs via the `otzaria://` protocol. A conversion of `Yehuda-Zakesh/Offline-repository-plugin-store` (itself derived from `Otzaria/Otzaria_Website`). |
| `custom_apps_manager/` | `custom_apps_manager` | Pure Dart (no Flutter). **User-added programs**: a record the user fills in a form (name, GitHub repo *or* a local installer, install location, detection rules) so the launcher can carry and silently install a program that is not Otzaria. It is *not* a plugin system — no runtime, no WebView, no permissions, and **no importing a record from an external file**, so every repo and every file was chosen by the user. See its README, especially why the asset must be picked from the real release listing rather than guessed, and why the detection fields are *learned* rather than asked. |
| `launcher_app/` | `launcher_app` | The Flutter desktop app (Windows + macOS) that wires the modules into one dashboard. Depends on the other six via relative `path:`, so it must stay a sibling of them. |

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
dart analyze                      # otzaria_l10n, otzaria_manager, plugins_manager, custom_apps_manager (pure Dart)
```

Notes:

- The root `analysis_options.yaml` **excludes** the sub-packages, so analyzing
  from the root does *not* cover them. `cd` into each package you changed and
  analyze there. Every sub-package now carries its own `analysis_options.yaml`
  for the same reason — without one, the analyzer walks up to the root file,
  inherits its `exclude:` for that very package, and reports "No issues found"
  while checking nothing. `library_manager` and `otzaria_manager` were both in
  that state; do not delete those files.
- **Each of those seven files includes two things:** its own base rule set
  (`package:flutter_lints/flutter.yaml` for the Flutter packages,
  `package:lints/recommended.yaml` for the pure-Dart ones) **and**
  `analysis_options_shared.yaml` at the repo root, which holds every tightening
  that applies repo-wide. A tightening added to one package only would silently
  not apply to the rest — that is exactly what happened to
  `prefer_single_quotes`, which was enabled in `otzaria_l10n` alone.
  `otzaria_l10n/test/shared_lint_config_test.dart` asserts all seven import it,
  the same way `process_names_test.dart` guards the other cross-package
  duplication. Before adding a rule there, measure it in **all seven** packages —
  a rule that is clean in five and fails in the sixth turns CI red. Note that
  `dart analyze` right-aligns severity labels, so `warning` lines carry **no**
  leading space while `info` lines do; a grep that assumes indentation misses
  every warning (this cost one wrong "clean everywhere" measurement).
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
- **Favor generous, layered test coverage over relying on manual checks** —
  unit tests, widget tests, golden/contract tests (like
  `test/patch_tables_contract.json`) stacked on top of each other. The point
  is not for a human (or an agent) to re-run everything by hand each time:
  `.github/workflows/ci.yml` runs the full suite, across every package, on
  every push and PR. (It briefly also ran on a weekly `cron`; that was removed
  on 2026-08-11 — the suite runs on every push, and that is the only trigger.)
  When adding logic, add the tests that let CI catch its regressions
  automatically, rather than trusting a one-time manual run.
- **A green push to `main` publishes a release.** `ci.yml`'s `publish` job
  bumps the launcher's patch version, commits it, tags it, and uploads the two
  artifacts the `launcher_app*` jobs already built. So `main` is not a
  scratchpad: anything merged there reaches users as a new version, which the
  launcher's own self-update then offers them. Details in
  `launcher_app/README.md` § "עדכון עצמי".
- **A local layer runs the same checks before a commit even leaves the
  machine.** `.githooks/pre-commit` runs `dart format` + analyze + test on
  whichever packages have staged changes, and blocks the commit on failure.
  It is not wired in by git automatically — each clone needs the one-time
  `git config core.hooksPath .githooks`.

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
`StatusChip`, `ColorPickerTile`) instead of raw Material widgets, and keep
alpha/hover overrides inside `lib/src/theme/`. The full rule table — including what deliberately was
*not* ported — is in `launcher_app/README.md`; the upstream contract is
`otzaria/AGENTS.md` § "MANDATORY UI Components". When touching UI, read the
Otzaria original before inventing something new.

**All user-visible text lives in `otzaria_l10n`, never inline.** The launcher
ships in Hebrew and English, defaulting to whichever the computer speaks
(`AppLanguagePreference.system`). Do not write a literal that a user
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
  not set `Directionality` by hand. There are exactly two exceptions, both
  pinned by an allowlist in `launcher_app/test/widgets_test.dart`: `UiSnack`,
  which lives in an `Overlay` and reads `AppL10n.language.isRtl` directly, and
  `SeedColorPalette`, which forces RTL so the swatch order does not mirror in
  English. A third one is a bug, not a precedent. For back/forward
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

What that contract covers is the **byte stream**, not the SHA-256
implementation. `FastSha256` deliberately runs the hash through the OS crypto
library (CNG on Windows, CommonCrypto on macOS) because `package:crypto` is pure
Dart at ~50MB/s against ~1,225MB/s native, and the logical hash reads the whole
~7.4GB DB on every patch. Same algorithm, identical digest — so it is safe, and
a self-test against `package:crypto` at load time silences the native path if it
ever disagrees. Do **not** "simplify" that back into `sha256.startChunkedConversion`,
and do not change what gets fed into it.

That native sink owns memory Dart's GC knows nothing about, so **every caller
must `dispose()` it in a `finally`** — which is why `FastSha256.start` returns
`FastSha256Sink` and not a bare `ByteConversionSink`. `close()` disposes on the
success path; the `finally` is what covers a cancelled download, a network
failure or an SQLite error mid-scan, each of which otherwise leaks a 1MB buffer
plus a CNG hash object for the life of the process. Adding to a sink after it
closed throws, exactly like `package:crypto` does — without that guard it wrote
into freed memory instead.

**The logical hash is verified once per chain, not once per patch — and
`<db>.unverified` is what makes that safe.** The hash covers the whole DB
content, so matching the *last* step's `toContentHash` proves every step before
it; verifying each step re-read a 7.4GB DB per patch. `PatchApplier.apply` still
defaults to `verifyToHash: true` (upstream parity); `LibraryUpdateApplier.applyDelta`
turns it off for every step but the last. The gap that creates: a chain
interrupted midway leaves a DB that applied cleanly but was never hash-verified.
So each unverified step records its version in `<db>.unverified`, and the next
apply starting from that version runs with `verifyFromHash: true`. Remove that
marker logic and you get a silently-unverified DB; remove the per-chain single
verify and you are back to N full reads.

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
`flutter create --platforms=macos .` — it overwrites them.

**`launcher_app/windows/runner/` is tracked in git too, and carries two
non-default edits.** `main.cpp` sets a Hebrew window title and sizes the window
to the monitor's work area; `win32_window.cpp`'s `Show()` uses
`SW_SHOWMAXIMIZED`, which is what makes the app open maximized. Doing it there
rather than from Dart is deliberate: the runner only shows the window once the
first frame is ready, so a `windowManager.maximize()` before `runApp` reveals an
empty window early (a visible flicker) and is then undone by the runner's own
`Show()`. `flutter create --platforms=windows .` — which CI still runs — only
fills in missing files and leaves these two alone (verified 2026-08-12), but it
does drop the `macos` entry from `.metadata`; check `git diff` after running it.

**There is no Windows installer — the distribution is one self-extracting exe.**
`inno_bundle` and its config were removed in `748accf`; Flutter for Windows
cannot produce a true single-file exe anyway. Both `ci.yml` and
`build-exe.yml` run `flutter build windows --release` and then
`launcher_app/windows_stub/package.ps1`, whose output is
`launcher_app/build/עדכוני אוצריא.exe` (the workflows upload it via a
`build/*.exe` glob, not by its Hebrew name). Do not reintroduce an installer
step without adding the dependency back first — that mismatch is exactly what
kept CI red from July 24 to August 6, 2026.

**The distributed exe carries the whole file pile inside it.**
`launcher_app.exe` cannot simply be shipped alone: `flutter_windows.dll` is a
load-time import (resolved before any of our code runs) and `data/` is resolved
relative to the exe's directory. So what ships is a tiny C stub,
`launcher_app/windows_stub/stub.c`, holding the entire Release folder as an
`RCDATA` resource: on first run it extracts it to `app-files\` **beside itself**
and then `CreateProcessW`s `app-files\launcher_app.exe`; on every later run the
`app-files\.ready` marker is there and it just launches. Five things are
load-bearing. It lives **outside** `windows/` because CI runs
`flutter create --platforms=windows .` and overwrites that directory. It is
compiled with **`/MT`** because a stub outside `app-files` cannot see the
`vcruntime140.dll` that travels *inside* it. Extraction goes
next to the exe and **never to `%TEMP%`** — `OtzariaData/` lands inside
`app-files/` (that is what `Platform.resolvedExecutable` yields, so
`app_paths.dart` needed no change) and holds ~1GB of downloads, which a temp
dir would discard on every run. The completion guard is the `.ready` marker
rather than the presence of `launcher_app.exe`, so an interrupted extraction is
never mistaken for a finished one. And its single error message is the **one**
user-visible string in this repo that is not in `otzaria_l10n` — C cannot depend
on a Dart package.

**`package.ps1` must pack the payload before it compiles the stub.** `stub.rc`
embeds `windows_stub/build/payload.otz`, so `rc.exe` needs that file to already
exist; `build_stub.ps1` throws if it does not. **Extraction happens inside the
stub process**, through Windows' Compression API (`cabinet.dll`, LZMS) over a
container format that `pack_payload.ps1` writes and `stub.c` reads — the two
must agree, and `stub_contract_test.dart` pins the magic and the algorithm.
It used to shell out to `tar.exe` over a zip in `%TEMP%`, and that is what
broke extraction in the field: `tar.exe` only exists from Windows 10 1803, and
its paths went through an ANSI command line, so a Hebrew path on a drive
without 8.3 names arrived mangled. Do not reintroduce an external process here.
The full rationale table is in `launcher_app/README.md`.

**The Visual C++ CRT rides in the payload — Flutter does not put it there.**
`launcher_app.exe`, `window_manager_plugin.dll`,
`screen_retriever_windows_plugin.dll`, `zstandard_windows_plugin.dll` and
`sqlite3_flutter_libs_plugin.dll` carry **load-time** imports on
`MSVCP140.dll` / `VCRUNTIME140.dll` / `VCRUNTIME140_1.dll`, and
`flutter build windows --release` copies none of them into the Release folder
(there is no CRT handling in `windows/CMakeLists.txt` either). Until this was
added, the shipped exe simply required the machine to already have the
**VC++ 2015–2022 Redistributable** — an assumption that is wrong in exactly our
case: the launcher runs on the **online** computer, which by definition is not
the one where Otzaria (whose installer brings the CRT along) is installed.
`package.ps1` therefore copies `Microsoft.VC*.CRT` out of the VS redist
directory (resolved with `vswhere`, highest toolset version, sorted as
`[version]` so `14.44` beats `14.9`) into the staged `app-files\`, and then
**throws** when any of the three required DLLs is absent. The loud failure is
the point: the old behaviour was a build that succeeded, an exe that was
produced, and a program that did not start on the user's machine. Note the
earlier `/MT` rationale depends on this: the stub sits outside `app-files` and
so cannot use these DLLs.

**This does nothing for issue #21, and the resemblance is a trap.** #21 asks
the drive to carry *Otzaria's* dependencies (a C++ runtime, and whatever the
plugin component turns out to be), because the mirror fetches the small
installer rather than the full one. The CRT bundled above is the **launcher's
own** and is invisible to Otzaria: Windows resolves a load-time import from the
directory of the *importing* executable, so DLLs sitting in `app-files\` are
reachable by `launcher_app.exe` alone. Serving #21 means mirroring the
redistributable **installer** and running it on the offline machine — a
system-wide install, not a file copy. A full import scan (`dumpbin /dependents`
over all 18 payload binaries) confirms the launcher now needs nothing beyond
the OS: Win32, the UCRT api-sets, and the graphics/crypto DLLs Windows ships.

**The launcher updates itself by replacing that stub — and `OtzariaData/`
lives *inside* the folder it re-extracts.** `lib/src/self_update/` downloads a
newer packaged exe into `mirror/launcher/`, copies it over the stub (two
renames, rollback on failure — same pattern as the `seforim.db` swap), and
re-launches it with `--after-update=<pid>`. Five things hold it together:

- **The stub never deletes anything.** It extracts the payload *over* the
  existing `app-files\`, so `app-files\OtzariaData\` — settings, the ~1GB
  mirror, the managed Otzaria install — is untouched. A "clean install" that
  wipes `app-files` first would delete exactly what the drive exists to carry.
  Cost of that choice: files removed in a newer version linger. They are inert
  (Flutter resolves assets through its manifest and only loads DLLs it
  imports), and that is the deliberate trade.
- **`.ready` holds the payload version, and that is what triggers a
  re-extract.** It used to be an empty marker file, so a replaced exe would
  have skipped extraction and run the *old* `launcher_app.exe` forever. An
  empty marker written by an older stub does not match, which is what makes
  the first self-update work at all.
- **The version comes from `pubspec.yaml` only.** `build_stub.ps1` generates
  `windows_stub/build/version.h` from it (`PAYLOAD_VERSION_A`, and
  `PAYLOAD_VERSION_COMMAS` for the exe's version resource); `launcherVersion`
  in `launcher_version.dart` must match it numerically, and a test asserts
  that. A tag that disagrees with those two would ship a launcher that reports
  the old number and offers itself the same update forever, so nothing sets
  them by hand: `tool/set_launcher_version.sh` writes both, and CI runs it in
  the build jobs *and* in `publish` with the same value, before the tag is
  created.
- **Versions have two parts (`0.2` → `0.3`); only the second one moves.**
  `pubspec.yaml` still holds `0.2.0` because pub rejects anything that is not
  MAJOR.MINOR.PATCH — that trailing `.0` is a technical detail and never
  reaches the user or `launcherVersion`. This is why `PayloadCheck` compares
  versions numerically rather than as strings.
- **⚠️ The git tag stays three-part (`v0.2.0`) even though the version shown
  is `0.2`.** Every launcher already in the field rejects a tag that is not
  `vX.Y.Z` exactly (`LauncherVersion.isReleaseTag` in the *released* build, not
  the one in this tree), so a `v0.2` release is invisible to all of them — it
  happened once, and the fix was to tag `vX.Y.0` instead. `LauncherRelease.version`
  drops that trailing `.0` again so the user is offered "0.2" and not "0.2.0".
- **The stub waits for the old process before extracting.** `launcher_app.exe`
  and `flutter_windows.dll` are locked while the old launcher runs, so `tar`
  would fail. Hence `--after-update=<pid>` and `WaitForProcessExit`. If
  extraction fails anyway *and* a launcher already exists on disk, the stub
  runs it instead of showing an error: the marker still holds the old version,
  so the next launch retries. The error box is only for "nothing to run at
  all".
- **Only a strict `vX.Y.Z` tag counts as a release, and the highest version
  wins — not the first one listed.** This repo already carries a hand-made
  release tagged **`V1`** ("גירסת בדיקה", with a `default.exe`).
  `normalize('V1')` is `1`, which compares *newer than every 0.x forever*, so a
  first-match-wins client would eventually hand users that stale test build.
  `LauncherVersion.isReleaseTag` rejects any tag that is not exactly
  `v<major>.<minor>.<patch>`, which is precisely what CI publishes. Picking the
  maximum instead of the first also removes the dependence on GitHub's ordering
  (a re-published or edited release moves to the top of `/releases`).
- **`Platform.resolvedExecutable` is the wrong file.** It points into
  `app-files\`; what must be replaced is the stub beside it. The stub therefore
  passes its own path in `OTZARIA_LAUNCHER_STUB`, and
  `LauncherInstallLayout` falls back to "the single `.exe` next to
  `app-files`" for stubs built before that existed.
  `launcher_app/test/stub_contract_test.dart` pins every one of these shared
  names (`app-files`, the env var, the flag, the packaged exe name) across
  `stub.c`, `package.ps1` and the Dart side — they have no compile-time link,
  exactly like the `processNamesFor` pair above.

On macOS the same code replaces the whole `.app` bundle (`ditto`, never
`unzip`) and does **not** restart: `open` on a bundle that was swapped under a
running app is unreliable, so the user is asked to reopen it.

**Some tables carry a UNIQUE constraint above their primary key, and a patch
that trips it is not our bug — but being stuck is.** `tocText.text`,
`author.name`, `source.name`, `topic.name`, `pub_place.name`, `pub_date.date`,
`generation.name`, `connection_type.name`, `book_version(bookId,versionTitle)`
and `alt_toc_structure(bookId,key)` are all `UNIQUE` in the SeforimLibrary
schema, while `kPatchTablesInFkOrder` knows only the PK — so `_runUpserts`
emits `ON CONFLICT(<pk>)`, which does not catch a value that moved from one id
to another, and upserts run *before* deletes. The producer has
`assertNoSecondaryUniqueCollisions` to refuse publishing such a patch; when one
ships anyway (issue #19, v18→v20), the applier blows up mid-transaction. Do not
"fix" this in the engine: it is byte-identical to upstream
`otzaria_library_updater` and to the Kotlin `PatchApplier`, the same patch fails
Otzaria's own online update, and a DB that disagrees with the patch would fail
`verifyToHash` anyway. What we own is the exit: the message names the table and
says a full download is needed, and `LibraryUpdatePlan.fullDownloadFallback`
carries the mirror's full DB alongside every delta plan so
`applyUpdate(useFullDownloadFallback: true)` can recover. That call is
**never** automatic — ~1.5GB copied plus ~5.5GB extracted is the user's
decision, the same reasoning as "no silent network fallback" below.

**An absolute path recorded in `library_state.json` is per-machine, because the
file rides on the drive.** `customDbPath` was one global record, written by
`applyUpdate` after every fresh install and by the manual picker — so a drive
that installed a library on a machine whose account is `user` arrived at the
next machine still pointing at `C:\Users\user\AppData\Roaming\otzaria\books`.
A standard account cannot create a folder under `C:\Users`, so
`applyFullDownload`'s `createSync(recursive: true)` failed with an access error
and the only way out was picking a location by hand (issue #23).
`LibraryStateStore` now keys it under `currentMachineKey()` — hostname **and**
account name, since two accounts on one machine are two `%APPDATA%` roots — and
each machine's own choice survives the trip. A legacy global record (no machine
key) is honoured only when it is absolute *for this platform* and its parent
directory exists here; that is what repairs the drives already in the field
without discarding the choice on the machine that wrote it.

**`otzaria_install_state.json` travels on the drive, so it is never trusted
as-is.** It lives in `OtzariaData/`, i.e. on the flash drive, so an install
recorded on one machine arrives on every other machine the drive is plugged
into. `checkForUpdate` used to accept it verbatim, which is why the launcher
announced "Otzaria is up to date" on two machines that had no Otzaria at all
(issue #19) and `launch()` tried to run a path that did not exist.
`OtzariaManager._verifyStoredState` now checks that `launchPath` still exists
here (a *file* on Windows, an `.app` *directory* on macOS — hence
`FileSystemEntity.typeSync`, not `File.existsSync`) and re-reads the version off
the executable, rejecting the state when it does not. The file itself is **not**
deleted: it may be perfectly valid on the machine the drive returns to. The same
disease is latent in `LibraryStateStore.appliedReleaseTag`, which also travels —
there it can only suppress an update when the version numbers already match.

**Version strings need normalizing before comparison.** An installed build
reports `0.9.96` while the release tag is `0.9.96+736`. `OtzariaUpdateCheckResult`
strips a leading `v` and everything after `+`; without that, every launch sees a
phantom update and re-downloads ~73MB.

**"Different tag" is not "newer tag".** `updateAvailable` used to be pure
inequality, so a user who had installed Otzaria 0.9.97+90970 himself while the
mirror still held 0.9.96+736 was told "ready to install" and offered a
*downgrade*. `compareVersions` orders the base components **numerically** (so
`0.9.9 < 0.9.10`, which a string compare gets backwards) and ranks a
pre-release suffix below the same bare base; `installedIsNewer` then suppresses
the offer. The one downgrade that stays on the table is a deliberate channel
switch — when the installed tag *is* the other mirrored channel's tag, the user
asked for it (see `OtzariaChannelPair`, which only ever holds a prerelease
newer than the stable). Two different suffixes on one base are incomparable and
compare as 0, which keeps the old behaviour there.

**Plugin install-state matching uses `manifestId`, not the catalog `id`.** The
`id` that `otzaria.org/api/plugins` returns is the website's database id;
Otzaria installs under `plugins/installed/<manifest.id>/`. `manifestId` is
extracted from the `manifest.json` inside the already-downloaded `.otzplugin`
(`PluginManifestReader`, BOM-stripped like `LogicalContentHasher`). Compare by
the catalog id and *nothing* is ever detected as installed. A plugin whose file
has not been downloaded yet correctly reports
`PluginInstallStatus.unknown` — that is not an error state.

**A plugin sync plans before it starts, and its counter shows only real
work.** `PluginMirrorSync._plan` decides per plugin what is missing from the
mirror (metadata comparison + file-existence checks, no network), and only
those enter the loop. So `PluginSyncProgress.total` is "how many are being
downloaded", not the size of the store — a store that is fully up to date ends
without a single request after `/api/plugins`, and the UI stops looking like it
re-downloads everything. `PluginSyncOutcome` carries `fetched`/`skipped`/
`failed` out, because the catalog alone reads the same whether nothing needed
downloading or everything failed. `failed` is also what keeps
`PluginsModuleController.onlineStatus` honest: a sync that could not fetch a
file leaves the "there is something new online" answer standing.

**A plugin sync downloads only what changed — images included.** The
`.otzplugin` file was always skipped when the version matched, but the image
and every screenshot of *every* plugin were re-fetched on each sync "because
they are small". Over a whole store that is the store downloaded again, for
one plugin that moved. `catalog.json` now also records where each asset came
from (`remoteImageUrl`, `remoteScreenshotUrls`), and an asset is fetched only
when that URL changed, when the plugin's `updatedAt` moved (the site can swap
an image under the same URL), or when the file is missing from the mirror.
Screenshots are all-or-nothing — their file names are `screenshot-<index>`, so
a changed list must re-fetch the whole series or the contents shift between
indices.

**An empty recorded URL means "old catalog", not "changed"** (`_sameSource`).
A mirror written before those fields existed has none of them, and treating
that as a difference re-downloaded every image in the store on the first sync
after the upgrade — the exact behaviour this removed, appearing one last time
at the worst moment. The comparison falls back to `updatedAt` plus the file
being on disk, and the URL is written into the catalog even when nothing is
downloaded, so the migration closes itself.

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

**Everything about plugins hangs off the Otzaria launch path the launcher
already detected** (`OtzariaModuleController.launchPath`, the same value
`LibraryDbLocator` gets). Two consequences, both load-bearing for a **portable**
Otzaria:

* `InstalledPluginsScanner` derives the plugins folder from it —
  `<exeDir>/otzaria_data/plugins` when `portable.marker` sits next to the
  executable **or that data folder already exists** (deliberately wider than
  `LibraryDbLocator`, which demands the marker), and only otherwise
  `%APPDATA%\otzaria\plugins`, then the system-wide install. The marker name
  and data-folder name are duplicated in `plugins_manager` and `library_manager`;
  `launcher_app/test/portable_paths_test.dart` verifies they never drift.
* `PluginDirectInstaller` hands the very same `otzaria://…` URL straight to that
  executable as its first argument — exactly what the registry handler would do
  (`"otzaria.exe" "%1"`). A portable install never registers the `otzaria://`
  scheme, so going through the OS was a guaranteed "make sure Otzaria is
  installed" failure there. Without a known path (or when it no longer exists)
  the OS protocol handler is still the fallback.

Because the launch path is only known after `OtzariaManager.checkForUpdate`,
`AppShell.checkAll()` re-scans the installed plugins right after it
(`PluginsModuleController.refreshInstalled`), and so does the manual
"pick the install folder" flow. Dropping those calls leaves the store showing a
scan of the wrong folder until the next launch.

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

**Downloads are parallel *across files*, never *within* a file — and that is
not a design preference, it is what the server allows.** Issue #17 asked for a
"download accelerator". The classic kind splits one file over N connections via
`Range`, and GitHub's release CDN (`release-assets.githubusercontent.com`,
an Azure Blob SAS behind a proxy) **strips it**: it answers `200` with the full
body to every `Range` request — and to `x-ms-range` too — while still
advertising `Accept-Ranges: bytes`. Verified five ways in August 2026. That is
also why resume never actually works against GitHub, which the code already
knew (`PatchDownloader._streamToFile` treats "server ignored Range → 200" as a
restart). What the CDN *does* throttle is **each connection separately**:
measured ~0.7MB/s on one connection versus ~2.1MB/s aggregate on four. So the
only accelerator that exists here is running different files at once.

`DownloadScheduler` (root package, exported) is that pool, and it is a
**shared semaphore on purpose**: `LibraryManager` hands the same instance to
`LibraryMirrorExporter` and to `CompanionAssetsMirror`, and then runs those two
concurrently — the ~509MB of companions used to queue behind the ~1.55GB DB for
no reason. One instance means the two stages together still never open more
than four connections. `plugins_manager` cannot depend on the root package (it
is pure Dart, the root is Flutter), so it carries its own 40-line `runPooled`;
keep the two in step conceptually, and do not "unify" them by adding a
cross-package dependency.

Three consequences that are load-bearing:

- **The biggest asset starts first** (`jobs.sort` by size, descending). With
  the ~1.55GB DB last, every other connection sits idle while it runs alone.
- **The byte counter is one aggregate for the whole download**
  (`ByteProgressAggregator`), not per file — in parallel there is no "current
  file". Each download gets its own `slot()`, and a slot only ever moves
  **up**: an asset that is already complete reports its full size and then
  re-hashes from zero on the same sink, which without the high-water mark
  dropped the bar mid-download. `LibraryModuleController` therefore must **not**
  null the byte fields on `onStage` any more; doing so blanks a bar that is
  in fact advancing.
- **A failed task stops new ones from starting but still awaits the ones
  already running**, before rethrowing. A download left running in the
  background keeps writing into the mirror after `MirrorDownloadUndo` has
  already cleaned it.

Deliberately *not* parallelised: `OtzariaAppMirror.sync` (two installers,
~6% of the bytes, and its `onChannelStart` progress UI assumes one channel at
a time) and the module ordering in `AppShell.downloadAll`.

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

**A fresh install lands in those same places — never in the launcher's own
folder.** `LibraryDbLocator.resolveInstallDbPath()` answers "where does a *new*
library go": the user's own choice if there is one (**even when the file does
not exist yet** — in a fresh install that path is the *target*, so the
existence check that `resolveDbPath` applies would be wrong), otherwise
Otzaria's own setting, otherwise the platform default. `checkForUpdate` used to
point at `<dataDir>/library/seforim.db` instead, which for a launcher running
off a USB drive installed the ~5.5GB library **onto the drive** — it travelled
away with it and vanished from the computer. `<dataDir>` survives only as the
last-resort fallback for a platform with no known location at all.
`isKnownToOtzaria(dbPath)` is the inverse question — will Otzaria find this file
by itself? A `false` there is what makes `LibraryScreen` demand an explicit
confirmation: any location outside those candidates is allowed, but only after
a dialog saying the user must point Otzaria's own library-location setting at
it, or Otzaria will see no books there.

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

**A DB updated from outside leaves Otzaria's search index stale, and the fix
is a deep link — not a file.** Otzaria re-indexes exactly the books
`PatchApplier` reports in `booksTouched` (or runs `ReconcileIndex` after a full
download); neither path runs when *we* write the DB, and startup indexing only
adds *new* books, so search in a changed book returns its old content. We asked
the Otzaria developers to read a file (`OTZARIA_REINDEX_REQUEST.md`); what they
shipped instead (`dev`, `78f395f3`) is **`otzaria://library/reindex`** —
parameterless, reloads the catalogue and runs `StartIndexing` +
`ReconcileIndex`, even when their "auto index update" setting is off. Their
fingerprint comparison finds the changed books itself, so `booksTouched` is not
needed on their side.

Three things about our half:

- **`.otzaria-external-update.json` is now our own pending marker**, not a
  message to Otzaria. `applyUpdate` writes it next to the DB; it survives
  launcher restarts, `LibraryManager.pendingReindexRequest()` reads it, and
  `clearReindexRequest()` deletes it **only after the request was actually
  delivered**. Clearing it on the *offer* (or on a failed launch) would leave
  the index on the old content with nobody aware — hence
  `onLaunchUriDelivered` fires after `launch()` returns, never before.
- **The link is handed to the detected executable as an argument**
  (`otzaria.exe <url>`, `open -a` on macOS), not to the OS protocol handler —
  same reason as `PluginDirectInstaller`: a portable install never registers
  the `otzaria://` scheme. A running instance receives it through Otzaria's
  single-instance forwarding. `OtzariaModuleController` therefore takes an
  injectable `OtzariaLauncher`: without that seam, any test touching `launch()`
  starts the real Otzaria on the machine running the suite — and asks it to
  reindex.
- **Every normal "launch Otzaria" carries a pending request along.** The
  explicit tile in `LibraryScreen` and the dialog after an update are not
  enough on their own: a user who opens Otzaria from a desktop shortcut never
  delivers it, and that gap is the accepted cost of a link-based fix.

**Where a fresh Windows install goes is the installer's call, not ours.**
`installFromFile` passes `/DIR=` **only when updating an install we already
know about**; for a fresh one it passes no `/DIR=` at all and then finds the
result through detection (`InstallLocation` in the uninstall registry, then the
known dirs). The reason is a landmine that already bit once: this repo recorded
`{autopf}\Otzaria` as "the installer's real default, verified against the
Otzaria developers (2026-08-07) — not a guess", and `installer/otzaria.iss` in
`Otzaria/otzaria` says `DefaultDirName=C:\אוצריא`. A copied default silently
drifts from the thing it copies; the installer always knows its own default, so
let it choose. `_windowsRealDefaultDirs` (`{autopf}\Otzaria`,
`%ProgramFiles%\Otzaria`, `{Program Files}\אוצריא`, `C:\אוצריא`) is now a
**detection** list only, and `resolveDefaultInstallDir()` is a Windows *display*
value plus the real macOS target — never an install argument on Windows. Verify
installer facts against **`Otzaria/otzaria`** (what `OtzariaReleaseClient`
downloads); `Sivan22/otzaria` also has an `installer/` folder with
similar-but-different scripts, and reading the wrong one produces confident
wrong answers. On macOS the same method returns
`/Applications`, falling back to `~/Applications` when the account cannot write
there. This is a *different*
directory from where the library DB lives (`%APPDATA%\otzaria\`, see above) —
don't conflate the two when debugging "Otzaria not detected" reports. Before
this was added, `OtzariaManager._autoDetectDirs` on Windows checked **only**
the launcher's own managed install folder, so any Otzaria installed
independently (via the real installer, or before the "data folder next to the
executable" rework moved that managed folder) was invisible to auto-detect —
the manual "בחירת מיקום ידנית" picker (`OtzariaModuleController.adoptInstallDir`)
is the fallback for anything these paths don't cover.

**The Windows uninstall registry beats all of those guesses.**
`WindowsInstallRegistry` reads `InstallLocation` out of the Inno Setup entries
under `…\CurrentVersion\Uninstall` (HKCU first, then HKLM 64- and 32-bit), so an
install in a folder nobody guessed is found *with Otzaria closed* — the case
`RunningOtzariaLocator` cannot cover. Only the **directory** comes from there;
the version is still read from the exe, because `DisplayVersion` records what
the installer wrote, not what is on disk now. The scan costs ~200ms, so
`checkForUpdate` builds `_autoDetectDirs` only when nothing is known yet.

**Never return the first `.exe` in the install folder.** `crashpad_handler.exe`
ships next to `otzaria.exe` and sorts before it, *and* carries a version
resource of its own (0.15.4) — so `OtzariaAppLocator` reporting the first match
produced a confident, completely wrong "installed version" plus a `launchPath`
that ran the crash handler. A name match (`OtzariaAppLocator.mentionsOtzaria`)
wins outright; known Flutter helper exes are excluded; anything else is only a
fallback, kept so a rename of the app's exe does not break detection.

**A name match must never match the launcher itself.** The Windows stub is
`עדכוני אוצריא.exe` (`windows_stub/package.ps1`), whose name *contains*
`אוצריא` — so the "name match wins outright" rule above made the launcher adopt
itself the moment a scanned directory contained it, which `C:\אוצריא` and
`%LocalAppData%\Programs\Otzaria` both realistically can. **The same file
travels under a second name:** GitHub strips non-ASCII characters from release
asset names, so an all-Hebrew name is erased down to `default.exe` (which is
what `V1` and `v0.1.1` actually published). The `publish` job therefore uploads
it as `Otzaria-Updates.exe` — a name that contains `otzaria`, and the one that
sticks for anyone who downloaded manually. Both names are excluded
(`_ourOwnExeNames`, pinned from the launcher side through
`OtzariaAppLocator.isOurOwnExe`) and both are tie-breakers in
`LauncherInstallLayout`. It then read its own
version resource as "the installed Otzaria" and `launch()` re-ran the launcher.
`OtzariaAppLocator._ourOwnExeNames` (plus a `Platform.resolvedExecutable`
check) excludes both of our exes. This is the file-scan twin of the
`pgrep -f` hazard already documented above — same trap, different mechanism.

**The Windows exe scan is breadth-first and depth-capped**
(`defaultWindowsMaxDepth`), exactly like the macOS one. Two reasons, both real:
`Directory.list(recursive: true)` has no defined order, so a nested exe could
beat the one at the install root and the answer differed between machines; and
`C:\אוצריא` is *both* an auto-detect install dir and a common `seforim.db`
library location, so an unbounded scan walked a ~1GB books tree on every
`checkForUpdate()` for anyone whose app is not installed there.

**A custom app learns how to detect itself, and a learned `DisplayName` is
not a usable regex.** The form cannot ask "where will this install" or "what
is the exe called" — on the online machine, where the record is created, the
program is not installed at all. `InstallLearner` (`custom_apps_manager`)
therefore snapshots the uninstall registry *before* running the installer and
looks for the key that was born. Four things are load-bearing:

- **A re-install does not create a new key**, and that is the common case, not
  an edge case: whoever already has the program updates the *same* key. The
  first version of this required a newly-born key, so it learned nothing
  precisely for the users who already had the program working (verified on real
  hardware against `KleiKodesh`). The pick therefore runs in three tiers — a key
  that was **born**, a key that **changed** while we installed, then an
  **existing** key whose name matches. The last two require a name match:
  browsers and system updaters rewrite registry entries in the background with
  no relation to us. And any name match beats a nameless guess — the "single
  fresh entry" fallback runs *last*, after all three tiers, or an installer that
  dragged one companion entry along would be adopted over the program's own
  entry that merely got updated.
- **Exit code 0 does not mean the install finished.** Inno's `setup.exe`
  extracts a temp copy and launches a second process (certainly when it
  elevates), so the registry entry can be written after the process we ran has
  already returned. A single read right after the run is too early — hence a
  **bounded re-poll** (60s, backing off from 500ms to 4s, because the registry
  scan itself costs ~200ms). "No entry appeared" is a normal outcome, not an
  error: a portable program registers no uninstall entry at all.
- **The learned directory is never written to the record.** `descriptor.json`
  travels on the drive, so an absolute path in it is exactly the
  `otzaria_install_state.json` disease. It goes to `locations.json`, which is
  per-host — and that happens for free, because `install` calls
  `detectInstalled` on the freshly-learned record and *that* records the
  location it found. Only `exeName` and `registryDisplayName` — facts about the
  program, not about the machine — reach the record.
- **`registryDisplayName` is a pattern, never the raw `DisplayName`.**
  `MyApp 1.4.2 (x64)` is two bugs at once: the parens and dots are regex
  metacharacters, and the embedded version stops matching the moment the
  program updates. `RegistryDisplayNamePattern` cuts the tail from the version
  on, escapes the rest, anchors at the start and adds a lookahead so `Git` does
  not swallow `GitHub Desktop`. Same trap `GithubAssetPattern` exists for.
  Compiling it goes through `RegistryDisplayNamePattern.compile`, never a bare
  `RegExp(...)`: a `FormatException` inside detection is swallowed upstream, and
  the result was a program reporting "not installed" forever with no sign
  anything broke.
- **`WindowsInstallRegistry.entries()` is what makes learning possible, and
  the two registry seams are needed together.** `installDirs()` throws the
  `DisplayName` away, and it also filters out an entry whose directory does not
  exist — for a before/after diff that entry *is* the evidence. `entries()`
  keeps both plus the key name, which is the stable identity (the `DisplayName`
  carries the version and changes with it). `UninstallEntriesLookup` learns the
  pattern; `UninstallDirLookup` is what turns it into detection. With only one
  of them wired, the record updates and the app still reports "not installed".

**Never pick the first `.exe` when learning either.** The learned exe name goes
through `OtzariaAppLocator.findIn(nameMatches:)` — the same verified scanner,
with an injected name predicate instead of `nameLooksLikeOtzaria`. The form's
own suggestion used to take the first `.exe` from `listSync()`: undefined order,
no `unins*` exclusion, no Flutter-helper exclusion. In a real Flutter app folder
that returns `crashpad_handler.exe`, which is the landmine documented right
below this one.

**Only `DisplayName` identifies an entry in the uninstall registry.** Matching
on `InstallLocation` too let any third-party program in a path merely
mentioning "otzaria" enter `_autoDetectDirs`, where `sharedDir: false` means no
further identity check at all. Both real Inno entries write a `DisplayName`
("אוצריא גירסה …"), verified against a real machine. `UninstallString` is only
a fallback for the *directory*, and it must be parsed as a command line, not a
path: `MsiExec.exe /X{GUID}` through `p.dirname` yields a **relative** string,
because `package:path` treats the `/switch` as a path segment.

---

## 6. Verification status (read before claiming something works)

The package READMEs each carry a "what was actually verified" section — trust
those over assumptions, and update them when you verify something new.

Also **not** verified end-to-end: the plugin store's real round trip — an actual
`sync()` against `otzaria.org`, carrying `OtzariaData/` on a USB drive to an
offline machine, and `otzaria://plugin/install-local` against a real Otzaria
install. Unit-tested logic only; see `plugins_manager/README.md`.

The launcher's **self-update** is unit-tested end to end on the Dart side (the
GitHub client against a mock, the mirror round trip, the executable-location
fallbacks, and the real file swap in a temp dir that asserts `OtzariaData/`
survives), and `stub.c` compiles clean at `/W4` with the generated
`version.h`. What has **not** run on real hardware: a full round trip — publish
a tag, let a shipped exe find it, download it to a USB drive, replace itself and
come back up in the new version. In particular the `--after-update=<pid>` wait,
the re-extract over a live `app-files\`, and the macOS bundle swap have never
executed outside tests.

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
`RunningOtzariaLocator`'s FFI half (`QueryFullProcessImageNameW`), and the
Windows `.db` file picker filter. `WindowsExeVersionReader` and
`WindowsInstallRegistry` **were** run against a real install
(`otzaria.exe` 0.9.96+90960, Windows 11, 2026-08-10). The macOS path of
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
