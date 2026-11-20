#!/usr/bin/env python3
"""Checks that a mac build says the game's version, in the bundle and in its file name.

    python3 tools/macos_version_test.py [build/donjon-<version>-macos.zip]

`Info.plist` is what "Get Info", a crash report and a launcher read; the menu and `project.godot` say `config/version`.
They are the same value only when the macOS export takes the second for the first, which it does when the preset leaves
`application/short_version` and `application/version` empty — what `tools/build.sh` writes now. 0.9.5 shipped with a
literal "1.0" in both while the game inside said 0.9.5. This reads the built zip back, so a literal put back in the
preset, or a build that says something else, fails before the artifact goes anywhere. CI runs it on the macOS build.

With no path it reads `build/donjon-<config/version>-macos.zip`, which `tools/build.sh macos` writes.
"""
import os
import plistlib
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "project.godot")

failed = 0


def check(ok, what):
    global failed
    print("macos_version_test: %s %s" % ("ok  " if ok else "FAIL", what))
    failed += 0 if ok else 1


def project_version():
    with open(PROJECT, encoding="utf-8") as f:
        m = re.search(r'^config/version="([^"]*)"', f.read(), re.M)
    return m.group(1) if m else ""


def main(argv):
    version = project_version()
    check(version != "", "project.godot has a config/version (%s)" % (version or "none"))
    if not version:
        return 1
    if len(argv) > 2:
        check(False, "one zip at a time (%d given)" % (len(argv) - 1))
        return 1
    name = "donjon-%s-macos.zip" % version
    path = argv[1] if len(argv) == 2 else os.path.join(ROOT, "build", name)
    if not os.path.isfile(path):
        check(False, "a build to read at %s (tools/build.sh macos writes it)" % os.path.relpath(path, ROOT))
        return 1
    check(True, "there is a build to read: %s" % os.path.relpath(path, ROOT))
    check(os.path.basename(path) == name, "its name says %s (%s)" % (version, os.path.basename(path)))
    try:
        with zipfile.ZipFile(path) as z:
            plists = [n for n in z.namelist() if n.endswith("/Contents/Info.plist")]
            check(len(plists) == 1, "it holds one app bundle (%d found)" % len(plists))
            if len(plists) != 1:
                return 1
            info = plistlib.loads(z.read(plists[0]))
    except (zipfile.BadZipFile, plistlib.InvalidFileException, KeyError) as e:
        check(False, "its Info.plist reads (%s)" % e)
        return 1
    check(plists[0].endswith("Donjon.app/Contents/Info.plist"), "the bundle is Donjon.app (%s)" % plists[0])
    for key, what in (("CFBundleShortVersionString", "Get Info's version"),
                      ("CFBundleVersion", "the bundle's version")):
        check(info.get(key) == version, "%s is %s (%s)" % (what, version, info.get(key)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
