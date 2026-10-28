extends Node3D
class_name ParkourCourse
## Mintwind Gardens: a winding, readable floating-garden parkour course.
## Walkable geometry is shared exactly by the native shapes and player solver.
const SAND := Color("e1d5bc")
const STONE := Color("bcc9c2")
const CORAL := Color("d98069")
const INK := Color("435b60")
const SLATE := Color("819c9c")
const GOLD := Color("e6bb61")
const PALE := Color("f1ead8")
const MINT := Color("82bfa3")
const LEAF := Color("639e89")
const CHECKPOINTS: Array[Dictionary] = [
	{"position": Vector3(0, 0, 5), "name": "Arrival courtyard"},
	{"position": Vector3(0, 2.2, -56), "name": "Mint garden"},
	{"position": Vector3(0, 5.2, -74), "name": "Terrace ruins"},
	{"position": Vector3(26, 6.8, -81), "name": "Wall-jump courtyard"},
	{"position": Vector3(26, 12, -91), "name": "Sky gate"},
	{"position": Vector3(56, 11.2, -94), "name": "Cloud orchard"},
	{"position": Vector3(74, 14, -69), "name": "Wind bridge"},
	{"position": Vector3(62, 17.6, -19), "name": "Sunset garden"},
]
# Ordered goals for human wayfinding and deterministic controls-only playtests.
# The shaft is climbed onto its left wall (19); walls20/21 are not route goals.
const ROUTE_TARGETS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46]
var boxes: Array[AABB] = []
var sun: DirectionalLight3D
var materials: Dictionary = {}
var scenery: Node3D

func setup() -> void:
	_environment()
	# Arrival and the stepping garden: clear gaps are generally one meter.
	platform(0, 0, 2, 18, 18, SAND, 2)
	var garden: Array[Vector3] = [Vector3(0, .2, -10), Vector3(2, .4, -15), Vector3(-1, .7, -20), Vector3(-3, 1, -25), Vector3(0, 1.3, -30), Vector3(3, 1.3, -35), Vector3(1, 1.6, -40), Vector3(-2, 1.9, -45), Vector3(0, 2.2, -50)]
	for i in garden.size():
		var p: Vector3 = garden[i]
		platform(p.x, p.y, p.z, 6.0 if i == 0 or i == 8 else 5.0, 4, MINT if i % 3 == 0 else PALE, 1.15)
	platform(0, 2.2, -56, 14, 7, MINT, 2)
	# One deliberately taller lip teaches a proper grab and supported pull-up.
	platform(0, 3, -62, 7, 4, PALE, 1.4)
	platform(0, 5.2, -67.5, 9, 5, CORAL, 3)
	platform(0, 5.2, -74, 14, 7, SAND, 2)
	for p in [Vector3(5, 5.7, -79.5), Vector3(10, 6, -81), Vector3(15, 6.4, -81), Vector3(20, 6.8, -81)]:
		platform(p.x, p.y, p.z, 4, 5, PALE, 1.1)
	platform(26, 6.8, -81, 10, 10, SAND, 2)
	# Narrow three-meter shaft: repeated wall jumps work at the calmer speed.
	box(Vector3(22, 6.8, -85), Vector3(24.5, 12, -78), INK)
	box(Vector3(27.5, 6.8, -85), Vector3(30, 12, -78), INK)
	box(Vector3(22, 6.8, -87), Vector3(30, 12, -85), SLATE)
	platform(20.5, 12, -88, 5, 4, MINT, 1.4)
	platform(26, 12, -91, 12, 7, SAND, 2)
	# Orchard trail bends east, then the wind bridge curves back toward the sun.
	var trail: Array[Vector3] = [Vector3(34, 12, -92), Vector3(39, 12.4, -94), Vector3(44, 12.8, -96), Vector3(49, 12, -96)]
	for i in trail.size():
		var p: Vector3 = trail[i]
		platform(p.x, p.y, p.z, 4, 5, MINT if i % 2 else PALE, 1.15)
	platform(56, 11.2, -94, 10, 10, MINT, 2)
	var bend: Array[Vector3] = [Vector3(64, 11.6, -92), Vector3(69, 12, -89), Vector3(73, 12.4, -85), Vector3(75, 12.8, -80), Vector3(74, 13.2, -75)]
	for i in bend.size():
		var p: Vector3 = bend[i]
		platform(p.x, p.y, p.z, 4 if i < 2 else 5, 5 if i < 2 else 4, CORAL if i % 2 else PALE, 1.15)
	platform(74, 14, -69, 10, 6, SAND, 2)
	var bridge: Array[Vector3] = [Vector3(74, 14, -63), Vector3(77, 14.4, -58), Vector3(81, 14.8, -54), Vector3(85, 15.2, -50), Vector3(89, 15.6, -46), Vector3(90, 16, -41), Vector3(86, 16.4, -36), Vector3(81, 16.8, -32), Vector3(77, 17.2, -28), Vector3(73, 17.6, -24), Vector3(68, 17.6, -21)]
	for i in bridge.size():
		var p: Vector3 = bridge[i]
		platform(p.x, p.y, p.z, 4, 5 if i == 10 else 4, MINT if i % 3 == 0 else PALE, 1.25)
	platform(62, 17.6, -19, 12, 12, GOLD, 2.5)
	_build_scenery()
	_flag()
	_checkpoints()

