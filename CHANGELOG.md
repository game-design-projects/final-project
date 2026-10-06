# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- The top status line no longer jumps around: one row, every slot (facing, gold, boons, achievements, toggles) a fixed width, so turning, earning gold or starting a fight only changes the text in place. Only the floor's name shortens (with an ellipsis, full name on hover) when space is tight.
- The dark ambient no longer plays on under the battle music: it now gets out of the way within 0.4 s when a fight starts (it took 5 s, so both played together for the first seconds).
- Yes/no questions (stairs down, Revivify, a monster asking to join) no longer hide in the top bar while every other key is silently ignored: they open as a glowing box over the view in the floor's accent color, with clickable answers, Enter/Esc for yes/no, and any other key shakes the box to show where to look. At the stairs you can simply walk away.
- Dungeon view perspective: the corridor is now a real 1/z projection (it used a geometric series, so far cells looked squashed), painted far to near with black-filled faces so nearer walls hide farther ones.
- No more phantom walls across side openings that lead into rooms and the boss hall.
- Wall decorations and stairs are mapped in perspective (a torch halfway down a side wall now sits halfway down it), and a torch's glow no longer leaks around the wall that hides it.
- The automap only reveals floor you could actually see.
- The automap shows walls: each side of seen floor that faces a wall gets a line in the floor's wall color, so walls no longer look the same as unexplored dark.

### Changed
- Scrollbars everywhere (log, panels) are square pixel bars instead of the browser's rounded ones, and focus rings are square.
- Tooltips are pixel art: every hover note is a framed box in the pixel fonts and the floor's color, with a pixel arrow, instead of the browser's grey system tooltip. Multi-part notes get one line each, and ability scores show as a small table (`public/tooltip.js`).
- The itch.io build starts in debug mode (Jev mind panel, `[DEBUG]` log lines, console hooks); `?nodebug` turns it off. Local play is unchanged.
- The party panel sits beside the view instead of at the bottom of the page, so you see everyone's health while choosing moves; the member choosing glows, and the one you're about to heal lights up. The automap moved right under the view, with a small key, and steps aside in fights; the whole screen fits in less height.
- Fights have their own music, built on the game's own melody (A B C D D D E D E D C C C D D D) moved into D major and lifted through B♭ and C: a bright, driving 8-bit loop (`battle.m4a`, rendered by `scripts/build-battle.py`) crossfades in when a fight starts, and the dark ambient comes back when it ends. No more creepy ambient under combat.
- Four battle loops instead of one, each the melody in a different key, mode, tempo and groove (heroic D major 124 BPM, fury E minor 132, march F major 112, gallop A major 120; none faster than 132). Each fight picks one at random, never the last one, and a long fight crossfades into another after two times round.
- The ambient comes back quickly: a 2-second fade-in, 2 seconds after a fight and 4 seconds after the stairs fanfare.
- The dark ambient no longer plays nonstop: about 90 seconds of music, then a minute or two of quiet, then it drifts back.
- You see 6 cells ahead instead of 4, with lines fading into the dark with distance.
- Stairs down are larger and drawn in the floor's accent color so they stand out from a distance.

### Added
- Monsters read their lines aloud with the browser's text to speech, each species with its own pitch and pace. Off by default; on by itself once you use voice input; L toggles it for good (`public/tts.js`).
- Achievements: 30 of them, about what makes Donjon different (talking, recruiting, vows, dice, champions, a few secrets), kept across runs. Unlocks slide in over the view with a jingle; K (or the trophy in the top bar) opens the full list with dates, progress bars and ??? for secrets (`public/achievements.js`).
- Debug REQUESTS tab in the Jev panel, in the game's pixel style (framed sections with label tabs, pixel triangles, JSON colored by token, square scrollbars): every API request with status, time, Jev calls, questions and tokens; open one for the exact request and response and each raw Jev call (state, questions, answers), with COPY buttons. The server returns the Jev calls for a request when asked with `?debug=1` (`public/inspector.js`).
- Mock Jev (`src/mock-jev.js`): seeded, well-formed random answers. `npm run crawler:mock` runs the game on it; the scenario scripts use it by default (`--live` for real calls); `npm test` now covers every API endpoint with it, and CI runs the scenarios on it.
- Hold Space to talk (or the HOLD TO SPEAK button) and speak instead of typing: in a fight it talks to the monsters, exploring to an ally, and in an empty talk box it just listens; the browser's built-in speech recognition fills the box live and sends it when you let go (`public/voice.js`).
- GitHub Actions CI (`.github/workflows/ci.yml`): tests and a validated itch bundle on every push and pull request; pushes to `main` publish to https://aalfalasi.itch.io/donjon with butler.
- Music cues for good news, both quoting the same melody: a bright 8-bit fanfare when you go down the stairs, and a short victory jingle when you win a fight.
- `npm test`: tests for the view geometry (`crawler/test/render.test.js`) and music mood switching (`crawler/test/ambient.test.js`).
