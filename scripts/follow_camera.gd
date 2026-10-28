extends Camera3D
class_name ParkourCamera
## Orbit camera with automatic recentering, obstacle avoidance and sprint FOV.
var yaw: float = 0.0
var pitch: float = 0.35
var idle: float = 9.0
var distance: float = 5.2
var base_distance: float = 5.2
var base_fov: float = 60.0
var dip: float = 0.0
var target := Vector3(0, 1, 4)
var boxes: Array[AABB] = []

func orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.0025
	pitch = clampf(pitch + relative.y * 0.0025, -0.25, 1.2)
	idle = 0.0

func tick(dt: float, player: ParkourPlayer) -> void:
	idle += dt
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	if idle > 1.0 and player.state == "move" and speed > 3.0 * ParkourPlayer.MOVEMENT_SCALE:
		var facing: float = (-player.velocity.x * sin(yaw) - player.velocity.z * cos(yaw)) / speed
		if facing > 0.3:
			yaw = lerp_angle(yaw, atan2(-player.velocity.x, -player.velocity.z), 1.0 - exp(-1.2 * dt * facing))
	dip *= exp(-6.0 * dt)
	target.x = lerpf(target.x, player.position.x, 1.0 - exp(-18.0 * dt))
	target.z = lerpf(target.z, player.position.z, 1.0 - exp(-18.0 * dt))
	target.y = lerpf(target.y, player.position.y + 1.0 - dip, 1.0 - exp(-9.0 * dt))
	var orbit_direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var desired_distance: float = base_distance
	for bounds in boxes:
		desired_distance = minf(desired_distance, ray_box(target, orbit_direction, bounds) - 0.3)
	desired_distance = maxf(desired_distance, 0.8)
	distance = desired_distance if desired_distance < distance else lerpf(distance, desired_distance, 1.0 - exp(-4.0 * dt))
	position = target + orbit_direction * distance
	look_at(target + Vector3.UP * 0.1, Vector3.UP)
	fov = lerpf(fov, base_fov + clampf((speed / ParkourPlayer.MOVEMENT_SCALE - 6.0) * 1.4, 0.0, 18.0), 1.0 - exp(-5.0 * dt))

static func ray_box(origin: Vector3, direction: Vector3, bounds: AABB) -> float:
	var low: float = 0.0
	var high: float = 1.0e9
	for axis in 3:
		if absf(direction[axis]) < 1.0e-6:
			if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]:
				return 1.0e9
		else:
			var a: float = (bounds.position[axis] - origin[axis]) / direction[axis]
			var b: float = (bounds.end[axis] - origin[axis]) / direction[axis]
			if a > b:
				var swap: float = a
				a = b
				b = swap
			low = maxf(low, a)
			high = minf(high, b)
			if low > high:
				return 1.0e9
	return low
