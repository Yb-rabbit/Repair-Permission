extends SceneTree
## 冒烟测试：把时间参数调小，跑完命令表、三层匹配、隐藏值、回放与三个结局。
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
	_check("boot_input_hidden", not main.boot_done and not main.input_line.visible, "")
	_check("boot_skip_hint", main.restart_hint.visible and main.restart_hint.text == "SKIP: ESC", main.restart_hint.text)
	main._on_submit("HELP")
	_check("boot_input_ignored", main.history.is_empty(), str(main.history))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main._unhandled_key_input(esc)        # smoke test skips the 15-line boot sequence
	_check("boot_skip_esc", main.boot_done, "")
	_check("boot_lines_written", main.old_text.get_parsed_text().contains("REPAIR PERMISSION // NIGHT SHIFT") and main.old_text.get_parsed_text().contains("READY."), "")
	_check("boot_skip_hint_hidden", not main.restart_hint.visible, "")
	_check("audio_room_and_old_layers", main._audio != null and main._audio.room_player.playing and main._audio.old_player.playing, "")
	_check("audio_new_layer_after_boot", main._audio.new_layer_on and main._audio.new_player.playing, "")

	main.old_timer.stop()
	main.pending_old.clear()
	main.old_timer.wait_time = 0.05
	main.replay_timer.wait_time = 0.01
	main.end_timer.wait_time = 0.01
	main.scan_timer.wait_time = 0.05
	main.scan_duration = 0.4

	_check("commands_loaded", main.commands.size() == 20, str(main.commands.size()))
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
	_check("popup_connected_sfx", p != null and p._connected_sfx != null and p._connected_sfx.playing, "")

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
	var disconnected_players := 0
	for child in main.get_tree().root.get_children():
		if child is AudioStreamPlayer and child.stream == load("res://disconnected.wav"):
			disconnected_players += 1
	_check("popup_disconnected_sfx", disconnected_players > 0, str(disconnected_players))
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
	_check("audio_accept_hum", main._audio.tension_on and main._audio.tension_player.playing, "")

	main._on_submit("KILL 077")
	await _tick()
	_check("void_killed", main.void_killed, "")
	_check("audio_kill_silences_new", not main._audio.new_layer_on, "")
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
	_check("audio_scan_stops_hum", not main._audio.tension_on, "")
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

	# C requires the full scan, then can be entered directly with the overflow date.
	main = await _fresh_main()
	main._on_submit("SET DATE 2038-01-19")
	await _tick()
	_check("inherit_requires_scan", not main.in_ending and main.old_text.get_parsed_text().contains("FULL SCAN REQUIRED"), "")

	main.scan_done = true
	main._on_submit("SET DATE 2038-01-19")
	await create_timer(1.35).timeout
	_check("inherit_direct_started", main.in_ending and main.ending_key == "inherit", main.ending_key)
	_check("inherit_clock_overflow", main.clock_label.text == "1901-12-13 20:45:52", main.clock_label.text)
	_check("inherit_epoch_negative", main.epoch_label.text == "EPOCH: -2147483648", main.epoch_label.text)
	_check("inherit_patch_replay", main.replay_index == main.history.size() and main.old_text.get_parsed_text().contains("[PATCH]"), str(main.replay_index))
	_check("inherit_black_screen", is_equal_approx(main.crt.color.a, 1.0), str(main.crt.color))
	_check("inherit_restart_hint", main.restart_hint.visible and main.restart_hint.text == "PRESS R TO RESTART", main.restart_hint.text)
	_check("inherit_final_line", main.final_line.visible and main.final_line.text.contains("077 INHERITED"), main.final_line.text)
	_check("inherit_ending_finished", main.ending_index == main.data.endings.inherit.size() and main.end_timer.is_stopped(), str(main.ending_index))

	# The documented shorthand dates must take the same route.
	main = await _fresh_main()
	main.scan_done = true
	main._on_submit("SET DATE 2038-1-19")
	await _tick()
	_check("inherit_date_short_month", main.in_ending and main.ending_key == "inherit", main.ending_key)

	main = await _fresh_main()
	main.scan_done = true
	main._on_submit("SET DATE 38-01-19")
	await _tick()
	_check("inherit_date_short_year", main.in_ending and main.ending_key == "inherit", main.ending_key)

	# KILL 077 opens a 60s window; any input cancels it, and silence enters C.
	main = await _fresh_main()
	main.scan_done = true
	main.inherit_timer.wait_time = 0.25
	main._on_submit("KILL 077")
	await _tick()
	_check("inherit_window_started", not main.inherit_timer.is_stopped(), "")
	main._on_submit("LS /VOID")
	await _tick()
	_check("inherit_window_cancelled", main.inherit_timer.is_stopped() and not main.in_ending, "")
	main._on_submit("KILL 077")
	await _tick()
	await create_timer(0.4).timeout
	_check("inherit_timeout_started", main.in_ending and main.ending_key == "inherit", main.ending_key)

	# A/B must win over an open inheritance window.
	main = await _fresh_main()
	main.scan_done = true
	main.inherit_timer.wait_time = 0.3
	main._on_submit("KILL 077")
	await _tick()
	main._on_submit("FORMAT /VOID")
	await _tick()
	_check("ab_priority_over_inherit", main.in_ending and main.ending_key == "format" and main.inherit_timer.is_stopped(), main.ending_key)

	# Soft gate: SCAN still runs; OLD records the unserviced pump and replays it.
	main = await _fresh_main()
	main._on_submit("SCAN /FULL")
	await _tick()
	_check("soft_gate_logged", main.history.has("* PUMP UNSERVICED. LOGGED."), str(main.history))
	await create_timer(0.5).timeout
	_check("soft_gate_scan_runs", main.scan_done, str(main.scan_stage))
	_check("soft_gate_old_line", main.old_text.get_parsed_text().contains("PUMP UNSERVICED. LOGGED."), "")
	main.old_text.clear()
	main.scan_done = true
	main._on_submit("FORMAT /VOID")
	await create_timer(1.2).timeout
	_check("soft_gate_replayed", main.replay_index == main.history.size() and main.old_text.get_parsed_text().contains("PUMP UNSERVICED. LOGGED."), "")

	# Pump handled first -> no soft-gate record.
	main = await _fresh_main()
	main._on_submit("PUMP 3 --ISOLATE")
	await _tick()
	main._on_submit("SCAN /FULL")
	await _tick()
	_check("soft_gate_handled_silent", not main.history.has("* PUMP UNSERVICED. LOGGED."), str(main.history))

	_finish()


func _fresh_main() -> Node:
	main.queue_free()
	await create_timer(0.05).timeout
	var next_main: Node = load("res://Main.tscn").instantiate()
	root.add_child(next_main)
	await create_timer(0.25).timeout
	next_main._finish_boot(true)          # smoke test skips the 15-line boot sequence
	next_main.old_timer.stop()
	next_main.pending_old.clear()
	next_main.old_timer.wait_time = 0.02
	next_main.replay_timer.wait_time = 0.01
	next_main.end_timer.wait_time = 0.01
	next_main.scan_timer.wait_time = 0.05
	next_main.scan_duration = 0.4
	# Suppress the delayed boot popup in the short C-only scenes.
	next_main._hints_seen["boot"] = {"title": "", "body": ""}
	next_main._clear_popups()
	return next_main


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
