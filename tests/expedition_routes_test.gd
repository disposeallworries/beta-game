extends SceneTree
## Controls-only resource exploration. Each recording starts independently at the
## real sanctuary spawn. A recording never teleports, respawns, or edits velocity
## or controller state. The prepared-return case is one continuous collection run.
const Player = preload("res://scripts/player.gd")
const Map = preload("res://scripts/expedition_map.gd")
const DT: float = 1.0 / 120.0
const CORE_LIFETIME: float = 180.0
const MANA_CAPACITY: float = 600.0
var assertions: int = 0
var failures: int = 0
var all_harvested: Array[int] = []
var all_stood_on: Array[int] = []
var all_blades: Array[int] = []
var wall_jumps: int = 0
var quick_vaults: int = 0
var assisted_vaults: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("EXPEDITION ROUTE: " + description)

func run() -> void:
	var world := Map.new()
	root.add_child(world)
	world.setup()
	var player := Player.new()
	root.add_child(player)
	player.boxes = world.boxes
	var recording: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/expedition_routes.json"))
	check(recording is Array and recording.size() == 4, "four independent branch recordings load")
	if recording is not Array or recording.size() != 4:
		world.free()
		player.free()
		quit(1)
		return
	for branch: Dictionary in recording:
		world.reset_resources()
		player.respawn(world.spawn_point)
		player.simulate(DT, {})
		var ticks: int = 0
		var mana: float = 0.0
		var blade: int = 0
		var collected: Array[int] = []
		for segment: Dictionary in branch["commands"]:
			var controls: Dictionary = segment["controls"]
			for tick in int(segment["ticks"]):
				if controls.has("yaw"):
					player.camera_yaw = controls["yaw"]
				if controls.get("jump", false):
					player.queue_jump()
				var before: String = player.state
				player.simulate(DT, controls)
				ticks += 1
				if before == "wall" and player.state == "move" and player.velocity.y > 0:
					wall_jumps += 1
				if before != "climb" and player.state == "climb" and player.quick_vault:
					if player.assisted_vault:
						assisted_vaults += 1
					else:
						quick_vaults += 1
				if player.position.y < -14.0:
					check(false, "%s must traverse without falling or respawning" % branch["name"])
					world.free()
					player.free()
					quit(1)
					return
				if not player.grounded:
					continue
				var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
				var result: Dictionary = world.harvest(player.position, player.grounded, speed, DT, MANA_CAPACITY - mana)
				if not result.is_empty() and float(result["amount"]) > 0:
					mana += float(result["amount"])
					var id: int = result["pool_id"]
					if id not in collected:
						collected.append(id)
					if id not in all_harvested:
						all_harvested.append(id)
				var pickup: int = world.take_sword(player.position)
				blade = maxi(blade, pickup)
				if pickup > 0 and pickup not in all_blades:
					all_blades.append(pickup)
				for index in world.boxes.size():
					var box: AABB = world.boxes[index]
					if absf(player.position.y - box.end.y) < 0.001 and player.position.x > box.position.x - 0.35 and player.position.x < box.end.x + 0.35 and player.position.z > box.position.z - 0.35 and player.position.z < box.end.z + 0.35:
						if index not in all_stood_on:
							all_stood_on.append(index)
		var elapsed: float = ticks * DT
		check(ticks == int(branch["ticks"]), "%s replays every recorded input tick" % branch["name"])
		check(absf(mana - float(branch["expected_mana"])) < 0.01, "%s gathers its recorded mana through real standing/channeling" % branch["name"])
		check(blade >= int(branch["blade"]), "%s reaches its sword pickup on foot" % branch["name"])
		check(player.grounded, "%s ends safely on a real island" % branch["name"])
		for id: int in branch["pools"]:
			check(id in collected, "%s actually harvests pool %d" % [branch["name"], id])
			check(float(world.pools[id]["remaining"]) < 0.01, "%s can fully channel finite pool %d" % [branch["name"], id])
		if bool(branch["portal"]):
			check(world.portal_in_range(player.position), "prepared route returns physically to the core portal")
			check(elapsed < CORE_LIFETIME, "prepared route returns before the three-minute core expires")
			check(mana >= 250.0 and mana <= MANA_CAPACITY, "prepared route brings at least 250 mana within capacity")
			check(blade >= 1, "prepared route returns carrying a discovered sword")
			print("Prepared expedition: %.2f seconds / 180, %.0f mana, blade %d, returned to portal" % [elapsed, mana, blade])
		else:
			check(elapsed < CORE_LIFETIME, "%s is reachable within one exploration phase" % branch["name"])
			print("Branch %s: %.2f seconds, %.0f mana, blade %d" % [branch["name"], elapsed, mana, blade])
	for id in 7:
		check(id in all_harvested, "pool %d is physically reachable and harvestable" % id)
	check(1 in all_blades and 2 in all_blades, "both sword tiers are reachable through gameplay")
	var targets: Array[int] = []
	for route: Array in world.POOL_ROUTES.values():
		for index: int in route:
			if index not in targets:
				targets.append(index)
	for route: Array in world.CONNECTOR_ROUTES:
		for index: int in route:
			if index not in targets:
				targets.append(index)
	for index in targets:
		check(index in all_stood_on, "resource routes stand on designated platform %d" % index)
	check(wall_jumps >= 2, "crown branch uses actual wall jumps")
	check(assisted_vaults >= 1, "expedition routes use the automatic lip assist")
	print("Expedition routes: %d assertions, %d failures; %d route platforms, %d wall jumps, %d quick / %d assisted vaults" % [assertions, failures, targets.size(), wall_jumps, quick_vaults, assisted_vaults])
	world.free()
	player.free()
	quit(0 if failures == 0 else 1)
