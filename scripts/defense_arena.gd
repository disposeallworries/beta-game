extends "res://scripts/course.gd"
class_name DefenseArena
## A resource-driven tower siege. Root owns the run and calls tick explicitly.

signal tower_destroyed
signal all_waves_cleared
signal enemy_killed(at: Vector3)
signal player_hit(drain: float)

const TOWER_MAX_HEALTH: float = 200.0
const BOLT_COST: float = 8.0
const BOLT_DAMAGE: float = 24.0
const BOLT_RANGE: float = 24.0
const BOLT_SPEED: float = 22.0
const BOLT_COOLDOWN: float = 0.38
const SWORD_COOLDOWN: float = 0.55
const TOWER_SHOT_COST: float = 2.0
const WAVE_COUNTS: Array[int] = [4, 6, 8, 10]
const SPAWN_POINTS: Array[Vector3] = [Vector3(22, 0, 0), Vector3(0, 0, -22), Vector3(-22, 0, 0), Vector3(0, 0, 22)]
var spawn_point := Vector3(0, 0, 7)
var tower_position := Vector3.ZERO
var tower_health: float = TOWER_MAX_HEALTH
var wave: int = 0
var total_waves: int = 4
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var active: bool = false
var wave_wait: float = 3.0
var bolt_cooldown: float = 0.0
var sword_cooldown: float = 0.0
var tower_cooldown: float = 0.0
var kills: int = 0
var _wave_spawned: bool = false
var _clock: float = 0.0
var _enemy_serial: int = 0
var _player_contact_grace: float = 0.0
var _tower_crystal: MeshInstance3D
var _tower_health_label: Label3D
var _effects: Array[Dictionary] = []


func setup() -> void:
	_environment()
	# The open siege floor needs readable silhouettes beyond the core's pool of
	# light, while retaining the expedition's dusk palette and long shadows.
	for child: Node in get_children():
		if child is WorldEnvironment:
			(child as WorldEnvironment).environment.ambient_light_energy = .40
	sun.light_energy = .48
	platform(0, 0, 0, 52, 52, Color("475866"), 2.0)
	# The tower is solid; the open radial lanes have no invisible nav obstacles.
	box(Vector3(-1.4, 0, -1.4), Vector3(1.4, 3.6, 1.4), Color("68727d"))
	for axis in 2:
		for side in [-1.0, 1.0]:
			for half in [-1.0, 1.0]:
				var at := Vector3(side * 25.5, 1.7, half * 15.5) if axis == 0 else Vector3(half * 15.5, 1.7, side * 25.5)
				var size := Vector3(1, 3.4, 21) if axis == 0 else Vector3(21, 3.4, 1)
				box(at - size / 2, at + size / 2, INK)
	scenery = Node3D.new()
	scenery.name = "SiegeCourtyard"
	add_child(scenery)
	for axis in 2:
		var size := Vector3(49, .012, 3.8) if axis == 0 else Vector3(3.8, .012, 49)
		_mesh_box(scenery, Vector3(0, .009, 0), size, Color("64787c"))
	for x in [-21.0, 21.0]:
		for z in [-21.0, 21.0]:
			var at := Vector3(x, 0, z)
			_mesh_box(scenery, at + Vector3.UP * 2, Vector3(2.2, 4, 2.2), SLATE.darkened(.3))
			_mesh_box(scenery, at + Vector3.UP * 4.15, Vector3(3, .3, 3), PALE.darkened(.25))
			_lantern(at + Vector3.UP * 4.3)
	for i in SPAWN_POINTS.size():
		_build_gate(SPAWN_POINTS[i], i)
	_build_tower()
	_label(Vector3(0, 7.8, -1), "THE HEARTKEEP", 40, Color("d8eadc"))


