## Bounded social combat rules. No view or network: only validated choices can change the game.
## The scheduler's draws use Dice with a seed derived from the encounter and resolved turn, so reading time never matters.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Dice = preload("res://src/utils/dice.gd")
const Odds = preload("res://src/rules/odds.gd")
const Moods = preload("res://src/rules/moods.gd")
const Hints = preload("res://src/rules/hints.gd")

static func table() -> Dictionary:
	return Content.table("social")


## A line of data/social.json's `lines`.
static func line(id: String) -> String:
	return str(table().lines[id])


## What `m` says on meeting you again about a promise you made it, or "".
static func remembered(m) -> String:
	if m.social.get("betrayed", false):
		return line("remembered_betrayal")
	if m.social.get("promise", false):
		return line("remembered_promise")
	return ""


## Whether a promise you made `m` still stands, so it accepts mercy (never a champion).
static func promised(m) -> bool:
	return m.social.get("promise", false) and not m.social.get("betrayed", false) and not m.boss

static func begin(m, s, dice: Dice) -> void:
	var used: bool = m.social.get("used", false)
	var history: Array = m.social.get("history", [])
	var promise: bool = m.social.get("promise", false)
	var betrayed: bool = m.social.get("betrayed", false)
	var seed_id := "%d:%d:%s:%s" % [s.run_seed, s.depth, m.name, m.cell]
	m.social = {"used": used, "history": history, "promise": promise, "betrayed": betrayed,
		"rounds": 0, "due": 2 + int(dice.keyed(absi(seed_id.hash())) * 3), "checked": -1, "pending": false,
		"seed": absi(seed_id.hash()), "was_low": m.hp_fraction() < 0.35, "pressure": 0.0,
		"soft_turns": 0, "opening": 0, "trial": 0}
	if s.recent_social == m.species:
		m.social.due = int(m.social.due) + int(table().cooldown)

## Context supplies the reason; the roll only decides whether to voice it now.
static func eligible(m, s) -> bool:
	if m.is_gone() or m.social.get("used", false) or s.practice:
		return false
	var goal := str(m.mood.get("goal", ""))
	match m.species:
		"bandit": return s.gold >= int(table().cost) or m.has_trait("jumpy") or m.has_trait("proud") or int(m.heard.get("standing", 0)) < -10 or m.hp_fraction() < 0.5 or goal in ["earn gold", "escape danger"]
		"slime": return m.meters.fear >= 25 or m.has_trait("shy") or m.has_trait("lonely") or s.items.has("ration") or m.meters.friendliness >= 20 or goal == "companionship"
		"snake": return m.has_trait("secretive") or m.has_trait("curious about humans") or not s.deeds.is_empty() or goal == "learn a secret"
		"rock": return m.last_intent == "fight" or m.meters.anger >= 30 or goal == "quiet"
		"dragon": return m.has_trait("proud") or m.last_intent in ["fight", "courage"] or goal in ["find a worthy rival", "prove superiority"]
	return false

## Once per resolved action, never from tick. Urgent changes queue early, but still open only in the command menu.
static func observe(m, s, dice: Dice, chance := -1.0) -> void:
	var r: int = int(m.social.get("rounds", 0)) + 1
	m.social["rounds"] = r
	if not eligible(m, s) or m.social.get("pending", false):
		return
	var low: bool = m.hp_fraction() < 0.35
	var urgent: bool = low and not m.social.get("was_low", false)
	m.social["was_low"] = low
	urgent = urgent or (m.last_intent in ["threat", "insult"] and m.has_trait("jumpy"))
	if not urgent and r < int(m.social.due):
		return
	if int(m.social.get("checked", -1)) == r:
		return
	m.social.checked = r
	m.social.due = r + int(table().cooldown)
	var probability: float = float(table().chance) if chance < 0.0 else clampf(chance, 0.0, 1.0)
	if urgent or dice.keyed(int(m.social.seed) + r * 7919) < probability:
		m.social.pending = true

