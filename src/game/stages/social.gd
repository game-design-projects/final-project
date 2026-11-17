## The monster owns this decision. Time never expires it; one accepted answer consumes one full action.
extends "res://src/game/stages/list_stage.gd"

const Social = preload("res://src/rules/social.gd")
const State = preload("res://src/game/state.gd")
const Talk = preload("res://src/game/stages/talk.gd")
const Words = preload("res://src/mind/words.gd")

const WORDS := -1 # what a typed line that answers none of the offer's choices is: plain words

func enter(flow, _args: Dictionary) -> void:
	var s = flow.state
	s.social_offer = Social.offer(s.foe, s)
	s.recent_social = s.foe.species
	s.social_typing = false
	s.social_heard = {}
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

func pick(flow, index: int, said := "") -> void:
	var s = flow.state
	if index == 3:
		s.social_typing = true
		s.social_heard = {}
		s.social_note = "Type a reply. Enter shows how it is heard; Enter again says it."
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
	s.add_chat("YOU", said if said != "" else str(s.social_offer.choices[index][1]))
	s.social_offer = {}
	s.social_typing = false
	s.social_heard = {}
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
		flow.state.social_heard = {}
		return
	var s = flow.state
	Social.ignore(s.foe)
	flow.event("social_reply", {"who": s.foe.name, "choice": "ignore", "cost": 0, "outcome": "Offer expired; player keeps action."})
	s.social_offer = {}
	s.say([State.sys_line("%s lowers the offer. You keep your action; the offer has expired." % s.foe.name)])
	await flow.go("menu")

## A typed reply, in two Enters: the first shows how it is heard (one of the offer's choices, or plain words that answer none of
## them), the second, on the same words, says it. Changed words are heard again. Nothing typed is ever a dead end: plain words
## close the offer and the monster reacts to them as to SAY SOMETHING, for your action.
func submit(flow, raw: String) -> void:
	var s = flow.state
	if not s.social_typing:
		return
	var text := raw.strip_edges().left(140)
	if text == "":
		s.social_typing = false
		s.social_heard = {}
		return
	if s.social_heard.get("text", null) == text:
		await _say_it(flow, text)
		return
	var words: Dictionary = Words.read(text)
	var id := Social.classify(s.social_offer, text, words)
	# At most one optional mind request per offer. Explicit local intents need no network at all.
	if id == "" and not s.foe.social.get("words_asked", false):
		s.foe.social["words_asked"] = true
		s.listening = true
		words = await flow.mind.read_words(text)
		s.listening = false
		id = Social.classify(s.social_offer, text, words)
	var choice := WORDS
	for i in s.social_offer.choices.size():
		if s.social_offer.choices[i][0] == id:
			choice = i
	s.social_heard = {"text": text, "choice": choice, "words": words}
	if choice == WORDS:
		s.social_note = "Heard as plain words, not an answer to its offer. Enter again to say it anyway: the offer ends and it costs your action. Or change the words."
	else:
		s.selected = choice
		s.social_note = "Heard as %s. Enter again to say it (same cost as the button), or change the words." % s.menu[choice].label
	print("social: '%s' heard as %s" % [text, "plain words" if choice == WORDS else id])


## The previewed line, said.
func _say_it(flow, text: String) -> void:
	var s = flow.state
	var heard: Dictionary = s.social_heard
	if heard.choice != WORDS:
		await pick(flow, int(heard.choice), text)
		if not s.social_offer.is_empty(): # it could not be done (not enough gold): back to the buttons, the reason in the note
			s.social_typing = false
			s.social_heard = {}
		return
	var m = s.foe
	m.social.used = true
	m.social.pending = false
	Social.remember(m, "words", "answered in its own words")
	flow.event("social_reply", {"who": m.name, "choice": "words", "cost": 1, "outcome": "Plain words; the offer closed."})
	print("social: %s <- plain words: %s" % [m.name, text])
	s.social_offer = {}
	s.social_typing = false
	s.social_heard = {}
	s.hint = "" # the popup is gone; the monster takes your words in, then answers as after SAY SOMETHING
	await Talk.say(flow, text, heard.words)

func leave(flow) -> void:
	flow.state.social_typing = false
