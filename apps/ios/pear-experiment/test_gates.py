import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import subprocess


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class ExperimentAdmissionTests(unittest.TestCase):
    def test_supported_wrapper_keeps_default_and_never_falls_back(self):
        root = Path(__file__).resolve().parents[3]
        wrapper = root / "scripts/ios-release-upload.sh"
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            bundle = directory / "bundle"
            bundle.write_text('#!/bin/bash\nif [[ "$2" == "check" ]]; then exit 0; fi\nprintf "%s\\n" "$*" >> "$PEAR_TEST_LOG"\nexit "${PEAR_TEST_EXIT:-0}"\n')
            bundle.chmod(0o755)
            log = directory / "calls"
            env = {"PATH": f"{directory}:/usr/bin:/bin", "PEAR_TEST_LOG": str(log)}
            result = subprocess.run(["/bin/bash", str(wrapper)], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn("exec fastlane ios release_upload", log.read_text())
            log.write_text("")
            env.update(PEAR_OLS_EXPERIMENT="1", PEAR_TEST_EXIT="39")
            result = subprocess.run(["/bin/bash", str(wrapper)], env=env, capture_output=True)
            self.assertEqual(result.returncode, 39)
            self.assertEqual(len(log.read_text().splitlines()), 1)
            self.assertIn("exec fastlane ios pear_ols_release", log.read_text())
            log.write_text("")
            result = subprocess.run(["/bin/bash", str(wrapper), "--build-number", "99"], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(log.read_text(), "")

    def test_wrong_source_and_automatic_dispatch_rejected(self):
        gate = module("verify-gate")
        config = json.loads((Path(__file__).parent / "release.json").read_text())
        sha = "a" * 40
        env = {"GITHUB_REPOSITORY": config["repository"], "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": f"refs/heads/{config['branch']}", "GITHUB_SHA": sha}
        gate.verify(env, sha, config)
        for field, bad in [("GITHUB_EVENT_NAME", "push"), ("GITHUB_REPOSITORY", "openclaw/openclaw"), ("GITHUB_REF", "refs/heads/main"), ("GITHUB_SHA", "b" * 40)]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                gate.verify(dict(env, **{field: bad}), sha, config)

    def test_release_identity_is_the_separate_pear_mvp_app(self):
        prepare = module("prepare")
        verify_ipa = module("verify-ipa")
        config = {"appId": "1234567890", "bundleId": "io.metahack.pear.mvp", "teamId": "7TWXNL6G85"}
        legacy_env = {"IOS_DEVELOPMENT_TEAM": "7TWXNL6G85", "IOS_BUNDLE_ID": "io.metahack.pear.legacy"}
        self.assertEqual(prepare.release_identity(config, legacy_env, simulator=False), ("io.metahack.pear.mvp", "7TWXNL6G85"))
        self.assertEqual(prepare.release_identity(config, {}, simulator=True), (prepare.SIMULATOR_BUNDLE, "7TWXNL6G85"))
        self.assertEqual(verify_ipa.expected_bundle_id(config, legacy_env), "io.metahack.pear.mvp")
        self.assertEqual(prepare.DISPLAY_NAME, "PEAR MVP")
        self.assertEqual(verify_ipa.DISPLAY_NAME, "PEAR MVP")
        collisions = [
            dict(legacy_env, IOS_BUNDLE_ID="io.metahack.pear.mvp"),
            dict(legacy_env, IOS_DEVELOPMENT_TEAM="OTHERTEAM1"),
        ]
        for env in collisions:
            with self.subTest(env=env), self.assertRaises(ValueError):
                prepare.release_identity(config, env, simulator=False)
        with self.assertRaises(ValueError):
            verify_ipa.expected_bundle_id(config, dict(legacy_env, IOS_BUNDLE_ID="io.metahack.pear.mvp"))
        for bad in [dict(config, appId=prepare.LEGACY_PEAR_APP_ID), dict(config, bundleId=""), dict(config, bundleId="ai.openclawfoundation.app")]:
            with self.subTest(config=bad), self.assertRaises(ValueError):
                prepare.release_identity(bad, legacy_env, simulator=False)
        with self.assertRaises(ValueError):
            verify_ipa.expected_bundle_id(dict(config, bundleId=""), legacy_env)
        # The committed release.json must already name the separate app, never the original.
        committed = json.loads((Path(__file__).parent / "release.json").read_text())
        self.assertEqual(committed["bundleId"], "io.metahack.pear.mvp")
        self.assertNotEqual(committed["appId"], prepare.LEGACY_PEAR_APP_ID)

    def test_shipping_targets_enable_designed_for_ipad_on_apple_silicon(self):
        prepare = module("prepare")
        source = prepare.yaml.safe_load((prepare.IOS / "project.yml").read_text())
        prepared = json.loads(json.dumps(source))
        prepare.enable_designed_for_ipad_on_mac(prepared)
        self.assertEqual(prepared["targets"]["OpenClaw"]["settings"]["base"]["TARGETED_DEVICE_FAMILY"], "1,2")
        for target_name in prepare.MAC_DESIGNED_TARGETS:
            with self.subTest(target=target_name):
                settings = prepared["targets"][target_name]["settings"]["base"]
                self.assertEqual(settings["SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD"], "YES")
                self.assertEqual(settings["SUPPORTS_MACCATALYST"], "NO")

    def test_screenshots_bound_to_successful_exact_source(self):
        gate = module("verify-evidence")
        sha = "a" * 40
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            content = b"\x89PNG\r\n\x1a\nsynthetic fixture"
            for name in ["iphone.png", "ipad.png"]:
                (directory / name).write_bytes(content)
            (directory / "formatting.patch").write_bytes(b"")
            manifest = {"sourceSha": sha, "testsPassed": True, "formattingPatchSha256": hashlib.sha256(b"").hexdigest(), "screenshotSource": "xctest-attachment", "screenshots": {name: hashlib.sha256(content).hexdigest() for name in ["iphone.png", "ipad.png"]}}
            (directory / "manifest.json").write_text(json.dumps(manifest))
            gate.verify(directory, sha)
            manifest["screenshotSource"] = "simctl-after-test"
            (directory / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                gate.verify(directory, sha)
            manifest["screenshotSource"] = "xctest-attachment"
            (directory / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                gate.verify(directory, "b" * 40)
            patch = b"synthetic formatting diff"
            (directory / "formatting.patch").write_bytes(patch)
            manifest["formattingPatchSha256"] = hashlib.sha256(patch).hexdigest()
            (directory / "manifest.json").write_text(json.dumps(manifest))
            gate.verify(directory, sha)
            with self.assertRaises(ValueError):
                gate.verify(directory, sha, require_committed_formatting=True)
            (directory / "ipad.png").write_bytes(content + b"changed")
            with self.assertRaises(ValueError):
                gate.verify(directory, sha)

    def test_xctest_proof_requires_one_retained_png(self):
        simulator = module("simulator")
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            nested = directory / "attachments"
            nested.mkdir()
            screenshot = nested / "One Living Surface conversation.png"
            screenshot.write_bytes(b"png")
            (directory / "manifest.json").write_text("{}")
            self.assertEqual(simulator.select_single_retained_screenshot(directory), screenshot)
            (directory / "second.png").write_bytes(b"png")
            with self.assertRaises(ValueError):
                simulator.select_single_retained_screenshot(directory)


if __name__ == "__main__":
    unittest.main()
