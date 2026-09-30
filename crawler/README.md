# Halls of Jev

A Wizardry-style wireframe dungeon crawler with roguelike runs. You can talk to the monsters, SMT-style. Every enemy decision comes from **Jev**: what your words meant, whether it fights, flees, haggles or joins you, who it attacks, and what it says. Monsters you befriend join the party. They judge what you do and may walk out, or turn on you, mid-run.

```bash
npm run crawler              # http://localhost:5174
npm run crawler:scenarios    # scripted encounters against the live API
```

The key comes from the project's `.env` (`TYPESAFE_API_KEY`) and stays on the server.

## Publishing on itch.io

itch.io only hosts static files, so the key can't go in the zip (anyone could open the files and take it). Instead, a small **Cloudflare Worker** (free tier) holds the key. The zip only knows the Worker's address.

**It's live** at `https://halls-of-jev-api.donjonjev.workers.dev`. The game has no password, so anyone who plays (or finds that address) uses your TypeSafe credits. Watch your usage on the TypeSafe dashboard.

```bash
cd crawler/proxy
npx wrangler login                        # opens your browser to sign in to Cloudflare
npx wrangler secret put TYPESAFE_API_KEY  # paste your TypeSafe key
npx wrangler deploy                       # prints https://halls-of-jev-api.<you>.workers.dev
cd ../..
npm run crawler:itch -- https://halls-of-jev-api.<you>.workers.dev
```

Upload `dist/halls-of-jev-itch.zip` to itch.io as an **HTML** project and tick "This file will be played in the browser". An embed size of about 1180 × 820 fits the game plus the Jev panel; enable the fullscreen button too.

- The Worker runs the same code as the local server (`crawler/src/api.js`), so the monsters behave identically.
- To test the itch build locally: `node crawler/proxy/dev.js` (Worker on port 5175), then `npm run crawler:itch -- http://localhost:5175` and serve `dist/halls-of-jev` from any static server.
- To take the game offline, remove the key (`npx wrangler secret delete TYPESAFE_API_KEY` in `crawler/proxy`) or delete the Worker in the Cloudflare dashboard.

## Playing

| Where | Keys |
| --- | --- |
| Exploring | ↑/W forward · ↓/S back · ←/A and →/D turn · **C** camp (heal; may be ambushed) · **M** map |
| Combat | **F** fight · **C** cast HALITO · **T** talk (type anything) · **G** give gold · **R** run |
| Anywhere | **J** Jev mind panel · **P** music on/off |

Floors are new mazes every time you descend. Death is permanent, and your deepest floor is remembered. Open `#debug` in the URL to get `halls.meet("dragon")` in the console.

## The monsters

| | Likes | Hates | As an ally, it cares about |
| --- | --- | --- | --- |
| **Orange slime** | kindness, jokes, peace | cruelty, killing slimes, being called gross | a gentle party that makes friends instead of killing |
| **Huge brown goblin** | gold, fighting, being called strong | being bossed, insults, cheap offers | loot and victories; hates giving gold away and running |
| **Yellow dragon** | flattery, courage, treasure, wit | rudeness, cowardice, cheap tribute | bold wins; disgusted by fleeing and cruelty |

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

`public/music.js`, soundfont samples (FluidR3 GM: warm pad, synth bass, saw lead) plus a synthesized kick for the thumps. Your melody **A B C D D D E D E D C C C D D D** is kept note for note:
- It's set in A minor over **Am | F | Dm | E**.
- It's given a rhythm (the D-D-D repeats land as short-short-long), and each 4-bar phrase gets an ending (E D C B, then E D C B G#) that pulls back to A.
- The second phrase lifts to F over the F chord.
- The first four bars are just pad, bass and thumps.

Edit the `SONG` object at the top of the file: note names plus lengths in eighth notes.
