extends CanvasLayer
class_name ExpeditionHUD
## Readable, mouse-transparent status for the gathering and tower-defense phases.

const INK := Color("e8eef2")
const MUTED := Color("a9bac7")
const CYAN := Color("65d8e8")
const GOLD := Color("e9bd78")
const RED := Color("ed7d79")
const PANEL := Color(0.026, 0.043, 0.061, 0.90)
const RadarScript = preload("res://scripts/expedition_radar.gd")

var root: Control
var phase_label: Label
var objective_label: Label
var location_label: Label
var progress_label: Label
var mana_label: Label
var mana_bar: ProgressBar
var core_label: Label
var core_bar: ProgressBar
var tower_label: Label
var tower_bar: ProgressBar
var wave_label: Label
var weapon_label: Label
var hint_label: Label
var crosshair: Label
var message_panel: PanelContainer
var message_heading: Label
var message_detail: Label
var message_controls: Label
var message_footer: Label
var message_kind: String = ""
var result_won: bool = false
var toast_label: Label
var warning_border: Panel
var radar: Control

var _objective_panel: PanelContainer
var _resource_panel: PanelContainer
var _guide_panel: PanelContainer
var _hint_panel: PanelContainer
var _toast_panel: PanelContainer
var _message_center: CenterContainer
var _veil: ColorRect
var _core_section: VBoxContainer
var _tower_section: VBoxContainer
var _mana_fill: StyleBoxFlat
var _core_fill: StyleBoxFlat
var _tower_fill: StyleBoxFlat
var _resource_style: StyleBoxFlat
var _toast_time: float = 0.0
var _entered_defense: bool = false
var _phase: String = "explore"
var _run_started: bool = false
var _bold_font: FontVariation


func setup() -> void:
	if is_instance_valid(root):
		return
	layer = 20
	_bold_font = FontVariation.new()
	_bold_font.base_font = ThemeDB.fallback_font
	_bold_font.variation_embolden = 0.6
	root = Control.new()
	root.name = "ExpeditionOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.resized.connect(_layout)
	_build_objective()
	_build_resources()
	_build_radar()
	_build_guide()
	_build_context()
	_build_message()
	_build_warning()
	_ignore_mouse(root)
	_layout()
	update_run({"phase": "explore", "mana": 0.0, "mana_cap": 600.0,
		"core_time": 180.0, "pools_total": 7, "location": "Mana sanctuary"})
	show_intro()


func _build_objective() -> void:
	_objective_panel = _panel()
	_objective_panel.name = "Objective"
	root.add_child(_objective_panel)
	var rows := _rows(4)
	_objective_panel.add_child(rows)
	phase_label = _label("PHASE I  ·  GATHER", 13, GOLD, true)
	rows.add_child(phase_label)
	objective_label = _label("Gather mana. Find your blade.", 19, INK, true)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(objective_label)
	location_label = _label("Mana sanctuary", 14, MUTED)
	rows.add_child(location_label)
	progress_label = _label("Pools 0 / 7  ·  Move to begin", 13, MUTED)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(progress_label)


func _build_resources() -> void:
	_resource_panel = _panel()
	_resource_panel.name = "Resources"
	_resource_style = _resource_panel.get_theme_stylebox("panel") as StyleBoxFlat
	root.add_child(_resource_panel)
	_resource_panel.resized.connect(_layout_radar)
	var rows := _rows(5)
	_resource_panel.add_child(rows)
	mana_label = _label("MANA RESERVE  0 / 600", 14, CYAN, true)
	rows.add_child(mana_label)
	mana_bar = _bar(CYAN)
	_mana_fill = mana_bar.get_theme_stylebox("fill") as StyleBoxFlat
	rows.add_child(mana_bar)
	_core_section = _rows(3)
	rows.add_child(_core_section)
	core_label = _label("CORE LIFETIME  3:00", 14, GOLD, true)
	_core_section.add_child(core_label)
	core_bar = _bar(GOLD)
	_core_fill = core_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_core_section.add_child(core_bar)
	_tower_section = _rows(3)
	rows.add_child(_tower_section)
	tower_label = _label("TOWER  200 / 200", 14, RED, true)
	_tower_section.add_child(tower_label)
	tower_bar = _bar(RED)
	_tower_fill = tower_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_tower_section.add_child(tower_bar)
	wave_label = _label("Wave 0 / 4", 13, MUTED)
	# The tower section starts hidden. Seed a width before its first wrap pass
	# so it cannot cache a one-character-wide, excessively tall minimum size.
	wave_label.custom_minimum_size.x = 220
	wave_label.size.x = 220
	wave_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tower_section.add_child(wave_label)
	weapon_label = _label("MANA BOLT · 8 mana   /   Find a sword", 13, MUTED)
	weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(weapon_label)


