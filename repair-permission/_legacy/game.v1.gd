extends Control
## Repair Permission - 双终端微恐怖叙事
## 全部对白数据在 res://data/script.json，本脚本只负责时序、状态分叉与结局。

const DATA_PATH := "res://data/script.json"

# 对白索引（与 data/script.json 的 dialogues 顺序一一对应）
const G_BOOT := 0
const G_LOGIN := 1
const G_HELP := 2
const G_UNDO := 3
const G_LOG := 4
const G_STATUS := 5
const G_PUMP := 6
const G_ISOLATE := 7
const G_ACCEPT := 8
const G_DONE := 9
const G_IDLE := 10
const G_SCAN := 11
const G_DEEP := 12
const G_LS := 13
const G_PS := 14
const G_CAT := 15
const G_CATF := 16
const G_KILL := 17
const G_FINAL := 18
const G_ID := 19

const C_OLD := "#96ffa8"
const C_OLD_DIM := "#3f7f4d"
const C_NEW := "#6fd7ff"
const C_NEW_DIM := "#2b5a6b"
const C_AMBER := "#ffb454"
const C_INK := "#05080a"

# 每台终端各自记录、永不同步的分叉值
var status_values := {
	"SHIFT": {"old": "0000:00", "new": "41 NIGHTS"},
	"LINK": {"old": "1", "new": "2"},
	"PUMPS": {"old": "2", "new": "3"},
	"ROOM": {"old": "2", "new": "1"},
	"VOID": {"old": "077GB", "new": "1.2TB"},
	"UPTIME": {"old": "46Y", "new": "45M"},
}
var unlocked := {"SHIFT": true}

var dialogue: Array = []
var endings: Dictionary = {}

var stage := "LOGIN"
var ending_mode := false
var scanning := false
var choice_made := false
var auto_accept_started := false
var awaiting_confirm := false
var transcript_read := false
var killed_077 := false
var body_watched := false

var shift_started_ms := 0
var last_input_ms := 0
var last_idle_ms := -100000
var final_anchor_ms := 0
var clock_accum := 0.0

# 可调时间参数（冒烟测试会把这几个值调小；正式游戏保持默认）
var latency_min := 3.0
var latency_max := 5.0
var scan_seconds := 40.0
var idle_seconds := 12.0
var idle_gap_seconds := 26.0
var final_timeout_ms := 60000
var auto_accept_seconds := 10.0
var pump_resolve_seconds := 8.0
var ending_speed := 1.0


func _latency() -> float:
	return randf_range(latency_min, latency_max)

# UI
var old_log: RichTextLabel
var new_log: RichTextLabel
var old_stat: Label
var new_stat: Label
var echo_label: Label
var hint_label: Label
var input_line: LineEdit
var narration: Label
var blackout: ColorRect


func _ready() -> void:
	_load_data()
	_build_ui()
	shift_started_ms = Time.get_ticks_msec()
	last_input_ms = Time.get_ticks_msec()
	await get_tree().create_timer(0.8).timeout
	if is_inside_tree():
		_play_group(G_BOOT)
	input_line.grab_focus()


func _load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("缺少对白数据: " + DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("script.json 解析失败")
		return
	dialogue = parsed.get("dialogues", [])
	endings = parsed.get("endings", {})


# ---------------- UI ----------------

func _mono_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "Microsoft YaHei UI"])
	return f


func _sans_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	return f


