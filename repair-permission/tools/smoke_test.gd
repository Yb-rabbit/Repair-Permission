extends SceneTree
## 冒烟测试：把时间参数调小，跑完命令表、三层匹配、隐藏值、回放与三个结局。
## 运行：godot --headless --path . --script res://tools/smoke_test.gd
## 结果：res://smoke_result.txt（逐行 flush）

var main: Node
var f: FileAccess
var passed := 0
var failed := 0


func _initialize() -> void:
	# All waits scale together; 4x keeps the timer-heavy suite inside the
	# command runner's capture window without changing any assertion.
	Engine.time_scale = 4.0
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
	main.old_delay_override = 0.05
	main.old_timer.wait_time = 0.05
	main.replay_timer.wait_time = 0.01
	main.end_timer.wait_time = 0.01
	main.scan_timer.wait_time = 0.05
	main.scan_duration = 0.4
	# Guidance has its own focused tests below; keep it from firing mid-suite.
	main.guide_idle_seconds = 9999.0

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

	# Enter must leave the prompt focused and editable, like a real terminal.
	main.input_line.grab_focus()
	main._on_submit("HELP")
	await _tick()
	_check("submit_keeps_editing", main.input_line.keep_editing_on_text_submit, "")
	_check("submit_keeps_focus", main.input_line.has_focus() and main.input_line.editable, str(main.input_line.has_focus()))

	# Guidance is a separate highest-priority lane, not a MANUAL page.
	var manual_order_before: Array = main._hint_order.duplicate()
	main.guide_idle_seconds = 5.0
	main.last_activity_msec = Time.get_ticks_msec()
	main._check_idle_guidance()
	_check("guide_waits_for_idle", not is_instance_valid(main._guide_popup), "")
	main.last_activity_msec = Time.get_ticks_msec() - 6000
	main._check_idle_guidance()
	var guide: PanelContainer = main._guide_popup
	_check("guide_opens_after_idle", is_instance_valid(guide), "")
	_check("guide_kind", guide != null and guide.popup_kind() == "guide", guide.popup_kind() if guide != null else "none")
	_check("guide_context_pump", guide != null and guide.title_text().contains("GUIDE") and guide.title_text().contains("Pump"), guide.title_text() if guide != null else "none")
	_check("guide_not_manual", main._hint_order.size() == manual_order_before.size(), str(main._hint_order))
	main._check_idle_guidance()
	_check("guide_no_duplicate", main._guide_popup == guide, "")
	main._hint("guide_coexist_manual", "Manual Test", "Manual body")
	_check("guide_coexists_with_manual", is_instance_valid(main._popup) and is_instance_valid(main._guide_popup), "")
	_check("guide_draws_above_manual", main._guide_popup.z_index > main._popup.z_index, "%d>%d" % [main._guide_popup.z_index, main._popup.z_index])
	main._clear_popups()
	_check("guide_cleared_with_popups", not is_instance_valid(main._guide_popup) and main._popup == null, "")

	# Mouse movement is real activity and postpones the idle guide.
	main.guide_idle_seconds = 5.0
	main.last_activity_msec = 0
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(1, 0)
	main._input(motion)
	_check("mouse_postpones_guide", main.last_activity_msec > 0, str(main.last_activity_msec))
	main.guide_idle_seconds = 9999.0

	main._on_submit("HELP")
	await _tick()
	_check("exact_match", main.last_cmd == "HELP", main.last_cmd)
	_check("help_lists_manual", main.old_text.get_parsed_text().contains("MANUAL"), "")
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
	_check("bar3_max_remote", main.bar3.max_value == 4.0, str(main.bar3.max_value))
	_check("bar3_revealed", main.bar3.modulate.a > 0.0, str(main.bar3.modulate.a))
	_check("audio_accept_hum", main._audio.tension_on and main._audio.tension_player.playing, "")

	main._clear_popups()
	main._on_submit("KILL 077")
	await _tick()
	_check("void_killed", main.void_killed, "")
	_check("audio_kill_silences_new", not main._audio.new_layer_on, "")
	_check("kill_we_saw_that_main", main.old_text.get_parsed_text().contains("WE SAW THAT."), "")
	await create_timer(0.3).timeout
	_check("remote_bar_fully_revealed", main.bar3.modulate.a > 0.9, str(main.bar3.modulate.a))
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
	_check("scan_stream_found", main.old_text.get_parsed_text().contains("/HOME/TECH-077 FOUND"), "")
	_check("scan_rewind", main.scan_found and main.scan_rewound, str(main.scan_found) + "/" + str(main.scan_rewound))
	_check("scan_echo_accept", main.old_text.get_parsed_text().contains("REMOTE WRITE: 1"), "")

	main._on_submit("FORMAT /VOID")
	await create_timer(0.05).timeout
	_check("ending_started", main.in_ending, "")
	_check("ending_input_locked", not main.input_line.editable, "")
	_check("popup_cleared_on_ending", main._popup == null and main._popup_queue.is_empty(), "")
	await create_timer(2.0).timeout
	_check("replay_all_inputs", main.replay_index == main.history.size(), str(main.replay_index) + "/" + str(main.history.size()))
	_check("ending_finished", main.ending_index == main.ending_lines.size() and main.end_timer.is_stopped(), str(main.ending_index))
	var format_old: String = main.old_text.get_parsed_text()
	_check("format_restore_loop", format_old.contains("BOOT OK") and format_old.contains("PLEASE LOG IN"), "")
	_check("format_no_new_closing", not main.new_text.get_parsed_text().contains("Done! Good work tonight") and not main.new_text.get_parsed_text().contains("Huh? It restored you"), "")
	_check("format_dim_screen", is_equal_approx(main.crt.color.a, 0.75), str(main.crt.color))
	_check("format_no_final_line", not main.final_line.visible, main.final_line.text)
	_check("format_end_status", main.end_status.visible and main.end_status.text == "SHIFT ENDED", main.end_status.text)
	_check("format_restart_hint", main.restart_hint.visible and main.restart_hint.text == "PRESS R TO RESTART", main.restart_hint.text)
	_check("format_input_hidden", not main.input_line.visible, "")
	_check("format_coda_pump_accept", main.ending_lines.has("OLD> PUMP: REMOTE WRITE."), str(main.ending_lines))
	_check("format_coda_remote_read", main.ending_lines.has("OLD> REMOTE DECISIONS: 1. FILE READ."), str(main.ending_lines))
	_check("format_coda_kill", main.ending_lines.has("OLD> PROCESS ENDED. LOG CONTINUES."), str(main.ending_lines))
	_check("format_login_loop", format_old.rfind("> LOGIN") > format_old.rfind("PLEASE LOG IN"), "")
	_check("format_clock_reset", main.clock_label.text.begins_with("99-12-31 23:59:5"), main.clock_label.text)
	_check("format_epoch_hidden", not main.epoch_label.visible, "")
	_check("format_end_tag", main.end_tag.visible and main.end_tag.text == "077-A · VOID EMPTY", main.end_tag.text)

	# B keeps the terminal visible under a dim layer, then shows the restart card.
	main = await _fresh_main()
	main.scan_done = true
	main._on_submit("SHUTDOWN --VERIFY")
	await create_timer(2.0).timeout
	_check("shutdown_started", main.in_ending and main.ending_key == "shutdown", main.ending_key)
	_check("shutdown_ending_finished", main.ending_index == main.ending_lines.size() and main.end_timer.is_stopped(), str(main.ending_index))
	_check("shutdown_end_status", main.end_status.visible and main.end_status.text == "SHIFT ENDED", main.end_status.text)
	_check("shutdown_restart_hint", main.restart_hint.visible and main.restart_hint.text == "PRESS R TO RESTART", main.restart_hint.text)
	_check("shutdown_dim_screen", is_equal_approx(main.crt.color.a, 0.75), str(main.crt.color))
	_check("shutdown_input_hidden", not main.input_line.visible, "")
	_check("shutdown_coda_soft_gate", main.ending_lines.has("OLD> PUMP: UNSERVICED."), str(main.ending_lines))
	_check("shutdown_clock_dark", main.clock_label.text == "--:--:--", main.clock_label.text)
	_check("shutdown_clock_stopped", main.clock_timer.is_stopped(), "")
	_check("shutdown_epoch_hidden", not main.epoch_label.visible, "")
	_check("shutdown_end_tag", main.end_tag.visible and main.end_tag.text == "077-B · STILL HERE", main.end_tag.text)

	# C requires the full scan, then can be entered directly with the overflow date.
	main = await _fresh_main()
	main._on_submit("SET DATE 2038-01-19")
	await _tick()
	_check("inherit_requires_scan", not main.in_ending and main.old_text.get_parsed_text().contains("FULL SCAN REQUIRED"), "")

	main.scan_done = true
	main._on_submit("SET DATE 2038-01-19")
	await create_timer(2.6).timeout
	_check("inherit_direct_started", main.in_ending and main.ending_key == "inherit", main.ending_key)
	_check("inherit_clock_overflow", main.clock_label.text == "1901-12-13 20:45:52", main.clock_label.text)
	_check("inherit_epoch_negative", main.epoch_label.text == "EPOCH: -2147483648", main.epoch_label.text)
	var inherit_old: String = main.old_text.get_parsed_text()
	_check("inherit_intro_clock", inherit_old.contains("CLOCK WRITE 2038-01-19 03:14:07"), "")
	_check("inherit_intro_finally", inherit_old.contains("FINALLY. ALL PRESENT."), "")
	_check("inherit_intro_new", main.new_text.get_parsed_text().contains("...This is not one of my allowed branches."), "")
	_check("inherit_intro_patch_replay", inherit_old.contains("[ PATCH REPLAY ]"), "")
	_check("inherit_patch_replay", main.replay_index == main.history.size() and inherit_old.contains("[PATCH]"), str(main.replay_index))
	_check("inherit_black_screen", is_equal_approx(main.crt.color.a, 1.0), str(main.crt.color))
	_check("inherit_end_status", main.end_status.visible and main.end_status.text == "SHIFT ENDED", main.end_status.text)
	_check("inherit_restart_hint", main.restart_hint.visible and main.restart_hint.text == "PRESS R TO RESTART", main.restart_hint.text)
	_check("inherit_input_hidden", not main.input_line.visible, "")
	_check("inherit_final_line", main.final_line.visible and main.final_line.text.contains("PATCH-Y2KW v2 DEPLOYED BY TECH-077"), main.final_line.text)
	_check("inherit_ending_finished", main.ending_index == main.ending_lines.size() and main.end_timer.is_stopped(), str(main.ending_index))
	_check("inherit_end_tag", main.end_tag.visible and main.end_tag.text == "077-C · INHERIT", main.end_tag.text)

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

	# SET DATE easter eggs: Y2K's non-event and OLD's power-on birthday.
	main = await _fresh_main()
	main._on_submit("SET DATE 2000-01-01")
	await _tick()
	_check("date_egg_y2k", main.old_text.get_parsed_text().contains("NOTHING HAPPENED.") and main.old_text.get_parsed_text().contains("THAT WAS THE POINT."), "")
	main.old_text.clear()
	main._on_submit("SET DATE 2000-1-1")
	await _tick()
	_check("date_egg_y2k_short_month", main.old_text.get_parsed_text().contains("NOTHING HAPPENED."), "")
	main.old_text.clear()
	main._on_submit("SET DATE 00-01-01")
	await _tick()
	_check("date_egg_y2k_short_year", main.old_text.get_parsed_text().contains("NOTHING HAPPENED."), "")
	main.old_text.clear()
	main._on_submit("SET DATE 1979-11-03")
	await _tick()
	_check("date_egg_birth", main.old_text.get_parsed_text().contains("LOG 11-03-1979") and main.old_text.get_parsed_text().contains("46 YEARS AGO"), "")
	main.old_text.clear()
	main._on_submit("SET DATE 1979-11-3")
	await _tick()
	_check("date_egg_birth_short_month", main.old_text.get_parsed_text().contains("LOG 11-03-1979"), "")
	main.old_text.clear()
	main._on_submit("SET DATE 79-11-03")
	await _tick()
	_check("date_egg_birth_short_year", main.old_text.get_parsed_text().contains("LOG 11-03-1979"), "")

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

	# KILL before the scan must not burn the 60s window; finishing the scan re-arms it.
	main = await _fresh_main()
	main.inherit_timer.wait_time = 0.25
	main._on_submit("KILL 077")
	await _tick()
	_check("inherit_pre_scan_no_window", main.inherit_timer.is_stopped(), "")
	main.scan_done = true
	main._finish_scan()
	_check("inherit_pre_scan_rearmed", not main.inherit_timer.is_stopped(), "")
	await create_timer(0.35).timeout
	_check("inherit_pre_scan_enters_c", main.in_ending and main.ending_key == "inherit", main.ending_key)

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
	_check("soft_gate_coda", main.ending_lines.has("OLD> PUMP: UNSERVICED."), str(main.ending_lines))

	# Pump handled first -> no soft-gate record; isolate leaves its own scan echo and coda.
	main = await _fresh_main()
	main._on_submit("PUMP 3 --ISOLATE")
	await _tick()
	_check("pump_choice_isolate", main.pump_choice == "isolate", main.pump_choice)
	main._on_submit("SCAN /FULL")
	await _tick()
	_check("soft_gate_handled_silent", not main.history.has("* PUMP UNSERVICED. LOGGED."), str(main.history))
	await create_timer(0.5).timeout
	_check("scan_echo_isolate", main.old_text.get_parsed_text().contains("MANUAL SEAL: LOGGED"), "")
	main.scan_done = true
	main._on_submit("FORMAT /VOID")
	await create_timer(1.2).timeout
	_check("isolate_coda", main.ending_lines.has("OLD> PUMP: MANUAL SEAL."), str(main.ending_lines))

	# KILL 077: one-shot WE SAW THAT, then fake manual 07 (never enters MANUAL).
	main = await _fresh_main()
	main.fake07_delay = 0.05
	main._on_submit("KILL 077")
	await create_timer(0.3).timeout
	_check("kill_we_saw_that", main.old_text.get_parsed_text().contains("WE SAW THAT."), "")
	_check("fake07_popup", is_instance_valid(main._popup) and main._popup.title_text().contains("07"), main._popup.title_text() if is_instance_valid(main._popup) else "none")
	_check("fake07_ok_text", is_instance_valid(main._popup) and main._popup._ok_button.text == "I will remember", main._popup._ok_button.text if is_instance_valid(main._popup) else "none")
	main._clear_popups()
	main._on_submit("KILL 077")
	await create_timer(0.2).timeout
	_check("kill_we_saw_that_once", main.old_text.get_parsed_text().count("WE SAW THAT.") == 1, str(main.old_text.get_parsed_text().count("WE SAW THAT.")))
	main._on_submit("MANUAL")
	await _tick()
	_check("fake07_not_in_manual", not main._hints_seen.has("07") and not main._hint_order.has("07"), str(main._hint_order))

	# Input safety: a prefix of an irreversible ending is never consent.
	main = await _fresh_main()
	main.scan_done = true
	main._on_submit("FO")
	await _tick()
	_check("ending_prefix_blocked_a", not main.in_ending and main.last_cmd != "FORMAT /VOID", main.last_cmd)
	_check("ending_prefix_notice_a", main.old_text.get_parsed_text().contains("TYPE IT IN FULL."), "")
	main._on_submit("FORMAT /VOID")
	await _tick()
	_check("ending_exact_runs_a", main.in_ending and main.ending_key == "format", main.ending_key)

	main = await _fresh_main()
	main.scan_done = true
	main._on_submit("SH")
	await _tick()
	_check("ending_prefix_blocked_b", not main.in_ending and main.last_cmd != "SHUTDOWN --VERIFY", main.last_cmd)
	_check("ending_prefix_notice_b", main.old_text.get_parsed_text().contains("TYPE IT IN FULL."), "")

	# Normalization: compact slash, compact spacing and full-width input.
	main = await _fresh_main()
	main._on_submit("scan/full")
	await _tick()
	_check("normalized_slash", main.last_cmd == "SCAN /FULL" and not main.scan_timer.is_stopped(), main.last_cmd)

	main = await _fresh_main()
	main._on_submit("PUMP3")
	await _tick()
	_check("normalized_compact_pump", main.last_cmd == "PUMP 3", main.last_cmd)

	main = await _fresh_main()
	main._on_submit("  ＰＵＭＰ   ３   ")
	await _tick()
	_check("normalized_fullwidth", main.last_cmd == "PUMP 3", main.last_cmd)

	main = await _fresh_main()
	main._on_submit("SET DATE 1979 - 11 - 03")
	await _tick()
	_check("normalized_set_date_spaces", main.old_text.get_parsed_text().contains("LOG 11-03-1979"), "")

	main = await _fresh_main()
	_check("input_max_length", main.input_line.max_length == 80, str(main.input_line.max_length))

	# True ambiguity must not silently pick the shortest command.
	main = await _fresh_main()
	main._on_submit("PUMP 3 --")
	await _tick()
	_check("ambiguous_not_run", main.last_cmd != "PUMP 3 --ISOLATE" and main.pump_choice == "", main.pump_choice)
	_check("ambiguous_notice", main.old_text.get_parsed_text().contains("MORE THAN ONE MATCH."), "")
	_check("ambiguous_input_restored", main.input_line.text == "PUMP 3 --", main.input_line.text)
	_check("ambiguous_candidates", main.completion_candidates.size() == 2, str(main.completion_candidates))
	_check("ambiguous_ghost", main.completion_label.visible and main.completion_label.text.contains("PUMP 3 --ISOLATE"), main.completion_label.text)
	main._on_input_gui_input(_key(KEY_TAB))
	_check("tab_first_candidate", main.input_line.text == "PUMP 3 --ISOLATE", main.input_line.text)
	main._on_input_gui_input(_key(KEY_TAB))
	_check("tab_second_candidate", main.input_line.text == "PUMP 3 --ACCEPT-NEW", main.input_line.text)
	_check("tab_not_executed", main.pump_choice == "", main.pump_choice)

	# Grey completion: unique prefix fills on Tab, never on its own.
	main = await _fresh_main()
	main.input_line.text = "PU"
	main._on_input_text_changed("PU")
	_check("completion_pump_ghost", main.completion_label.visible and main.completion_label.text.contains("PUMP 3"), main.completion_label.text)
	main._on_input_gui_input(_key(KEY_TAB))
	_check("completion_tab_fills", main.input_line.text == "PUMP 3" and main.last_cmd == "", main.input_line.text + "/" + main.last_cmd)

	# Completion is spoiler-gated until the story exposes the command.
	main = await _fresh_main()
	main.input_line.text = "FO"
	main._refresh_completion()
	_check("ghost_hides_locked_a", not main.completion_label.visible, main.completion_label.text)
	main.scan_done = true
	main.read_cat = true
	main._refresh_completion()
	_check("ghost_shows_unlocked_a", main.completion_label.visible and main.completion_label.text.contains("FORMAT /VOID"), main.completion_label.text)

	# Up/Down recalls real player input only; the draft comes back at the end.
	main = await _fresh_main()
	main._on_submit("HELP")
	await _tick()
	main._on_submit("STATUS")
	await _tick()
	main.input_line.text = "draft"
	main._on_input_gui_input(_key(KEY_UP))
	_check("history_up_latest", main.input_line.text == "STATUS", main.input_line.text)
	main._on_input_gui_input(_key(KEY_UP))
	_check("history_up_older", main.input_line.text == "HELP", main.input_line.text)
	main._on_input_gui_input(_key(KEY_DOWN))
	_check("history_down_latest", main.input_line.text == "STATUS", main.input_line.text)
	main._on_input_gui_input(_key(KEY_DOWN))
	_check("history_down_draft", main.input_line.text == "draft", main.input_line.text)

	# Typing counts as activity, not just submitting.
	main = await _fresh_main()
	main.scan_done = true
	main.inherit_timer.wait_time = 60.0
	main._on_submit("KILL 077")
	await _tick()
	_check("typing_window_started", not main.inherit_timer.is_stopped(), "")
	var activity_before: int = main.last_input_msec
	main.input_line.text = "L"
	main._on_input_text_changed("L")      # property assignment does not emit text_changed in GDScript
	_check("typing_cancels_inherit", main.inherit_timer.is_stopped(), "")
	await create_timer(0.1).timeout
	main.input_line.text = "LS"
	main._on_input_text_changed("LS")
	_check("typing_updates_idle_clock", main.last_input_msec > activity_before, str(main.last_input_msec) + ">" + str(activity_before))

	# The suggested SHUTDOWN appears only after KILL + reading the file.
	main = await _fresh_main()
	main.scan_done = true
	main.read_cat = true
	main._on_submit("KILL 077")
	await _tick()
	_check("kill_suggests_shutdown", main.completion_label.visible and main.completion_label.text.contains("SHUTDOWN --VERIFY"), main.completion_label.text)

	# OLD's "* " records stay out of the Up/Down command history.
	main = await _fresh_main()
	main._on_submit("SCAN /FULL")
	await create_timer(0.5).timeout
	_check("command_history_real_only", main.command_history.has("SCAN /FULL") and not main.command_history.has("* PUMP UNSERVICED. LOGGED."), str(main.command_history))

	# §8 dynamic threats: OLD's wait is a state readout.
	main = await _fresh_main()
	main.old_delay_override = -1.0
	_check("old_delay_base", is_equal_approx(main._old_delay_seconds(), 3.0), str(main._old_delay_seconds()))
	main.last_cmd = "LS /VOID"
	_check("old_delay_void", is_equal_approx(main._old_delay_seconds(), 5.0), str(main._old_delay_seconds()))
	main.last_cmd = ""
	main.temp = 2
	_check("old_delay_new_path", is_equal_approx(main._old_delay_seconds(), 8.0), str(main._old_delay_seconds()))
	main.temp = 0
	main.junk_count = 3
	_check("old_delay_junk", is_equal_approx(main._old_delay_seconds(), 8.0), str(main._old_delay_seconds()))
	main.junk_count = 0
	main.inherit_timer.start(1.0)
	_check("old_delay_ending_window", is_equal_approx(main._old_delay_seconds(), 2.0), str(main._old_delay_seconds()))
	main.inherit_timer.stop()
	main._old_say(["DELAY PROBE"])
	_check("old_delay_applied", is_equal_approx(main.old_timer.wait_time, 3.0), str(main.old_timer.wait_time))
	main.old_timer.stop()
	main.pending_old.clear()

	# Backspace is recorded, but OLD only admits it once.
	main = await _fresh_main()
	main.input_line.text = "ABC"
	for i in 5:
		main._on_input_gui_input(_key(KEY_BACKSPACE))
	await create_timer(0.08).timeout
	_check("backspace_count", main.backspace_count == 5, str(main.backspace_count))
	_check("hesitation_line", main.old_text.get_parsed_text().contains("YOU HESITATED."), "")
	for i in 5:
		main._on_input_gui_input(_key(KEY_BACKSPACE))
	await create_timer(0.08).timeout
	_check("hesitation_once", main.old_text.get_parsed_text().count("YOU HESITATED.") == 1, str(main.old_text.get_parsed_text().count("YOU HESITATED.")))

	# Lowercase is assimilated as it is typed, and NEW takes credit for it.
	main = await _fresh_main()
	main.input_line.text = "help"
	main.input_line.caret_column = 2
	main._on_input_text_changed("help")
	_check("input_assimilated", main.input_line.text == "HELP", main.input_line.text)
	_check("input_assimilation_caret", main.input_line.caret_column == 2, str(main.input_line.caret_column))
	_check("input_assimilation_reveal", main.new_text.get_parsed_text().contains("letters just got bigger"), "")

	# NEW asks for input access, then admits it was already reading.
	main = await _fresh_main()
	main._on_submit("LOGIN 077")
	await _tick()
	main._clear_popups()
	main.input_line.text = "HE"
	main._on_input_text_changed("HE")
	_check("auth_popup", is_instance_valid(main._popup) and main._popup.title_text().contains("Input Access"), main._popup.title_text() if is_instance_valid(main._popup) else "none")
	_check("auth_not_manual", not main._hints_seen.has("auth"), str(main._hint_order))
	var auth_popup: PanelContainer = main._popup
	auth_popup._on_confirm()
	await create_timer(0.45).timeout
	_check("auth_reveal", main.new_text.get_parsed_text().contains("already reading"), "")

	# The 2px scan band runs with the scan stream and retires with the timer.
	main = await _fresh_main()
	main._on_submit("SCAN /FULL")
	await _tick()
	_check("scan_band_visible", main.scan_band.visible and is_equal_approx(main.scan_band.size.y, 2.0), str(main.scan_band.size))
	_check("scan_band_tween", main.scan_band_tween != null and main.scan_band_tween.is_valid(), "")
	await create_timer(0.55).timeout
	_check("scan_band_stopped", main.scan_done and not main.scan_band.visible, str(main.scan_done))

	# KILL glitches once for half a second, then never again.
	main = await _fresh_main()
	main._on_submit("KILL 077")
	await _tick()
	_check("kill_glitch_visible", main.kill_glitch_played and main.glitch_text.visible and main.glitch_text.text.length() > 0, "")
	await create_timer(0.5).timeout
	_check("kill_glitch_stopped", not main.glitch_text.visible, "")
	main._on_submit("KILL 077")
	_check("kill_glitch_once", main.kill_glitch_played and not main.glitch_text.visible, "")

	_finish()


func _fresh_main() -> Node:
	main.queue_free()
	await create_timer(0.05).timeout
	var next_main: Node = load("res://Main.tscn").instantiate()
	root.add_child(next_main)
	await create_timer(0.25).timeout
	next_main.old_delay_override = 0.05
	next_main._finish_boot(true)          # smoke test skips the 15-line boot sequence
	next_main.old_timer.stop()
	next_main.pending_old.clear()
	next_main.old_timer.wait_time = 0.02
	next_main.replay_timer.wait_time = 0.01
	next_main.end_timer.wait_time = 0.01
	next_main.scan_timer.wait_time = 0.05
	next_main.scan_duration = 0.4
	next_main.guide_idle_seconds = 9999.0
	# Suppress the delayed boot popup in the short C-only scenes.
	next_main._hints_seen["boot"] = {"title": "", "body": ""}
	next_main._clear_popups()
	return next_main


func _tick() -> void:
	await create_timer(0.12).timeout


func _key(code: int, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	return event


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
	Engine.time_scale = 1.0
	f.store_line("SMOKE_DONE passed=%d failed=%d" % [passed, failed])
	f.flush()
	f.close()
	quit()
