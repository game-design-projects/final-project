## Hold to talk: the browser's built-in speech recognition (Web Speech API) turns what you say into the words
## you'd otherwise type to a monster. Chrome, Edge and Safari have it; the web build reaches it through
## JavaScriptBridge. Everywhere else (the desktop builds, Firefox) `supported` is false and the game just keeps
## the text box (the ui hides the mic button).
## Load it with `const Voice = preload("res://src/audio/voice.gd")` and use `Voice.Listener`.
extends RefCounted

const Self = preload("res://src/audio/voice.gd")
const J = preload("res://src/core/js.gd")

## How long a key must be held before it means "listen" rather than a tap
const HOLD_MS := 280

static var _spaces := RegEx.create_from_string("\\s+")


## The recognizer class (anything with `.new()` giving a Recognition: see Listener), or null if there is none.
## `win` is a Dictionary standing in for `window` (tests); by default, the browser's, on the web build.
static func recognizer(win = null):
	if win is Dictionary:
		return J.nz(win.get("SpeechRecognition"), win.get("webkitSpeechRecognition"))
	if OS.has_feature("web") and WebRecognition.available():
		return WebRecognition
	return null


## What holding Space does, from the game's state (pure, so it can be tested):
##   "listen": the talk box is open and empty, so speak into it
##   "talk":   in a fight with nothing else waiting, open TALK (T) and listen
##   "ally":   exploring with a monster ally, open TALK TO ALLY (E) and listen once its box opens
##   null:     Space is just a key here (a menu, a question, "any key", the monsters' turn, a box with text in it)
## opts: inputOpen, inputEmpty (true), numeric, waiting, combat, allies (a count)
static func space_hold(opts := {}):
	if opts.get("inputOpen", false):
		return "listen" if opts.get("inputEmpty", true) and not opts.get("numeric", false) else null
	if opts.get("waiting", false):
		return null
	if opts.get("combat", false):
		return "talk"
	if opts.get("allies", 0) > 0:
		return "ally"
	return null


## SpeechRecognition from the page, behind the interface Listener uses. Properties: lang, continuous, interimResults;
## callbacks the Listener sets (Callables): onresult(ev), onerror(ev), onend(); methods: start() -> bool, stop(), abort().
## ev is {results: [{transcript, isFinal}, ...]} for a result (the whole session so far) and {error} for an error.
class WebRecognition:
	extends RefCounted
	var lang := "en-US"
	var continuous := false
	var interimResults := false
	var onresult := Callable()
	var onerror := Callable()
	var onend := Callable()
	var _rec = null  # the JavaScriptObject
	var _js_callbacks: Array = []  # JavaScriptBridge callbacks must be kept alive

	static func available() -> bool:
		if not OS.has_feature("web"):
			return false
		return JavaScriptBridge.eval("!!(window.SpeechRecognition || window.webkitSpeechRecognition)", true) == true

	## The page's language, as the JS Listener's default
	static func page_language() -> String:
		var l = JavaScriptBridge.eval("navigator.language || ''", true)
		return l if l is String and l != "" else "en-US"

	func _init() -> void:
		# The page-side helpers: the event's results as JSON (the list isn't a plain array), and a start() that reports a throw
		JavaScriptBridge.eval("window.__donjonSpeechResults = function (ev) { return JSON.stringify(Array.from(ev.results, function (r) { return { transcript: r[0].transcript, isFinal: !!r.isFinal }; })); };", true)
		JavaScriptBridge.eval("window.__donjonSpeechStart = function (r) { try { r.start(); return true; } catch (e) { console.warn('voice:', e); return false; } };", true)
		var name := "SpeechRecognition" if JavaScriptBridge.eval("!!window.SpeechRecognition", true) == true else "webkitSpeechRecognition"
		_rec = JavaScriptBridge.create_object(name)

	func start() -> bool:
		if _rec == null:
			return false
		_rec.lang = lang
		_rec.continuous = continuous
		_rec.interimResults = interimResults
		var on_result := JavaScriptBridge.create_callback(_js_result)
		var on_error := JavaScriptBridge.create_callback(_js_error)
		var on_end := JavaScriptBridge.create_callback(_js_end)
		_js_callbacks = [on_result, on_error, on_end]
		_rec.onresult = on_result
		_rec.onerror = on_error
		_rec.onend = on_end
		return JavaScriptBridge.get_interface("window").__donjonSpeechStart(_rec) == true

	func stop() -> void:
		if _rec != null:
			_rec.stop()

	func abort() -> void:
		if _rec != null:
			_rec.abort()

	func _js_result(args: Array) -> void:
		if not onresult.is_valid():
			return
		var win = JavaScriptBridge.get_interface("window")
		var parsed = JSON.parse_string(str(win.__donjonSpeechResults(args[0])))
		onresult.call({"results": parsed if parsed is Array else []})

	func _js_error(args: Array) -> void:
		if onerror.is_valid():
			onerror.call({"error": str(args[0].error)})

	func _js_end(_args: Array) -> void:
		if onend.is_valid():
			onend.call()


