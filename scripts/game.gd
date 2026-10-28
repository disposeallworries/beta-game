extends Node3D
## The whole game runs locally; no browser, CDN, add-on, or network is required.
const PlayerScript = preload("res://scripts/player.gd")
const CourseScript = preload("res://scripts/course.gd")
const CameraScript = preload("res://scripts/follow_camera.gd")
const VisualScript = preload("res://scripts/blob_visual.gd")
const DustScript = preload("res://scripts/dust.gd")
const HudScript = preload("res://scripts/game_hud.gd")

var player: ParkourPlayer
var course: ParkourCourse
var follow_camera: ParkourCamera
var visual: BlobVisual
var dust: ParkourDust
var hud: GameHUD
var checkpoint_index: int = 0
var elapsed: float = 0.0
var started: bool = false
var finished: bool = false
var dragging: bool = false

func _ready() -> void:
	_register_controls()
	course = CourseScript.new()
	course.name = "Course"
	add_child(course)
	course.setup()
	player = PlayerScript.new()
	player.name = "Player"
	player.boxes = course.boxes
	add_child(player)
	follow_camera = CameraScript.new()
	follow_camera.name = "FollowCamera"
	follow_camera.near = 0.1
	follow_camera.far = 300
	follow_camera.fov = 60
	follow_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	follow_camera.current = true
	follow_camera.boxes = course.boxes
	add_child(follow_camera)
	visual = VisualScript.new()
	visual.name = "MintBlob"
	add_child(visual)
	visual.setup(player)
	dust = DustScript.new()
	dust.name = "Dust"
	add_child(dust)
	dust.setup()
	player.dust_requested.connect(dust.emit_dust)
	player.landed.connect(_on_landed)
	player.fell.connect(respawn)
	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup()
	respawn()
	hud.show_intro()
	follow_camera.tick(0.0, player)
	visual.tick(0.0)
	hud.update_stats(course.CHECKPOINTS[0]["name"], elapsed, 0)

func _register_controls() -> void:
	var mapping: Dictionary = {
		"move_left": [KEY_A], "move_right": [KEY_D],
		"move_forward": [KEY_W], "move_back": [KEY_S],
		"sprint": [KEY_SHIFT], "jump": [KEY_SPACE],
		"drop": [KEY_CTRL], "climb": [KEY_UP],
		"respawn": [KEY_R], "restart": [KEY_ENTER, KEY_KP_ENTER],
		"release_mouse": [KEY_ESCAPE],
	}
	for action: String in mapping:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in mapping[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("jump"):
			player.queue_jump()
		if event.is_action_pressed("respawn"):
			respawn()
		if event.is_action_pressed("restart") and finished:
			restart()
		if event.is_action_pressed("release_mouse"):
			dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.is_action_pressed("jump") or event.is_action_pressed("move_left") or event.is_action_pressed("move_right") or event.is_action_pressed("move_forward") or event.is_action_pressed("move_back"):
			started = true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if event.pressed:
			hud.dismiss_intro()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and (dragging or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		follow_camera.orbit(event.relative)

func read_controls() -> Dictionary:
	return {
		"left": Input.is_action_pressed("move_left"),
		"right": Input.is_action_pressed("move_right"),
		"forward": Input.is_action_pressed("move_forward"),
		"back": Input.is_action_pressed("move_back"),
		"sprint": Input.is_action_pressed("sprint"),
		"jump_held": Input.is_action_pressed("jump"),
		"drop": Input.is_action_pressed("drop"),
		"climb": Input.is_action_pressed("climb"),
	}

func _physics_process(dt: float) -> void:
	player.camera_yaw = follow_camera.yaw
	if started and not finished:
		elapsed += dt
	player.simulate(dt, read_controls())
	update_checkpoints()

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	visual.tick(dt)
	dust.tick(dt, player)
	follow_camera.tick(dt, player)
	course.follow_sun(player.position)
	hud.update_stats(course.CHECKPOINTS[checkpoint_index]["name"], elapsed, Vector2(player.velocity.x, player.velocity.z).length())

func update_checkpoints() -> void:
	if not player.grounded:
		return
	for i in range(checkpoint_index + 1, course.CHECKPOINTS.size()):
		var at: Vector3 = course.CHECKPOINTS[i]["position"]
		if Vector2(player.position.x - at.x, player.position.z - at.z).length() < 2.2 and absf(player.position.y - at.y) < 1.0:
			checkpoint_index = i
			if i == course.CHECKPOINTS.size() - 1:
				finished = true
				hud.show_finish(elapsed)

func respawn() -> void:
	player.respawn(course.CHECKPOINTS[checkpoint_index]["position"])
	follow_camera.idle = 9.0

func restart() -> void:
	checkpoint_index = 0
	finished = false
	elapsed = 0.0
	started = false
	respawn()
	hud.hide_message()

func _on_landed(fall_speed: float) -> void:
	follow_camera.dip = minf(0.2, fall_speed * 0.012)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
