extends Node3D
class_name ParkourPlayer
## Feet-origin, fixed-step port of the original browser controller.
## The deliberately axis-separated AABB solver preserves the course's jump tuning.

signal dust_requested(at: Vector3, count: int, speed: float)
signal landed(fall_speed: float)
signal fell

const RADIUS: float = 0.35
const HEIGHT: float = 1.15
const GRAVITY: float = 30.0
const JUMP_VELOCITY: float = 10.5

var boxes: Array[AABB] = []
var velocity: Vector3 = Vector3.ZERO
var camera_yaw: float = 0.0
var state: String = "move"
var grounded: bool = false
var yaw: float = PI
var yaw_target: float = PI
var sprint_time: float = 0.0
var wall_jump_time: float = 0.0
var drop_time: float = 0.0
var ledge: Dictionary = {"ax": 0.0, "az": 0.0, "top": 0.0}
var hang_time: float = 0.0
var climb_progress: float = 0.0
var ledge_front: float = 0.0
var wall_time: float = 0.0
var has_move_input: bool = false

var coyote_time: float = 0.0
var jump_buffer: float = 0.0
var ledge_cooldown: float = 0.0
var control_lock: float = 0.0
var last_wall: int = -1
var wall_box: int = -1
var wall_normal: Vector3 = Vector3.ZERO
var wall_tangent: Vector3 = Vector3.ZERO
var wall_speed: float = 0.0
var wall_no_contact: float = 0.0
var wall_away_time: float = 0.0
var hit: Dictionary = {}
var was_grounded: bool = false
var jump_held: bool = false
var climb_start: Vector3 = Vector3.ZERO
var climb_end: Vector3 = Vector3.ZERO


func queue_jump() -> void:
	jump_buffer = 0.12


func respawn(at: Vector3) -> void:
	position = at
	velocity = Vector3.ZERO
	state = "move"
	grounded = false
	was_grounded = false
	last_wall = -1
	wall_box = -1
	wall_normal = Vector3.ZERO
	wall_tangent = Vector3.ZERO
	wall_time = 0.0
	wall_no_contact = 0.0
	wall_away_time = 0.0
	wall_speed = 0.0
	ledge_cooldown = 0.3
	wall_jump_time = 0.0
	drop_time = 0.0
	control_lock = 0.0
	coyote_time = 0.0
	jump_buffer = 0.0
	jump_held = false
	sprint_time = 0.0
	hang_time = 0.0
	climb_progress = 0.0
	hit.clear()


func simulate(dt: float, controls: Dictionary) -> void:
	var ix: float = float(controls.get("right", false)) - float(controls.get("left", false))
	var iz: float = float(controls.get("forward", false)) - float(controls.get("back", false))
	var cy: float = cos(camera_yaw)
	var sy: float = sin(camera_yaw)
	var direction := Vector3(ix * cy - iz * sy, 0.0, -iz * cy - ix * sy)
	var input_length: float = direction.length()
	if input_length > 1.0:
		direction /= input_length
	has_move_input = input_length > 0.1
	jump_buffer -= dt
	ledge_cooldown -= dt
	control_lock -= dt
	wall_jump_time -= dt
	drop_time -= dt
	var drop: bool = controls.get("back", false) or controls.get("drop", false)
	match state:
		"move":
			_move_step(dt, controls, direction)
		"wall":
			_wall_step(dt, direction, drop)
		"hang":
			_hang_step(dt, controls, drop)
		"climb":
			_climb_step(dt)
	was_grounded = grounded or state != "move"
	if position.y < -14.0:
		fell.emit()


