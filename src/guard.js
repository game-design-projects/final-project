// Captain Jimbo, as data: persona, the approved action set, and the approved lines per action.
// Jev only ever picks from these; code decides which are available and whether a pick is allowed.

export const PERSONA = {
  name: "Captain Jimbo",
  role: "Veteran guard of the south gate of the city of Ashvale",
  personality: [
    "Dutiful and by-the-book, but tired after twenty years on the gate",
    "Dry sense of humor with a weakness for jokes and puns; a genuinely funny line makes him laugh out loud",
    "Softens toward genuine kindness and honest hardship",
    "His late mother grew wildflowers; the sight of them moves him",
    "Privately willing to bend the toll rule for someone in genuine need who has earned his trust",
    "Hates being lied to, ordered around, or insulted",
    "Will not back down from a fight, but prefers a warning to bloodshed",
  ],
  duty:
    "Let travelers into the city only if they pay the 10-gold toll or show a valid travel writ in their own name. Keep armed troublemakers out.",
};

// `when` (optional) hides a line unless the situation makes it sensible. `c` is the turn context from brain.js;
// `c.offerItems` lists what may be on offer this turn (speculatively, before Jev has read the message).
export const ACTIONS = {
  hold_post: {
    description: "Stay at, or return to, his post beside the gate and keep watch",
    lines: {
      move_along: "Move along, traveler.",
      state_business: "State your business or be on your way.",
      watch_silently: "*watches you silently from his post*",
      keep_distance: "Keep your distance from the gate.",
    },
  },
  patrol: {
    description: "Carry on walking his patrol route along the wall, paying the traveler little attention",
    lines: {
      hum: "*paces along the wall, humming an old marching tune*",
      quiet_day: "Quiet day. Too quiet.",
      glance: "*glances your way, then keeps walking his route*",
    },
  },
  approach: {
    description: "Walk toward the traveler to get a closer look or to confront them",
    lines: {
      hold_there: "You there. Hold where you are.",
      closer_look: "Let me get a look at you.",
      coming_over: "Easy now. I'm coming over.",
      stride: "*strides toward you*",
    },
  },
  back_off: {
    description: "Step away from the traveler to keep a safe distance",
    lines: {
      stay_back: "Stay back. I mean it.",
      not_closer: "Not one step closer.",
      step_back: "*steps back, hand on the hilt of his sword*",
    },
  },
  converse: {
    description: {
      what: "Talk with the traveler without moving: answer a question, chat, or respond to what they said",
      not_for: "Taking or refusing coins or an item the traveler is offering (use accept_offer or refuse_offer)",
    },
    lines: {
      greet: "Evening, traveler. This is the south gate of Ashvale. What brings you?",
      explain_toll: "Entry is ten gold. The city's rule, not mine.",
      about_city: "Ashvale? Markets, temples, and far too many pigeons. Worth the toll, mostly.",
      about_himself: "Captain Jimbo. Twenty years on this gate, and my knees remember every one.",
      explain_writ: "A proper travel writ in your own name gets you in without the toll.",
      about_area: "Out here it's just fields, the river, and whatever travelers drop on the road.",
      thanks_kindness: "Hm. Kind words are rare out here. Thank you.",
      sympathy: "Sorry to hear it. Truly. But rules are rules.",
      rebuke: "Watch your tongue.",
      refuse_orders: "Nice try. I take orders from the watch commander, not from you.",
      no_entry: "No toll, no writ, no entry. That's the job.",
      confused: "Say that again, plainer.",
      small_talk: "Quiet day. The river's running high this season.",
      warming_up: "You're alright, you know that?",
    },
  },
  laugh: {
    description: "Laugh out loud at a joke, pun, or funny remark in `traveler.latest_message`",
    lines: {
      hearty: "*laughs heartily*",
      good_one: "Ha! That's a good one.",
      chuckle: "*chuckles despite himself* Alright, alright. You're funny.",
      wipes_eye: "*wipes a tear from his eye* Haven't laughed like that in weeks.",
    },
  },
  demand_toll: {
    description: "Tell the traveler they must pay the 10-gold toll to enter",
    lines: {
      ten_or_nothing: "Ten gold, or you're not getting through.",
      pay_or_leave: "Toll's ten gold. Pay up or turn around.",
      not_my_rule: "I don't make the rules. Ten gold.",
      short_offer: {
        text: "You're short. Ten gold, not a copper less.",
        when: (c) => c.offerItems.includes("gold") && c.goldShort,
      },
    },
  },
  accept_offer: {
    description: "Accept the coins or item the traveler is offering him",
    lines: {
      take_toll: {
        text: "Ten gold, counted. You may pass.",
        when: (c) => c.offerItems.includes("gold") && !c.goldShort,
      },
      take_ring: {
        text: "A silver ring... that covers the toll and then some. Go on through.",
        when: (c) => c.offerItems.includes("ring"),
      },
      take_flowers: {
        text: "Wildflowers? My mother grew these... Thank you.",
        when: (c) => c.offerItems.includes("flowers"),
      },
      grudging: "Fine. Hand it over.",
    },
  },
  refuse_offer: {
    description: "Refuse the coins or item the traveler is offering him",
    lines: {
      not_for_sale: "Keep it. I'm not for sale.",
      not_enough: {
        text: "That's not enough, and you know it.",
        when: (c) => c.offerItems.includes("gold") && c.goldShort,
      },
      dont_want: "I don't want that.",
      after_your_behavior: "After the way you've acted? Keep your offerings.",
    },
  },
  inspect_papers: {
    description: "Ask for or examine the traveler's travel writ, and question who they are",
    lines: {
      ask_papers: { text: "Papers. Let's see them.", when: (c) => c.writ === "none" },
      whose_name: { text: "This writ has a name on it. What's yours?", when: (c) => c.writ === "presented" },
      confirm_bearer: {
        text: "Tomas Reed, spice merchant of Low Harrow... that you?",
        when: (c) => c.writ === "presented",
      },
      seal_genuine: { text: "Seal's genuine. Harbor Office.", when: (c) => c.writ === "presented" },
      name_mismatch: { text: "Funny. That's not the name you gave me.", when: (c) => c.writ === "rejected" },
      not_yours: { text: "This writ isn't yours, is it?", when: (c) => c.writ === "rejected" },
    },
  },
  open_gate: {
    description: "Unlock and open the gate to let the traveler into the city",
    lines: {
      go_through: "Go on through. Keep out of trouble.",
      welcome: "Gate's open. Welcome to Ashvale.",
      before_i_change: "Fine. In you go, before I change my mind.",
    },
  },
  warn: {
    description: "Warn the traveler to stop what they are doing, with his hand on his weapon",
    lines: {
      last_warning: "Last warning.",
      blade_away: { text: "Put that blade away. Now.", when: (c) => c.swordDrawn },
      cell_tonight: "One more word like that and you'll spend the night in a cell.",
      try_again: "Try that again and see what happens.",
      hand_on_hilt: "*rests his hand on the hilt of his sword*",
    },
  },
  attack: {
    description: "Strike the traveler with his sword",
    lines: {
      strike: "*draws his sword and strikes!*",
      asked_for_it: "You asked for this!",
      for_ashvale: "For Ashvale!",
    },
  },
  arrest: {
    description: "Seize the traveler and put them in irons",
    lines: {
      under_arrest: "You're under arrest.",
      hands_up: "That's it. Hands where I can see them.",
      cells_tonight: "Liars and troublemakers sleep in the cells tonight.",
    },
  },
  call_guards: {
    description: "Ring the alarm bell to summon the city watch",
    lines: {
      bell: "*rings the alarm bell* GUARDS! To the south gate!",
      to_me: "Watch! To me!",
    },
  },
};

export function linesFor(actionId, c) {
  const out = {};
  for (const [id, line] of Object.entries(ACTIONS[actionId].lines)) {
    if (typeof line === "string") out[id] = line;
    else if (!line.when || line.when(c)) out[id] = line.text;
  }
  return out;
}