func _build_radar() -> void:
	radar = RadarScript.new()
	radar.name = "TacticalRadar"
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(radar)
	radar.hide()


func _build_guide() -> void:
	_guide_panel = _panel()
	_guide_panel.name = "Controls"
	root.add_child(_guide_panel)
	var guide := _label("WASD  Move       Shift  Sprint\nSpace  Jump / wall jump / vault\nCtrl / S  Drop       R  Return (mana cost)\nE  Portal       Esc  Pause / mouse\nLMB  Attack       RMB  Blade       Q  Switch", 13, MUTED)
	_guide_panel.add_child(guide)


func _build_context() -> void:
	_hint_panel = _panel()
	_hint_panel.name = "Context"
	root.add_child(_hint_panel)
	hint_label = _label("Stand still in a glowing pool to gather mana.", 15, INK)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_panel.add_child(hint_label)
	crosshair = _label("+", 25, Color(0.80, 0.95, 1.0, 0.88))
	crosshair.name = "Reticle"
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(crosshair)
	_toast_panel = _panel(16, 9)
	_toast_panel.name = "Toast"
	root.add_child(_toast_panel)
	toast_label = _label("", 15, GOLD)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(toast_label)
	_toast_panel.hide()


func _build_message() -> void:
	_veil = ColorRect.new()
	_veil.name = "PhaseVeil"
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(0.006, 0.012, 0.025, 0.36)
	root.add_child(_veil)
	_message_center = CenterContainer.new()
	_message_center.name = "MessageCenter"
	_message_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_message_center)
	message_panel = _panel(28, 22)
	message_panel.name = "Message"
	_message_center.add_child(message_panel)
	var rows := _rows(10)
	message_panel.add_child(rows)
	message_heading = _label("", 27, GOLD, true)
	message_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(message_heading)
	message_detail = _label("", 17, INK)
	message_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(message_detail)
	message_controls = _label("", 14, MUTED)
	message_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(message_controls)
	message_footer = _label("", 14, CYAN, true)
	message_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(message_footer)


func _build_warning() -> void:
	warning_border = Panel.new()
	warning_border.name = "LowResourceBorder"
	warning_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.75, 0.18, 0.16, 0.7)
	style.set_border_width_all(2)
	warning_border.add_theme_stylebox_override("panel", style)
	root.add_child(warning_border)
	warning_border.hide()


