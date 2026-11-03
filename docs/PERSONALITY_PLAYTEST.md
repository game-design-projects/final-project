# Monster personality playtest

Run the seeded personality slice with Godot 4.7.2 (the flag skips the menu and starts at once):

```bash
godot --path . -- personality-slice seed=7042 nosound
```

The run starts with two bandits, ROOK and VEX, in consecutive encounters. CHECK is free; the foe tooltip also shows each clue. Both begin with the same meters, 12 gold is available, and the slice fixes the negotiation and answer roll at 0.5. Other combat and mercy rolls use the seed, so repeat the same actions to reproduce a branch. The slice does not autosave. After the second encounter, or after fleeing, the fixed interaction roll is cleared and the ordinary floor remains playable. A new floor, loading a save, or leaving the scene also clears it. A retry restores the encounter-start state, including HP, gold, allies, and the monster’s personality and meters. Manual saves contain the floor state but not the temporary fixed roll or queued encounter. Without a seed the slice uses 7042.

Suggested routes (restart the command for each route):

1. CHECK each bandit, then choose **ACT → OFFER A FAIR CUT** for both. ROOK takes 6 gold and leaves; VEX refuses, leaves the remaining gold in your purse, and attacks. You can still fight, spare, or flee from VEX.
2. Ask each **“Where are the stairs?”** using **ACT → SAY SOMETHING**. ROOK gives a corridor direction from the current position; VEX withholds it. Talking uses a turn, so dodge if an attack follows. After ROOK's question, use the fair cut or mercy to reach VEX.
3. Choose **SPARE** for ROOK. On this seed and route, ROOK joins as a KEEN EYE ally. Offer VEX a fair cut: ROOK objects to offering gold to another monster and loses loyalty, even if VEX refuses and you keep the coins. The ally tooltip describes its values. This is a short-term attempt to avoid a fight with a relationship cost; the existing ally system handles the judgement.

For **5–8 participants**, record the first choice at each bandit, whether they read CHECK or the tooltip, gold/HP/ally changes, and any point where the response surprised them. Let them try their own route after one of the suggested routes. Ask afterward:

- Could you tell how ROOK and VEX differed before acting? Which clue did you use?
- Did that difference change your strategy for the second bandit?
- Did you understand why each bandit accepted, refused, answered, or attacked?
- Was spending a turn to talk useful? What information changed your next decision?
- If you recruited ROOK, did its response to the later offer make sense?
- Would you want to encounter another monster with a different personality? Why?

Automated runs verify that the game plays through. They cannot establish whether the choices feel clear, fair, or enjoyable; use the participant observations for that judgement.

## Automated reproduction and survival

With Godot 4.7.2 on PATH, `godot --headless --path . -s res://tools/autoplay.gd` plays five whole games to the stairs with random choices (add `-- seed=7042 mock` for one seed with the seeded mind). It shows that a run can be finished, not that the slice is fair: standing still through attacks can kill the player, dodge movement and combat timing change the outcome, and defeating VEX at normal HP has not been established.

For a facilitated session, start a fresh command for each of 5–8 participants. Give them the controls and goal, but do not explain the personalities. Ask them to try the fair-cut route and then a route of their own, including retry if they die. Record actions, HP, gold, deaths, and their interpretation before asking the questions above. Do not coach dodge movement until after observing the first attempt; note whether they flee or defeat VEX and whether they can continue exploring.