static func ready(m, s) -> bool:
	return s.stage == "menu" and m.social.get("pending", false) and not m.social.get("used", false) and not m.is_gone()

static func offer(m, s) -> Dictionary:
	var e: Dictionary = table().events.get(m.species, {}).duplicate(true)
	if e.is_empty():
		return {}
	e["id"] = m.species
	e["cue"] = visible_cue(m)
	if e.has("afraid") and (m.meters.fear >= 45 or m.hp_fraction() < 0.35):
		e.goal = e.afraid.goal
		e.speech = e.afraid.speech
	if e.has("warned") and int(m.heard.get("standing", 0)) < -10:
		e.speech = e.warned
	e.erase("afraid")
	e.erase("warned")
	if m.species == "snake":
		# Direct sight only: not the player's invisible global tally. Freeze its knowledge with the question.
		e["witness"] = s.floor_map.monsters.any(func(o): return o != m and o.gone == "spared" and _witnessed(s.floor_map, m.cell, o.cell))
	if m.social.get("betrayed", false):
		e.speech = line("broke_word") + " " + str(e.speech)
	return e

static func _witnessed(floor_map, from: Vector2i, to: Vector2i) -> bool:
	if from.x != to.x and from.y != to.y:
		return false
	var distance := absi(to.x - from.x) + absi(to.y - from.y)
	if distance > 3:
		return false
	var direction := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	for i in range(1, distance):
		if not floor_map.is_open(from + direction * i):
			return false
	return true

static func visible_cue(m) -> String:
	var mood := Moods.of(m).to_upper()
	if m.mood.get("id", "") in ["watchful", "confident", "calm"]:
		mood += " / " + str(m.mood.id).to_upper()
	var clues: Array = m.clues()
	return "%s · %s" % [mood, str(clues[0]) if not clues.is_empty() else str(table().events[m.species].goal)]

static func cost(id: String) -> int:
	return int(table().cost) if id == "pay" else (2 if id == "proof" else 0)

static func remember(m, choice: String, outcome: String) -> void:
	var history: Array = m.social.get("history", [])
	history.append({"choice": choice, "outcome": outcome, "turn": int(m.social.get("rounds", 0)), "goal": str(m.mood.get("goal", table().events.get(m.species, {}).get("goal", "")))})
	m.social.history = history.slice(-int(table().memory_max))

static func ignore(m) -> void:
	m.social.used = true
	m.social.pending = false
	remember(m, "ignore", "offer expired")

