extends SceneTree
## Functional combat checks against the real tower arena and projectile solver.
const ArenaScript = preload("res://scripts/defense_arena.gd")
const PlayerScript = preload("res://scripts/player.gd")
const STEP := 1.0 / 120.0
var arena: Node3D
var checks: int = 0
var failures: int = 0
var economy: Dictionary = {"mana": 600.0, "spent": 0.0}
var kills: Array[Vector3] = []
var tower_losses: int = 0
var victories: int = 0
var contact_drained: float = 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	arena = ArenaScript.new()
	root.add_child(arena)
	arena.setup()
	arena.enemy_killed.connect(func(at: Vector3) -> void: kills.append(at))
	arena.tower_destroyed.connect(func() -> void: tower_losses += 1)
	arena.all_waves_cleared.connect(func() -> void: victories += 1)
	arena.player_hit.connect(func(amount: float) -> void: contact_drained += amount)
	_check(arena.boxes.size() >= 10, "Arena has real floor, solid tower and boundary collisions")
	_check(arena.boxes[0].has_point(Vector3(20, -.5, 20)), "Full courtyard supports all four combat lanes")
	_check(arena.spawn_point.y == 0 and not _standing_blocked(arena.spawn_point), "Arena spawn has clear standing room")
	_test_start_and_weapons()
	_test_projectiles()
	_test_swords()
	_test_tower_and_contact()
	_test_waves()
	_test_reentrant_shutdown()
	_test_controls_only_battle()
	arena.free()
	await process_frame
	print("Defense arena: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DEFENSE: " + description)

func _standing_blocked(at: Vector3) -> bool:
	var body := AABB(at + Vector3(-.35, .01, -.35), Vector3(.7, 1.14, .7))
	for box: AABB in arena.boxes:
		if box.intersects(body): return true
	return false

func _spend(amount: float) -> bool:
	if float(economy["mana"]) < amount:
		return false
	economy["mana"] = float(economy["mana"]) - amount
	economy["spent"] = float(economy["spent"]) + amount
	return true

func _reset() -> void:
	arena.start_defense()
	economy["mana"] = 600.0
	economy["spent"] = 0.0
	kills.clear()
	contact_drained = 0
	# Tests of individual attacks run without ambient tower firing or auto waves.
	arena.tower_cooldown = 1000.0
	arena.wave_wait = 1000.0

func _ticks(count: int, player_at: Vector3 = Vector3(15, 0, 15)) -> void:
	for i in count:
		arena.tick(STEP, player_at, _spend)

func _test_start_and_weapons() -> void:
	_check(not arena.active, "Construction does not start the siege before portal entry")
	_check(not arena.fire_bolt(Vector3(0, .65, 7), Vector3.FORWARD, _spend), "Bolt cannot fire before defense begins")
	_check(not arena.swing_sword(Vector3(0, 0, 7), Vector3.FORWARD, 1), "Sword cannot swing outside active defense")
	_reset()
	_check(arena.active and arena.wave == 0 and arena.tower_health == 200, "Starting defense resets the tower and initial countdown")
	_check(arena.enemies.is_empty() and arena.projectiles.is_empty(), "New defense starts without stale enemies or projectiles")
	_check(not arena.swing_sword(Vector3(0, 0, 7), Vector3.FORWARD, 0), "A sword must actually be collected before swinging")
	economy["mana"] = 7.0
	_check(not arena.fire_bolt(Vector3(0, .65, 7), Vector3.FORWARD, _spend), "Bolt requires all eight mana")
	_check(economy["mana"] == 7.0 and arena.projectiles.is_empty(), "An unaffordable bolt neither drains mana nor creates a projectile")
	economy["mana"] = 20.0
	_check(not arena.fire_bolt(Vector3(0, .65, 7), Vector3.ZERO, _spend), "Zero aim direction is rejected before spending mana")
	_check(arena.fire_bolt(Vector3(0, .65, 7), Vector3.FORWARD, _spend), "Affordable bolt launches with a valid aim")
	_check(economy["mana"] == 12 and arena.projectiles.size() == 1, "Successful bolt costs exactly eight mana")
	_check(not arena.fire_bolt(Vector3(0, .65, 7), Vector3.FORWARD, _spend), "Held-fire input is bounded by the 0.38 second bolt cooldown")
	_ticks(46)
	_check(arena.fire_bolt(Vector3(0, .65, 7), Vector3.FORWARD, _spend), "Bolt cooldown recharges through actual arena ticks")
	arena.stop_defense()
	_check(not arena.active and arena.projectiles.is_empty(), "Stopping defense clears all in-flight projectiles")

