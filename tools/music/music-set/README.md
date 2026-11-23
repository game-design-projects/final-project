# Music set: fight, boss and final-boss themes, and three exploring loops

Abdulla's renders and the MIDI they come from. None of them is in the game any more: they share the hum theme's melody,
and the game keeps only one old theme (the hum theme's exploring loop, at the camp); every fight now has its own tune
from `../build-themes.py`. The three fights played as `set-fight`, `set-boss` and `set-final` until then (git history has
them). This folder is under `tools/music/`, which Godot ignores.

| File | Was in the game as | Played |
| --- | --- | --- |
| `donjon_piano_battle.ogg` | `assets/audio/set-fight.ogg` | A fight with a monster. 41.86 s, one loop. |
| `donjon_battle_boss.ogg` | `assets/audio/set-boss.ogg` | A fight with a champion (a dragon on the stairs). 41.86 s. |
| `donjon_battle_final_boss.ogg` | `assets/audio/set-final.ogg` | The fight with the last champion, at the Last Door. 45.33 s. |
| `donjon_explore_choir.ogg`, `donjon_explore_undercroft.ogg`, `donjon_explore_caves.ogg` | Never in the game | Exploring loops, 130.91 s each. |
| `*.mid` | | The MIDI each render comes from. |

The three fight tracks measure -16.2 dBFS mean, 0.9 dB over the hum theme's combat loop (both source only now).

## Still to write down

Which soundfont or instruments these were rendered with, and its licence. None of them ships, so `assets/CREDITS.txt`
carries no entry for them; one is needed before any of them is played again.
