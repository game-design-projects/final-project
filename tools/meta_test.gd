## Checks what lasts longer than a run or wears on one: achievements, the legacy between runs, going hungry, and what can be done
## about that with a friend (issue #40). Prints one line per check and exits with 1 if any failed.
##   godot --headless --path . -s res://tools/meta_test.gd -- nosave nosound
extends "res://tools/test_base.gd"

const Achievements = preload("res://src/rules/achievements.gd")
const Ally = preload("res://src/game/ally.gd")
const Clans = preload("res://src/rules/clans.gd")
const Flags = preload("res://src/utils/flags.gd")
const Flow = preload("res://src/game/flow.gd")
const FloorMap = preload("res://src/rules/floor_map.gd")
const Floors = preload("res://src/rules/floors.gd")
const Items = preload("res://src/rules/items.gd")
const Legacy = preload("res://src/rules/legacy.gd")
const LocalMind = preload("res://src/mind/local_mind.gd")
const Rng = preload("res://src/utils/rng.gd")
const State = preload("res://src/game/state.gd")
const Survival = preload("res://src/rules/survival.gd")
const Transitions = preload("res://src/game/transitions.gd")

const BASE := ["nosave", "nosound"]
const FEATURES := ["achievements", "legacy"]

# loaded when the test runs: they read the Store autoload, which a `-s` script is compiled before
var Menus
var Progress
var Store


func _name() -> String:
	return "meta_test"


func _run() -> void:
	Menus = load("res://src/menu/menus.gd")
	Progress = load("res://src/menu/progress.gd")
	Store = root.get_node("Store")
	_declared()
	await _without_them()
	await _achievements()
	await _legacy()
	_progress_store()
	await _hunger()
	await _camp()
	await _butcher()
	await _feeding()
	await _selling()
	await _saved()
	await _endings()
	_menu_pages()
	_finish()


func _use(words := []) -> void:
	var all := PackedStringArray(BASE)
	all.append_array(PackedStringArray(words))
	Flags.set_args(all)


func _flow(seed_value: int, words := []) -> Variant:
	_use(words)
	return Flow.new(Rng.new(seed_value), LocalMind.new())


func _clear_store() -> void:
	for key in [Progress.EARNED_KEY, Progress.EMBERS_KEY, Progress.RANKS_KEY, Progress.PAID_KEY]:
		Store.remove(key)


func _ally(species := "slime", who := "DRIP", loyalty := 60.0):
	return Ally.make(species, who, loyalty)


func _declared() -> void:
	_use()
	for f in FEATURES:
		_check(Flags.FEATURES.has(f), "%s is a feature" % f)
	_check(Transitions.allowed("explore", "camp") and Transitions.allowed("camp", "explore"), "you can sit down and get up")
	_check(not Transitions.allowed("menu", "camp"), "but not in the middle of a fight")
	for stage in Transitions.stages():
		_check(int(stage in Transitions.FIGHT) + int(stage in Transitions.WALK) == 1, "%s is either a fight or a walk, not both" % stage)
	for stage in Transitions.FIGHT + Transitions.WALK + Transitions.PICKING:
		_check(Transitions.ALLOWED.has(stage), "%s, named as a kind of stage, is a stage" % stage)
	_check(Transitions.PICKING.all(func(s): return s in Transitions.FIGHT), "picking a command only happens in a fight")
	for id in Achievements.ids():
		var info: Dictionary = Achievements.info(id)
		_check(str(info.label) != "" and str(info.text) != "", "%s says what it is" % id)
	for id in Legacy.boons():
		_check(Legacy.top_rank(id) > 0 and Legacy.next_cost(id, 0) > 0, "%s can be bought" % id)
		_check(not Legacy.describe(id, 1).contains("%"), "%s says what it does (%s)" % [id, Legacy.describe(id, 1)])
	_check(Items.known(Survival.RATION) and Items.known(Survival.ROAST), "the food is in the item table")


func _without_them() -> void:
	var flow = _flow(5, ["no-legacy", "no-achievements"])
	flow.legacy_ranks = {"skin": 3, "purse": 3}
	await flow.new_run()
	var s = flow.state
	_check(s.max_hp == State.new().max_hp and s.gold == State.new().gold, "no-legacy: the boons do nothing")
	flow.event("spared", {"boss": false})
	_check(flow.trophies.earned.is_empty(), "no-achievements: nothing is earned")


