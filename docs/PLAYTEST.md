# A playtest session, start to finish

A plan for the half-hour playtests, so two testers' notes can be read side by side. Change it as the team likes: what
matters is that every session covers the same ground, and that a note can be traced back to the moment it is about.

## Before anyone sits down

- One build, one channel: the itch build or a zip from the release, not a mix, and the same one for every tester. Write the
  version down (it is on the main menu, bottom left).
- The seed: the pause menu's hint ends on it (`ESC RESUME · SEED 7`), and a run from source also prints `seed N` on the first
  floor. The seed is what the floors are made from, so a note that names it can be played again on the same floors; the
  monsters' words and choices are not in it, so a bug still wants the floor, the monster's name and what it was doing.
- Saves: the run autosaves on the way down, and six slots are on the menu. A tester can go back to a save rather than replay
  the whole run, so nobody has to see the same first floor twice.

## The thirty minutes

The order matters less than the coverage; the numbers are ten-minute blocks.

1. **The menu and the first minute.** Main menu: NEW GAME. A first run with the tips on opens on the practice floor, one slime
   above B1F; a later one starts on B1F, and SHOW THE TIPS AGAIN in SETTINGS brings the landing back. Watch whether the goal
   ("five floors down, and the only way out") and the first monster read without being told.
2. **A walk.** Arrows or WASD, ENTER to camp, **M** for the whole floor's map, **I** for what is around, **K** for
   achievements. Turn round, walk into a monster, and try the fight.
3. **A fight.** FIGHT at the right moment, HEAVY, ACT, SPARE, FLEE. The dodge box is the part to watch: does a glowing
   square, its colour and the marks on it read as "this will land here, now", and can a tester step off in time?
4. **The things a floor hides.** A cracked wall (walk into it), the chest behind it, a pad, the writing on a wall, the stairs,
   and a trader (floors 2 and 4, or below a market stair). Press **M** once 80% of a floor is seen: does the rest of the
   layout appearing help, or steal the mystery?
5. **The gate on the third stairs.** Someone has to hold it. Ask what the choice felt like, and whether the cost was clear.
6. **A champion.** The keepsake choice after it: three cards, one kept. Can a tester say what each does and why they picked it?
7. **The end.** The Last Door wants company. Ask what the ending screen said, and whether embers meant anything to them.

The **TEST ROOM** on the main menu is for a question the run cannot ask in thirty minutes: every kind of monster in a row, so
a tester can fight a deep one without walking there, and say whether it felt different from a first-floor one.

## What to watch for

These are the open questions, not the fixed ones. A note is most useful when it says which of these it touches.

- **Mystery against guidance.** The map now charts the rest of a floor once 80% is seen, and a monster may carry a map of it.
  Does that read as a reward, or as the dungeon being given away?
- **The spare and recruit loop.** Is SPARE ever the obvious move, and is the moment it becomes likely said before the choice?
- **Names over heads.** A monster's name, an ally's, a trader's, the one asking a favour. Is anything ever named that is not
  on the screen?
- **The first floor.** Does a tester know what they want after one floor, or only where the stairs are?
- **Voices.** SETTINGS, SOUND, MONSTER VOICES. Whether a monster's voice helps it read as a character, or gets in the way.

## What to write down

One note per moment, and the moment is what makes it useful:

- what happened, in one line ("the gate's second card said the others will see and stopped");
- where ("B3F, the gate on the stairs", or "a deep kind in the test room");
- what the tester said, as close to their words as you can get — "I don't know what the number by the name means" is worth
  more than "the UI was unclear";
- the build, if it is not the one everyone played.

Notes go into #41 for a playtest's summary, and into an issue of their own when one is a bug with a reproduction. A design
note goes to the issue that owns the question (#42 mystery, #56 who you are, #77 what a lord is).
