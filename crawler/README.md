# Donjon

A Wizardry-style wireframe dungeon crawler with roguelike runs. You can talk to the monsters, SMT-style. Every enemy decision comes from **Jev**: what your words meant, whether it fights, flees, haggles or joins you, who it attacks, and what it says. Monsters you befriend join the party. They judge what you do and may walk out, or turn on you, mid-run.

```bash
npm run crawler              # http://localhost:5174
npm run crawler:scenarios    # scripted encounters against the live API
```

The key comes from the project's `.env` (`TYPESAFE_API_KEY`) and stays on the server.

## Publishing on itch.io

itch.io only hosts static files, so the key can't go in the zip (anyone could open the files and take it). Instead, a small **Cloudflare Worker** (free tier) holds the key. The zip only knows the Worker's address.

**It's live** at `https://halls-of-jev-api.donjonjev.workers.dev` (the Worker keeps the game's old name, so this address stays the same). The game has no password, so anyone who plays (or finds that address) uses your TypeSafe credits. Watch your usage on the TypeSafe dashboard.

```bash
cd crawler/proxy
npx wrangler login                        # opens your browser to sign in to Cloudflare
npx wrangler secret put TYPESAFE_API_KEY  # paste your TypeSafe key
npx wrangler deploy                       # prints https://halls-of-jev-api.<you>.workers.dev
cd ../..
npm run crawler:itch -- https://halls-of-jev-api.<you>.workers.dev
```

**CI publishes automatically.** `.github/workflows/ci.yml` runs `npm test` and builds and validates the itch bundle on every push and pull request; every push to `main` that passes is pushed with butler to https://aalfalasi.itch.io/donjon (channel `html5`, version = the commit SHA). It needs the `BUTLER_API_KEY` repository secret, and pull requests never see it.

To upload by hand instead, upload `dist/donjon-itch.zip` to itch.io as an **HTML** project and tick "This file will be played in the browser". An embed size of about 1180 × 820 fits the game plus the Jev panel; enable the fullscreen button too.

- The Worker runs the same code as the local server (`crawler/src/api.js`), so the monsters behave identically.
- To test the itch build locally: `node crawler/proxy/dev.js` (Worker on port 5175), then `npm run crawler:itch -- http://localhost:5175` and serve `dist/donjon` from any static server.
- To take the game offline, remove the key (`npx wrangler secret delete TYPESAFE_API_KEY` in `crawler/proxy`) or delete the Worker in the Cloudflare dashboard.

## Playing

| Where | Keys |
| --- | --- |
| Exploring | ↑/W forward · ↓/S back · ←/A and →/D turn · **C** camp (long rest; may be ambushed) · **E** talk to an ally · **V** make a vow to an ally · **B** boons · **M** map |
| Combat | **F** fight (everyone uses their default) · **C** cast: choose each adventurer's action, spell or skill · **T** talk (everyone hears) · **R** recruit the target · **G** give gold · **V** vow to the target · **E** escape · **1–3** pick target |
| Anywhere | **J** Jev mind panel · **P** music on/off · **O** sound effects on/off · **H** tips off / back on from the start |

**Tips.** New players get one short hint at a time, the first time each thing matters: how to walk, the automap, the stairs, your first fight (and that you can talk), targeting, feelings, a monster warming to you, your first ally, camping when hurt, levelling up, someone going down, a champion's floor. Each shows once, in a framed note over the bottom of the view, and lights up what it talks about (the keys' buttons, the map, the party). It never blocks anything: your next key does its job and clears the hint, and a key that does nothing nudges it instead. **H** turns tips off; **H** again turns them back on from the start. Seen tips are remembered in `localStorage` (`hallsOfJev.tipsSeen`, `hallsOfJev.tipsOff`). The hints and their wording live in `public/tutorial.js`.

### D&D-style combat

The rules follow D&D 5e, simplified (`public/dnd.js`). Every roll is shown in the log, e.g. `HORTENSE ATTACKS KRUNK: D20 13/16 ADV→16+5=21 VS AC 12. HIT! 7 DAMAGE.`