func platform(cx: float, top: float, cz: float, width: float, depth: float, color: Color, thickness: float = 1.2) -> void:
	box(Vector3(cx - width / 2, top - thickness, cz - depth / 2), Vector3(cx + width / 2, top, cz + depth / 2), color)

func box(low: Vector3, high: Vector3, color: Color) -> void:
	var bounds := AABB(low, high - low)
	boxes.append(bounds)
	var body := StaticBody3D.new()
	body.name = "Platform%02d" % boxes.size()
	body.position = bounds.get_center()
	add_child(body)
	var shape := CollisionShape3D.new()
	var cube_shape := BoxShape3D.new()
	cube_shape.size = bounds.size
	shape.shape = cube_shape
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = bounds.size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material(color.darkened(0.12))
	body.add_child(visual)
	# A flush inset cap and shallow lower plinth give the islands a crafted rim.
	_mesh_box(body, Vector3(0, bounds.size.y / 2 - .035, 0), Vector3(bounds.size.x - .025, .07, bounds.size.z - .025), color)
	_mesh_box(body, Vector3(0, bounds.size.y / 2 - .13, 0), Vector3(bounds.size.x + .025, .10, bounds.size.z + .025), color.lightened(.11))
	_mesh_box(body, Vector3(0, -bounds.size.y / 2 - .10, 0), Vector3(bounds.size.x * .84, .20, bounds.size.z * .84), INK.lightened(.08))

func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .9
		materials[color] = mat
	return materials[color]

func _mesh_box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, at, color)

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material(color)
	parent.add_child(instance)
	return instance