## {ok, text, pacified, end, intent}. Effects survive until consumed by the real combat paths.
static func resolve(m, s, e: Dictionary, id: String) -> Dictionary:
	if m.social.get("used", false) or (e.get("id", "") != m.species or not table().events.get(m.species, {}).get("choices", []).any(func(c): return c[0] == id)):
		return {"ok": false, "text": "That offer has expired."}
	if s.gold < cost(id):
		return {"ok": false, "text": "You need %d gold. Choose another reply or Ignore." % cost(id)}
	s.gold -= cost(id)
	m.social.used = true
	m.social.pending = false
	var out := {"ok": true, "text": "", "pacified": false, "end": false, "intent": "peace"}
	var nervous: bool = m.has_trait("jumpy") or m.meters.fear >= 55 or m.mood.get("id", "") == "watchful"
	var proud: bool = (m.has_trait("proud") and m.meters.anger >= 20) or m.mood.get("id", "") == "confident"
	match id:
		"pay":
			out.end = not m.boss
			out.pacified = true
			out.intent = "gold"
			out.text = "Six gold. Deal. My blade stays down." if not m.boss else "Six gold buys one breath. I still guard these stairs."
		"bluff":
			out.intent = "threat"
			out.pacified = nervous and not proud
			m.social.pressure = 0.9 if not out.pacified else 0.0
			m.social.opening = 3 if out.pacified else 0
			out.text = "You saw my hands shake. One free breath; my guard is open (+3 next hit)." if out.pacified else "A bluff? Watch closely. My next attack is stronger."
		"challenge":
			out.intent = "threat"
			out.pacified = nervous and not proud
			m.social.opening = 4
			m.social.pressure = 1.1 if proud else 0.35
			out.text = "Keep back! My guard slips (+4 next hit); I hesitate this turn." if out.pacified else "Then face me! My guard opens (+4 next hit), but I strike harder."
		"comfort":
			out.intent = "kindness"
			m.social.soft_turns = 2
			out.text = "Stay where I can see you. My next two attacks will be gentler."
		"promise":
			out.intent = "peace"
			out.pacified = not m.social.get("betrayed", false)
			m.social.promise = true
			m.meters.friendliness = minf(100.0, m.threshold + 24.0)
			m.meters.anger = 0.0 if out.pacified else 45.0
			out.text = "I believe you. I will hold back; you can offer SPARE. Hurt me and I will remember." if out.pacified else "You promised before. Prove it this time. I am still watching your weapon."
		"reject":
			out.intent = "insult"
			m.social.opening = 4
			m.social.pressure = 0.9
			out.text = "Oh. You too. My guard slips (+4 next hit), but my panic makes this attack stronger."
		"truth", "lie":
			var spared: bool = s.floor_map.monsters.any(func(o): return o.gone == "spared")
			var caught: bool = id == "lie" and spared and e.get("witness", false)
			out.intent = "insult" if caught else "question"
			m.social.pressure = 1.0 if caught else 0.3
			if caught:
				out.text = "I watched you spare my neighbour. That was a lie. My next attack is stronger."
			else:
				out.text = ("Your record is useful. " if id == "truth" else "I cannot verify that. Take the route, but I remain wary. ") + Hints.answer(s.floor_map, s.cell, m, "where are the stairs").trim_prefix("...")
				if id == "truth":
					m.social.soft_turns = 2 if spared else 1
		"proof":
			out.intent = "gold"
			m.social.soft_turns = 1
			out.text = "Two gold for a verifiable route. " + Hints.answer(s.floor_map, s.cell, m, "where are the stairs").trim_prefix("...")
		"wait":
			var healed: int = mini(3, s.max_hp - s.hp)
			var rested: int = mini(4, m.max_hp - m.hp)
			s.hp += healed
			m.hp += rested
			out.pacified = true
			out.text = "A quiet breath. You recover %d HP; I recover %d HP. No attack this turn." % [healed, rested]
		"respect":
			m.social.soft_turns = 2
			m.meters.friendliness = minf(100.0, m.meters.friendliness + 20.0)
			out.pacified = true
			out.text = "You kept watch. No attack this turn; my next two attacks soften."
		"exploit":
			out.intent = "threat"
			m.social.opening = 5
			m.social.pressure = 1.0
			out.text = "You study a crack (+5 next hit). I wake angry: this attack is stronger."
		"accept", "stakes":
			out.intent = "threat"
			m.social.trial = 8 if id == "accept" else 3
			m.social.pressure = 1.2 if id == "accept" else 0.4
			out.text = "Find the gaps in my WALLS pattern for %d gold%s. The stairs remain guarded." % [m.social.trial, " and +4 on your next hit" if id == "accept" else ""]
		"flatter":
			out.intent = "flattery"
			var healed: int = mini(6, m.max_hp - m.hp)
			m.hp += healed
			out.pacified = true
			out.text = "At last, respect. I rest this turn and recover %d HP. You earn no trial reward." % healed
	m.last_intent = out.intent
	remember(m, id, out.text)
	return out

## One hit only, and never carried to another monster. Called on landed timed strikes or damage skills.
static func strike_bonus(m) -> int:
	var bonus: int = int(m.social.get("opening", 0))
	if bonus != 0:
		m.social["opening"] = 0
	return bonus