- **The party:** HORTENSE is a fighter (longsword, AC 16, Second Wind and Action Surge once per rest, a second attack at level 5). ROLF is a cleric (mace, healing and holy spells). EUGENE is a wizard (Fire Bolt and attack spells). Each has ability modifiers; hover a party row to see them.
- **Initiative:** each fight opens with a d20 roll for each side. Whoever wins acts first.
- **Attacks:** d20 + proficiency + ability against the target's armor class. A natural 20 is a critical hit and rolls the damage dice twice; a natural 1 always misses.
- **Advantage:** roll two d20s and keep the higher. You get it against monsters that are asleep, paralyzed, glowing from Guiding Bolt, or off guard from flattery. Disadvantage (keep the lower) comes from being poisoned or restrained, or attacking a monster that is dodging.
- **Spells use slots** on the 5e table (2 first-circle slots at level 1, up to third-circle spells at level 5). Cantrips are free and roll a second die from level 5. Camping restores slots.
  - Wizard: Fire Bolt, Magic Missile, Burning Hands, Sleep, Scorching Ray, Hold Monster, Fireball.
  - Cleric: Sacred Flame, Cure Wounds, Bless, Guiding Bolt, Prayer of Healing, Revivify, Spirit Guardians.
- **Saving throws:** area spells, Hold Monster and monster specials call for a save against a DC; a success halves the damage or avoids the effect. From B3F, monster specials also poison, entangle (restrained) or knock down (prone, losing your next action).
- **Death saves:** at 0 HP a member falls unconscious instead of dying. At the start of each of your turns they roll a d20: 10+ is a success and below 10 a failure. Three successes stabilize them, three failures kill them, and a natural 20 brings them back with 1 HP. Any healing gets them up, and after a fight they come to with 1 HP. The dead can be brought back with Revivify, in a fight or while camping.
- **Monster allies** act on their own each round: an attack, or their species' special every few rounds.

### Talking always matters

- **Charisma checks:** when you talk, your best talker rolls Charisma. A strong roll makes your words land harder (up to ×2 on a natural 20); a natural 1 halves them.
- **Feelings:** every time you talk to monsters, pay them, or ask them to join, Jev picks how each one **feels**, and code gives every feeling a visible effect (`public/emotions.js`):

  | Feeling | Effect |
  | --- | --- |
  | DELIGHTED | won't attack this round |
  | IN STITCHES | too busy laughing to fight |
  | TOUCHED | its heart opens; if it likes you enough, it asks to join |
  | FLATTERED | lowers its guard: you get advantage against it |
  | INTRIGUED | lets slip a weak spot: +2 to hit it for the rest of the fight |
  | CONFUSED | loses its turn |
  | SADDENED | disadvantage on its attacks |
  | OFFENDED | +2 damage against you |
  | ENRAGED | advantage and +3 damage, but reckless (AC −3) |
  | TERRIFIED | disadvantage on attacks, and it drops gold |

  Each feeling also moves its friendliness, anger or fear, and the log shows by how much.
- **Recruit (R):** ask your target to join, with or without words. Your talker rolls Persuasion against a DC set by how much it likes you, how angry it is, and whether it is losing. The result (irresistible, convincing, close, clumsy or disastrous) shifts its mood before it answers. Winning a monster over, or letting it leave in peace, gives half its XP.
- **Ally talks (E)** always have a result, by how your words land (0–4): it sulks and sits out the next fight, gets distracted (−2 to hit), feels steady (+1 to hit), gets its species buff, or is inspired (buff, full heal and a level).

### Floors and champions

- **Complexity grows as you descend.** B1F is a small maze with lone slimes and goblins. B2F brings pairs, bandits and snake people; B3F groups of three, rock entities, and specials that inflict conditions; B4F dragons and wider halls; B6F veteran monsters. Each new rule is announced when you arrive.
- **Every 5th floor** has a 5×5 hall at its heart with a **red champion** in the middle, marked red on your map and visible down the corridor. It is a normal monster of its kind but far harder: about 2× the HP, two attacks a turn, a faster special, better saves, and Legendary Resistance against the first two Sleep or Hold spells. You can still talk to it and recruit it, though it takes more to impress.
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
- **Floors:** each one gets a random color theme (Bone Crypt, Blood Vault, Frost Warrens and others). Walls carry torches that flicker and glow, chains, banners, barred windows, skull niches and cracks. Placement is seeded per floor, so decorations stay put as you move.
- **Sound effects** (`public/sfx.js`) are synthesized live, with no sound files: hits, crits, misses, kills, spells, heals, dice, feelings, joins, level-ups, and the Roll of Fate's ticking spin and landing fanfare.

### Groups, ally talks and vows

