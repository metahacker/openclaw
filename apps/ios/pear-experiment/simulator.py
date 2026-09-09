#!/usr/bin/env python3
"""Run OLS behavioral tests and capture the same synthetic surface on two devices."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parents[1]
EVIDENCE = IOS / "build/pear-ols-evidence"
DERIVED = IOS / "build/pear-ols-simulator"


def run(*args: str) -> None:
    subprocess.run(args, cwd=ROOT, check=True)


def main() -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"]
    candidates = []
    for runtime in sorted(devices, reverse=True):
        if "iOS" in runtime:
            candidates.extend(d for d in devices[runtime] if d.get("isAvailable"))
    selected = {
        "iphone": next((d for d in candidates if "iPhone" in d["name"]), None),
        "ipad": next((d for d in candidates if "iPad" in d["name"] and "13-inch" in d["name"]), None),
    }
    if any(d is None for d in selected.values()):
        raise SystemExit("Required iPhone and 13-inch iPad simulators unavailable")
    screenshots = {}
    for family, device in selected.items():
        udid = device["udid"]
        if device["state"] != "Booted":
            run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        args = ["xcodebuild", "-project", str(IOS / "OpenClaw.xcodeproj"), "-scheme", "OpenClawUITests", "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", str(DERIVED), "-resultBundlePath", str(EVIDENCE / f"{family}.xcresult"), "-parallel-testing-enabled", "NO", "-only-testing:OpenClawUITests/PearOLSUITests", "CODE_SIGNING_ALLOWED=NO", "test"]
        run(*args)
        if family == "iphone":
            run("xcodebuild", "-project", str(IOS / "OpenClaw.xcodeproj"), "-scheme", "OpenClaw", "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", str(DERIVED), "-resultBundlePath", str(EVIDENCE / "logic.xcresult"), "-parallel-testing-enabled", "NO", "-only-testing:OpenClawTests/PearOLSTimelineTests", "CODE_SIGNING_ALLOWED=NO", "test")
        app = DERIVED / "Build/Products/Debug-iphonesimulator/OpenClaw.app"
        run("xcrun", "simctl", "install", udid, str(app))
        run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
        run("xcrun", "simctl", "launch", udid, "io.metahack.pear.ols.validation.debug", "--pear-ols-screenshot")
        # Behavioral readiness is asserted by the UI test; this settles capture animation.
        time.sleep(3)
        name = f"{family}.png"
        run("xcrun", "simctl", "io", udid, "screenshot", str(EVIDENCE / name))
        screenshots[name] = hashlib.sha256((EVIDENCE / name).read_bytes()).hexdigest()
    formatting = (EVIDENCE / "formatting.patch").read_bytes()
    (EVIDENCE / "manifest.json").write_text(json.dumps({"sourceSha": os.environ["GITHUB_SHA"], "testsPassed": True, "formattingPatchSha256": hashlib.sha256(formatting).hexdigest(), "hasUncommittedFormatting": bool(formatting), "screenshots": screenshots, "devices": {k: v["name"] for k, v in selected.items()}}, indent=2) + "\n")


if __name__ == "__main__":
    main()
