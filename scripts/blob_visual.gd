class_name BlobVisual
extends Node3D
## Plays the original glTF clips and layers the HTML game's contact poses over them.
## Clip sampling is manual so the procedural hands/feet are applied after blending.

const MODEL_PATH := "res://assets/mint_blob.glb"
const CLIP_NAMES := ["idle", "walk", "run", "jump"]
const WALK_SPEED := 3.12
const RUN_SPEED := 5.7
const MOVEMENT_SCALE := 0.6
# These are the actual distal centers of the original GLB's arm and leg meshes.
const HAND_TIP := Vector3(0, -0.475, 0)
const FOOT_TIP := Vector3(0, -0.25, 0)
const PIVOTS := [Vector3.ZERO, Vector3(-0.275, 0.725, 0),
	Vector3(0.275, 0.725, 0), Vector3(-0.21, 0.25, 0.03), Vector3(0.21, 0.25, 0.03)]

var player: Node3D
var model: Node3D
var bones: Array[Node3D] = []
var _nodes: Dictionary = {}
var _rest: Dictionary = {}
var _clips: Dictionary = {}
var _weights := PackedFloat32Array([1, 0, 0, 0])
var _times := PackedFloat32Array([0, 0, 0, 0])
var _pose_weight := 0.0
var _pose: Array[Quaternion] = []
var _was_air := false
var _previous_contact := ""
var _grip_anchors: Array[Vector3] = []
var _grip_front := 0.0
var _grip_top := 0.0
var _root_return := 0.0


func setup(for_player: Node3D) -> void:
	player = for_player
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Mint Blob's original GLB could not be loaded.")
		return
	model = packed.instantiate() as Node3D
	add_child(model)
	# Godot's imported AnimationPlayer is intentionally disabled: we sample the same
	# embedded keyframes below, preserving all four simultaneous clip weights.
	for child in model.find_children("*", "AnimationPlayer", true, false):
		(child as AnimationPlayer).active = false
	for bone_name in ["Rig", "ArmL", "ArmR", "LegL", "LegR"]:
		var bone := model.find_child(bone_name, true, false) as Node3D
		if bone == null:
			push_error("Missing original model node: " + bone_name)
			return
		bones.append(bone)
		_pose.append(Quaternion.IDENTITY)
	_load_original_clips()


func tick(dt: float) -> void:
	if model == null or bones.size() != 5:
		return
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var moving: bool = player.state == "move"
	var air: bool = moving and not player.grounded
	var contact: bool = player.state in ["hang", "climb", "wall"]
	# A grip is a geometric constraint: a turning character would sweep its hands
	# sideways through the lip even with otherwise correct local-space IK.
	player.yaw = player.yaw_target if contact else lerp_angle(player.yaw, player.yaw_target,
		1.0 - exp(-14.0 * dt))
	position = player.position
	rotation.y = player.yaw
	if air and not _was_air:
		_times[3] = 0.0
	_was_air = air
	var walk := clampf(speed / WALK_SPEED, 0, 1)
	var run := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0, 1)
	var targets := [1.0 - walk if moving and not air else 0.0,
		walk * (1.0 - run) if moving and not air else 0.0,
		walk * run if moving and not air else 0.0, 1.0 if air else 0.0]
	var weight_sum := 0.0
	for i in range(4):
		_weights[i] = lerpf(_weights[i], targets[i], 1.0 - exp(-12.0 * dt))
		weight_sum += _weights[i]
	if weight_sum < 0.01:
		_weights[0] = 1.0
		weight_sum = 1.0
	for i in range(4):
		var clip: Dictionary = _clips.get(CLIP_NAMES[i], {})
		var length: float = clip.get("duration", 1.0)
		var cadence: float = MOVEMENT_SCALE if i in [1, 2] else 1.0
		_times[i] = minf(_times[i] + dt * length / 0.8, length) if i == 3 else fmod(_times[i] + dt * cadence, length)
	_apply_animation(weight_sum)
	if contact:
		_apply_contact_pose()
		_root_return = 1.0
		_previous_contact = player.state
		return
	_previous_contact = ""
	_grip_anchors.clear()
	# Retain a little of the neutral contact root while returning to locomotion.
	# The model never supplies its own jump displacement on top of physics.
	_root_return *= exp(-14.0 * dt)
	bones[0].position = bones[0].position.lerp(Vector3.ZERO, _root_return)
	bones[0].scale = bones[0].scale.lerp(Vector3.ONE, _root_return)
	var target_pose: Array[Quaternion] = []
	if moving and player.wall_jump_time > 0:
		target_pose = _euler_pose([-0.15, 0, 0, -2.6, 0, -0.7, -2.6, 0, 0.7, -0.9, 0, 0, 0.5, 0, 0])
	elif moving and player.drop_time > 0 and air:
		target_pose = _euler_pose([0.1, 0, 0, -0.3, 0, -1.5, -0.3, 0, 1.5, 0.3, 0, 0, -0.3, 0, 0])
	var pose_rate := 16.0
	if not target_pose.is_empty():
		for i in range(5):
			_pose[i] = target_pose[i] if _pose_weight < 0.02 else _pose[i].slerp(target_pose[i], 1.0 - exp(-pose_rate * dt))
	_pose_weight = lerpf(_pose_weight, 0.0 if target_pose.is_empty() else 1.0, 1.0 - exp(-14.0 * dt))
	if _pose_weight > 0.01:
		for i in range(5):
			bones[i].quaternion = bones[i].quaternion.slerp(_pose[i], _pose_weight)


