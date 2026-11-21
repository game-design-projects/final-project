"""The mac app a release ships says the game's version.

Godot writes the bundle's Info.plist from the macOS export preset. `tools/build.sh` leaves that preset's two version
fields empty, and the macOS exporter then writes `config/version` from project.godot into both -- the value the menu
shows -- where it wrote a literal "1.0" until 0.9.5 shipped with one (#229). This reads the built zip back: its name,
that it holds one app bundle, and both of the bundle's versions against project.godot, so a literal put back in the
preset, or a build that says another version, fails CI instead of a release.

    python3 tools/pack_version_test.py [build/donjon-<version>-macos.zip]

With no argument it reads `build/donjon-<config/version>-macos.zip`, which `tools/build.sh macos` writes.
Exits 1 when the zip's name or the bundle's version is not the game's.
"""
import os
import plistlib
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def game_version() -> str:
    with open(os.path.join(ROOT, "project.godot"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^config/version="(.*)"', line.strip())
            if m:
                return m.group(1)
    raise SystemExit("pack_version_test: project.godot has no config/version")


def bundle(path: str) -> dict:
    with zipfile.ZipFile(path) as z:
        info = [n for n in z.namelist() if n.endswith(".app/Contents/Info.plist")]
        if len(info) != 1:
            raise SystemExit("pack_version_test: %s holds %d app bundles, not one" % (path, len(info)))
        d = plistlib.loads(z.read(info[0]))
        return {
            "app": info[0],
            "short": str(d.get("CFBundleShortVersionString", "")),
            "version": str(d.get("CFBundleVersion", "")),
        }


def main() -> int:
    want = game_version()
    name = "donjon-%s-macos.zip" % want
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join("build", name)
    if not os.path.isfile(path):
        raise SystemExit("pack_version_test: no build to read at %s (tools/build.sh macos writes it)" % path)
    got = bundle(path)
    print("pack_version_test: %s says %s (%s), the game is %s" % (path, got["short"], got["version"], want))
    failed = 0
    if os.path.basename(path) != name:
        print("::error::%s: the zip is not named %s (tools/build.sh names it from config/version)" % (path, name))
        failed += 1
    if not got["app"].endswith("Donjon.app/Contents/Info.plist"):
        print("::error::%s: the bundle inside is not Donjon.app (%s)" % (path, got["app"]))
        failed += 1
    for key, field, what in (
        ("short", "CFBundleShortVersionString", "Get Info's version"),
        ("version", "CFBundleVersion", "the bundle's version"),
    ):
        if got[key] != want:
            print("::error::%s: %s (%s) is %s, the game is %s" % (path, field, what, got[key], want))
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