func _test_projectiles() -> void:
	_reset()
	var enemy: Dictionary = arena.spawn_enemy("crawler", Vector3(0, 0, 12))
	_check(enemy["hp"] == 30 and enemy["kind"] == "crawler", "Crawler spawns with its intended health and type")
	_check(arena.fire_bolt(Vector3(0, .65, 7), Vector3.BACK, _spend), "Player bolt fires toward actual enemy")
	_ticks(25)
	_check(enemy["hp"] == 6 and enemy["alive"], "Traveling bolt hits once and applies 24 damage")
	_check(arena.projectiles.is_empty(), "Projectile is consumed by its first enemy hit")
	_ticks(22)
	arena.fire_bolt(Vector3(0, .65, 7), Vector3.BACK, _spend)
	_ticks(25)
	_check(not enemy["alive"] and not arena.enemies.has(enemy) and kills.size() == 1, "Second bolt kills, removes enemy and emits one death location")
	arena.damage_enemy(enemy, 100)
	_check(kills.size() == 1, "A dead enemy cannot award duplicate kills")
	_reset()
	var near: Dictionary = arena.spawn_enemy("crawler", Vector3(5, 0, 8))
	var far: Dictionary = arena.spawn_enemy("crawler", Vector3(5, 0, 12))
	arena.fire_bolt(Vector3(5, .65, 5), Vector3.BACK, _spend)
	# A long tick would cross both creatures; nearest swept impact still wins.
	arena.tick(.4, Vector3(20, 0, 20), _spend)
	_check(near["hp"] == 6 and far["hp"] == 30, "Swept projectile collision hits nearest target instead of tunneling or piercing")
	_reset()
	enemy = arena.spawn_enemy("brute", Vector3(0, 0, 12))
	arena.fire_bolt(Vector3(0, .8, 7), Vector3.BACK, _spend)
	_ticks(25)
	_check(enemy["hp"] == 48 and enemy["max_hp"] == 72, "Brute uses its larger collider and tougher 72 health")
	_reset()
	var soft_target: Dictionary = arena.spawn_enemy("crawler", Vector3(5.6, 0, 12))
	arena.fire_bolt(Vector3(5, .65, 5), Vector3.BACK, _spend)
	var direction: Vector3 = arena.projectiles[0]["direction"]
	_check(direction.x > .04 and direction.dot(Vector3.BACK) > cos(deg_to_rad(12.0)), "Soft aim assists an enemy inside the twelve-degree cone")
	_ticks(40)
	_check(soft_target["hp"] == 6, "Assisted projectile reaches the intended moving enemy")
	_reset()
	arena.spawn_enemy("crawler", Vector3(6.0, 0, 12))
	arena.spawn_enemy("crawler", Vector3(7.6, 0, 12))
	arena.fire_bolt(Vector3(5, .65, 5), Vector3.BACK, _spend)
	direction = arena.projectiles[0]["direction"]
	_check(direction.dot(Vector3.BACK) >= cos(deg_to_rad(12.0)), "Soft aim remains bounded to original aim rather than chaining across enemies")
	_reset()
	enemy = arena.spawn_enemy("crawler", Vector3(0, 0, -4))
	arena.fire_bolt(Vector3(0, .65, 4), Vector3.FORWARD, _spend)
	_ticks(70)
	_check(enemy["hp"] == 30, "The solid tower blocks player bolts fired through it")
	_check(arena.projectiles.is_empty(), "World impact consumes the bolt")
	_reset()
	arena.fire_bolt(Vector3(8, .65, 8), Vector3.BACK, _spend)
	_ticks(150)
	_check(arena.projectiles.is_empty(), "A missed bolt expires at its finite range")

