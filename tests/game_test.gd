extends SceneTree
## Integration coverage for the real game scene. This tests state transitions;
## checkpoint placement here does not claim an automated full-course playthrough.

const STEP: float = 1.0 / 120.0
var game: Node3D
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "Main scene loads")
	if scene == null:
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	_test_course()
	_test_animation()
	_test_input_and_timer()
	_test_checkpoints_and_respawn()
	_test_finish_and_restart()
	_test_camera()
	_test_dust()
	_test_hud()
	game.free()
	print("Game integration: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_course() -> void:
	_check(game.course.boxes.size() == 19, "All 19 original collision bounds exist")
	_check(game.course.CHECKPOINTS.size() == 6, "All six original checkpoints exist")
	var first: AABB = game.course.boxes[0]
	_check(first.position.is_equal_approx(Vector3(-9, -2, -9)) and first.size.is_equal_approx(Vector3(18, 2, 18)), "Start platform exact bounds")
	var last: AABB = game.course.boxes[18]
	_check(last.position.is_equal_approx(Vector3(43, 11.1, -62)) and last.size.is_equal_approx(Vector3(10, 1.5, 10)), "Gold finish exact bounds")
	var shaft: AABB = game.course.boxes[7]
	_check(shaft.position.is_equal_approx(Vector3(-5, 5.4, -53)) and shaft.end.is_equal_approx(Vector3(-2, 12.6, -45)), "Shaft wall exact bounds")
	var bodies: int = 0
	var shapes: int = 0
	var flag_found: bool = false
	var markers: int = 0
	for node: Node in game.course.get_children():
		if node is StaticBody3D:
			bodies += 1
			for child: Node in node.get_children():
				if child is CollisionShape3D and child.shape is BoxShape3D:
					shapes += 1
		if node.name.begins_with("Checkpoint"):
			markers += 1
		if node is MeshInstance3D and node.mesh is BoxMesh:
			if node.position.is_equal_approx(Vector3(48.7, 15.4, -57)):
				flag_found = node.mesh.size.is_equal_approx(Vector3(1.4, 0.8, 0.05))
	_check(bodies == 19 and shapes == 19, "Native static collision bodies match all original boxes")
	_check(markers == 5, "Five visible checkpoint markers exist")
	_check(flag_found, "Original finish flag geometry and position exist")
	_check(game.course.sun.shadow_enabled, "Directional light casts shadows")


func _test_animation() -> void:
	_check(game.visual.model != null and game.visual.bones.size() == 5, "Original GLB model and five contact-pose nodes loaded")
	for clip: String in ["idle", "walk", "run", "jump"]:
		_check(game.visual._clips.has(clip) and not game.visual._clips[clip]["channels"].is_empty(), "Original %s animation has keyframes" % clip)
	game.player.grounded = true
	game.player.velocity = Vector3.ZERO
	game.player.state = "move"
	var rig: Node3D = game.visual.bones[0]
	game.visual.tick(0.1)
	var before: Vector3 = rig.scale
	game.visual.tick(0.2)
	_check(not rig.scale.is_equal_approx(before), "Idle keyframes visibly breathe the rig")
	game.player.velocity = Vector3(0, 0, -13)
	for i in 30:
		game.visual.tick(STEP)
	_check(game.visual._weights[2] > 0.9, "Sprint blends into original run animation")
	game.player.grounded = false
	game.player.velocity.y = 5.0
	for i in 30:
		game.visual.tick(STEP)
	_check(game.visual._weights[3] > 0.9, "Airborne movement blends into original jump animation")
	game.respawn()


func _test_input_and_timer() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "sprint", "jump", "drop", "climb", "respawn", "restart", "release_mouse"]:
		_check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "%s has a keyboard binding" % action)
	_check(not game.started and not game.finished and is_zero_approx(game.elapsed), "Run starts with stopped zero timer")
	for i in 5:
		game._physics_process(STEP)
	_check(is_zero_approx(game.elapsed) and game.player.grounded, "Idle game stays grounded without starting timer")
	_key(KEY_W)
	_check(game.started, "Movement keyboard event starts timer")
	for i in 15:
		game._physics_process(STEP)
	_check(is_equal_approx(game.elapsed, 15.0 * STEP), "Started timer advances at physics timestep")
	_key(KEY_R)
	_check(is_equal_approx(game.elapsed, 15.0 * STEP), "R preserves elapsed run time")
	_key(KEY_SPACE)
	_check(game.player.jump_buffer > 0, "Space input queues buffered jump")
	game.player.jump_buffer = 0.0


