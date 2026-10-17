extends Control
## Repair Permission -- two-terminal minimal build.
## All dialogue comes from res://script_data.json; the command table is a Dictionary:
## command -> {old, new, cb}

const DATA_PATH := "res://script_data.json"
const POPUP_SCRIPT := preload("res://popup.gd")
const UI_FONT := preload("res://ui_font.tres")

@onready var old_text: RichTextLabel = $VBox/Mid/OldPanel/OldText
@onready var new_text: RichTextLabel = $VBox/Mid/NewPanel/NewText
@onready var input_line: LineEdit = $VBox/Input
@onready var pump_bar: ProgressBar = $VBox/Bars/PumpBar
@onready var scan_bar: ProgressBar = $VBox/Bars/ScanBar
@onready var bar3: ProgressBar = $VBox/Bars/Bar3
@onready var popup_layer: CanvasLayer = $Popups
@onready var old_timer: Timer = $OldTimer
@onready var scan_timer: Timer = $ScanTimer
@onready var replay_timer: Timer = $ReplayTimer
@onready var end_timer: Timer = $EndTimer

var data: Dictionary = {}
var commands: Dictionary = {}          # "PUMP 3" -> {"old": Array, "new": String, "cb": Callable}
var actions: Dictionary = {}           # "accept" -> Callable

var history: Array[String] = []        # every player input, replayed at the ending
var pending_old: Array[String] = []    # delayed output queue for OLD
var junk_count := 0
var temp := 0                          # hidden stat: +2 each time NEW decides for you
var void_killed := false

var scan_time := 0.0
var scan_duration := 15.0
var scan_stage := 0
var scan_done := false

var replay_index := 0
var ending_lines: Array = []
var ending_index := 0
var ending_key := ""
var in_ending := false
var last_cmd := ""

var new_tween: Tween

var _popup: PanelContainer = null      # currently visible hint popup
var _popup_queue: Array[Dictionary] = []
var _hints_seen: Dictionary = {}       # id -> {title, body}; each hint is shown only once
var _hint_order: Array[String] = []    # first-seen order, replayed by MANUAL


func _ready() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing " + DATA_PATH)
		return
	data = JSON.parse_string(file.get_as_text())
	_init_actions()
	_build_commands()
	_setup_fonts()
	_setup_ui()
	old_timer.timeout.connect(_on_old_timeout)
	scan_timer.timeout.connect(_on_scan_tick)
	replay_timer.timeout.connect(_on_replay_tick)
	end_timer.timeout.connect(_on_end_tick)
	input_line.text_submitted.connect(_on_submit)
	input_line.grab_focus()
	_old_say(data.boot.old)
	_new_say(str(data.boot.new))
	_show_boot_hint()


# ---------------- Setup ----------------

func _setup_fonts() -> void:
	old_text.add_theme_font_override("normal_font", UI_FONT)
	old_text.add_theme_font_size_override("normal_font_size", 16)
	new_text.add_theme_font_override("normal_font", UI_FONT)
	new_text.add_theme_font_size_override("normal_font_size", 17)
	input_line.add_theme_font_override("font", UI_FONT)
	input_line.add_theme_font_size_override("font_size", 16)


func _setup_ui() -> void:
	old_text.scroll_following = true
	new_text.scroll_following = true
	new_text.visible_characters = -1
	pump_bar.max_value = 100
	scan_bar.max_value = 100
	bar3.max_value = 20
	bar3.value = 0
	input_line.placeholder_text = "Type a command, press Enter"
	# NEW already filled in half the login: Enter auto-completes "LOGIN" to "LOGIN 077".
	input_line.text = "LOGIN"
	input_line.select_all()


func _init_actions() -> void:
	actions = {
		"none": _act_none,
		"pump": _act_pump,
		"isolate": _act_isolate,
		"accept": _act_accept,
		"scan_full": _act_scan_full,
		"kill": _act_kill,
		"format": _act_format,
		"shutdown": _act_shutdown,
		"manual": _act_manual,
	}


func _build_commands() -> void:
	for key in data.commands:
		var c: Dictionary = data.commands[key]
		commands[str(key)] = {
			"old": c.old,
			"new": str(c.new),
			"cb": actions.get(str(c.action), _act_none),
		}


# ---------------- Input: three-tier matching ----------------

func _on_submit(raw: String) -> void:
	var text := raw.strip_edges()
	input_line.clear()
	if in_ending:
		return
	if text == "":
		return

	var cmd := text.to_upper()
	history.append(cmd)
	_old_print("> " + cmd, true)

	# During a scan, every keystroke only earns a DELETED line
	if not scan_timer.is_stopped():
		_old_print("[ DELETED ]", true)
		return

	if commands.has(cmd):
		_run(cmd)
		return

	var full := ""
	for key in commands:
		if cmd.length() >= 2 and str(key).begins_with(cmd):
			if full == "" or str(key).length() < full.length():
				full = str(key)
	if full != "":
		_new_say("I completed that to " + full + " for you. Running it :)")
		_old_say(["PARTIAL MATCH", "MEANT " + _clip(full, 9)])
		_run(full)
		return

	_junk()