func _build_tower() -> void:
	var foundation := CylinderMesh.new()
	foundation.top_radius = 2.3
	foundation.bottom_radius = 2.7
	foundation.height = .38
	foundation.radial_segments = 8
	_mesh(scenery, foundation, Vector3(0, .19, 0), INK)
	for y in [1.1, 2.4, 3.65]:
		_mesh_box(scenery, Vector3(0, y, 0), Vector3(3.2, .22, 3.2), PALE.darkened(.22))
	var pedestal := CylinderMesh.new()
	pedestal.top_radius = .9
	pedestal.bottom_radius = 1.6
	pedestal.height = 1.3
	pedestal.radial_segments = 8
	_mesh(scenery, pedestal, Vector3(0, 4.35, 0), Color("516676"))
	var crystal := PrismMesh.new()
	crystal.size = Vector3(1.4, 2.4, 1.4)
	_tower_crystal = _mesh(scenery, crystal, Vector3(0, 6.1, 0), Color("67e2ce"))
	_tower_crystal.material_override = _emissive(Color("67e2ce"), .65)
	var core_light := OmniLight3D.new()
	core_light.name = "TowerCoreLight"
	core_light.position = Vector3(0, 5, 0)
	core_light.light_color = Color("8edbd5")
	core_light.light_energy = .8
	core_light.omni_range = 12.0
	core_light.shadow_enabled = false
	scenery.add_child(core_light)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.3
	ring.outer_radius = 1.42
	ring.rings = 24
	ring.ring_segments = 8
	var halo := _mesh(scenery, ring, Vector3(0, 5.8, 0), Color("c9b180"))
	halo.material_override = _emissive(Color("c9b180"), .2)
	_tower_health_label = Label3D.new()
	_tower_health_label.text = "TOWER  200 / 200"
	_tower_health_label.position = Vector3(0, 8.3, 0)
	_tower_health_label.font_size = 30
	_tower_health_label.pixel_size = .009
	_tower_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tower_health_label.modulate = Color("d0f3dd")
	scenery.add_child(_tower_health_label)


func _build_gate(at: Vector3, index: int) -> void:
	var direction: Vector3 = -at.normalized()
	var right := Vector3(direction.z, 0, -direction.x)
	for side in [-1.0, 1.0]:
		_mesh_box(scenery, at + right * side * 2 + Vector3.UP * 1.8, Vector3(.65, 3.6, .65), INK)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.5
	ring.outer_radius = 1.65
	ring.rings = 24
	ring.ring_segments = 8
	var portal := _mesh(scenery, ring, at + Vector3.UP * 1.9, Color("a95988"))
	portal.rotation = Vector3(PI / 2, atan2(direction.x, direction.z), 0)
	portal.material_override = _emissive(Color("d86291"), .5)
	_label(at + Vector3.UP * 4.2, "RIFT %d" % (index + 1), 25, Color("e7b5bb"))


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = .7
	return mat


func start_defense() -> void:
	_clear_entities()
	tower_health = TOWER_MAX_HEALTH
	wave = 0
	wave_wait = 3.0
	_wave_spawned = false
	bolt_cooldown = 0
	sword_cooldown = 0
	tower_cooldown = 0
	_player_contact_grace = 0
	kills = 0
	active = true
	_update_tower()


func stop_defense() -> void:
	active = false
	for projectile in projectiles:
		_dispose(projectile["node"])
	projectiles.clear()


