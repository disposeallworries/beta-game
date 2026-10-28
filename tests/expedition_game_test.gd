extends SceneTree
## Integration tests for the actual gather -> rift -> tower-defense main scene.
## Resource/encounter placement is a deliberate fixture, not a claim that these
## tests traverse the exploration map using movement controls alone.
const STEP: float = 1.0 / 120.0
var game: Node3D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "Main expedition scene loads")
	if scene == null:
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	_test_initial_run()
	_test_harvesting()
	_test_sword_pickups()
	_test_recovery_and_pause()
	_test_portal_flow()
	_test_forced_portal_and_loss()
	_test_combat_wiring()
	_test_run_results_and_restart()
	game.free()
	print("Expedition integration: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_initial_run() -> void:
	_check(game.run_state.phase == "explore" and not game.run_state.started, "Fresh run starts in exploration before the core timer begins")
	_check(is_zero_approx(game.run_state.mana) and is_equal_approx(game.run_state.core_time, 180.0), "Fresh run starts without mana and with a three-minute core")
	_check(game.active_world == game.exploration, "Exploration is the active world")
	_check(game.player.boxes == game.exploration.boxes and game.follow_camera.boxes == game.exploration.boxes, "Player and camera use exploration bounds")
	_check(game.exploration.pools.size() == 7 and game.exploration.swords.size() >= 2, "Exploration provides seven finite pools and discoverable swords")
	_check(game.exploration.boxes.size() >= 45, "Expedition map contains substantial parkour geometry")
	var footprint: AABB = game.exploration.boxes[0]
	for bounds: AABB in game.exploration.boxes:
		footprint = footprint.merge(bounds)
	_check(footprint.size.x >= 130 and footprint.size.z >= 140, "Resource expedition spans a larger, branching map")
	_check(game.hud != null and game.hud.message_kind == "intro", "New main has an explanatory intro HUD")
	var core_before: float = game.run_state.core_time
	_steps(20)
	_check(is_equal_approx(game.run_state.core_time, core_before), "Reading the intro does not consume core lifetime")
	_key(KEY_W)
	_steps(20)
	_check(game.run_state.started and game.run_state.core_time < core_before, "Movement input starts actual core countdown")
	_check(game.visual.model != null and game.visual.bones.size() == 5, "New main still loads the original animated blob")
	_check(game.hud.message_kind != "intro", "Starting through movement dismisses the intro")
	game.restart()

func _test_harvesting() -> void:
	game.restart()
	_key(KEY_W)
	var pool: Dictionary = game.exploration.pools[0]
	var at: Vector3 = pool["position"]
	var capacity: float = pool["capacity"]
	game.player.respawn(at)
	_steps(120)
	_check(game.run_state.mana > 20.0 and game.run_state.mana < 26.0, "Standing in a real pool charges mana at its intended rate")
	_check(float(pool["remaining"]) < capacity and game.run_state.pools_visited.has(int(pool["id"])), "Actual harvesting depletes the source and records its discovery")
	_near(game.run_state.mana + float(pool["remaining"]), capacity, "Harvesting conserves mana between the finite source and core")
	_steps(600)
	_near(float(pool["remaining"]), 0.0, "A pool eventually runs dry")
	var gathered: float = game.run_state.mana
	_steps(120)
	_near(game.run_state.mana, gathered, "A dry pool cannot be farmed indefinitely")
	game.restart()
	_key(KEY_W)
	pool = game.exploration.pools[0]
	at = pool["position"]
	game.player.respawn(at + Vector3.UP * 1.5)
	_steps(1)
	_check(is_zero_approx(game.run_state.mana), "Flying over a pool does not collect mana")
	game.player.respawn(at)
	_steps(1)
	var mana_before: float = game.run_state.mana
	game.player.velocity = Vector3(6, 0, 0)
	_steps(1)
	_near(game.run_state.mana, mana_before, "Moving through a pool is not the same as standing and channeling")
	game.restart()
	_key(KEY_W)
	pool = game.exploration.pools[0]
	at = pool["position"]
	game.run_state.add_mana(game.run_state.MANA_CAP - 2.0)
	game.player.respawn(at)
	_steps(120)
	_near(game.run_state.mana, game.run_state.MANA_CAP, "Harvesting respects the core's mana capacity")
	_near(float(pool["remaining"]), float(pool["capacity"]) - 2.0, "A full core does not waste unaccepted mana from the pool")
	game.restart()

func _test_sword_pickups() -> void:
	game.restart()
	var first: Dictionary = game.exploration.swords[0]
	game.player.respawn(first["position"])
	_steps(8)
	_check(game.run_state.sword_level >= 1 and first["taken"], "A grounded approach to a real sword unlocks it")
	var level_before: int = game.run_state.sword_level
	_steps(8)
	_check(game.run_state.sword_level == level_before, "The same sword pickup cannot be collected repeatedly")
	var second: Dictionary = game.exploration.swords[1]
	game.player.respawn(second["position"])
	_steps(8)
	_check(game.run_state.sword_level == 2 and second["taken"], "The harder sword pickup upgrades the carried weapon")
	game.restart()
	_check(game.run_state.sword_level == 0, "New runs start without a collected sword")
	for sword: Dictionary in game.exploration.swords:
		_check(not sword["taken"], "Restart restores each discoverable sword")

func _test_recovery_and_pause() -> void:
	game.restart()
	game.run_state.add_mana(100)
	_key(KEY_W)
	var mana_before: float = game.run_state.mana
	var core_before: float = game.run_state.core_time
	game.player.position = game.exploration.spawn_point + Vector3(5, 4, 0)
	_key(KEY_R)
	_near(game.run_state.mana, mana_before - 15.0, "Exploration recovery costs mana instead of providing a free reset")
	_near(game.run_state.core_time, core_before - 8.0, "Exploration recovery also spends core lifetime")
	_check(game.player.position.distance_to(game.exploration.spawn_point) < .1, "Exploration recovery returns safely to a known sanctuary")
	mana_before = game.run_state.mana
	game.player.position.y = -15.0
	_steps(1)
	_near(game.run_state.mana, mana_before - 15.0, "Falling off the expedition pays the same resource recovery penalty")
	_check(game.player.position.y > -1.0 and game.run_state.phase == "explore", "A recoverable fall does not leave the player below the map")
	_key(KEY_ESCAPE)
	_check(game.paused_run, "Escape provides a real pause for the timed run")
	core_before = game.run_state.core_time
	_steps(120)
	_near(game.run_state.core_time, core_before, "A paused run does not consume core lifetime")
	_key(KEY_ESCAPE)
	_check(not game.paused_run, "Escape resumes the expedition")
	_steps(15)
	_check(game.run_state.core_time < core_before, "The resumed core countdown continues")
	_key(KEY_ESCAPE)
	_key(KEY_ENTER)
	_check(game.run_state.phase == "explore" and not game.run_state.started and not game.paused_run, "Enter from pause can abandon an active run and start fresh")
	_check(is_zero_approx(game.run_state.mana) and is_equal_approx(game.run_state.core_time, 180.0), "Paused restart resets resources and core lifetime")
	game.restart()

func _test_portal_flow() -> void:
	game.restart()
	_key(KEY_W)
	game.player.respawn(game.exploration.portal_position)
	_steps(1)
	_key(KEY_E)
	_check(game.run_state.phase == "explore", "Portal interaction rejects an unprepared empty core")
	game.run_state.add_mana(120.0)
	game.run_state.collect_sword(1)
	game.player.respawn(game.exploration.spawn_point + Vector3(8, 0, 0))
	_key(KEY_E)
	_check(game.run_state.phase == "explore", "Early portal use requires actually reaching the portal")
	game.player.respawn(game.exploration.portal_position)
	_steps(1)
	_key(KEY_E)
	_check(game.run_state.phase == "transition", "E at an affordable portal begins the rift transition")
	var at: Vector3 = game.player.position
	Input.action_press("move_forward")
	_steps(15)
	Input.action_release("move_forward")
	_check(game.player.position.distance_to(at) < .01, "The character is held safely during portal transfer")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(game.paused_run, "Losing focus also pauses the portal countdown")
	var transition_before: float = game.run_state.transition_time
	_steps(120)
	_near(game.run_state.transition_time, transition_before, "A backgrounded rift cannot silently launch unattended combat")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not game.paused_run, "Refocusing safely resumes the paused portal animation")
	_wait_for_defense()
	_check(game.run_state.phase == "defend" and game.arena != null, "Transition reaches the monster-defense area")
	if game.run_state.phase != "defend" or game.arena == null:
		return
	_check(game.active_world == game.arena and game.arena.active, "Defense arena becomes the active game world")
	_check(game.player.boxes == game.arena.boxes and game.follow_camera.boxes == game.arena.boxes, "Player and camera switch to arena collision bounds")
	_check(game.player.position.distance_to(game.arena.spawn_point) < .1, "Transfer places the blob safely beside its tower")
	_check(game.run_state.sword_level == 1 and game.run_state.mana > 119.0, "Transfer carries collected mana and sword into defense")
	var mana_before: float = game.run_state.mana
	var core_before: float = game.run_state.core_time
	_steps(120)
	_check(game.run_state.mana < mana_before - .5, "Defending the tower consumes the actual shared reserve")
	_near(game.run_state.core_time, core_before, "The exploration core timer no longer drains in the arena")
	_check(game.arena.tower_health > 0 and game.arena.total_waves == 4, "A live tower and four-wave defense objective exist")
	game.restart()

