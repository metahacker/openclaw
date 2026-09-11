#!/usr/bin/env python3
"""Isolate why Xcode's automatic signing rejects the App Store Connect key.

Archives a trivial app (bundle io.metahack.pear.mvp, no entitlements) under
several environment variants and records only Xcode's error lines, with the key
ID, issuer ID, and key path redacted. Never prints key material."""
import base64
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import textwrap
import time
from pathlib import Path

EVIDENCE = Path(__file__).resolve().parents[1] / "build/pear-ols-evidence"
TEAM = json.loads((Path(__file__).parent / "release.json").read_text())["teamId"]
BUNDLE = json.loads((Path(__file__).parent / "release.json").read_text())["bundleId"]
KEY_ID = os.environ["ASC_KEY_ID"].strip()
ISSUER = os.environ["ASC_ISSUER_ID"].strip()


def canonical_key_pem() -> bytes:
    raw = os.environ["ASC_KEY_CONTENT"].strip()
    pem = raw.replace("\\n", "\n") if "BEGIN PRIVATE KEY" in raw else base64.b64decode(raw).decode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as handle:
        handle.write(pem if pem.endswith("\n") else pem + "\n")
        source = handle.name
    try:
        # openssl re-emits the exact PKCS#8 form Apple ships (138 DER bytes for P-256).
        return subprocess.check_output(["openssl", "pkey", "-in", source])
    finally:
        os.unlink(source)


def redact(text: str) -> str:
    for value in (KEY_ID, ISSUER):
        if value:
            text = text.replace(value, "<redacted>")
    return text


def make_project(root: Path, entitlements: bool = False) -> Path:
    (root / "Sources").mkdir(parents=True, exist_ok=True)
    entitlement_block = ""
    if entitlements:
        (root / "Probe.entitlements").write_text(textwrap.dedent(f'''
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>aps-environment</key><string>production</string>
              <key>com.apple.security.application-groups</key><array><string>group.{BUNDLE}.shared</string></array>
              <key>com.apple.developer.healthkit</key><true/>
            </dict></plist>
        ''').lstrip())
        entitlement_block = "        CODE_SIGN_ENTITLEMENTS: Probe.entitlements\n"
    (root / "Sources/ProbeApp.swift").write_text(textwrap.dedent('''
        import SwiftUI
        @main struct ProbeApp: App { var body: some Scene { WindowGroup { Text("probe") } } }
    '''))
    (root / "project.yml").write_text(textwrap.dedent(f'''
        name: PearAuthProbe
        options:
          deploymentTarget:
            iOS: "18.0"
        targets:
          Probe:
            type: application
            platform: iOS
            sources: [Sources]
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: {BUNDLE}
                DEVELOPMENT_TEAM: {TEAM}
                CODE_SIGN_STYLE: Automatic
                GENERATE_INFOPLIST_FILE: YES
                TARGETED_DEVICE_FAMILY: "1,2"
                SWIFT_VERSION: "5.0"
    ''') + entitlement_block)
    generated = subprocess.run(["xcodegen", "generate"], cwd=root, capture_output=True, text=True)
    if generated.returncode != 0:
        raise RuntimeError(f"xcodegen failed: {(generated.stdout + generated.stderr).strip()[-400:]}")
    return root / "PearAuthProbe.xcodeproj"


def archive(project: Path, extra: list[str], env: dict) -> dict:
    archive_path = project.parent / "probe.xcarchive"
    shutil.rmtree(archive_path, ignore_errors=True)
    command = ["xcodebuild", "-project", str(project), "-scheme", "Probe", "-configuration", "Release",
               "-destination", "generic/platform=iOS", "-archivePath", str(archive_path), "archive", *extra]
    started = time.time()
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=600, env=env)
        output = result.stdout + result.stderr
        code = result.returncode
    except subprocess.TimeoutExpired as expired:
        output = (expired.stdout or "") + (expired.stderr or "")
        code = "timeout"
    lines = [line.strip() for line in output.splitlines() if "error:" in line or "warning: " in line and "sign" in line.lower()]
    return {"exit": code, "seconds": round(time.time() - started), "errors": [redact(line)[:240] for line in lines[:8]]}


def job_keychain(env: dict) -> dict:
    keychain = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())) / "pear-auth-probe.keychain-db"
    password = secrets.token_hex(16)
    subprocess.run(["security", "create-keychain", "-p", password, str(keychain)], check=True)
    subprocess.run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)], check=True)
    subprocess.run(["security", "unlock-keychain", "-p", password, str(keychain)], check=True)
    existing = subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True).replace('"', "").split()
    subprocess.run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *existing], check=True)
    subprocess.run(["security", "default-keychain", "-s", str(keychain)], check=True)
    return {"keychain": keychain.name, "searchList": [Path(p).name for p in existing]}


def main() -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    pem = canonical_key_pem()
    home = Path.home()
    for directory in (home / "private_keys", home / ".appstoreconnect/private_keys", home / ".private_keys"):
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"AuthKey_{KEY_ID}.p8").write_bytes(pem)
        os.chmod(directory / f"AuthKey_{KEY_ID}.p8", 0o600)
    key_path = home / "private_keys" / f"AuthKey_{KEY_ID}.p8"
    auth = ["-allowProvisioningUpdates", "-authenticationKeyPath", str(key_path),
            "-authenticationKeyID", KEY_ID, "-authenticationKeyIssuerID", ISSUER]
    report = {
        "keyDerBytes": len(base64.b64decode(b"".join(l for l in pem.splitlines() if b"-----" not in l))),
        "loginKeychains": [Path(p).name for p in subprocess.check_output(["security", "list-keychains", "-d", "user"], text=True).replace('"', "").split()],
        "defaultKeychain": subprocess.run(["security", "default-keychain"], capture_output=True, text=True).stdout.strip().replace('"', "").split("/")[-1],
        "variants": {},
    }
    distribution = ["CODE_SIGN_IDENTITY=Apple Distribution"]
    try:
        with tempfile.TemporaryDirectory(prefix="pear-auth-probe-") as tmp:
            env = dict(os.environ)
            project = make_project(Path(tmp))
            # Development identity hits the team's development-certificate cap; Apple-managed
            # distribution signing needs no local certificate and the distribution slot is free.
            report["variants"]["development-identity"] = archive(project, auth, env)
            report["variants"]["distribution-identity"] = archive(project, auth + distribution, env)
            project = make_project(Path(tmp), entitlements=True)
            report["variants"]["distribution-identity+entitlements"] = archive(project, auth + distribution, env)
    except Exception as error:  # the partial report is the evidence; keep it
        report["probeError"] = redact(str(error))[:400]
    for directory in (home / "private_keys", home / ".appstoreconnect/private_keys", home / ".private_keys"):
        try:
            (directory / f"AuthKey_{KEY_ID}.p8").unlink()
        except FileNotFoundError:
            pass
    (EVIDENCE / "xcode-auth-probe.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
