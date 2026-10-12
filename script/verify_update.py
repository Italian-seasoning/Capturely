#!/usr/bin/env python3
"""Validate the bundle, appcast, and exact archive before publishing an update."""
import argparse
import pathlib
import plistlib
import re
import subprocess
import urllib.parse
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument("app", type=pathlib.Path)
p.add_argument("archive", type=pathlib.Path)
p.add_argument("feed", type=pathlib.Path)
p.add_argument("--sparkle-bin", required=True, type=pathlib.Path)
p.add_argument("--account", default="ed25519")
p.add_argument("--repository", required=True)
p.add_argument("--require-newer", action="store_true")
a = p.parse_args()
info = plistlib.loads((a.app / "Contents/Info.plist").read_bytes())
ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items = ET.parse(a.feed).findall("./channel/item")
item = next((i for i in items if i.findtext(ns + "version") == info["CFBundleVersion"]), None)
assert item is not None, "Feed does not contain the built CFBundleVersion"
assert item.findtext(ns + "shortVersionString") == info["CFBundleShortVersionString"], "Marketing version mismatch"
assert item.findtext(ns + "minimumSystemVersion") == info["LSMinimumSystemVersion"], "Minimum OS mismatch"
enclosure = item.find("enclosure")
assert enclosure is not None, "Missing update archive"
expected = "https://github.com/" + a.repository + "/releases/download/v" + info["CFBundleShortVersionString"] + "/" + urllib.parse.quote(a.archive.name)
assert enclosure.get("url") == expected, "Archive URL does not match the release tag and filename"
assert int(enclosure.get("length", "0")) == a.archive.stat().st_size, "Archive length mismatch"
assert info["SUFeedURL"].startswith("https://"), "Feed must use HTTPS"
if a.require_newer:
    try:
        with urllib.request.urlopen(info["SUFeedURL"], timeout=30) as response:
            previous = ET.fromstring(response.read())
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
    else:
        def version(value):
            parts = [int(part) for part in value.split(".")]
            return tuple(parts + [0] * max(0, 8 - len(parts)))
        for old in previous.findall("./channel/item"):
            value = old.findtext(ns + "version") or old.find("enclosure").get(ns + "version")
            assert version(info["CFBundleVersion"]) > version(value), "Build number must advance beyond the published feed"
def run(*args):
    return subprocess.check_output(["rtk", "proxy", *map(str, args)], text=True).strip()
public_key = run(a.sparkle_bin / "generate_keys", "--account", a.account, "-p")
assert public_key == info["SUPublicEDKey"], "Signing account does not match the bundle public key"
run(a.sparkle_bin / "sign_update", "--account", a.account, "--verify", a.archive, enclosure.get(ns + "edSignature", ""))
if info.get("SURequireSignedFeed"):
    run(a.sparkle_bin / "sign_update", "--account", a.account, "--verify", a.feed)
run("codesign", "--verify", "--deep", "--strict", a.app)
binary = a.app / "Contents/MacOS" / info["CFBundleExecutable"]
build_info = run("vtool", "-show-build", binary)
def os_version(value):
    return tuple(int(part) for part in value.split("."))
for minimum in re.findall(r"minos\s+([0-9.]+)", build_info):
    assert os_version(info["LSMinimumSystemVersion"]) >= os_version(minimum), "Advertised minimum OS is below the executable's minimum OS"
for file in a.app.rglob("*"):
    if file.is_file() and not file.is_symlink():
        assert not re.search(rb"/Users/[^/\s\x00]+/", file.read_bytes()), "Absolute user path in release bundle: " + str(file.relative_to(a.app))
print("Verified: bundle signature, archive signature, feed metadata, download URL, and signing key")