func _achievements() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	var heard := []
	flow.happened.connect(func(n, d):
		if n == "trophy":
			heard.append(d.id))
	s.banner = null
	flow.event("spared", {"boss": false})
	_check(flow.trophies.earned.has("words"), "sparing a monster earns one")
	_check(heard == ["words"], "the scene hears of it")
	_check(s.banner == null, "what earned it has its say first")
	flow.event("step")
	_check(s.banner != null and str(s.banner.text).contains(str(Achievements.info("words").label)), "it goes up on the picture")
	flow.event("spared", {"boss": false})
	_check(heard == ["words"], "earned once")
	s.banner = {"title": "x", "text": "y", "t0": flow.clock, "ms": 1000.0}
	flow.event("slain", {"boss": true})
	flow.event("step")
	_check(flow.trophies.earned.has("champion_slain") and str(s.banner.title) == "x", "a banner already up isn't pushed off")
	s.banner = null
	flow.event("step")
	_check(s.banner != null and str(s.banner.text).contains(str(Achievements.info("champion_slain").label)), "it goes up once the way is clear")
	# the ends
	s.tally = {"spared": 2, "slain": 0, "fled": 0, "recruited": 1, "left": 0}
	s.allies = [_ally()]
	var quiet := Achievements.earned_by("run_ended", {"how": "cleared"}, s)
	_check(quiet.has("door") and quiet.has("quiet") and not quiet.has("blood"), "a clean end with a friend (%s)" % [quiet])
	s.tally.slain = 3
	s.tally.spared = 0
	s.allies = []
	var red := Achievements.earned_by("run_ended", {"how": "cleared"}, s)
	_check(red.has("blood") and not red.has("door"), "a red end (%s)" % [red])
	_check(Achievements.earned_by("run_ended", {"how": "lonely"}, s) == ["lonely"], "the drain is its own end")
	s.tally = {"spared": 0, "slain": 0, "fled": 0, "recruited": 0, "left": 0}
	_check(Achievements.earned_by("run_ended", {"how": "cleared"}, s).has("ghost"), "nobody met")
	s.meals = 2
	_check(Achievements.earned_by("run_ended", {"how": "cleared"}, s).has("nobody_asked"), "fed them and got away with it")
	s.found_out = true
	_check(not Achievements.earned_by("run_ended", {"how": "cleared"}, s).has("nobody_asked"), "not when it came out")
	var off = _flow(5, ["no-achievements"])
	await off.new_run()
	off.event("spared", {"boss": false})
	_check(off.trophies.earned.is_empty(), "no-achievements earns nothing")


func _legacy() -> void:
	var plain = _flow(5)
	await plain.new_run()
	var base_hp: int = plain.state.max_hp
	var base_gold: int = plain.state.gold
	_check(plain.state.items.is_empty() and plain.state.sharpened == 0, "no ranks, nothing extra")
	var flow = _flow(5)
	flow.legacy_ranks = {"skin": 2, "purse": 1, "satchel": 2, "edge": 1, "nonsense": 9}
	await flow.new_run()
	var s = flow.state
	var b := Legacy.boons()
	_check(s.max_hp == base_hp + 2 * int(b.skin.max_hp) and s.hp == s.max_hp, "more max HP, and full (%d)" % s.max_hp)
	_check(s.gold == base_gold + int(b.purse.gold), "more gold (%d)" % s.gold)
	_check(s.items == [str(b.satchel.item), str(b.satchel.item)], "salves in the bag (%s)" % [s.items])
	_check(s.sharpened == int(b.edge.sharpened), "a kept edge (%d)" % s.sharpened)
	var over = _flow(5)
	over.legacy_ranks = {"skin": 99}
	await over.new_run()
	_check(over.state.max_hp == base_hp + Legacy.top_rank("skin") * int(b.skin.max_hp), "a rank past the top counts as the top")
	var off = _flow(5, ["no-legacy"])
	off.legacy_ranks = {"skin": 3}
	await off.new_run()
	_check(off.state.max_hp == base_hp, "no-legacy: the boons do nothing")
	var e: Dictionary = Legacy.table().earn
	s.tally = {"spared": 2, "slain": 1, "fled": 0, "recruited": 1, "left": 0}
	s.depth = 3
	var want := 2 * int(e.spared) + int(e.slain) + int(e.recruited) + 2 * int(e.floor)
	_check(Legacy.earned(s, false) == want, "embers come from what you did (%d)" % want)
	_check(Legacy.earned(s, true) == want + int(e.cleared), "and more for clearing it")
	# the run pays when it closes
	var paid := []
	flow.happened.connect(func(n, d):
		if n == "run_closed":
			paid.append(d.embers))
	_use()
	flow.close_run(false)
	_check(paid == [want], "a closed run says what it earned (%s)" % [paid])
	var slice = _flow(5, ["no-legacy"])
	await slice.new_run()
	var none := []
	slice.happened.connect(func(n, _d):
		if n == "run_closed":
			none.append(1))
	slice.close_run(false)
	_check(none.is_empty(), "no-legacy: nothing to pay")


