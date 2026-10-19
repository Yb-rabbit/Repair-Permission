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
const GUIDE_IDLE_SEC := 20.0
const INHERIT_WINDOW_SEC := 60.0
const INHERIT_CLOCK_TEXT := "1901-12-13 20:45:52"
const INHERIT_EPOCH_TEXT := "EPOCH: -2147483648"
const INHERIT_GLITCH_STEPS := 20
const INHERIT_GLITCH_STEP := 0.05
const INHERIT_GLITCH_CHARS := 360
const GLITCH_POOL := "0123456789ABCDEF:/._-#%$"
const SCAN_FOUND_RATIO := 0.74
const SCAN_REWIND_RATIO := 0.87
const SCAN_REWIND_VALUE := 97.0
const SCAN_STREAM_STEP_RATIO := 0.06
const BOOT_TICK := 0.25
const BOOT_INTRO_HOLD := 2.0  # title hold; full cold start lands at about 3s
const BOOT_SKIP_HINT := "SKIP: ESC"
const BOOT_INTRO_TITLE := "REPAIR PERMISSION"
const BOOT_INTRO_SUB := "NIGHT SHIFT TERMINAL // COLD START"
const BOOT_INTRO_STATUS := "POST // MEM 640K // RTC ???"
const END_STATUS_TEXT := "SHIFT ENDED"
const END_FADE_TIME := 0.9
const END_HINT_DELAY := 0.25
const END_DIM_ALPHA := 0.75   # A/B keep the terminal faintly visible underneath
const END_BLACK_ALPHA := 1.0  # C drops to full black
const INPUT_MAX_LENGTH := 80
const COMMAND_HISTORY_MAX := 50
const ENDING_COMMANDS := ["FORMAT /VOID", "SHUTDOWN --VERIFY"]
# §8 dynamic threats: OLD's delay is a state readout, not a fixed timer.
const OLD_DELAY_BASE := 3.0
const OLD_DELAY_DANGER := 5.0
const OLD_DELAY_NEW_PATH := 8.0
const OLD_DELAY_ENDING_WINDOW := 2.0
const OLD_ENDING_WINDOW := 2.0
const BACKSPACE_REVEAL := 5
const SCAN_BAND_HEIGHT := 2.0
const SCAN_BAND_TIME := 1.25
const KILL_GLITCH_TIME := 0.5
const KILL_GLITCH_CHARS := 900
const KILL_GLITCH_LINE := 72
# Completion is a service, not a spoiler. Commands are revealed in the same order
# the story reveals them: scan first, then CAT /VOID/TECH-077.
const COMPLETION_HIDDEN_BEFORE_SCAN := [
	"LS /VOID", "PS", "CAT /VOID/TECH-077",
	"KILL 077", "FORMAT /VOID", "SHUTDOWN --VERIFY",
]
const COMPLETION_HIDDEN_BEFORE_CAT := [
	"KILL 077", "FORMAT /VOID", "SHUTDOWN --VERIFY",
]

@onready var old_text: RichTextLabel = $VBox/Mid/OldPanel/OldText
@onready var new_text: RichTextLabel = $VBox/Mid/NewPanel/NewText
@onready var input_line: LineEdit = $VBox/Input
@onready var completion_label: Label = $VBox/Input/Completion
@onready var pump_bar: ProgressBar = $VBox/Bars/PumpBar
@onready var scan_bar: ProgressBar = $VBox/Bars/ScanBar
@onready var bar3: ProgressBar = $VBox/Bars/Bar3
@onready var clock_label: Label = $VBox/Top/ClockLabel
@onready var epoch_label: Label = $VBox/Top/EpochLabel
@onready var crt: ColorRect = $CRT
@onready var scan_band: ColorRect = $ScanBand
@onready var glitch_text: RichTextLabel = $Glitch
@onready var end_status: Label = $EndStatus
@onready var end_tag: Label = $EndTag
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
var compact_commands: Dictionary = {}  # "PUMP3" -> "PUMP 3"; whitespace-insensitive matching
var actions: Dictionary = {}           # "accept" -> Callable

var history: Array[String] = []        # every player input + OLD "* " records, replayed at the ending
var command_history: Array[String] = []  # only real player input, for Up/Down recall
var pending_old: Array[String] = []    # delayed output queue for OLD
var junk_count := 0
var temp := 0                          # hidden stat: +2 each time NEW decides for you
var logged_in := false                 # LOGIN resolved, including the prefilled "LOGIN" prefix
var void_killed := false

var history_cursor := -1               # -1 = not browsing history
var history_draft := ""                # text restored after the newest history entry
var completion_candidates: Array[String] = []
var completion_index := 0
var _programmatic_input := false       # text_changed is ours, not the player typing

var scan_time := 0.0
var scan_duration := 15.0
var scan_stage := 0
var scan_done := false
var scan_found := false
var scan_rewound := false
var scan_stream_index := 0

var pump_handled := false          # true after --ISOLATE or --ACCEPT-NEW
var pump_gate_logged := false      # soft-gate line already recorded
var pump_choice := ""              # "", "isolate" or "accept"
var read_cat := false              # player opened /VOID/TECH-077
var saw_that := false              # KILL 077 one-shot line already delivered
var _fake07_seen := false          # fake manual 07 already queued/shown
var fake07_delay := 8.0            # seconds after the first KILL; tests shorten this
var old_delay_override := -1.0      # smoke tests pin this; production uses the state readout
var backspace_count := 0
var hesitation_shown := false
var input_assimilated := false
var auth_requested := false
var kill_glitch_played := false

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
var last_activity_msec := 0
var guide_idle_seconds := GUIDE_IDLE_SEC
var idle_egg_shown := false

