# Monster-initiated dialogue

Implemented on `feat/monster-initiated-dialogue`, starting with main `fcaad51`, merging PR #55 head `5bcd342`, then integrating main `8f71d21`. The newer opening film, practice floor and opt-in skill combat remain in the branch. The mood expression API is unchanged.

A monster has a reason to ask, waits for a combat decision boundary, and offers three species-specific strategies. Read its visible mood and individual behavioural clue before choosing. Responses spend one full action; Ignore immediately expires the offer and keeps the action. Custom text previews one of the same three strategies, including its cost, and requires confirmation. Unrecognised text spends nothing. Ordinary ACT → SAY SOMETHING is separate and still works.

## Play the 5–7 minute demo

```sh
godot --path . -- social-demo seed=7042 nosave no-tutorial
```

On this Mac, substitute `/Applications/Godot.app/Contents/MacOS/Godot` for `godot` if it is not on PATH. The demo starts directly, uses the local mind, gives 40 HP and 18 gold, and chains five real encounters. Ordinary combat damage and resource rules still apply. For the comparison, run the same command with `no-initiated-dialogue` appended. `classic` also disables the feature.

Suggested session, without a reading timer:

1. **PIP**, jumpy/greedy Bandit (about 1 minute): take two combat turns to hear the truce. Notice the hands/exit clue. Try calling the bluff, paying, or challenging. Check the gold counter and next attack/strike.
2. **BRASS**, proud/honest Bandit (about 1 minute): compare the same question and a different clue. Challenge or call the bluff and notice that he attacks instead of hesitating.
3. **MALLOW**, lonely/shy Slime (about 1 minute): reassure it for softer attacks, or promise no harm and follow with SPARE to see the recruitment decision. A promise ends no fight on its own.
4. **QUIVER**, frightened Slime (about 1 minute): compare the emotional cue and try rejecting it, or promise and then land a hit to see betrayal. A timed-strike miss does not count as harm.
5. **CINDER**, bored/vain Dragon champion (about 1 minute): take the trial or lower the stakes, survive its announced WALLS pattern, and check the payout. Flattery skips the attack but heals the Dragon. The challenge never clears the champion or its stairs.
6. Spend the remaining 1–2 minutes comparing choices or restarting with the feature disabled. FLEE ends the chained demo, as it does in the existing personality slice. Finish or spare each encounter to reach the next one.

Use SHOW A CLEVER TRICK against the Bandits and STAND YOUR GROUND against Cinder to reach the offers without an ordinary paid ACT truce. A Dragon soothed with flattery may no longer want a contest until you show bravery or attack.

Three normal hits leave the first four demo monsters alive after two turns. The demo guarantees the first eligible opportunity at turn 2; ordinary games use the configurable scheduler. No real-time countdown runs in the popup or custom input. Keyboard: arrows/WASD, Enter, 1–5, Esc. Mouse: click a choice; custom text has a Preview button. Esc from typing goes back to choices; Esc there ignores.

## Gameplay effects

| Species / strategy | Benefit | Cost or risk |
| --- | --- | --- |
| Bandit: pay | Guaranteed truce | Deducts 6 gold; no recruitment. Champions only pause one action. |
| Bandit: call bluff | A nervous, non-proud foe skips its attack and opens for +3 next hit | A confident/proud foe attacks harder instead. |
| Bandit: challenge | +4 next hit | Proud/confident foes attack harder immediately; nervous ones hesitate, then press harder on their next attack. |
| Slime: reassure | Two softer attacks | Uses your action; no damage or guaranteed truce. |
| Slime: promise | Holds back; non-boss SPARE is guaranteed while the promise stands | A landed timed strike or damaging skill breaks trust, restores hostility and strengthens retaliation. |
| Slime: reject | +4 next hit | Immediate stronger panic attack. |
| Snake: truth | A route computed from the actual floor, plus softer pressure | Gives it your actual record; the battle continues. |
| Snake: deny mercy | Route without admitting your record | A lie it can verify causes stronger attacks. Without evidence it cannot catch you. |
| Snake: request proof | Route and gentler next attack | Deducts 2 gold. |
| Rock: rest | Recover up to 3 HP and skip its attack | Rock recovers up to 4 HP too; your action is spent. |
| Rock: keep watch | Skip this attack, soften two later attacks, improve mercy | No damage or healing for you this action. |
| Rock: exploit | +5 next hit | A stronger attack now. |
| Dragon: trial | Survive for 8 gold and +4 next hit | Stronger WALLS attack now; death pays nothing. |
| Dragon: lower stakes | Survive for 3 gold | Still takes an attack; no opening reward. |
| Dragon: flattery | Skip its attack | Dragon heals up to 6 HP; no reward. |