func _progress_store() -> void:
	_use()
	_clear_store()
	_check(Progress.embers() == 0 and Progress.ranks().is_empty() and Progress.earned().is_empty(), "a fresh store has nothing")
	_check(Progress.pay(77, 10) == 10 and Progress.embers() == 10, "a run pays")
	_check(Progress.pay(77, 10) == 0 and Progress.embers() == 10, "the same run left again pays nothing more")
	_check(Progress.pay(77, 14) == 4 and Progress.embers() == 14, "and only what is new")
	_check(Progress.pay(78, 2) == 2 and Progress.embers() == 16, "another run pays by itself")
	var cost := Legacy.next_cost("skin", 0)
	_check(Progress.buy("skin") == "bought" and Progress.ranks().skin == 1 and Progress.embers() == 16 - cost, "a boon is bought")
	Store.set_value(Progress.EMBERS_KEY, 0)
	_check(Progress.buy("skin") == "poor" and Progress.ranks().skin == 1, "not without the embers")
	Store.set_value(Progress.EMBERS_KEY, 999)
	while Progress.ranks().get("skin", 0) < Legacy.top_rank("skin"):
		Progress.buy("skin")
	var left: int = Progress.embers()
	_check(Progress.buy("skin") == "full" and Progress.embers() == left, "not past the top")
	Progress.earn("words")
	Progress.earn("words")
	Progress.earn("nonsense")
	_check(Progress.earned() == ["words"], "earned once, and what isn't one doesn't count")
	Store.set_value(Progress.EMBERS_KEY, "lots")
	Store.set_value(Progress.RANKS_KEY, [1, 2])
	Store.set_value(Progress.EARNED_KEY, "all")
	_check(Progress.embers() == 0 and Progress.ranks().is_empty() and Progress.earned().is_empty(), "a damaged store counts as nothing")
	Store.set_value(Progress.RANKS_KEY, {"skin": 99, "nonsense": 1, "purse": "x"})
	_check(Progress.ranks() == {"skin": Legacy.top_rank("skin")}, "damaged ranks are brought back into line (%s)" % [Progress.ranks()])
	_clear_store()


## Stands the party somewhere with two cells of open floor, so it can walk there and back as long as a test wants.
func _pace(flow, steps: int) -> void:
	var s = flow.state
	s.floor_map.monsters = []
	s.floor_map.pickups = []
	s.floor_map.treasure = []
	s.floor_map.teleports = []
	s.floor_map.merchant = {}
	s.floor_map.quester = {}
	for i in 4:
		if s.floor_map.is_open(s.cell + FloorMap.DIRS[i]) and s.cell + FloorMap.DIRS[i] != s.floor_map.stairs:
			s.facing = i
			break
	for i in steps:
		await flow.press("up" if i % 2 == 0 else "down")


