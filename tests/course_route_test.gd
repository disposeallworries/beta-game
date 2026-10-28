extends SceneTree
## Replays a successful, controls-only run through the complete sky-garden course.
## The fixture was found with controller rollouts, then replayed without teleporting
## or setting movement/state. Every checkpoint must be reached on the ground.
const Player = preload("res://scripts/player.gd")
const Course = preload("res://scripts/course.gd")
const DT := 1.0 / 120.0
var assertions: int = 0
var failures: int = 0
var ticks: int = 0
var reached: Array[int] = []
var stood_on: Array[int] = []
var transitions: Dictionary = {}
var quick_vaults: int = 0
var assisted_vaults: int = 0
var momentum_exits: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ROUTE: " + description)

func run() -> void:
	var course := Course.new()
	root.add_child(course)
	course.setup()
	var player := Player.new()
	root.add_child(player)
	player.boxes = course.boxes
	player.respawn(course.CHECKPOINTS[0]["position"])
	player.simulate(DT, {})
	var recording: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/route.json"))
	check(recording is Array and not recording.is_empty(), "recording loads")
	if recording is not Array or recording.is_empty():
		course.free()
		player.free()
		quit(1)
		return
	for segment: Dictionary in recording:
		var controls: Dictionary = segment["controls"]
		for tick in int(segment["ticks"]):
			if controls.has("yaw"):
				player.camera_yaw = controls["yaw"]
			if controls.get("jump", false):
				player.queue_jump()
			var before: String = player.state
			var was_quick: bool = player.quick_vault
			player.simulate(DT, controls)
			ticks += 1
			if before != player.state:
				var name: String = before + "->" + player.state
				transitions[name] = int(transitions.get(name, 0)) + 1
				if player.state == "climb" and player.quick_vault:
					if is_equal_approx(player.climb_duration, Player.ASSIST_VAULT_DURATION):
						assisted_vaults += 1
					else:
						quick_vaults += 1
				if before == "climb" and player.state == "move" and was_quick:
					var exit_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
					check(exit_speed >= Player.WALK_SPEED - 0.001 and exit_speed <= Player.VAULT_MAX_SPEED + 0.001, "vault exits preserve bounded forward momentum")
					momentum_exits += 1
			if player.position.y < -14:
				check(false, "recorded route must not fall off the course")
				course.free()
				player.free()
				quit(1)
				return
			if not player.grounded:
				continue
			for i in course.CHECKPOINTS.size():
				var at: Vector3 = course.CHECKPOINTS[i]["position"]
				if Vector2(player.position.x - at.x, player.position.z - at.z).length() < 2.2 and absf(player.position.y - at.y) < 1:
					if i not in reached:
						reached.append(i)
			for i in course.boxes.size():
				var box: AABB = course.boxes[i]
				if absf(player.position.y - box.end.y) < .001 and player.position.x > box.position.x - .35 and player.position.x < box.end.x + .35 and player.position.z > box.position.z - .35 and player.position.z < box.end.z + .35:
					if i not in stood_on:
						stood_on.append(i)
	var expected: Array[int] = []
	for index in course.CHECKPOINTS.size():
		expected.append(index)
	check(reached == expected, "all sky-garden checkpoints reached in course order while grounded")
	for index in course.ROUTE_TARGETS:
		check(index in stood_on, "stand on course platform %d" % index)
	check(int(transitions.get("move->wall", 0)) >= 2, "contact both walls in shaft")
	check(int(transitions.get("wall->move", 0)) >= 2, "jump away from shaft walls")
	check(int(transitions.get("move->hang", 0)) >= 1, "grab a tall ledge before quick vaulting")
	check(int(transitions.get("hang->climb", 0)) + int(transitions.get("move->climb", 0)) >= 3, "vault garden ledges and shaft top")
	check(quick_vaults >= 1, "activate quick vaults while traversing the course")
	check(assisted_vaults >= 1, "activate halfway-height auto-assist while traversing the course")
	check(momentum_exits >= 3, "complete quick and assisted vaults with momentum")
	var finish: Vector3 = course.CHECKPOINTS[-1]["position"]
	check(player.grounded and absf(player.position.y - finish.y) < .001, "finish grounded on gold platform")
	check(Vector2(player.position.x - finish.x, player.position.z - finish.z).length() < 2.2, "reach finish flag trigger")
	print("Full course: %d assertions, %d failures; %d controls-only ticks; checkpoints %s; %d quick / %d assisted vaults" % [assertions, failures, ticks, str(reached), quick_vaults, assisted_vaults])
	course.free()
	player.free()
	quit(0 if failures == 0 else 1)
