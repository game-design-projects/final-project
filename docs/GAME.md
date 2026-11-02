# The game

What Donjon does, for players and designers: the screen, the rules, the monsters, Genre Halls and what Jev decides. How to run it: [README.md](../README.md); how the code is laid out: [ARCHITECTURE.md](ARCHITECTURE.md).

## The screen, voices and feel

**The screen.** The top line says where you are: the floor, the way you face (or that you're in a fight), gold, boons, and the switches as keycaps with pixel icons (H tips, J Jev panel in debug runs, K achievements, L voices, O sound, P music; slashed red when off, hover for what they do). Beside the view sit **the party** (top), your active vows (bottom) and the log between them; monster allies get one line each under an "ALLIES 2/3" count (the party holds six: your three adventurers and up to three monsters). The automap sits right under the view with a small key (you, stairs down, the champion), and steps aside in a fight. Everything you can do sits in the **command dock right under the view**, as keycap buttons: press the key or click the button. Hover a button to read what it does on the line beneath. When the game waits on you (a menu like CHOOSE MOVES' spell list, the talk box, "any key" after a Roll of Fate), the dock lights up in the floor's color, and a key it doesn't take shakes it instead of vanishing. The window can be any size: the screen lays itself out for 1180 × 820 and scales or rearranges from there.

**Questions wait where you're looking.** When the game needs a yes or no (stairs down, Revivify, a monster asking to join), a box lights up over the view in the floor's accent color with clickable answers. **Y**/**Enter** says yes, **N**/**Esc** no, and any other key shakes the box so you can't miss it. At the stairs you can simply walk away.

**The party panel** reads at a glance, mostly without words. While you choose moves, the member choosing glows with a ▶; while you pick who to heal or revive, the one highlighted in the menu lights up here too:

- **Health** is a segmented bar: its length and color say how hurt someone is (green healthy, yellow HURT, red CRITICAL). At 0 it reads DYING (blinking) with their death saves as boxes, three green for successes and three red for failures; STABLE once three succeed; the dead get a skull and a struck-through name.
- **Armor** is a shield with the number an attacker has to reach.
- **Spells** are pips, one per spell slot, colored by circle (blue first, violet second, gold third); lit pips are left, hollow ones are spent. The fighter's two pips are Second Wind and Action Surge. In the CHOOSE MOVES menu each spell shows the same colored pips for the slots it would draw on, or FREE.
- **Status** chips pair a pixel icon with a word: POISONED (droplet), ENTANGLED (chain), KNOCKED DOWN (arrow), an ally's loyalty (heart: DEVOTED, CONTENT, UNEASY, RESENTFUL, MAY LEAVE), its talk buff (PUMPED, BOUNCY, ...) or mood. Monsters in a fight wear the same icons over their health bars (ASLEEP, PARALYZED, ENRAGED, SCARED, VETERAN, ...).

Hover any of them for the details (exact numbers, ability scores, boons).

**Monsters answer out loud.** Monsters and allies read their lines aloud, each kind in its own voice (a deep, slow dragon; a squeaky slime), skipping the *stage directions*. It starts off, and turns on by itself the first time you talk to the game with your voice: someone speaking to the monsters wants to hear them answer. **L** steps through the voices this build has, then off, and the game keeps your choice:

- **Rendered ahead**, when the game has a voice bank in `assets/voices/`: every line in the game spoken by an open text-to-speech model, one bank per model (`cosyvoice3`, the engine of the Feiyu stack, and `qwen3`), each monster's voice cloned from a Creative Commons recording. A bank plays instantly and sounds the same on every machine. A line that names someone (*"You side with them, ROLF?"*) isn't in it and goes to the next voice. How they're made: [tools/voices/README.md](../tools/voices/README.md).
- **A live service** on your network, when one is set up: a Feiyu voice service or a Qwen3-TTS service synthesises each line as it's said. Any line, a second or more to start (they need a good GPU). See [Voices](AUDIO.md#voices).
- **Your system's voice**: the macOS, Windows or Linux speech engine, or the browser's on the web; each monster gets its own pitch and pace.

The keycap only shows when there is at least one. Speech can't be turned up past full volume, so while a monster talks the music drops to a quarter and the effects to half, then come back as it finishes. It goes quiet while the microphone listens, and drops a backlog rather than falling behind the fight (`src/audio/tts.gd`, `tts_engines.gd`).