func _test_forced_portal_and_loss() -> void:
	game.restart()
	game.run_state.add_mana(100)
	game.run_state.collect_sword(2)
	game.run_state.start()
	game.run_state.core_time = STEP * .5
	_steps(1)
	_check(game.run_state.phase == "transition", "Running out of core lifetime forces the portal instead of ending exploration silently")
	_wait_for_defense()
	_check(game.run_state.phase == "defend" and game.run_state.sword_level == 2, "Forced transfer preserves prepared mana and equipment")
	game.restart()
	game.run_state.start()
	game.run_state.core_time = STEP * .5
	_steps(1)
	_check(game.run_state.phase == "transition", "An empty run still shows the forced rift transition")
	_wait_for_defense()
	_check(game.run_state.phase == "lost" and not game.run_state.loss_reason.is_empty(), "Arriving at the rift without mana produces an explained defeat")
	_check(game.hud.message_kind in ["result", "lost", "defeat"], "Empty-core defeat is visible in the game HUD")
	_key(KEY_ENTER)
	_check(game.run_state.phase == "explore" and is_zero_approx(game.run_state.mana), "Enter after defeat starts a clean expedition")

func _test_combat_wiring() -> void:
	if not _defend_with(400.0, 0):
		return
	var mana_before: float = game.run_state.mana
	game.attack("sword")
	_near(game.run_state.mana, mana_before, "An uncollected sword cannot spend or grant combat resources")
	_check(game.run_state.sword_level == 0, "Attacking does not fabricate an undiscovered blade")
	game.arena.wave_wait = 1000.0
	game.arena.tower_cooldown = 1000.0
	var enemy: Dictionary = game.arena.spawn_enemy("crawler", game.player.position + Vector3(0, 0, -4))
	mana_before = game.run_state.mana
	game.follow_camera.yaw = 0.0
	game.attack("bolt")
	_check(game.run_state.mana <= mana_before - 8.0, "The player's mana bolt pays from the shared run reserve")
	_steps(60)
	_check(_enemy_damaged(enemy, 30.0), "A real fired bolt can damage or kill an arena monster")
	game.arena.player_hit.emit(3.0)
	var hit_before: float = game.run_state.mana
	game.arena.player_hit.emit(3.0)
	_near(game.run_state.mana, hit_before - 3.0, "Monster contact drains the same shared mana through the main-scene signal")
	if not _defend_with(250.0, 1):
		return
	game.arena.wave_wait = 1000.0
	game.arena.tower_cooldown = 1000.0
	enemy = game.arena.spawn_enemy("crawler", game.player.position + Vector3(0, 0, -1.7))
	game.follow_camera.yaw = 0.0
	mana_before = game.run_state.mana
	game.attack("sword")
	_near(game.run_state.mana, mana_before, "Collected sword attacks conserve mana")
	_check(_enemy_damaged(enemy, 30.0), "A collected blade actually strikes a nearby monster")
	game.run_state.drain_mana(game.run_state.mana)
	_check(game.run_state.phase == "lost", "Mana reaching zero during defense immediately loses the run")
	_check(not game.arena.active, "Combat stops after the shared reserve is exhausted")