func _hunger() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	var h: Dictionary = Survival.table().hunger
	_check(s.hunger == 0.0 and Survival.stage_of(s.hunger) == "", "a run starts fed")
	await _pace(flow, 4)
	_check(is_equal_approx(s.hunger, 4 * float(h.per_step)), "walking wears on you (%.2f)" % s.hunger)
	s.hunger = float(h.hungry_at) - 0.01
	s.hp = 5
	s.steps = 0
	await _pace(flow, flow.WALK_HEAL_STEPS)
	_check(Survival.stage_of(s.hunger) == "hungry" and s.hp == 5, "hungry, the walk stops healing you")
	_check(s.lines.size() > 0, "and the log has something to say")
	s.hunger = float(h.starving_at)
	s.hp = 5
	s.starved_steps = 0
	await _pace(flow, int(h.starve_every))
	_check(s.hp == 4, "starving costs health every few steps (%d)" % s.hp)
	s.hp = 1
	await _pace(flow, int(h.starve_every) * 2)
	_check(s.hp == 1, "but never the last of it")
	s.hunger = 50.0
	Survival.rest(s)
	_check(s.hunger == 50.0 + float(h.per_floor), "going down is a rest")
	s.hunger = 5.0
	Survival.rest(s)
	_check(s.hunger == 0.0, "which goes no lower than fed")
	var plan_on: Dictionary = {"food": true}
	var pick := Items.floor_finds(Rng.new(3), plan_on)
	_check(pick.has(Survival.RATION), "a floor has food lying about (%s)" % [pick])
	_check(not Items.floor_finds(Rng.new(3), {}).has(Survival.RATION) and not Items.floor_finds(Rng.new(3), {}).has(Survival.ROAST), "and not when the plan has none")
	_check(Items.stock(Rng.new(3), plan_on).has(Survival.RATION), "a trader sells it")
	_check(not Items.stock(Rng.new(3), {}).has(Survival.ROAST), "but nobody has roasts to sell")


func _camp() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	s.allies = []
	s.items = [Survival.RATION, Survival.RATION]
	s.hunger = 80.0
	s.hp = 5
	await flow.press("confirm")
	_check(s.stage == "camp", "Enter sits you down")
	_check(s.menu[0].label == "EAT %s" % Items.label(Survival.RATION) and s.menu.size() == 2, "the same food is offered once (%s)" % [s.menu.map(func(i): return i.label)])
	await flow.press("confirm")
	_check(s.items.size() == 1 and s.hunger == 80.0 - float(Items.info(Survival.RATION).food), "eating takes it from the bag and fills you")
	_check(s.hp == 5 + int(Items.info(Survival.RATION).amount), "and heals a little (%d)" % s.hp)
	var turn_steps: int = s.floor_map.steps
	await flow.press("cancel")
	_check(s.stage == "explore", "Esc gets you up")
	_check(s.floor_map.steps == turn_steps, "and nobody moved while you sat")
	s.items = [Survival.RATION]
	s.hunger = 80.0
	await flow.go("intro", {"foe": s.floor_map.monsters[0]})
	await flow.tick(flow.clock + 1000.0)
	await flow.press("confirm")
	var at: int = s.menu.map(func(i): return i.label).find("ITEM")
	_check(at >= 0, "food counts as something to use in a fight")
	await flow.press(str(at + 1))
	var hunger_was: float = s.hunger
	await flow.press("1")
	_check(s.hunger < hunger_was and s.items.is_empty(), "and it can be eaten there")