func update_run(data: Dictionary) -> void:
	if not is_instance_valid(root):
		return
	_phase = str(data.get("phase", "explore"))
	_run_started = bool(data.get("started", _phase == "defend"))
	radar.update_data(data)
	if _phase == "defend":
		_entered_defense = true
	elif _phase == "explore":
		_entered_defense = false
	var terminal: bool = _phase in ["won", "lost"]
	var defending: bool = _phase == "defend" or (terminal and _entered_defense)
	var mana: float = maxf(float(data.get("mana", 0.0)), 0.0)
	var mana_cap: float = maxf(float(data.get("mana_cap", 600.0)), 1.0)
	var core_time: float = maxf(float(data.get("core_time", 180.0)), 0.0)
	var tower: float = maxf(float(data.get("tower_health", 200.0)), 0.0)
	var tower_max: float = maxf(float(data.get("tower_max", 200.0)), 1.0)
	var sword: int = int(data.get("sword_level", 0))
	var selected: String = str(data.get("weapon", "bolt"))
	mana_label.text = "MANA RESERVE  %d / %d" % [int(ceil(mana)), int(mana_cap)]
	mana_bar.max_value = mana_cap
	mana_bar.value = mana
	core_label.text = "CORE LIFETIME  " + _clock(core_time)
	core_bar.max_value = 180.0
	core_bar.value = core_time
	tower_label.text = "TOWER  %d / %d" % [int(ceil(tower)), int(tower_max)]
	tower_bar.max_value = tower_max
	tower_bar.value = tower
	_core_section.visible = not defending
	_tower_section.visible = defending
	wave_label.text = "Wave %d / %d  ·  %d monsters" % [int(data.get("wave", 0)), int(data.get("waves", 4)), int(data.get("enemies", 0))]
	if defending and not terminal and int(data.get("enemies", 0)) == 0:
		var wait: int = maxi(ceili(float(data.get("wave_wait", 0.0))), 0)
		wave_label.text += "  ·  Incoming in %ds" % wait
	location_label.text = str(data.get("location", "Mana sanctuary"))
	if _phase == "explore":
		phase_label.text = "PHASE I  ·  GATHER"
		objective_label.text = "Gather mana. Find your blade."
		var timing: String = "Core expiry opens the rift" if data.get("started", false) else "Move to begin"
		progress_label.text = "Pools %d / %d  ·  %s" % [int(data.get("pools_found", 0)), int(data.get("pools_total", 7)), timing]
	elif _phase == "transition":
		phase_label.text = "THE RIFT IS OPEN"
		objective_label.text = "Carry your mana into the defense."
		progress_label.text = "Your gathered mana powers the tower."
	elif _phase == "defend":
		phase_label.text = "PHASE II  ·  DEFEND"
		objective_label.text = "Protect the tower. Guard your mana."
		progress_label.text = "Core upkeep and tower shots use mana. Empty reserve ends the run."
	elif _phase == "won":
		phase_label.text = "EXPEDITION COMPLETE"
		objective_label.text = "The tower still burns."
		progress_label.text = "Run time " + format_time(float(data.get("elapsed", 0.0)))
	else:
		phase_label.text = "CORE EXTINGUISHED"
		objective_label.text = "Begin another expedition."
		progress_label.text = "Run time " + format_time(float(data.get("elapsed", 0.0)))
	if selected == "sword" and sword > 0:
		weapon_label.text = "RIFT BLADE %s · Free swing · Q for bolt" % ["II" if sword > 1 else "I"]
	elif sword > 0:
		weapon_label.text = "MANA BOLT · 8 mana · Q for blade"
	else:
		weapon_label.text = "MANA BOLT · 8 mana  /  Sword not found"
	var default_hint: String = "Stand still in a glowing pool to gather mana."
	if _phase == "defend":
		default_hint = "LMB/RMB: free blade swing. Q: mana bolt (8 mana)." if selected == "sword" and sword > 0 else "LMB: mana bolt (8 mana). RMB: free blade swing if collected."
	if _phase == "transition":
		default_hint = "Entering another area. Your mana and sword travel with you."
	hint_label.text = str(data.get("hint", default_hint))
	_hint_panel.visible = not terminal and _phase != "transition"
	crosshair.visible = _phase == "defend" and message_kind != "result"
	var mana_low: bool = defending and mana / mana_cap < 0.2
	var core_low: bool = _phase == "explore" and data.get("started", false) and core_time / 180.0 < 0.2
	var tower_low: bool = defending and tower / tower_max < 0.2
	_mana_fill.bg_color = RED if mana_low else CYAN
	_core_fill.bg_color = RED if core_low else GOLD
	_tower_fill.bg_color = RED if tower_low else Color("d78c82")
	_resource_style.border_color = RED.darkened(0.35) if mana_low or core_low or tower_low else Color("355061")
	warning_border.visible = not terminal and (mana_low or core_low or tower_low)
	_sync_radar_visibility()
	_layout()


func show_intro() -> void:
	_entered_defense = false
	message_kind = "intro"
	message_heading.text = "THE LAST EMBER"
	message_heading.add_theme_color_override("font_color", GOLD)
	message_detail.text = "Gather mana before your core fades.\nCross the rift. Defend your tower."
	message_controls.text = "Stand still in glowing pools to charge.\n250+ mana and a blade is a solid start.\nE at the portal enters early once you have 60 mana."
	message_footer.text = "Move to begin the 3-minute core countdown · Click to capture mouse"
	_show_message(0.36)


func dismiss_intro() -> void:
	if message_kind == "intro":
		hide_message()


func show_transition(time_left: float, mana: float) -> void:
	message_kind = "transition"
	message_heading.text = "ENTERING THE RIFT"
	message_heading.add_theme_color_override("font_color", CYAN)
	message_detail.text = "Core fading — the tower is calling."
	message_controls.text = "%d  ·  Mana carried: %d" % [maxi(int(ceil(time_left)), 0), int(ceil(maxf(mana, 0.0)))]
	message_footer.text = "Your mana and collected sword will travel with you."
	_show_message(0.75)


