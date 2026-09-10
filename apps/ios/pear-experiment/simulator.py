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


def app_pid() -> int | None:
    """Simulator apps are host processes; find the app under test by its bundle path."""
    listing = subprocess.run(["ps", "-axo", "pid=,%cpu=,comm="], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[2].endswith("/OpenClaw.app/OpenClaw"):
            return int(parts[0])
    return None


def cpu_percent(pid: int) -> float:
    out = subprocess.run(["ps", "-o", "%cpu=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return 0.0


def collect_app_log(udid: str, target: Path) -> None:
    """The app's own stdout/stderr is lost when XCTest kills a hung process; the unified
    log still has its SwiftUI runtime issues and os_log output."""
    with target.open("w") as handle:
        subprocess.run(
            ["xcrun", "simctl", "spawn", udid, "log", "show", "--last", "10m", "--style", "compact",
             "--predicate", 'process == "OpenClaw" OR subsystem == "com.apple.runtime-issues"'],
            stdout=handle, stderr=subprocess.STDOUT, check=False)


def run_sampling_busy_main_thread(args: list[str], label: str, udid: str) -> None:
    """Run xcodebuild while watching the app under test. If it pegs a core for a sustained
    period (a stuck main thread makes XCTest report "main thread busy"), capture a `sample`
    into the evidence directory so the hang can be diagnosed without a local Xcode."""
    process = subprocess.Popen(args, cwd=ROOT)
    busy_ticks = 0
    captures = 0
    try:
        while process.poll() is None:
            time.sleep(5)
            pid = app_pid()
            if pid is None:
                busy_ticks = 0
                continue
            busy_ticks = busy_ticks + 1 if cpu_percent(pid) >= 80 else 0
            if busy_ticks >= 3 and captures < 2:
                captures += 1
                busy_ticks = 0
                target = EVIDENCE / f"{label}-busy-sample-{captures}.txt"
                subprocess.run(["sample", str(pid), "8", "-mayDie", "-file", str(target)], check=False)
                if not target.exists() or target.stat().st_size < 2000:
                    # sample cannot always attach on hosted runners; spindump needs root there.
                    subprocess.run(["sudo", "spindump", str(pid), "5", "-file", str(target)], check=False)
    finally:
        if process.poll() is None:
            process.wait()
    if process.returncode != 0:
        collect_app_log(udid, EVIDENCE / f"{label}-app-log.txt")
        raise subprocess.CalledProcessError(process.returncode, args)


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
        run_sampling_busy_main_thread(args, f"{family}-uitest", udid)
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
