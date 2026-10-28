extends Node3D
## A complete expedition: harvest a fading core's mana, cross the rift, defend.
const PlayerScript = preload("res://scripts/player.gd")
const CameraScript = preload("res://scripts/follow_camera.gd")
const VisualScript = preload("res://scripts/blob_visual.gd")
const DustScript = preload("res://scripts/dust.gd")
const StateScript = preload("res://scripts/run_state.gd")
const MapScript = preload("res://scripts/expedition_map.gd")
const ArenaScript = preload("res://scripts/defense_arena.gd")
const HudScript = preload("res://scripts/expedition_hud.gd")

var player: ParkourPlayer
var follow_camera: ParkourCamera
var visual: BlobVisual
var dust: ParkourDust
var run_state: Node
var exploration: Node3D
var arena: Node3D
var active_world: Node3D
var hud: CanvasLayer
var weapon: String = "bolt"
var paused_run: bool = false
var safe_index: int = 0
var visited_anchors: Dictionary = {0: true}
var harvesting: Dictionary = {}
var rift_fx: Node3D
var kill_count: int = 0
var attack_facing_time: float = 0.0
var attack_yaw: float = PI

func _ready() -> void:
	_register_controls()
	run_state = StateScript.new()
	run_state.name = "RunState"
	add_child(run_state)
	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	follow_camera = CameraScript.new()
	follow_camera.name = "FollowCamera"
	follow_camera.near = 0.1
	follow_camera.far = 400
	follow_camera.current = true
	follow_camera.fov = 60
	add_child(follow_camera)
	visual = VisualScript.new()
	visual.name = "MintBlob"
	add_child(visual)
	visual.setup(player)
	dust = DustScript.new()
	dust.name = "Dust"
	add_child(dust)
	dust.setup()
	player.dust_requested.connect(dust.emit_dust)
	player.landed.connect(_on_landed)
	player.fell.connect(respawn)
	hud = HudScript.new()
	hud.name = "ExpeditionHUD"
	add_child(hud)
	hud.setup()
	run_state.phase_changed.connect(_on_phase_changed)
	run_state.run_ended.connect(_on_run_ended)
	_build_exploration()
	_update_hud()
	hud.show_intro()

