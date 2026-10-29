## The party panel as data: partyRow(), statusChips(), slotPips(), powersCell(), deathSaves(), chip() and
## renderParty() from game.js, as rows the party widget paints. Pure (tested in tests/ui).
##   ctx: color_of (Callable: a monster member's colour), boon_title (Callable: a member's stats line for the tooltip)
## rows(G, ctx) returns one entry per member, with an "ALLIES n/m" divider before the first monster:
##   {kind: "human"|"monster", num, name, sub, ink, skull, state, dying, dead, acting, picked, title, name_tip,
##    hp: {pct, color, word, text, saves, tip}, ac, ac_tip, pw, chips}
##   {kind: "div", allies, max, full, tip}
extends RefCounted

const J = preload("res://src/core/js.gd")
const Status = preload("res://src/rules/status.gd")

## An ally's mood after a talk: its icon and colour
const MOODS := {"SULKING": ["frown", "#8a8a8a"], "DISTRACTED": ["what", "#ffd23f"], "STEADY": ["target", "#8fd3ff"]}


static func chip(icon: String, word: String, color: String, tip: String) -> Dictionary:
	return {"icon": icon, "word": word, "color": color, "tip": tip}


## Spell slots as pips coloured by circle, with the counts in the tooltip
static func slot_pips(m: Dictionary) -> Dictionary:
	var groups := Status.slot_groups(m.get("slots"), m.get("maxSlots"))
	var parts := []
	for g in groups:
		parts.append("%s CIRCLE %d OF %d" % [Status.CIRCLE_WORDS[g.circle - 1], g.left, g.max])
	var tip := "SPELL SLOTS LEFT: %s. A SPELL USES ONE SLOT OF ITS CIRCLE. CAMP TO REFILL" % ", ".join(parts)
	return {"kind": "slots", "groups": groups, "tip": tip}


## A caster's slot pips, or the fighter's Second Wind and Action Surge as two square pips
static func powers_cell(m: Dictionary):
	if m.get("maxSlots") != null:
		return slot_pips(m)
	if m.get("clsId") != "fighter":
		return null
	var uses: Dictionary = m.get("uses", {}) if m.get("uses") is Dictionary else {}
	var skills := [["second_wind", "SECOND WIND"], ["action_surge", "ACTION SURGE"]]
	var parts := []
	var pips := []
	for s in skills:
		var ready := J.truthy(uses.get(s[0]))
		parts.append("%s %s" % [s[1], "READY" if ready else "USED"])
		pips.append(ready)
	return {"kind": "skills", "pips": pips, "color": "#ffb347", "tip": "SKILLS: %s. THEY COME BACK WHEN YOU CAMP" % ", ".join(parts)}


static func status_chips(m: Dictionary) -> Array:
	var chips := []
	var dead := J.truthy(m.get("dead"))
	if m.get("kind") == "monster" and not dead:
		var loyalty = J.nz(m.get("loyalty"), 50)
		var l := Status.loyalty_state(loyalty)
		chips.append(chip("heart", l.word, l.color, "LOYALTY %s OF 100: %s. AN UNHAPPY ALLY MAY LEAVE OR TURN ON YOU" % [J.num(loyalty), l.word]))
	for c in Status.cond_list(m.get("cond")):
		chips.append(chip(c.icon, c.word, c.color, c.tip))
	var buff = m.get("buff")
	if buff is Dictionary:
		chips.append(chip("star", str(buff.id), "#ffe14a", "%s: %s" % [buff.id, J.up(buff.get("desc", ""))]))
	var mood = m.get("mood")
	if mood is Dictionary:
		var look: Array = MOODS.get(mood.id, ["dot", "#e8e8e8"])
		chips.append(chip(look[0], str(mood.id), look[1], "%s: %s" % [mood.id, J.up(mood.get("desc", ""))]))
	if J.truthy(m.get("phoenix")) and not dead:
		chips.append(chip("flame", "PHOENIX", "#ffb347", "PHOENIX FEATHER: WILL CHEAT DEATH ONCE"))
	return chips