func _butcher() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	var left := []
	flow.happened.connect(func(n, d):
		if n == "ally_left" or n == "butchered" or n == "found_out":
			left.append(n))
	s.allies = [_ally("slime", "DRIP"), _ally("snake", "HISS"), _ally("rock", "GRUMM")]
	var standing := float(s.reputation.get(Clans.of("slime"), 0.0))
	await flow.go("camp")
	var labels: Array = s.menu.map(func(i): return i.label)
	_check(labels == ["BUTCHER DRIP", "BUTCHER HISS", "BUTCHER GRUMM", "LEAVE"], "each friend can be butchered (%s)" % [labels])
	await flow.press("1")
	_check(s.allies.size() == 3 and s.menu[0].label == "NO" and s.selected == 0, "it asks first, with NO picked")
	await flow.press("cancel")
	_check(s.stage == "camp" and s.allies.size() == 3 and s.menu.size() == 4, "Esc takes it back")
	await flow.press("1")
	await flow.press("1")
	_check(s.allies.size() == 3 and s.menu.size() == 4, "and NO leaves it be")
	flow.dice.pin(0.99)
	await flow.press("1")
	await flow.press("2")
	flow.dice.unpin()
	_check(s.allies.size() == 2 and s.allies.all(func(a): return a.name != "DRIP"), "YES: it is gone")
	_check(s.items.count(Survival.ROAST) == int(Survival.table().butcher.roasts), "and the bag has roasts in it (%s)" % [s.items])
	_check(left == ["butchered", "ally_left"], "the sound and the party hear of it (%s)" % [left])
	_check(s.butchered == [{"species": "slime", "name": "DRIP"}], "the run remembers who")
	_check(not s.found_out, "nobody noticed, on that roll")
	_check(float(s.reputation.get(Clans.of("slime"), 0.0)) < standing, "its clan has its doubts anyway")
	_check(s.menu.map(func(i): return i.label).has("FEED HISS"), "now there is something to feed the others")
	_check(s.menu.map(func(i): return i.label).has("EAT %s" % Items.label(Survival.ROAST)), "or to eat")
	await flow.press("cancel")
	# a witness
	var two = _flow(6)
	await two.new_run()
	var t = two.state
	t.allies = [_ally("slime", "DRIP"), _ally("snake", "HISS", 80.0), _ally("rock", "GRUMM", 80.0)]
	await two.go("camp")
	two.dice.pin(0.0)
	await two.press("1")
	await two.press("2")
	two.dice.unpin()
	_check(t.found_out and t.allies.size() < 3, "on a low roll someone saw, and walked out")
	_check(t.lines.any(func(l): return str(l.text).contains("walks out")), "and the log says so (%s)" % [t.lines])
	# the last friend
	var last = _flow(7)
	await last.new_run()
	last.state.allies = [_ally()]
	await last.go("camp")
	last.dice.pin(0.99)
	await last.press("1")
	await last.press("2")
	last.dice.unpin()
	_check(last.state.allies.is_empty(), "the last friend can go too")
	_check(last.state.menu[-1].label == "LEAVE", "and the camp still works alone (%s)" % [last.state.menu])
	last.state.items = [Survival.ROAST]
	await last.press("cancel")
	# a full bag
	var full = _flow(8)
	await full.new_run()
	full.state.allies = [_ally()]
	full.state.items = []
	for _i in int(Items.table().carry):
		full.state.items.append("salve")
	await full.go("camp")
	full.dice.pin(0.99)
	await full.press("1")
	await full.press("2")
	full.dice.unpin()
	_check(full.state.items.count(Survival.ROAST) == 0 and full.state.lines[0].text == Survival.line("no_room"), "a full bag wastes it, and says so")


func _feeding() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	s.allies = [_ally("snake", "HISS", 50.0), _ally("rock", "GRUMM", 50.0)]
	s.butchered = [{"species": "slime", "name": "DRIP"}]
	s.items = [Survival.ROAST, Survival.ROAST]
	flow.dice.pin(0.99)
	var quiet: Dictionary = Survival.feed(s, s.allies[0], flow.dice)
	flow.dice.unpin()
	_check(not quiet.found_out and s.allies.size() == 2, "fed, and it suspects nothing")
	_check(s.allies[0].loyalty == 50.0 + float(Survival.table().butcher.feed_loyalty), "and it likes you better (%.0f)" % s.allies[0].loyalty)
	_check(s.meals == 1 and s.allies[0].meals == 1 and s.items.size() == 1, "the bowl is counted")
	_check(Survival.notice_odds(s.allies[0]) > Survival.notice_odds(s.allies[1]), "the more it has eaten, the likelier it works it out")
	var standing := float(s.reputation.get(Clans.of("slime"), 0.0))
	var gator = s.allies[0]
	var other = s.allies[1]
	var other_loyalty: float = other.loyalty
	flow.dice.pin(0.0)
	var caught: Dictionary = Survival.feed(s, gator, flow.dice)
	flow.dice.unpin()
	_check(caught.found_out and not s.allies.has(gator), "on a low roll it works it out and leaves")
	_check(s.found_out, "the run remembers it came out")
	_check(s.tally.left == 1, "the tally counts it as gone")
	_check(caught.told == [other] and other.loyalty == other_loyalty + float(Survival.table().butcher.told_loyalty), "the others are told, and trust you less")
	_check(float(s.reputation.get(Clans.of("slime"), 0.0)) < standing, "and the victim's clan hears")
	s.items = []
	var none: Dictionary = Survival.feed(s, other, flow.dice)
	_check(not none.found_out and s.meals == 2, "no roast, nothing happens")
	# by the menu: a roll goes through the flow's dice, and the log says it
	var by_menu = _flow(9)
	await by_menu.new_run()
	var m = by_menu.state
	m.allies = [_ally("snake", "HISS"), _ally("rock", "GRUMM")]
	m.butchered = [{"species": "slime", "name": "DRIP"}]
	m.items = [Survival.ROAST]
	await by_menu.go("camp")
	var labels: Array = m.menu.map(func(i): return i.label)
	by_menu.dice.pin(0.0)
	await by_menu.press(str(labels.find("FEED HISS") + 1))
	by_menu.dice.unpin()
	_check(m.lines[0].text == Survival.line("found_out") % "HISS", "the log says who worked it out")
	_check(m.lines[1].text == Survival.line("told") % "GRUMM", "and who was told")