class Listener:
	extends Node
	## One listening session at a time: start() resolves with the words heard (possibly "") once you stop,
	## or null if it was cancelled or speech isn't supported. onText gets the words so far as they come in.
	## opts: `Recognition` (a class with .new() giving a Recognition, see WebRecognition; default: Voice.recognizer()),
	## `lang`, `onText` (Callable(String)), `onError` (Callable(String)).
	var recognition = null
	var lang := "en-US"
	var on_text := Callable()
	var on_error := Callable()
	var rec = null
	var _session: Dictionary = {}

	func _init(opts := {}) -> void:
		recognition = opts["Recognition"] if opts.has("Recognition") else Self.recognizer()
		if opts.has("lang"):
			lang = opts["lang"]
		elif OS.has_feature("web") and recognition != null:
			lang = WebRecognition.page_language()
		on_text = opts.get("onText", Callable())
		on_error = opts.get("onError", Callable())

	var supported: bool:
		get:
			return recognition != null

	var listening: bool:
		get:
			return rec != null

	func start():
		if recognition == null:
			return null
		cancel()
		var r = recognition.new()
		rec = r
		r.lang = lang
		r.continuous = true  # keep listening for as long as the key is held
		r.interimResults = true  # show the words while you're still speaking
		var session := {"text": "", "cancelled": false, "waiter": J.Waiter.new()}
		_session = session
		r.onresult = func(ev):
			# The engine reports the whole session so far: finished phrases, then the one still in progress
			var text := ""
			for item in ev.get("results", []):
				text += str(item.get("transcript", ""))
			session.text = Self._spaces.sub(text, " ", true).strip_edges()
			if on_text.is_valid():
				on_text.call(session.text)
		r.onerror = func(ev):
			var err := str(ev.get("error", ""))
			print_verbose("voice: error ", err)
			if err != "no-speech" and err != "aborted" and on_error.is_valid():
				on_error.call(err)
		r.onend = func():
			if rec == r:
				rec = null
			print_verbose("voice: heard \"%s\"%s" % [session.text, " (cancelled)" if session.cancelled else ""])
			session.waiter.resolve(null if session.cancelled else session.text)
			# the callbacks hold r, and r holds the callbacks: let go of them
			r.onresult = Callable()
			r.onerror = Callable()
			r.onend = Callable()
		# e.g. start() while a previous session is still shutting down
		if r.start() == false:
			push_warning("voice: could not start")
			rec = null
			return null
		print_verbose("voice: listening ", lang)
		return await session.waiter.wait()

	## Let go: the engine finishes the last phrase, then start() resolves with everything
	func stop() -> void:
		if rec != null:
			rec.stop()

	func cancel() -> void:
		if rec == null:
			return
		_session["cancelled"] = true
		var r = rec
		rec = null
		r.abort()