## Down members: three boxes for death-save successes, three for failures
static func death_saves(m: Dictionary) -> Dictionary:
	var s = m.get("saves") if m.get("saves") is Dictionary else {"s": 0, "f": 0}
	var ok := int(s.get("s", 0))
	var bad := int(s.get("f", 0))
	return {"s": ok, "f": bad, "tip": "DEATH SAVES: %d OF 3 SUCCESSES, %d OF 3 FAILURES. THREE FAILURES AND %s DIES. ANY HEALING GETS THEM UP" % [ok, bad, m.get("name", "")]}


## partyRow(m, i): one member
static func row(G: Dictionary, m: Dictionary, i: int, ctx := {}) -> Dictionary:
	var st := Status.hp_state(m)
	var hp := maxi(0, int(m.get("hp", 0)))
	var monster: bool = m.get("kind") == "monster"
	var color_of: Callable = ctx.get("color_of", Callable())
	var boon_title: Callable = ctx.get("boon_title", Callable())
	var dead := J.truthy(m.get("dead"))
	var down := J.truthy(m.get("down"))
	var word: String = "" if st.id == "healthy" else st.word
	var text := ""
	var saves = null
	if not dead and not down:
		text = "%d/%s" % [hp, J.num(m.get("maxHp", 0))]
	elif down and not dead and not J.truthy(m.get("stable")):
		saves = death_saves(m)
	var menu = G.get("menu")
	var acting: bool = menu is Dictionary and is_same(menu.get("who"), m)
	var picked := false
	if menu is Dictionary:
		var options: Array = menu.get("options", [])
		var sel := int(menu.get("sel", 0))
		picked = sel >= 0 and sel < options.size() and is_same(options[sel].get("who"), m)
	var level = J.nz(m.get("level"), 1)
	return {
		"kind": "monster" if monster else "human",
		"num": "▶" if acting and not monster else str(i + 1),
		"name": str(m.get("name", "")),
		"sub": "%s%s · LEVEL %s" % [Status.class_word(m), " ALLY" if monster else "", J.num(level)],
		"name_tip": "%s: %s ALLY · LEVEL %s" % [m.get("name", ""), Status.class_word(m), J.num(level)] if monster else "",
		"ink": str(color_of.call(m)) if monster and color_of.is_valid() else "",
		"skull": dead,
		"state": st.id,
		"dying": st.id == "dying",
		"dead": dead,
		"acting": acting and not monster,
		"picked": picked,
		"title": str(boon_title.call(m)) if boon_title.is_valid() and m.get("mods") is Dictionary else "",
		"hp": {"pct": st.pct, "color": st.color, "word": word, "text": text, "saves": saves, "tip": "HEALTH %d OF %s: %s" % [hp, J.num(m.get("maxHp", 0)), st.word]},
		"ac": J.num(m.get("ac", 0)),
		"ac_tip": "ARMOR %s: AN ATTACKER NEEDS %s OR MORE, WITH ITS BONUS, TO HIT" % [J.num(m.get("ac", 0)), J.num(m.get("ac", 0))],
		"pw": null if monster else powers_cell(m),
		"chips": status_chips(m),
	}


## renderParty(): every member, with "ALLIES n/m" (how many monsters can still join) where the monsters start
static func rows(G: Dictionary, ctx := {}) -> Array:
	var party: Array = G.get("party", [])
	var out := []
	var room := Status.ally_room(party)
	for i in party.size():
		var m: Dictionary = party[i]
		if m.get("kind") == "monster" and not out.any(func(r): return r.kind == "div"):
			var tip := "YOUR PARTY HOLDS %d: ROOM FOR %d MONSTER ALLIES BESIDE YOUR ADVENTURERS%s" % [Status.PARTY_MAX, room.max, ". FULL: NO ONE ELSE CAN JOIN" if room.full else ""]
			out.append({"kind": "div", "allies": room.allies, "max": room.max, "full": room.full, "tip": tip})
		out.append(row(G, m, i, ctx))
	return out
