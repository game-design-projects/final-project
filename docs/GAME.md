# The game

![The foe's card in a fight](shots/foe-card.png)

The main menu has Continue, New Game, Load Game, the save manager, Settings, Credits and Quit. A run is one floor: find the stairs. The monsters stand in the corridors, and walking into one starts a fight.

## Walking

A floor is a 13×13 maze with a 5×5 hall in the middle, where the champion stands, and the stairs at the farthest cell. Four monsters and the champion wait on it. The camera glides from cell to cell, torches light the walls, and every floor wears one of eight palettes picked from the run's seed.

The automap in the corner learns what the camera sees. Monsters you have seen show as dots, and the champion is marked in red from the start.

## Fights

- **FIGHT** is a timing bar: strike when the line crosses the middle. A hit sours the monster's mood.
- **ACT** has CHECK (free), three acts for that species, and SAY SOMETHING, one typed line per fight. Ask about the stairs, the champion or another monster, and it may answer, depending on its personality. Bandits and snakes can take a 6-gold cut to stand down; you start with 8.
- **SPARE** rolls against the monster's mercy, shown as a percentage on the command. Its name turns gold with "(MERCY 50%+)" when the odds are at least even. A spared monster may ask to join.
- **FLEE** always works, except from the champion. The monster stays where it is, back at full health.

Then the monster attacks, unless what you did calmed it.

## The box: lit squares hurt

You dodge on a 7×7 grid. Each faction attacks in its own genre:

| Monster | Genre | How it attacks |
| --- | --- | --- |
| Slime | Goo rain | Falling goo; watch where it will land |
| Bandit | Chess | Rook (row and column), bishop (diagonals), knight (L-jumps) |
| Snake | Shadow | A lantern flares; hide in a pillar's shadow |
| Rock | Rhythm | It stomps on the beat; move between beats |
| Dragon (champion) | All four | Its rules change every turn |

You have 20 HP. A hit costs 3, or 4 from the champion. Nothing heals between fights, and if you die you can try the fight again at full health.

## The mind

Every monster has a species' tastes, its own traits and a motive, and meters for friendliness, anger and fear. Each act asks the mind how it feels, whether it would accept mercy and how hard it attacks. Hover the foe or press **I** to see its meters, a clue to its personality, and the last two answers.

Monsters think through one interface (`src/mind/`): local rules, a seeded random mind (`mock`), or Jev through the proxy, falling back to the local rules whenever it can't answer.

## Allies

Up to three spared monsters travel with you, and each gives a passive charm:

| Ally | Charm | Effect |
| --- | --- | --- |
| Slime | BOUNCY | Absorbs the first hit of every fight |
| Bandit | KEEN EYE | Warnings stay lit longer |
| Snake | SLIPPERY | Longer safety after you get hit |
| Rock | STEADY | The strike bar moves slower |
| Dragon | HOARD-FIRE | +4 damage on every strike |

Allies have values and judge what you do. Upset one enough and it walks out. Hover its chip or press **I** to see its mood, loyalty and what it cares about.

## Routes and saves

The stairs name how you played: ghost (met no one), quiet (killed no one), blood (spared no one) or tangled.

A run is autosaved when a floor starts and whenever you are back to walking. The pause menu saves into six slots while you walk; a fight in progress isn't saved.