func _run(cmd: String) -> void:
	last_cmd = cmd
	var entry: Dictionary = commands[cmd]
	_new_say(_new_text_for(cmd))
	_old_say(entry.old)
	var cb: Callable = entry.cb
	cb.call()
	_hint_for(cmd)


func _new_text_for(cmd: String) -> String:
	if cmd == "LS /VOID" and void_killed:
		return str(data.alt.ls_after_kill)
	return str(commands[cmd].new)


func _junk() -> void:
	junk_count += 1
	_new_say(str(data.ambient.new.pick_random()))
	if junk_count == 3:
		_old_say(data.egg)
	elif junk_count == 2:
		_old_say(["LOGGED " + _clock()])
	else:
		_old_say(data.ambient.old)


func _clip(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len)


func _clock() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d" % [t.hour, t.minute]


# ---------------- Output for both terminals ----------------

func _old_say(lines: Array) -> void:
	if lines.is_empty():
		return
	if pending_old.is_empty():
		_old_print("...", true)          # lag effect: one ellipsis line first
	for line in lines:
		pending_old.append(str(line).replace("{clock}", _clock()))
	if old_timer.is_stopped():
		old_timer.start()


func _on_old_timeout() -> void:
	for line in pending_old:
		_old_print(line)
	pending_old.clear()


func _old_print(text: String, dim := false) -> void:
	old_text.push_color(Color("#3f7f4d") if dim else Color("#96ffa8"))
	old_text.add_text(text + "\n")
	old_text.pop()


func _new_say(text: String) -> void:
	if new_tween and new_tween.is_valid():
		new_tween.kill()
	new_text.visible_characters = -1
	var start := new_text.get_total_character_count()
	new_text.add_text(text + "\n\n")
	var total := new_text.get_total_character_count()
	if total <= start:
		return
	new_text.visible_characters = start
	new_tween = create_tween()
	new_tween.tween_property(new_text, "visible_characters", total, float(total - start) * 0.012)


# ---------------- Command callbacks ----------------

func _act_none() -> void:
	pass


func _act_manual() -> void:
	if in_ending:
		return
	# Re-queue hints in the order the player first saw them; unseen pages stay hidden.
	var replay: Array[Dictionary] = []
	for id in _hint_order:
		var seen: Dictionary = _hints_seen.get(id, {})
		replay.append({"id": id, "title": seen.get("title", ""), "body": seen.get("body", "")})
	if replay.is_empty():
		return
	_hints_seen.clear()
	_hint_order.clear()
	for item in replay:
		_hint(str(item.id), str(item.title), str(item.body))


func _act_pump() -> void:
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 40.0, 1.0)


func _act_isolate() -> void:
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 60.0, 2.0)


func _act_accept() -> void:
	temp += 2                            # hidden stat: no hint at all
	bar3.value = temp
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 100.0, 1.5)


func _act_kill() -> void:
	void_killed = true


func _act_scan_full() -> void:
	if scan_done or not scan_timer.is_stopped():
		return
	scan_time = 0.0
	scan_stage = 0
	scan_bar.value = 0
	scan_timer.start()


func _act_format() -> void:
	_begin_ending("format")


func _act_shutdown() -> void:
	_begin_ending("shutdown")


# ---------------- SCAN /FULL: 15 seconds + NEW cuts in twice ----------------

func _on_scan_tick() -> void:
	scan_time += scan_timer.wait_time
	scan_bar.value = clampf(scan_time / scan_duration * 100.0, 0.0, 100.0)
	if scan_stage == 0 and scan_time >= scan_duration / 3.0:
		scan_stage = 1
		_new_say("Ten seconds to go. I already have the result. Want a peek? :)")
	elif scan_stage == 1 and scan_time >= scan_duration * 2.0 / 3.0:
		scan_stage = 2
		_new_say("Hey, the old screen just scanned you too. Even more thoroughly than I did.")
	elif scan_time >= scan_duration:
		scan_timer.stop()
		scan_stage = 3
		scan_done = true
		scan_bar.value = 100.0
		_new_say("All done. There's something in /VOID called TECH-077.")
		_old_say(["SCAN DONE", "VOL 3 /VOID", "SIZE 077 GB", "MOUNTED 1979"])
		_hint_scan()


# ---------------- Ending: line-by-line replay + ending ----------------