func show_result(won: bool, reason: String, mana: float, waves: int, elapsed: float) -> void:
	message_kind = "result"
	result_won = won
	message_heading.text = "THE TOWER HOLDS" if won else "THE EMBER FADES"
	message_heading.add_theme_color_override("font_color", GOLD if won else RED)
	message_detail.text = reason
	message_controls.text = "Wave %d  ·  Mana remaining %d  ·  Run %s" % [waves, int(ceil(maxf(mana, 0.0))), format_time(elapsed)]
	message_footer.text = "Press Enter to begin a new expedition"
	crosshair.hide()
	warning_border.hide()
	_show_message(0.68)


func hide_message() -> void:
	message_kind = ""
	message_panel.hide()
	_veil.hide()
	_sync_radar_visibility()


func toast(text: String, seconds: float = 2.0) -> void:
	toast_label.text = text
	_toast_time = maxf(seconds, 0.1)
	_toast_panel.modulate.a = 1.0
	_toast_panel.show()
	_layout()


func tick(dt: float) -> void:
	if _toast_time > 0.0:
		_toast_time = maxf(_toast_time - dt, 0.0)
		_toast_panel.modulate.a = minf(_toast_time / 0.3, 1.0)
		if _toast_time <= 0.0:
			_toast_panel.hide()


static func format_time(elapsed: float) -> String:
	var value: float = maxf(elapsed, 0.0)
	return "%d:%04.1f" % [int(floor(value / 60.0)), fmod(value, 60.0)]


func _clock(value: float) -> String:
	var seconds: int = maxi(int(ceil(value)), 0)
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _show_message(opacity: float) -> void:
	_veil.color.a = opacity
	_veil.show()
	message_panel.show()
	_sync_radar_visibility()
	_layout()


func _sync_radar_visibility() -> void:
	if not is_instance_valid(radar):
		return
	radar.visible = (_phase == "defend" or (_phase == "explore" and _run_started)) and message_kind not in ["intro", "transition", "result"]


func _layout() -> void:
	if not is_instance_valid(_objective_panel) or not is_instance_valid(message_panel):
		return
	var view: Vector2 = root.size
	if view.x <= 1.0:
		view = get_viewport().get_visible_rect().size
	var objective_width: float = clampf(view.x * 0.43, 300.0, 520.0)
	var resource_width: float = clampf(view.x * 0.30, 280.0, 360.0)
	_objective_panel.position = Vector2(20, 16)
	_objective_panel.size = Vector2(objective_width, 0)
	_resource_panel.position = Vector2(view.x - resource_width - 20.0, 16)
	_resource_panel.size = Vector2(resource_width, 0)
	_layout_radar()
	var guide_width: float = clampf(view.x * 0.35, 315.0, 390.0)
	_guide_panel.position = Vector2(20, view.y - 144)
	_guide_panel.size = Vector2(guide_width, 124)
	var hint_width: float = clampf(view.x * 0.44, 340.0, 560.0)
	_hint_panel.position = Vector2(view.x - hint_width - 20.0, view.y - 100.0)
	_hint_panel.size = Vector2(hint_width, 80)
	crosshair.position = view * 0.5 - Vector2(16, 18)
	crosshair.size = Vector2(32, 36)
	var toast_width: float = minf(560.0, view.x - 64.0)
	var toast_x: float = (view.x - toast_width) * 0.5
	if view.x < 1000:
		toast_x = maxf(20.0, (radar.position.x - toast_width) * 0.5)
	_toast_panel.position = Vector2(toast_x, 176)
	_toast_panel.size = Vector2(toast_width, 0)
	message_panel.custom_minimum_size.x = minf(600.0, view.x - 64.0)
	message_panel.size.x = message_panel.custom_minimum_size.x


func _layout_radar() -> void:
	# Text wrapping can change the resource height after container layout runs.
	# This callback only repositions the map, never resizes its resource sibling.
	if not is_instance_valid(radar) or not is_instance_valid(root):
		return
	var view: Vector2 = root.size
	if view.x <= 1.0:
		view = get_viewport().get_visible_rect().size
	var edge: float = 140.0 if view.x < 1000 else 176.0
	var resource_height: float = maxf(_resource_panel.size.y, _resource_panel.get_combined_minimum_size().y)
	radar.position = Vector2(view.x - edge - 20.0, _resource_panel.position.y + resource_height + 12.0)
	radar.size = Vector2(edge, edge + 34.0)


func _rows(spacing: int) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", spacing)
	return rows


func _label(text: String, font_size: int, color: Color = INK, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _bold_font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel(horizontal: int = 16, vertical: int = 12) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = Color("355061")
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 8
	bar.show_percentage = false
	bar.max_value = 100
	var background := StyleBoxFlat.new()
	background.bg_color = Color("111f2a")
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore_mouse(child)
