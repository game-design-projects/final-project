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
   square, its colour and the marks on it read as "this will land here, now", and can a tester step off in time? After two or
   three fights, ask what the level they reached said and what it gave them (#162).
4. **The things a floor hides.** A cracked wall (walk into it), the chest behind it, a pad, the writing on a wall, the stairs,
   and a trader (floors 2 and 4, or below a market stair). Press **M** once 80% of a floor is seen: does the rest of the
   layout appearing help, or steal the mystery?
5. **The gate on the third stairs.** Someone has to hold it. Ask what the choice felt like, and whether the cost was clear.
6. **A champion.** The keepsake choice after it: three cards, one kept. Can a tester say what each does and why they picked it?
7. **The end.** The Last Door wants company. Ask what the ending screen said, and whether embers meant anything to them.

The **TEST ROOM** on the main menu is for a question the run cannot ask in thirty minutes: every kind of monster in a row, so
a tester can fight a deep one without walking there, and say whether it felt different from a first-floor one. A clan's lord
stands on its aisle with a favour to ask, so the ask, the walk for the thing and the pay can be tried in one room.

## What to watch for

These are the open questions, not the fixed ones. A note is most useful when it says which of these it touches.

- **Mystery against guidance.** The map now charts the rest of a floor once 80% is seen, and a monster may carry a map of it.
  Does that read as a reward, or as the dungeon being given away?
- **The spare and recruit loop.** Is SPARE ever the obvious move, and is the moment it becomes likely said before the choice?
- **The commands beside FIGHT.** #163: HEAVY is the hard hit only near the middle of its mark now, and a blow landed wide pays
  no more than the FIGHT that hand would have had. Does any tester reach for HEAVY, ACT, ITEM or FLEE without being told, does a
  heavy hit that lands *badly* feel like the risk it is meant to be, and can they find the middle by eye or by the line's note?
- **The champion's goo.** #170: a champion's splash is a slime's cross on 0.7 s of warning instead of 0.82 s, so the
  first pattern of a champion's fight has to be read as it starts. Does it feel like a boss's rain rather than a slime's, and
  does a splash that lands before a tester has planned a step feel unfair rather than tight?
- **The twin lanterns.** #275: two lanterns flare in turn, and the pattern read as the set's hardest until the bot was
  allowed to stand still and wait for a flare to pass, which it clears at 0.15 hits a dodge at the champion's first pace and
  1.27 at its last. Does a tester who waits out a flare find the gap, and does the pair read as a boss's own attack rather
  than as two lights on a timer?
- **Names over heads.** A monster's name, an ally's, a trader's, the one asking a favour. Is anything ever named that is not
  on the screen?
- **The row under the picture.** LVL, HP with the thin level fill under it, GOLD, PARTY, FED (or HUNGRY/STARVING) at 11 px,
  and nerve beside the box while a fight is on. Can a tester find gold and the party without being pointed at them (#164)?
- **A level.** #162: every fight teaches experience, however it ended, and enough makes a level (2 more max HP and the health
  with it, and every second level a harder strike). Does a tester notice the banner and the row's fill, and can they say what
  the level gave them?
- **Clans on the other side.** #165: a kill is half as welcome to each of the clans on the other side as it is unwelcome to the
  victim's own, and the log says so the first time; two rival kills are worth one of its own dead, so killing a clan's enemies
  can cool a clan that hates you. Does a tester notice a rival clan's monsters starting friendlier, does a kill start to read as
  taking a side, and does the praise ever make killing feel cheaper than it should?
- **The first floor.** Does a tester know what they want after one floor, or only where the stairs are?
- **A favour, all the way.** Someone asks for something on some floors; a lord of a clan asks more, asks again where its biome
  comes back, and swears its clan when paid. Does a tester finish one, and can they say what they got?
- **A chase that ends.** A hunter that cannot see you for five steps gives up for ten, and a pad carries a chaser across the
  floor. Does a tester notice a chase end, or only that the monster left (#169)?
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