var new_tween: Tween
var black_tween: Tween
var scan_band_tween: Tween
var _audio

# Cold-start overlay. It is built in code so Main.tscn stays the terminal layout.
var _boot_layer: CanvasLayer
var _boot_intro: Control
var _boot_line: ColorRect
var _boot_sweep: ColorRect
var _boot_title: Label
var _boot_sub: Label
var _boot_status: Label
var _boot_tag: Label
var _boot_skip: Label
var _boot_intro_tween: Tween
var _boot_intro_token := 0

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

var _popup: PanelContainer = null      # currently visible manual popup
var _guide_popup: PanelContainer = null  # highest-priority guidance popup, independent lane
var _popup_queue: Array[Dictionary] = []
var _popup_after := ""                 # optional narration to run when the current popup closes
var _hints_seen: Dictionary = {}       # id -> {title, body}; each hint is shown only once
var _hint_order: Array[String] = []    # first-seen order, replayed by MANUAL


func _ready() -> void:
	last_input_msec = Time.get_ticks_msec()
	last_activity_msec = last_input_msec
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
	input_line.text_changed.connect(_on_input_text_changed)
	input_line.gui_input.connect(_on_input_gui_input)
	input_line.focus_exited.connect(_hide_completion)
	input_line.resized.connect(_refresh_completion)
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
	completion_label.add_theme_font_override("font", UI_FONT)
	completion_label.add_theme_font_size_override("font_size", 14)
	completion_label.add_theme_color_override("font_color", Color(0.435294, 0.843137, 1, 0.42))
	final_line.add_theme_font_override("font", UI_FONT)
	final_line.add_theme_font_size_override("font_size", 24)
	end_tag.add_theme_font_override("font", UI_FONT)
	end_tag.add_theme_font_size_override("font_size", 14)
	restart_hint.add_theme_font_override("font", UI_FONT)
	restart_hint.add_theme_font_size_override("font_size", 18)
	glitch_text.add_theme_font_override("normal_font", UI_FONT)
	glitch_text.add_theme_font_size_override("normal_font_size", 14)


func _setup_ui() -> void:
	old_text.scroll_following = true
	new_text.scroll_following = true
	new_text.visible_characters = -1
	pump_bar.max_value = 100
	scan_bar.max_value = 100
	bar3.max_value = 4.0
	bar3.value = 0
	bar3.modulate.a = 0.0
	input_line.placeholder_text = "Type a command · Tab completes · Enter runs"
	input_line.max_length = INPUT_MAX_LENGTH
	# A terminal prompt stays ready after Enter. Without this, LineEdit releases
	# editing on text_submitted and the next command starts from a blurred input.
	input_line.keep_editing_on_text_submit = true
	input_line.visible = false
	completion_label.visible = false
	completion_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	final_line.visible = false
	end_tag.visible = false
	restart_hint.visible = false
	crt.color = Color(0, 0, 0, 0)
	scan_band.visible = false
	glitch_text.visible = false
	_build_boot_intro()


