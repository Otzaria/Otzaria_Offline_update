"""Plan native CI work; uncertainty schedules work instead of hiding a check.

Only PRs with explicitly audited non-runtime paths can avoid native work.
Pushes run all native work; Linux checks and Windows coverage are never filtered.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

PACKAGES = frozenset({
    "launcher_app", "library_manager", "otzaria_manager", "otzaria_downloads",
    "otzaria_l10n", "plugins_manager", "custom_apps_manager", "error_reports_manager",
})
MAC_TEST_PACKAGES = PACKAGES - {"otzaria_downloads", "otzaria_l10n"}
# Do not use '*.md': launcher_app/assets/יומן שינויים.md is shipped in the app.
DOCUMENTATION = frozenset({
    "README.md", "AGENTS.md", "CLAUDE.md", "CHANGELOG.md", "LICENSE",
    *(f"{package}/README.md" for package in PACKAGES),
})
PORTABLE_TOOLS = frozenset({
    "tool/coverage.dart", "test/coverage_report_test.dart", "test/engine_pin_test.dart",
})
SHA = re.compile(r"[0-9a-f]{40}\Z")


@dataclass(frozen=True)
class Plan:
    macos: bool
    macos_build: bool
    windows_build: bool
    reason: str

    @classmethod
    def full(cls, reason: str) -> Plan:
        return cls(True, True, True, reason)

    def outputs(self) -> dict[str, str]:
        return {key: str(value).lower() for key, value in asdict(self).items()
                if isinstance(value, bool)}


def classify_paths(paths: list[str]) -> Plan:
    macos = macos_build = windows_build = False
    for path in paths:
        # Git returns literal POSIX paths. Never normalize an unexpected path
        # into the allowlist (backslashes and newlines can be real file names).
        if path in DOCUMENTATION or path in PORTABLE_TOOLS:
            continue
        package, separator, relative = path.partition("/")
        if package in PACKAGES and separator and relative.startswith("test/"):
            macos |= package in MAC_TEST_PACKAGES
            continue
        if path.startswith(("launcher_app/windows/", "launcher_app/windows_stub/")):
            windows_build = True
            continue
        if path.startswith("launcher_app/macos/"):
            macos = macos_build = True
            continue
        # Shared source, assets, dependencies, CI and all future/unknown paths.
        return Plan.full("Runtime, CI, dependency or unclassified path changed")
    return Plan(macos, macos_build, windows_build, "Audited changed-path classification")


def git(repo: Path, *args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=repo, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=30).stdout


def checked_sha(value: Any) -> str:
    if not isinstance(value, str) or not SHA.fullmatch(value) or set(value) == {"0"}:
        raise ValueError("Missing or invalid commit")
    return value


def changed_paths(repo: Path, event_name: str, event: dict[str, Any],
                  checkout_sha: str) -> list[str]:
    checkout_sha = checked_sha(checkout_sha)
    if git(repo, "rev-parse", "HEAD").decode().strip() != checkout_sha:
        raise ValueError("Checkout does not match the event commit")
    if event_name == "pull_request":
        pr = event["pull_request"]
        base, head = checked_sha(pr["base"]["sha"]), checked_sha(pr["head"]["sha"])
        git(repo, "merge-base", "--is-ancestor", base, checkout_sha)
        git(repo, "merge-base", "--is-ancestor", head, checkout_sha)
        start = checked_sha(git(repo, "merge-base", base, head).decode().strip())
        # Diff the entire PR AND its integrated base, not just the last push.
        # Base-branch changes can make a docs-only PR exercise new native code.
        end = checkout_sha
    elif event_name == "push":
        start, end = checked_sha(event["before"]), checked_sha(event["after"])
        if end != checkout_sha:
            raise ValueError("Push and checkout commits differ")
    else:
        raise ValueError("Unclassified event")
    data = git(repo, "diff", "--name-only", "--no-renames", "-z", start, end, "--")
    # --no-renames includes BOTH sides of moves; -z handles Unicode/newlines.
    if data and not data.endswith(b"\0"):
        raise ValueError("Incomplete git diff")
    return [path.decode("utf-8") for path in data.split(b"\0") if path]


def plan_for_event(repo: Path, event_name: str, event: dict[str, Any],
                   checkout_sha: str, release: bool = False) -> Plan:
    if release or event_name == "workflow_dispatch":
        return Plan.full("Explicit full CI / release")
    if event_name == "push":
        # A newer push can cancel native work for changes outside its own diff.
        return Plan.full("Push replaces earlier runs: validate all native work")
    try:
        if event_name == "pull_request":
            draft = event["pull_request"]["draft"]
            if not isinstance(draft, bool):
                raise ValueError("Missing draft state")
            if draft:
                return Plan(False, False, False, "Draft PR: native work waits for ready_for_review")
        return classify_paths(changed_paths(repo, event_name, event, checkout_sha))
    except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
        return Plan.full("Incomplete event/history: run all native work")


def check_results(needs: dict[str, Any]) -> list[str]:
    """A skipped dependency must not turn a failed workflow into a green gate."""
    errors = []
    for job in ("version", "linux_checks", "coverage", "coverage_total"):
        result = needs.get(job, {}).get("result")
        if result != "success":
            errors.append(f"{job}: expected success, got {result!r}")
    outputs = needs.get("version", {}).get("outputs", {})
    for flag in ("macos", "macos_build", "windows_build"):
        if outputs.get(flag) not in ("true", "false"):
            errors.append(f"Missing/invalid native plan output: {flag}")
    if outputs.get("macos_build") == "true" and outputs.get("macos") != "true":
        errors.append("A macOS build requires the macOS job")
    for job, flag in (("launcher_app_macos", "macos"), ("launcher_app", "windows_build")):
        allowed = {"success"} if outputs.get(flag) == "true" else {"success", "skipped"}
        result = needs.get(job, {}).get("result")
        if result not in allowed:
            errors.append(f"{job}: unexpected result {result!r}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("plan", "check"))
    args = parser.parse_args()
    if args.command == "check":
        try:
            errors = check_results(json.loads(os.environ["CI_NEEDS"]))
        except (KeyError, TypeError, AttributeError, ValueError):
            errors = ["Cannot read CI job results"]
        for error in errors:
            print(error)
        return int(bool(errors))
    if os.environ.get("CI_RELEASE") == "true":
        plan = Plan.full("Explicit full CI / release")
    else:
        try:
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
            plan = plan_for_event(Path.cwd(), os.environ.get("GITHUB_EVENT_NAME", ""),
                                  event, os.environ.get("GITHUB_SHA", ""))
        except (KeyError, TypeError, ValueError, OSError):
            plan = Plan.full("Cannot read event: run all native work")
    print(json.dumps(asdict(plan), ensure_ascii=False, indent=2))
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in plan.outputs().items():
            output.write(f"{key}={value}\n")
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a", encoding="utf-8") as output:
            output.write(f"### Native CI plan\n\n{plan.reason}\n\n")
            for key, value in plan.outputs().items():
                output.write(f"- `{key}`: `{value}`\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
