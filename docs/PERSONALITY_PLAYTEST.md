# Monster personality playtest

Run the seeded personality slice with Godot 4.7.2 (the flag skips the menu and starts at once):

```bash
godot --path . -- personality-slice seed=7042 nosound
```

The run starts with two bandits, ROOK and VEX, in consecutive encounters. CHECK is free; the foe's card (hover it or press I) also shows each clue. Both begin with the same meters, 12 gold is available, and the slice fixes every interaction roll at 0.5: the cut, the answer to a question, the feeling a hit or a question stirs, whether mercy is accepted, whether a spared monster joins, how an ally judges a deed, whether it leaves and how loyal a recruit starts. So the same actions give the same outcomes. Only the dodge patterns and the wording of lines still come from the seed (the damage of a strike follows your timing). The monsters always think with the local rules, so a saved or shipped Jev address changes nothing. The slice floor is never autosaved, even after the slice is over, so your earlier run stays in the AUTO slot. After the second encounter, or after fleeing, the fixed interaction roll is cleared and the ordinary floor remains playable. A new floor or loading a save also clears it, and so does leaving the scene: the flag starts one slice per launch, so MAIN MENU shows the real menu. A retry starts at full HP with the gold, allies, and the monster’s personality and meters the fight began with. Manual saves contain the floor state but not the temporary fixed roll or queued encounter. Without a seed (or with one that is not a whole number from 0 to 9223372036854775807, which is warned about) the slice uses 7042.

Suggested routes (restart the command for each route):

1. CHECK each bandit, then choose **ACT → OFFER A FAIR CUT** for both. ROOK takes 6 gold and leaves; VEX refuses, leaves the remaining gold in your purse, and does not attack on that turn. You can still fight, spare, or flee from VEX (on this seed, sparing him recruits him as a KEEN EYE ally).
2. Ask each **“Where are the stairs?”** using **ACT → SAY SOMETHING**. ROOK gives a corridor direction from the current position; VEX withholds it. Talking uses a turn, so dodge if an attack follows. After ROOK's question, use the fair cut or mercy to reach VEX.
3. Choose **SPARE** for ROOK. On this seed and route, ROOK joins as a KEEN EYE ally. Offer VEX a fair cut: ROOK objects to offering gold to another monster and loses loyalty, even if VEX refuses and you keep the coins. The ally tooltip describes its values. This is a short-term attempt to avoid a fight with a relationship cost; the existing ally system handles the judgement.

For **5–8 participants**, record the first choice at each bandit, whether they read CHECK or the tooltip, gold/HP/ally changes, and any point where the response surprised them. Let them try their own route after one of the suggested routes. Ask afterward:

- Could you tell how ROOK and VEX differed before acting? Which clue did you use?
- Did that difference change your strategy for the second bandit?
- Did you understand why each bandit accepted, refused, answered, or attacked?
- Was spending a turn to talk useful? What information changed your next decision?
- If you recruited ROOK, did its response to the later offer make sense?
- Would you want to encounter another monster with a different personality? Why?

`godot --headless --path . -s res://tools/slice_test.gd` plays the fair-cut route, the retry and the flee through the slice and checks what ends it, that the floor may not be autosaved, the seed and the mind. Automated runs verify that the game plays through. They cannot establish whether the choices feel clear, fair, or enjoyable; use the participant observations for that judgement.

## Automated reproduction and survival

With Godot 4.7.2 on PATH, `godot --headless --path . -s res://tools/autoplay.gd` plays five whole games to the stairs with random choices on ordinary floors, not the slice (add `-- seed=7042 mock` for one seed with the seeded mind). It shows that a run can be finished, not that the slice is fair: standing still through attacks can kill the player, dodge movement and combat timing change the outcome, and defeating VEX at normal HP has not been established.

For a facilitated session, start a fresh command for each of 5–8 participants. Give them the controls and goal, but do not explain the personalities. Ask them to try the fair-cut route and then a route of their own, including retry if they die. Record actions, HP, gold, deaths, and their interpretation before asking the questions above. Do not coach dodge movement until after observing the first attempt; note whether they flee or defeat VEX and whether they can continue exploring.