func _selling() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	s.floor_map.merchant = {"cell": Vector2i(1, 1), "stock": ["salve"]}
	s.items = [Survival.ROAST, "salve"]
	s.gold = 3
	await flow.go("trade")
	var labels: Array = s.menu.map(func(i): return i.label)
	var price := Survival.sell_price(Survival.ROAST)
	var sell := "SELL %s %dG" % [Items.label(Survival.ROAST), price]
	_check(labels.has(sell), "a trader buys a roast (%s)" % [labels])
	_check(not labels.any(func(l): return str(l).begins_with("SELL %s" % Items.label("salve"))), "and only that")
	await flow.press(str(labels.find(sell) + 1))
	_check(s.gold == 3 + price and s.items == ["salve"], "gold for it (%d)" % s.gold)
	_check(s.lines[0].text == Survival.line("sold") % [Items.label(Survival.ROAST), price, s.gold], "and it doesn't ask")
	_check(not s.menu.map(func(i): return i.label).has(sell), "none left to sell")
	await flow.press("cancel")
	_check(s.stage == "explore", "and you walk off as ever")


func _saved() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	s.hunger = 42.5
	s.starved_steps = 3
	s.meals = 2
	s.found_out = true
	s.butchered = [{"species": "slime", "name": "DRIP"}]
	var a = _ally("snake", "HISS")
	a.meals = 3
	s.allies = [a]
	s.items = [Survival.ROAST, Survival.RATION]
	var copy = State.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	_check(copy != null, "a run with all that in it saves")
	_check(copy.hunger == 42.5 and copy.starved_steps == 3 and copy.meals == 2 and copy.found_out, "and hunger and the secret come back")
	_check(copy.butchered == s.butchered and copy.allies[0].meals == 3, "with who it was and who ate what")
	_check(copy.items == s.items, "and the food in the bag")
	var old: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	for key in ["hunger", "starvedSteps", "meals", "foundOut", "butchered"]:
		old.erase(key)
	old.allies[0].erase("meals")
	var older = State.from_dict(old)
	_check(older != null and older.hunger == 0.0 and older.meals == 0 and not older.found_out and older.butchered.is_empty() and older.allies[0].meals == 0, "a save from before all this still loads")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(s.to_dict()))
	bad.hunger = 1000.0
	bad.butchered = [1, {"species": "slime"}, {"name": "x"}, {"species": "slime", "name": "DRIP"}]
	bad.meals = -4
	var fixed = State.from_dict(bad)
	_check(fixed != null and fixed.hunger == float(Survival.table().hunger.starving_at) and fixed.meals == 0 and fixed.butchered.size() == 1, "a damaged save is brought back into line (%s)" % [fixed.butchered])