func _test_checkpoints_and_respawn() -> void:
	game.player.position = game.course.CHECKPOINTS[1]["position"]
	game.player.grounded = false
	game.update_checkpoints()
	_check(game.checkpoint_index == 0, "Flying over checkpoint does not activate it")
	game.player.grounded = true
	game.update_checkpoints()
	_check(game.checkpoint_index == 1, "Grounded player activates ledge checkpoint")
	game.player.position = game.course.CHECKPOINTS[3]["position"]
	game.update_checkpoints()
	_check(game.checkpoint_index == 3, "Later checkpoints can skip earlier checkpoints as in source")
	game.elapsed = 12.3
	game.player.position = Vector3(0, 30, 0)
	game.player.velocity = Vector3(4, -6, 2)
	_key(KEY_R)
	_check(game.player.position.is_equal_approx(game.course.CHECKPOINTS[3]["position"]) and game.player.velocity.is_zero_approx(), "R restores active checkpoint and clears velocity")
	_check(game.checkpoint_index == 3 and is_equal_approx(game.elapsed, 12.3), "Respawn preserves checkpoint and time")
	game.player.position = Vector3(0, -15, 4)
	game._physics_process(STEP)
	_check(game.player.position.is_equal_approx(game.course.CHECKPOINTS[3]["position"]), "Falling below death plane automatically respawns")
	_check(game.elapsed > 12.3, "Automatic death respawn preserves running timer")
	game.player.position = game.course.CHECKPOINTS[4]["position"]
	game.player.grounded = true
	game.update_checkpoints()
	_check(game.checkpoint_index == 4, "Wall-slide pad checkpoint activates")


func _test_finish_and_restart() -> void:
	game.elapsed = 65.2
	game.player.position = game.course.CHECKPOINTS[5]["position"]
	game.player.grounded = true
	game.update_checkpoints()
	_check(game.finished and game.checkpoint_index == 5, "Grounded finish activation completes run")
	_check(game.hud.message_kind == "finish" and game.hud.message_heading.text.contains("1:05.2"), "Completion card shows frozen finish time")
	game.hud.dismiss_intro()
	_check(game.hud.message_panel.visible, "Mouse capture intro dismissal preserves completion card")
	var before: Vector3 = game.player.position
	game.player.velocity = Vector3(3, 0, 0)
	game._physics_process(STEP)
	_check(is_equal_approx(game.elapsed, 65.2), "Completed run timer stays stopped")
	_check(game.player.position.x > before.x, "Player movement remains enabled after finish")
	_key(KEY_ENTER)
	_check(game.checkpoint_index == 0 and not game.started and not game.finished and is_zero_approx(game.elapsed), "Enter restarts checkpoint and timer after finish")
	_check(game.player.position.is_equal_approx(Vector3(0, 0, 4)) and not game.hud.message_panel.visible, "Restart returns to start and hides completion message")


