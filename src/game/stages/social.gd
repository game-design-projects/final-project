## The monster owns this decision. Time never expires it; one accepted answer consumes one full action.
extends "res://src/game/stages/list_stage.gd"

const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Words = preload("res://src/mind/words.gd")

func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.social_offer = Social.offer(s.foe, s)
	s.recent_social = s.foe.species
	s.social_typing = false
	s.social_note = "Replies use one combat action. Ignore keeps your action."
	s.menu = []
	for c in s.social_offer.choices:
		s.menu.append({"label": c[1], "sub": c[2]})
	s.menu.append({"label": "SAY SOMETHING ELSE", "sub": "Preview how your words will be understood before committing."})
	s.menu.append({"label": "IGNORE", "sub": "Keep your action. The offer expires."})
	flow.event("social_offer", {"who": s.foe.name, "species": s.foe.species, "turn": int(s.foe.social.rounds), "goal": s.social_offer.goal})
	print("social: %s initiates at turn %d: %s" % [s.foe.name, int(s.foe.social.rounds), s.social_offer.goal])
	s.hint = "ARROWS CHOOSE · ENTER ANSWER · ESC IGNORE"
	s.say([]) # one speech surface: the popup, with a permanent transcript in chat
	s.add_chat(s.foe.name, s.social_offer.speech)
	flow.event("shout", {"text": s.social_offer.speech, "species": s.foe.species, "boss": s.foe.boss})

func handle(flow, key: String) -> void:
	if flow.state.social_typing:
		if key == "cancel":
			flow.state.social_typing = false
		return
	# Popup rows always use linear navigation, independently of command grid settings.
	if key in ["up", "down", "left", "right"]:
		flow.state.selected = posmod(flow.state.selected + (-1 if key in ["up", "left"] else 1), flow.state.menu.size())
		flow.event("menu_move")
		return
	await super.handle(flow, key)

func pick(flow, index: int) -> void:
	var s = flow.state
	if index == 3:
		s.social_typing = true
		s.social_note = "Enter previews a matching choice; confirm that choice to spend your action."
		return
	if index == 4:
		await cancel(flow)
		return
	if index < 0 or index >= 3:
		return
	var result := Social.resolve(s.foe, s, s.social_offer, str(s.social_offer.choices[index][0]))
	if not result.ok:
		s.social_note = result.text
		return
	var choice: String = s.social_offer.choices[index][0]
	flow.event("social_reply", {"who": s.foe.name, "choice": choice, "cost": Social.cost(choice), "outcome": result.text})
	print("social: %s <- %s (cost %d): %s" % [s.foe.name, choice, Social.cost(choice), result.text])
	s.add_chat("YOU", str(s.social_offer.choices[index][1]))
	s.social_offer = {}
	s.social_typing = false
	flow.encounter.judge(result.intent)
	flow.event("mood", {"tone": "good" if result.pacified else "odd"})
	if result.end:
		await flow.encounter.defeat(s.foe, "spared", false, result.text)
		return
	var pressure: float = await flow.mind.pressure(s.foe)
	await flow.encounter.after_player([State.speech(s.foe.name, result.text)], {"pressure": pressure, "pacified": result.pacified}, false)

func cancel(flow) -> void:
	if flow.state.social_typing:
		flow.state.social_typing = false
		return
	var s = flow.state
	Social.ignore(s.foe)
	flow.event("social_reply", {"who": s.foe.name, "choice": "ignore", "cost": 0, "outcome": "Offer expired; player keeps action."})
	s.social_offer = {}
	s.say([State.sys_line("%s lowers the offer. You keep your action; the offer has expired." % s.foe.name)])
	await flow.go("menu")

func submit(flow, raw: String) -> void:
	var s = flow.state
	if not s.social_typing:
		return
	var text := raw.strip_edges().left(140)
	if text == "":
		s.social_typing = false
		return
	var id := Social.classify(s.social_offer, text, Words.read(text))
	# At most one optional mind request per offer. Explicit local intents need no network at all.
	if id == "" and not s.foe.social.get("words_asked", false):
		s.foe.social["words_asked"] = true
		s.listening = true
		var words: Dictionary = await flow.mind.read_words(text)
		s.listening = false
		id = Social.classify(s.social_offer, text, words)
	if id == "":
		s.social_note = "Not understood. Try another wording or choose a response; no action spent."
		return
	for i in s.social_offer.choices.size():
		if s.social_offer.choices[i][0] == id:
			s.selected = i
			s.social_typing = false
			s.social_note = "Heard as %s. Enter confirms; arrows change your choice. Same costs apply." % s.menu[i].label
			return

func leave(flow) -> void:
	flow.state.social_typing = false