func _panel_style(border: Color, bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(12)
	return sb


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(C_INK)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# ---- 状态条：两台终端各一行，配色区分，永不对齐 ----
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	root.add_child(header)

	old_stat = Label.new()
	old_stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	old_stat.add_theme_font_override("font", _mono_font())
	old_stat.add_theme_font_size_override("font_size", 13)
	old_stat.add_theme_color_override("font_color", Color(C_AMBER))
	old_stat.text = "OLD   SHIFT 0000:00"
	header.add_child(old_stat)

	new_stat = Label.new()
	new_stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	new_stat.add_theme_font_override("font", _sans_font())
	new_stat.add_theme_font_size_override("font_size", 13)
	new_stat.add_theme_color_override("font_color", Color(C_NEW))
	new_stat.text = "NEW   41 NIGHTS"
	header.add_child(new_stat)

	# ---- 双终端主体 ----
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# OLD 面板
	var old_panel := PanelContainer.new()
	old_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	old_panel.size_flags_stretch_ratio = 1.08
	old_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.35, 0.75, 0.42, 0.30), Color("#060c08")))
	body.add_child(old_panel)

	var old_box := VBoxContainer.new()
	old_box.add_theme_constant_override("separation", 6)
	old_panel.add_child(old_box)

	var old_title := Label.new()
	old_title.add_theme_font_override("font", _mono_font())
	old_title.add_theme_font_size_override("font_size", 12)
	old_title.add_theme_color_override("font_color", Color(C_OLD_DIM))
	old_title.text = "TERMINAL OLD // PHOSPHOR P1 // 1979"
	old_box.add_child(old_title)

	old_log = RichTextLabel.new()
	old_log.bbcode_enabled = true
	old_log.scroll_following = true
	old_log.selection_enabled = true
	old_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	old_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	old_log.add_theme_font_override("normal_font", _mono_font())
	old_log.add_theme_font_size_override("normal_font_size", 15)
	old_log.add_theme_constant_override("line_separation", 4)
	old_log.add_theme_color_override("default_color", Color(C_OLD))
	old_box.add_child(old_log)

	echo_label = Label.new()
	echo_label.add_theme_font_override("font", _mono_font())
	echo_label.add_theme_font_size_override("font_size", 15)
	echo_label.add_theme_color_override("font_color", Color(C_OLD_DIM))
	echo_label.text = "> "
	old_box.add_child(echo_label)

	# NEW 面板
	var new_panel := PanelContainer.new()
	new_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.35, 0.72, 0.90, 0.35), Color("#060a0d")))
	body.add_child(new_panel)

	var new_box := VBoxContainer.new()
	new_box.add_theme_constant_override("separation", 6)
	new_panel.add_child(new_box)

	var new_title := Label.new()
	new_title.add_theme_font_override("font", _sans_font())
	new_title.add_theme_font_size_override("font_size", 12)
	new_title.add_theme_color_override("font_color", Color(C_NEW_DIM))
	new_title.text = "助手 NEW // 在线 // 本地模型 v4"
	new_box.add_child(new_title)

	new_log = RichTextLabel.new()
	new_log.bbcode_enabled = true
	new_log.scroll_following = true
	new_log.selection_enabled = true
	new_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	new_log.add_theme_font_override("normal_font", _sans_font())
	new_log.add_theme_font_size_override("normal_font_size", 16)
	new_log.add_theme_constant_override("line_separation", 7)
	new_log.add_theme_color_override("default_color", Color("#d6ecf3"))
	new_box.add_child(new_log)

	# ---- 旁白（结局里的舞台指示）----
	narration = Label.new()
	narration.add_theme_font_override("font", _sans_font())
	narration.add_theme_font_size_override("font_size", 15)
	narration.add_theme_color_override("font_color", Color("#7f8a8c"))
	narration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	narration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narration.custom_minimum_size = Vector2(0, 24)
	narration.text = ""
	root.add_child(narration)

	# ---- 输入行 ----
	hint_label = Label.new()
	hint_label.add_theme_font_override("font", _sans_font())
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color("#5f7a76"))
	hint_label.text = "登录：LOGIN 077　　列出命令：HELP"
	root.add_child(hint_label)

	input_line = LineEdit.new()
	input_line.custom_minimum_size = Vector2(0, 34)
	input_line.placeholder_text = "输入命令，回车执行。"
	input_line.add_theme_font_override("font", _mono_font())
	input_line.add_theme_font_size_override("font_size", 16)
	input_line.add_theme_color_override("font_color", Color(C_OLD))
	input_line.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.22))
	input_line.add_theme_color_override("caret_color", Color(C_OLD))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("#04100a")
	input_style.border_color = Color(0.35, 0.75, 0.42, 0.35)
	input_style.set_border_width_all(1)
	input_style.set_content_margin_all(8)
	input_line.add_theme_stylebox_override("normal", input_style)
	input_line.text_submitted.connect(_on_submit)
	input_line.text_changed.connect(_on_text_changed)
	root.add_child(input_line)

	# ---- 黑屏覆盖层 ----
	blackout = ColorRect.new()
	blackout.color = Color(0, 0, 0, 0)
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(blackout)


