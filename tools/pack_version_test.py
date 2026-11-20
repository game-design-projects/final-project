"""The mac app a release ships says the game's version.

Godot writes the bundle's Info.plist from the macOS export preset, and the preset's two version fields are filled by
tools/build.sh from `config/version` (they were a literal "1.0" until 0.9.5 shipped with it, #229). This reads the version
back out of the built zip and compares it with project.godot, so a preset that loses its version, or a build that stops
filling it, fails CI instead of a release.

    python3 tools/pack_version_test.py [build/donjon-0.9.5-macos.zip]

With no argument it finds the macos zip in build/. Exits 1 when the bundle's version is not the game's.
"""
import glob
import plistlib
import re
import sys
import zipfile


def game_version() -> str:
    with open("project.godot", encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^config/version="(.*)"', line.strip())
            if m:
                return m.group(1)
    raise SystemExit("pack_version_test: project.godot has no config/version")


def bundle_versions(path: str) -> dict:
    with zipfile.ZipFile(path) as z:
        info = [n for n in z.namelist() if n.endswith(".app/Contents/Info.plist")]
        if not info:
            raise SystemExit("pack_version_test: %s has no .app/Contents/Info.plist" % path)
        d = plistlib.loads(z.read(info[0]))
        return {"short": str(d.get("CFBundleShortVersionString", "")), "version": str(d.get("CFBundleVersion", ""))}


def main() -> int:
    want = game_version()
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    if not path:
        found = sorted(glob.glob("build/donjon-*-macos.zip"))
        if not found:
            raise SystemExit("pack_version_test: no build/donjon-*-macos.zip to check")
        path = found[-1]
    got = bundle_versions(path)
    print("pack_version_test: %s says %s (%s), the game is %s" % (path, got["short"], got["version"], want))
    wrong = [k for k, v in got.items() if v != want]
    if wrong:
        field = "CFBundleShortVersionString" if "short" in wrong else "CFBundleVersion"
        print("::error::%s: %s is %s, the game is %s" % (path, field, got[wrong[0]], want))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
