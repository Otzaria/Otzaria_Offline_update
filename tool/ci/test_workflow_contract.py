"""Small structural guardrails for the scheduling policy (no YAML dependency).

Use actionlint for complete YAML/expression validation. These tests protect the
specific policy contracts whose accidental removal could hide required work.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CI = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")


def job(name):
    match = re.search(r"^  " + re.escape(name) + r":\n(.*?)(?=^  [a-z_]+:\n|\Z)",
                      CI, re.M | re.S)
    if not match:
        raise AssertionError(f"Missing job: {name}")
    return match.group(1)


class WorkflowContractTests(unittest.TestCase):
    def test_one_automatic_apple_runner(self):
        self.assertEqual(CI.count("runs-on: macos-latest"), 1)

    def test_darwin_suites_preserved_without_root_duplicate(self):
        mac = job("launcher_app_macos")
        for package in ("otzaria_manager", "error_reports_manager", "plugins_manager", "custom_apps_manager",
                        "launcher_app", "library_manager"):
            self.assertIn("working-directory: " + package + "\n", mac)
        self.assertEqual(mac.count("&& dart test\n"), 4)
        self.assertEqual(mac.count("flutter test --no-pub"), 2)
        self.assertNotIn("otzaria_offline_update (root tools)", mac)

    def test_standalone_dart_precedes_flutter_setup(self):
        mac = job("launcher_app_macos")
        self.assertLess(mac.index("sdk: 3.13.2"), mac.index("flutter-version: 3.47.2"))

    def test_launcher_analysis_is_on_linux_only(self):
        self.assertIn("launcher_app (analyze once, before native work)", job("linux_checks"))
        for name in ("launcher_app", "launcher_app_macos"):
            self.assertNotIn("flutter analyze", job(name))

    def test_native_jobs_wait_for_cheap_checks(self):
        for name in ("launcher_app", "launcher_app_macos"):
            self.assertIn("needs: [version, linux_checks, coverage_total]", job(name))
            self.assertIn("needs.version.outputs.", job(name))

    def test_windows_native_engine_is_still_required(self):
        coverage = job("coverage")
        self.assertEqual(coverage.count("- shard:"), 4)
        self.assertIn('REQUIRE_NATIVE_ENGINE: "1"', coverage)
        for name in ("native_engine", "native_install_identity", "native_vector_install", "native_pending",
                     "native_manifest_identity", "native_qa491_install", "native_work_cleanup"):
            self.assertIn("test/" + name + "_test.dart", coverage)
        self.assertIn("--min=60 --target=0", coverage)
        self.assertIn("--min=60 --target=80", job("coverage_total"))
        self.assertIn('REQUIRE_NATIVE_ZSTD: "1"', job("linux_checks"))

    def test_release_contract_and_artifact_names(self):
        release = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("uses: ./.github/workflows/ci.yml", release)
        self.assertIn("release: true", release)
        self.assertIn("${{ jobs.version.outputs.version }}", CI)
        self.assertIn("${{ jobs.version.outputs.tag }}", CI)
        for name in ("launcher_app-macos", "launcher_app-windows-portable-ci"):
            self.assertIn("name: " + name + "\n", CI)

    def test_draft_reentry_and_no_workflow_path_skip(self):
        events = CI.split("permissions:")[0]
        for event in ("opened", "synchronize", "reopened", "ready_for_review", "converted_to_draft"):
            self.assertIn(event, events)
        self.assertNotIn("paths:", events)
        self.assertNotIn("paths-ignore:", events)
        self.assertIn("fetch-depth: 0", job("version"))

    def test_failures_reach_required_summary(self):
        summary = job("ci_status")
        self.assertIn("if: ${{ !cancelled() }}", summary)
        self.assertIn("needs: [version, linux_checks, coverage, coverage_total, launcher_app, launcher_app_macos]", summary)
        self.assertIn("python3 tool/ci/native_plan.py check", summary)

    def test_release_isolated_from_main_cancellation(self):
        concurrency = CI.split("concurrency:\n", 1)[1].split("jobs:\n", 1)[0]
        self.assertIn("inputs.release && format('release-{0}', github.run_id)", concurrency)
        self.assertIn("cancel-in-progress: ${{ !inputs.release &&", concurrency)

    def test_pub_caches_follow_locks_and_sdk_cache_is_not_duplicated(self):
        keys = re.findall(r"^\s+pub-cache-key: (.+)$", CI, re.M)
        self.assertEqual(len(keys), 4)
        for key in keys:
            self.assertIn("hashFiles('**/pubspec.lock')", key)
        self.assertNotRegex(CI, r"(?m)^\s+cache-key: .*build")

    def test_manual_workflows_are_bounded_cached_and_uncompressed(self):
        for name in ("build-exe.yml", "build-macos.yml"):
            text = (ROOT / ".github/workflows" / name).read_text(encoding="utf-8")
            self.assertIn("timeout-minutes: 40", text)
            self.assertIn("cache: true", text)
            self.assertIn("--release --no-pub", text)
            self.assertIn("compression-level: 0", text)
            self.assertIn("contents: read", text)


if __name__ == "__main__":
    unittest.main()
