## Keepsakes: what a champion leaves you once it is out of your way. Three are offered, you take one, and it is yours for the rest
## of the run (data/keepsakes.json has their names and words). What each does is a number here and one line where it applies: the
## strike bar, the dodge, the fight menu, a purse.
extends RefCounted

const Content = preload("res://src/rules/content.gd")
const Rng = preload("res://src/utils/rng.gd")

const OFFERED := 3
const EMBER_MAX_HP := 6 # ember heart
const TOOTH_DAMAGE := 2 # sharp tooth: added to every strike that lands
const STEADY_SCALE := 2.0 # steady hand: how much wider the perfect mark is
const THICK_GUARD := 1 # thick hide: taken off every hit in the box
const QUICK_WINDOW := 1.5 # quick feet: how much longer the close-call window is
const DEEP_NERVE := 2 # deep breath: the nerve a fight starts with
const OPEN_MERCY := 0.15 # open hand: added to the odds that a monster takes mercy
const LUCKY_GOLD := 1.5 # lucky coin: what a purse or a chest is worth
const NEEDS_NERVE := ["quick_feet", "deep_breath"] # never offered in a game without the feature nerve
const SEED_OFFSET := 7700 # so an offer draws its own numbers from the run's seed


static func table() -> Dictionary:
	return Content.table("keepsakes")


static func ids() -> Array:
	return table().keepsakes.keys()


static func known(id: String) -> bool:
	return table().keepsakes.has(id)


static func name_of(id: String) -> String:
	return str(table().keepsakes[id].name)


static func text_of(id: String) -> String:
	return str(table().keepsakes[id].text)


## Whether the party holds this one.
static func has(s, id: String) -> bool:
	return s.keepsakes.has(id)


## The three offered after the champion of floor `depth`: always the same three for the same run, floor and holdings, and none
## already held. Fewer when fewer are left; `nerve` false leaves out the ones that only matter with the feature nerve.
static func offer(run_seed: int, depth: int, held: Array, nerve := true) -> Array:
	var pool: Array = ids().filter(func(id): return not held.has(id) and (nerve or not NEEDS_NERVE.has(id)))
	Rng.new(Rng.offset(run_seed, SEED_OFFSET + depth)).shuffle(pool)
	return pool.slice(0, OFFERED)


## The party takes this one. What it does at once (the ember heart) is done here; the rest is read where it applies.
static func take(s, id: String) -> void:
	if not known(id) or s.keepsakes.has(id):
		return
	s.keepsakes.append(id)
	if id == "ember_heart":
		s.max_hp += EMBER_MAX_HP
		s.hp = s.max_hp


## What a purse or a chest of `amount` gold is worth to this party.
static func gold(s, amount: int) -> int:
	return roundi(amount * LUCKY_GOLD) if has(s, "lucky_coin") else amount


## The names of what the party holds, in the order taken.
static func held_names(s) -> Array:
	return s.keepsakes.map(func(id): return name_of(id))


## "the EMBER HEART and the SHARP TOOTH", for a line that says what the party holds ("" when it holds none).
static func held_words(s) -> String:
	var names := held_names(s)
	if names.is_empty():
		return ""
	return str(names[0]) if names.size() == 1 else "%s and the %s" % [", the ".join(names.slice(0, -1)), names[-1]]
