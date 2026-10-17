extends SceneTree
## Non-audio smoke probe: verifies that the soundscape nodes exist, are playing,
## and that each WAV has a valid forward loop range. Run headless:
## godot --headless --path . --script res://tools/audio_probe.gd

var f: FileAccess


func _initialize() -> void:
	f = FileAccess.open("res://audio_probe.txt", FileAccess.WRITE)
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.4).timeout
	main._finish_boot(true)
	await create_timer(0.2).timeout
	var a = main._audio
	_line("audio_node=%s" % str(a != null))
	_line("boot new_layer_on=%s" % str(a.new_layer_on))
	_probe("room", a.room_player)
	_probe("old_idle", a.old_player)
	_probe("new_idle", a.new_player)
	_probe("tension", a.tension_player)
	a.on_accept_new()
	await create_timer(0.1).timeout
	_line("accept tension_on=%s playing=%s" % [str(a.tension_on), str(a.tension_player.playing)])
	a.on_scan_start()
	await create_timer(0.1).timeout
	_line("scan tension_on=%s" % str(a.tension_on))
	a.on_kill()
	await create_timer(0.1).timeout
	_line("kill new_layer_on=%s" % str(a.new_layer_on))
	_line("DONE")
	f.flush()
	f.close()
	quit()


func _probe(label: String, player: AudioStreamPlayer) -> void:
	var wav := player.stream as AudioStreamWAV
	_line("%s playing=%s vol=%.1f loop=%d begin=%d end=%d length=%.2f data=%d" % [
		label, str(player.playing), player.volume_db,
		wav.loop_mode, wav.loop_begin, wav.loop_end,
		wav.get_length(), wav.data.size(),
	])


func _line(text: String) -> void:
	f.store_line(text)
	f.flush()