func tick(dt: float, player_position: Vector3, spend_mana: Callable) -> void:
	if dt <= 0:
		return
	_clock += dt
	_tick_effects(dt)
	if is_instance_valid(_tower_crystal):
		_tower_crystal.rotation.y += dt * .35
	if not active:
		return
	bolt_cooldown = maxf(0, bolt_cooldown - dt)
	sword_cooldown = maxf(0, sword_cooldown - dt)
	tower_cooldown = maxf(0, tower_cooldown - dt)
	_player_contact_grace = maxf(0, _player_contact_grace - dt)
	if enemies.is_empty():
		if _wave_spawned:
			if wave >= total_waves:
				active = false
				all_waves_cleared.emit()
				return
			_wave_spawned = false
			wave_wait = 6.0
		wave_wait -= dt
		if wave_wait <= 0:
			_spawn_wave()
	for enemy: Dictionary in enemies.duplicate():
		if not active:
			return
		_tick_enemy(enemy, dt, player_position)
	if not active:
		return
	_tick_projectiles(dt)
	if not active:
		return
	if tower_cooldown <= 0:
		var target: Dictionary = nearest_enemy(tower_position, 17.0)
		if not target.is_empty():
			if spend_mana.is_valid() and bool(spend_mana.call(TOWER_SHOT_COST)):
				if not active:
					return
				var target_at: Vector3 = _enemy_center(target)
				var horizontal: Vector3 = target["position"] - tower_position
				horizontal.y = 0
				var origin: Vector3 = tower_position + Vector3.UP * 4.2 + horizontal.normalized() * 1.65
				_add_bolt(origin, (target_at - origin).normalized(), 12.0, true)
				tower_cooldown = 1.2
			else:
				tower_cooldown = .2


func _spawn_wave() -> void:
	wave += 1
	_wave_spawned = true
	var count: int = WAVE_COUNTS[mini(wave - 1, WAVE_COUNTS.size() - 1)]
	for i in count:
		var lane: int = (i + wave - 1) % SPAWN_POINTS.size()
		var at: Vector3 = SPAWN_POINTS[lane]
		var tangent := Vector3(-at.z, 0, at.x).normalized()
		at += tangent * (float(i / 4) - .5) * 1.4
		var kind: String = "brute" if wave >= 2 and i % (5 - mini(wave, 3)) == 0 else "crawler"
		spawn_enemy(kind, at)


func spawn_enemy(kind: String, at: Vector3) -> Dictionary:
	kind = "brute" if kind == "brute" else "crawler"
	var brute: bool = kind == "brute"
	var node := Node3D.new()
	node.name = "%s%d" % [kind.capitalize(), _enemy_serial]
	_enemy_serial += 1
	node.position = at
	add_child(node)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .72 if brute else .5
	sphere.height = 1.75 if brute else 1.05
	sphere.radial_segments = 8
	sphere.rings = 4
	body.mesh = sphere
	body.position.y = .88 if brute else .55
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("755c98") if brute else Color("bb6c63")
	skin.roughness = .92
	skin.emission_enabled = true
	skin.emission = Color("ffddb1")
	skin.emission_energy_multiplier = 0
	body.material_override = skin
	node.add_child(body)
	for side in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = .1 if brute else .075
		eye.height = .12 if brute else .09
		eye.radial_segments = 6
		eye.rings = 3
		var eye_node := _mesh(node, eye, Vector3(side * .21, 1.1 if brute else .69, -.62 if brute else -.45), Color("f8cd7e"))
		eye_node.material_override = _emissive(Color("f8cd7e"), .6)
		var leg := BoxMesh.new()
		leg.size = Vector3(.22, .28, .55) if brute else Vector3(.17, .18, .36)
		_mesh(node, leg, Vector3(side * (.46 if brute else .33), .13, 0), skin.albedo_color.darkened(.2))
	if brute:
		for side in [-1.0, 1.0]:
			var horn := PrismMesh.new()
			horn.size = Vector3(.28, .7, .28)
			_mesh(node, horn, Vector3(side * .45, 1.85, 0), PALE.darkened(.15))
	var health_label := Label3D.new()
	health_label.position = Vector3(0, 2.45 if brute else 1.4, 0)
	health_label.font_size = 18
	health_label.pixel_size = .005
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.modulate = Color("f0b7ae")
	node.add_child(health_label)
	var enemy: Dictionary = {
		"kind": kind, "hp": 72.0 if brute else 30.0, "max_hp": 72.0 if brute else 30.0,
		"position": at, "node": node, "body": body, "skin": skin, "label": health_label,
		"alive": true, "speed": 1.3 if brute else 1.8, "attack_damage": 16.0 if brute else 8.0,
		"attack_period": 1.3 if brute else .9, "attack_time": .5, "contact_time": 0.0,
		"hit_time": 0.0, "seed": float(_enemy_serial) * 1.9,
	}
	_update_enemy_health(enemy)
	enemies.append(enemy)
	return enemy


