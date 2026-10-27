class_name BlobVisual
extends Node3D
## Plays the original glTF clips and layers the HTML game's contact poses over them.
## Clip sampling is manual so the procedural hands/feet are applied after blending.

const MODEL_PATH := "res://assets/mint_blob.glb"
const CLIP_NAMES := ["idle", "walk", "run", "jump"]
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
	player.yaw = lerp_angle(player.yaw, player.yaw_target,
		1.0 - exp(-(14.0 if moving else 25.0) * dt))
	position = player.position
	rotation.y = player.yaw
	if air and not _was_air:
		_times[3] = 0.0
	_was_air = air
	var walk := clampf(speed / 5.2, 0, 1)
	var run := clampf((speed - 5.2) / 4.3, 0, 1)
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
		_times[i] = minf(_times[i] + dt * length / 0.8, length) if i == 3 else fmod(_times[i] + dt, length)
	_apply_animation(weight_sum)
	var target_pose: Array[Quaternion] = []
	if player.state == "hang":
		target_pose = _ledge_pose(0.0, player.hang_time)
	elif player.state == "climb":
		target_pose = _ledge_pose(minf(player.climb_progress, 1.0), player.hang_time)
	elif player.state == "wall":
		target_pose = _wall_pose(player.wall_time)
	elif moving and player.wall_jump_time > 0:
		target_pose = _euler_pose([-0.15, 0, 0, -2.6, 0, -0.7, -2.6, 0, 0.7, -0.9, 0, 0, 0.5, 0, 0])
	elif moving and player.drop_time > 0 and air:
		target_pose = _euler_pose([0.1, 0, 0, -0.3, 0, -1.5, -0.3, 0, 1.5, 0.3, 0, 0, -0.3, 0, 0])
	var pose_rate: float = 30.0 if player.state == "climb" and player.quick_vault else 16.0
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
			"translation": node.position = entry["value"]
			"rotation": node.quaternion = entry["value"]
			"scale": node.scale = entry["value"]


func _ik(lean: float, targets: Array[Vector3]) -> Array[Quaternion]:
	var root := Quaternion(Vector3.RIGHT, lean)
	var result: Array[Quaternion] = [root]
	for i in range(1, 5):
		var pivot: Vector3 = root * PIVOTS[i]
		var direction: Vector3 = (root.inverse() * (targets[i - 1] - pivot)).normalized()
		result.append(Quaternion(Vector3.DOWN, direction))
	return result


func _wall_pose(time: float) -> Array[Quaternion]:
	var sway := sin(time * 3.0) * 0.03
	return _ik(0, [Vector3(-0.3, 1.08 + sway, 0.32), Vector3(0.3, 1.0 - sway, 0.32),
		Vector3(-0.21, 0.1 + sway * 1.5, 0.23), Vector3(0.21, 0.16 - sway * 1.5, 0.23)])


func _ledge_pose(progress: float, time: float) -> Array[Quaternion]:
	var top: float = player.ledge["top"]
	var front: float = player.ledge_front
	var projected: float = player.position.x * player.ledge["ax"] + player.position.z * player.ledge["az"]
	var sway := sin(time * 2.4) * 0.03
	var hand_rise := _smooth(0.1, 0.3, progress)
	var release := _smooth(0.5, 0.75, progress)
	var step := _smooth(0.3, 0.55, progress)
	var neutral := _smooth(0.82, 1.0, progress)
	var targets: Array[Vector3] = []
	for side in [-1, 1]:
		targets.append(Vector3(side * 0.3, top - 0.03 * (1.0 - hand_rise) - player.position.y,
			front - 0.03 + 0.08 * hand_rise - projected).lerp(Vector3(side * 0.34, 0.25, 0.02), release))
	var foot_heights := [top - 1.0 + 0.2 * _smooth(0, 0.45, progress) + sway,
		top - 0.95 + 0.4 * _smooth(0, 0.4, progress) - sway]
	var foot_fronts := [front + 0.1, front + 0.25]
	for i in range(2):
		var side: float = -1.0 if i == 0 else 1.0
		targets.append(Vector3(side * 0.21, foot_heights[i] - player.position.y, front - 0.12 - projected)
			.lerp(Vector3(side * 0.21, top + 0.02 - player.position.y, foot_fronts[i] - projected), step)
			.lerp(Vector3(side * 0.21, -0.5, 0.03), neutral))
	return _ik(0.3 * _smooth(0.4, 0.6, progress) * (1.0 - _smooth(0.85, 1.0, progress)), targets)


func _smooth(low: float, high: float, value: float) -> float:
	var t := clampf((value - low) / (high - low), 0, 1)
	return t * t * (3.0 - 2.0 * t)


func _euler_pose(angles: Array) -> Array[Quaternion]:
	var result: Array[Quaternion] = []
	for i in range(5):
		result.append(Quaternion(Vector3.RIGHT, angles[i * 3]) * Quaternion(Vector3.UP, angles[i * 3 + 1])
			* Quaternion(Vector3.BACK, angles[i * 3 + 2]))
	return result