**How it looks, sounds and feels.** The view is a 3D set drawn as the 2D wireframe was (`src/view/stage3d.gd`): the floor is built from the map (`dungeon3d.gd`) and the monsters from simple shapes (`monsters3d.gd`), and their shaders fill every surface black and draw only lines, in the floor's wall color and each monster's own, dimming with distance as the old drawing did (`line.gdshaderinc`; `stone.gdshader` outlines every wall face, `ink.gdshader` every model's parts, `flame.gdshader` the torch flames). Names, health bars, dice and floating numbers are drawn in 2D over it. [docs/shots/](shots/) has the 3D view next to the old 2D one, every monster, and a walk down a corridor into a fight (`walk.gif`). It runs through a shader (`src/view/postfx.gd`, `postfx.gdshader`) that makes the lines glow like an old vector monitor: lines bloom, the pixels stay sharp at any window size, faint scanlines follow the game's own rows, and each floor's accent color tints the dark. Game state drives it, along with the music and the shake, through one event bus (`src/rules/juice.gd` `FX_EVENTS`): the rules announce hits, kills, falls, steps and fights, and the presentation answers.

- **Danger** (`danger_of`: how much health the living have left, and whether anyone is rolling death saves) drains the color, closes in a red edge, muffles the music behind a low-pass filter and starts a heartbeat on the music's beat: every other beat while hurt, every beat when someone is about to die. The red edge pulses with each heartbeat, timed from the audio clock.
- **Hits** shake the screen in proportion to the blow (trauma that drains away, so small hits nudge and big ones rattle). Critical hits and kills freeze the monsters for a few frames and flash the view; getting hurt flashes the edges red. Big moments dip the music for an instant so they punch through.
- **Moving** eases: the camera glides a step, swings round on a turn, and lunges at a wall you walk into. When a fight starts it backs off and looks down a little, and the monsters stand in the corridor in front of you, two or three in a V.
- **Sound**: music and effects share one mixing desk (`src/audio/mix.gd`: Godot audio buses, ending in a limiter). Repeated effects (hits, misses, coins...) get a random detune and volume each time, and at most a few copies of one sound start at once (`src/audio/sfx.gd` `VARY`, `POLY`).

The `nofx` flag turns the shader off: the plain view shows, and everything else works the same. When the browser reports prefers-reduced-motion (web build only; see [Platform differences](DEVELOPMENT.md#platform-differences)) the game turns off the shake, the step and turn transitions, the pulsing glows and the blinking, and tones the flashes down.

**Hold Space to talk.** Instead of typing, hold **Space**, say it, and let go: the words fill the talk box as you speak and are sent when you let go. In a fight it talks to the monsters (like T); exploring, it talks to a monster ally (like E; pick one first if you have several); with a talk box already open and empty (after T, R or E) it just listens. A quick tap of Space is still an ordinary key, and with words already in the box Space types a space. With a mouse or a finger, press and hold the **HOLD TO SPEAK** button beside the box.

- **Desktop builds** hear you on your own computer, with nothing sent anywhere: NVIDIA's Nemotron Speech Streaming model (English) running in a small helper program the game carries (sherpa-onnx). The model is a one-time **662 MB download**: the first time you hold Space the game offers it, and holding Space again starts it (keep typing meanwhile; the log says when it's done). It loads in a few seconds the first time you speak in a session, and uses about 1 GB of memory while the game runs. macOS asks for the microphone once.
- **The web build** uses the browser's speech recognition (Web Speech API: Chrome, Edge and Safari; Chrome sends the audio to Google's recognizer, Safari to Apple's), in the browser's language, and asks for the microphone the first time. In Firefox the button hides and Space is an ordinary key: type instead.

The logic is `src/audio/voice.gd`, and `src/audio/asr.gd` for the desktop recognizer.

**Achievements.** Thirty of them, for what makes this game itself rather than for grinding: words that leave a monster DELIGHTED or IN STITCHES, a fight won without a single attack, your first ally, a shiny, three monster allies at once, a vow carried down the stairs (or broken and forgiven), a natural 20 while talking, a death save that pulls someone back up, floors 5 and 10, a red champion slain or talked down, a legendary boon. Five are secret and read **???** until you stumble on them. When you earn one, a gold note slides down over the top of the view with a short jingle (the **O** toggle mutes it) and the log says so; it never takes a key or a click away from you. **K** (or the trophy keycap in the top bar, which also shows your count) lists them all over the view: earned ones lit in their group's color with the date, locked ones dimmed with what to do, and progress bars for the two that count up across runs (EMPATH, every feeling; MENAGERIE, every kind of monster). While the list is open it glows, **K** or **Esc** closes it, the arrows scroll it, and any other key shakes it. Achievements are kept across runs, deaths and restarts in the game's saved data (`donjon.achievements`, see [Platform differences](DEVELOPMENT.md#platform-differences)). The list and its rules live in `src/rules/achievements.gd`; the game calls it from one-line hooks.

**Tips.** New players get one short hint at a time, the first time each thing matters: how to walk, the automap, the stairs, your first fight (and that you can talk), targeting, feelings, a monster warming to you, your first ally, camping when hurt, levelling up, someone going down, a champion's floor. Each shows once, in a framed note over the bottom of the view, and lights up what it talks about (the keys' buttons, the map, the party). It never blocks anything: your next key does its job and clears the hint, and a key that does nothing nudges it instead. **H** turns tips off; **H** again turns them back on from the start. Seen tips are remembered (`hallsOfJev.tipsSeen`, `hallsOfJev.tipsOff`). The hints and their wording live in `src/rules/tutorial.gd`. **Your first fight is a lesson**: one shy slime, and only TALK works (it glows, the rest wait, dimmed), then only RECRUIT, and the slime always says yes. It's how you learn that monsters here listen and can join you. It happens once (H off skips it; H back on replays it); every later fight is yours.


## The rules

### D&D-style combat

The rules follow D&D 5e, simplified (`src/rules/dnd.gd`). Every roll is shown in the log, in words, e.g. `HORTENSE ATTACKS KRUNK: ROLLED 16 (ADVANTAGE) +5 = 21 VS ARMOR 12. HIT! 7 DAMAGE.` Saving throws read `ROLLED 9, NEEDED 15`, spell descriptions give damage as a range (`8-48 FIRE TO EVERY ENEMY`) rather than dice notation, and floors are FLOOR 1, FLOOR 2... in the game.

- **The party:** HORTENSE is a fighter (longsword, AC 16, Second Wind and Action Surge once per rest, a second attack at level 5). ROLF is a cleric (mace, healing and holy spells). EUGENE is a wizard (Fire Bolt and attack spells). Each has ability modifiers; hover a party row to see them. The game calls armor class ARMOR, hit points HEALTH and experience EXPERIENCE on screen.
- **Initiative:** each fight opens with a d20 roll for each side. Whoever wins acts first.
- **Attacks:** d20 + proficiency + ability against the target's armor class. A natural 20 is a critical hit and rolls the damage dice twice; a natural 1 always misses.
- **Advantage:** roll two d20s and keep the higher. You get it against monsters that are asleep, paralyzed, glowing from Guiding Bolt, or off guard from flattery. Disadvantage (keep the lower) comes from being poisoned or restrained, or attacking a monster that is dodging.
- **Spells use slots** on the 5e table (2 first-circle slots at level 1, up to third-circle spells at level 5). Cantrips are free and roll a second die from level 5. Camping restores slots.
  - Wizard: Fire Bolt, Magic Missile, Burning Hands, Sleep, Scorching Ray, Hold Monster, Fireball.
  - Cleric: Sacred Flame, Cure Wounds, Bless, Guiding Bolt, Prayer of Healing, Revivify, Spirit Guardians.
- **Saving throws:** area spells, Hold Monster and monster specials call for a save against a DC; a success halves the damage or avoids the effect. From FLOOR 3, monster specials also poison, entangle (restrained) or knock down (prone, losing your next action).
- **Death saves:** at 0 HP a member falls unconscious instead of dying. At the start of each of your turns they roll a d20: 10+ is a success and below 10 a failure (a natural 1 counts as two). Three successes stabilize them, three failures kill them, and a natural 20 brings them back with 1 HP. Any healing gets them up, and after a fight they come to with 1 HP. The dead can be brought back with Revivify, in a fight or while camping.
- **Camping (C)** heals every living member by half their maximum health, clears conditions and returns spell slots and skills. A cleric who knows Revivify offers to raise the dead (it costs a third-circle slot). One camp in four is found by a wandering encounter.
- **Monster allies** act on their own each round: an attack, or their species' special every few rounds.

### Talking always matters

- **Charisma checks:** when you talk, your best talker rolls Charisma. A strong roll makes your words land harder (up to ×2 on a natural 20); a natural 1 halves them.
- **Feelings:** every time you talk to monsters, pay them, or ask them to join, Jev picks how each one **feels**, and code gives every feeling a visible effect (`src/rules/emotions.gd`):

  | Feeling | Effect |
  | --- | --- |
  | DELIGHTED | won't attack this round |
  | IN STITCHES | too busy laughing to fight |
  | TOUCHED | its heart opens: it won't attack you this round, and if it likes you enough it asks to come along |
  | FLATTERED | lowers its guard: you get advantage against it |
  | INTRIGUED | lets slip a weak spot: +2 to hit it for the rest of the fight |
  | CONFUSED | loses its turn |
  | SADDENED | disadvantage on its attacks |
  | OFFENDED | +2 damage against you |
  | ENRAGED | advantage and +3 damage, but reckless (armor −3) |
  | TERRIFIED | disadvantage on attacks, and it drops gold |

  Each feeling also moves its friendliness, anger or fear. You never see those numbers: you read the mood the way you would at a table, from what it says and how it moves. The log narrates a tell for every feeling ("Grak lets its big ears droop."), and when a monster changes sides ("the fight has gone out of it", "You've made an enemy").
- **Recruit (R):** ask your target to join, with or without words. Your talker rolls Persuasion against a DC set by how much it likes you, how angry it is, and whether it is losing. A convincing or irresistible pitch brings it up to the point where it would consider joining; a close, clumsy or disastrous one only nudges (or sours) its mood. Then the monster answers in character, and the log always says why, so what it seems to feel and what it does agree:
  - *"Grak grins, showing crooked teeth, but grunts that it won't leave Snag."* (likes you, but won't abandon its brother)
  - *"Glop still quivers a little, but burbles that it won't be alone down here anymore."* (unsure of you, but comes anyway)
  - *"Drip wobbles from side to side and burbles that it didn't like how you asked."* (a botched pitch to a friend)

  Reasons to refuse: it doesn't know you well enough yet, wants more first, is still angry, didn't like how you asked, won't leave the others with it, is too proud, won't leave its home, is afraid of what lies deeper, or you let it down before. Reasons to come: it likes you, respects your strength, wants gold and loot, is lonely, wants to be with its kind in your party, feels safer with you, is curious, or is grateful. Winning a monster over, or letting it leave in peace, gives half its XP.
- **Ally talks (E)** always have a result, by how your words land (0–4): it sulks and sits out the next fight, gets distracted (−2 to hit), feels steady (+1 to hit), gets its species buff, or is inspired (buff, full heal and a level).

### Floors and champions

- **Complexity grows as you descend.** FLOOR 1 is a small maze with lone slimes and goblins. FLOOR 2 brings pairs, bandits and snake people; FLOOR 3 groups of three, rock entities, and specials that inflict conditions; FLOOR 4 dragons and wider halls (a floor's maze grows two cells a side per floor, from 15 up to 25); FLOOR 6 on, veteran monsters (more health, sharper attacks). Each new rule is announced when you arrive.
- **Every 5th floor** has a 5×5 hall at its heart with a **red champion** in the middle, marked red on your map and visible down the corridor. It is a normal monster of its kind but far harder: about 2.2× the HP, two attacks a turn, a faster special, better saves, and Legendary Resistance against the first two Sleep or Hold spells. You can still talk to it and recruit it, though it takes more to impress.
- Killing it, winning it over, or talking it into leaving earns a **Great Roll of Fate**: a boon at double strength, with a 60% chance of a legendary one (PHOENIX FEATHER, LEGENDARY ARMS, ARCHMAGE'S CROWN, TITAN'S BLOOD, TWIN SOUL). It's optional: the stairs are elsewhere.

### Roguelike progression

- **Roll of Fate:** every time you take the stairs down, you roll one random boon. Its strength scales with the floor you just cleared, and boons stack. The pool:
  - WHETSTONE: +12% damage per floor of depth, multiplying with earlier ones
  - KEEN EYE: crit on a wider range (19–20, then 18–20, down to 15–20)
  - TRUE AIM: + to hit
  - FLURRY: strikes per turn go 1× → 2× → 3× → 4× → 8×
  - IRON SKIN: higher AC
  - VAMPIRIC EDGE: heal a share of damage dealt
  - ARCANE SURGE: a caster gets more spell slots and stronger spells
  - VIGOR: max HP for the whole party
  - GOLDEN TOUCH: more gold from monsters

  Press **B** to list your boons, or hover a party row to see that member's stats.
- **Balance:** monster HP grows 1.3× per floor and damage 1.1× per floor. Armor and to-hit creep up slowly, as in 5e, so your dice keep mattering.
- **Levels:** each party member earns XP and levels up on their own, gaining HP, proficiency, spell slots and new spells, as in 5e. Recruited monsters join at the current floor's level.
- **The view** (`src/view/render.gd`) is a true perspective projection of the maze, six cells deep: walls are painted far to near so nearer ones hide what's behind, side passages open into the rooms and halls that are really there, and lines fade into the dark with distance. The automap fills in only floor you have actually seen, and draws the walls beside it as lines.
- **Floors:** each one gets a random color theme (Bone Crypt, Blood Vault, Frost Warrens and others). Walls carry torches that flicker and glow, chains, banners, barred windows, skull niches and cracks. Placement is seeded per floor, so decorations stay put as you move.
- **Sound effects** (`src/audio/sfx.gd`) are synthesized by the game, with no sound files: hits, crits, misses, kills, spells, heals, dice, feelings, joins, level-ups, and the Roll of Fate's ticking spin and landing fanfare. Each is a recipe built from tones, filtered noise and a formant voice (`src/audio/synth.gd`), rendered once into a sample while the game starts and played from there.

### Groups, ally talks and vows

- **Groups.** You can meet 1–3 monsters at once, possibly of different species, and one Jev request decides all their moves each round. Monsters see which side the others are on. When one warms to the party, the rest hear it "sided with the party against them", and a hostile monster may club the turncoat. A friendly monster that gets attacked by its own group may flee. Code only lets a monster turn on another when they're on opposite sides or one hit the other.
- **Rolled on Jev's odds.** Monsters don't always take Jev's top choice. Any action at 15% or more can happen, in proportion to its probability. Jev's probabilities are calibrated, so a 20% "turn on the traitor" really happens about one time in five.
- **Talking to allies (E).** Each ally hears you once per floor. If your words land well (3+ out of 4), it gets a buff for the next fight: goblin **PUMPED** (double damage), slime **BOUNCY** (absorbs a hit), dragon **STORMING** (free lightning on every enemy), and so on. Worse results have consequences too (see above).
- **Vows (V).** Build a promise from menus: *I WILL / I WON'T* → *KILL / TALK TO / GIVE GOLD TO / RUN FROM / BEFRIEND* → *SLIMES / GOBLINS / DRAGONS / MONSTERS*. Swear to an ally (once per ally per floor) or to the monster you're targeting (once per fight); you can keep six active vows. Jev judges how the monster feels about the promise, which shifts friendliness or loyalty.
- **Breaking vows.** Because vows are structured, code checks them exactly against what you do (killing, sparing, talking, paying, fleeing, attacking, recruiting). A broken vow gets slashed in the ledger, and the monster you swore to responds, with Jev picking one of:
  - **forgive** (only if loyalty is still at least 35)
  - **leave the party**
  - **attack you** (a fight where you can win it back, though rejoining takes more friendliness than before)
  - **steal your gold** (60% chance to get away with 25–50% of it; otherwise you catch it)

  If you swore to a monster that's still in the fight, it gets angry instead. If the one you swore to is gone, nobody holds you to it.
- **Allies explain themselves.** After a fight, each ally's reaction line matches how it judged you, and the log names the moment it can't get past ("Glop can't stomach how you killed Drip while it begged for mercy.") or liked. An ally that nearly walked out "stays. For now." A betrayed ally that wanted to forgive you but can't says so before it leaves.

Test these against the live API with `cli/social_scenarios.gd -- --live`, or in a debug run on the web with `halls.meet("goblin", "slime")`, `halls.hostile("slime")`, `halls.ally("slime", "Glop")`, and the guided first fight with `halls.lesson()`.

## The monsters

| | Likes | Hates | As an ally, it cares about |
| --- | --- | --- | --- |
| **Orange slime** | kindness, jokes, peace | cruelty, killing slimes, being called gross | a gentle party that makes friends instead of killing |
| **Huge brown goblin** | gold, fighting, being called strong | being bossed, insults, cheap offers | loot and victories; hates giving gold away and running |
| **Yellow dragon** | flattery, courage, treasure, wit | rudeness, cowardice, cheap tribute | bold wins; disgusted by fleeing and cruelty |
| **Snake person** | clever bargains, secrets, compliments on its scales | being rushed, clumsy lies, loud brutes | cunning deals and promises kept; hates pointless brutality |
| **Rock entity** | patience, quiet, respect for old things | being hurried, noise, greed | a calm, steady party; hates waste, greed and panicked running |
| **Bandit** (human) | gold, a fair cut, clever tricks | being looked down on, cheapskates | profit and fair shares; hates gold given to monsters |

Their lines, tastes and stats are in `src/rules/species.gd` and `src/rules/dnd.gd`. Any monster (except a champion) has a **15% chance to be shiny**: drawn in metallic gold with twinkling glints. Shinies are tougher (+30% HP, +1 AC, +1 to hit, saves and special DC, +10% damage) and worth double gold and 1.5× XP. They know they're rare and are proud of it. **Recruit one and you get a Shiny Roll of Fate** after the fight: a normal-strength boon, on top of the one you get for the stairs. A recruited shiny keeps its stronger stats. Talking well to an ally earns a species buff for the next fight: slime BOUNCY, goblin PUMPED, dragon STORMING, snake VENOMOUS, rock BULWARK, bandit SNEAKY.

So allies conflict with each other. Killing a monster that was pleading pleases a goblin and upsets a slime.

## Genre Halls: Undertale-style battles

Genre Halls is the next version of the fights, built on the same renderer, monster art, species, feelings and synth. The main menu starts it (`godot --path .`, the exported builds, the web page); **New Game** or **Continue** opens it. The original Donjon is behind `-- main`; from the original Donjon, **G** on its title card or the `genre-halls` flag comes back. It needs no key.

- **One floor, five fights.** Walking is the 3D set drawn as lines (the camera glides from cell to cell, torches light the walls); the monsters you can see stand in their cells with their genre over their heads, and a fight cuts to the flat battle screen. A 13×13 maze holds one slime, bandit, snake person and rock entity, plus a red dragon champion in the 5×5 hall at the center. Monsters are drawn down the corridor when you can see them, straight ahead or diagonal down a side opening, and show on the automap.
- **One box, one rule: lit squares hurt.** When a monster attacks, you dodge on a 7×7 grid with the arrow keys (or WASD). Every faction attacks in its own genre. Slimes rain goo, and the shadow of each drop shows where it will land. Bandits play chess: a rook lights its row and column, a bishop its diagonals, a knight its L-jumps. Snake people swing a lantern around the box, and you hide in a pillar's shadow. Rock entities stomp on the beat, with each pattern shown two beats ahead. The champion changes genre every turn.
- **FIGHT, ACT, SPARE, FLEE.** FIGHT is a timing bar: strike when the line crosses the middle. ACT gives CHECK, three acts for that species (a slime likes jokes, a bandit a fair cut, a rock quiet), and SAY SOMETHING, a typed line once per fight. SPARE works when the monster's mercy odds are 50% or more. Champions can't be fled.
- **The mind.** Each act asks the same kinds of question the main game asks Jev: how it feels (a choice over the ten feelings in `src/rules/emotions.gd`), whether it accepts mercy (yes/no), and how hard it attacks (a 0–3 score). Here a local stand-in answers them from the species' tastes, two rolled traits and its friendliness, anger and fear. In a new run, at least one of those traits gives each monster an individual need: a lonely slime notices company, a curious slime studies questions, and a jumpy bandit may shrink from a threat that makes a proud bandit fight harder. CHECK and the monster tooltip show behavioral clues before you act, without naming a winning choice. A fitting action changes its feeling, emotional meters, mercy and recruitment odds, and sometimes the intensity of the next dodge. Typed words are read by keyword cues and a nonsense detector. Hover the monster in a fight to see its mind: what it seems like, its friendliness, anger and fear, and the last two answers with their odds. As in the main game, any feeling at 15% or more can happen.
- **Questions and bargains.** A typed question uses your one message for that fight and a combat turn. Ask for the stairs to learn the first walkable direction from your position, for another living monster to learn an aversion and a behavioral clue, or for the champion's opening genres. These facts come from the current floor and monster state; they do not name a guaranteed action. Curious and observant monsters answer more often, while guarded ones may refuse; even a cooperative monster can decline. You start with 8 gold, shown beside HP. A bandit's fair cut or a snake's bargain, whether chosen in ACT or offered in words, costs 6 gold only if accepted and ends that fight without recruiting it. A refusal keeps your gold but uses a turn and can lead to another attack. Anger and personality shift the acceptance odds; no bargain is certain. The purse cannot pay both monsters on one floor, and older saves receive 8 gold. Fighting, ordinary ACT, SPARE and FLEE remain available.
- **Allies are charms.** A spared monster may ask to join, up to three. Each ally gives a passive charm: BOUNCY absorbs the first hit, KEEN EYE keeps warnings lit longer, SLIPPERY lengthens your safety after a hit, STEADY slows the strike bar, and HOARD-FIRE adds 4 damage. Allies judge what you do (killing a monster that was ready to stop, fleeing, insults) and walk out when their loyalty runs low.
- **The screen is one frame that fills the window**, with as little text as possible. Top line: where you are and your route. Under the view, the text box: an HP bar, the log (three lines), and the commands, at a fixed height so the view never changes size. The automap sits in the view's corner while you explore (hover it for the monster colors) and steps aside in a fight; allies are small chips in the view's bottom-left corner (red when about to leave). Explanations are tooltips: hover a command for what it does (SPARE turns gold when it would work, and its tooltip explains allies and charms), an ally for its charm and loyalty, the monster for its mind. With the keys, the highlighted command shows its tooltip too.
- **Routes.** The stairs name how you played: ghost (met no one), quiet (killed no one), blood (spared no one) or tangled.
- **Saves.** A run is one floor. It is autosaved whenever you are back to walking (the floor's start, after a fight, after backing away), and the pause menu saves into six slots while you walk; a fight in progress isn't saved, so loading puts you in the corridor before it. **Continue** loads the newest save. Saves are files in `user://saves/` (IndexedDB on the web), one per slot; the Save Manager copies, renames and deletes them.

The rules (factions, floor, mind, word reading, box geometry) are in `src/genre/genre_rules.gd`, with no UI, and are tested in `tests/genre/`. Drawing and input are in `src/genre/genre_halls.gd`. The `meet=<species>` flag jumps straight into that faction's fight.

## How Jev runs it

**Each combat round:** one Jev request (`src/jev/enemy.gd`; from a handful to about two dozen questions per monster, depending on what you just did):
- It reads your message: threat, insult, kindness 0–3, joke, offers gold, asks it to join, asks for peace.
- It picks an action from the feasible set and a target from the living party members.
- It also picks one line per possible action from that species' approved lines in `src/rules/species.gd`, so whatever action survives the rules already has a line.
- Whenever joining is possible (you recruited it, your words invite it, or it's warm enough to ask): whether it wants to say yes, plus its main reason to say yes **and** its main reason to say no (both asked at once, since Jev answers in parallel).

**Code owns the rules:**
- Your words move the monster's friendliness, anger and fear, using per-species weights.
- A monster can only join once it's friendly enough (the slime's bar is lower than the dragon's) and calm enough. The answer to an invitation is settled from its mood *after* this round's pitch, words and feeling, plus Jev's yes/no; code then keeps the reason that matches the outcome (an angry refusal always gets an angry reason). Feeling offended, enraged or confused that same round rules out a yes. A monster that likes you and says no declines instead of attacking.
- Tribute must meet the monster's minimum. Code describes the offer in words ("a generous offer") because Jev compares words better than numbers. A refusal says whether the offer was too small, it's too angry, or it can't be bought.
- An angry monster can't just walk away.
- `src/rules/narrate.gd` turns all of this into the log: species body language, and the reason behind an answer. It never shows a number.

**After each encounter:** one request (`src/jev/allies.gd`) scores how each ally feels about what happened, from 0 to 4, by its own values, and picks the moment it reacted to most. Code turns the score into loyalty and picks the reaction line Jev liked best *among the lines that match the score*, so a disapproving ally never cheers (ally talks and vows, in `src/jev/bonds.gd`, do the same). Allies below 45 loyalty are also asked whether they stay, leave or turn on you. Code only allows leaving below 30 and betrayal below 15. A betrayer becomes an enemy that remembers why.
