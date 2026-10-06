# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Yes/no questions (stairs down, Revivify, a monster asking to join) no longer hide in the top bar while every other key is silently ignored: they open as a glowing box over the view in the floor's accent color, with clickable answers, Enter/Esc for yes/no, and any other key shakes the box to show where to look. At the stairs you can simply walk away.
- Dungeon view perspective: the corridor is now a real 1/z projection (it used a geometric series, so far cells looked squashed), painted far to near with black-filled faces so nearer walls hide farther ones.
- No more phantom walls across side openings that lead into rooms and the boss hall.
- Wall decorations and stairs are mapped in perspective (a torch halfway down a side wall now sits halfway down it), and a torch's glow no longer leaks around the wall that hides it.
- The automap only reveals floor you could actually see.
- The automap shows walls: each side of seen floor that faces a wall gets a line in the floor's wall color, so walls no longer look the same as unexplored dark.

### Changed
- Fights have their own music, built on the game's own melody (A B C D D D E D E D C C C D D D) moved into D major and lifted through B♭ and C: a bright, driving 8-bit loop (`battle.m4a`, rendered by `scripts/build-battle.py`) crossfades in when a fight starts, and the dark ambient comes back when it ends. No more creepy ambient under combat.
- The dark ambient no longer plays nonstop: about 90 seconds of music, then a minute or two of quiet, then it drifts back.
- You see 6 cells ahead instead of 4, with lines fading into the dark with distance.
- Stairs down are larger and drawn in the floor's accent color so they stand out from a distance.

### Added
- GitHub Actions CI (`.github/workflows/ci.yml`): tests and a validated itch bundle on every push and pull request; pushes to `main` publish to https://aalfalasi.itch.io/donjon with butler.
- Music cues for good news, both quoting the same melody: a bright 8-bit fanfare when you go down the stairs (then quiet for a while instead of the creepy ambient), and a short victory jingle when you win a fight.
- `npm test`: tests for the view geometry (`crawler/test/render.test.js`) and music mood switching (`crawler/test/ambient.test.js`).
