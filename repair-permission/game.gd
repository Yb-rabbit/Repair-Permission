extends Control
## Repair Permission —— 双终端最小实现
## 对白全部来自 res://script_data.json；命令表是 Dictionary：命令 -> {old, new, cb}

const DATA_PATH := "res://script_data.json"
const POPUP_SCRIPT := preload("res://popup.gd")

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

var history: Array[String] = []        # 玩家全部输入，终局回放用
var pending_old: Array[String] = []    # OLD 的延迟输出队列
var junk_count := 0
var temp := 0                          # 隐藏数值：NEW 每替你做一次决定 +2
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

var _popup: PanelContainer = null      # 当前显示的提示弹窗
var _popup_queue: Array[Dictionary] = []
var _hints_seen: Dictionary = {}       # 每个提示只弹一次


func _ready() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("缺少 " + DATA_PATH)
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


# ---------------- 初始化 ----------------

func _setup_fonts() -> void:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Microsoft YaHei UI", "Courier New"])
	var sans := SystemFont.new()
	sans.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	old_text.add_theme_font_override("normal_font", mono)
	old_text.add_theme_font_size_override("normal_font_size", 15)
	new_text.add_theme_font_override("normal_font", sans)
	new_text.add_theme_font_size_override("normal_font_size", 16)
	input_line.add_theme_font_override("font", mono)
	input_line.add_theme_font_size_override("font_size", 16)


func _setup_ui() -> void:
	old_text.scroll_following = true
	new_text.scroll_following = true
	new_text.visible_characters = -1
	pump_bar.max_value = 100
	scan_bar.max_value = 100
	bar3.max_value = 20
	bar3.value = 0
	input_line.placeholder_text = "输入命令，回车执行"


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
	}


func _build_commands() -> void:
	for key in data.commands:
		var c: Dictionary = data.commands[key]
		commands[str(key)] = {
			"old": c.old,
			"new": str(c.new),
			"cb": actions.get(str(c.action), _act_none),
		}


# ---------------- 输入：三层匹配 ----------------

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

	# 扫描期间：什么键都只换来一行 DELETED
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
		_new_say("我帮你补全成 " + full + " 了，直接跑 :)")
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


# ---------------- 两台终端的输出 ----------------

func _old_say(lines: Array) -> void:
	if lines.is_empty():
		return
	if pending_old.is_empty():
		_old_print("...", true)          # 延迟感：先来一行省略号
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


# ---------------- 命令回调 ----------------

func _act_none() -> void:
	pass


func _act_pump() -> void:
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 40.0, 1.0)


func _act_isolate() -> void:
	var tw := create_tween()
	tw.tween_property(pump_bar, "value", 60.0, 2.0)


func _act_accept() -> void:
	temp += 2                            # 隐藏数值：没有任何提示
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


# ---------------- SCAN /FULL：15 秒 + NEW 插话 2 次 ----------------

func _on_scan_tick() -> void:
	scan_time += scan_timer.wait_time
	scan_bar.value = clampf(scan_time / scan_duration * 100.0, 0.0, 100.0)
	if scan_stage == 0 and scan_time >= scan_duration / 3.0:
		scan_stage = 1
		_new_say("还差十秒，我这边已经出结果了，要不要先看 :)")
	elif scan_stage == 1 and scan_time >= scan_duration * 2.0 / 3.0:
		scan_stage = 2
		_new_say("喂，老屏幕刚才也把你扫了一遍，扫得比我还细")
	elif scan_time >= scan_duration:
		scan_timer.stop()
		scan_stage = 3
		scan_done = true
		scan_bar.value = 100.0
		_new_say("扫完啦，/VOID 里有个东西，名字叫 TECH-077")
		_old_say(["SCAN DONE", "VOL 3 /VOID", "SIZE 077 GB", "MOUNTED 1979"])
		_hint("scan", "值班手册 04 · 隐藏分区", "[color=#8fe3ff]扫描结束，/VOID 已挂载。[/color]\n\n试试 [color=#8fe3ff]LS /VOID[/color]、[color=#8fe3ff]PS[/color]、[color=#8fe3ff]CAT /VOID/TECH-077[/color]。\n两台机器报的数目可能不一样——先记下你亲眼看到的那一个。")


# ---------------- 终局：逐条回放 + 结局 ----------------

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
	input_line.placeholder_text = "结局播放中 · 按 R 重来"
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


# ---------------- 提示弹窗：可拖动 / 可关闭 / 可确认 ----------------

func _hint(id: String, title: String, body: String) -> void:
	if in_ending or _hints_seen.has(id):
		return
	_hints_seen[id] = true
	_popup_queue.append({"title": title, "body": body})
	_pump_popup()


func _hint_for(cmd: String) -> void:
	match cmd:
		"LOGIN 077":
			_hint("login", "值班手册 02 · 已登录", "操作员 [color=#8fe3ff]TECH-077[/color]，夜班，班次 1/1。\n\n下一步：敲 [color=#8fe3ff]PUMP 3[/color] 看一眼三号泵。")
		"PUMP 3":
			_hint("pump3", "值班手册 03 · 两条路", "[color=#8fe3ff]PUMP 3 --ISOLATE[/color] — OLD 的机械隔离。慢，但每一步都有纸面记录。\n[color=#8fe3ff]PUMP 3 --ACCEPT-NEW[/color] — NEW 的远程修复。快，记录由它来写。\n\n两条路都能推进，但记录会不一样。选之前先 [color=#8fe3ff]STATUS[/color]。")
		"CAT /VOID/TECH-077":
			_hint("cat", "值班手册 05 · 你已经看到了", "[color=#8fe3ff]KILL 077[/color] 能结束那个进程（两台机器会给出两种答案）。\n\n收场只有两种：[color=#8fe3ff]FORMAT /VOID[/color] 或 [color=#8fe3ff]SHUTDOWN --VERIFY[/color]。\n选哪个都行——但记住你刚才亲眼看到的东西。")


func _show_boot_hint() -> void:
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree() or in_ending:
		return
	_hint("boot", "值班手册 01 · 目标", "[color=#8fe3ff]查清三号泵为什么在夜里自己启动。[/color]\n\n· 命令不区分大小写，输入 [color=#8fe3ff]HELP[/color] 看全部。\n· 只打前几个字母也行，回车自动补全。\n· 本窗口可拖动标题栏、点 × 关闭，按 ESC 也能关。")


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