func _register_controls() -> void:
	var mapping: Dictionary = {
		"move_left": [KEY_A], "move_right": [KEY_D],
		"move_forward": [KEY_W], "move_back": [KEY_S],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE],
		"drop": [KEY_CTRL], "climb": [KEY_UP],
		"respawn": [KEY_R], "restart": [KEY_ENTER, KEY_KP_ENTER],
		"release_mouse": [KEY_ESCAPE], "enter_portal": [KEY_E],
		"switch_weapon": [KEY_Q], "mana_attack": [KEY_F], "blade_attack": [KEY_V],
	}
	for action: String in mapping:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in mapping[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(run_state):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("restart") and (paused_run or run_state.phase in ["won", "lost"]):
			restart()
			return
		if event.is_action_pressed("release_mouse"):
			if run_state.phase in ["explore", "defend"]:
				paused_run = not paused_run
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused_run else Input.MOUSE_MODE_CAPTURED
				if paused_run:
					hud.toast("Paused — click / Esc to resume, Enter for a new expedition", 4.0)
			return
		if paused_run or run_state.phase in ["transition", "won", "lost"]:
			return
		if event.is_action_pressed("move_left") or event.is_action_pressed("move_right") or event.is_action_pressed("move_forward") or event.is_action_pressed("move_back") or event.is_action_pressed("jump"):
			_begin_play()
		if event.is_action_pressed("jump"):
			player.queue_jump()
		if event.is_action_pressed("respawn"):
			respawn()
		if event.is_action_pressed("enter_portal"):
			begin_portal()
		if event.is_action_pressed("switch_weapon"):
			if run_state.sword_level > 0:
				weapon = "sword" if weapon == "bolt" else "bolt"
				hud.toast("Blade readied" if weapon == "sword" else "Mana bolt readied — 8 mana each")
			else:
				hud.toast("Find a sword on the expedition map first")
		if event.is_action_pressed("mana_attack"):
			attack("bolt")
		if event.is_action_pressed("blade_attack"):
			attack("sword")
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if run_state.phase in ["won", "lost", "transition"]:
				return
			if paused_run or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				paused_run = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_begin_play()
			else:
				attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not paused_run:
			attack("sword")
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused_run:
		follow_camera.orbit(event.relative)

func _begin_play() -> void:
	run_state.start()
	hud.dismiss_intro()

func read_controls() -> Dictionary:
	return {
		"left": Input.is_action_pressed("move_left"), "right": Input.is_action_pressed("move_right"),
		"forward": Input.is_action_pressed("move_forward"), "back": Input.is_action_pressed("move_back"),
		"sprint": Input.is_action_pressed("sprint"), "jump_held": Input.is_action_pressed("jump"),
		"drop": Input.is_action_pressed("drop"), "climb": Input.is_action_pressed("climb"),
	}

func _physics_process(dt: float) -> void:
	if paused_run or run_state.phase in ["won", "lost"]:
		return
	var controls: Dictionary = read_controls()
	if run_state.phase == "explore" and not run_state.started:
		if controls["left"] or controls["right"] or controls["forward"] or controls["back"] or controls["jump_held"]:
			_begin_play()
	var previous_phase: String = run_state.phase
	run_state.tick(dt)
	# A phase boundary creates a different world. Its actor starts on the next
	# fixed tick, so transition time is never also applied as a giant physics step.
	if run_state.phase != previous_phase or run_state.phase in ["transition", "won", "lost"]:
		return
	player.camera_yaw = follow_camera.yaw
	player.simulate(dt, controls)
	attack_facing_time = maxf(attack_facing_time - dt, 0.0)
	if run_state.phase == "defend" and attack_facing_time > 0.0 and player.state == "move":
		player.yaw_target = attack_yaw
	if run_state.phase == "explore":
		_update_exploration(dt)
	elif run_state.phase == "defend" and is_instance_valid(arena):
		arena.tick(dt, player.position, Callable(run_state, "spend_mana"))
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				attack("sword")
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				attack()

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if not paused_run and run_state.phase not in ["won", "lost"]:
		visual.tick(dt)
		dust.tick(dt, player)
		if run_state.phase == "explore":
			exploration.tick(dt)
		follow_camera.tick(dt, player)
		active_world.follow_sun(player.position)
	var charge: float = run_state.core_time / run_state.CORE_DURATION if run_state.phase == "explore" else run_state.mana / run_state.MANA_CAP
	visual.set_core_charge(charge)
	if run_state.phase == "transition":
		hud.show_transition(run_state.transition_time, run_state.mana)
		if is_instance_valid(rift_fx):
			rift_fx.rotate_y(dt * 0.8)
			var scale_factor: float = 1.0 + 0.07 * sin(run_state.transition_time * 7.0)
			rift_fx.scale = Vector3.ONE * scale_factor
	hud.tick(dt)
	_update_hud()

func _update_exploration(dt: float) -> void:
	harvesting = {}
	if player.grounded:
		for i in exploration.safe_points.size():
			var anchor: Dictionary = exploration.safe_points[i]
			var at: Vector3 = anchor["position"]
			if Vector2(at.x - player.position.x, at.z - player.position.z).length() < 2.2 and absf(at.y - player.position.y) < .6:
				safe_index = i
				if not visited_anchors.has(i):
					visited_anchors[i] = true
					hud.toast("Anchor attuned: " + str(anchor["name"]))
		var level: int = exploration.take_sword(player.position)
		if level > 0 and run_state.collect_sword(level):
			weapon = "sword"
			visual.set_weapon(run_state.sword_level)
			hud.toast("Garden blade found — free melee" if level == 1 else "Crown greatsword found — stronger melee")
	if run_state.started:
		var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		harvesting = exploration.harvest(player.position, player.grounded, speed, dt, run_state.MANA_CAP - run_state.mana)
		if not harvesting.is_empty() and float(harvesting.get("amount", 0.0)) > 0:
			run_state.add_mana(harvesting["amount"])
			run_state.record_pool(harvesting["pool_id"])
	exploration.set_portal_ready(run_state.mana >= run_state.MIN_PORTAL_MANA)

func begin_portal(force: bool = false) -> bool:
	if run_state.phase != "explore" or paused_run:
		return false
	if not force and not exploration.portal_in_range(player.position):
		hud.toast("Return to the violet portal at the central sanctuary")
		return false
	if not run_state.request_portal(force):
		hud.toast("The portal needs at least 60 mana. Stand still in a pool to charge.")
		return false
	return true

func attack(kind: String = "current") -> bool:
	if run_state.phase != "defend" or paused_run or not is_instance_valid(arena) or player.state != "move":
		return false
	var selected: String = weapon if kind == "current" else kind
	var direction := Vector3(-sin(follow_camera.yaw), 0, -cos(follow_camera.yaw))
	var success: bool = false
	if selected == "sword":
		success = arena.swing_sword(player.position, direction, run_state.sword_level)
	elif selected == "bolt":
		success = arena.fire_bolt(player.position + Vector3.UP * .8, direction, Callable(run_state, "spend_mana"))
	if success:
		attack_yaw = atan2(direction.x, direction.z)
		attack_facing_time = .42 if selected == "sword" else .34
		player.yaw_target = attack_yaw
		visual.play_attack(selected)
	return success

func _on_phase_changed(phase: String) -> void:
	if phase == "transition":
		player.velocity = Vector3.ZERO
		player.jump_buffer = 0
		_spawn_rift()
	elif phase == "defend":
		_enter_defense()
	elif phase in ["won", "lost"]:
		if is_instance_valid(arena):
			arena.stop_defense()

func _spawn_rift() -> void:
	if is_instance_valid(rift_fx):
		rift_fx.queue_free()
	rift_fx = Node3D.new()
	rift_fx.name = "CoreRift"
	rift_fx.position = player.position + Vector3.UP * .8
	active_world.add_child(rift_fx)
	for i in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.0 + .18 * i
		torus.outer_radius = 1.10 + .18 * i
		torus.rings = 36
		torus.ring_segments = 10
		ring.mesh = torus
		ring.rotation.x = PI / 2
		ring.rotation.y = PI / 2 * i
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("a28af5") if i == 0 else Color("5ee6df")
		ring.material_override = mat
		rift_fx.add_child(ring)

func _enter_defense() -> void:
	if is_instance_valid(rift_fx):
		rift_fx.queue_free()
		rift_fx = null
	if exploration.get_parent() == self:
		remove_child(exploration)
	arena = ArenaScript.new()
	arena.name = "TowerDefense"
	add_child(arena)
	arena.setup()
	arena.tower_destroyed.connect(func() -> void: run_state.lose("The tower was destroyed."))
	arena.all_waves_cleared.connect(func() -> void: run_state.win())
	arena.player_hit.connect(_on_player_hit)
	arena.enemy_killed.connect(_on_enemy_killed)
	active_world = arena
	_reset_player(arena.spawn_point)
	visual.set_weapon(run_state.sword_level)
	arena.start_defense()
	hud.hide_message()
	hud.toast("Your core and tower fire consume mana. Bolts cost 8; a found blade costs none.", 5.0)

func _on_player_hit(amount: float) -> void:
	if run_state.phase == "defend":
		run_state.drain_mana(amount)
		if run_state.phase == "defend":
			hud.toast("Core struck: −%d mana" % ceili(amount), .9)

func _on_enemy_killed(at: Vector3) -> void:
	kill_count += 1
	dust.emit_dust(at, 5, 1.8)

func _on_run_ended(won: bool, reason: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	paused_run = false
	hud.show_result(won, reason, run_state.mana, arena.wave if is_instance_valid(arena) else 0, run_state.elapsed)

func respawn() -> void:
	if paused_run or run_state.phase in ["transition", "won", "lost"]:
		return
	if run_state.phase == "explore":
		run_state.start()
		run_state.drain_mana(15)
		run_state.core_time = maxf(run_state.core_time - 8.0, 0.0)
		_reset_player(exploration.safe_points[safe_index]["position"])
		hud.toast("Core fracture: −15 mana, −8 seconds. Returned to your anchor.", 3.0)
		if run_state.core_time <= 0:
			run_state.request_portal(true)
	else:
		run_state.drain_mana(20)
		if run_state.phase == "defend":
			_reset_player(arena.spawn_point)
			hud.toast("Returned to the tower: −20 mana", 2.0)

func _reset_player(at: Vector3) -> void:
	attack_facing_time = 0.0
	attack_yaw = PI
	player.boxes = active_world.boxes
	player.respawn(at)
	player.yaw = PI
	player.yaw_target = PI
	follow_camera.boxes = active_world.boxes
	follow_camera.target = at + Vector3.UP
	follow_camera.yaw = 0
	follow_camera.pitch = .55 if run_state.phase == "defend" else .35
	follow_camera.base_distance = 7.2 if run_state.phase == "defend" else 5.2
	follow_camera.base_fov = 65.0 if run_state.phase == "defend" else 60.0
	follow_camera.distance = follow_camera.base_distance
	follow_camera.fov = follow_camera.base_fov
	follow_camera.dip = 0
	follow_camera.idle = 9
	follow_camera.tick(0, player)
	visual.tick(0)

func _build_exploration() -> void:
	exploration = MapScript.new()
	exploration.name = "ManaExpedition"
	add_child(exploration)
	exploration.setup()
	active_world = exploration
	_reset_player(exploration.spawn_point)

func restart() -> void:
	if is_instance_valid(arena):
		arena.stop_defense()
		if arena.get_parent() == self:
			remove_child(arena)
		arena.free()
		arena = null
	if is_instance_valid(exploration):
		if exploration.get_parent() == self:
			remove_child(exploration)
		exploration.free()
	if is_instance_valid(rift_fx):
		rift_fx.free()
	rift_fx = null
	weapon = "bolt"
	paused_run = false
	safe_index = 0
	visited_anchors = {0: true}
	harvesting = {}
	kill_count = 0
	run_state.reset()
	visual.set_weapon(0)
	_build_exploration()
	hud.show_intro()
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	var hint: String = ""
	var location: String = "The rift"
	if run_state.phase == "explore":
		location = exploration.safe_points[safe_index]["name"]
		hint = exploration.get_hint(player.position)
		if not harvesting.is_empty() and float(harvesting.get("amount", 0.0)) > 0:
			hint = "Channeling " + str(harvesting["pool_name"]) + " • Stand still • " + str(ceili(float(harvesting["remaining"]))) + " left in this pool"
	elif run_state.phase == "defend":
		location = "The Last Ember — tower grounds"
		hint = "Hold LMB to attack • RMB uses a found blade • Q switches weapon • Keep monsters away from the tower"
	if paused_run:
		hint = "Paused — click / Esc to resume • Enter starts a new expedition"
	var living: int = 0
	var radar_enemies: Array[Vector3] = []
	var radar_pools: Array[Vector3] = []
	var radar_swords: Array[Vector3] = []
	if run_state.phase == "explore":
		for pool: Dictionary in exploration.pools:
			if float(pool["remaining"]) > 0:
				radar_pools.append(pool["position"])
		for sword: Dictionary in exploration.swords:
			if not sword["taken"]:
				radar_swords.append(sword["position"])
	if is_instance_valid(arena):
		for enemy: Dictionary in arena.enemies:
			if enemy.get("alive", false):
				living += 1
				radar_enemies.append(enemy["position"])
	hud.update_run({
		"phase": run_state.phase, "started": run_state.started, "mana": run_state.mana,
		"mana_cap": run_state.MANA_CAP, "core_time": run_state.core_time, "elapsed": run_state.elapsed,
		"pools_found": run_state.pools_visited.size(), "pools_total": exploration.pools.size(),
		"sword_level": run_state.sword_level, "weapon": weapon,
		"tower_health": arena.tower_health if is_instance_valid(arena) else 200.0, "tower_max": 200.0,
		"wave": arena.wave if is_instance_valid(arena) else 0, "waves": 4, "enemies": living,
		"wave_wait": arena.wave_wait if is_instance_valid(arena) else 3.0,
		"speed": Vector2(player.velocity.x, player.velocity.z).length(), "location": location, "hint": hint,
		"radar_player": player.position, "radar_yaw": player.yaw,
		"radar_bounds": active_world.boxes, "radar_pools": radar_pools, "radar_swords": radar_swords,
		"radar_enemies": radar_enemies, "radar_portal": exploration.portal_position,
		"radar_radius": 28.0 if run_state.phase == "defend" else 90.0,
	})

func _on_landed(fall_speed: float) -> void:
	follow_camera.dip = minf(0.2, fall_speed * 0.012)

func _notification(what: int) -> void:
	if not is_instance_valid(run_state):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and run_state.started:
		paused_run = run_state.phase in ["explore", "transition", "defend"]
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and run_state.phase == "transition":
		# A backgrounded portal animation must not start an unattended siege.
		paused_run = false

func _exit_tree() -> void:
	# Exploration is intentionally detached while the defense world is active.
	if is_instance_valid(exploration) and exploration.get_parent() == null:
		exploration.free()