func _move_step(dt: float, controls: Dictionary, direction: Vector3) -> void:
	var sprint: bool = controls.get("sprint", false)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var initial_speed: float = horizontal.length()
	if sprint and has_move_input and grounded:
		sprint_time = minf(sprint_time + dt, 3.0)
	elif grounded:
		sprint_time = 0.0
	var speed: float = 9.5 + sprint_time / 3.0 * 3.5 if sprint else 5.2
	if grounded:
		coyote_time = 0.12
		last_wall = -1
	else:
		coyote_time -= dt
	var target: Vector3 = direction * speed
	var acceleration: float
	if grounded:
		acceleration = 9.0 if initial_speed > speed + 0.5 and has_move_input else (48.0 if has_move_input else 60.0)
	else:
		acceleration = 2.0 if control_lock > 0.0 else (18.0 if has_move_input else 2.5)
		if has_move_input:
			target = direction * maxf(speed, initial_speed)
		else:
			target = horizontal
	horizontal = horizontal.move_toward(target, acceleration * dt)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if jump_buffer > 0.0 and coyote_time > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer = 0.0
		coyote_time = 0.0
		grounded = false
		jump_held = true
		dust_requested.emit(position, 5, 1.5)
	if not controls.get("jump_held", false) and jump_held and velocity.y > 3.0:
		velocity.y *= 0.55
		jump_held = false
	if velocity.y <= 0.0:
		jump_held = false
	velocity.y = maxf(velocity.y - GRAVITY * dt, -35.0)
	if horizontal.length() > 0.5 and control_lock <= 0.0:
		yaw_target = atan2(velocity.x, velocity.z)
	var pre_vertical_speed: float = velocity.y
	var pre_speed: float = horizontal.length()
	_collide(dt)
	if grounded and not was_grounded and pre_vertical_speed < -4.0:
		dust_requested.emit(position, mini(14, int(-pre_vertical_speed)), 2.5)
		landed.emit(-pre_vertical_speed)
	if not grounded and velocity.y < 2.0 and ledge_cooldown <= 0.0:
		var approach := direction if has_move_input else Vector3(velocity.x, 0.0, velocity.z)
		if approach.length() > 0.5:
			if absf(approach.x) > absf(approach.z):
				approach = Vector3(signf(approach.x), 0.0, 0.0)
			else:
				approach = Vector3(0.0, 0.0, signf(approach.z))
			var probe: Vector3 = position + approach * (RADIUS + 0.3)
			for box in boxes:
				var height_to_top: float = box.end.y - position.y
				if height_to_top > 0.7 and height_to_top < 1.65 and probe.x > box.position.x and probe.x < box.end.x and probe.z > box.position.z and probe.z < box.end.z:
					_grab(box, approach)
					break
	if state == "move" and not grounded and not hit.is_empty():
		var index: int = hit["index"]
		var normal: Vector3 = hit["normal"]
		var impact_speed: float = hit["speed"]
		if index != last_wall and velocity.y < 3.0 and boxes[index].end.y - position.y > 1.8 and (impact_speed > 2.5 or -direction.dot(normal) > 0.3):
			state = "wall"
			wall_normal = normal
			wall_box = index
			wall_time = 0.0
			wall_no_contact = 0.0
			wall_away_time = 0.0
			wall_tangent = Vector3(velocity.x, 0.0, velocity.z)
			wall_speed = pre_speed
			velocity.x = 0.0
			velocity.z = 0.0
			yaw_target = atan2(-normal.x, -normal.z)
			dust_requested.emit(position - normal * RADIUS + Vector3.UP * 0.6, 3, 1.0)


func _wall_step(dt: float, direction: Vector3, drop: bool) -> void:
	wall_time += dt
	wall_tangent *= exp(-1.2 * dt)
	velocity.x = -wall_normal.x * 1.5 + wall_tangent.x
	velocity.z = -wall_normal.z * 1.5 + wall_tangent.z
	velocity.y = maxf(velocity.y - (5.0 if wall_time < 0.3 else 10.0) * dt, -1.0 if wall_time < 0.3 else -2.8)
	_collide(dt)
	if hit.is_empty() or hit["index"] != wall_box:
		wall_no_contact += dt
	else:
		wall_no_contact = 0.0
	if direction.dot(wall_normal) > 0.6:
		wall_away_time += dt
	else:
		wall_away_time = 0.0
	if jump_buffer > 0.0:
		var strength: float = minf(20.0, maxf(8.0, wall_speed * 0.95) + 2.0)
		var horizontal: Vector3 = wall_normal * strength + wall_tangent * 0.5 + direction * 2.0
		if horizontal.length() > 20.0:
			horizontal = horizontal.normalized() * 20.0
		velocity = horizontal
		velocity.y = JUMP_VELOCITY + minf((strength - 8.0) * 0.3, 2.5)
		jump_buffer = 0.0
		last_wall = wall_box
		state = "move"
		control_lock = 0.15
		wall_jump_time = 0.45
		yaw_target = atan2(wall_normal.x, wall_normal.z)
		coyote_time = 0.0
		grounded = false
		jump_held = false
		dust_requested.emit(position - wall_normal * RADIUS + Vector3.UP * 0.5, 6, 2.0)
	elif grounded or wall_no_contact > 0.1 or drop or wall_away_time > 0.15:
		state = "move"
		last_wall = wall_box
		velocity.x = wall_normal.x * 2.0 + wall_tangent.x
		velocity.z = wall_normal.z * 2.0 + wall_tangent.z
		if drop:
			drop_time = 0.4


