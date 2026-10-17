extends SceneTree
## 冒烟测试：把时间参数调小，跑完一整局，验证阶段机、分叉值与三个结局。
## 运行：godot --headless --path . --script res://tools/smoke_test.gd
## 结果写进 res://smoke_result.txt（逐行 flush）。

var main: Node = null
var logf: FileAccess
var frames := 0


func _initialize() -> void:
	logf = FileAccess.open("res://smoke_result.txt", FileAccess.WRITE)
	_log("START")
	await _spawn()
	await _send("LOGIN 077", "login")
	await _send("HELP", "help")
	await _send("UNDO", "undo")
	await _send("LOG", "log")
	_log("STAGE_AFTER_LOG=" + str(main.stage))
	await _send("STATUS", "status")
	_log("UNLOCKED_ROOM=" + str(main.unlocked.has("ROOM")))
	await _send("PUMP 3", "pump")
	await _wait(2.0)
	_log("STAGE_AFTER_PUMP3=" + str(main.stage) + " choice=" + str(main.choice_made))
	await _send("SCAN", "scan")
	await _wait(2.0)
	_log("VOID_OPEN=" + str(main.unlocked.has("VOID")) + " scanning=" + str(main.scanning))
	await _send("LS /VOID", "ls")
	await _send("PS", "ps")
	await _send("CAT /VOID/TECH-077", "cat")
	await _send("CAT /VOID/TECH-077 --CONFIRM", "catf")
	_log("STAGE_AFTER_LOOP=" + str(main.stage))
	await _wait(2.0)
	await _send("FORMAT /VOID", "format")
	_log("AWAITING_CONFIRM=" + str(main.awaiting_confirm))
	await _send("Y", "yes")
	await _wait(2.0)
	_log("ENDING_A_MODE=" + str(main.ending_mode))
	_log("STATUS_LINE_OLD=" + main.old_stat.text)
	_log("STATUS_LINE_NEW=" + main.new_stat.text)

	await _respawn()
	main._set_stage("FINAL")
	main._play_ending("B_shutdown_verify")
	await _wait(2.0)
	_log("ENDING_B_MODE=" + str(main.ending_mode))

	await _respawn()
	main.stage = "FINAL"
	main.final_anchor_ms = Time.get_ticks_msec() - 5000
	await _wait(1.0)
	_log("ENDING_C_MODE=" + str(main.ending_mode))
	await _wait(2.0)
	_log("ENDING_C_NARRATION=" + main.narration.text)
	_log("SMOKE_DONE")
	logf.close()
	quit()


func _process(_delta: float) -> bool:
	frames += 1
	if frames % 60 == 0 and main != null and is_instance_valid(main):
		_log("TICK stage=" + str(main.stage) + " scanning=" + str(main.scanning) + " ending=" + str(main.ending_mode))
	return false


func _log(s: String) -> void:
	logf.store_line(s)
	logf.flush()


func _spawn() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.4).timeout
	main.latency_min = 0.05
	main.latency_max = 0.12
	main.scan_seconds = 0.8
	main.idle_seconds = 3.0
	main.idle_gap_seconds = 6.0
	main.final_timeout_ms = 4000
	main.auto_accept_seconds = 0.4
	main.pump_resolve_seconds = 0.6
	main.ending_speed = 80.0


func _respawn() -> void:
	main.queue_free()
	await process_frame
	await _spawn()


func _send(cmd: String, tag := "") -> void:
	main._on_submit(cmd)
	_log("SENT=" + cmd + " [" + tag + "]")
	await create_timer(0.45).timeout


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
