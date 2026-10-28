extends SceneTree
## Checks the actual distal mesh centers in world space, rather than only pose state.
const STEP := 1.0 / 120.0
const HAND_TIP := Vector3(0, -0.475, 0)
const FOOT_TIP := Vector3(0, -0.25, 0)
var player: ParkourPlayer
var visual: BlobVisual
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	player = ParkourPlayer.new()
	visual = BlobVisual.new()
	root.add_child(player)
	root.add_child(visual)
	visual.setup(player)
	await process_frame
	_check(visual.bones.size() == 5, "All original body and limb nodes load")
	# Seed the jump at its visual apex. Contact must remove its secondary root arc.
	visual._weights = PackedFloat32Array([0, 0, 0, 1])
	visual._times[3] = 0.4
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		for height: float in [0.71, 1.1, 1.24]:
			for gap: float in [0.35, 0.52]:
				_set_contact(direction, height, gap)
				visual.tick(STEP)
				_check_grip("Hang %.2f m / gap %.2f / %s" % [height, gap, direction])
				_check(visual.bones[0].position.is_zero_approx() and visual.bones[0].scale.is_equal_approx(Vector3.ONE), "Contact cancels animation root lift/squash")
				_check(is_equal_approx(player.yaw, player.yaw_target), "Contact faces the lip exactly")
	# Test hand contact during the early rise on both normal and fast pull-ups.
	for fast: bool in [false, true]:
		_set_contact(Vector3.FORWARD, 1.1, 0.35)
		visual.tick(STEP)
		var start: Vector3 = player.position
		for progress: float in [0.0, 0.05, 0.1, 0.2, 0.3, 0.35]:
			player.state = "climb"
			player.quick_vault = fast
			player.climb_progress = progress
			player.position.y = lerpf(start.y, player.ledge["top"], smoothstep(0.0, 0.7, progress))
			visual.tick(STEP)
			_check_grip("%s climb early phase %.2f" % ["Quick" if fast else "Normal", progress])
		# Complete release smoothly and return all limb lengths to their real size.
		for i in range(36, 101):
			player.climb_progress = float(i) / 100.0
			player.position.y = lerpf(start.y, player.ledge["top"], smoothstep(0.0, 0.7, player.climb_progress))
			visual.tick(STEP)
		_check(visual.bones[1].scale.is_equal_approx(Vector3.ONE) and visual.bones[2].scale.is_equal_approx(Vector3.ONE), "Completed climb releases both hands at normal limb size")
	_set_contact(Vector3.FORWARD, 1.1, 0.35)
	visual.tick(STEP)
	for index in [3, 4]:
		var foot: Vector3 = visual.bones[index].to_global(FOOT_TIP)
		var normal_distance: float = player.ledge_front - foot.dot(Vector3.FORWARD)
		_check(absf(normal_distance - 0.12) < 0.002, "Hanging foot's outer mesh surface braces against the wall")
	player.state = "move"
	player.grounded = false
	player.velocity = Vector3(0, 3, 0)
	for i in range(60):
		visual.tick(STEP)
		_check(visual.bones[0].position.is_zero_approx(), "Jump animation does not add height beyond the physics position")
	player.grounded = true
	player.velocity = Vector3(0, 0, -ParkourPlayer.SPRINT_MAX)
	for i in range(120):
		visual.tick(STEP)
	_check(visual._weights[2] > 0.99, "Calmer sprint still selects the original run clip")
	visual.free()
	player.free()
	print("Contact animation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _set_contact(direction: Vector3, height: float, gap: float) -> void:
	# The platform lip is at y=3 and projection=0; the body remains outside it.
	player.state = "hang"
	player.grounded = false
	player.assisted_vault = false
	player.position = -direction * gap + Vector3.UP * (3.0 - height)
	player.ledge = {"ax": direction.x, "az": direction.z, "top": 3.0}
	player.ledge_front = 0.0
	player.hang_time = 0.0
	player.climb_progress = 0.0
	player.velocity = Vector3.ZERO
	player.yaw_target = atan2(direction.x, direction.z)
	player.yaw = player.yaw_target + 0.5
	visual._previous_contact = ""
	visual._grip_anchors.clear()


func _check_grip(message: String) -> void:
	for index in range(2):
		var tip: Vector3 = visual.bones[index + 1].to_global(HAND_TIP)
		var expected: Vector3 = visual._grip_anchors[index]
		_check(tip.distance_to(expected) < 0.002, message + " actual hand tip remains on the lip (error %.5f)" % tip.distance_to(expected))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
