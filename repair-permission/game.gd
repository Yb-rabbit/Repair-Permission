extends Control
## Repair Permission -- two-terminal minimal build.
## All dialogue comes from res://script_data.json; the command table is a Dictionary:
## command -> {old, new, cb}

const DATA_PATH := "res://script_data.json"
const POPUP_SCRIPT := preload("res://popup.gd")
const AUDIO_SCRIPT := preload("res://audio.gd")
const UI_FONT := preload("res://ui_font.tres")

# OLD clock: starts at 99-12-31 23:59:50 and rewinds 10s at the midnight boundary.
# 946684780 is 23:59:40 UTC; 946684790 is the requested 23:59:50.
const CLOCK_START_UNIX := 946684790
const CLOCK_MIDNIGHT_UNIX := 946684800
const CLOCK_REWIND := 10
const EPOCH_START := 2147482647
const SCAN_CONFESSION_NEW_DELAY := 4.0
const IDLE_INPUT_MS := 30000
const INHERIT_WINDOW_SEC := 60.0
const INHERIT_CLOCK_TEXT := "1901-12-13 20:45:52"
const INHERIT_EPOCH_TEXT := "EPOCH: -2147483648"
const INHERIT_GLITCH_STEPS := 20
const INHERIT_GLITCH_STEP := 0.05
const INHERIT_GLITCH_CHARS := 360
const GLITCH_POOL := "0123456789ABCDEF:/._-#%$"
const BOOT_TICK := 0.25
const BOOT_SKIP_HINT := "SKIP: ESC"

@onready var old_text: RichTextLabel = $VBox/Mid/OldPanel/OldText
@onready var new_text: RichTextLabel = $VBox/Mid/NewPanel/NewText
@onready var input_line: LineEdit = $VBox/Input
@onready var pump_bar: ProgressBar = $VBox/Bars/PumpBar
@onready var scan_bar: ProgressBar = $VBox/Bars/ScanBar
@onready var bar3: ProgressBar = $VBox/Bars/Bar3
@onready var clock_label: Label = $VBox/Top/ClockLabel
@onready var epoch_label: Label = $VBox/Top/EpochLabel
@onready var crt: ColorRect = $CRT
@onready var final_line: Label = $FinalLine
@onready var restart_hint: Label = $RestartHint
@onready var popup_layer: CanvasLayer = $Popups
@onready var old_timer: Timer = $OldTimer
@onready var boot_timer: Timer = $BootTimer
@onready var scan_timer: Timer = $ScanTimer
@onready var replay_timer: Timer = $ReplayTimer
@onready var end_timer: Timer = $EndTimer
@onready var clock_timer: Timer = $ClockTimer
@onready var inherit_timer: Timer = $InheritTimer

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

var pump_handled := false          # true after --ISOLATE or --ACCEPT-NEW
var pump_gate_logged := false      # soft-gate line already recorded

var replay_index := 0
var ending_lines: Array = []
var ending_index := 0
var ending_key := ""
var in_ending := false
var last_cmd := ""

var clock_unix := CLOCK_START_UNIX
var epoch_value := EPOCH_START
var clock_loops := 0
var last_input_msec := 0
var idle_egg_shown := false

var new_tween: Tween
var _audio

var boot_done := false                 # false -> input hidden, commands ignored
var boot_index := 0
var boot_lines: Array[String] = [
	"REPAIR PERMISSION // NIGHT SHIFT",
	"POST: CPU ................ OK",
	"POST: MEM 640K ........... OK",
	"POST: DISK 40MB .......... OK",
	"POST: KEYBOARD ........... OK",
	"MEM TEST ................. PASS",
	"DISK 0: 40MB ............. READY",
	"RTC SYNC... FAILED",
	"RTC: 99-12-31 23:59:50",
	"USING LAST KNOWN TIME",
	"PATCH-Y2KW .............. MOUNTED",
	"PATCH-Y2KW ... LOADED",
	"TERMINAL BUS ............. 1",
	"1 TERMINAL AVAILABLE",
	"READY.",
	"TWO-TERMINAL MINIMAL BUILD For LD60",
	"BY YibiRabbit007",
]

