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

	_check("commands_loaded", main.commands.size() == 17, str(main.commands.size()))

	main._on_submit("HELP")
	await _tick()
	_check("exact_match", main.last_cmd == "HELP", main.last_cmd)
	_check("old_ellipsis", main.old_text.get_parsed_text().contains("..."), "")

	main._on_submit("PUMP")
	await _tick()
	_check("fuzzy_match", main.last_cmd == "PUMP 3", main.last_cmd)
	_check("old_correction", main.old_text.get_parsed_text().contains("PARTIAL MATCH"), "")

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