func _build_scenery() -> void:
	scenery = Node3D.new()
	scenery.name = "GardenScenery"
	add_child(scenery)
	_wayfinding()
	# Off-center trees leave the route and the camera's travel corridor open.
	for at in [Vector3(-6, 0, 3), Vector3(6, 0, 3), Vector3(-6, 0, -3), Vector3(6, 0, -3), Vector3(-5, 2.2, -56), Vector3(5, 2.2, -56), Vector3(-5, 5.2, -74), Vector3(5, 5.2, -72), Vector3(22, 12, -93), Vector3(30, 12, -93), Vector3(53, 11.2, -97), Vector3(59, 11.2, -97), Vector3(59, 11.2, -91), Vector3(71, 14, -69), Vector3(58, 17.6, -21), Vector3(66, 17.6, -21), Vector3(58, 17.6, -16), Vector3(66, 17.6, -16)]:
		_tree(at)
	_arch(Vector3(0, 0, -4), 0, "MINTWIND GARDENS")
	_arch(Vector3(0, 5.2, -73), 0, "TERRACE RUINS")
	_arch(Vector3(26, 12, -91), PI / 2, "THE SKY GATE")
	_arch(Vector3(62, 17.6, -22), PI / 2, "SUNSET GARDEN")
	for index in [0, 10, 13, 18, 23, 28, 34, 46]:
		var bounds: AABB = boxes[index]
		var top: float = bounds.end.y
		for side in [-1.0, 1.0]:
			var at := Vector3(bounds.position.x + .65 if side < 0 else bounds.end.x - .65, top, bounds.position.z + .65)
			_lantern(at)
	for index in range(boxes.size()):
		if index in [19, 20, 21]:
			continue
		var bounds: AABB = boxes[index]
		# Beneath each traversable island: stone keels and gentle hanging roots.
		var rock := CylinderMesh.new()
		rock.top_radius = minf(bounds.size.x, bounds.size.z) * .32
		rock.bottom_radius = rock.top_radius * .35
		rock.height = 1.5 if bounds.size.x < 8 else 3.0
		rock.radial_segments = 5
		_mesh(scenery, rock, bounds.get_center() - Vector3.UP * (bounds.size.y / 2 + rock.height / 2 + .15), SLATE.darkened(.2))
		for side in [-1.0, 1.0]:
			var root_at := Vector3(bounds.get_center().x + side * bounds.size.x * .32, bounds.position.y - .2, bounds.get_center().z + bounds.size.z * .25)
			_cylinder_between(root_at, root_at + Vector3(side * .15, -1.2 - float(index % 3) * .4, .1), .045, LEAF.darkened(.12))
	# Distant islands are scenery only and lie well outside the marked route.
	for info in [Vector4(-29, -7, -15, 4), Vector4(24, -5, -30, 5), Vector4(-26, -4, -56, 6), Vector4(-24, 1, -86, 5), Vector4(2, -3, -106, 6), Vector4(40, 1, -113, 7), Vector4(77, 3, -111, 5), Vector4(103, 1, -86, 6), Vector4(112, 6, -54, 5), Vector4(105, 7, -15, 7), Vector4(35, -2, -11, 5)]:
		_distant_island(Vector3(info.x, info.y, info.z), info.w)
	# Light banks of cloud anchor the scene without disguising playable edges.
	for info in [Vector4(-20, -9, -15, 5), Vector4(20, -11, -25, 6), Vector4(-16, -7, -78, 7), Vector4(40, -5, -111, 7), Vector4(92, -1, -95, 6), Vector4(106, 3, -51, 7), Vector4(47, 3, -17, 5)]:
		_cloud(Vector3(info.x, info.y, info.z), info.w)

func _wayfinding() -> void:
	for i in range(ROUTE_TARGETS.size() - 1):
		var index: int = ROUTE_TARGETS[i]
		var bounds: AABB = boxes[index]
		var at := Vector3(bounds.get_center().x, bounds.end.y + .008, bounds.get_center().z)
		var next: Vector3 = boxes[ROUTE_TARGETS[i + 1]].get_center()
		if index == 17:
			next = Vector3(21.5, at.y, -76.8)
		if index == 18:
			# The shaft is entered around its open front, not through the left wall.
			at = Vector3(26, bounds.end.y + .008, -76.9)
			next = Vector3(26, at.y, -81)
		_arrow(at, next)
	_arrow(Vector3(21.6, 6.808, -76.9), Vector3(26, 6.808, -76.9))
	_label(Vector3(0, 1.2, 8.8), "A garden above the clouds", 26, INK)
	_label(Vector3(26, 9.6, -76.3), "WALL JUMPS  ↑", 27, INK)
	_label(Vector3(74, 16.8, -69), "WIND BRIDGE", 29, INK)
	for i in range(1, CHECKPOINTS.size() - 1):
		var at: Vector3 = CHECKPOINTS[i]["position"]
		# A small route-number stone beside each checkpoint is readable from any side.
		var pedestal := at + Vector3(-2.3, .28, .7)
		_mesh_box(scenery, pedestal, Vector3(.9, .56, .75), PALE)
		_label(pedestal + Vector3.UP * .7, "%02d" % i, 26, INK)