var _popup: PanelContainer = null      # currently visible hint popup
var _popup_queue: Array[Dictionary] = []
var _hints_seen: Dictionary = {}       # id -> {title, body}; each hint is shown only once
var _hint_order: Array[String] = []    # first-seen order, replayed by MANUAL


func _ready() -> void:
	last_input_msec = Time.get_ticks_msec()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing " + DATA_PATH)
		return
	data = JSON.parse_string(file.get_as_text())
	_init_actions()
	_build_commands()
	_setup_fonts()
	_setup_ui()
	_setup_audio()
	_setup_status_clock()
	old_timer.timeout.connect(_on_old_timeout)
	scan_timer.timeout.connect(_on_scan_tick)
	replay_timer.timeout.connect(_on_replay_tick)
	end_timer.timeout.connect(_on_end_tick)
	inherit_timer.wait_time = INHERIT_WINDOW_SEC
	inherit_timer.one_shot = true
	inherit_timer.timeout.connect(_on_inherit_timeout)
	input_line.text_submitted.connect(_on_submit)
	boot_timer.timeout.connect(_on_boot_tick)
	_start_boot()


# ---------------- Setup ----------------

func _setup_audio() -> void:
	_audio = AUDIO_SCRIPT.new()
	add_child(_audio)


func _setup_fonts() -> void:
	old_text.add_theme_font_override("normal_font", UI_FONT)
	old_text.add_theme_font_size_override("normal_font_size", 16)
	new_text.add_theme_font_override("normal_font", UI_FONT)
	new_text.add_theme_font_size_override("normal_font_size", 17)
	input_line.add_theme_font_override("font", UI_FONT)
	input_line.add_theme_font_size_override("font_size", 16)
	final_line.add_theme_font_override("font", UI_FONT)
	final_line.add_theme_font_size_override("font_size", 24)
	restart_hint.add_theme_font_override("font", UI_FONT)
	restart_hint.add_theme_font_size_override("font_size", 18)


func _setup_ui() -> void:
	old_text.scroll_following = true
	new_text.scroll_following = true
	new_text.visible_characters = -1
	pump_bar.max_value = 100
	scan_bar.max_value = 100
	bar3.max_value = 20
	bar3.value = 0
	input_line.placeholder_text = "Type a command, press Enter"
	input_line.visible = false
	final_line.visible = false
	restart_hint.visible = false
	crt.color = Color(0, 0, 0, 0)


func _prefill_login() -> void:
	# NEW already filled in half the login: Enter auto-completes "LOGIN" to "LOGIN 077".
	input_line.text = "LOGIN"
	input_line.select_all()


# ---------------- Boot sequence: OLD terminal only, one line every BOOT_TICK ----------------

func _start_boot() -> void:
	boot_done = false
	boot_index = 0
	boot_timer.wait_time = BOOT_TICK
	_show_skip_hint()
	boot_timer.start()


func _on_boot_tick() -> void:
	if boot_index >= boot_lines.size():
		_finish_boot()
		return
	_boot_print(boot_lines[boot_index], boot_index == 0)
	boot_index += 1
	if boot_index >= boot_lines.size():
		_finish_boot()


func _boot_print(line: String, small := false) -> void:
	if small:
		old_text.push_font_size(11)
		old_text.push_color(Color("#3f7f4d"))
	else:
		old_text.push_color(Color("#96ffa8"))
	old_text.add_text(line + "\n")
	old_text.pop()
	if small:
		old_text.pop()


func _finish_boot(skip := false) -> void:
	if boot_done:
		return
	boot_timer.stop()
	if skip:
		while boot_index < boot_lines.size():
			_boot_print(boot_lines[boot_index], boot_index == 0)
			boot_index += 1
	boot_done = true
	_hide_skip_hint()
	input_line.visible = true
	_prefill_login()
	input_line.grab_focus()
	_audio.on_boot_done()
	_old_say(data.boot.old)
	_new_say(str(data.boot.new))
	_show_boot_hint()