- **Groups.** You can meet 1–3 monsters at once, possibly of different species, and one Jev request decides all their moves each round. Monsters see which side the others are on. When one warms to the party, the rest hear it "sided with the party against them", and a hostile monster may club the turncoat. A friendly monster that gets attacked by its own group may flee. Code only lets a monster turn on another when they're on opposite sides or one hit the other.
- **Rolled on Jev's odds.** Monsters don't always take Jev's top choice. Any action at 15% or more can happen, in proportion to its probability. Jev's probabilities are calibrated, so a 20% "turn on the traitor" really happens about one time in five.
- **Talking to allies (E).** Each ally hears you once per floor. If your words land well (3+ out of 4), it gets a buff for the next fight: goblin **PUMPED** (double damage), slime **BOUNCY** (absorbs a hit), dragon **STORMING** (free lightning on every enemy), and so on. Worse results have consequences too (see above).
- **Vows (V).** Build a promise from menus: *I WILL / I WON'T* → *KILL / TALK TO / GIVE GOLD TO / RUN FROM / BEFRIEND* → *SLIMES / GOBLINS / DRAGONS / MONSTERS*. Swear to an ally (once per ally per floor) or to the monster you're targeting (once per fight). Jev judges how the monster feels about the promise, which shifts friendliness or loyalty.
- **Breaking vows.** Because vows are structured, code checks them exactly against what you do (killing, sparing, talking, paying, fleeing, attacking, recruiting). A broken vow gets slashed in the ledger, and the monster you swore to responds, with Jev picking one of:
  - **forgive** (only if loyalty is still at least 35)
  - **leave the party**
  - **attack you** (a fight where you can win it back, though rejoining takes more friendliness than before)
  - **steal your gold** (60% chance to get away with 25–50% of it; otherwise you catch it)

  If you swore to a monster that's still in the fight, it gets angry instead. If the one you swore to is gone, nobody holds you to it.

Test these against the live API with `node crawler/scripts/social-scenarios.js`, or in the browser with `#debug` and `halls.meet("goblin", "slime")`, `halls.hostile("slime")`, `halls.ally("slime", "Glop")`.

**Test runs:** open http://localhost:5174/#floor5 (any number) to start on that floor with a party that got there: every member at that level, one Roll of Fate boon per floor cleared, some gold, fully rested. Add `-debug` (`#floor5-debug`) to also get the console hooks.

Floors are new mazes every time you descend. Death is permanent, and your deepest floor is remembered. Open `#debug` in the URL to get `halls.meet("dragon")` in the console.

## The monsters

| | Likes | Hates | As an ally, it cares about |
| --- | --- | --- | --- |
| **Orange slime** | kindness, jokes, peace | cruelty, killing slimes, being called gross | a gentle party that makes friends instead of killing |
| **Huge brown goblin** | gold, fighting, being called strong | being bossed, insults, cheap offers | loot and victories; hates giving gold away and running |
| **Yellow dragon** | flattery, courage, treasure, wit | rudeness, cowardice, cheap tribute | bold wins; disgusted by fleeing and cruelty |
| **Snake person** | clever bargains, secrets, compliments on its scales | being rushed, clumsy lies, loud brutes | cunning deals and promises kept; hates pointless brutality |
| **Rock entity** | patience, quiet, respect for old things | being hurried, noise, greed | a calm, steady party; hates waste, greed and panicked running |
| **Bandit** (human) | gold, a fair cut, clever tricks | being looked down on, cheapskates | profit and fair shares; hates gold given to monsters |

Any monster (except a champion) has a **15% chance to be shiny**: drawn in metallic gold with twinkling glints. Shinies are tougher (+30% HP, +1 AC, +1 to hit, saves and special DC, +10% damage) and worth double gold and 1.5× XP. They know they're rare and are proud of it. **Recruit one and you get a Shiny Roll of Fate** after the fight: a normal-strength boon, on top of the one you get for the stairs. A recruited shiny keeps its stronger stats. Talking well to an ally earns a species buff for the next fight: slime BOUNCY, goblin PUMPED, dragon STORMING, snake VENOMOUS, rock BULWARK, bandit SNEAKY.

**Dev pages** (local only, left out of the itch build): `gallery.html` shows every monster, with the jaggedness and shiny toggles (the game uses smooth lines; `ART.pixel` in `public/art.js`); `cover.html` draws the itch.io cover (saved as `assets/donjon-cover.png`, 630 × 500); `beatmaker.html` is the step sequencer whose SAVE TO GAME writes `song.json`.

So allies conflict with each other. Killing a monster that was pleading pleases a goblin and upsets a slime.

## How Jev runs it

**Each combat round:** one Jev request (`src/enemy.js`, about 10–20 questions, ~150–250 ms):
- It reads your message: threat, insult, kindness 0–3, joke, offers gold, asks it to join, asks for peace.
- It picks an action from the feasible set and a target from the living party members.
- It also picks one line per possible action from that species' approved lines in `public/species.js`, so whatever action survives the rules already has a line.

**Code owns the rules:**
- Your words move the monster's friendliness, anger and fear, using per-species weights.
- A monster can only join once it's friendly enough (the slime's bar is lower than the dragon's). The state tells Jev whether that's true yet.
- Tribute must meet the monster's minimum. Code describes the offer in words ("a generous offer") because Jev compares words better than numbers.
- An angry monster can't just walk away.
- The Jev panel shows every blocked choice.