func _tick_enemy(enemy: Dictionary, dt: float, player_position: Vector3) -> void:
	if not enemy["alive"]:
		return
	var at: Vector3 = enemy["position"]
	var toward: Vector3 = tower_position - at
	toward.y = 0
	var distance: float = toward.length()
	enemy["attack_time"] = maxf(0, float(enemy["attack_time"]) - dt)
	enemy["contact_time"] = maxf(0, float(enemy["contact_time"]) - dt)
	if distance > 2.21:
		var heading: Vector3 = toward.normalized()
		var avoidance := Vector3.ZERO
		for other: Dictionary in enemies:
			if other == enemy or not other["alive"]:
				continue
			var separation: Vector3 = at - (other["position"] as Vector3)
			separation.y = 0
			var separation_length: float = separation.length()
			if separation_length > .001 and separation_length < 1.15:
				avoidance += separation / separation_length * (1.15 - separation_length) * .7
		var move: Vector3 = (heading + avoidance).normalized() * float(enemy["speed"]) * dt
		if move.length() > distance - 2.2:
			move = move.normalized() * maxf(0, distance - 2.2)
		at += move
		enemy["position"] = at
		(enemy["node"] as Node3D).position = at
		(enemy["node"] as Node3D).rotation.y = atan2(-heading.x, -heading.z)
	elif float(enemy["attack_time"]) <= 0:
		damage_tower(float(enemy["attack_damage"]))
		enemy["attack_time"] = enemy["attack_period"]
	if not active:
		return
	if at.distance_to(player_position) < 1.2 and _player_contact_grace <= 0 and float(enemy["contact_time"]) <= 0:
		_player_contact_grace = .75
		enemy["contact_time"] = 1.2
		player_hit.emit(3.0)
	if not active:
		return
	enemy["hit_time"] = maxf(0, float(enemy["hit_time"]) - dt)
	var skin: StandardMaterial3D = enemy["skin"]
	skin.emission_energy_multiplier = 1.2 if float(enemy["hit_time"]) > 0 else 0.0
	var body: MeshInstance3D = enemy["body"]
	body.position.y = (.88 if enemy["kind"] == "brute" else .55) + sin(_clock * 6 + float(enemy["seed"])) * .035


func damage_tower(amount: float) -> void:
	if not active or amount <= 0:
		return
	tower_health = maxf(0, tower_health - amount)
	_update_tower()
	if tower_health <= 0:
		active = false
		tower_destroyed.emit()


func _update_tower() -> void:
	if is_instance_valid(_tower_health_label):
		_tower_health_label.text = "TOWER  %d / %d" % [ceili(tower_health), int(TOWER_MAX_HEALTH)]
		_tower_health_label.modulate = Color("f0a091") if tower_health < 60 else Color("d0f3dd")
	if is_instance_valid(_tower_crystal):
		_tower_crystal.scale = Vector3.ONE * (.8 + .2 * tower_health / TOWER_MAX_HEALTH)


func fire_bolt(origin: Vector3, direction: Vector3, spend_mana: Callable) -> bool:
	if not active or bolt_cooldown > 0 or direction.length_squared() < .001:
		return false
	if not spend_mana.is_valid() or not bool(spend_mana.call(BOLT_COST)):
		return false
	if not active:
		return false
	var requested_aim: Vector3 = direction.normalized()
	var aim: Vector3 = requested_aim
	var best_angle: float = cos(deg_to_rad(12.0))
	for enemy: Dictionary in enemies:
		var offset: Vector3 = _enemy_center(enemy) - origin
		if offset.length() <= BOLT_RANGE and offset.length() > .01:
			var angle: float = requested_aim.dot(offset.normalized())
			if angle > best_angle:
				best_angle = angle
				aim = offset.normalized()
	_add_bolt(origin, aim, BOLT_DAMAGE, false)
	bolt_cooldown = BOLT_COOLDOWN
	return true