func _show_skip_hint() -> void:
	# Reuse the ending's restart hint as the bottom-right boot hint (no new UI nodes).
	restart_hint.text = BOOT_SKIP_HINT
	restart_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	restart_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	restart_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	restart_hint.offset_left = -170.0
	restart_hint.offset_top = -42.0
	restart_hint.offset_right = -22.0
	restart_hint.offset_bottom = -18.0
	restart_hint.add_theme_font_size_override("font_size", 12)
	restart_hint.modulate = Color(1, 1, 1, 0.55)
	restart_hint.visible = true


func _hide_skip_hint() -> void:
	restart_hint.visible = false
	restart_hint.text = "PRESS R TO RESTART"
	restart_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	restart_hint.set_anchors_preset(Control.PRESET_CENTER)
	restart_hint.offset_left = -250.0
	restart_hint.offset_top = 72.0
	restart_hint.offset_right = 250.0
	restart_hint.offset_bottom = 108.0
	restart_hint.add_theme_font_size_override("font_size", 18)
	restart_hint.modulate = Color(1, 1, 1, 1)


# ---------------- Status clock / epoch ----------------

func _setup_status_clock() -> void:
	_refresh_status_labels()
	clock_timer.timeout.connect(_on_clock_tick)
	clock_timer.start()


func _on_clock_tick() -> void:
	clock_unix += 1
	# 23:59:59 -> 00:00:00 would cross midnight; rewind 10s to 23:59:50 instead.
	if clock_unix >= CLOCK_MIDNIGHT_UNIX:
		clock_unix -= CLOCK_REWIND
		clock_loops += 1
	epoch_value -= 1
	_refresh_status_labels()
	_check_idle_egg()


func _refresh_status_labels() -> void:
	var dt := Time.get_datetime_dict_from_unix_time(clock_unix)
	clock_label.text = "%02d-%02d-%02d %02d:%02d:%02d" % [
		int(dt.year) % 100, int(dt.month), int(dt.day),
		int(dt.hour), int(dt.minute), int(dt.second),
	]
	epoch_label.text = "EPOCH: %d" % epoch_value


func _check_idle_egg() -> void:
	if idle_egg_shown or in_ending or not scan_timer.is_stopped():
		return
	if clock_loops < 3:
		return
	if Time.get_ticks_msec() - last_input_msec < IDLE_INPUT_MS:
		return
	idle_egg_shown = true
	_old_say(data.idle.old)
	_new_say(str(data.idle.new))


func _init_actions() -> void:
	actions = {
		"none": _act_none,
		"pump": _act_pump,
		"isolate": _act_isolate,
		"accept": _act_accept,
		"scan_full": _act_scan_full,
		"kill": _act_kill,
		"date_auto": _act_date_auto,
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
	if not boot_done or in_ending:
		return
	if text == "":
		return
	last_input_msec = Time.get_ticks_msec()
	# Any real input cancels the KILL 077 inheritance window.
	inherit_timer.stop()
	_audio.on_player_input()
	_audio.on_submit()

	var cmd := text.to_upper()
	history.append(cmd)
	_old_print("> " + cmd, true)

	# During a scan, every keystroke only earns a DELETED line
	if not scan_timer.is_stopped():
		_old_print("[ DELETED ]", true)
		return

	var resolved := cmd
	var completed := false
	if not commands.has(cmd):
		# SET DATE accepts free-form dates; exact SET DATE --AUTO is handled above.
		if cmd.begins_with("SET DATE "):
			last_cmd = cmd
			_handle_set_date(cmd.substr(9).strip_edges())
			return
		resolved = ""
		for key in commands:
			if cmd.length() >= 2 and str(key).begins_with(cmd):
				if resolved == "" or str(key).length() < resolved.length():
					resolved = str(key)
		if resolved == "":
			_junk()
			return
		completed = true

	# Lock all endings until the full scan has exposed /VOID.
	if not scan_done and (resolved == "FORMAT /VOID" or resolved == "SHUTDOWN --VERIFY"):
		_old_say(["UNKNOWN PARTITION."])
		return

	if completed:
		_new_say("I completed that to " + resolved + " for you. Running it :)")
		_old_say(["PARTIAL MATCH", "MEANT " + _clip(resolved, 9)])
	_run(resolved)


func _handle_set_date(value: String) -> void:
	var parts := value.split("-")
	if parts.size() == 3:
		var year_text := str(parts[0])
		var month_text := str(parts[1])
		var day_text := str(parts[2])
		if year_text.is_valid_int() and month_text.is_valid_int() and day_text.is_valid_int():
			var year := int(year_text)
			if int(month_text) == 1 and int(day_text) == 19:
				if year_text.length() == 4 and year == 2038:
					_trigger_ending_c()
					return
				if year_text.length() == 2 and year == 38:
					# Windowed years 00-49 mean 20xx, so "38" is the same 2038 overflow.
					_new_say("You used the same two-digit year they did :) Same result.")
					_trigger_ending_c()
					return
	_old_say(["DATE ACCEPTED.", "RTC WRITTEN."])


func _run(cmd: String) -> void:
	last_cmd = cmd
	var entry: Dictionary = commands[cmd]
	_new_say(_new_text_for(cmd))
	_old_say(entry.old)
	var cb: Callable = entry.cb
	cb.call()
	if cmd == "LOGIN 077":
		_audio.play_chime()
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
	_audio.on_old_print(dim)
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
	_audio.on_new_say()
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
	pump_handled = true
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 60.0, 2.0)