## Breaking a promise works even when a single blow kills; it cannot be undone by a friendly roll afterward.
static func hit(m) -> String:
	if not m.social.get("promise", false):
		return ""
	m.social.promise = false
	m.social.betrayed = true
	m.social.soft_turns = 0
	m.social.pressure = 1.2
	m.meters.friendliness = 0.0
	m.meters.anger = 85.0
	m.mood["id"] = "watchful"
	m.mood["goal"] = "escape danger"
	remember(m, "betrayal", "the player broke a promise")
	return "%s recoils: You promised! Trust breaks; its next attack strengthens." % m.name

static func pressure(m, base: float) -> float:
	var extra := float(m.social.get("pressure", 0.0))
	m.social["pressure"] = 0.0
	if int(m.social.get("soft_turns", 0)) > 0:
		extra -= 0.8
		m.social.soft_turns = int(m.social.soft_turns) - 1
	return clampf(base + extra, 0.0, 4.2)

static func trial_over(m, s) -> String:
	var reward: int = int(m.social.get("trial", 0))
	if reward == 0:
		return ""
	m.social.trial = 0
	s.gold += reward
	m.social.opening = 4 if reward == 8 else 0
	remember(m, "trial won", str(reward))
	return "%s honours the trial: +%d gold%s. The champion still guards the stairs." % [m.name, reward, "; +4 next hit" if reward == 8 else ""]

## Reuse the mind's existing intents. Contextual phrases refine them into exactly the same paid/limited choices.
static func classify(e: Dictionary, text: String, words: Dictionary) -> String:
	var t := text.to_lower()
	var patterns := {
		"pay": "\\b(pay|coins?|gold|money|deal|counteroffer)\\b",
		"bluff": "\\b(bluff(?:ing)?|pretend(?:ing)?|fak(?:e|ing)|afraid|scared)\\b",
		"challenge": "\\b(dare|challenge|fight|coward|brave|prove)\\b",
		"promise": "\\b(promise|swear|vow|stay|never hurt|no harm|won.t hurt|will not hurt|put.*weapon down)\\b",
		"reject": "\\b(leave|alone|no|go away|reject)\\b",
		"comfort": "\\b(safe|friend|okay|comfort|together|worry|play)\\b",
		"lie": "\\b(no one|nobody|never|lie|none)\\b",
		"truth": "\\b(truth|yes|spared|mercy|honest)\\b",
		"proof": "\\b(proof|prove|evidence|partial)\\b",
		"wait": "\\b(wait|rest|recover|sleep)\\b",
		"respect": "\\b(quiet|respect|silence|watch)\\b",
		"exploit": "\\b(exploit|crack|hit|attack|provoke)\\b",
		"accept": "\\b(accept|yes|brave|ready|challenge|insult|coward)\\b",
		"stakes": "\\b(negotiate|less|lower|stakes|smaller)\\b",
		"flatter": "\\b(praise|mighty|great|flatter|refuse|no)\\b",
	}
	# Explicit social language takes precedence over a broad ordinary TALK intent.
	var order: Array = {"bandit": ["bluff", "challenge", "pay"], "slime": ["promise", "reject", "comfort"], "snake": ["proof", "lie", "truth"], "rock": ["exploit", "wait", "respect"], "dragon": ["stakes", "flatter", "accept"]}.get(e.id, [])
	for id in order:
		if RegEx.create_from_string(patterns.get(id, "a^")).search(t) != null:
			return str(id)
	var top := Odds.top(words)
	var maps := {"bandit": {"gold": "pay", "threat": "challenge", "insult": "challenge"},
		"slime": {"kindness": "comfort", "peace": "promise", "insult": "reject", "joke": "comfort"},
		"snake": {"question": "proof", "peace": "truth"},
		"rock": {"peace": "respect", "kindness": "wait", "threat": "exploit"},
		"dragon": {"threat": "accept", "flattery": "flatter", "peace": "stakes"}}
	return str(maps.get(e.id, {}).get(top, ""))
