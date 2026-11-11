# Dynamic moods

Launch an ordinary encounter with `godot --path . -- meet=bandit seed=7042 nosave nosound`.
Resolve several actions and read the log before dodging. Jumpy bandits tend to watch
the exit; proud ones challenge you. Comfort or peace can calm either after the
two-action minimum cooldown. Low HP or high fear overrides pride.

Stable traits, taste and motives remain unchanged. Temporary mood, immediate goal,
elapsed resolution count and next opportunity are stored on the monster and included
in its existing save/retry snapshot. Opportunities occur every 2–4 resolved player
actions; important actions can trigger one after two actions. CHECK, menus, typing,
pausing and animation frames do not advance this counter. Repeated states emit no
additional cue. This counts player-action resolutions, including pacified rounds,
rather than elapsed time or enemy attack completions.

Species behaviors are in data/moods.json: companionship, bargaining, questioning,
drowsiness and provocation. Cues explicitly announce bounded pressure shifts
(-0.45 to +0.3, monster pressure clamped to 0–3 before the heavy-miss penalty), with no extra turns or network calls.
Jev receives the temporary state and existing interaction memory. Local play applies
the same authoritative pressure modifier. No additional negotiation, trust or
recruitment modifier is implemented in this first slice.

Run tools/moods_test.gd and tools/rules_test.gd with
`-- nosave nosound`. Disable with no-dynamic-moods.
The unit test covers snapshot restoration, not a full interactive death/retry.
Visual readability and balance still need human playtesting.