func _act_accept() -> void:
	pump_handled = true
	_audio.on_accept_new()
	temp += 2                            # hidden stat: no hint at all
	bar3.value = temp
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 100.0, 1.5)


func _act_date_auto() -> void:
	temp += 2
	bar3.value = temp


func _act_kill() -> void:
	void_killed = true
	_audio.on_kill()
	inherit_timer.start()


func _act_scan_full() -> void:
	if scan_done or not scan_timer.is_stopped():
		return
	_audio.on_scan_start()
	scan_time = 0.0
	scan_stage = 0
	scan_bar.value = 0
	# Soft gate: scanning still runs, but OLD records the untouched pump once.
	if not pump_handled and not pump_gate_logged:
		pump_gate_logged = true
		var note := "PUMP UNSERVICED. LOGGED."
		history.append("* " + note)      # "* " marks an OLD record, not player input
		_old_say([note])
	scan_timer.start()


func _act_format() -> void:
	_begin_ending("format")


func _act_shutdown() -> void:
	_begin_ending("shutdown")


func _trigger_ending_c() -> void:
	if in_ending:
		return
	if not scan_done:
		_old_say(["RTC WRITE REFUSED.", "FULL SCAN REQUIRED."])
		return
	inherit_timer.stop()
	_begin_ending("inherit")


func _on_inherit_timeout() -> void:
	# The silent KILL window only counts once the full scan has exposed /VOID.
	if in_ending or not scan_done:
		return
	_trigger_ending_c()


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
		var scan_old: Array = ["SCAN DONE", "VOL 3 /VOID", "SIZE 077 GB", "MOUNTED 1979"]
		scan_old.append(str(data.scan_complete.old[0]))
		_old_say(scan_old)
		epoch_label.visible = true
		_hint_scan()
		_hint_for("SCAN /FULL")
		_scan_confession()


func _scan_confession() -> void:
	await get_tree().create_timer(SCAN_CONFESSION_NEW_DELAY).timeout
	if not is_inside_tree() or in_ending:
		return
	_new_say(str(data.scan_complete.new))


# ---------------- Ending: line-by-line replay + ending ----------------

func _begin_ending(key: String) -> void:
	if in_ending:
		return
	in_ending = true
	ending_key = key
	_audio.on_ending_start()
	replay_index = 0
	inherit_timer.stop()
	scan_timer.stop()
	_clear_popups()
	old_timer.stop()
	pending_old.clear()
	input_line.editable = false
	input_line.release_focus()
	input_line.placeholder_text = "Ending in progress · press R to restart"
	restart_hint.visible = false
	if key == "inherit":
		clock_timer.stop()
		_inherit_intro()
		return
	_old_print("[ LOG REPLAY ]", true)
	replay_timer.start()


