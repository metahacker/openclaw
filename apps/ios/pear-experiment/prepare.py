#!/usr/bin/env python3
"""Generate isolated PEAR build inputs; never change the upstream target graph."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import yaml

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parents[1]
CONFIG = json.loads((IOS / "pear-experiment/release.json").read_text())
SIMULATOR_BUNDLE = "io.metahack.pear.ols.validation"
DISPLAY_NAME = "PEAR MVP"
# The original PEAR app; this experiment ships as a separate app and must never build for it.
LEGACY_PEAR_APP_ID = "6759186465"
MAC_DESIGNED_TARGETS = (
    "OpenClaw",
    "OpenClawShareExtension",
    "OpenClawActivityWidget",
)


def release_identity(config: dict, env: dict, *, simulator: bool) -> tuple[str, str]:
    """Resolve (bundle, team). The release identity is source-controlled in release.json;
    env IOS_BUNDLE_ID belongs to the original PEAR app and is only used as a forbidden value."""
    bundle = SIMULATOR_BUNDLE if simulator else str(config.get("bundleId", ""))
    team = config["teamId"] if simulator else env.get("IOS_DEVELOPMENT_TEAM", "")
    if team != config["teamId"] or bundle.startswith("ai.openclawfoundation."):
        raise ValueError("PEAR experiment cannot use the upstream OpenClaw app/team")
    if not re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+", bundle):
        raise ValueError("Invalid bundle identifier")
    if not simulator:
        legacy = env.get("IOS_BUNDLE_ID", "")
        if legacy and bundle == legacy:
            raise ValueError("PEAR MVP must not build for the original PEAR app bundle")
        if str(config.get("appId", "")) == LEGACY_PEAR_APP_ID:
            raise ValueError("PEAR MVP must not target the original PEAR App Store Connect app")
    return bundle, team


def enable_designed_for_ipad_on_mac(project: dict) -> None:
    """Make the shipping iOS products explicitly eligible for Apple-silicon Macs.

    This is Apple's compatibility path for the same iPhone/iPad binary, not a
    Catalyst or native macOS target.
    """
    for target_name in MAC_DESIGNED_TARGETS:
        target = project["targets"].get(target_name)
        if target is None:
            raise ValueError(f"Missing required Mac-compatible target: {target_name}")
        settings = target.setdefault("settings", {}).setdefault("base", {})
        settings["SUPPORTS_MACCATALYST"] = "NO"
        settings["SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD"] = "YES"


def prepare(*, simulator: bool, build_number: str) -> Path:
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("Build number must be a positive integer")
    bundle, team = release_identity(CONFIG, dict(os.environ), simulator=simulator)

    source = yaml.safe_load((IOS / "project.yml").read_text())
    project = json.loads(json.dumps(source))
    app = project["targets"]["OpenClaw"]
    app["info"]["properties"]["CFBundleDisplayName"] = DISPLAY_NAME
    app["info"]["properties"]["ITSAppUsesNonExemptEncryption"] = False
    enable_designed_for_ipad_on_mac(project)
    for value in project["targets"].values():
        info = value.get("info", {}).get("properties", {})
        if isinstance(info.get("CFBundleDisplayName"), str):
            info["CFBundleDisplayName"] = info["CFBundleDisplayName"].replace("OpenClaw", DISPLAY_NAME)
    for config in ("Debug", "Release"):
        settings = app["settings"]["configs"].setdefault(config, {})
        settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
        # Existing PEAR OAuth broker returns the registered openclaw:// handoff.
        settings["OPENCLAW_URL_SCHEME"] = "openclaw"
        settings["OPENCLAW_PUSH_MODE"] = "localProduction" if config == "Release" else "localSandbox"
    # Keep Watch, share, widget, app groups, HealthKit, and all upstream tests intact.
    if project["targets"].keys() != source["targets"].keys() or app["dependencies"] != source["targets"]["OpenClaw"]["dependencies"]:
        raise ValueError("Experimental preparation must preserve upstream capabilities")
    spec = IOS / "project.pear-ols.generated.yml"
    spec.write_text(yaml.safe_dump(project, sort_keys=False, allow_unicode=True))

    signing = {
        "OPENCLAW_CODE_SIGN_STYLE": "Automatic",
        "OPENCLAW_CODE_SIGN_IDENTITY": "Apple Development",
        "OPENCLAW_DEVELOPMENT_TEAM": team,
        "OPENCLAW_IOS_SELECTED_TEAM": team,
        "OPENCLAW_APP_BUNDLE_ID": bundle,
        "OPENCLAW_SHARE_BUNDLE_ID": f"{bundle}.share",
        "OPENCLAW_ACTIVITY_WIDGET_BUNDLE_ID": f"{bundle}.activitywidget",
        "OPENCLAW_WATCH_APP_BUNDLE_ID": f"{bundle}.watchkitapp",
        "OPENCLAW_APP_GROUP_ID": f"group.{bundle}.shared",
        "OPENCLAW_APP_PROFILE": "",
        "OPENCLAW_SHARE_PROFILE": "",
        "OPENCLAW_ACTIVITY_WIDGET_PROFILE": "",
        "OPENCLAW_WATCH_APP_PROFILE": "",
    }
    (IOS / "LocalSigning.xcconfig").write_text("// Generated PEAR experiment; do not commit.\n" + "".join(f"{key} = {value}\n" for key, value in signing.items()))
    build = IOS / "build"
    build.mkdir(exist_ok=True)
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    version = CONFIG["version"]
    (build / "Version.xcconfig").write_text(
        f"OPENCLAW_IOS_VERSION = {version}\nOPENCLAW_MARKETING_VERSION = {version}\n"
        f"OPENCLAW_BUILD_VERSION = {build_number}\nOPENCLAW_GIT_COMMIT = {sha}\n"
        f"OPENCLAW_BUILD_TIMESTAMP = {os.environ.get('PEAR_BUILD_TIMESTAMP', 'experimental')}\n"
    )
    print(f"Prepared PEAR {'simulator' if simulator else 'release'} inputs; all upstream targets preserved")
    return spec


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", action="store_true")
    parser.add_argument("--build-number", required=True)
    options = parser.parse_args()
    prepare(simulator=options.simulator, build_number=options.build_number)
