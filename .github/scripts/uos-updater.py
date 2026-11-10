#!/usr/bin/env python3
"""Rewrite uos-version.env with the latest UniFi OS Server release.

Queries Ubiquiti's firmware API for the release channel of both architectures,
records the version plus each installer's download URL and SHA-256, and prints
the version on stdout (the workflow uses it for the branch and PR title).
Exits non-zero, leaving the file untouched, if anything looks wrong.
"""
import json
import re
import sys
import urllib.request

API = (
    "https://fw-update.ubnt.com/api/firmware-latest"
    "?filter=eq~~product~~unifi-os-server"
    "&filter=eq~~platform~~{platform}"
    "&filter=eq~~channel~~release"
)
PLATFORMS = {"AMD64": "linux-x64", "ARM64": "linux-arm64"}
OUT = "uos-version.env"


def latest(platform: str) -> dict:
    req = urllib.request.Request(
        API.format(platform=platform),
        headers={"User-Agent": "uos-docker-updater (github.com/jacobalberty/uos-docker)"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        firmware = json.load(resp)["_embedded"]["firmware"]
    if not firmware:
        raise RuntimeError(f"no release firmware for {platform}")
    fw = firmware[0]
    version = fw["version"].lstrip("v")
    url = fw["_links"]["data"]["href"]
    sha = fw["sha256_checksum"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError(f"unexpected version {version!r} for {platform}")
    if not url.startswith("https://fw-download.ubnt.com/"):
        raise RuntimeError(f"unexpected download host in {url!r}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise RuntimeError(f"bad sha256 {sha!r} for {platform}")
    return {"version": version, "url": url, "sha256": sha}


def main() -> int:
    found = {arch: latest(platform) for arch, platform in PLATFORMS.items()}
    versions = {f["version"] for f in found.values()}
    if len(versions) != 1:
        # Ubiquiti publishes the architectures separately; wait until both match.
        print(f"architectures disagree on version: {versions}", file=sys.stderr)
        return 1
    version = versions.pop()
    lines = [f"UOS_VERSION={version}"]
    for arch, f in found.items():
        lines.append(f"UOS_{arch}_URL={f['url']}")
        lines.append(f"UOS_{arch}_SHA256={f['sha256']}")
    with open(OUT, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
