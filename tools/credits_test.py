#!/usr/bin/env python3
"""Everything the game ships in assets/ is named in assets/CREDITS.txt with its licence, and every licence text it names is there.

The credits are a legal record as much as a thank-you: the music is played on a CC0 orchestra (VSCO-2 CE),
the fonts under the SIL Open Font License (which requires the notice and the licence to travel with the font), the voices
are cloned from CC BY 4.0 recordings, and the old credits named the licences of the art, the files and the build but not
where their texts live — nor did `tools/build.sh` ship them, since Godot exports only resources unless an include
filter names the rest, so the fonts travelled without their licence. This check keeps that from happening again, and it
needs no Godot:

    python3 tools/credits_test.py

The checks: every file in assets/audio (and assets/audio/music), assets/art, assets/fonts and assets/video, and every bank in assets/voices, is named
in the credits (an exact name, or a line like `assets/audio/music/*.ogg` that covers it); every path to a `.txt` the credits
name exists; each font has its SIL font-license file beside it, and that file is the OFL 1.1 with the font's own copyright
line; the Creative Commons text is the one the credits claim it is; the music names the CC0 orchestra it is played on and
the hum theme to be Abdulla's, rendered with GeneralUser GS, and the music set to be his too; and every export preset in `tools/build.sh` carries the licence
texts into the build.
"""
import fnmatch
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
CREDITS = os.path.join(ASSETS, "CREDITS.txt")
BUILD = os.path.join(ROOT, "tools", "build.sh")
LICENCES = os.path.join(ASSETS, "LICENSES")
FONTS = os.path.join(ASSETS, "fonts")
MUSIC = ["assets/audio/music/*.ogg"]  # every place's and every foe's tune, played on the VSCO-2 CE orchestra
HUM = ["hum-explore.ogg"]
SET = ["set-fight.ogg", "set-boss.ogg", "set-final.ogg"]  # Abdulla's music set, played in a fight (the feature `music-set`)

failed = 0


def check(ok, what):
    global failed
    print("credits_test: %s %s" % ("ok  " if ok else "FAIL", what))
    failed += 0 if ok else 1


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def named(credits, path):
    """The asset is named: its full path, its file name, or a glob line that covers it (assets/art/*.png)."""
    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
    if rel in credits or os.path.basename(path) in credits:
        return True
    for pattern in re.findall(r"assets/[A-Za-z0-9_./*?-]+\.(?:png|ogg|ogv|ttf|txt)", credits):
        if "*" in pattern and fnmatch.fnmatch(rel, pattern):
            return True
    return False


def main():
    credits = read(CREDITS)

    # 1. every shipped asset is named
    missing = []
    for folder in ("audio", os.path.join("audio", "music"), "art", "fonts", "video"):
        for name in sorted(os.listdir(os.path.join(ASSETS, folder))):
            path = os.path.join(ASSETS, folder, name)
            if not os.path.isfile(path) or name.endswith((".import", ".uid")):
                continue
            if not named(credits, path):
                missing.append(os.path.relpath(path, ROOT))
    check(not missing, "every file in assets/audio (and audio/music), art, fonts and video is named in the credits%s" % (
        (", and these are not: " + ", ".join(missing)) if missing else ""))

    voices = os.path.join(ASSETS, "voices")
    banks = sorted(d for d in os.listdir(voices) if os.path.isdir(os.path.join(voices, d)))
    unnamed = [b for b in banks if "assets/voices/%s/" % b not in credits and "assets/voices/*/" not in credits]
    check(banks and not unnamed, "every voice bank is named (%d banks%s)" % (
        len(banks), (", and these are not: " + ", ".join(unnamed)) if unnamed else ""))

    # 2. every licence text the credits name is there
    texts = sorted(set(re.findall(r"assets/(?:LICENSES|fonts)/[A-Za-z0-9_.-]+\.txt", credits)))
    gone = [t for t in texts if not os.path.isfile(os.path.join(ROOT, t))]
    check(len(texts) >= 2 and not gone, "every licence text the credits name exists (%d named%s)" % (
        len(texts), (", and these are missing: " + ", ".join(gone)) if gone else ""))

    # 3. each font has the open font licence beside it, and it is the OFL with that font's copyright line
    fonts = sorted(f for f in os.listdir(FONTS) if f.endswith(".ttf"))
    bad_fonts = []
    for font in fonts:
        stem = font[:-4]
        ofl = os.path.join(FONTS, "OFL-%s.txt" % stem.replace("-Regular", ""))
        if not os.path.isfile(ofl):
            bad_fonts.append("%s has no OFL-%s.txt" % (font, stem.replace("-Regular", "")))
            continue
        body = read(ofl)
        if "SIL OPEN FONT LICENSE Version 1.1" not in body:
            bad_fonts.append("%s's licence is not the OFL 1.1" % font)
        if "Copyright" not in body.split("-----------------------------------------------------------")[0]:
            bad_fonts.append("%s's licence has no copyright line" % font)
        if font not in credits:
            bad_fonts.append("%s is not named in the credits" % font)
    check(fonts and not bad_fonts, "each font ships its SIL Open Font License, with its copyright line (%d fonts%s)" % (
        len(fonts), (", and these do not: " + "; ".join(bad_fonts)) if bad_fonts else ""))

    # 4. the Creative Commons texts are the ones the credits claim
    by = os.path.join(LICENCES, "CC-BY-4.0.txt")
    ok_texts = os.path.isfile(by) and "Attribution 4.0 International" in read(by)
    check(ok_texts, "the Creative Commons text is the version the credits name (CC BY 4.0, for the reference voices)")

    # 5. the music's licences are stated, not only its sources
    sampled = all(name in credits for name in MUSIC)
    check(sampled and "VSCO-2 CE" in credits and "CC0" in credits and "Ivy Audio" in credits,
          "the music names the orchestra it is played on, its licence (CC0) and the organ's sampler (%d of %d entries)" % (
              sum(1 for name in MUSIC if name in credits), len(MUSIC)))
    check(all(name in credits for name in HUM) and "Abdulla Alfalasi" in credits and "GeneralUser GS" in credits,
          "the hum theme names its author and the soundfont it was rendered with (%d of %d files)" % (
              sum(1 for name in HUM if name in credits), len(HUM)))
    set_entry = next((part for part in credits.split("\n\n") if part.startswith("MUSIC: the music set")), "")
    check(all(name in set_entry for name in SET) and "Abdulla Alfalasi" in set_entry and "tools/music/music-set/" in set_entry,
          "the music set names its author and where its renders and MIDI are kept (%d of %d files)" % (
              sum(1 for name in SET if name in set_entry), len(SET)))

    # 6. every export preset carries the licence texts into the build
    build = read(BUILD)
    presets = re.findall(r'include_filter="([^"]*)"', build)
    wanted = ("assets/fonts/*.txt", "assets/LICENSES/*")
    thin = [p for p in presets if not all(w in p for w in wanted)]
    check(len(presets) == 4 and not thin,
          "every export preset ships the licence texts (%d presets, %d without one of %s)" % (
              len(presets), len(thin), " and ".join(wanted)))

    print("credits_test: %s" % ("all checks passed" if failed == 0 else "%d CHECK(S) FAILED" % failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