func _load_original_clips() -> void:
	var animation_player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_error("The original character's animation clips are missing.")
		return
	var animation_root := animation_player.get_node(animation_player.root_node)
	for clip_name: String in CLIP_NAMES:
		var animation := animation_player.get_animation(clip_name)
		var channels: Array[Dictionary] = []
		for track in range(animation.get_track_count()):
			var path := ""
			match animation.track_get_type(track):
				Animation.TYPE_POSITION_3D: path = "translation"
				Animation.TYPE_ROTATION_3D: path = "rotation"
				Animation.TYPE_SCALE_3D: path = "scale"
			if path.is_empty():
				continue
			var node := animation_root.get_node(animation.track_get_path(track)) as Node3D
			var node_id := node.get_instance_id()
			_nodes[node_id] = node
			_rest[node_id] = {"translation": node.position, "rotation": node.quaternion, "scale": node.scale}
			var times: Array = []
			var values: Array = []
			for key in range(animation.track_get_key_count(track)):
				times.append(animation.track_get_key_time(track, key))
				values.append(animation.track_get_key_value(track, key))
			channels.append({"node": node_id, "path": path, "times": times, "values": values})
		_clips[clip_name] = {"duration": animation.length, "channels": channels}


func _sample(channel: Dictionary, time: float) -> Variant:
	var times: Array = channel["times"]
	var values: Array = channel["values"]
	if time <= times[0]:
		return values[0]
	if time >= times[times.size() - 1]:
		return values[values.size() - 1]
	var low := 0
	var high := times.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if times[middle] <= time:
			low = middle
		else:
			high = middle
	var blend: float = (time - times[low]) / (times[high] - times[low])
	if channel["path"] == "rotation":
		return (values[low] as Quaternion).slerp(values[high], blend)
	return (values[low] as Vector3).lerp(values[high], blend)


func _apply_animation(weight_sum: float) -> void:
	var blended: Dictionary = {}
	for i in range(4):
		var weight := _weights[i] / weight_sum
		if weight < 0.00001 or not _clips.has(CLIP_NAMES[i]):
			continue
		for channel: Dictionary in _clips[CLIP_NAMES[i]]["channels"]:
			var node_id: int = channel["node"]
			var path: String = channel["path"]
			var key := str(node_id) + ":" + path
			var value: Variant = _sample(channel, _times[i])
			if not blended.has(key):
				blended[key] = {"node": node_id, "path": path, "value": value, "weight": weight}
			else:
				var entry: Dictionary = blended[key]
				var ratio: float = weight / (entry["weight"] + weight)
				if path == "rotation":
					entry["value"] = (entry["value"] as Quaternion).slerp(value, ratio)
				else:
					entry["value"] = (entry["value"] as Vector3).lerp(value, ratio)
				entry["weight"] += weight
	for node_id: int in _nodes:
		var node: Node3D = _nodes[node_id]
		node.position = _rest[node_id]["translation"]
		node.quaternion = _rest[node_id]["rotation"]
		node.scale = _rest[node_id]["scale"]
	for entry: Dictionary in blended.values():
		if not _nodes.has(entry["node"]):
			continue
		var node: Node3D = _nodes[entry["node"]]
		match entry["path"]:
			"translation":
				# Physics owns the feet position. The GLB jump clip contains a second
				# vertical jump arc, which otherwise makes the body float above it.
				node.position = Vector3.ZERO if node == bones[0] and not player.grounded else entry["value"]
			"rotation": node.quaternion = entry["value"]
			"scale": node.scale = entry["value"]


