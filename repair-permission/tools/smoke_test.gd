extends SceneTree
## 冒烟测试：把时间参数调小，跑完命令表、三层匹配、隐藏值、回放与两个结局。
## 运行：godot --headless --path . --script res://tools/smoke_test.gd
## 结果：res://smoke_result.txt（逐行 flush）

var main: Node
var f: FileAccess
var passed := 0
var failed := 0


func _initialize() -> void:
	f = FileAccess.open("res://smoke_result.txt", FileAccess.WRITE)
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.25).timeout

	main.old_timer.stop()
	main.pending_old.clear()
	main.old_timer.wait_time = 0.05
	main.replay_timer.wait_time = 0.01
	main.end_timer.wait_time = 0.01
	main.scan_timer.wait_time = 0.05
	main.scan_duration = 0.4

	_check("commands_loaded", main.commands.size() == 18, str(main.commands.size()))
	_check("initial_prefill", main.input_line.text == "LOGIN", main.input_line.text)
	_check("initial_prefill_selected", main.input_line.has_selection(), "")

	main.input_line.text_submitted.emit(main.input_line.text)
	await _tick()
	_check("login_match", main.last_cmd == "LOGIN 077", main.last_cmd)
	var login_body := str(main._hints_seen.get("login", {}).get("body", ""))
	_check("hint02_mentions_log", login_body.contains("LOG"), "")
	var p: PanelContainer = main._popup
	_check("popup_after_login", is_instance_valid(p) and p.visible, "")
	_check("popup_has_title", p != null and p.title_text().contains("02"), p.title_text() if p != null else "")

	await create_timer(1.3).timeout
	_check("popup_queue_waiting", main._popup_queue.size() >= 1, str(main._popup_queue.size()))
	var boot_body := str(main._hints_seen.get("boot", {}).get("body", ""))
	_check("hint01_mentions_manual_id", boot_body.contains("MANUAL") and boot_body.contains("ID"), "")
	var before: Vector2 = p.position
	p._begin_drag(Vector2(400, 300))
	p._drag_to(Vector2(120, 520))
	p._end_drag()
	_check("popup_dragged", p.position != before, str(p.position))
	var vp: Vector2 = main.get_viewport_rect().size
	_check("popup_in_view", p.position.x >= 8.0 and p.position.x <= vp.x - 40.0 and p.position.y <= vp.y - 40.0, "")
	p._on_confirm()
	await create_timer(0.1).timeout
	_check("popup_confirm_closed", not is_instance_valid(main._popup), "")
	await create_timer(0.7).timeout
	_check("popup_queue_advanced", is_instance_valid(main._popup) and main._popup.title_text().contains("01"), main._popup.title_text() if is_instance_valid(main._popup) else "none")

	main._on_submit("MANUAL")
	await _tick()
	_check("manual_match", main.last_cmd == "MANUAL", main.last_cmd)
	_check("manual_requeued", main._popup_queue.size() == 2, str(main._popup_queue.size()))
	main._clear_popups()

	main._on_submit("HELP")
	await _tick()
	_check("exact_match", main.last_cmd == "HELP", main.last_cmd)
	_check("old_ellipsis", main.old_text.get_parsed_text().contains("..."), "")
	_check("new_help_mentions_log", main.new_text.get_parsed_text().contains("LOG"), "")

	main._on_submit("PUMP")
	await _tick()
	_check("fuzzy_match", main.last_cmd == "PUMP 3", main.last_cmd)
	_check("old_correction", main.old_text.get_parsed_text().contains("PARTIAL MATCH"), "")
	var pump_body := str(main._hints_seen.get("pump3", {}).get("body", ""))
	_check("hint03_mentions_scan_full", pump_body.contains("SCAN /FULL"), "")

	main._on_submit("ZZZ")
	await _tick()
	_check("junk_1", main.junk_count == 1, str(main.junk_count))
	_check("junk_1_room", main.old_text.get_parsed_text().contains("ROOM 2 PERSONS"), "")
	main._on_submit("YYY")
	await _tick()
	_check("junk_2_clock", main.old_text.get_parsed_text().contains("LOGGED "), "")
	main._on_submit("QQQ")
	await _tick()
	_check("junk_3_egg", main.old_text.get_parsed_text().contains("ONLY YOU"), "")

	main._on_submit("PUMP 3 --ACCEPT-NEW")
	await _tick()
	_check("hidden_temp", main.temp == 2, str(main.temp))
	_check("bar3_value", int(main.bar3.value) == 2, str(main.bar3.value))

	main._on_submit("KILL 077")
	await _tick()
	_check("void_killed", main.void_killed, "")
	main._on_submit("LS /VOID")
	await _tick()
	_check("new_side_void_zero", main.new_text.get_parsed_text().contains("0 items"), "")
	_check("old_side_void_one", main.old_text.get_parsed_text().contains("/VOID 1 FILE"), "")

	main._on_submit("CAT /VOID/TECH-077")
	await _tick()
	var scan_pos: int = main._hint_order.find("scan")
	var cat_pos: int = main._hint_order.find("cat")
	_check("cat_hint_order_guard", scan_pos >= 0 and cat_pos > scan_pos, str(main._hint_order))
	main._clear_popups()

	main._on_submit("SCAN /FULL")
	main._on_submit("HELLO")
	await create_timer(0.05).timeout
	_check("scan_input_locked", main.old_text.get_parsed_text().contains("[ DELETED ]"), "")
	_check("scan_input_still_logged", main.history[-1] == "HELLO", main.history[-1])
	await create_timer(0.8).timeout
	_check("scan_done", main.scan_done, str(main.scan_stage))
	_check("scan_bar_full", int(main.scan_bar.value) == 100, str(main.scan_bar.value))

	main._on_submit("FORMAT /VOID")
	await create_timer(0.05).timeout
	_check("ending_started", main.in_ending, "")
	_check("ending_input_locked", not main.input_line.editable, "")
	_check("popup_cleared_on_ending", main._popup == null and main._popup_queue.is_empty(), "")
	await create_timer(1.2).timeout
	_check("replay_all_inputs", main.replay_index == main.history.size(), str(main.replay_index) + "/" + str(main.history.size()))
	_check("ending_finished", main.ending_index == 14 and main.end_timer.is_stopped(), str(main.ending_index))

	_finish()


func _tick() -> void:
	await create_timer(0.12).timeout


func _check(name: String, cond: bool, extra: String) -> void:
	var line := ("PASS " if cond else "FAIL ") + name
	if extra != "":
		line += " = " + extra
	f.store_line(line)
	f.flush()
	if cond:
		passed += 1
	else:
		failed += 1


func _finish() -> void:
	f.store_line("SMOKE_DONE passed=%d failed=%d" % [passed, failed])
	f.flush()
	f.close()
	quit()
