# Music set: fight, boss and final-boss themes, and three exploring loops

Abdulla's renders and the MIDI they come from. Three of them are in the game (feature `music-set`, on by default),
copied byte for byte to `assets/audio/` and played by `src/audio/music.gd` (`SET_BATTLES`). After a new render, copy the
new `.ogg` over the one in `assets/audio/`. This folder is under `tools/music/`, which Godot ignores.

| File | In the game as | Plays |
| --- | --- | --- |
| `donjon_piano_battle.ogg` | `assets/audio/set-fight.ogg` | A fight with a monster. 41.86 s, one loop. |
| `donjon_battle_boss.ogg` | `assets/audio/set-boss.ogg` | A fight with a champion (a dragon on the stairs). 41.86 s. |
| `donjon_battle_final_boss.ogg` | `assets/audio/set-final.ogg` | The fight with the last champion, at the Last Door. 45.33 s. |
| `donjon_explore_choir.ogg`, `donjon_explore_undercroft.ogg`, `donjon_explore_caves.ogg` | Not in the game yet | Exploring loops, 130.91 s each. Exploring still plays the hum theme. |
| `*.mid` | | The MIDI each render comes from. |

The three fight tracks measure -16.2 dBFS mean, 0.9 dB over the hum theme's combat loop, so `SET_TRIM_DB` plays them
2 dB under the battle volume.

## Still to write down

Which soundfont or instruments these were rendered with, and its licence. `assets/CREDITS.txt` names Abdulla as the
composer and nothing else until that is known.
