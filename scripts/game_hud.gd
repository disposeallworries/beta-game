extends CanvasLayer
class_name GameHUD
## Native overlay matching the source game's three translucent HTML panels.

var checkpoint_label: Label
var timer_label: Label
var speed_label: Label
var message_panel: PanelContainer
var message_heading: Label
var message_detail: Label
var message_kind: String = ""
var root: Control
var ink: Color = Color("22313a")
var panel_color: Color = Color(1.0, 1.0, 1.0, 0.8)
var bold_font: FontVariation


func setup() -> void:
	if is_instance_valid(root):
		return
	layer = 10
	if DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode():
		ink = Color("e8f1f3")
		panel_color = Color(0.078, 0.118, 0.141, 0.78)
	bold_font = FontVariation.new()
	bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 0.7
	root = Control.new()
	root.name = "Overlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var stats: PanelContainer = _panel()
	stats.name = "Stats"
	stats.position = Vector2(12, 12)
	root.add_child(stats)
	var stats_rows: VBoxContainer = VBoxContainer.new()
	stats_rows.add_theme_constant_override("separation", 1)
	stats.add_child(stats_rows)
	checkpoint_label = _label("Start", 16, true)
	stats_rows.add_child(checkpoint_label)
	timer_label = _label("0:00.0", 14)
	stats_rows.add_child(timer_label)
	var speed_row: HBoxContainer = HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	stats_rows.add_child(speed_row)
	speed_label = _label("0.0", 16, true)
	speed_row.add_child(speed_label)
	var units: Label = _label("m/s", 14)
	units.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_row.add_child(units)

	var guide_anchor: MarginContainer = MarginContainer.new()
	guide_anchor.name = "ControlsAnchor"
	guide_anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guide_anchor.add_theme_constant_override("margin_left", 12)
	guide_anchor.add_theme_constant_override("margin_right", 12)
	guide_anchor.add_theme_constant_override("margin_bottom", 12)
	root.add_child(guide_anchor)
	var guide: PanelContainer = _panel()
	guide.name = "Controls"
	guide.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	guide.size_flags_vertical = Control.SIZE_SHRINK_END
	guide_anchor.add_child(guide)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	guide.add_child(grid)
	var controls: Array[Array] = [
		["WASD", "Move; hold W to vault ledges"],
		["Shift", "Sprint"],
		["Space", "Jump, wall jump, climb up"],
		["S / Ctrl", "Let go of a ledge or wall"],
		["Mouse", "Camera (click to capture)"],
		["R", "Back to checkpoint"],
	]
	for row: Array in controls:
		var key_label: Label = _label(str(row[0]), 14, true)
		key_label.add_theme_color_override("font_color", Color("e4604a"))
		grid.add_child(key_label)
		grid.add_child(_label(str(row[1]), 14))

	var center: CenterContainer = CenterContainer.new()
	center.name = "MessageCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	message_panel = _panel(28, 18)
	message_panel.name = "Message"
	center.add_child(message_panel)
	var message_rows: VBoxContainer = VBoxContainer.new()
	message_rows.add_theme_constant_override("separation", 3)
	message_panel.add_child(message_rows)
	message_heading = _label("", 20)
	message_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_rows.add_child(message_heading)
	message_detail = _label("", 14)
	message_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_rows.add_child(message_detail)
	_ignore_mouse(root)
	show_intro()


func update_stats(checkpoint_name: String, elapsed: float, speed: float) -> void:
	checkpoint_label.text = checkpoint_name
	timer_label.text = format_time(elapsed)
	speed_label.text = "%.1f" % speed


func show_intro() -> void:
	message_kind = "intro"
	message_heading.text = "Click to play"
	message_detail.text = "Reach the gold platform"
	message_panel.show()


func dismiss_intro() -> void:
	if message_kind == "intro":
		hide_message()


func show_finish(elapsed: float) -> void:
	message_kind = "finish"
	message_heading.text = "Course complete in " + format_time(elapsed)
	message_detail.text = "Press Enter to run it again"
	message_panel.show()


func hide_message() -> void:
	message_kind = ""
	message_panel.hide()


func set_captured(captured: bool) -> void:
	if captured:
		dismiss_intro()


static func format_time(elapsed: float) -> String:
	var minutes: int = int(floor(elapsed / 60.0))
	var seconds: float = fmod(elapsed, 60.0)
	return "%d:%04.1f" % [minutes, seconds]


func _label(text: String, font_size: int, bold: bool = false) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	if bold:
		label.add_theme_font_override("font", bold_font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel(horizontal_padding: int = 14, vertical_padding: int = 10) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.set_corner_radius_all(10)
	style.content_margin_left = horizontal_padding
	style.content_margin_right = horizontal_padding
	style.content_margin_top = vertical_padding
	style.content_margin_bottom = vertical_padding
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore_mouse(child)