func _test_camera() -> void:
	var camera: Camera3D = game.follow_camera
	game.dragging = true
	var mouse: InputEventMouseMotion = InputEventMouseMotion.new()
	mouse.relative = Vector2(100, 10000)
	var old_yaw: float = camera.yaw
	game._input(mouse)
	_check(is_equal_approx(camera.yaw, old_yaw - 0.25) and is_equal_approx(camera.pitch, 1.2), "Mouse event orbits yaw and clamps lower camera view")
	mouse.relative = Vector2(0, -10000)
	game._input(mouse)
	_check(is_equal_approx(camera.pitch, -0.25) and is_zero_approx(camera.idle), "Mouse pitch upper view clamp and automatic-follow idle reset")
	_key(KEY_ESCAPE)
	_check(not game.dragging and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases captured/dragged mouse")
	var saved_boxes: Array[AABB] = camera.boxes.duplicate()
	var obstacle_boxes: Array[AABB] = [AABB(Vector3(-1, 0, 6), Vector3(2, 3, 1))]
	camera.boxes = obstacle_boxes
	game.player.respawn(Vector3(0, 0, 4))
	camera.target = Vector3(0, 1, 4)
	camera.yaw = 0.0
	camera.pitch = 0.0
	camera.distance = 5.2
	camera.tick(0.0, game.player)
	_check(is_equal_approx(camera.distance, 1.7), "Obstructing box pulls camera in immediately")
	var empty_boxes: Array[AABB] = []
	camera.boxes = empty_boxes
	camera.tick(0.1, game.player)
	_check(camera.distance > 1.7 and camera.distance < 5.2, "Camera returns outward smoothly after obstruction")
	game.player.velocity = Vector3(20, 0, 0)
	for i in 120:
		camera.tick(0.01, game.player)
	_check(camera.fov > 77.9 and camera.fov <= 78.0, "High speed widens camera FOV to maximum")
	game.player.landed.emit(30.0)
	_check(is_equal_approx(camera.dip, 0.45), "Landing signal produces capped camera dip")
	camera.tick(0.1, game.player)
	_check(camera.dip > 0 and camera.dip < 0.45, "Landing camera dip settles smoothly")
	_check(is_equal_approx(camera.ray_box(Vector3.ZERO, Vector3.BACK, AABB(Vector3(-1, -1, 2), Vector3(2, 2, 1))), 2.0), "Ray-box hit distance correct")
	_check(camera.ray_box(Vector3(5, 0, 0), Vector3.BACK, AABB(Vector3(-1, -1, 2), Vector3(2, 2, 1))) > 1000, "Parallel ray outside bounds does not obstruct camera")
	camera.boxes = saved_boxes
	game.respawn()


func _test_dust() -> void:
	game.player.grounded = false
	game.player.velocity = Vector3.ZERO
	game.dust.tick(1.0, game.player)
	game.dust.emit_dust(Vector3.ZERO, 5, 2.0)
	_check(_live_particles() == 5, "Dust emission activates requested number of particles")
	var first: Dictionary = game.dust.particles[0]
	var old_position: Vector3 = first["mesh"].position
	game.dust.tick(0.1, game.player)
	_check(first["mesh"].position.y > old_position.y and first["mesh"].scale.x > 0.5, "Dust particles drift and grow")
	_check(first["material"].albedo_color.a > 0 and first["material"].albedo_color.a < 0.6, "Dust particles fade")
	game.dust.emit_dust(Vector3.ZERO, 100, 2.0)
	_check(_live_particles() == 30 and game.dust.particles.size() == 30, "Dust pool caps at 30 reusable particles")
	game.dust.tick(0.6, game.player)
	_check(_live_particles() == 0, "Expired dust is hidden and reusable")
	game.player.grounded = true
	game.player.velocity = Vector3(13, 0, 0)
	game.dust.footstep_time = 0.0
	game.dust.tick(0.01, game.player)
	_check(_live_particles() == 1, "Ground sprint emits footstep dust")
	game.respawn()


func _test_hud() -> void:
	game.hud.update_stats("Shaft top", 72.3, 13.0)
	_check(game.hud.checkpoint_label.text == "Shaft top" and game.hud.timer_label.text == "1:12.3" and game.hud.speed_label.text == "13.0", "HUD displays current checkpoint, time and speed")
	game.hud.show_intro()
	_check(game.hud.message_heading.text == "Click to play" and game.hud.message_detail.text == "Reach the gold platform", "Intro retains original game instructions")
	game.hud.dismiss_intro()
	_check(not game.hud.message_panel.visible, "Intro dismissal hides prompt")
	_check(_all_mouse_ignored(game.hud.root), "HUD descendants allow mouse input through")
	_check(game.hud.format_time(0) == "0:00.0" and game.hud.format_time(65.2) == "1:05.2" and game.hud.format_time(600) == "10:00.0", "Timer formats minutes and tenths")


func _key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._input(event)


func _live_particles() -> int:
	var count: int = 0
	for particle: Dictionary in game.dust.particles:
		if float(particle["life"]) > 0 and particle["mesh"].visible:
			count += 1
	return count


func _all_mouse_ignored(node: Node) -> bool:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child: Node in node.get_children():
		if not _all_mouse_ignored(child):
			return false
	return true


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
