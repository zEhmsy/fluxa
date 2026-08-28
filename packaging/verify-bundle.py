"""Static Direct bundle checks only: never launch Fluxa, access keys or contact a feed."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
import sys
from urllib.parse import urlsplit


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def tree_manifest(root):
    """Compare file contents, permissions and link targets without following framework symlinks."""
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if path.is_symlink():
                value = ("link", os.readlink(path))
            elif path.is_file():
                value = ("file", stat.S_IMODE(mode), hashlib.sha256(path.read_bytes()).hexdigest())
            else:
                value = ("directory", stat.S_IMODE(mode))
            result[str(path.relative_to(root))] = value
    return result


def validate_plist(info, allow_unconfigured=False):
    require(info.get("CFBundleIdentifier") == "com.giuseppe.fluxa", "Expected the Fluxa Direct bundle identifier.")
    require(info.get("CFBundleExecutable") == "Fluxa", "Missing Fluxa executable metadata.")
    require(info.get("CFBundlePackageType") == "APPL", "Expected an application bundle.")
    require(info.get("LSMinimumSystemVersion") == "14.0", "Expected a macOS 14 deployment minimum.")
    version, build = info.get("CFBundleShortVersionString", ""), info.get("CFBundleVersion", "")
    require(re.fullmatch(r"\d+\.\d+\.\d+", version), "Expected an x.y.z marketing version.")
    require(re.fullmatch(r"[1-9]\d*", build) and int(build) > 8, "Sparkle builds must increase CFBundleVersion above 8.")
    require(info.get("SUVerifyUpdateBeforeExtraction") is True, "Archive verification before extraction must remain enabled.")
    require(info.get("SUAllowsAutomaticUpdates") is False, "This Direct integration requires user confirmation for installation.")
    require(info.get("SUEnableSystemProfiling") is False, "System profiling must remain disabled by default.")
    require("SUEnableAutomaticChecks" not in info, "Let Sparkle ask for automatic-check consent.")
    feed, key = info.get("SUFeedURL"), info.get("SUPublicEDKey")
    if feed is None and key is None and allow_unconfigured:
        return False
    require(isinstance(feed, str) and isinstance(key, str),
            "Configure both SUFeedURL and SUPublicEDKey first; see docs/Updates.md. For development only use ./build.sh --development.")
    url = urlsplit(feed)
    host = (url.hostname or "").lower()
    require(url.scheme == "https" and host and not url.username and not url.password and not url.fragment,
            "SUFeedURL must be HTTPS without credentials or a fragment.")
    require(host not in {"localhost", "example.com", "example.org", "example.net"}
            and not host.endswith((".example", ".invalid", ".test", ".localhost", ".example.com", ".example.org", ".example.net")),
            "Refusing a placeholder feed host.")
    decoded = base64.b64decode(key, validate=True)
    require(len(decoded) == 32 and any(decoded), "SUPublicEDKey must be the real 32-byte base64 Ed25519 public key.")
    return True


def embedded_plist(binary):
    """Read the arm64 Mach-O section without executing the binary."""
    data = binary.read_bytes()
    require(struct.unpack_from("<I", data)[0] == 0xFEEDFACF, "Expected a thin 64-bit Mach-O executable.")
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        cmd, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and offset + size <= len(data), "Invalid Mach-O load command.")
        if cmd == 0x19:  # LC_SEGMENT_64
            for index in range(struct.unpack_from("<I", data, offset + 64)[0]):
                section = offset + 72 + index * 80
                name = data[section:section + 16].rstrip(b"\0")
                segment = data[section + 16:section + 32].rstrip(b"\0")
                if (name, segment) == (b"__info_plist", b"__TEXT"):
                    _, length, start = struct.unpack_from("<QQI", data, section + 32)
                    return plistlib.loads(data[start:start + length].rstrip(b"\0"))
        offset += size
    raise ValueError("The executable has no embedded Info.plist.")


def validate_bundle(bundle, allow_unconfigured=False, allow_local=False):
    contents = bundle / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    configured = validate_plist(info, allow_unconfigured)
    binary = contents / "MacOS/Fluxa"
    require(command("/usr/bin/lipo", "-archs", str(binary)) == "arm64", "Fluxa must be arm64 only.")
    require(embedded_plist(binary) == info, "Embedded and packaged Info.plist differ. Rebuild; never patch a signed bundle.")
    command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle))
    requirement = command("/usr/bin/codesign", "-d", "-r-", str(bundle))
    match = re.search(r'^(?:# )?designated => (.+)$', requirement, re.MULTILINE)
    require(match, "Could not read the signing requirement.")
    require(allow_local or match[1] != 'identifier "com.giuseppe.fluxa"',
            "Refusing to distribute the local identifier-only signature.")
    framework = contents / "Frameworks/Sparkle.framework"
    require((framework / "Versions/Current").is_symlink() and (framework / "Sparkle").is_symlink(),
            "Sparkle framework symlinks were not preserved.")
    vendor_dir = framework / "Versions/B"
    for helper in [vendor_dir / "Autoupdate", vendor_dir / "Updater.app",
                   vendor_dir / "XPCServices/Installer.xpc", vendor_dir / "XPCServices/Downloader.xpc", framework]:
        require(helper.exists(), f"Missing Sparkle helper: {helper.name}")
        command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(helper))
    for executable in [vendor_dir / "Sparkle", vendor_dir / "Autoupdate",
                       vendor_dir / "Updater.app/Contents/MacOS/Updater",
                       vendor_dir / "XPCServices/Installer.xpc/Contents/MacOS/Installer",
                       vendor_dir / "XPCServices/Downloader.xpc/Contents/MacOS/Downloader"]:
        require(executable.stat().st_mode & 0o111, f"Lost executable permissions: {executable.name}")
        require("arm64" in command("/usr/bin/lipo", "-archs", str(executable)).split(),
                f"Sparkle helper lacks arm64: {executable.name}")
    vendor = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
    repo = Path(__file__).resolve().parent.parent
    lock = json.loads((repo / "Package.resolved").read_text())
    pin = next(p for p in lock["pins"] if p["identity"] == "sparkle")
    require(vendor["CFBundleShortVersionString"] == pin["state"]["version"], "Embedded Sparkle differs from Package.resolved.")
    require((contents / "Resources/Sparkle-LICENSE.txt").is_file(), "Missing Sparkle license notice.")
    links = command("/usr/bin/otool", "-L", str(binary)).splitlines()[1:]
    dependencies = [line.strip().split(" (", 1)[0] for line in links]
    require("@rpath/Sparkle.framework/Versions/B/Sparkle" in dependencies, "Fluxa is not linked to its embedded Sparkle framework.")
    for dependency in dependencies:
        require(dependency.startswith(("/System/Library/", "/usr/lib/", "@rpath/")), f"Nonportable dependency: {dependency}")
    load_commands = command("/usr/bin/otool", "-l", str(binary))
    runpaths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", load_commands)
    require("@executable_path/../Frameworks" in runpaths, "Missing the bundle framework runpath.")
    for runpath in runpaths:
        require(runpath in {"/usr/lib/swift", "@loader_path", "@executable_path/../Frameworks"},
                f"Unexpected runtime search path: {runpath}")
    return info, configured


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Bundle or source Info.plist to check")
    parser.add_argument("--allow-unconfigured-updater", action="store_true", help="Development builds only; both trust fields must be absent")
    parser.add_argument("--allow-local-signature", action="store_true", help="Local checks only, never distribution")
    parser.add_argument("--vendor-source", type=Path, help="Verify an ad-hoc build preserved the complete upstream framework")
    args = parser.parse_args()
    if args.path.is_file():
        info = plistlib.loads(args.path.read_bytes())
        configured = validate_plist(info, args.allow_unconfigured_updater)
    else:
        info, configured = validate_bundle(args.path, args.allow_unconfigured_updater, args.allow_local_signature)
        if args.vendor_source:
            require(tree_manifest(args.vendor_source) == tree_manifest(args.path / "Contents/Frameworks/Sparkle.framework"),
                    "Bundling changed Sparkle files, modes or symlinks.")
    print(f"Verified Fluxa {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}): "
          + ("updater configured." if configured else "DEVELOPMENT ONLY; updater is not configured."))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, StopIteration, struct.error, subprocess.CalledProcessError) as error:
        sys.exit(f"Verification failed: {getattr(error, 'output', None) or error}")