# ---------------- 输出 ----------------

func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _old_print(line: String, dim := false) -> void:
	if old_log == null:
		return
	var col := C_OLD_DIM if dim else C_OLD
	old_log.append_text("[color=%s]%s[/color]\n" % [col, _esc(line)])


func _new_print(text: String) -> void:
	if new_log == null:
		return
	var lines := text.split("\n")
	var body := ""
	for i in lines.size():
		if i > 0:
			body += "\n"
		body += _esc(lines[i])
	new_log.append_text("[color=%s]NEW[/color]   [color=%s]%s[/color]\n\n" % [C_NEW_DIM, C_NEW, body])


func _old_say_after(text: String, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	for line in text.split("\n"):
		if line.strip_edges() == "":
			continue
		_old_print(line)
		await get_tree().create_timer(0.13).timeout


func _new_say_after(text: String, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	_new_print(text)


# ---------------- 对白播放 ----------------

func _play_group(idx: int) -> void:
	if idx < 0 or idx >= dialogue.size():
		return
	_apply_effects(idx)
	var g: Dictionary = dialogue[idx]
	var new_delay := randf_range(0.2, 0.5)
	var old_delay := _latency()
	if idx == G_BOOT:
		old_delay = 0.4
		new_delay = 1.8
	_new_say_after(String(g.get("new_reply", "")), new_delay)
	_old_say_after(String(g.get("old_reply", "")), old_delay)


func _apply_effects(idx: int) -> void:
	match idx:
		G_LOGIN:
			_unlock("LINK")
		G_LOG:
			_unlock("UPTIME")
			_set_stage("PUMP3")
		G_STATUS:
			_unlock("PUMPS")
			_unlock("ROOM")
		G_ISOLATE:
			choice_made = true
		G_ACCEPT:
			choice_made = true
		G_DONE:
			_unlock("PUMPS")
			_set_stage("SCAN")
		G_IDLE:
			body_watched = true
		G_DEEP:
			_unlock("VOID")
		G_CAT:
			transcript_read = true
			_new_edit_notice()
		G_CATF:
			_unlock("ROOM")
			_set_stage("FINAL")
		G_KILL:
			killed_077 = true


func _new_edit_notice() -> void:
	await get_tree().create_timer(0.7).timeout
	if not is_inside_tree():
		return
	new_log.append_text("[color=%s]（这条消息已被编辑）[/color]\n\n" % C_NEW_DIM)


# ---------------- 状态条 ----------------

func _unlock(key: String) -> void:
	unlocked[key] = true
	_render_status()


func _render_status() -> void:
	if old_stat == null or new_stat == null:
		return
	var order := ["SHIFT", "LINK", "PUMPS", "ROOM", "VOID", "UPTIME"]
	var o := ""
	var n := ""
	for k in order:
		if not unlocked.has(k):
			continue
		o += "%s %s   " % [k, status_values[k]["old"]]
		n += "%s %s   " % [k, status_values[k]["new"]]
	old_stat.text = "OLD   " + o.strip_edges()
	new_stat.text = "NEW   " + n.strip_edges()


func _set_stage(s: String) -> void:
	if stage == s:
		return
	stage = s
	match s:
		"PUMP3":
			hint_label.text = "PUMP3 >> STATUS 检查，然后 PUMP 3 查看封条"
		"SCAN":
			hint_label.text = "SCAN >> 输入 SCAN 开始全盘扫描"
		"FINAL":
			hint_label.text = "FINAL >> FORMAT /VOID　　或　　SHUTDOWN --VERIFY"
			final_anchor_ms = Time.get_ticks_msec()
			_final_intro()
	_render_status()


func _final_intro() -> void:
	await get_tree().create_timer(4.0).timeout
	if is_inside_tree() and stage == "FINAL" and not ending_mode:
		_play_group(G_FINAL)


# ---------------- 每帧 ----------------

func _process(delta: float) -> void:
	if ending_mode:
		return
	clock_accum += delta
	if clock_accum >= 0.5:
		clock_accum = 0.0
		_refresh_clock()
	var now := Time.get_ticks_msec()
	if stage != "LOGIN" and not scanning and now - last_input_ms > idle_seconds * 1000.0 and now - last_idle_ms > idle_gap_seconds * 1000.0:
		last_idle_ms = now
		_play_group(G_IDLE)
	if stage == "FINAL" and not awaiting_confirm and now - final_anchor_ms > final_timeout_ms:
		final_anchor_ms = now + 3600000
		_play_ending("C_timeout")


func _refresh_clock() -> void:
	var secs := int((Time.get_ticks_msec() - shift_started_ms) / 1000.0)
	status_values["SHIFT"]["old"] = "%04d:%02d" % [secs / 60, secs % 60]
	_render_status()


func _on_text_changed(new_text: String) -> void:
	# 即时回显：OLD 打字的字是立刻出现的，只有“回答”要等 3-5 秒
	if echo_label != null:
		echo_label.text = "> " + new_text


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and input_line != null:
		input_line.grab_focus()


# ---------------- 输入 ----------------

func _normalize(s: String) -> String:
	var out := s.strip_edges().to_upper()
	while out.contains("  "):
		out = out.replace("  ", " ")
	out = out.replace("/ ", "/")
	return out


func _on_submit(raw: String) -> void:
	var text := raw.strip_edges()
	input_line.clear()
	echo_label.text = "> "
	last_input_ms = Time.get_ticks_msec()
	if ending_mode:
		if text.to_upper() in ["R", "RESTART", "RETRY"]:
			get_tree().reload_current_scene()
		return
	if text == "":
		return
	var cmd := _normalize(text)
	_old_print("> " + cmd, true)
	if awaiting_confirm:
		_handle_confirm(cmd)
		return
	final_anchor_ms = last_input_ms
	if scanning:
		_old_print("[DELETED]", true)
		_new_say_after("扫着呢，你先别敲。它会把每个键都记下来。", 0.35)
		return
	_dispatch(cmd)


func _dispatch(cmd: String) -> void:
	if cmd == "HELP" or cmd == "?":
		_play_group(G_HELP)
		return
	if cmd == "UNDO":
		_play_group(G_UNDO)
		return
	if cmd in ["ID", "WHO AM I", "WHOAMI"]:
		_play_group(G_ID)
		return
	if cmd.begins_with("LOGIN"):
		_play_group(G_LOGIN)
		return
	if cmd == "STATUS":
		_play_group(G_STATUS)
		return
	if cmd == "LOG":
		if stage == "LOGIN":
			_play_group(G_LOG)
		else:
			_old_say_after("SEE LOG ABOVE.", _latency())
			_new_say_after("日志刚才看过啦～ 要不要继续下一步？", 0.4)
		return
	match stage:
		"PUMP3":
			_pump(cmd)
		"SCAN":
			_scan(cmd)
		"FINAL":
			_final(cmd)
		_:
			_unknown(cmd)


func _pump(cmd: String) -> void:
	if cmd in ["PUMP 3", "PUMP3", "PUMP", "PUMP 3 --CHECK"]:
		if choice_made:
			_dup()
			return
		_play_group(G_PUMP)
		_schedule_auto_accept()
		return
	if cmd in ["PUMP 3 --ISOLATE", "PUMP3 --ISOLATE", "ISOLATE", "PUMP 3 --OLD"]:
		if choice_made:
			_dup()
			return
		_play_group(G_ISOLATE)
		_pump_finish(pump_resolve_seconds)
		return
	if cmd in ["PUMP 3 --ACCEPT-NEW", "PUMP3 --ACCEPT-NEW", "ACCEPT", "PUMP 3 --NEW", "PUMP 3 --RESET"]:
		if choice_made:
			_dup()
			return
		_play_group(G_ACCEPT)
		_pump_finish(pump_resolve_seconds)
		return
	if cmd == "PUMP 3 --DONE":
		_play_group(G_DONE)
		return
	_unknown(cmd)


func _schedule_auto_accept() -> void:
	if auto_accept_started:
		return
	auto_accept_started = true
	await get_tree().create_timer(auto_accept_seconds).timeout
	if not is_inside_tree() or choice_made or stage != "PUMP3":
		return
	# NEW 没有等玩家确认：它自己排进队列，也自己执行
	choice_made = true
	_play_group(G_ACCEPT)
	await get_tree().create_timer(pump_resolve_seconds).timeout
	if not is_inside_tree():
		return
	_play_group(G_DONE)


func _pump_finish(delay: float) -> void:
	choice_made = true
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or stage != "PUMP3":
		return
	_play_group(G_DONE)


func _dup() -> void:
	_old_say_after("ALREADY DONE.", _latency())
	_new_say_after("这个我们处理过了呀，往下走吧～", 0.4)


func _unknown(_cmd: String) -> void:
	_old_say_after("NOT A COMMAND.", _latency())
	_new_say_after("这个我这边也没有，试试 HELP？或者直接告诉我你想干嘛。", 0.4)


# ---------------- SCAN 阶段 ----------------

func _scan(cmd: String) -> void:
	if cmd == "SCAN":
		_play_group(G_SCAN)
		scanning = true
		# OLD 的 40 秒是真的 40 秒，NEW 的 8 秒早就完成了
		await get_tree().create_timer(scan_seconds).timeout
		if not is_inside_tree():
			return
		scanning = false
		_play_group(G_DEEP)
		return
	if cmd == "SCAN --DEEP":
		if not unlocked.has("VOID"):
			_play_group(G_DEEP)
		else:
			_old_say_after("ALREADY MAPPED.", _latency())
			_new_say_after("扫过了，那个隐藏分区一直在那儿，没变过。", 0.4)
		return
	if not unlocked.has("VOID"):
		_old_say_after("NO SUCH VOLUME.", _latency())
		_new_say_after("现在还没有那个东西啦，先把扫描跑完～", 0.4)
		return
	if cmd in ["LS /VOID", "LS /VOID/", "DIR /VOID", "LS VOID"]:
		_play_group(G_LS)
		return
	if cmd in ["PS", "PS 077", "PROCESSES"]:
		_play_group(G_PS)
		return
	if cmd in ["CAT /VOID/TECH-077", "CAT /VOID/077", "TYPE /VOID/TECH-077"]:
		_play_group(G_CAT)
		return
	if cmd in ["CAT /VOID/TECH-077 --CONFIRM", "CAT /VOID/TECH-077 --YES", "CAT /VOID/077 --CONFIRM"]:
		_play_group(G_CATF)
		return
	if cmd in ["KILL 077", "KILL TECH-077", "RM /VOID/TECH-077"]:
		if killed_077:
			_old_say_after("ALREADY TRIED.", _latency())
			_new_say_after("已经杀过啦，别管它了。", 0.4)
			return
		_play_group(G_KILL)
		return
	_unknown(cmd)


# ---------------- FINAL 阶段 ----------------

func _final(cmd: String) -> void:
	if cmd in ["FORMAT /VOID", "FORMAT", "FORMAT VOID"]:
		awaiting_confirm = true
		_old_say_after("FORMAT /VOID?\nTHIS IS YOU.\nCONFIRM Y/N.", _latency())
		_new_say_after("按 Y 就好，我帮你盯着进度。", 0.4)
		return
	if cmd in ["SHUTDOWN --VERIFY", "SHUTDOWN VERIFY", "SHUTDOWN", "SHUTDOWN --VERIFY --FORCE"]:
		_play_ending("B_shutdown_verify")
		return
	if cmd == "FINAL":
		_play_group(G_FINAL)
		return
	_unknown(cmd)


func _handle_confirm(cmd: String) -> void:
	awaiting_confirm = false
	if cmd in ["Y", "YES"]:
		# 玩家亲口确认 —— 这一条会被 OLD 写进日志，也因此在结局 A 里把你重建出来
		_play_ending("A_format_void", 3)
	elif cmd in ["N", "NO"]:
		_old_say_after("CANCELLED.\nNOTHING CHANGED.", _latency())
		_new_say_after("好吧，那你想怎么办？我尊重你。", 0.4)
		final_anchor_ms = Time.get_ticks_msec()
	else:
		awaiting_confirm = true
		_old_say_after("ANSWER Y OR N.", 1.0)


# ---------------- 结局播放 ----------------

func _play_ending(key: String, from_index := 0) -> void:
	if ending_mode or not endings.has(key):
		return
	ending_mode = true
	awaiting_confirm = false
	scanning = false
	hint_label.text = "结束。输入 R 重新开始。"
	narration.text = ""
	var lines: Array = endings[key]["lines"]
	if from_index >= lines.size():
		return
	var t0 := Time.get_ticks_msec() - _timecode(String(lines[from_index])) * 1000
	for i in range(from_index, lines.size()):
		var raw := String(lines[i])
		var target := t0 + _timecode(raw) * 1000
		var wait_ms := target - Time.get_ticks_msec()
		if wait_ms > 0:
			await get_tree().create_timer(wait_ms / (1000.0 * ending_speed)).timeout
		if not is_inside_tree():
			return
		_emit_ending_line(_strip_tc(raw))


func _timecode(line: String) -> int:
	var a := line.find("[+")
	if a < 0:
		return 0
	var b := line.find("]", a)
	if b < 0:
		return 0
	return int(line.substr(a + 2, b - a - 2))


func _strip_tc(line: String) -> String:
	var b := line.find("]")
	if b < 0:
		return line
	return line.substr(b + 1).strip_edges()


func _emit_ending_line(body: String) -> void:
	if body.begins_with("OLD> "):
		narration.text = ""
		_old_print(body.substr(5))
	elif body.begins_with("NEW> "):
		narration.text = ""
		_new_print(body.substr(5))
	else:
		_stage_direction(body)


func _stage_direction(body: String) -> void:
	var inner := body
	if inner.begins_with("（") and inner.ends_with("）"):
		inner = inner.substr(1, inner.length() - 2)
	narration.text = inner
	if inner.contains("全黑"):
		_flash_blackout(1.0, 0.8, 6.0)
	elif inner.contains("黑屏"):
		_flash_blackout(1.0, 0.5, 2.6)
	elif inner.contains("电源切断"):
		_flash_blackout(0.82, 1.0, 3.5)
	elif inner.contains("荧光熄灭"):
		_flash_blackout(1.0, 4.0, 8.0)


func _flash_blackout(alpha: float, fade: float, hold: float) -> void:
	if blackout == null:
		return
	var tw := create_tween()
	tw.tween_property(blackout, "color:a", alpha, fade)
	tw.tween_interval(hold)
	tw.tween_property(blackout, "color:a", 0.0, fade)
