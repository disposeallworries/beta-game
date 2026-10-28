extends SceneTree
## Integration coverage for the preserved practice scene. This tests state transitions;
## checkpoint placement here does not claim an automated full-course playthrough.

const STEP: float = 1.0 / 120.0
var game: Node3D
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/practice.tscn")
	_check(scene != null, "Practice scene loads")
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
	_test_vault_animation()
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
	var box_count: int = game.course.boxes.size()
	var checkpoint_count: int = game.course.CHECKPOINTS.size()
	_check(box_count >= 45, "Expanded garden has at least 45 collision platforms and walls")
	_check(checkpoint_count >= 8, "Expanded garden has eight or more distinct checkpoint zones")
	_check(game.course.ROUTE_TARGETS.size() >= 40, "Ordered route spans at least 40 walkable targets")
	var footprint: AABB = game.course.boxes[0]
	for bounds: AABB in game.course.boxes:
		footprint = footprint.merge(bounds)
	_check(footprint.size.x >= 100 and footprint.size.z >= 105 and footprint.end.y >= 17.5, "Garden winds across a larger two-axis footprint with elevated terraces")
	var route_length: float = 0.0
	var previous_index: int = -1
	var route_indices: Dictionary = {}
	for index: int in game.course.ROUTE_TARGETS:
		_check(index >= 0 and index < box_count and not route_indices.has(index), "Route target %d is a unique valid platform" % index)
		route_indices[index] = true
		if previous_index >= 0:
			var from: Vector3 = game.course.boxes[previous_index].get_center()
			var to: Vector3 = game.course.boxes[index].get_center()
			route_length += Vector2(to.x - from.x, to.z - from.z).length()
		previous_index = index
	_check(route_length > 210.0, "Winding route offers over 210 meters of horizontal traversal")
	var bodies: int = 0
	var shapes: int = 0
	var flag_found: bool = false
	var markers: int = 0
	var finish: Vector3 = game.course.CHECKPOINTS[checkpoint_count - 1]["position"]
	for node: Node in game.course.get_children():
		if node is StaticBody3D:
			bodies += 1
			for child: Node in node.get_children():
				if child is CollisionShape3D and child.shape is BoxShape3D:
					shapes += 1
		if node.name.begins_with("Checkpoint"):
			markers += 1
		if node is MeshInstance3D and node.mesh is BoxMesh:
			if node.position.is_equal_approx(finish + Vector3(.7, 2.8, 0)):
				flag_found = node.mesh.size.is_equal_approx(Vector3(1.4, .8, .05))
	_check(bodies == box_count and shapes == box_count, "Native static collision bodies match every solver bound")
	_check(markers == checkpoint_count - 1, "Every non-start checkpoint has a visible marker")
	_check(flag_found, "Finish flag follows the final checkpoint's new garden location")
	_check(game.course.sun.shadow_enabled, "Directional light casts shadows")
	_check(game.course.has_node("GardenScenery"), "Garden scenery is separate from gameplay collision geometry")
	var checkpoint_names: Dictionary = {}
	for i in checkpoint_count:
		var at: Vector3 = game.course.CHECKPOINTS[i]["position"]
		var zone_name: String = game.course.CHECKPOINTS[i]["name"]
		_check(not zone_name.is_empty() and not checkpoint_names.has(zone_name), "Checkpoint %d has a unique named garden zone" % i)
		checkpoint_names[zone_name] = true
		var supported: bool = false
		for bounds: AABB in game.course.boxes:
			if absf(at.y - bounds.end.y) < 0.001 and at.x > bounds.position.x + .35 and at.x < bounds.end.x - .35 and at.z > bounds.position.z + .35 and at.z < bounds.end.z - .35:
				supported = true
		_check(supported and not game.player.blocked(at + Vector3.UP * .02), "Checkpoint %d is supported with clear standing room" % i)
		game.player.respawn(at)
		for frame in 8:
			game.player.simulate(STEP, {})
		_check(game.player.grounded and game.player.position.distance_to(at) < .03, "Checkpoint %d remains safely grounded under actual player physics" % i)
		if i > 0:
			var marker: MeshInstance3D = game.course.get_node("Checkpoint%d" % i)
			_check(marker.position.distance_to(at) < .1, "Checkpoint %d marker aligns with spawn surface" % i)
	game.respawn()


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
	game.player.velocity = Vector3(0, 0, -7.8)
	for i in 30:
		game.visual.tick(STEP)
	_check(game.visual._weights[2] > 0.9, "Sprint blends into original run animation")
	game.player.grounded = false
	game.player.velocity.y = 5.0
	for i in 30:
		game.visual.tick(STEP)
	_check(game.visual._weights[3] > 0.9, "Airborne movement blends into original jump animation")
	game.respawn()


