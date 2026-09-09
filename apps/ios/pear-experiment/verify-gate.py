#!/usr/bin/env python3
"""Credential-free admission for this one explicitly authorized experiment."""
import json
import os
from pathlib import Path
import re
import subprocess


def verify(env: dict, sha: str, config: dict) -> None:
    if env.get("GITHUB_REPOSITORY") != config["repository"]:
        raise ValueError("Wrong repository for PEAR experiment")
    if env.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
        raise ValueError("PEAR experiment only accepts explicit manual dispatch")
    if env.get("GITHUB_REF") != f"refs/heads/{config['branch']}":
        raise ValueError("Wrong branch for PEAR experiment")
    if not re.fullmatch(r"[a-f0-9]{40}", sha) or sha != env.get("GITHUB_SHA"):
        raise ValueError("Exact requested commit does not match the workflow ref")


if __name__ == "__main__":
    config = json.loads((Path(__file__).parent / "release.json").read_text())
    sha = os.environ["PEAR_EXPECTED_SHA"]
    verify(dict(os.environ), sha, config)
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if actual != sha:
        raise SystemExit("Checkout does not match the admitted source")
    print(f"Admitted PEAR experimental source {sha}")