func _test_swords() -> void:
	_reset()
	var front: Dictionary = arena.spawn_enemy("crawler", Vector3(5, 0, 7))
	var behind: Dictionary = arena.spawn_enemy("crawler", Vector3(5, 0, 3))
	var far: Dictionary = arena.spawn_enemy("crawler", Vector3(5, 0, 9))
	var high: Dictionary = arena.spawn_enemy("crawler", Vector3(5, 3, 7))
	var mana_before: float = economy["mana"]
	_check(arena.swing_sword(Vector3(5, 0, 5), Vector3.BACK, 1), "Collected blade swings in its facing direction")
	_check(not front["alive"] and behind["hp"] == 30, "Blade's forward arc hits the creature ahead, not behind")
	_check(far["hp"] == 30 and high["hp"] == 30, "Blade respects horizontal range and vertical reach")
	_check(economy["mana"] == mana_before, "Sword combat preserves collected mana")
	_check(not arena.swing_sword(Vector3(5, 0, 5), Vector3.BACK, 1), "Sword cannot bypass its cooldown")
	_ticks(67)
	_check(arena.swing_sword(Vector3(5, 0, 5), Vector3.FORWARD, 1), "Blade recharges after 0.55 seconds of simulation")
	_reset()
	var brute: Dictionary = arena.spawn_enemy("brute", Vector3(5, 0, 7))
	arena.swing_sword(Vector3(5, 0, 5), Vector3.BACK, 2)
	_check(brute["hp"] == 28, "Stronger found blade deals 44 damage")
	arena.stop_defense()
	_check(not arena.swing_sword(Vector3(5, 0, 5), Vector3.BACK, 2), "Outcome screens cannot attack frozen enemies")

func _test_tower_and_contact() -> void:
	_reset()
	var enemy: Dictionary = arena.spawn_enemy("crawler", Vector3(10, 0, 0))
	var old_distance: float = (enemy["position"] as Vector3).length()
	_ticks(120)
	_check((enemy["position"] as Vector3).length() < old_distance - 1.5, "Creature genuinely walks toward the tower")
	_reset()
	enemy = arena.spawn_enemy("crawler", Vector3(2.2, 0, 0))
	_ticks(61)
	_check(arena.tower_health == 192, "Creature at the tower performs a real eight-point attack")
	_ticks(110)
	_check(arena.tower_health == 184, "Tower attack obeys its repeat cooldown")
	_reset()
	arena.spawn_enemy("brute", Vector3(2.2, 0, 0))
	_ticks(61)
	_check(arena.tower_health == 184, "Brute's siege hit is stronger than a crawler's")
	_reset()
	enemy = arena.spawn_enemy("crawler", Vector3(5, 0, 5))
	_ticks(1, Vector3(5, 0, 5))
	_check(contact_drained == 3, "A creature contacting the player emits three mana drain")
	_ticks(30, Vector3(5, 0, 5))
	_check(contact_drained == 3, "Contact damage has a grace interval instead of draining every tick")
	_reset()
	arena.spawn_enemy("crawler", Vector3(10, 0, 0))
	arena.tower_cooldown = 0
	_ticks(1)
	_check(economy["spent"] == 2 and arena.projectiles.size() == 1, "Tower auto-fire spends shared mana and creates a visible bolt")
	_ticks(70)
	_check(arena.enemies[0]["hp"] == 18, "Tower bolt travels and damages its actual target")
	_reset()
	arena.spawn_enemy("crawler", Vector3(10, 0, 0))
	arena.tower_cooldown = 0
	economy["mana"] = 1
	_ticks(1)
	_check(economy["mana"] == 1 and arena.projectiles.is_empty(), "Tower does not fire free shots when mana is insufficient")
	_reset()
	var before: int = tower_losses
	arena.damage_tower(999)
	_check(arena.tower_health == 0 and not arena.active and tower_losses == before + 1, "Destroying the tower emits one defeat event and stops the siege")
	arena.damage_tower(20)
	_check(tower_losses == before + 1, "Tower defeat event is not repeated")

