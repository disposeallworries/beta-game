extends SceneTree
## Whole-game proof: actual main-scene input replay, real harvesting/pickups,
## physically return to the portal, then fight four waves with the found blade.
## After ready(), this test never assigns player position/state/velocity, changes
## resources, edits enemies, disables costs, or invokes damage/kill helpers.
const STEP: float = 1.0 / 120.0
const ACTIONS: Dictionary = {
	"forward": "move_forward", "back": "move_back", "left": "move_left", "right": "move_right",
	"sprint": "sprint", "jump_held": "jump", "drop": "drop", "climb": "climb",
}
var game: Node3D
var checks: int = 0
var failures: int = 0
var exploration_ticks: int = 0
var combat_ticks: int = 0
var sword_attacks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	seed(20261028)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "Actual expedition main scene loads")
	if scene == null:
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	_check(game.run_state.phase == "explore" and is_zero_approx(game.run_state.mana), "Connected run starts at the true empty-core exploration state")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/expedition_routes.json"))
	var prepared: Dictionary = {}
	if data is Array:
		for branch: Dictionary in data:
			if bool(branch.get("portal", false)):
				prepared = branch
				break
	_check(not prepared.is_empty(), "A recorded exploration route returns to the portal")
	if prepared.is_empty():
		_finish()
		return
	# Match the route's initial real grounded tick without moving or teleporting.
	_apply_controls({})
	_step_main()
	_key(KEY_W)
	_check(game.run_state.started and game.hud.message_kind != "intro", "Real movement input starts the expedition and dismisses the intro")
	for segment: Dictionary in prepared["commands"]:
		var controls: Dictionary = segment["controls"]
		for tick in int(segment["ticks"]):
			if controls.has("yaw"):
				game.follow_camera.yaw = float(controls["yaw"])
			_apply_controls(controls)
			if controls.get("jump", false):
				_key(KEY_SPACE)
			_step_main()
			exploration_ticks += 1
			if game.run_state.phase != "explore":
				_check(false, "Recorded explorer stays alive and within its core lifetime until returning to the portal")
				print("Route stopped at ", game.player.position, " phase=", game.run_state.phase, " reason=", game.run_state.loss_reason)
				_finish()
				return
			if exploration_ticks % 600 == 0:
				await process_frame
	_apply_controls({})
	_check(exploration_ticks == int(prepared["ticks"]), "Every recorded exploration input tick reaches the actual main controller")
	_check(game.exploration.portal_in_range(game.player.position), "Blob physically returns to the central portal")
	_check(game.player.grounded, "Prepared explorer reaches the portal while standing on its real sanctuary")
	_check(game.run_state.core_time > 0 and game.run_state.elapsed < 180.0, "Collection and return finish before the three-minute core expires")
	_check(absf(game.run_state.mana - float(prepared["expected_mana"])) < .1, "Actual shared run state holds the 310 mana harvested through the map")
	_check(game.run_state.sword_level >= int(prepared["blade"]), "Actual sword pickup survives the full return route")
	for id: int in prepared["pools"]:
		_check(game.run_state.pools_visited.has(id), "Main-scene harvesting records visited pool %d" % id)
		_check(float(game.exploration.pools[id]["remaining"]) < .01, "Preparation actually depletes finite pool %d" % id)
	var mana_at_portal: float = game.run_state.mana
	var blade_at_portal: int = game.run_state.sword_level
	_check(game.begin_portal(false), "The real portal accepts a prepared explorer in physical range")
	_check(game.run_state.phase == "transition", "Portal begins the real rift transition")
	for tick in 380:
		if game.run_state.phase != "transition":
			break
		_step_main()
	_check(game.run_state.phase == "defend" and game.arena != null, "The same run transfers into the monster-defense arena")
	if game.run_state.phase != "defend" or game.arena == null:
		_finish()
		return
	_check(game.run_state.sword_level == blade_at_portal and absf(game.run_state.mana - mana_at_portal) < 1.0, "Portal carries the actually gathered mana and sword into defense")
	_check(game.player.boxes == game.arena.boxes and game.active_world == game.arena, "Player physically operates in the tower-defense area")
	var tower_start: float = game.arena.tower_health
	while game.run_state.phase == "defend" and combat_ticks < 18000:
		var target: Dictionary = game.arena.nearest_enemy(game.arena.tower_position, 100.0)
		var controls: Dictionary = {}
		if not target.is_empty():
			var aim: Vector3 = target["position"] - game.player.position
			aim.y = 0
			if aim.length() > .001:
				game.follow_camera.yaw = atan2(-aim.x, -aim.z)
				if aim.length() > 1.8:
					var desired: Vector3 = aim.normalized()
					var blocker: AABB = game.arena.boxes[1].grow(.6)
					var intersection: Variant = blocker.intersects_segment(game.player.position + Vector3.UP * .6, (target["position"] as Vector3) + Vector3.UP * .6)
					if intersection is Vector3:
						var radial := Vector3(game.player.position.x, 0, game.player.position.z)
						var tangent := Vector3(-radial.z, 0, radial.x).normalized()
						desired = (tangent + radial.normalized() * (.45 if radial.length() < 3.5 else 0.0)).normalized()
					controls = _relative_controls(desired, game.follow_camera.yaw)
		_apply_controls(controls)
		game._physics_process(STEP)
		if game.run_state.phase == "defend" and not target.is_empty() and bool(target.get("alive", false)):
			var aim: Vector3 = target["position"] - game.player.position
			aim.y = 0
			if aim.length() < 2.8 and aim.length() > .001:
				game.follow_camera.yaw = atan2(-aim.x, -aim.z)
				if game.attack("sword"):
					sword_attacks += 1
		game._process(STEP)
		combat_ticks += 1
		if combat_ticks % 600 == 0:
			await process_frame
	_apply_controls({})
	_check(game.run_state.phase == "won", "One connected legal-input run wins both exploration and all defense waves")
	_check(game.arena.wave == 4 and game.arena.kills == 28, "The connected run defeats all 28 real monsters across four waves")
	_check(sword_attacks > 10, "Collected sword is genuinely swung through the public combat API")
	_check(game.arena.tower_health > 0 and game.arena.tower_health <= tower_start, "The real tower survives without changing or disabling damage")
	_check(game.run_state.mana > 0 and game.run_state.mana < mana_at_portal, "Victory pays passive, contact and tower costs from the gathered reserve")
	_check(game.run_state.elapsed > exploration_ticks * STEP + 3.0 and game.run_state.elapsed < 300.0, "Connected run includes real exploration, portal and battle time")
	_check(not game.arena.active and game.hud.message_kind in ["result", "won", "victory"], "Actual victory stops the siege and shows a result")
	print("Connected run: %.2f s explore, %.2f s battle, %d kills, %d sword attacks, %.1f mana left, %.0f tower health, phase=%s" % [exploration_ticks * STEP, combat_ticks * STEP, game.arena.kills, sword_attacks, game.run_state.mana, game.arena.tower_health, game.run_state.phase])
	if game.run_state.phase == "lost":
		print("Loss reason: ", game.run_state.loss_reason, " position=", game.player.position)
	_finish()

func _relative_controls(direction: Vector3, yaw: float) -> Dictionary:
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var x: float = direction.dot(right)
	var z: float = direction.dot(forward)
	return {"forward": z > .38, "back": z < -.38, "right": x > .38, "left": x < -.38, "sprint": true}

func _apply_controls(controls: Dictionary) -> void:
	for key: String in ACTIONS:
		var action: String = ACTIONS[key]
		if controls.get(key, false):
			Input.action_press(action)
		else:
			Input.action_release(action)

func _step_main() -> void:
	game._physics_process(STEP)
	game._process(STEP)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._input(event)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FULL RUN: " + description)

func _finish() -> void:
	_apply_controls({})
	if is_instance_valid(game):
		game.free()
	print("Full expedition run: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