func _add_bolt(origin: Vector3, direction: Vector3, damage: float, from_tower: bool) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = .16 if not from_tower else .11
	sphere.height = sphere.radius * 2
	sphere.radial_segments = 8
	sphere.rings = 4
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.position = origin
	mesh.material_override = _emissive(Color("8ce5dc") if not from_tower else Color("e9cc83"), 1.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	projectiles.append({"position": origin, "direction": direction, "damage": damage, "remaining": BOLT_RANGE, "node": mesh, "tower": from_tower})


func _tick_projectiles(dt: float) -> void:
	for projectile: Dictionary in projectiles.duplicate():
		var from: Vector3 = projectile["position"]
		var length: float = minf(BOLT_SPEED * dt, float(projectile["remaining"]))
		var to: Vector3 = from + (projectile["direction"] as Vector3) * length
		var hit: Dictionary = {}
		var closest: float = 2.0
		for enemy: Dictionary in enemies:
			var fraction: float = _segment_sphere(from, to, _enemy_center(enemy), 1.0 if enemy["kind"] == "brute" else .67)
			if fraction >= 0 and fraction < closest:
				closest = fraction
				hit = enemy
		var wall_fraction: float = _wall_hit(from, to, bool(projectile["tower"]))
		if wall_fraction >= 0 and wall_fraction < closest:
			hit = {}
			closest = wall_fraction
		if closest <= 1:
			var at: Vector3 = from.lerp(to, closest)
			if not hit.is_empty():
				damage_enemy(hit, float(projectile["damage"]))
			_flash(at, Color("9ce8df"), .18, .25)
			_remove_projectile(projectile)
			continue
		projectile["position"] = to
		projectile["remaining"] = float(projectile["remaining"]) - length
		(projectile["node"] as Node3D).position = to
		if float(projectile["remaining"]) <= 0:
			_remove_projectile(projectile)


func _wall_hit(from: Vector3, to: Vector3, from_tower: bool) -> float:
	var closest: float = 2.0
	var total_length: float = from.distance_to(to)
	if total_length < .00001:
		return -1.0
	for i in boxes.size():
		if from_tower and i == 1:
			continue # A tower's own bolts leave from its rotating upper crystal.
		var hit: Variant = boxes[i].intersects_segment(from, to)
		if hit is Vector3:
			closest = minf(closest, from.distance_to(hit) / total_length)
	return closest if closest <= 1 else -1.0


static func _segment_sphere(from: Vector3, to: Vector3, center: Vector3, radius: float) -> float:
	var offset: Vector3 = from - center
	if offset.length_squared() <= radius * radius:
		return 0.0
	var delta: Vector3 = to - from
	var a: float = delta.length_squared()
	if a < .000001:
		return -1.0
	var b: float = 2.0 * offset.dot(delta)
	var c: float = offset.length_squared() - radius * radius
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0:
		return -1.0
	var result: float = (-b - sqrt(discriminant)) / (2.0 * a)
	return result if result >= 0 and result <= 1 else -1.0


func swing_sword(origin: Vector3, forward: Vector3, level: int) -> bool:
	if not active or level <= 0 or sword_cooldown > 0:
		return false
	var direction := Vector3(forward.x, 0, forward.z)
	if direction.length_squared() < .001:
		return false
	direction = direction.normalized()
	sword_cooldown = SWORD_COOLDOWN
	for enemy: Dictionary in enemies.duplicate():
		var offset: Vector3 = enemy["position"] - origin
		if absf(offset.y) > 1.8:
			continue
		offset.y = 0
		if offset.length() <= 2.8 and (offset.length() < .001 or offset.normalized().dot(direction) >= cos(deg_to_rad(55.0))):
			damage_enemy(enemy, 44.0 if level >= 2 else 30.0)
	_sword_arc(origin + Vector3.UP * .7, direction)
	return true


func damage_enemy(enemy: Dictionary, amount: float) -> void:
	if amount <= 0 or not enemy.get("alive", false):
		return
	enemy["hp"] = maxf(0, float(enemy["hp"]) - amount)
	enemy["hit_time"] = .12
	_update_enemy_health(enemy)
	if float(enemy["hp"]) <= 0:
		enemy["alive"] = false
		var at: Vector3 = enemy["position"]
		enemies.erase(enemy)
		kills += 1
		for i in 5:
			_flash(at + Vector3(randf_range(-.4, .4), randf_range(.3, 1.1), randf_range(-.4, .4)), Color("c78eae"), .25, .12)
		_dispose(enemy["node"])
		enemy_killed.emit(at)


func nearest_enemy(origin: Vector3, maximum_range: float) -> Dictionary:
	var target: Dictionary = {}
	var closest: float = maximum_range
	for enemy: Dictionary in enemies:
		var offset: Vector3 = enemy["position"] - origin
		offset.y = 0
		if offset.length() < closest:
			closest = offset.length()
			target = enemy
	return target


func _enemy_center(enemy: Dictionary) -> Vector3:
	return (enemy["position"] as Vector3) + Vector3.UP * (1.0 if enemy["kind"] == "brute" else .65)


func _update_enemy_health(enemy: Dictionary) -> void:
	var label: Label3D = enemy["label"]
	label.text = "%d / %d" % [ceili(float(enemy["hp"])), int(enemy["max_hp"])]
	label.visible = float(enemy["hp"]) > 0 and float(enemy["hp"]) < float(enemy["max_hp"])


func _sword_arc(at: Vector3, forward: Vector3) -> void:
	var curve := ImmediateMesh.new()
	curve.surface_begin(Mesh.PRIMITIVE_LINES)
	var right := Vector3(forward.z, 0, -forward.x)
	for i in 14:
		var a: float = lerpf(-.95, .95, float(i) / 14)
		var b: float = lerpf(-.95, .95, float(i + 1) / 14)
		curve.surface_add_vertex((forward * cos(a) + right * sin(a)) * 2.25)
		curve.surface_add_vertex((forward * cos(b) + right * sin(b)) * 2.25)
	curve.surface_end()
	var mesh := MeshInstance3D.new()
	mesh.mesh = curve
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("f2d294")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	add_child(mesh)
	_effects.append({"node": mesh, "life": .16, "duration": .16, "material": mat, "grow": false})


func _flash(at: Vector3, color: Color, duration: float, radius: float) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2
	sphere.radial_segments = 6
	sphere.rings = 3
	mesh.mesh = sphere
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_effects.append({"node": mesh, "life": duration, "duration": duration, "material": mat, "grow": true})


func _tick_effects(dt: float) -> void:
	for effect: Dictionary in _effects.duplicate():
		effect["life"] = float(effect["life"]) - dt
		var node: MeshInstance3D = effect["node"]
		var mat: StandardMaterial3D = effect["material"]
		mat.albedo_color.a = maxf(0, float(effect["life"]) / float(effect["duration"]))
		if effect["grow"]:
			node.scale += Vector3.ONE * dt * 2
		if float(effect["life"]) <= 0:
			_dispose(node)
			_effects.erase(effect)


func _remove_projectile(projectile: Dictionary) -> void:
	_dispose(projectile["node"])
	projectiles.erase(projectile)


func _dispose(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _clear_entities() -> void:
	for enemy: Dictionary in enemies:
		_dispose(enemy["node"])
	enemies.clear()
	for projectile: Dictionary in projectiles:
		_dispose(projectile["node"])
	projectiles.clear()
	for effect: Dictionary in _effects:
		_dispose(effect["node"])
	_effects.clear()
