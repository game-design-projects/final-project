# Monster personality playtest

Run the seeded Genre Halls slice with Godot 4.7.2:

```bash
godot --path . -- personality-slice seed=7042 nosound
```

The run starts with two bandits, ROOK and VEX, in consecutive encounters. CHECK is free; the foe tooltip also shows each clue. Both begin with the same meters, 12 gold is available, and the slice fixes the negotiation and answer roll at 0.5. Other combat and mercy rolls use the seed, so repeat the same actions to reproduce a branch. The slice does not autosave. After the second encounter, the ordinary floor remains playable.

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

Automated tests verify state changes and reachable outcomes. They cannot establish whether the choices feel clear, fair, or enjoyable; use the participant observations for that judgement.
