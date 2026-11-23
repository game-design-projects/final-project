# Music set: fight, boss and final-boss themes, and three exploring loops

Abdulla's renders and the MIDI they come from. Three of them are in the game (the feature `music-set`, on by default),
copied byte for byte to `assets/audio/` and played by `src/audio/music.gd` (`SET`, `set_theme`) in place of the foe's own
tune: #299 took them out when every foe got a tune of its own, and they are back as a choice beside those
(`no-music-set` plays every foe its own). After a new render, copy the new `.ogg` over the one in `assets/audio/`. This
folder is under `tools/music/`, which Godot ignores.

| File | In the game as | Plays |
| --- | --- | --- |
| `donjon_piano_battle.ogg` | `assets/audio/set-fight.ogg` | A fight with a monster. 41.86 s, one loop. |
| `donjon_battle_boss.ogg` | `assets/audio/set-boss.ogg` | A fight with a champion (a dragon on the stairs). 41.86 s. |
| `donjon_battle_final_boss.ogg` | `assets/audio/set-final.ogg` | The fight with the last champion, at the Last Door. 45.33 s. |
| `donjon_explore_choir.ogg`, `donjon_explore_undercroft.ogg`, `donjon_explore_caves.ogg` | Not in the game | Exploring loops, 130.91 s each. |
| `*.mid` | | The MIDI each render comes from. |

The three fight tracks measure -16.2 to -16.3 dBFS mean against -17.0 for the foes' own tunes, so `TRIM_DB` plays them
1 dB down.

## Still to write down

Which soundfont or instruments these were rendered with, and its licence. `assets/CREDITS.txt` names Abdulla as the
composer and says this is not recorded yet; it wants writing down before a release.