**After each encounter:** one request (`src/allies.js`) scores how each ally feels about what happened, from 0 to 4, by its own values. Code turns that into loyalty. Allies below 45 loyalty are also asked whether they stay, leave or turn on you. Code only allows leaving below 30 and betrayal below 15. A betrayer becomes an enemy that remembers why.

## Music

**The dungeon plays `public/ambient.m4a`**, a 96-second dark ambient loop made for the game: a warm low pad drifting between minor chords a third apart (Dm, B♭m, F♯m, ending on a tense A7♭9 that falls back to Dm), a sub drone, a soft glass-bell melody with echo, a distant heartbeat thump and cave air, all in a long dark reverb. `public/ambient.js` loops it seamlessly; **P** turns it on and off.

The track is synthesised from scratch by `scripts/build-ambient.py` (Python with numpy and scipy; no samples). The chords, bell notes and mix levels are tables at the top of the script. To change it and rebuild:

```bash
python3 crawler/scripts/build-ambient.py /tmp/ambient.wav
afconvert -f m4af -d aac -b 160000 /tmp/ambient.wav crawler/public/ambient.m4a
```

**The ambient comes and goes.** It plays for a minute and a half or so, fades out, and leaves a minute or two of quiet before it drifts back, so the dungeon isn't wallpapered with it.

**Good news gets its own cue** (`scripts/build-stings.py`, in the battle loop's 8-bit voice): `fanfare.m4a`, a bright da-da-da-DAAA landing on a high D major chord, plays when you go down the stairs, followed by twenty seconds of quiet; `victory.m4a`, a quick rising arpeggio, plays when you win a fight (every foe killed, driven off, won over or let go; not when you run).

**Fights play `public/battle.m4a` instead**, a bright 25-second 8-bit loop at 152 BPM: a pulse-wave lead with a ping-pong echo, a pulse arpeggio, a triangle bass pumping octaves and noise drums, on the heroic D–C–G–A progression with a B minor bridge. When a fight starts it cuts in within a third of a second and the ambient fades out underneath (keeping its place); when the fight ends the battle loop fades and the dungeon creeps back. Each fight starts the loop from bar one. Rebuild it the same way:

```bash
python3 crawler/scripts/build-battle.py /tmp/battle.wav
afconvert -f m4af -d aac -b 160000 /tmp/battle.wav crawler/public/battle.m4a
python3 crawler/scripts/build-stings.py /tmp     # fanfare.wav and victory.wav
for n in fanfare victory; do afconvert -f m4af -d aac -b 160000 /tmp/$n.wav crawler/public/$n.m4a; done
```

The 8-bit voices (pulse, triangle, kick, noise hits) live in `scripts/chip.py`, shared by both scripts.

**The beat maker and its engine are separate now.** The dungeon no longer plays what follows; it is still there for `beatmaker.html`.

The engine (`public/music.js`) plays sampled instruments from the **MusyngKite** soundfont (CC BY-SA 3.0) and **FluidR3** (CC BY 3.0), plus **LinnDrum** drum samples (public domain), through a generated cathedral reverb. Every track can use any instrument. Credits are in `public/CREDITS.txt`, which ships in the itch zip; put the same credits on the itch.io page.

The game's theme is **Beethoven's Symphony No. 7, Allegretto, bars 3–50**: the hypnotic repeated-E theme, then the singing counter-melody over it. Every note comes from a public-domain score (Mutopia Project MIDI in `assets/`). `scripts/build-theme.js` arranges it into `public/theme.json` as layers: strings on every part, a choir doubling the violas, a dark synth pad under the cellos, a sub bass an octave below the basses, and a soft kick heartbeat. Change the `ARRANGEMENT` table (instrument, volume, octave) and rerun `node crawler/scripts/build-theme.js`. Or open the beat maker, where each score layer can be re-voiced, rebalanced or muted, and you can add your own drums and notes on top.

**Older notes:**

`public/music.js`, soundfont samples (FluidR3 GM: warm pad, synth bass, saw lead) plus a synthesized kick for the thumps. Your melody **A B C D D D E D E D C C C D D D** is kept note for note:
- It's set in A minor over **Am | F | Dm | E**.
- It's given a rhythm (the D-D-D repeats land as short-short-long), and each 4-bar phrase gets an ending (E D C B, then E D C B G#) that pulls back to A.
- The second phrase lifts to F over the F chord.
- The first four bars are just pad, bass and thumps.

Edit the `SONG` object at the top of the file: note names plus lengths in eighth notes.
