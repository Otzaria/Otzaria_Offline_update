"""Regression tests run before native CI is scheduled; Python standard library only."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from native_plan import Plan, check_results, classify_paths, plan_for_event


class ClassificationTests(unittest.TestCase):
    def test_root_and_package_documentation(self):
        self.assertEqual(classify_paths(["README.md", "AGENTS.md", "CHANGELOG.md",
                                        "library_manager/README.md"]).outputs(),
                         {"macos": "false", "macos_build": "false", "windows_build": "false"})

    def test_packaged_markdown_is_runtime(self):
        self.assertTrue(classify_paths(["launcher_app/assets/יומן שינויים.md"]).macos_build)

    def test_unknown_markdown_is_not_assumed_documentation(self):
        self.assertTrue(classify_paths(["new-package/README.md"]).macos_build)

    def test_portable_root_tools(self):
        self.assertFalse(classify_paths(["tool/coverage.dart", "test/engine_pin_test.dart",
                                         "test/coverage_report_test.dart"]).macos)

    def test_macos_package_test_does_not_rebuild_app(self):
        plan = classify_paths(["launcher_app/test/otzaria_controller_test.dart"])
        self.assertEqual((plan.macos, plan.macos_build, plan.windows_build), (True, False, False))

    def test_macos_test_fixtures_still_run_tests(self):
        self.assertTrue(classify_paths(["library_manager/test/support/native_vector_set/model.json"]).macos)

    def test_windows_covered_packages_do_not_add_a_new_macos_suite(self):
        self.assertFalse(classify_paths(["otzaria_downloads/test/windows_elevation_test.dart",
                                        "otzaria_l10n/test/button_quotes_test.dart"]).macos)

    def test_windows_native_change(self):
        plan = classify_paths(["launcher_app/windows_stub/package.ps1"])
        self.assertEqual((plan.macos, plan.macos_build, plan.windows_build), (False, False, True))

    def test_macos_native_change(self):
        plan = classify_paths(["launcher_app/macos/Runner/MainFlutterWindow.swift"])
        self.assertEqual((plan.macos, plan.macos_build, plan.windows_build), (True, True, False))

    def test_mixed_native_changes(self):
        self.assertEqual(classify_paths(["launcher_app/windows/a.cpp", "launcher_app/macos/a.swift"]).outputs(),
                         Plan.full("unused").outputs())

    def test_runtime_ci_dependencies_and_unknown_paths_run_all(self):
        for path in ("launcher_app/lib/main.dart", "otzaria_l10n/lib/strings.dart",
                     "pubspec.lock", "launcher_app/pubspec.yaml", "tool/ci/native_plan.py",
                     ".github/workflows/ci.yml", "new-package/source.data", "test/new_test.dart"):
            with self.subTest(path=path):
                self.assertEqual(classify_paths([path]).outputs(), Plan.full("").outputs())

    def test_no_path_normalization_into_allowlist(self):
        for path in ("./README.md", "../README.md", "README.md\nlib/a.dart", "README.md ",
                     "launcher_app\\README.md"):
            with self.subTest(path=path):
                self.assertTrue(classify_paths([path]).macos_build)

    def test_changed_file_order_does_not_matter(self):
        paths = ["README.md", "launcher_app/test/a.dart", "launcher_app/macos/a.swift"]
        self.assertEqual(classify_paths(paths), classify_paths(paths[::-1]))

    def test_no_file_count_limit(self):
        self.assertTrue(classify_paths(["README.md"] * 4000 + ["launcher_app/lib/main.dart"]).macos_build)

    def test_empty_diff_does_not_schedule_native(self):
        self.assertFalse(classify_paths([]).macos)


class GitPlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "CI test")
        self.git("config", "user.email", "ci-test@example.invalid")
        # Isolate temporary test commits from the developer's global signing/hooks.
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", str(self.repo / "empty-hooks"))
        self.git("config", "core.autocrlf", "false")
        self.base = self.commit("README.md", "initial\n")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, name, content):
        file = self.repo / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf-8")
        self.git("add", "--", name)
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def pr(self, head, base=None, draft=False):
        return {"pull_request": {"draft": draft, "base": {"sha": base or self.base},
                                 "head": {"sha": head}}}

    def plan(self, event_name, event, sha=None, release=False):
        return plan_for_event(self.repo, event_name, event,
                              sha or self.git("rev-parse", "HEAD"), release)

    def test_documentation_push(self):
        head = self.commit("README.md", "documentation\n")
        self.assertFalse(self.plan("push", {"before": self.base, "after": head}).macos)

    def test_whole_pr_not_only_last_documentation_commit(self):
        self.commit("launcher_app/lib/main.dart", "changed code\n")
        head = self.commit("README.md", "documentation\n")
        self.assertTrue(self.plan("pull_request", self.pr(head)).macos_build)

    def test_merge_base_changes_are_not_lost(self):
        self.git("switch", "-qc", "topic")
        head = self.commit("README.md", "PR docs\n")
        self.git("switch", "-q", "main")
        base = self.commit("launcher_app/lib/main.dart", "new base code\n")
        self.git("merge", "--no-ff", "-qm", "synthetic merge", "topic")
        self.assertTrue(self.plan("pull_request", self.pr(head, base)).macos_build)

    def test_rename_checks_old_and_new_path(self):
        before = self.commit("runtime.dart", "same content\n")
        self.git("mv", "runtime.dart", "README-renamed.md")
        self.git("commit", "-qm", "rename")
        head = self.git("rev-parse", "HEAD")
        self.assertTrue(self.plan("push", {"before": before, "after": head}).macos_build)

    def test_delete_runtime_is_a_change(self):
        before = self.commit("launcher_app/lib/a.dart", "code\n")
        self.git("rm", "launcher_app/lib/a.dart")
        self.git("commit", "-qm", "delete")
        self.assertTrue(self.plan("push", {"before": before, "after": self.git("rev-parse", "HEAD")}).macos)

    @unittest.skipIf(os.name == "nt", "Newline is not a valid Windows file name")
    def test_newline_and_hebrew_filename(self):
        head = self.commit("launcher_app/assets/תוכן\nfile.md", "asset\n")
        self.assertTrue(self.plan("push", {"before": self.base, "after": head}).macos_build)

    def test_missing_history_runs_everything(self):
        self.assertTrue(self.plan("push", {"before": "a" * 40, "after": self.base}).windows_build)

    def test_zero_before_runs_everything(self):
        self.assertTrue(self.plan("push", {"before": "0" * 40, "after": self.base}).macos)

    def test_mismatched_checkout_runs_everything(self):
        head = self.commit("README.md", "new docs\n")
        self.assertTrue(self.plan("push", {"before": self.base, "after": head}, sha=self.base).macos)

    def test_malformed_events_fail_open(self):
        for event in ({}, {"pull_request": {}}, {"pull_request": {"draft": "false"}}, None, []):
            with self.subTest(event=event):
                self.assertTrue(self.plan("pull_request", event).macos_build)

    def test_git_failure_runs_all(self):
        with patch("native_plan.git", side_effect=OSError("git unavailable")):
            self.assertTrue(self.plan("pull_request", self.pr(self.base), sha=self.base).macos_build)

    def test_draft_defers_native(self):
        self.assertFalse(self.plan("pull_request", self.pr(self.base, draft=True)).macos)

    def test_ready_for_review_runs_full_pr_again(self):
        head = self.commit("launcher_app/lib/main.dart", "native-relevant\n")
        event = self.pr(head)
        event["action"] = "ready_for_review"
        self.assertTrue(self.plan("pull_request", event).macos)

    def test_release_overrides_draft_and_paths(self):
        self.assertTrue(self.plan("pull_request", self.pr(self.base, draft=True), release=True).macos_build)

    def test_manual_dispatch_always_full(self):
        self.assertTrue(self.plan("workflow_dispatch", {}).macos_build)

    def test_unknown_event_always_full(self):
        self.assertTrue(self.plan("merge_group", {}).macos_build)


class ResultGateTests(unittest.TestCase):
    def setUp(self):
        self.needs = {key: {"result": "success"} for key in (
            "version", "linux_checks", "coverage", "coverage_total", "launcher_app", "launcher_app_macos")}
        self.needs["version"]["outputs"] = Plan.full("").outputs()

    def test_all_required_work_succeeded(self):
        self.assertEqual(check_results(self.needs), [])

    def test_expected_native_skips_pass(self):
        self.needs["version"]["outputs"] = classify_paths(["README.md"]).outputs()
        for job in ("launcher_app", "launcher_app_macos"):
            self.needs[job]["result"] = "skipped"
        self.assertEqual(check_results(self.needs), [])

    def test_required_native_skip_fails(self):
        self.needs["launcher_app_macos"]["result"] = "skipped"
        self.assertTrue(check_results(self.needs))

    def test_failed_cancelled_or_skipped_core_checks_fail(self):
        for job in ("version", "linux_checks", "coverage", "coverage_total"):
            for result in ("failure", "cancelled", "skipped", None):
                needs = copy.deepcopy(self.needs)
                needs[job]["result"] = result
                with self.subTest(job=job, result=result):
                    self.assertTrue(check_results(needs))

    def test_missing_plan_is_not_success(self):
        self.needs["version"]["outputs"] = {}
        self.assertTrue(check_results(self.needs))

    def test_inconsistent_build_plan_fails(self):
        self.needs["version"]["outputs"]["macos"] = "false"
        self.assertTrue(check_results(self.needs))

    def test_optional_job_failure_still_fails(self):
        self.needs["version"]["outputs"]["macos"] = "false"
        self.needs["version"]["outputs"]["macos_build"] = "false"
        self.needs["launcher_app_macos"]["result"] = "failure"
        self.assertTrue(check_results(self.needs))


class CliTests(unittest.TestCase):
    def invoke(self, command, env, cwd):
        return subprocess.run([sys.executable, str(Path(__file__).with_name("native_plan.py")), command],
                              cwd=cwd, env={**os.environ, **env}, capture_output=True, text=True)

    def test_missing_event_writes_full_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            summary = Path(directory) / "summary"
            result = self.invoke("plan", {"GITHUB_EVENT_PATH": str(Path(directory) / "missing"),
                                         "GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": str(summary),
                                         "CI_RELEASE": "false"}, directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text().splitlines(),
                             ["macos=true", "macos_build=true", "windows_build=true"])
            self.assertIn("Native CI plan", summary.read_text())

    def test_release_does_not_need_event_file(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.invoke("plan", {"GITHUB_EVENT_PATH": "/missing", "CI_RELEASE": "true",
                                         "GITHUB_OUTPUT": str(Path(directory) / "output")}, directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)["macos_build"])

    def test_bad_results_json_fails(self):
        result = self.invoke("check", {"CI_NEEDS": "not JSON"}, Path.cwd())
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
