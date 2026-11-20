#!/usr/bin/env python3
"""Checks the changelog's version links against its sections, and its newest section against the project's version.

    python3 tools/changelog_test.py

Keep a Changelog keeps one link reference per version at the bottom of the file, and GitHub draws a heading with no such
link as bare text. 0.9.5 went out that way: `## [0.9.5] - 2026-11-20` had no link of its own, and `[Unreleased]` still
compared from `v0.9.4`, so the notes of a version already shipped read as unreleased. Nothing said so — `release.yml` looks
only for the heading, and a markdown file is never compiled.

The checks: every version heading has its link, unless a comment in the file says its tag isn't cut yet (0.5.3); the
`[Unreleased]` link compares from the newest version; that version's link compares from the one before it; no link points at
a section the changelog doesn't have, and no version is filed twice; and the newest section is the version `project.godot`
holds, the pair `release.yml` cuts a tag from.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
PROJECT = os.path.join(ROOT, "project.godot")

failed = 0


def check(ok, what):
    global failed
    print("changelog_test: %s %s" % ("ok  " if ok else "FAIL", what))
    failed += 0 if ok else 1


def read():
    with open(CHANGELOG, encoding="utf-8") as f:
        lines = f.read().splitlines()
    sections = [m.group(1) for m in (re.match(r"^## \[([^\]]+)\]", line) for line in lines) if m]
    links = {}
    doubled = set()
    for line in lines:
        m = re.match(r"^\[([^\]]+)\]:\s*(\S+)\s*$", line)
        if not m:
            continue
        if m.group(1) in links:
            doubled.add(m.group(1))
        links[m.group(1)] = m.group(2)
    # A version whose tag isn't cut has no link yet, and a comment above the block is where the file says which.
    untagged = set()
    for line in lines:
        if line.lstrip().startswith("<!--"):
            untagged.update(re.findall(r"v(\d[\w.\-]*)", line))
    return sections, links, doubled, untagged


def main():
    sections, links, doubled, untagged = read()
    released = [s for s in sections if s != "Unreleased"]
    check(bool(released) and sections[0] == "Unreleased", "the changelog opens with an [Unreleased] section (%d versions below it)" % len(released))
    check(len(set(sections)) == len(sections), "no version is filed twice (%d sections)" % len(sections))

    # every version heading has a link, unless the file says its tag isn't cut
    missing = [s for s in released if s not in links and s not in untagged]
    check(not missing, "every version section has a link" + ("" if not missing else ": none for %s" % ", ".join("[%s]" % s for s in missing)))
    with_tag = [s for s in released if s in links]
    check(bool(with_tag), "at least one version has a link (%s)" % ", ".join(with_tag[:3]))

    # no link points at a section that isn't there
    orphans = [label for label in links if label != "Unreleased" and label not in sections]
    check(not orphans, "every link has a section" + ("" if not orphans else ": none for %s" % ", ".join("[%s]" % o for o in orphans)))
    check(not doubled, "no version has two links" + ("" if not doubled else ": %s" % ", ".join("[%s]" % d for d in sorted(doubled))))

    # [Unreleased] compares from the newest section, not from the version before it: a release that forgets this line leaves
    # a shipped version's notes under a link that calls them unreleased
    newest = released[0] if released else None
    unreleased = links.get("Unreleased", "")
    check(
        newest is not None and unreleased.endswith("/compare/v%s...main" % newest),
        "[Unreleased] compares from [%s] (%s)" % (newest, unreleased.rsplit("/", 1)[-1]) if newest else "[Unreleased] compares from the newest version",
    )

    # the newest version compares from the one before it: the newest older version that has a link, since a version whose
    # tag was never cut sits in the file without one (0.5.3, and 0.6.0 compares from 0.5.2 for that reason)
    before = [s for s in released[1:] if s in links]
    base = before[0] if before else None
    check(
        newest in links and base is not None and links[newest].endswith("/compare/v%s...v%s" % (base, newest)),
        "[%s] compares from [%s] (%s)" % (newest, base, links.get(newest, "no link").rsplit("/", 1)[-1]) if newest and base else "the newest version compares from the one before it",
    )

    # the newest section is the version the project holds, which is the pair a tag needs
    with open(PROJECT, encoding="utf-8") as f:
        m = re.search(r'^config/version="([^"]+)"', f.read(), re.M)
    version = m.group(1) if m else None
    check(
        version is not None and version == (released[0] if released else None),
        'the newest section is config/version in project.godot (%s)' % version,
    )

    print("changelog_test: %s" % ("all checks passed" if failed == 0 else "%d CHECK(S) FAILED" % failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
