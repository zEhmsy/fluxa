"""Build a clean installer root without changing Finder's global preferences."""

import argparse
from pathlib import Path
import subprocess
import sys

from dmgbuild import build_dmg
from ds_store import DSStore
from mac_alias import Alias


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    mount = None
    metadata_written = False

    def capture_mount(mount_point, _options):
        nonlocal mount
        mount = Path(mount_point)

    def finish_metadata(event):
        nonlocal metadata_written
        # dmgbuild 1.6.7 emits this after closing .DS_Store and before detaching or
        # compressing. Keep this hook aligned with packaging/requirements.txt.
        if (event.get("type"), event.get("operation")) != (
            "operation::finished", "dsstore::create"
        ):
            return
        if mount is None:
            raise RuntimeError("dmgbuild did not provide the installer mount point.")

        artwork = mount / "Fluxa.app/Contents/Resources/InstallerBackground.tiff"
        if artwork.read_bytes() != (repo / "packaging/dmg-background.tiff").read_bytes():
            raise RuntimeError("Installer artwork is missing or stale; rebuild Fluxa first.")

        # Generate the alias on the mounted volume, so its volume ID and target
        # file ID refer to the shipped DMG rather than the source checkout.
        with DSStore.open(str(mount / ".DS_Store"), "r+") as store:
            options = store["."]["icvp"]
            options["backgroundType"] = 2
            options["backgroundImageAlias"] = Alias.for_file(str(artwork)).to_bytes()
            store["."]["icvp"] = options

        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(mount / "Fluxa.app")],
            check=True,
        )
        subprocess.run(
            [sys.executable, str(repo / "packaging/verify-bundle.py"), str(mount / "Fluxa.app")],
            check=True,
        )
        if (mount / "Read Me First.txt").read_bytes() != (repo / "docs/First Launch.txt").read_bytes():
            raise RuntimeError("The first-launch guide was not copied intact.")
        if (mount / "Applications").readlink() != Path("/Applications"):
            raise RuntimeError("The Applications link has an unexpected target.")
        # .Trashes is a temporary system directory that dmgbuild removes next.
        allowed = {"Fluxa.app", "Applications", "Read Me First.txt", ".DS_Store", ".Trashes"}
        unexpected = {entry.name for entry in mount.iterdir()} - allowed
        if unexpected:
            raise RuntimeError(f"Unexpected loose installer files: {sorted(unexpected)}")
        metadata_written = True

    build_dmg(
        str(args.output.resolve()),
        "Fluxa",
        settings_file=str(repo / "packaging/dmg-settings.py"),
        defines={"repo": str(repo)},
        settings={"create_hook": capture_mount},
        lookForHiDPI=False,
        detach_retries=5,
        callback=finish_metadata,
    )
    if not metadata_written:
        raise RuntimeError("Installer metadata hook was not called; check the dmgbuild version.")


if __name__ == "__main__":
    main()
