#!/usr/bin/env python3
"""Verify the signed PEAR identity and retained native targets before upload."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

DISPLAY_NAME = "PEAR MVP"


def expected_bundle_id(config: dict, env: dict) -> str:
    """The signed app must be the separate PEAR MVP app from release.json, never the
    original PEAR app whose bundle still lives in the IOS_BUNDLE_ID secret."""
    bundle = str(config.get("bundleId", ""))
    if not bundle:
        raise ValueError("release.json bundleId is required")
    legacy = env.get("IOS_BUNDLE_ID", "")
    if legacy and bundle == legacy:
        raise ValueError("Signed IPA must not be the original PEAR app")
    return bundle


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--build-number", required=True)
    args = parser.parse_args()
    config = json.loads((Path(__file__).parent / "release.json").read_text())
    expected_bundle = expected_bundle_id(config, dict(os.environ))
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        with zipfile.ZipFile(args.ipa) as archive:
            for item in archive.infolist():
                path = root / item.filename
                if not path.resolve().is_relative_to(root):
                    raise ValueError("Unsafe IPA archive path")
            archive.extractall(root)
        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("IPA must contain one main application")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        expected = {"CFBundleIdentifier": expected_bundle, "CFBundleDisplayName": DISPLAY_NAME, "CFBundleShortVersionString": config["version"], "CFBundleVersion": args.build_number, "OpenClawGitCommit": os.environ["GITHUB_SHA"], "ITSAppUsesNonExemptEncryption": False}
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f"IPA identity mismatch: {key}")
        if info.get("UIDeviceFamily") != [1, 2]:
            raise ValueError("IPA must preserve iPhone and iPad support")
        for key in ["NSPhotoLibraryUsageDescription", "NSMotionUsageDescription", "NSMicrophoneUsageDescription"]:
            if not info.get(key):
                raise ValueError(f"IPA is missing {key}")
        if info.get("OpenClawPushMode") != "localProduction":
            raise ValueError("PEAR cannot ship as an official OpenClaw relay client")
        extensions = list((app / "PlugIns").glob("*.appex"))
        watches = list((app / "Watch").glob("*.app"))
        products = {plistlib.loads((p / "Info.plist").read_bytes())["CFBundleIdentifier"] for p in extensions + watches}
        required = {f"{expected_bundle}.share", f"{expected_bundle}.activitywidget", f"{expected_bundle}.watchkitapp"}
        if products != required:
            raise ValueError("IPA must preserve share, Live Activity widget, and Watch products")
        profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")], stderr=subprocess.DEVNULL))
        entitlements = profile.get("Entitlements", {})
        if profile.get("TeamIdentifier") != [config["teamId"]] or entitlements.get("get-task-allow") is not False:
            raise ValueError("IPA provisioning is not PEAR distribution signing")
        if entitlements.get("application-identifier") != f"{config['teamId']}.{expected_bundle}":
            raise ValueError("IPA provisioning does not match the PEAR app")
    print("Verified PEAR signed IPA, exact source/build, privacy, and native companion products")


if __name__ == "__main__":
    main()