func _inherit_intro() -> void:
	clock_label.text = INHERIT_CLOCK_TEXT
	epoch_label.visible = true
	epoch_label.text = INHERIT_EPOCH_TEXT
	for i in INHERIT_GLITCH_STEPS:
		if not is_inside_tree() or ending_key != "inherit":
			return
		_set_glitch_text(old_text, Color("#96ffa8"))
		_set_glitch_text(new_text, Color("#6fd7ff"))
		await get_tree().create_timer(INHERIT_GLITCH_STEP).timeout
	if not is_inside_tree() or ending_key != "inherit":
		return
	old_text.clear()
	new_text.clear()
	_old_print("[ CLOCK OVERFLOW ]", true)
	_old_print("[ PATCH REPLAY ]", true)
	_new_say("Your last commands are still in memory. I'll patch them in order.")
	replay_timer.start()


func _set_glitch_text(label: RichTextLabel, color: Color) -> void:
	label.clear()
	label.push_color(color)
	label.add_text(_glitch_text(INHERIT_GLITCH_CHARS))
	label.pop()


func _glitch_text(length: int) -> String:
	var out := ""
	for i in length:
		out += GLITCH_POOL.substr(randi() % GLITCH_POOL.length(), 1)
	return out


func _on_replay_tick() -> void:
	if replay_index < history.size():
		var entry := history[replay_index]
		var prefix := "[PATCH] " if ending_key == "inherit" else "> "
		if entry.begins_with("* "):
			_old_print(entry.substr(2), true)   # OLD record: dim, no input prompt
		else:
			_old_print(prefix + entry, true)
		replay_index += 1
		return
	replay_timer.stop()
	ending_lines = data.endings[ending_key]
	ending_index = 0
	_old_print("[ PATCH COMPLETE ]" if ending_key == "inherit" else "[ REPLAY END ]", true)
	end_timer.start()


func _on_end_tick() -> void:
	if ending_index >= ending_lines.size():
		end_timer.stop()
		_audio.on_ending_complete()
		return
	var line := str(ending_lines[ending_index])
	ending_index += 1
	if line.begins_with("OLD> "):
		_old_print(line.substr(5))
	elif line.begins_with("NEW> "):
		_new_say(line.substr(5))
	elif line.begins_with("BLACK> "):
		_show_black_screen()
	elif line.begins_with("FINAL> "):
		_show_final_line(line.substr(7))
	else:
		_old_print(line, true)


func _show_black_screen() -> void:
	crt.color = Color(0, 0, 0, 1)
	restart_hint.visible = true
	_audio.on_black_screen()


func _show_final_line(text: String) -> void:
	final_line.text = text
	final_line.visible = true
	restart_hint.visible = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if not boot_done:
		if event.keycode == KEY_ESCAPE:
			_finish_boot(true)
		return
	if in_ending and event.keycode == KEY_R:
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
		"SCAN /FULL":
			if scan_done:
				_hint("scan_y2k", "Night Shift Manual 06 · 32-Bit Ceiling", "[color=#8fe3ff]A signed 32-bit Unix timestamp maxes out at 2147483647.[/color]\nThat is [color=#8fe3ff]2038-01-19 03:14:07[/color].\n\nY2K did not remove the limit. It used a two-digit year window: 00-49 -> 20xx, 50-99 -> 19xx. The patch only moved the same rollover further away.\n\n[color=#8fe3ff]EPOCH → 2147483647 = 2038-01-19 03:14:07[/color]\n\n[color=#8fe3ff]The RTC will accept a date it cannot represent.[/color] It does not validate the 32-bit ceiling.")
		"CAT /VOID/TECH-077":
			# Reading the file first must not skip page 04; queue the scan page before page 05.
			if not _hints_seen.has("scan"):
				_hint_scan()
			_hint("cat", "Night Shift Manual 05 · You Already Saw It", "[color=#8fe3ff]KILL 077[/color] can end that process (the two machines will give two different answers).\n\nThere are two documented ways out: [color=#8fe3ff]FORMAT /VOID[/color] or [color=#8fe3ff]SHUTDOWN --VERIFY[/color].\nEither one is fine -- but remember what you just saw with your own eyes.")


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

