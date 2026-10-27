extends Node3D
class_name ParkourCourse
## Original course, in meters. Bounds are shared by the mesh and player solver.
const SAND := Color("e8dfd0")
const STONE := Color("cfc8bb")
const CORAL := Color("e4604a")
const INK := Color("41525e")
const SLATE := Color("6b7f8f")
const GOLD := Color("f0bf4a")
const PALE := Color("f4efe6")

const CHECKPOINTS: Array[Dictionary] = [
	{"position": Vector3(0, 0, 4), "name": "Start"},
	{"position": Vector3(0, 3.2, -37), "name": "Ledge climb"},
	{"position": Vector3(0, 5.4, -43), "name": "Wall-jump shaft"},
	{"position": Vector3(-3.5, 12.6, -49), "name": "Shaft top"},
	{"position": Vector3(0, 6.6, -56.5), "name": "Wall-slide pad"},
	{"position": Vector3(48, 12.6, -57), "name": "Finish"},
]
var boxes: Array[AABB] = []
var sun: DirectionalLight3D
var materials: Dictionary = {}

func setup() -> void:
	_environment()
	platform(0, 0, 0, 18, 18, SAND, 2)
	for p in [Vector3(0, 0, -13.5), Vector3(2.5, 0.4, -19.5), Vector3(-2, 0.8, -25.5), Vector3(2, 1.2, -31)]:
		platform(p.x, p.y, p.z, 4, 3, STONE)
	platform(0, 3.2, -37, 10, 7, CORAL, 4.4)
	platform(0, 5.4, -48, 16, 13, SAND, 6.4)
	box(Vector3(-5, 5.4, -53), Vector3(-2, 12.6, -45), INK)
	box(Vector3(2, 5.4, -53), Vector3(5, 12.6, -45), INK)
	box(Vector3(-5, 5.4, -54.5), Vector3(5, 12.6, -53), INK)
	platform(0, 6.6, -56.5, 18, 4, SAND, 2)
	box(Vector3(-9, 4, -63), Vector3(9, 24, -58.5), SLATE)
	var hops: Array[Vector3] = [Vector3(13, 7.2, -56.5), Vector3(18.5, 8.4, -54), Vector3(24, 9.6, -57), Vector3(29.5, 8.6, -60), Vector3(35, 10.2, -57), Vector3(40.5, 11.6, -54)]
	for i in hops.size():
		var p: Vector3 = hops[i]
		platform(p.x, p.y, p.z, 3.4, 3.4, PALE if i % 2 else CORAL, 0.8)
	platform(48, 12.6, -57, 10, 10, GOLD, 1.5)
	_flag()
	for i in range(1, CHECKPOINTS.size()):
		var marker := MeshInstance3D.new()
		marker.name = "Checkpoint%d" % i
		var disk := CylinderMesh.new()
		disk.top_radius = 1.1
		disk.bottom_radius = 1.1
		disk.height = 0.06
		disk.radial_segments = 24
		marker.mesh = disk
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.7) if i == 5 else Color(0.294, 0.839, 0.627, 0.7)
		marker.material_override = mat
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = CHECKPOINTS[i]["position"] + Vector3.UP * 0.04
		add_child(marker)

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
	visual.material_override = material(color)
	body.add_child(visual)
	# Twelve translucent edges, matching Three.js EdgesGeometry.
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in 3:
		for a in 2:
			for b in 2:
				var start := Vector3.ZERO
				start[axis] = -bounds.size[axis] / 2
				start[(axis + 1) % 3] = bounds.size[(axis + 1) % 3] * (float(a) - 0.5)
				start[(axis + 2) % 3] = bounds.size[(axis + 2) % 3] * (float(b) - 0.5)
				var end := start
				end[axis] *= -1
				lines.surface_add_vertex(start)
				lines.surface_add_vertex(end)
	lines.surface_end()
	var outline := MeshInstance3D.new()
	outline.mesh = lines
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(0.169, 0.227, 0.259, 0.3)
	outline.material_override = line_mat
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(outline)

func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		materials[color] = mat
	return materials[color]

func _flag() -> void:
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = 0.06
	cylinder.height = 3.2
	pole.mesh = cylinder
	pole.material_override = material(INK)
	pole.position = Vector3(48, 14.2, -57)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var rectangle := BoxMesh.new()
	rectangle.size = Vector3(1.4, 0.8, 0.05)
	flag.mesh = rectangle
	flag.material_override = material(CORAL)
	flag.position = Vector3(48.7, 15.4, -57)
	add_child(flag)

func _environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("cfe3ec")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e3e9ed")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color("cfe3ec")
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 70
	env.fog_depth_end = 200
	world.environment = env
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("fff1dc")
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	follow_sun(Vector3.ZERO)

func follow_sun(at: Vector3) -> void:
	sun.position = at + Vector3(22, 38, 16)
	sun.look_at(at, Vector3.UP)