func _begin_ending(key: String) -> void:
	if in_ending:
		return
	in_ending = true
	ending_key = key
	replay_index = 0
	_clear_popups()
	old_timer.stop()
	pending_old.clear()
	input_line.editable = false
	input_line.release_focus()
	input_line.placeholder_text = "Ending in progress · press R to restart"
	_old_print("[ LOG REPLAY ]", true)
	replay_timer.start()


func _on_replay_tick() -> void:
	if replay_index < history.size():
		_old_print("> " + history[replay_index], true)
		replay_index += 1
		return
	replay_timer.stop()
	ending_lines = data.endings[ending_key]
	ending_index = 0
	_old_print("[ REPLAY END ]", true)
	end_timer.start()


func _on_end_tick() -> void:
	if ending_index >= ending_lines.size():
		end_timer.stop()
		return
	var line := str(ending_lines[ending_index])
	ending_index += 1
	if line.begins_with("OLD> "):
		_old_print(line.substr(5))
	elif line.begins_with("NEW> "):
		_new_say(line.substr(5))
	else:
		_old_print(line, true)


func _unhandled_key_input(event: InputEvent) -> void:
	if in_ending and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()


# ---------------- Hint popups: draggable / closable / confirmable ----------------

func _hint(id: String, title: String, body: String) -> void:
	if in_ending or _hints_seen.has(id):
		return
	_hints_seen[id] = {"title": title, "body": body}
	_hint_order.append(id)
	_popup_queue.append({"title": title, "body": body})
	_pump_popup()


func _hint_scan() -> void:
	_hint("scan", "Night Shift Manual 04 · Hidden Partition", "[color=#8fe3ff]Scan complete. /VOID is the hidden partition.[/color]\n\nTry [color=#8fe3ff]LS /VOID[/color], [color=#8fe3ff]PS[/color], [color=#8fe3ff]CAT /VOID/TECH-077[/color].\nThe two machines may report different counts. Remember the one you saw with your own eyes.")


func _hint_for(cmd: String) -> void:
	match cmd:
		"LOGIN 077":
			_hint("login", "Night Shift Manual 02 · Logged In", "Operator [color=#8fe3ff]TECH-077[/color], night shift, shift 1/1.\n\nIf you want the machine's side of the story, type [color=#8fe3ff]LOG[/color].\nNext: type [color=#8fe3ff]PUMP 3[/color] and take a look at pump 3.")
		"PUMP 3":
			_hint("pump3", "Night Shift Manual 03 · Two Paths", "[color=#8fe3ff]PUMP 3 --ISOLATE[/color] -- OLD's mechanical isolation. Slow, but every step leaves a paper trail.\n[color=#8fe3ff]PUMP 3 --ACCEPT-NEW[/color] -- NEW's remote repair. Fast, and it writes the record.\n\nBoth paths move you forward, but the records differ. Check [color=#8fe3ff]STATUS[/color] before you choose.\nWhen the pump is settled, run [color=#8fe3ff]SCAN /FULL[/color] and see what else is on this machine.")
		"CAT /VOID/TECH-077":
			# Reading the file first must not skip page 04; queue the scan page before page 05.
			if not _hints_seen.has("scan"):
				_hint_scan()
			_hint("cat", "Night Shift Manual 05 · You Already Saw It", "[color=#8fe3ff]KILL 077[/color] can end that process (the two machines will give two different answers).\n\nThere are only two ways out: [color=#8fe3ff]FORMAT /VOID[/color] or [color=#8fe3ff]SHUTDOWN --VERIFY[/color].\nEither one is fine -- but remember what you just saw with your own eyes.")


func _show_boot_hint() -> void:
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree() or in_ending:
		return
	_hint("boot", "Night Shift Manual 01 · Objective", "[color=#8fe3ff]Find out why pump 3 started by itself in the middle of the night.[/color]\n\n· Commands are case-insensitive. Type [color=#8fe3ff]HELP[/color] to see them all.\n· Typing just the first few letters works too; press Enter to auto-complete.\n· Type [color=#8fe3ff]MANUAL[/color] to reopen these pages; [color=#8fe3ff]ID[/color] tells you who you are.\n· Drag this window by its title bar, close it with ×, or press ESC.")


func _pump_popup() -> void:
	if in_ending or is_instance_valid(_popup) or _popup_queue.is_empty():
		return
	var item: Dictionary = _popup_queue.pop_front()
	var p: PanelContainer = POPUP_SCRIPT.new()
	popup_layer.add_child(p)
	p.open(str(item.title), str(item.body))
	p.closed.connect(_on_popup_closed.bind(p))
	_popup = p


func _on_popup_closed(p: Node) -> void:
	if _popup == p:
		_popup = null
	await get_tree().create_timer(0.35).timeout
	if is_inside_tree():
		_pump_popup()


func _clear_popups() -> void:
	_popup_queue.clear()
	var current := _popup
	_popup = null
	if is_instance_valid(current):
		current.close()