Openings apply once to the next landed timed strike or damaging skill, only against that monster. Gentler attacks are counted when actual attacks occur, not when free menus open. Trial payouts are applied after the real dodge finishes and cannot repeat.

## Scheduler, memory and integration

`data/social.json` defines the event goals, speeches, choices, probability (65%), cooldown (2 turns), cost and memory bound. `rules/social.gd` evaluates species, traits, current mood/goal, feelings, HP, last resolved intent, available gold/food, clan news and previous offers. Normal eligibility begins after 2–4 resolved player actions; repeated species topics wait two extra actions. HP crossing below 35%, or threats to a jumpy monster, take priority. Opportunities are queued during action resolution and opened only by the main combat menu, after the enemy attack or held-back turn has finished. The tutorial practice encounter is excluded.

All scheduling rolls pass through the flow's Dice. `Dice.keyed` derives a draw from encounter identity and resolved turn and honours the existing pin. Waiting, typing, animation frames and other rolls do not change a scheduled draw. The original personality slice has all new features disabled as before.

There is at most one offer per encounter, with a stronger anti-farming rule: a monster that has resolved or been ignored never repeats its offer after fleeing or loading. Its last eight important interactions are structured records; promises and betrayals persist with the monster. Re-entering a fight remembers the promise in its greeting. Save fields are optional for older saves and validated before loading. Retry restores the pre-encounter monster, resources, social topic and schedule. This uses the existing walk-only save policy; it does not add mid-fight saves.

Snake evidence is deliberately narrow: a spared monster within three cells along an unobstructed row/column. It cannot use the player's invisible global tally to catch a lie. Revealed routes use the existing `Hints` pathfinder. Jev may classify an unfamiliar reply once per offer; explicit local phrases need no request. Results always map to the same three rule-owned choices, with a deterministic local fallback and no invented resources.

The `social` stage joins the existing transition table. Responses use `Encounter.after_player` once; all timed, dodge, ordinary TALK, recruitment and skill-combat stages remain in place. The popup owns speech and input while visible; the dock and old speech bubble do not duplicate it. Consequences use the existing speech box/log afterward. There is no fight-ending CONTINUE screen.

## Checks and playtest measurements

Run the suite and render the actual UI:

```sh
godot --headless --path . -s res://tools/social_test.gd -- nosave nosound
godot --path . -s res://tools/screenshots.gd -- social-demo seed=7042 nosave nosound no-tutorial out=/tmp/donjon-social-shots
```

The suite checks seeded eligibility, cooldown, urgent queuing, safe boundaries, personality branches, actual resource deductions and attack windups, Ignore, promise betrayal in both combat modes, save/load/retry, custom text preview/offline handling, feature-off/classic and mouse/focus behaviour in the gameplay scene. `tools/autoplay.gd` now handles social choices and preserves peaceful recruitment when running `pacifist`. CI and `tools/run_tests.sh` include the new suite and PR #55's mood checks.

Automated observation verifies that the popup names the initiator, shows motive/clue and action cost, offers three distinct replies plus custom/Ignore, renders without a duplicate bubble, and stays open after two simulated minutes. Screenshots cover the Bandit offer, typing, preview, consequence, Slime offer, promise consequence and compact window. These are functional/readability checks, not proof that people find the mechanic fun.

For a human comparison, alternate the enabled/disabled order between players. After each offer, ask the player to explain their reasoning without giving away the trait. Record:

| Measure | Record |
| --- | --- |
| Recognises initiator | Monster / player / unsure, before prompting |
| Infers motivation | Their words; correct / partial / unclear |
| Understands tradeoff | Predicted action/resource/attack cost before selection |
| Notices consequence | Observed gold, opening, pressure, mercy or promise effect |
| Adapts to personality | Whether BRASS changes their response after PIP, and why |
| Pacing/engagement | 1–5 rating, interruptions noticed, verbatim comment |

`social_offer` and `social_reply` events include the monster, turn, goal, validated choice, paid cost and consequence. `debug` logs them; ordinary logs also print the offered goal and resolved choice. No human sessions have been conducted as part of this implementation. Assess the 5–7 minute duration, balance and enjoyment with people before treating the initial tuning as final.

Current scope: one authored event family per species, three bounded strategies per popup, and per-monster memory within a run. Custom wording does not create a fourth mechanical solution. Recruitment uses the existing party and loyalty system; allies do not acquire a separate dialogue-memory model. There is no cross-run social reputation beyond the game's existing progression.
