#!/usr/bin/env python3
"""Bind synthetic UI proof to the exact source selected for a release."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def verify(directory: Path, expected_sha: str, require_committed_formatting: bool = False) -> dict:
    if not re.fullmatch(r"[a-f0-9]{40}", expected_sha):
        raise ValueError("Expected a full exact source commit")
    manifest = json.loads((directory / "manifest.json").read_text())
    if manifest.get("sourceSha") != expected_sha or manifest.get("testsPassed") is not True:
        raise ValueError("Simulator proof is missing or belongs to another source commit")
    if manifest.get("screenshotSource") != "xctest-attachment":
        raise ValueError("Screenshot proof must come from the retained passing XCTest attachment")
    formatting = (directory / "formatting.patch").read_bytes()
    if manifest.get("formattingPatchSha256") != hashlib.sha256(formatting).hexdigest():
        raise ValueError("Formatting patch is missing or changed")
    if require_committed_formatting and formatting:
        raise ValueError("Commit the captured formatting patch and rerun verification before release")
    expected = {"iphone.png", "ipad.png"}
    if set(manifest.get("screenshots", {})) != expected:
        raise ValueError("Both iPhone and iPad screenshot proof are required")
    for name, digest in manifest["screenshots"].items():
        image = (directory / name).read_bytes()
        if image[:8] != b"\x89PNG\r\n\x1a\n" or hashlib.sha256(image).hexdigest() != digest:
            raise ValueError("Screenshot evidence is missing or changed")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("sha")
    parser.add_argument("--require-committed-formatting", action="store_true")
    args = parser.parse_args()
    verify(args.directory, args.sha, args.require_committed_formatting)
    print("Verified exact-source simulator/test/screenshot evidence")
