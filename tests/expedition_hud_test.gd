extends SceneTree
## Native phase HUD checks: resource truth, prompts, terminal persistence and layout.
const HUD = preload("res://scripts/expedition_hud.gd")
var hud: CanvasLayer
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	hud = HUD.new()
	root.add_child(hud)
	hud.setup()
	await process_frame
	_check(hud.message_kind == "intro" and hud.message_heading.text == "THE LAST EMBER", "Intro introduces the new expedition")
	_check(hud.message_controls.text.contains("Stand still") and hud.message_footer.text.contains("3-minute"), "Intro explains gathering and fixed core lifetime")
	_check(_transparent(hud.root), "All native overlay descendants pass mouse input to the game")
	_check(not hud.crosshair.visible, "Exploration has no combat reticle")
	_check(not hud.radar.visible, "Intro keeps the field radar out of the centered explanation")
	_check(hud.message_controls.text.contains("250+") and hud.message_controls.text.contains("60 mana"), "Intro separates a recommended defense reserve from the early-entry minimum")
	hud.dismiss_intro()
	_check(not hud.message_panel.visible, "First click dismisses the intro")
	hud.update_run({"phase": "explore", "started": true, "mana": 150.5, "mana_cap": 600.0,
		"core_time": 125.0, "pools_found": 2, "pools_total": 7, "sword_level": 1, "weapon": "bolt", "location": "Broken aqueduct", "hint": "Stand still to channel: 42 mana left"})
	_check(hud.mana_bar.value == 150.5 and hud.mana_label.text == "MANA RESERVE  151 / 600", "Mana bar and count represent the carried reserve")
	_check(hud.core_label.text == "CORE LIFETIME  2:05" and hud.core_bar.value == 125.0, "Core lifetime is shown separately from mana")
	_check(hud.progress_label.text.contains("Pools 2 / 7") and hud.progress_label.text.contains("opens the rift"), "Exploration status explains collection and timer expiry")
	_check(hud.location_label.text == "Broken aqueduct" and hud.hint_label.text.contains("42 mana"), "World location and contextual harvest prompt are visible")
	_check(not hud.warning_border.visible, "Healthy exploration resources do not show a danger border")
	_check(hud.radar.visible, "Moving exploration reveals the field radar")
	hud.radar.update_data({"phase": "explore", "radar_player": Vector3(10, 0, 10), "radar_yaw": PI,
		"radar_bounds": [AABB(Vector3(5, -1, 5), Vector3(10, 1, 10))], "radar_pools": [Vector3(10, 0, -10)],
		"radar_swords": [Vector3(30, 0, 10)], "radar_portal": Vector3.ZERO, "radar_radius": 20.0})
	var map_area: Rect2 = hud.radar.map_rect()
	var player_map: Vector2 = hud.radar.world_to_map(Vector3(10, 0, 10))
	_check(player_map.is_equal_approx(map_area.get_center()), "Radar keeps the actual player at the center")
	var north: Vector2 = hud.radar.world_to_map(Vector3(10, 0, -10))
	var east: Vector2 = hud.radar.world_to_map(Vector3(30, 0, 10))
	_check(is_equal_approx(north.y, map_area.position.y) and is_equal_approx(east.x, map_area.end.x), "North is negative world Z and east is positive world X")
	var heading: PackedVector2Array = hud.radar.heading_polygon()
	_check(heading[0].y < player_map.y and is_equal_approx(heading[0].x, player_map.x), "North-facing model yaw points its radar triangle north")
	hud.radar.player_yaw = PI / 2.0
	heading = hud.radar.heading_polygon()
	_check(heading[0].x > player_map.x and is_equal_approx(heading[0].y, player_map.y), "East-facing model yaw points its radar triangle east")
	var far_point: Vector2 = hud.radar.world_to_map(Vector3(1000, 0, -1000), true)
	_check(map_area.has_point(far_point), "Distant resources remain clamped to the radar edge")
	_check(hud.radar.world_bounds.size() == 1 and hud.radar.pool_positions.size() == 1 and hud.radar.sword_positions.size() == 1, "Radar uses the actual collision bounds and available pickup positions")
	hud.update_run({"phase": "explore", "started": true, "mana": 0, "core_time": 20.0})
	_check(hud.warning_border.visible, "Low core lifetime produces a steady warning cue")
	_check(hud._core_fill.bg_color == hud.RED and hud._mana_fill.bg_color == hud.CYAN, "Exploration warns about the core while allowing zero gathered mana")
	hud.show_transition(2.4, 210.0)
	_check(hud.message_kind == "transition" and hud.message_controls.text.contains("3") and hud.message_controls.text.contains("210"), "Rift transition counts down and shows carried mana")
	hud.dismiss_intro()
	_check(hud.message_panel.visible and hud.message_kind == "transition", "An intro-dismiss input cannot erase the mandatory transition")
	_check(not hud.radar.visible, "Portal transition hides the tactical map")
	hud.hide_message()
	hud.update_run({"phase": "defend", "mana": 300, "mana_cap": 600, "tower_health": 170, "tower_max": 200,
		"wave": 2, "waves": 4, "enemies": 5, "sword_level": 1, "weapon": "sword", "location": "Ember tower"})
	_check(hud.crosshair.visible and hud._tower_section.visible and not hud._core_section.visible, "Defense replaces the exploration countdown with tower health and aiming")
	_check(hud.tower_bar.value == 170 and hud.tower_label.text == "TOWER  170 / 200", "Tower health has its own value and maximum")
	_check(hud.wave_label.text == "Wave 2 / 4  ·  5 monsters", "Wave and living monster counts are displayed")
	_check(hud.weapon_label.text.contains("RIFT BLADE I") and hud.hint_label.text.contains("free blade"), "Equipped collected sword explains its free attack")
	_check(hud.radar.visible and hud.radar.phase == "defend", "The defense HUD shows the threat radar")
	hud.radar.update_data({"phase": "defend", "radar_player": Vector3(0, 0, 7), "radar_yaw": PI,
		"radar_enemies": [Vector3(15, 0, 0), Vector3(-15, 0, 0)], "radar_radius": 28.0})
	_check(hud.radar.enemy_positions.size() == 2 and hud.radar.radius == 28.0, "Threat radar receives living monsters and the smaller arena range")
	_check(hud.radar.world_to_map(Vector3.ZERO).y < hud.radar.map_rect().get_center().y, "Central tower position remains correctly located relative to a moving player")
	hud.update_run({"phase": "defend", "mana": 15, "mana_cap": 600, "tower_health": 30, "tower_max": 200})
	_check(hud.warning_border.visible and hud._mana_fill.bg_color == hud.RED and hud._tower_fill.bg_color == hud.RED, "Low mana and tower health have independent danger cues")
	hud.show_result(false, "The tower ran out of mana.", 0, 3, 185.6)
	_check(hud.message_kind == "result" and not hud.result_won and hud.message_detail.text.contains("mana"), "Defeat clearly names the loss reason")
	_check(hud.message_footer.text.contains("Enter") and not hud.crosshair.visible, "Defeat offers a new run and removes the reticle")
	_check(not hud.radar.visible, "Run results hide the threat map")
	hud.dismiss_intro()
	_check(hud.message_panel.visible and hud.message_kind == "result", "Clicking to capture the mouse cannot hide a result card")
	hud.show_result(true, "All waves defeated.", 44, 4, 240.0)
	_check(hud.result_won and hud.message_heading.text == "THE TOWER HOLDS" and hud.message_controls.text.contains("4:00.0"), "Victory shows the actual wave/time/reserve summary")
	hud.toast("Rift blade collected", 0.5)
	_check(hud._toast_panel.visible and hud.toast_label.text.contains("blade"), "Pickup feedback is a nonblocking toast")
	hud.tick(0.3)
	_check(hud._toast_panel.visible and hud._toast_panel.modulate.a < 1.0, "Toast fades toward the end of its lifetime")
	hud.tick(0.3)
	_check(not hud._toast_panel.visible, "Expired toast hides cleanly")
	hud.root.size = Vector2(800, 600)
	hud._layout()
	await process_frame
	_check(hud._objective_panel.position.x >= 0 and hud._resource_panel.position.x + hud._resource_panel.size.x <= 801, "Header stays inside an 800-pixel-wide viewport")
	_check(hud._objective_panel.position.x + hud._objective_panel.size.x < hud._resource_panel.position.x, "Objective and resource panels do not overlap at the supported minimum width")
	_check(hud._guide_panel.position.x + hud._guide_panel.size.x < hud._hint_panel.position.x, "Context and control panels remain separate at minimum width")
	_check(is_equal_approx(hud.radar.size.x, 140.0), "Radar shrinks to a compact card at 800-pixel width")
	_check(hud.radar.position.y >= hud._resource_panel.position.y + hud._resource_panel.size.y + 10.0, "Radar sits below the measured resource panel")
	_check(hud.radar.position.y + hud.radar.size.y < hud._hint_panel.position.y, "Compact radar leaves space for bottom context prompts")
	_check(hud.format_time(0) == "0:00.0" and hud.format_time(72.3) == "1:12.3", "Run clock formats zero and elapsed time")
	hud.free()
	print("Expedition HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _transparent(node: Node) -> bool:
	if node is Control and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child: Node in node.get_children():
		if not _transparent(child):
			return false
	return true

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HUD: " + message)
