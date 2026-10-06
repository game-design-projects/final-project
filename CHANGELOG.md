# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Dungeon view perspective: the corridor is now a real 1/z projection (it used a geometric series, so far cells looked squashed), painted far to near with black-filled faces so nearer walls hide farther ones.
- No more phantom walls across side openings that lead into rooms and the boss hall.
- Wall decorations and stairs are mapped in perspective (a torch halfway down a side wall now sits halfway down it), and a torch's glow no longer leaks around the wall that hides it.
- The automap only reveals floor you could actually see.
- The automap shows walls: each side of seen floor that faces a wall gets a line in the floor's wall color, so walls no longer look the same as unexplored dark.

### Changed
- Fights have their own music: a bright, driving 8-bit loop (`battle.m4a`, rendered by `scripts/build-battle.py`) crossfades in when a fight starts, and the dark ambient comes back when it ends. No more creepy ambient under combat.
- You see 6 cells ahead instead of 4, with lines fading into the dark with distance.
- Stairs down are larger and drawn in the floor's accent color so they stand out from a distance.

### Added
- `npm test`: tests for the view geometry (`crawler/test/render.test.js`) and music mood switching (`crawler/test/ambient.test.js`).
