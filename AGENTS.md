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
2. They plug the drive into a computer **that does have internet**, run the
   launcher from there, and it downloads:
   - library (`seforim.db`) updates for Otzaria — full DB or delta patches,
   - Otzaria app updates,
   - (planned) Otzaria plugin updates.
   Everything lands in a self-contained **offline mirror** folder on the drive.
3. They unplug the drive, plug it into **their own offline computer**, run the
   launcher again, and it applies the update from the drive — no network needed.

So the guiding principle for every change: **anything the update path needs must
be able to come from a local folder, and the apply step must work with the
network completely unavailable.** Downloading and applying are deliberately two
separate phases that can happen on two different computers, days apart.

The offline mirror is the mechanism that makes this work:

| Step | API | Runs on |
| --- | --- | --- |
| Build/refresh the mirror | `LibraryManager.exportOfflineMirror(destDir:)` / `refreshOfflineMirrorCache()` | the online computer |
| Point the launcher at a mirror | `LibraryManager.useLocalMirror(mirrorDir)` | the offline computer |
| Back to network mode | `LibraryManager.useCloud()` | either |

`refreshOfflineMirrorCache()` also runs in the background on every launch into
`<dataDir>/offline-mirror`, so a machine that goes online once stays usable
offline afterwards.

Beyond the offline case, the launcher is also just a normal unified dashboard:
check / install / launch Otzaria, and update its database.

---

## 2. Repository layout

Four separate Dart/Flutter packages, each with its own `pubspec.yaml`. The main
package sits at the repo root (historical, do not move it).

| Path | Package | Role |
| --- | --- | --- |
| `.` (root, `lib/`) | `seforim_library_updater` | Flutter package. The client side of the `Otzaria/SeforimLibrary` delta release format: discover releases, plan an update route (delta vs. full), download, verify the logical content hash, apply patches atomically. |
| `otzaria_manager/` | `otzaria_manager` | Pure Dart (no Flutter). Manages the **Otzaria app itself**: check latest release, download, silent install, launch. Windows + macOS. |
| `library_manager/` | `library_manager` | Flutter package. Wires `seforim_library_updater` into the launcher: locate the user's real `seforim.db`, check versions, apply updates to the **live** DB, export/consume the offline mirror. |
| `launcher_app/` | `launcher_app` | The Flutter desktop app (Windows + macOS) that wires the modules into one dashboard. Depends on the other three via relative `path:`, so it must stay a sibling of them. |
| `plugins_manager` | — | **Not built yet.** The dashboard shows a disabled "coming soon" card in its place. |

Producer vs. consumer: the Kotlin repo `Otzaria/SeforimLibrary` *produces* the DB
and the patches; this repo only *consumes* them.

---

## 3. Mandatory workflow after every change

Run these at the end of every change, in the package(s) you touched. This is not
optional and not something to defer to CI.

```bash
# 1. Format
dart format .

# 2. Analyze
flutter analyze --no-fatal-infos   # seforim_library_updater (root), library_manager, launcher_app
dart analyze                      # otzaria_manager (pure Dart)
```

Notes:

- The root `analysis_options.yaml` **excludes** the sub-packages, so analyzing
  from the root does *not* cover them. `cd` into each package you changed and
  analyze there.
- Run the relevant tests too when logic changed: `flutter test` (root,
  `library_manager`, `launcher_app`) or `dart test` (`otzaria_manager`).
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
- Do not silently widen scope. Fix what was asked, then say what you left out.

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

**The launcher's macOS process name must not be `אוצריא`.** `PRODUCT_NAME` is
`Otzaria Launcher` for exactly that reason — see the table in
`launcher_app/README.md`.

**`launcher_app/macos/` is tracked in git** and contains non-default settings
(product name, bundle id, sandbox disabled). Never run
`flutter create --platforms=macos .` — it overwrites them. `windows/` is the
opposite: it is generated in CI.

**The `inno_bundle:` GUID in `launcher_app/pubspec.yaml` is frozen.** Changing it
makes Inno Setup treat new builds as a different application for everyone who
already installed.

**Version strings need normalizing before comparison.** An installed build
reports `0.9.96` while the release tag is `0.9.96+736`. `OtzariaUpdateCheckResult`
strips a leading `v` and everything after `+`; without that, every launch sees a
phantom update and re-downloads ~73MB.

**Release selection ignores `prerelease`.** `OtzariaReleaseClient` takes the
newest release regardless of the prerelease flag, because the Otzaria repo
(`github.com/Sivan22/otzaria`) has published almost nothing stable since 2025.
This was an explicit product decision, not an oversight.

**DB location is discovered, not assumed.** `LibraryDbLocator` checks, in order:
a path we saved ourselves, then `%APPDATA%\otzaria\books\`, `%ProgramData%\otzaria\books\`
(Windows) or `~/Library/Application Support/otzaria/books/` and the system-wide
equivalent (macOS), then falls back to `C:\אוצריא\`. If nothing is found it
returns `null` and the UI must ask the user to point at the file. Do not
hardcode a path here — a previous confident claim about the "real" location was
simply wrong.

---

## 6. Verification status (read before claiming something works)

The package READMEs each carry a "what was actually verified" section — trust
those over assumptions, and update them when you verify something new.

Currently **not** verified on real hardware: the Windows path of
`LibraryUpdateApplier` (full ~1GB download, delta chains, `tasklist` behaviour),
`WindowsExeVersionReader` (FFI via `package:win32`), the Windows `.db` file
picker filter, and the `inno_bundle` output path. The macOS path of
`otzaria_manager` and the launcher build/run on macOS **were** verified against a
real `otzaria-macos.zip`.

Known MVP limitation: the fullDownload route decompresses in memory (up to
~1.1GB of RAM). Streaming extraction is the natural follow-up if that hurts.

---

## 7. Communication

Reply to the user in Hebrew (per their global preference). Code, identifiers,
commands and this file stay in English.