func _arrow(at: Vector3, target: Vector3) -> void:
	var direction := target - at
	direction.y = 0
	if direction.length_squared() < .01:
		return
	var arrow := ImmediateMesh.new()
	var polygon: Array[Vector3] = [Vector3(0, 0, .7), Vector3(-.42, 0, .05), Vector3(-.15, 0, .05), Vector3(-.15, 0, -.55), Vector3(.15, 0, -.55), Vector3(.15, 0, .05), Vector3(.42, 0, .05)]
	arrow.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, polygon.size() - 1):
		arrow.surface_add_vertex(polygon[0])
		arrow.surface_add_vertex(polygon[i + 1])
		arrow.surface_add_vertex(polygon[i])
	arrow.surface_end()
	var mesh := _mesh(scenery, arrow, at, GOLD)
	mesh.name = "RouteArrow"
	mesh.rotation.y = atan2(direction.x, direction.z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := material(GOLD).duplicate() as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat

func _tree(at: Vector3, scale_factor: float = 1.0, planter: bool = true) -> void:
	if planter:
		_mesh_box(scenery, at + Vector3.UP * .16, Vector3(1.6, .32, 1.6) * scale_factor, PALE)
		_mesh_box(scenery, at + Vector3.UP * .33, Vector3(1.34, .04, 1.34) * scale_factor, INK.lightened(.15))
	var trunk_base: Vector3 = at + Vector3.UP * (.34 if planter else 0.0)
	_cylinder_between(trunk_base, trunk_base + Vector3.UP * 1.8 * scale_factor, .15 * scale_factor, Color("8c7660"))
	for side in [-1.0, 1.0]:
		_cylinder_between(trunk_base + Vector3.UP * .9 * scale_factor, trunk_base + Vector3(side * .55, 1.8, .1) * scale_factor, .075 * scale_factor, Color("8c7660"))
	for offset in [Vector3(-.55, 2.05, 0), Vector3(.55, 2.25, .1), Vector3(0, 2.8, -.1)]:
		var leaves := SphereMesh.new()
		leaves.radius = .85 * scale_factor
		leaves.height = 1.5 * scale_factor
		leaves.radial_segments = 8
		leaves.rings = 4
		_mesh(scenery, leaves, trunk_base + offset * scale_factor, MINT if offset.x <= 0 else LEAF)
	if planter:
		for offset in [Vector3(-.6, .5, .55), Vector3(.6, .5, -.55)]:
			var flower := SphereMesh.new()
			flower.radius = .16
			flower.height = .22
			flower.radial_segments = 6
			flower.rings = 3
			_mesh(scenery, flower, at + offset, CORAL)

func _cylinder_between(from: Vector3, to: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * .82
	cylinder.bottom_radius = radius
	cylinder.height = from.distance_to(to)
	cylinder.radial_segments = 7
	var mesh := _mesh(scenery, cylinder, (from + to) / 2, color)
	mesh.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	return mesh

func _arch(at: Vector3, yaw: float, title: String) -> void:
	var arch := Node3D.new()
	arch.name = "GardenArch"
	arch.position = at
	arch.rotation.y = yaw
	scenery.add_child(arch)
	for side in [-1.0, 1.0]:
		_mesh_box(arch, Vector3(side * 3.1, .18, 0), Vector3(.95, .36, 1.05), PALE)
		_mesh_box(arch, Vector3(side * 3.1, 1.85, 0), Vector3(.5, 3.0, .65), STONE)
		_mesh_box(arch, Vector3(side * 3.1, 3.42, 0), Vector3(.9, .32, .95), PALE)
	_mesh_box(arch, Vector3(0, 3.78, 0), Vector3(7.4, .42, 1.0), PALE)
	_mesh_box(arch, Vector3(0, 3.98, 0), Vector3(6.8, .08, .86), MINT)
	_label(at + Vector3.UP * 4.5, title, 35, INK)

func _label(at: Vector3, text: String, font_size: int, color: Color) -> void:
	var label := Label3D.new()
	label.name = "GardenSign"
	label.text = text
	label.position = at
	label.font_size = font_size
	label.pixel_size = .008
	label.modulate = color
	label.outline_modulate = PALE
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	scenery.add_child(label)

func _lantern(at: Vector3) -> void:
	_mesh_box(scenery, at + Vector3.UP * .1, Vector3(.55, .2, .55), INK)
	_mesh_box(scenery, at + Vector3.UP * .65, Vector3(.13, 1.0, .13), INK)
	_mesh_box(scenery, at + Vector3.UP * 1.25, Vector3(.42, .45, .42), GOLD.lightened(.2))
	_mesh_box(scenery, at + Vector3.UP * 1.53, Vector3(.6, .12, .6), INK)

func _distant_island(at: Vector3, radius: float) -> void:
	var rock := CylinderMesh.new()
	rock.top_radius = radius
	rock.bottom_radius = radius * .15
	rock.height = radius * 1.5
	rock.radial_segments = 6
	_mesh(scenery, rock, at - Vector3.UP * rock.height / 2, SLATE)
	var grass := CylinderMesh.new()
	grass.top_radius = radius
	grass.bottom_radius = radius
	grass.height = .28
	grass.radial_segments = 6
	_mesh(scenery, grass, at, LEAF)
	_tree(at + Vector3.UP * .14, .8, false)

func _cloud(at: Vector3, size: float) -> void:
	for offset in [Vector3(-.6, 0, 0), Vector3(0, .15, -.15), Vector3(.6, -.05, .1)]:
		var sphere := SphereMesh.new()
		sphere.radius = size * .65
		sphere.height = size * .48
		sphere.radial_segments = 10
		sphere.rings = 5
		var mesh := _mesh(scenery, sphere, at + offset * size, Color("eaf1e8"))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _flag() -> void:
	var at: Vector3 = CHECKPOINTS[-1]["position"]
	var pole := CylinderMesh.new()
	pole.top_radius = .06
	pole.bottom_radius = .06
	pole.height = 3.2
	_mesh(self, pole, at + Vector3(0, 1.6, 0), INK)
	_mesh_box(self, at + Vector3(.7, 2.8, 0), Vector3(1.4, .8, .05), CORAL)

func _checkpoints() -> void:
	for i in range(1, CHECKPOINTS.size()):
		var marker := MeshInstance3D.new()
		marker.name = "Checkpoint%d" % i
		var disk := CylinderMesh.new()
		disk.top_radius = 1.1
		disk.bottom_radius = 1.1
		disk.height = .035
		disk.radial_segments = 32
		marker.mesh = disk
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, .65) if i == CHECKPOINTS.size() - 1 else Color(.43, .82, .68, .5)
		marker.material_override = mat
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = CHECKPOINTS[i]["position"] + Vector3.UP * .021
		add_child(marker)

func _environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var gradient := ProceduralSkyMaterial.new()
	gradient.sky_top_color = Color("a5c8d2")
	gradient.sky_horizon_color = Color("e9eee0")
	gradient.ground_bottom_color = Color("9cb9ba")
	gradient.ground_horizon_color = Color("e9eee0")
	gradient.sky_curve = .2
	gradient.ground_curve = .4
	sky.sky_material = gradient
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_color = Color("dce9e2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e3e9ed")
	env.ambient_light_energy = .35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("dce9e2")
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 90
	env.fog_depth_end = 240
	world.environment = env
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("fff1dc")
	sun.light_energy = .75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	follow_sun(Vector3.ZERO)

func follow_sun(at: Vector3) -> void:
	sun.position = at + Vector3(22, 38, 16)
	sun.look_at(at, Vector3.UP)
