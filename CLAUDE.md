# CLAUDE.md

The full agent contract for this repository lives in [AGENTS.md](AGENTS.md) —
read it before making changes. It covers what this software is for (an offline
update path for Otzaria: download on an online computer, carry the USB drive to
the offline one, apply there), the four-package layout, and the landmines that
must not be broken.

The two rules that apply to *every* change:

1. **Format and analyze when you are done.** In each package you touched:
   `dart format .`, then `flutter analyze --no-fatal-infos`
   (root / `library_manager` / `launcher_app`) or `dart analyze`
   (`otzaria_manager`). The root `analysis_options.yaml` excludes the
   sub-packages, so analyzing from the root does not cover them.
2. **Keep code comments short** — one or two lines, explaining *why*. Longer
   explanations belong in the package README or CHANGELOG. Comments and
   doc-comments are written in Hebrew, matching the existing code.

Reply to the user in Hebrew.