func _apply_contact_pose() -> void:
	var rig: Node3D = bones[0]
	rig.position = Vector3.ZERO
	rig.scale = Vector3.ONE
	rig.quaternion = Quaternion.IDENTITY
	var progress: float = clampf(player.climb_progress, 0, 1) if player.state == "climb" else 0.0
	var release: float = _smooth(0.35, 0.75, progress)
	if player.state == "wall":
		var sway := sin(player.wall_time * 3.0) * 0.02
		for i in range(2):
			var side: float = -1 if i == 0 else 1
			_aim_endpoint(bones[i + 1], Vector3(side * 0.3, 1.06 + sway * -side, 0.35), HAND_TIP, 0)
			_aim_endpoint(bones[i + 3], Vector3(side * 0.21, 0.10 + sway * side, 0.23), FOOT_TIP, 0)
	else:
		if _grip_anchors.is_empty() or _previous_contact == "wall" or not is_equal_approx(_grip_front, player.ledge_front) or not is_equal_approx(_grip_top, player.ledge["top"]):
			_capture_grip()
		var assisted: bool = player.state == "climb" and player.assisted_vault
		if assisted:
			# A low step-over starts with the torso above the lip. Use the hands as
			# a brief downward push, rather than flipping into an overhead hang.
			release = _smooth(0, 0.45, progress)
		for i in range(2):
			var hand_target: Vector3 = rig.to_local(_grip_anchors[i])
			_aim_endpoint(bones[i + 1], hand_target, HAND_TIP, release)
			# The short legs brace against the wall and step upward with the torso.
			# Aiming at a stationary foot point through the whole pull-up would
			# require stretching these 25 cm meshes several times their length.
			var side: float = -1 if i == 0 else 1
			var sway := sin(player.hang_time * 2.4) * 0.015
			var forward: float = player.ledge_front - player.position.dot(Vector3(player.ledge["ax"], 0, player.ledge["az"])) - 0.12
			var foot_target := Vector3(side * 0.21, 0.10 + 0.05 * i + sway * -side, forward)
			_aim_endpoint(bones[i + 3], foot_target, FOOT_TIP, _smooth(0.3, 0.75, progress))
	_pose_weight = 1.0
	for i in range(5):
		_pose[i] = bones[i].quaternion


func _capture_grip() -> void:
	_grip_anchors.clear()
	_grip_front = player.ledge_front
	_grip_top = player.ledge["top"]
	var forward := Vector3(player.ledge["ax"], 0, player.ledge["az"])
	var right := Vector3(forward.z, 0, -forward.x)
	var center: Vector3 = player.position + forward * (_grip_front - player.position.dot(forward))
	center.y = _grip_top + 0.005
	for side in [-1, 1]:
		_grip_anchors.append(center + right * side * 0.3)


func _aim_endpoint(limb: Node3D, target: Vector3, tip: Vector3, release: float) -> void:
	var delta := target - limb.position
	var length := delta.length()
	if length < 0.001:
		return
	var contact_rotation := Quaternion(Vector3.DOWN, delta / length)
	var neutral: Quaternion = _rest[limb.get_instance_id()]["rotation"]
	limb.quaternion = contact_rotation.slerp(neutral, release)
	# Modest length compensation makes the actual mesh endpoint, rather than an
	# abstract direction vector, coincide with the lip. Never create long arms.
	var maximum_stretch: float = 1.60 if tip == HAND_TIP else 1.15
	var stretch := clampf(length / tip.length(), 0.70, maximum_stretch)
	limb.scale = Vector3(1, lerpf(stretch, 1.0, release), 1)


func _smooth(low: float, high: float, value: float) -> float:
	var t := clampf((value - low) / (high - low), 0, 1)
	return t * t * (3.0 - 2.0 * t)


func _euler_pose(angles: Array) -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for i in range(5):
		result.append(Quaternion(Vector3.RIGHT, angles[i * 3]) * Quaternion(Vector3.UP, angles[i * 3 + 1])
			* Quaternion(Vector3.BACK, angles[i * 3 + 2]))
	return result