func _build_boot_intro() -> void:
	_boot_layer = CanvasLayer.new()
	_boot_layer.layer = 5
	add_child(_boot_layer)

	_boot_intro = Control.new()
	_boot_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot_intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boot_layer.add_child(_boot_intro)

	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boot_intro.add_child(black)

	# A thin green beam expands from the centre, like a CRT finding its raster.
	_boot_line = ColorRect.new()
	_boot_line.color = Color(0.588235, 1, 0.658824, 0.92)
	_boot_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot_line.set_anchors_preset(Control.PRESET_CENTER)
	_boot_line.offset_left = -1.0
	_boot_line.offset_top = -1.0
	_boot_line.offset_right = 1.0
	_boot_line.offset_bottom = 1.0
	_boot_line.modulate.a = 0.0
	_boot_intro.add_child(_boot_line)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boot_intro.add_child(center)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	_boot_title = _make_boot_label(BOOT_INTRO_TITLE, 34, Color(0.588235, 1, 0.658824, 1))
	_boot_title.add_theme_color_override("font_outline_color", Color(0.588235, 1, 0.658824, 0.18))
	_boot_title.add_theme_constant_override("outline_size", 3)
	_boot_title.modulate.a = 0.0
	box.add_child(_boot_title)

	var rule := ColorRect.new()
	rule.color = Color(0.588235, 1, 0.658824, 0.34)
	rule.custom_minimum_size = Vector2(300, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	_boot_sub = _make_boot_label(BOOT_INTRO_SUB, 12, Color(0.376471, 0.705882, 0.443137, 1))
	_boot_sub.modulate.a = 0.0
	box.add_child(_boot_sub)

	_boot_status = _make_boot_label(BOOT_INTRO_STATUS, 10, Color(0.588235, 1, 0.658824, 0.7))
	_boot_status.modulate.a = 0.0
	box.add_child(_boot_status)

	_boot_tag = _make_boot_label("LD60 // BOOT ROM", 10, Color(0.376471, 0.705882, 0.443137, 1))
	_boot_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boot_tag.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_boot_tag.offset_left = 24.0
	_boot_tag.offset_top = 18.0
	_boot_tag.offset_right = 260.0
	_boot_tag.offset_bottom = 38.0
	_boot_tag.modulate.a = 0.0
	_boot_intro.add_child(_boot_tag)

	_boot_skip = _make_boot_label("ESC // SKIP", 11, Color(0.588235, 1, 0.658824, 0.8))
	_boot_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boot_skip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_boot_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_boot_skip.offset_left = -180.0
	_boot_skip.offset_top = -42.0
	_boot_skip.offset_right = -24.0
	_boot_skip.offset_bottom = -18.0
	_boot_skip.modulate.a = 0.0
	_boot_intro.add_child(_boot_skip)

	# Very faint interference sweep; it crosses the title during the power-on.
	_boot_sweep = ColorRect.new()
	_boot_sweep.color = Color(0.588235, 1, 0.658824, 0.04)
	_boot_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot_sweep.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_boot_sweep.offset_top = 0.0
	_boot_sweep.offset_bottom = 2.0
	_boot_intro.add_child(_boot_sweep)

	_boot_intro.visible = false


func _make_boot_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _prefill_login() -> void:
	# NEW already filled in half the login: Enter auto-completes "LOGIN" to "LOGIN 077".
	input_line.text = "LOGIN"
	input_line.select_all()
	_refresh_completion()


# ---------------- Boot sequence: OLD terminal only, one line every BOOT_TICK ----------------

func _start_boot() -> void:
	boot_done = false
	boot_index = 0
	boot_timer.wait_time = BOOT_TICK
	_show_skip_hint()
	if _audio:
		_audio.play_relay()
	_boot_intro_token += 1
	_play_boot_intro(_boot_intro_token)


func _play_boot_intro(token: int) -> void:
	if _boot_intro == null:
		boot_timer.start()
		return
	if _boot_intro_tween and _boot_intro_tween.is_valid():
		_boot_intro_tween.kill()
	var vp := get_viewport_rect().size
	_boot_intro.visible = true
	_boot_intro.modulate.a = 1.0
	_boot_line.modulate.a = 0.0
	_boot_line.offset_left = -1.0
	_boot_line.offset_right = 1.0
	_boot_title.modulate.a = 0.0
	_boot_sub.modulate.a = 0.0
	_boot_status.modulate.a = 0.0
	_boot_tag.modulate.a = 0.0
	_boot_skip.modulate.a = 0.0
	_boot_sweep.position = Vector2(0.0, -4.0)
	_boot_sweep.size = Vector2(vp.x, 2.0)

	var tween := create_tween()
	_boot_intro_tween = tween
	tween.tween_property(_boot_line, "modulate:a", 0.92, 0.06)
	tween.parallel().tween_property(_boot_line, "offset_left", -vp.x * 0.5, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_boot_line, "offset_right", vp.x * 0.5, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(_boot_line, "modulate:a", 0.0, 0.10)
	tween.tween_property(_boot_title, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(_boot_sub, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(_boot_status, "modulate:a", 0.7, 0.18)
	tween.parallel().tween_property(_boot_tag, "modulate:a", 0.7, 0.18)
	tween.parallel().tween_property(_boot_skip, "modulate:a", 0.75, 0.18)
	tween.parallel().tween_property(_boot_sweep, "position", Vector2(0.0, vp.y), 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Let the title breathe so the cold start reads before POST takes over.
	tween.tween_interval(BOOT_INTRO_HOLD)
	# Two quick brown-outs sell the CRT without a full-screen flash.
	tween.tween_property(_boot_intro, "modulate:a", 0.62, 0.03)
	tween.tween_property(_boot_intro, "modulate:a", 1.0, 0.04)
	tween.tween_property(_boot_intro, "modulate:a", 0.78, 0.03)
	tween.tween_property(_boot_intro, "modulate:a", 1.0, 0.04)
	tween.tween_property(_boot_intro, "modulate:a", 0.0, 0.20)
	await tween.finished
	if token != _boot_intro_token or boot_done:
		return
	_boot_intro.visible = false
	_boot_intro.modulate.a = 1.0
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
	# Cancel the intro coroutine/tween before printing the skipped log.
	_boot_intro_token += 1
	if _boot_intro_tween and _boot_intro_tween.is_valid():
		_boot_intro_tween.kill()
	if _boot_intro:
		_boot_intro.visible = false
		_boot_intro.modulate.a = 1.0
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
	_check_idle_guidance()


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


func _check_idle_guidance() -> void:
	if not boot_done or in_ending or is_instance_valid(_guide_popup):
		return
	if Time.get_ticks_msec() - last_activity_msec < int(guide_idle_seconds * 1000.0):
		return
	_show_guidance()


func _guidance_content() -> Dictionary:
	var guides: Dictionary = data.get("guidance", {})
	var id := "free"
	if not logged_in:
		id = "login"
	elif not pump_handled:
		id = "pump"
	elif not scan_done:
		id = "scan"
	elif not read_cat:
		id = "void"
	var fallback := {
		"title": "GUIDE · Next Step",
		"body": "Type [color=#8fe3ff]HELP[/color] for the command list.",
		"ok": "Got it",
	}
	var page: Dictionary = guides.get(id, fallback)
	page = page.duplicate()
	page["id"] = id
	return page


func _show_guidance() -> void:
	if not boot_done or in_ending or is_instance_valid(_guide_popup):
		return
	var page := _guidance_content()
	var p: PanelContainer = POPUP_SCRIPT.new()
	popup_layer.add_child(p)
	_guide_popup = p
	p.closed.connect(_on_guide_closed.bind(p))
	p.open(
		str(page.get("title", "GUIDE · Next Step")),
		str(page.get("body", "")),
		str(page.get("ok", "Got it")),
		"guide"
	)


func _on_guide_closed(p: Node) -> void:
	if _guide_popup == p:
		_guide_popup = null


func _mark_activity() -> void:
	last_activity_msec = Time.get_ticks_msec()


func _refocus_input_after_submit() -> void:
	# Deferred because LineEdit may release editing after text_submitted. Do not
	# fight an ending (the input is hidden). A later click on a popup may still
	# blur the prompt, which is intentional.
	if boot_done and not in_ending and input_line.visible and input_line.editable:
		input_line.grab_focus()


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
	commands.clear()
	compact_commands.clear()
	for key in data.commands:
		var c: Dictionary = data.commands[key]
		var cmd := str(key)
		commands[cmd] = {
			"old": c.old,
			"new": str(c.new),
			"cb": actions.get(str(c.action), _act_none),
		}
		compact_commands[_compact(cmd)] = cmd


# ---------------- Input: three-tier matching ----------------

func _on_submit(raw: String) -> void:
	var cmd := _normalize_input(raw)
	input_line.clear()
	if not boot_done or in_ending:
		return
	if cmd == "":
		return
	_mark_input_activity()
	input_line.grab_focus()
	_refocus_input_after_submit.call_deferred()
	_audio.on_player_input()
	_audio.on_submit()

	history.append(cmd)
	_remember_command(cmd)
	_old_print("> " + cmd, true)

	# During a scan, every keystroke only earns a DELETED line
	if not scan_timer.is_stopped():
		_old_print("[ DELETED ]", true)
		return

	# SET DATE accepts free-form dates; exact SET DATE --AUTO is handled by the table.
	if cmd.begins_with("SET DATE ") and not commands.has(cmd):
		last_cmd = cmd
		_handle_set_date(cmd.substr(9))
		return

	var matched := _match_command(cmd)
	var kind := str(matched.get("kind", "none"))
	var resolved := str(matched.get("resolved", ""))
	var candidates: Array[String] = []
	for candidate in matched.get("candidates", []):
		candidates.append(str(candidate))

	if kind == "none":
		_junk()
		return
	if kind == "ambiguous":
		_new_say("I found more than one way to finish that. I can pick, but you should :)")
		_old_say(["MORE THAN ONE MATCH.", "TYPE MORE OR PRESS TAB."])
		completion_candidates = candidates
		completion_index = 0
		_restore_input(cmd)
		_show_completion()
		return

	# Irreversible A/B endings must be named in full. "FO" is a prefix, not consent.
	if not scan_done and resolved in ENDING_COMMANDS:
		_old_say(["UNKNOWN PARTITION."])
		return
	if resolved in ENDING_COMMANDS and not _is_full_command(cmd, resolved):
		_new_say("I can finish it, but this one should be yours :)")
		_old_say(["TYPE IT IN FULL."])
		_restore_input(cmd)
		return

	if kind == "prefix":
		_new_say("I completed that to " + resolved + " for you. Running it :)")
		_old_say(["PARTIAL MATCH", "MEANT " + _clip(resolved, 9)])
		_run(resolved)
		return

	_run(resolved)


func _on_input_text_changed(_new_text: String) -> void:
	if _programmatic_input:
		return
	# OLD takes the keyboard one character at a time. The caret stays where the
	# player left it; only the glyph casing changes.
	_assimilate_input()
	_mark_input_activity()
	history_cursor = -1
	history_draft = ""
	completion_index = 0
	_refresh_completion()
	_request_input_access()


func _assimilate_input() -> void:
	var current := input_line.text
	var upper := current.to_upper()
	if upper == current:
		return
	var caret := input_line.caret_column
	var growth := maxi(upper.length() - current.length(), 0)
	_programmatic_input = true
	input_line.text = upper
	input_line.caret_column = mini(caret + growth, upper.length())
	_programmatic_input = false
	if input_assimilated:
		return
	input_assimilated = true
	var line := str(data.get("assimilate", ""))
	if line != "" and not in_ending:
		_new_say(line)


func _request_input_access() -> void:
	# NEW asks first, then admits it was already reading. The request itself is
	# the reveal; the grayscale completion has been doing it since login.
	if auth_requested or in_ending or not boot_done:
		return
	if not logged_in:
		return
	var auth: Dictionary = data.get("auth", {})
	if auth.is_empty():
		return
	auth_requested = true
	_popup_queue.append({
		"title": str(auth.get("title", "NEW · Input Access Request")),
		"body": str(auth.get("body", "")),
		"ok": str(auth.get("ok", "Allow")),
		"after": "auth",
	})
	_pump_popup()


func _record_backspace() -> void:
	if in_ending or not boot_done:
		return
	backspace_count += 1
	if backspace_count < BACKSPACE_REVEAL or hesitation_shown:
		return
	hesitation_shown = true
	var lines: Array = data.get("backspace", ["YOU HESITATED."])
	_old_say(lines)


func _mark_input_activity() -> void:
	last_input_msec = Time.get_ticks_msec()
	_mark_activity()
	# Typing is real input. It also cancels the KILL 077 inheritance window.
	if not inherit_timer.is_stopped():
		inherit_timer.stop()


func _normalize_input(raw: String) -> String:
	var text := raw.strip_edges().to_upper()
	var out := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 0xFF01 and code <= 0xFF5E:
			out += String.chr(code - 0xFEE0)      # full-width ASCII -> half-width
		elif code == 0x3000 or code == 0x00A0:
			out += " "                            # full-width / non-breaking space
		elif code == 9 or code == 10 or code == 13:
			out += " "
		else:
			out += String.chr(code)
	text = out
	while text.contains("  "):
		text = text.replace("  ", " ")
	return text.strip_edges()


func _compact(text: String) -> String:
	# Whitespace is presentation, not syntax: SCAN/FULL, SCAN / FULL and PUMP3
	# all collapse to the same comparison key.
	return text.replace(" ", "")


func _is_full_command(input: String, canonical: String) -> bool:
	return input == canonical or _compact(input) == _compact(canonical)


func _match_command(text: String) -> Dictionary:
	if commands.has(text):
		return {"kind": "exact", "resolved": text, "candidates": [text]}

	var compact := _compact(text)
	if compact.length() < 2:
		return {"kind": "none", "resolved": "", "candidates": []}
	if compact_commands.has(compact):
		var canonical := str(compact_commands[compact])
		return {"kind": "prefix", "resolved": canonical, "candidates": [canonical]}

	var matches: Array[String] = []
	for key in compact_commands:
		if str(key).begins_with(compact):
			matches.append(str(compact_commands[key]))
	if matches.is_empty():
		return {"kind": "none", "resolved": "", "candidates": []}
	if matches.size() == 1:
		return {"kind": "prefix", "resolved": matches[0], "candidates": [matches[0]]}

	# Longest common prefix is the safe completion. If it is itself a command
	# (PUMP -> PUMP 3), complete to it. If not (PUMP 3 --), it is true ambiguity.
	var compact_matches: Array[String] = []
	for candidate in matches:
		compact_matches.append(_compact(candidate))
	var prefix := _longest_common_prefix(compact_matches)
	if compact_commands.has(prefix):
		var common := str(compact_commands[prefix])
		return {"kind": "prefix", "resolved": common, "candidates": [common]}

	matches.sort_custom(_sort_commands)
	return {"kind": "ambiguous", "resolved": "", "candidates": matches}


func _longest_common_prefix(values: Array[String]) -> String:
	if values.is_empty():
		return ""
	var prefix := values[0]
	for i in range(1, values.size()):
		while not values[i].begins_with(prefix):
			prefix = prefix.substr(0, prefix.length() - 1)
			if prefix == "":
				return ""
	return prefix


func _sort_commands(a: String, b: String) -> bool:
	if a.length() == b.length():
		return a < b
	return a.length() < b.length()


func _remember_command(cmd: String) -> void:
	command_history.append(cmd)
	if command_history.size() > COMMAND_HISTORY_MAX:
		command_history.pop_front()
	history_cursor = -1
	history_draft = ""


func _restore_input(text: String) -> void:
	_programmatic_input = true
	input_line.text = text
	input_line.caret_column = text.length()
	_programmatic_input = false
	_mark_input_activity()
	_refresh_completion()


func _set_input_text(text: String) -> void:
	_programmatic_input = true
	input_line.text = text
	input_line.caret_column = text.length()
	_programmatic_input = false
	_mark_input_activity()
	completion_index = 0
	_refresh_completion()


func _history_prev() -> void:
	if command_history.is_empty():
		return
	if history_cursor == -1:
		history_draft = input_line.text
		history_cursor = command_history.size() - 1
	elif history_cursor > 0:
		history_cursor -= 1
	_set_input_text(command_history[history_cursor])


func _history_next() -> void:
	if history_cursor == -1:
		return
	history_cursor += 1
	if history_cursor >= command_history.size():
		history_cursor = -1
		_set_input_text(history_draft)
	else:
		_set_input_text(command_history[history_cursor])


func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_BACKSPACE:
		_record_backspace()
	if key.keycode == KEY_TAB:
		_cycle_completion(key.shift_pressed)
		accept_event()
		return
	if key.keycode == KEY_UP:
		_history_prev()
		accept_event()
		return
	if key.keycode == KEY_DOWN:
		_history_next()
		accept_event()
		return
	if key.keycode == KEY_RIGHT and not key.shift_pressed and input_line.caret_column >= input_line.text.length():
		if _accept_current_completion():
			accept_event()


func _refresh_completion() -> void:
	if not is_node_ready() or completion_label == null:
		return
	if in_ending or not boot_done or not input_line.visible or not scan_timer.is_stopped():
		_hide_completion()
		return

	var text := _normalize_input(input_line.text)
	var candidates: Array[String] = []
	if text == "":
		if void_killed and read_cat:
			candidates.append("SHUTDOWN --VERIFY")
	elif not commands.has(text):
		var matched := _match_command(text)
		var kind := str(matched.get("kind", "none"))
		if kind == "prefix" or kind == "ambiguous":
			for candidate in matched.get("candidates", []):
				var cmd := str(candidate)
				if _completion_visible(cmd):
					candidates.append(cmd)

	if candidates.is_empty():
		_hide_completion()
		return
	completion_candidates = candidates
	completion_index = clampi(completion_index, 0, candidates.size() - 1)
	_show_completion()


func _completion_visible(cmd: String) -> bool:
	# The grey text may only name what the story has already exposed.
	if not scan_done:
		return not (cmd in COMPLETION_HIDDEN_BEFORE_SCAN)
	if not read_cat:
		return not (cmd in COMPLETION_HIDDEN_BEFORE_CAT)
	return true


func _show_completion() -> void:
	if completion_candidates.is_empty():
		_hide_completion()
		return
	completion_index = clampi(completion_index, 0, completion_candidates.size() - 1)
	var hint := "TAB  " + completion_candidates[completion_index]
	if completion_candidates.size() > 1:
		hint += "  (%d/%d)" % [completion_index + 1, completion_candidates.size()]
	completion_label.text = hint
	if not _completion_fits(hint):
		_hide_completion()
		return
	completion_label.visible = true


func _completion_fits(hint: String) -> bool:
	var font := completion_label.get_theme_font("font")
	var font_size := completion_label.get_theme_font_size("font_size")
	if font == null:
		return true
	# Measure what the player typed with the LineEdit's own font: it is larger
	# than the hint font, so using 14px for both would under-estimate overlap.
	var typed_font := input_line.get_theme_font("font")
	var typed_size := input_line.get_theme_font_size("font_size")
	if typed_font == null:
		typed_font = font
		typed_size = font_size
	var typed_width := typed_font.get_string_size(input_line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, typed_size).x
	var hint_width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var available := input_line.size.x
	# Headless / pre-layout frames can report only the LineEdit's minimum width.
	# Fall back to the viewport row width so the hint still has a real budget.
	var view_width := get_viewport_rect().size.x
	if available < 320.0 and view_width >= 320.0:
		available = maxf(available, view_width - 56.0)
	if available <= 0.0:
		available = 800.0
	return typed_width + hint_width + 36.0 <= available


func _hide_completion() -> void:
	completion_candidates.clear()
	completion_index = 0
	if is_instance_valid(completion_label):
		completion_label.visible = false
		completion_label.text = ""


func _cycle_completion(reverse := false) -> void:
	if completion_candidates.is_empty():
		return
	var compact_text := _compact(_normalize_input(input_line.text))
	var current := -1
	for i in completion_candidates.size():
		if _compact(completion_candidates[i]) == compact_text:
			current = i
			break
	if current == -1:
		current = completion_candidates.size() - 1 if reverse else 0
	else:
		current = wrapi(current + (-1 if reverse else 1), 0, completion_candidates.size())
	_apply_completion(current)


func _accept_current_completion() -> bool:
	if completion_candidates.is_empty():
		return false
	var compact_text := _compact(_normalize_input(input_line.text))
	for cmd in completion_candidates:
		if _compact(cmd) == compact_text:
			return false
	_apply_completion(completion_index)
	return true


func _apply_completion(index: int) -> void:
	if completion_candidates.is_empty():
		return
	completion_index = clampi(index, 0, completion_candidates.size() - 1)
	var cmd := completion_candidates[completion_index]
	_programmatic_input = true
	input_line.text = cmd
	input_line.caret_column = cmd.length()
	_programmatic_input = false
	_mark_input_activity()
	history_cursor = -1
	history_draft = ""
	_show_completion()


func _handle_set_date(value: String) -> void:
	var cleaned := value.replace(" ", "").replace("—", "-")
	var parts := cleaned.split("-")
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
			var month := int(month_text)
			var day := int(day_text)
			var eggs: Dictionary = data.get("date_eggs", {})
			if month == 1 and day == 1 and ((year_text.length() == 4 and year == 2000) or (year_text.length() == 2 and year == 0)):
				var y2k_lines: Array = eggs.get("y2k", ["NOTHING HAPPENED.", "THAT WAS THE POINT."])
				_old_say(y2k_lines)
				return
			if month == 11 and day == 3 and ((year_text.length() == 4 and year == 1979) or (year_text.length() == 2 and year == 79)):
				var birth_lines: Array = eggs.get("birth", ["LOG 11-03-1979", "00:00 POWER ON", "FIRST ENTRY", "46 YEARS AGO"])
				_old_say(birth_lines)
				return
	_old_say(["DATE ACCEPTED.", "RTC WRITTEN."])


func _run(cmd: String) -> void:
	last_cmd = cmd
	if cmd == "LOGIN 077":
		logged_in = true
	var entry: Dictionary = commands[cmd]
	_new_say(_new_text_for(cmd))
	_old_say(entry.old)
	var cb: Callable = entry.cb
	cb.call()
	if cmd == "LOGIN 077":
		_audio.play_chime()
	if cmd == "CAT /VOID/TECH-077":
		read_cat = true
		_refresh_completion()
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
		old_timer.wait_time = _old_delay_seconds(lines)
		old_timer.start()


func _old_delay_seconds(lines: Array = []) -> float:
	# The wait is OLD's state readout. Priority: the C window is closing, then
	# the player has already let NEW decide / made the room noisy, then /VOID.
	if old_delay_override >= 0.0:
		return old_delay_override
	if not inherit_timer.is_stopped() and inherit_timer.time_left <= OLD_ENDING_WINDOW:
		return OLD_DELAY_ENDING_WINDOW
	if pump_choice == "accept" or temp > 0 or junk_count >= 3:
		return OLD_DELAY_NEW_PATH
	if last_cmd.contains("VOID"):
		return OLD_DELAY_DANGER
	for line in lines:
		if str(line).contains("VOID"):
			return OLD_DELAY_DANGER
	return OLD_DELAY_BASE


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
	pump_choice = "isolate"
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 60.0, 2.0)


func _act_accept() -> void:
	pump_handled = true
	pump_choice = "accept"
	_audio.on_accept_new()
	_add_remote_writes(2)
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 100.0, 1.5)


func _add_remote_writes(points: int) -> void:
	temp += points                       # hidden stat: 2 points per NEW decision
	bar3.value = float(temp)
	if bar3.modulate.a < 1.0:
		var reveal := create_tween()
		reveal.tween_property(bar3, "modulate:a", 1.0, 0.35)


func _act_date_auto() -> void:
	_add_remote_writes(2)


func _act_kill() -> void:
	void_killed = true
	_audio.on_kill()
	# KILL before the full scan arms nothing yet; _finish_scan() starts the window.
	if scan_done:
		inherit_timer.start()
	if not kill_glitch_played:
		kill_glitch_played = true
		_play_kill_glitch()
	if not saw_that:
		saw_that = true
		_old_say(["WE SAW THAT."])
		_schedule_fake07()
	_refresh_completion()


func _schedule_fake07() -> void:
	if _fake07_seen:
		return
	await get_tree().create_timer(fake07_delay).timeout
	if not is_inside_tree() or in_ending or _fake07_seen:
		return
	_show_fake07()


func _start_scan_band() -> void:
	if scan_band == null:
		return
	if scan_band_tween and scan_band_tween.is_valid():
		scan_band_tween.kill()
	var rect := old_text.get_global_rect()
	var top := rect.position.y
	var travel := maxf(rect.size.y - SCAN_BAND_HEIGHT, 0.0)
	scan_band.position = Vector2(rect.position.x, top)
	scan_band.size = Vector2(rect.size.x, SCAN_BAND_HEIGHT)
	scan_band.color = Color(0.588235, 1, 0.658824, 0.22)
	scan_band.visible = true
	scan_band_tween = create_tween().set_loops()
	scan_band_tween.tween_property(scan_band, "position:y", top + travel, SCAN_BAND_TIME).set_trans(Tween.TRANS_LINEAR)
	scan_band_tween.tween_callback(_reset_scan_band.bind(top))


func _reset_scan_band(top: float) -> void:
	if is_instance_valid(scan_band):
		scan_band.position.y = top


func _stop_scan_band() -> void:
	if scan_band_tween and scan_band_tween.is_valid():
		scan_band_tween.kill()
	if is_instance_valid(scan_band):
		scan_band.visible = false


func _show_fake07() -> void:
	if in_ending or _fake07_seen:
		return
	var pages: Dictionary = data.get("fake_manuals", {})
	var page: Dictionary = pages.get("07", {})
	if page.is_empty():
		return
	_fake07_seen = true
	_popup_queue.append({
		"title": str(page.get("title", "Night Shift Manual 07")),
		"body": str(page.get("body", "")),
		"ok": str(page.get("ok", "I will remember")),
	})
	_pump_popup()


func _act_scan_full() -> void:
	if scan_done or not scan_timer.is_stopped():
		return
	_hide_completion()
	_audio.on_scan_start()
	_start_scan_band()
	scan_time = 0.0
	scan_stage = 0
	scan_found = false
	scan_rewound = false
	scan_stream_index = 0
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
	_print_scan_stream()

	if scan_stage == 0 and scan_time >= scan_duration / 3.0:
		scan_stage = 1
		_new_say("Ten seconds to go. I already have the result. Want a peek? :)")
	elif scan_stage == 1 and scan_time >= scan_duration * 2.0 / 3.0:
		scan_stage = 2
		_new_say("Hey, the old screen just scanned you too. Even more thoroughly than I did.")

	var stream: Dictionary = data.get("scan_stream", {})
	if not scan_found and scan_time >= scan_duration * SCAN_FOUND_RATIO:
		scan_found = true
		scan_bar.value = 99.0
		_old_print(str(stream.get("found", "/HOME/TECH-077 FOUND")), true)
		return
	if scan_found and not scan_rewound and scan_time >= scan_duration * SCAN_REWIND_RATIO:
		scan_rewound = true
		scan_bar.value = SCAN_REWIND_VALUE
		return

	if not scan_found:
		scan_bar.value = clampf(scan_time / maxf(scan_duration * SCAN_FOUND_RATIO, 0.001) * 74.0, 0.0, 74.0)
	elif scan_rewound:
		var rewind_span := maxf(scan_duration * (1.0 - SCAN_REWIND_RATIO), 0.001)
		var tail := clampf((scan_time - scan_duration * SCAN_REWIND_RATIO) / rewind_span, 0.0, 1.0)
		scan_bar.value = SCAN_REWIND_VALUE + tail * (100.0 - SCAN_REWIND_VALUE)

	if scan_time >= scan_duration:
		_finish_scan()


func _print_scan_stream() -> void:
	var stream: Dictionary = data.get("scan_stream", {})
	var lines: Array = stream.get("lines", [])
	while scan_stream_index < lines.size() and scan_time >= scan_duration * SCAN_STREAM_STEP_RATIO * float(scan_stream_index + 1):
		_old_print(str(lines[scan_stream_index]), true)
		scan_stream_index += 1


func _finish_scan() -> void:
	scan_timer.stop()
	_stop_scan_band()
	scan_stage = 3
	scan_done = true
	scan_bar.value = 100.0
	_new_say("All done. There's something in /VOID called TECH-077.")
	var stream: Dictionary = data.get("scan_stream", {})
	var scan_old = stream.get("done", ["SCAN DONE", "VOL 3 /VOID", "SIZE 077 GB", "MOUNTED 1979"]).duplicate()
	scan_old.append(str(data.scan_complete.old[0]))
	if pump_choice == "isolate":
		scan_old.append("MANUAL SEAL: LOGGED")
	elif pump_choice == "accept":
		scan_old.append("REMOTE WRITE: 1")
	_old_say(scan_old)
	epoch_label.visible = true
	_hint_scan()
	_hint_for("SCAN /FULL")
	_scan_confession()
	# A KILL issued before the scan still counts: start the silent window now.
	if void_killed and not in_ending:
		inherit_timer.start()
	_refresh_completion()


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
	_stop_scan_band()
	if is_instance_valid(glitch_text):
		glitch_text.visible = false
	_clear_popups()
	old_timer.stop()
	pending_old.clear()
	_hide_completion()
	input_line.editable = false
	input_line.release_focus()
	input_line.placeholder_text = "Ending in progress · press R to restart"
	restart_hint.visible = false
	end_status.visible = false
	end_tag.visible = false
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
	var intro: Dictionary = data.get("inherit_intro", {})
	for line in intro.get("system", []):
		_old_print(str(line), true)
	for line in intro.get("old", []):
		_old_print(str(line))
	var intro_new := str(intro.get("new", ""))
	if intro_new != "":
		_new_say(intro_new)
	_old_print("[ PATCH REPLAY ]", true)
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


func _play_kill_glitch() -> void:
	if glitch_text == null or in_ending:
		return
	glitch_text.text = _glitch_block(KILL_GLITCH_CHARS, KILL_GLITCH_LINE)
	glitch_text.visible = true
	await get_tree().create_timer(KILL_GLITCH_TIME).timeout
	if is_inside_tree() and is_instance_valid(glitch_text):
		glitch_text.visible = false


func _glitch_block(length: int, line_length: int) -> String:
	var out := ""
	for i in length:
		out += GLITCH_POOL.substr(randi() % GLITCH_POOL.length(), 1)
		if (i + 1) % line_length == 0:
			out += "\n"
	return out


func _ending_coda() -> Array[String]:
	var coda: Array[String] = []
	if pump_choice == "isolate":
		coda.append("OLD> PUMP: MANUAL SEAL.")
	elif pump_choice == "accept":
		coda.append("OLD> PUMP: REMOTE WRITE.")
	else:
		coda.append("OLD> PUMP: UNSERVICED.")
	if temp > 0 and read_cat:
		coda.append("OLD> REMOTE DECISIONS: %d. FILE READ." % int(temp / 2))
	elif temp > 0:
		coda.append("OLD> REMOTE DECISIONS: %d." % int(temp / 2))
	elif read_cat:
		coda.append("OLD> FILE READ: TECH-077.")
	if void_killed:
		coda.append("OLD> PROCESS ENDED. LOG CONTINUES.")
	elif junk_count > 0:
		coda.append("OLD> JUNK ENTRIES: %d." % junk_count)
	return coda


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
	ending_lines = _ending_coda()
	ending_lines.append_array(data.endings[ending_key])
	ending_index = 0
	_old_print("[ PATCH COMPLETE ]" if ending_key == "inherit" else "[ REPLAY END ]", true)
	end_timer.start()


func _on_end_tick() -> void:
	if ending_index >= ending_lines.size():
		end_timer.stop()
		if ending_key == "shutdown":
			# B keeps the "machine still on" closing, but dims the terminal before the end card.
			_show_black_screen(END_DIM_ALPHA, false)
		_audio.on_ending_complete()
		return
	var line := str(ending_lines[ending_index])
	ending_index += 1
	if line.begins_with("OLD> "):
		_old_print(line.substr(5))
	elif line.begins_with("NEW> "):
		_new_say(line.substr(5))
	elif line.begins_with("BLACK> "):
		# A leaves the machine barely visible; C buries the whole terminal.
		_show_black_screen(END_DIM_ALPHA if ending_key == "format" else END_BLACK_ALPHA)
	elif line.begins_with("CLOCK> "):
		_apply_clock_directive(line.substr(7).strip_edges())
	elif line.begins_with("FINAL> "):
		_show_final_line(line.substr(7))
	else:
		_old_print(line, true)


func _show_black_screen(alpha: float = END_BLACK_ALPHA, fade_audio: bool = true) -> void:
	if black_tween and black_tween.is_valid():
		black_tween.kill()
	black_tween = create_tween()
	black_tween.tween_property(crt, "color", Color(0, 0, 0, alpha), END_FADE_TIME)
	black_tween.tween_interval(END_HINT_DELAY)
	black_tween.tween_callback(_show_end_card)
	if fade_audio:
		_audio.on_black_screen()


func _apply_clock_directive(value: String) -> void:
	match value:
		"RESET":
			clock_unix = CLOCK_START_UNIX
			epoch_value = EPOCH_START
			clock_loops = 0
			epoch_label.visible = false
			_refresh_status_labels()
		"DARK":
			clock_timer.stop()
			clock_label.text = "--:--:--"
			epoch_label.visible = false


func _show_end_card() -> void:
	if not is_inside_tree():
		return
	# Deferred: changing a focused LineEdit's visibility inside the fade tween's
	# callback can stall the container layout on Godot 4.7.
	input_line.call_deferred("hide")
	end_status.text = END_STATUS_TEXT
	end_status.visible = true
	_show_end_tag()
	restart_hint.visible = true


func _show_end_tag() -> void:
	var meta: Dictionary = data.get("ending_meta", {}).get(ending_key, {})
	if meta.is_empty():
		end_tag.visible = false
		return
	end_tag.text = "%s · %s" % [str(meta.get("code", "")), str(meta.get("name", ""))]
	end_tag.visible = true


func _show_final_line(text: String) -> void:
	final_line.text = text
	final_line.visible = true


func _input(event: InputEvent) -> void:
	# Guidance waits for complete inactivity: keys, clicks and mouse movement
	# all count, so a player reading with the mouse does not get interrupted.
	if event is InputEventKey:
		if event.pressed and not event.echo:
			_mark_activity()
	elif event is InputEventMouseButton:
		if event.pressed:
			_mark_activity()
	elif event is InputEventMouseMotion:
		if event.relative.length_squared() > 0.0:
			_mark_activity()


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
	p.open(str(item.title), str(item.body), str(item.get("ok", "Got it")))
	p.closed.connect(_on_popup_closed.bind(p))
	_popup = p
	_popup_after = str(item.get("after", ""))


func _on_popup_closed(p: Node) -> void:
	if _popup == p:
		_popup = null
		var after := _popup_after
		_popup_after = ""
		if after == "auth" and not in_ending:
			var auth: Dictionary = data.get("auth", {})
			var reveal := str(auth.get("reveal", ""))
			if reveal != "":
				_new_say(reveal)
	await get_tree().create_timer(0.35).timeout
	if is_inside_tree():
		_pump_popup()


func _clear_popups() -> void:
	_popup_queue.clear()
	_popup_after = ""
	var current := _popup
	_popup = null
	if is_instance_valid(current):
		current.close()
	var guide := _guide_popup
	_guide_popup = null
	if is_instance_valid(guide):
		guide.close()