func _test_waves() -> void:
	arena.start_defense()
	economy["mana"] = 600
	arena.tower_cooldown = 1000
	arena.tick(2.9, Vector3(15, 0, 15), _spend)
	_check(arena.wave == 0 and arena.enemies.is_empty(), "Portal arrival gives a three-second preparation countdown")
	arena.tick(.11, Vector3(15, 0, 15), _spend)
	_check(arena.wave == 1 and arena.enemies.size() == 4, "First wave spawns four monsters from the gates")
	for wave_index in range(4):
		_check(arena.wave == wave_index + 1 and arena.enemies.size() == [4, 6, 8, 10][wave_index], "Wave %d has its intended increasing population" % (wave_index + 1))
		if wave_index > 0:
			_check(arena.enemies.any(func(enemy: Dictionary) -> bool: return enemy["kind"] == "brute"), "Later wave includes tougher brutes")
		for enemy: Dictionary in arena.enemies.duplicate():
			arena.damage_enemy(enemy, 1000)
		if wave_index < 3:
			arena.tick(1.0, Vector3(15, 0, 15), _spend)
			_check(arena.enemies.is_empty() and arena.wave == wave_index + 1, "Cleared wave offers a breather before the next assault")
			arena.tick(5.1, Vector3(15, 0, 15), _spend)
	var before: int = victories
	arena.tick(STEP, Vector3(15, 0, 15), _spend)
	_check(victories == before + 1 and not arena.active and arena.wave == 4, "Clearing all four waves emits one victory and ends combat")
	arena.tick(10, Vector3(15, 0, 15), _spend)
	_check(victories == before + 1, "Victory is not emitted repeatedly on later ticks")
	arena.start_defense()
	_check(arena.wave == 0 and arena.enemies.is_empty() and arena.tower_health == 200 and arena.kills == 0, "A fresh defense fully resets the previous wave outcome")

func _test_reentrant_shutdown() -> void:
	_reset()
	arena.spawn_enemy("crawler", Vector3(10, 0, 0))
	var close_run: Callable = func(_cost: float) -> bool:
		arena.stop_defense()
		return true
	_check(not arena.fire_bolt(Vector3(8, .65, 0), Vector3.RIGHT, close_run), "Mana callback ending the run prevents creation of a late player projectile")
	_check(arena.projectiles.is_empty(), "No projectile survives synchronous mana-loss shutdown")
	_reset()
	arena.spawn_enemy("crawler", Vector3(10, 0, 0))
	arena.tower_cooldown = 0
	arena.tick(STEP, Vector3(15, 0, 15), close_run)
	_check(not arena.active and arena.projectiles.is_empty(), "Tower callback respects the same immediate mana-depletion outcome")


func _test_controls_only_battle() -> void:
	# This is a legal-input combat run, unlike the preceding isolated wave tests:
	# after spawning, the actual player only moves through simulate() and attacks
	# through swing_sword(). No enemy damage helper or player teleport is used.
	arena.start_defense()
	economy["mana"] = 300.0
	economy["spent"] = 0.0
	var player := PlayerScript.new()
	root.add_child(player)
	player.boxes = arena.boxes
	player.respawn(arena.spawn_point)
	var won_before: int = victories
	var losses_before: int = tower_losses
	var elapsed: float = 0.0
	var passive_drain: float = 0.6
	var on_contact: Callable = func(amount: float) -> void:
		economy["mana"] = float(economy["mana"]) - amount
	arena.player_hit.connect(on_contact)
	while elapsed < 150 and arena.active and float(economy["mana"]) > 0:
		economy["mana"] = float(economy["mana"]) - passive_drain * STEP
		var target: Dictionary = arena.nearest_enemy(Vector3.ZERO, 100)
		if not target.is_empty():
			var destination: Vector3 = target["position"]
			var tower_blocker: AABB = arena.boxes[1].grow(.6)
			var blocked: Variant = tower_blocker.intersects_segment(player.position + Vector3.UP * .6, destination + Vector3.UP * .6)
			if blocked is Vector3:
				var orbit := Vector3(-player.position.z, 0, player.position.x).normalized() * 3.5
				destination = player.position + orbit
			var direction: Vector3 = destination - player.position
			direction.y = 0
			player.camera_yaw = atan2(-direction.x, -direction.z)
			player.simulate(STEP, {"forward": direction.length() > 1.8, "sprint": true})
			var aim: Vector3 = target["position"] - player.position
			aim.y = 0
			if aim.length() < 2.8:
				arena.swing_sword(player.position, aim, 1)
		else:
			player.simulate(STEP, {})
		arena.tick(STEP, player.position, _spend)
		elapsed += STEP
	arena.player_hit.disconnect(on_contact)
	_check(victories == won_before + 1 and tower_losses == losses_before, "Controls-only player and found blade can genuinely win all four waves")
	_check(arena.kills == 28 and arena.wave == 4, "Successful battle defeats all 28 actual wave monsters")
	_check(float(economy["mana"]) > 0 and float(economy["mana"]) < 300, "Victory is possible from 300 mana with real passive, contact and tower costs")
	_check(arena.tower_health > 0 and elapsed < 150, "Combat run protects a living tower without endless kiting")
	player.free()