func _test_run_results_and_restart() -> void:
	if not _defend_with(300, 1):
		return
	game.arena.damage_tower(500.0)
	_check(game.run_state.phase == "lost" and game.run_state.loss_reason.to_lower().contains("tower"), "Tower destruction is wired to a meaningful loss result")
	if not _defend_with(300, 1):
		return
	game.arena.all_waves_cleared.emit()
	_check(game.run_state.phase == "won", "Clearing the defense waves is wired to victory")
	_check(not game.arena.active and game.hud.message_kind in ["result", "won", "victory"], "Victory stops combat and displays the outcome")
	var elapsed_before: float = game.run_state.elapsed
	var mana_before: float = game.run_state.mana
	_steps(120)
	_near(game.run_state.elapsed, elapsed_before, "A completed run freezes elapsed time")
	_near(game.run_state.mana, mana_before, "A completed run no longer drains its reserve")
	_key(KEY_ENTER)
	_check(game.run_state.phase == "explore" and not game.run_state.started, "Enter after victory returns to an unstarted exploration run")
	_check(is_equal_approx(game.run_state.core_time, 180.0) and is_zero_approx(game.run_state.mana), "Restart restores core lifetime and empties run resources")
	_check(game.run_state.sword_level == 0 and game.run_state.pools_visited.is_empty(), "Restart clears run equipment and discovery history")
	_check(game.active_world == game.exploration and game.player.position.distance_to(game.exploration.spawn_point) < .1, "Restart reactivates the exploration map at its spawn")
	for pool: Dictionary in game.exploration.pools:
		_near(float(pool["remaining"]), float(pool["capacity"]), "Restart replenishes every finite pool")

func _defend_with(mana: float, sword: int) -> bool:
	game.restart()
	game.run_state.add_mana(mana)
	game.run_state.collect_sword(sword)
	game.begin_portal(true)
	_wait_for_defense()
	var ready: bool = game.run_state.phase == "defend" and game.arena != null
	_check(ready, "Fixture reaches defense through the actual three-second portal")
	return ready

func _wait_for_defense() -> void:
	for i in 380:
		if game.run_state.phase != "transition":
			break
		_steps(1)

func _enemy_damaged(enemy: Dictionary, initial_hp: float) -> bool:
	for key: String in ["hp", "health"]:
		if enemy.has(key):
			return float(enemy[key]) < initial_hp
	return enemy.has("alive") and not bool(enemy["alive"])

func _steps(count: int) -> void:
	for i in count:
		game._physics_process(STEP)
		game._process(STEP)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	game._input(event)

func _near(actual: float, expected: float, description: String, tolerance: float = .02) -> void:
	_check(absf(actual - expected) <= tolerance, description + " (%.4f vs %.4f)" % [actual, expected])

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)