func _endings() -> void:
	var flow = _flow(5)
	await flow.new_run()
	var s = flow.state
	var closed := []
	flow.happened.connect(func(n, d):
		if n == "run_closed" or n == "run_ended":
			closed.append(n))
	s.depth = Floors.run_floors()
	s.allies = [_ally()]
	s.meals = 1
	s.floor_map.monsters = []
	var stairs: Vector2i = s.floor_map.stairs
	for i in 4:
		if s.floor_map.is_open(stairs - FloorMap.DIRS[i]):
			s.cell = stairs - FloorMap.DIRS[i]
			s.facing = i
			break
	await flow.press("up")
	_check(s.stage == "end" and s.run_over, "the last stairs end the run")
	_check(closed == ["run_ended", "run_closed"], "and it says how, and pays (%s)" % [closed])
	_check(s.lines.any(func(l): return str(l.text).contains(Survival.line("kept"))), "the end knows about the stew (%s)" % [s.lines])
	s.found_out = true
	_check(Survival.ending_note(s) == Survival.line("known"), "and when it came out")
	s.found_out = false
	s.meals = 0
	_check(Survival.ending_note(s) == "", "and says nothing of a clean run")
	# the door shuts if the last friend is in your bag
	var door = _flow(6)
	await door.new_run()
	var d = door.state
	d.depth = Floors.run_floors()
	d.allies = [_ally()]
	await door.go("camp")
	door.dice.pin(0.99)
	await door.press("1")
	await door.press("2")
	door.dice.unpin()
	await door.press("cancel")
	d.floor_map.monsters = []
	for i in 4:
		if d.floor_map.is_open(d.floor_map.stairs - FloorMap.DIRS[i]):
			d.cell = d.floor_map.stairs - FloorMap.DIRS[i]
			d.facing = i
			break
	await door.press("up")
	_check(d.menu[0].label == "TURN BACK", "the Last Door won't open for someone who ate their friend")
	# a fall closes a run only when you give it up
	var fell = _flow(7)
	await fell.new_run()
	var f = fell.state
	var paid := []
	fell.happened.connect(func(n, data):
		if n == "run_closed":
			paid.append(data.embers))
	f.foe = f.floor_map.monsters[0]
	f.tally.slain = 3
	await fell.go("intro", {"foe": f.foe})
	await fell.tick(fell.clock + 1000.0)
	await fell.go("wait")
	await fell.go("dodge")
	f.hp = 0
	await fell.go("dead")
	_check(paid.is_empty(), "falling alone doesn't end it: you may try again")
	await fell.press(str(f.menu.map(func(i): return i.label).find("MAIN MENU") + 1))
	_check(paid.size() == 1 and paid[0] == 3 * int(Legacy.table().earn.slain), "leaving does (%s)" % [paid])


func _menu_pages() -> void:
	_use()
	_clear_store()
	Progress.earn("words")
	Store.set_value(Progress.EMBERS_KEY, 7)
	var panel := MenuStub.new()
	var main: Dictionary = Menus.main(panel, {"new_game": func(): pass, "load_slot": func(_s): pass})
	var labels: Array = main.items.map(func(i): return i.label)
	_check(labels.has("LEGACY") and labels.has("ACHIEVEMENTS"), "the main menu has both pages (%s)" % [labels])
	var legacy_line: Dictionary = main.items[labels.find("LEGACY")]
	_check(str(legacy_line.sub).contains("7"), "and says how many embers (%s)" % legacy_line.sub)
	var page: Dictionary = Menus.legacy(panel)
	_check(page.items.size() == Legacy.boons().size(), "a line per boon")
	var cost := Legacy.next_cost("purse", 0)
	var purse = page.items.filter(func(i): return str(i.label).contains(str(Legacy.boons().purse.label))).front()
	_check(str(purse.label).contains(str(cost)), "each says what it costs (%s)" % purse.label)
	purse.act.call()
	_check(Progress.ranks().get("purse", 0) == 1 and Progress.embers() == 7 - cost, "picking one buys it")
	var trophies: Dictionary = Menus.achievements()
	_check(str(trophies.title).contains("1") and str(trophies.body).contains(str(Achievements.info("words").label)), "the earned ones are named (%s)" % trophies.title)
	_check(not str(trophies.body).contains(str(Achievements.info("nobody_asked").label)), "and the others stay a surprise")
	_use(["no-legacy", "no-achievements"])
	var without: Dictionary = Menus.main(panel, {"new_game": func(): pass, "load_slot": func(_s): pass})
	var plain: Array = without.items.map(func(i): return i.label)
	_check(not plain.has("LEGACY") and not plain.has("ACHIEVEMENTS"), "without them: neither page")
	_clear_store()
	panel.free()


class MenuStub:
	extends Object
	func open(_builder) -> void:
		pass
	func push(_builder) -> void:
		pass
	func pop() -> void:
		pass
	func refresh() -> void:
		pass