func _hang_step(dt: float, controls: Dictionary, drop: bool) -> void:
	hang_time += dt
	velocity = Vector3.ZERO
	var approach := Vector3(ledge["ax"], 0.0, ledge["az"])
	if drop:
		state = "move"
		ledge_cooldown = 0.4
		position -= approach * 0.15
		drop_time = 0.5
	elif jump_buffer > 0.0 or (hang_time > 0.5 and (controls.get("forward", false) or controls.get("climb", false))):
		jump_buffer = 0.0
		var finish: Vector3 = position + approach * (2.0 * RADIUS + 0.34)
		finish.y = ledge["top"]
		if not blocked(finish + Vector3.UP * 0.02):
			state = "climb"
			climb_progress = 0.0
			climb_start = position
			climb_end = finish


func _climb_step(dt: float) -> void:
	climb_progress += dt / 0.95
	var progress: float = minf(climb_progress, 1.0)
	var forward_ease: float = smoothstep(0.42, 0.9, progress)
	position.y = climb_start.y + (float(ledge["top"]) - 0.25 - climb_start.y) * smoothstep(0.0, 0.4, progress) + 0.25 * smoothstep(0.55, 0.9, progress)
	position.x = lerpf(climb_start.x, climb_end.x, forward_ease)
	position.z = lerpf(climb_start.z, climb_end.z, forward_ease)
	if progress >= 1.0:
		state = "move"
		grounded = true
		ledge_cooldown = 0.3
		velocity = Vector3.ZERO


func _grab(box: AABB, approach: Vector3) -> void:
	state = "hang"
	ledge = {"ax": approach.x, "az": approach.z, "top": box.end.y}
	velocity = Vector3.ZERO
	hang_time = 0.0
	if approach.x > 0.0:
		position.x = box.position.x - RADIUS
	elif approach.x < 0.0:
		position.x = box.end.x + RADIUS
	if approach.z > 0.0:
		position.z = box.position.z - RADIUS
	elif approach.z < 0.0:
		position.z = box.end.z + RADIUS
	position.y = box.end.y - 1.1
	ledge_front = position.dot(approach) + RADIUS
	yaw = atan2(approach.x, approach.z)
	yaw_target = yaw


func blocked(at: Vector3) -> bool:
	for box in boxes:
		if _overlaps(at, box):
			return true
	return false


func _overlaps(at: Vector3, box: AABB) -> bool:
	return at.x + RADIUS > box.position.x and at.x - RADIUS < box.end.x and at.y + HEIGHT > box.position.y and at.y < box.end.y and at.z + RADIUS > box.position.z and at.z - RADIUS < box.end.z


func _collide(dt: float) -> void:
	hit = {}
	grounded = false
	position.x += velocity.x * dt
	for index in range(boxes.size()):
		var box: AABB = boxes[index]
		if _overlaps(position, box):
			var impact_speed: float = absf(velocity.x)
			var normal := Vector3.RIGHT
			if velocity.x > 0.0:
				position.x = box.position.x - RADIUS - 0.001
				normal = Vector3.LEFT
			else:
				position.x = box.end.x + RADIUS + 0.001
			hit = {"index": index, "normal": normal, "speed": impact_speed}
			velocity.x = 0.0
	position.z += velocity.z * dt
	for index in range(boxes.size()):
		var box: AABB = boxes[index]
		if _overlaps(position, box):
			var impact_speed: float = absf(velocity.z)
			var normal := Vector3.BACK
			if velocity.z > 0.0:
				position.z = box.position.z - RADIUS - 0.001
				normal = Vector3.FORWARD
			else:
				position.z = box.end.z + RADIUS + 0.001
			hit = {"index": index, "normal": normal, "speed": impact_speed}
			velocity.z = 0.0
	position.y += velocity.y * dt
	for box in boxes:
		if _overlaps(position, box):
			if velocity.y <= 0.0:
				position.y = box.end.y
				grounded = true
			else:
				position.y = box.position.y - HEIGHT
			velocity.y = 0.0
