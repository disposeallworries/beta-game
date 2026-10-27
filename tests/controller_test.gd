extends SceneTree
## Deterministic native controller regression tests; run with:
## godot --headless --path . --script res://tests/controller_test.gd

const PlayerScript = preload("res://scripts/player.gd")
const DT: float = 1.0 / 120.0
const FLOOR := AABB(Vector3(-200.0, -2.0, -200.0), Vector3(400.0, 2.0, 400.0))
const WALL := AABB(Vector3(1.0, -2.0, -5.0), Vector3(3.0, 16.0, 10.0))
const LEDGE := AABB(Vector3(-2.0, 0.0, -5.0), Vector3(4.0, 3.0, 4.0))
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_ground_movement()
	_test_jump_timing()
	_test_collisions_and_events()
	_test_wall_actions()
	_test_ledge_actions()
	_test_respawn()
	print("Controller tests: %d passed, %d failed, %d total." % [checks - failures, failures, checks])
	quit(1 if failures else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _near(actual: float, expected: float, description: String, tolerance: float = 0.002) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (got %.5f, expected %.5f)" % [description, actual, expected])


func _player(at: Vector3 = Vector3.ZERO, geometry: Array[AABB] = [FLOOR]) -> ParkourPlayer:
	var p := PlayerScript.new()
	root.add_child(p)
	p.boxes.assign(geometry)
	p.respawn(at)
	return p


func _ticks(p: ParkourPlayer, count: int, controls: Dictionary = {}) -> void:
	for _i in range(count):
		p.simulate(DT, controls)


func _grounded_player() -> ParkourPlayer:
	var p := _player()
	p.simulate(DT, {})
	return p


func _wall_player() -> ParkourPlayer:
	var p := _player(Vector3(0.6, 6.0, 0.0), [WALL])
	p.velocity = Vector3(10.0, -2.0, 0.0)
	p.simulate(DT, {"right": true})
	return p


func _hanging_player(extra_geometry: Array[AABB] = []) -> ParkourPlayer:
	var geometry: Array[AABB] = [LEDGE]
	geometry.append_array(extra_geometry)
	var p := _player(Vector3(0.0, 1.9, -0.5), geometry)
	p.ledge_cooldown = 0.0
	p.simulate(DT, {"forward": true})
	return p


func _test_ground_movement() -> void:
	var p := _grounded_player()
	_ticks(p, 240)
	_check(p.grounded, "Resting player stays grounded")
	_near(p.position.y, 0.0, "Floor remains at exact feet height")
	_near(p.velocity.length(), 0.0, "No input leaves player stationary")
	_ticks(p, 120, {"forward": true})
	_near(p.velocity.z, -5.2, "Walk speed matches HTML")
	_near(p.velocity.x, 0.0, "Forward input has no lateral drift")
	_ticks(p, 20)
	_near(p.velocity.length(), 0.0, "Ground friction stops movement")
	_ticks(p, 120, {"forward": true, "right": true})
	_near(Vector2(p.velocity.x, p.velocity.z).length(), 5.2, "Diagonal movement is normalized")
	_near(p.velocity.x, -p.velocity.z, "Diagonal components match")
	p.respawn(Vector3.ZERO)
	p.camera_yaw = PI / 2.0
	_ticks(p, 120, {"forward": true})
	_near(p.velocity.x, -5.2, "Movement follows rotated camera yaw")
	_near(p.velocity.z, 0.0, "Rotated forward has no world Z drift")
	p.respawn(Vector3.ZERO)
	p.camera_yaw = 0.0
	_ticks(p, 120, {"forward": true, "sprint": true})
	_check(p.velocity.length() > 10.0 and p.velocity.length() < 11.0, "Sprint accelerates through its timed ramp")
	_ticks(p, 360, {"forward": true, "sprint": true})
	_near(p.velocity.length(), 13.0, "Full sprint reaches 13 m/s")
	_near(p.sprint_time, 3.0, "Sprint ramp caps at three seconds")
	p.queue_jump()
	p.simulate(DT, {"forward": true, "sprint": true, "jump_held": true})
	var launch_speed: float = Vector2(p.velocity.x, p.velocity.z).length()
	_ticks(p, 15, {"jump_held": true})
	_near(Vector2(p.velocity.x, p.velocity.z).length(), launch_speed, "Air movement preserves momentum without input")
	p.simulate(DT, {"forward": true, "jump_held": true})
	_near(Vector2(p.velocity.x, p.velocity.z).length(), launch_speed, "Releasing sprint in air preserves momentum with input")
	p.free()


func _jump_apex(hold_jump: bool) -> float:
	var p := _grounded_player()
	p.queue_jump()
	p.simulate(DT, {"jump_held": true})
	var apex: float = p.position.y
	for _i in range(150):
		p.simulate(DT, {"jump_held": hold_jump})
		apex = maxf(apex, p.position.y)
	p.free()
	return apex


func _test_jump_timing() -> void:
	var full_apex: float = _jump_apex(true)
	var short_apex: float = _jump_apex(false)
	_check(full_apex > 1.7 and full_apex < 1.85, "Held jump reaches original approximately 1.8 m apex")
	_check(short_apex < full_apex * 0.5 and short_apex > 0.45, "Early release produces a shorter jump")
	var p := _grounded_player()
	p.queue_jump()
	p.simulate(DT, {"jump_held": true})
	_near(p.velocity.y, 10.25, "Jump uses 10.5 impulse and 30 m/s² gravity")
	_check(not p.grounded, "Jump immediately clears grounded state")
	_ticks(p, 10, {"jump_held": true})
	p.queue_jump()
	var previous_vertical: float = p.velocity.y
	p.simulate(DT, {"jump_held": true})
	_near(p.velocity.y, previous_vertical - 0.25, "Jump press in air cannot double jump")
	p.free()
	# Walk off a real platform, then jump during the coyote interval.
	p = _player(Vector3.ZERO, [AABB(Vector3(-5, -2, -1), Vector3(10, 2, 2))])
	p.simulate(DT, {})
	for _i in range(120):
		p.simulate(DT, {"forward": true})
		if not p.grounded:
			break
	_check(not p.grounded and p.position.z < -1.0, "Fixture actually walks beyond the platform")
	_ticks(p, 5, {"forward": true})
	p.queue_jump()
	p.simulate(DT, {"forward": true, "jump_held": true})
	_check(p.velocity.y > 10.0, "Coyote time allows jump shortly after leaving a ledge")
	p.free()
	p = _player(Vector3(0.0, 0.20, 0.0))
	p.velocity.y = -3.0
	p.queue_jump()
	var bounced: bool = false
	for _i in range(16):
		p.simulate(DT, {"jump_held": true})
		if p.velocity.y > 9.0:
			bounced = true
	_check(bounced, "Jump buffered before landing launches on the next grounded tick")
	p.free()
	p = _player(Vector3(0.0, 1.0, 0.0))
	p.queue_jump()
	_ticks(p, 90, {"jump_held": true})
	_check(p.grounded and is_zero_approx(p.velocity.y), "Expired jump buffer does not trigger after a later landing")
	p.free()


func _test_collisions_and_events() -> void:
	var p := _player(Vector3.ZERO, [FLOOR, AABB(Vector3(-5, 2, -5), Vector3(10, 1, 10))])
	p.simulate(DT, {})
	p.queue_jump()
	var ceiling_hit: bool = false
	var ceiling_clear: bool = true
	for _i in range(45):
		p.simulate(DT, {"jump_held": true})
		ceiling_clear = ceiling_clear and p.position.y <= 0.851
		if p.position.y > 0.8 and is_zero_approx(p.velocity.y):
			ceiling_hit = true
	_check(ceiling_clear, "Ceiling prevents body penetration throughout the whole jump")
	_check(ceiling_hit, "Ceiling collision cancels upward velocity")
	p.free()
	p = _player(Vector3(0, 5, 0))
	var events := {"landed": 0, "dust": 0, "fell": 0, "impact": 0.0}
	p.landed.connect(func(speed: float) -> void:
		events["landed"] += 1
		events["impact"] = speed)
	p.dust_requested.connect(func(_at: Vector3, count: int, _speed: float) -> void: events["dust"] += count)
	_ticks(p, 150)
	_check(events["landed"] == 1 and events["impact"] > 10.0, "Hard landing emits one impact signal with fall speed")
	_check(events["dust"] > 0, "Hard landing emits dust particles")
	p.fell.connect(func() -> void: events["fell"] += 1)
	p.boxes.clear()
	p.position.y = -13.9
	p.velocity.y = -35.0
	p.simulate(DT, {})
	_check(events["fell"] == 1, "Falling below -14 m signals checkpoint respawn to game")
	p.free()
	# A tall wall must stop horizontal movement even with sustained input.
	p = _player(Vector3.ZERO, [FLOOR, WALL])
	_ticks(p, 240, {"right": true})
	_check(p.position.x <= 1.0 - ParkourPlayer.RADIUS, "Solid horizontal collision prevents wall penetration")
	_check(p.grounded, "Horizontal wall contact on floor does not enter wall slide")
	p.free()


func _test_wall_actions() -> void:
	var p := _wall_player()
	_check(p.state == "wall", "Airborne collision with a tall wall starts slide")
	_check(p.wall_normal == Vector3.LEFT, "Wall normal faces out of contacted surface")
	_ticks(p, 100, {"right": true})
	_check(p.state == "wall", "Sustained contact holds wall slide")
	_check(p.velocity.y >= -2.801, "Wall slide caps downward speed at 2.8 m/s")
	p.queue_jump()
	p.simulate(DT, {"jump_held": true})
	_check(p.state == "move" and p.velocity.x < -8.0 and p.velocity.y > 10.5, "Wall jump pushes away and upward")
	_check(p.wall_jump_time > 0.4 and p.control_lock > 0.1, "Wall jump sets pose timer and brief air control lock")
	_check(p.last_wall == 0, "Wall jump remembers contacted wall")
	p.position = Vector3(0.6, 6.0, 0.0)
	p.velocity = Vector3(10.0, -2.0, 0.0)
	p.simulate(DT, {"right": true})
	_check(p.state == "move", "Same wall cannot be grabbed again before landing or another wall")
	p.free()
	p = _wall_player()
	p.wall_speed = 40.0
	p.wall_tangent = Vector3(0.0, 0.0, 12.0)
	p.queue_jump()
	p.simulate(DT, {"left": true, "jump_held": true})
	_near(Vector2(p.velocity.x, p.velocity.z).length(), 20.0, "High-momentum wall jump clamps horizontal speed to 20 m/s")
	_near(p.velocity.y, 13.0, "High-momentum wall jump caps upward bonus at 2.5 m/s")
	p.free()
	p = _wall_player()
	p.simulate(DT, {"drop": true})
	_check(p.state == "move" and p.velocity.x < 0.0 and p.drop_time > 0.3, "Ctrl drops from wall with outward impulse and fall pose")
	p.free()
	p = _wall_player()
	p.simulate(DT, {"back": true})
	_check(p.state == "move" and p.drop_time > 0.3, "S also releases wall")
	p.free()
	p = _wall_player()
	_ticks(p, 20, {"left": true})
	_check(p.state == "move", "Holding away from wall releases after 0.15 seconds")
	p.free()
	p = _wall_player()
	p.boxes.clear()
	_ticks(p, 14)
	_check(p.state == "move", "Lost wall contact releases after grace interval")
	p.free()
	p = _wall_player()
	p.state = "move"
	p.grounded = true
	p.last_wall = 0
	p.boxes.assign([FLOOR])
	p.position = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.simulate(DT, {})
	_check(p.last_wall == -1, "Landing clears same-wall jump restriction")
	p.free()


func _test_ledge_actions() -> void:
	var p := _hanging_player()
	_check(p.state == "hang", "Approaching a reachable lip automatically grabs ledge")
	_near(p.position.y, 1.9, "Hanging feet sit 1.1 m below lip")
	_near(p.position.z, -0.65, "Hanging body stays one radius outside wall")
	_check(p.velocity == Vector3.ZERO, "Hanging stops all motion")
	_ticks(p, 80)
	_check(p.state == "hang", "No input keeps ledge hanging stable")
	p.queue_jump()
	p.simulate(DT, {})
	_check(p.state == "climb", "Space starts ledge climb")
	_ticks(p, 115)
	_check(p.state == "move" and p.grounded, "Climb completes into grounded movement")
	_near(p.position.y, 3.0, "Climb ends on top of platform")
	_check(p.position.z < -1.35 and not p.blocked(p.position + Vector3.UP * 0.001), "Climb crosses lip into clear standing space")
	p.free()
	p = _hanging_player()
	_ticks(p, 62, {"forward": true})
	_check(p.state == "climb", "Holding W auto climbs after half-second hang")
	p.free()
	p = _hanging_player()
	_ticks(p, 62, {"climb": true})
	_check(p.state == "climb", "Arrow Up also triggers automatic climb")
	p.free()
	p = _hanging_player()
	p.simulate(DT, {"drop": true})
	_check(p.state == "move" and p.ledge_cooldown > 0.3 and p.drop_time > 0.4, "Ctrl releases ledge and prevents immediate regrab")
	_check(p.position.z > -0.65, "Ledge drop moves body away from wall")
	p.free()
	p = _hanging_player()
	p.simulate(DT, {"back": true})
	_check(p.state == "move", "S also releases ledge")
	p.free()
	# An overhang occupies the intended landing volume but not the hanging volume.
	p = _hanging_player([AABB(Vector3(-1, 3.7, -2.0), Vector3(2, 1, 1.0))])
	p.queue_jump()
	p.simulate(DT, {})
	_check(p.state == "hang", "Climb rejects blocked standing clearance")
	p.free()
	p = _player(Vector3(0, 1.9, -0.5), [LEDGE])
	p.simulate(DT, {"forward": true})
	_check(p.state != "hang", "Respawn ledge cooldown prevents instant regrab")
	p.free()


func _test_respawn() -> void:
	var p := _wall_player()
	p.queue_jump()
	p.sprint_time = 3.0
	p.coyote_time = 0.12
	p.wall_jump_time = 0.4
	p.control_lock = 0.15
	p.drop_time = 0.5
	p.grounded = true
	p.jump_held = true
	p.last_wall = 0
	p.respawn(Vector3(12.0, 7.0, -5.0))
	_check(p.position == Vector3(12, 7, -5), "Respawn moves feet exactly to checkpoint")
	_check(p.velocity == Vector3.ZERO and p.state == "move", "Respawn resets movement state and velocity")
	_check(not p.grounded and not p.was_grounded and not p.jump_held, "Respawn clears stale ground and jump flags")
	_check(is_zero_approx(p.jump_buffer) and is_zero_approx(p.coyote_time), "Respawn clears buffered and coyote jumps")
	_check(is_zero_approx(p.sprint_time) and is_zero_approx(p.wall_jump_time) and is_zero_approx(p.drop_time), "Respawn clears sprint and pose timers")
	_check(p.last_wall == -1 and p.wall_box == -1 and p.wall_tangent == Vector3.ZERO, "Respawn clears wall contacts and momentum")
	_near(p.ledge_cooldown, 0.3, "Respawn establishes ledge cooldown")
	p.free()
