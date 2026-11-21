#!/usr/bin/env python3
"""Every script at the top of tools/ is named in docs/DEVELOPMENT.md, and every row of its two script tables starts with a .gd in tools/.

The doc is where someone looks for the tool that checks a thing, and a tool nobody's told about is one only its author runs.
It lost three anyway (`favours_test.sh`, `pack_version_test.py`, `intro_refs.py`) without anything failing, and got them
back by hand (#240) — twice now, since markdown is never compiled and no run reads it. `tools/changelog_test.py` exists for
the same reason on the changelog's links.

    python3 tools/doc_tools_test.py

The checks: every regular file at the top of tools/ ending in .gd, .sh or .py is named in the doc — a .gd by its stem, the
way the tables name it (`favours_test.gd` is `favours_test`), the others by their whole name, since `tools/build.sh` is
named that way in the Commands block; and every row of the doc's two tables (`| Script | ... |`) starts with, in backticks, a
.gd that is in tools/, because every row of both is a `godot ... -s res://tools/<name>.gd` run — headless for the suites,
with a window for the tools that draw — and a shell script in one of them would be a command that cannot run. A directory
under tools/ is not a tool here: `tools/voices/`, `tools/music/`, `tools/art/` and `tools/godot-mcp/` carry their own
README, and CI calls what they hold by path.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
DOC = os.path.join(ROOT, "docs", "DEVELOPMENT.md")
SOURCES = (".gd", ".sh", ".py")

failed = 0


def check(ok, what):
    global failed
    print("doc_tools_test: %s %s" % ("ok  " if ok else "FAIL", what))
    failed += 0 if ok else 1


def tools_here():
    return sorted(
        f for f in os.listdir(TOOLS) if os.path.isfile(os.path.join(TOOLS, f)) and f.endswith(SOURCES)
    )


def tables(text):
    """The first column of every table whose header starts with `Script`, one list of cells per table."""
    found = []
    rows = None
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.strip().startswith("|") else None
        if rows is None:
            if cells and cells[0] == "Script":
                rows = []
            continue
        if cells is None:
            found.append(rows)
            rows = None
            continue
        if set("".join(cells)) <= set("-: "):  # | --- | --- |
            continue
        rows.append(cells[0])
    if rows is not None:
        found.append(rows)
    return found


def main():
    text = open(DOC, encoding="utf-8").read()
    here = tools_here()
    missing = [f for f in here if (f[: -len(".gd")] if f.endswith(".gd") else f) not in text]
    check(not missing, "every script at the top of tools/ is named in the doc (%d scripts, %d unnamed%s)" % (
        len(here), len(missing), (": " + ", ".join(missing)) if missing else ""))

    gd = {f[: -len(".gd")] for f in here if f.endswith(".gd")}
    sheets = tables(text)
    stale = []
    unstarted = []
    rows = 0
    for cells in sheets:
        for cell in cells:
            rows += 1
            names = re.findall(r"`([^`]+)`", cell)
            if not names or not cell.startswith("`" + names[0] + "`"):
                unstarted.append(cell or "an empty cell")
            for name in names:
                if name not in gd:
                    stale.append(name)
    check(len(sheets) == 2, "the doc has the two script tables (%d found)" % len(sheets))
    check(
        not unstarted,
        "every row of those tables opens with its name, in backticks (%d rows%s)" % (
            rows, (", and these do not: " + ", ".join(unstarted)) if unstarted else ""),
    )
    check(
        not stale,
        "every row of those tables names a script in tools/ (%d rows%s)" % (
            rows, (", and these are not .gd scripts there: " + ", ".join(sorted(set(stale)))) if stale else ""),
    )

    print("doc_tools_test: %s" % ("all checks passed" if failed == 0 else "%d CHECK(S) FAILED" % failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