func _test_vault_animation() -> void:
	var player: ParkourPlayer = game.player
	var original_boxes: Array[AABB] = player.boxes
	var fixture: Array[AABB] = [AABB(Vector3(-2, 0, -5), Vector3(4, 3, 4))]
	player.boxes = fixture
	player.respawn(Vector3(0, 1.9, -0.64))
	player.ledge_cooldown = 0.0
	player.velocity = Vector3(0, 0, -6.0)
	player.simulate(STEP, {"forward": true})
	_check(player.state == "hang" and absf(player.position.y - 1.9) < .01, "Ledge grab preserves the body's actual height without a pop")
	game.visual.tick(STEP)
	player.simulate(STEP, {"forward": true})
	_check(player.state == "climb" and player.quick_vault, "Real scene player begins a quick follow-through vault")
	var contact_pose_seen: bool = false
	var finite_poses: bool = true
	var vault_ticks: int = 0
	for i in 70:
		player.simulate(STEP, {"forward": true})
		vault_ticks += 1
		game.visual.tick(STEP)
		contact_pose_seen = contact_pose_seen or game.visual._pose_weight > 0.7
		for bone: Node3D in game.visual.bones:
			finite_poses = finite_poses and bone.transform.is_finite()
		if player.state == "move":
			break
	_check(contact_pose_seen and finite_poses, "Fast vault animates original limbs through valid contact poses")
	_check(player.state == "move" and player.grounded and player.velocity.z < -6.0, "Animated vault exits onto the platform with momentum at reduced movement speed")
	_check(absf(vault_ticks * STEP - .48) <= STEP, "Quick vault gives contact animation its full 0.48-second duration")
	_check(game.visual.position.is_equal_approx(player.position), "Character visual follows the fast vault without positional lag")
	player.respawn(Vector3(0, 2.55, -.64))
	player.ledge_cooldown = 0.0
	player.velocity = Vector3(0, 0, -6.0)
	player.simulate(STEP, {"forward": true})
	_check(player.state == "climb" and player.assisted_vault and absf(player.position.y - 2.55) < .01, "Half-height ledge assist begins smoothly from actual feet position")
	var assist_ticks: int = 0
	for i in 50:
		player.simulate(STEP, {"forward": true})
		game.visual.tick(STEP)
		assist_ticks += 1
		if player.state == "move":
			break
	_check(player.grounded and player.state == "move" and absf(player.position.y - 3.0) < .001, "Assisted vault exits standing on the platform")
	_check(absf(assist_ticks * STEP - .32) <= STEP and not player.assisted_vault, "Assisted vault finishes in 0.32 seconds and clears its contact state")
	player.boxes = original_boxes
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
	var skip_index: int = mini(3, game.course.CHECKPOINTS.size() - 2)
	var penultimate: int = game.course.CHECKPOINTS.size() - 2
	game.player.position = game.course.CHECKPOINTS[1]["position"]
	game.player.grounded = false
	game.update_checkpoints()
	_check(game.checkpoint_index == 0, "Flying over checkpoint does not activate it")
	game.player.grounded = true
	game.update_checkpoints()
	_check(game.checkpoint_index == 1, "Grounded player activates first route checkpoint")
	game.player.position = game.course.CHECKPOINTS[skip_index]["position"]
	game.update_checkpoints()
	_check(game.checkpoint_index == skip_index, "Later checkpoints can skip earlier checkpoints as in source")
	game.elapsed = 12.3
	game.player.position = Vector3(0, 30, 0)
	game.player.velocity = Vector3(4, -6, 2)
	_key(KEY_R)
	_check(game.player.position.is_equal_approx(game.course.CHECKPOINTS[skip_index]["position"]) and game.player.velocity.is_zero_approx(), "R restores active checkpoint and clears velocity")
	_check(game.checkpoint_index == skip_index and is_equal_approx(game.elapsed, 12.3), "Respawn preserves checkpoint and time")
	game.player.position = Vector3(0, -15, 4)
	game._physics_process(STEP)
	_check(game.player.position.is_equal_approx(game.course.CHECKPOINTS[skip_index]["position"]), "Falling below death plane automatically respawns")
	_check(game.elapsed > 12.3, "Automatic death respawn preserves running timer")
	game.player.position = game.course.CHECKPOINTS[penultimate]["position"]
	game.player.grounded = true
	game.update_checkpoints()
	_check(game.checkpoint_index == penultimate, "Final pre-finish checkpoint activates")


func _test_finish_and_restart() -> void:
	var finish_index: int = game.course.CHECKPOINTS.size() - 1
	game.elapsed = 65.2
	game.player.position = game.course.CHECKPOINTS[finish_index]["position"]
	game.player.grounded = true
	game.update_checkpoints()
	_check(game.finished and game.checkpoint_index == finish_index, "Grounded finish activation completes run")
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
	_check(game.player.position.is_equal_approx(game.course.CHECKPOINTS[0]["position"]) and not game.hud.message_panel.visible, "Restart returns to start and hides completion message")


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
	game.player.velocity = Vector3(12, 0, 0)
	for i in 120:
		camera.tick(0.01, game.player)
	_check(camera.fov > 77.9 and camera.fov <= 78.0, "High speed widens camera FOV to maximum")
	game.player.landed.emit(30.0)
	_check(is_equal_approx(camera.dip, 0.2), "Landing signal produces calmer capped camera dip")
	camera.tick(0.1, game.player)
	_check(camera.dip > 0 and camera.dip < 0.2, "Landing camera dip settles smoothly")
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
	game.player.velocity = Vector3(7.8, 0, 0)
	game.dust.footstep_time = 0.0
	game.dust.tick(0.01, game.player)
	_check(_live_particles() == 1, "Ground sprint emits footstep dust")
	game.respawn()


func _test_hud() -> void:
	var checkpoint_name: String = game.course.CHECKPOINTS[2]["name"]
	game.hud.update_stats(checkpoint_name, 72.3, 7.8)
	_check(game.hud.checkpoint_label.text == checkpoint_name and game.hud.timer_label.text == "1:12.3" and game.hud.speed_label.text == "7.8", "HUD displays current checkpoint, time and reduced speed")
	game.hud.show_intro()
	_check(game.hud.message_heading.text == "Click to play" and game.hud.message_detail.text == "Follow the gold arrows to Sunset garden", "Intro explains how to follow the expanded garden route")
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
