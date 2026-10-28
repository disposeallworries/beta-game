extends Node3D
class_name ParkourDust
## Small reusable particle pool: no texture, plug-in, or GPU-particle dependency.
var particles: Array[Dictionary] = []
var footstep_time: float = 0.0

func setup() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	sphere.radial_segments = 6
	sphere.rings = 4
	for i in 30:
		var mesh := MeshInstance3D.new()
		mesh.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color("f2eee6")
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)
		particles.append({"mesh": mesh, "material": mat, "life": 0.0, "velocity": Vector3.ZERO})

func emit_dust(at: Vector3, count: int, speed: float) -> void:
	for i in count:
		for particle in particles:
			if float(particle["life"]) > 0:
				continue
			particle["life"] = 0.5
			var mesh: MeshInstance3D = particle["mesh"]
			mesh.position = at + Vector3(randf_range(-0.2, 0.2), 0.05, randf_range(-0.2, 0.2))
			mesh.scale = Vector3.ONE * 0.5
			mesh.visible = true
			particle["velocity"] = Vector3(randf_range(-0.5, 0.5) * speed, randf_range(0.3, 1.5), randf_range(-0.5, 0.5) * speed)
			var mat: StandardMaterial3D = particle["material"]
			mat.albedo_color.a = 0.6
			break

func tick(dt: float, player: ParkourPlayer) -> void:
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if player.grounded and speed > 8.0 * ParkourPlayer.MOVEMENT_SCALE:
		footstep_time -= dt
		if footstep_time < 0.0:
			footstep_time = 0.08 if speed > 12.0 * ParkourPlayer.MOVEMENT_SCALE else 0.14
			emit_dust(player.position, 1, 0.8)
	for particle in particles:
		var life: float = particle["life"]
		if life <= 0:
			continue
		life -= dt
		particle["life"] = life
		var mesh: MeshInstance3D = particle["mesh"]
		mesh.position += (particle["velocity"] as Vector3) * dt
		mesh.scale = Vector3.ONE * (0.5 + (1.0 - life / 0.5) * 2.2)
		var mat: StandardMaterial3D = particle["material"]
		mat.albedo_color.a = maxf(life / 0.5, 0.0) * 0.6
		if life <= 0:
			mesh.visible = false
