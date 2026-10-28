extends SceneTree
## Ledge flow regressions: fast follow-up, halfway assistance, momentum and safety.
## godot --headless --path . --script tests/vault_test.gd
const PlayerScript = preload("res://scripts/player.gd")
const DT: float = 1.0 / 120.0
const LEDGE := AABB(Vector3(-2, 0, -5), Vector3(4, 3, 4))
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_quick_followups()
	_test_window_and_slow_fallback()
	_test_momentum()
	_test_halfway_assist()
	_test_safety()
	_test_resets()
	print("Vault tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func _near(actual: float, expected: float, description: String, tolerance: float = 0.003) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (%.4f vs %.4f)" % [description, actual, expected])

func _player(at: Vector3 = Vector3(0, 1.9, -0.5), extra: Array[AABB] = []) -> ParkourPlayer:
	var p := PlayerScript.new()
	root.add_child(p)
	p.boxes.assign([LEDGE])
	p.boxes.append_array(extra)
	p.respawn(at)
	p.ledge_cooldown = 0.0
	return p

func _hang(speed: float = 0.0, extra: Array[AABB] = []) -> ParkourPlayer:
	var p := _player(Vector3(0, 1.9, -0.5), extra)
	p.velocity.z = -speed
	p.simulate(DT, {"forward": true})
	return p

func _ticks(p: ParkourPlayer, count: int, controls: Dictionary = {}) -> void:
	for _i in count:
		p.simulate(DT, controls)

func _finish(p: ParkourPlayer) -> Dictionary:
	var ticks: int = 0
	var clear: bool = true
	var minimum_height: float = p.position.y
	var maximum_height: float = p.position.y
	var maximum_up_step: float = 0.0
	var rises_before_crossing: bool = true
	var start: Vector3 = p.position
	while p.state == "climb" and ticks < 150:
		var previous_y: float = p.position.y
		p.simulate(DT, {})
		clear = clear and not p.blocked(p.position + Vector3.UP * 0.0001)
		minimum_height = minf(minimum_height, p.position.y)
		maximum_height = maxf(maximum_height, p.position.y)
		maximum_up_step = maxf(maximum_up_step, p.position.y - previous_y)
		if Vector2(p.position.x - start.x, p.position.z - start.z).length() > 0.002:
			rises_before_crossing = rises_before_crossing and p.position.y >= p.climb_end.y - 0.001
		ticks += 1
	return {"ticks": ticks, "clear": clear, "minimum_height": minimum_height, "maximum_height": maximum_height, "maximum_up_step": maximum_up_step, "rises_before_crossing": rises_before_crossing}

func _test_quick_followups() -> void:
	var p := _hang()
	_check(p.state == "hang", "Normal-height lip first produces a genuine hanging state")
	_ticks(p, 10)
	_check(p.state == "hang", "No follow-up input preserves the hang")
	p.simulate(DT, {"forward": true})
	_check(p.state == "climb" and p.quick_vault, "Quick forward follow-up starts the fast vault")
	_near(p.climb_duration, 0.48, "Quick follow-up uses a controlled 0.48-second pull-over")
	var result := _finish(p)
	_check(result["ticks"] >= 57 and result["ticks"] <= 59 and p.state == "move" and p.grounded, "Fast vault completes promptly on top")
	_check(result["clear"], "Fast vault never intersects the ledge while rising and crossing")
	_check(result["maximum_up_step"] < 0.05, "Fast vault lifts gradually instead of snapping upward like a launch")
	_check(result["rises_before_crossing"], "Fast vault fully clears the lip before moving onto the platform")
	_near(result["maximum_height"], 3.0, "Fast vault never rises above its standing destination")
	_near(p.position.y, 3.0, "Fast vault finishes at the top height")
	_near(-p.velocity.z, 3.12, "Low-speed fast vault exits forward at the scaled walk speed")
	_near(p.velocity.y, 0.0, "Fast vault exits grounded without upward launch velocity")
	_check(not p.quick_vault and is_zero_approx(p.ledge_entry_speed), "Completed vault clears its stored entry momentum and active flag")
	p.free()
	p = _hang()
	p.simulate(DT, {"forward": true})
	_check(p.state == "climb" and p.quick_vault, "Forward already held through a grab flows into a fast vault")
	p.free()
	p = _hang()
	p.simulate(DT, {"climb": true})
	_check(p.state == "climb" and p.quick_vault, "Quick Up follow-up also starts a fast vault")
	p.free()
	p = _hang()
	p.queue_jump()
	p.simulate(DT, {})
	_check(p.state == "climb" and p.quick_vault, "Quick Space follow-up starts a fast vault")
	p.free()

func _test_window_and_slow_fallback() -> void:
	var p := _hang()
	_ticks(p, 24)
	p.simulate(DT, {"forward": true})
	_check(p.state == "climb" and p.quick_vault, "Forward near the end of the quick-response window is accepted")
	p.free()
	p = _hang()
	_ticks(p, 30)
	p.queue_jump()
	p.simulate(DT, {})
	_check(p.state == "climb" and not p.quick_vault, "A delayed Space input retains the regular climb")
	_near(p.climb_duration, 0.95, "Regular climb keeps its original duration")
	var result := _finish(p)
	_check(result["ticks"] >= 113 and result["ticks"] <= 115, "Slow fallback actually takes the normal climb time")
	_check(p.grounded and p.velocity == Vector3.ZERO, "Regular climb still ends safely without a bonus")
	p.free()
	p = _hang()
	_ticks(p, 65)
	p.simulate(DT, {"forward": true})
	_check(p.state == "climb" and not p.quick_vault, "Forward after a long hang uses the normal climb")
	p.free()

func _test_momentum() -> void:
	var p := _player(Vector3(0, 1.9, -0.64))
	p.velocity.z = -6.0
	p.simulate(DT, {"forward": true})
	_check(p.state == "hang" and not p.hit.is_empty(), "Momentum fixture actually collides with the ledge before grabbing")
	_near(p.ledge_entry_speed, 6.0, "Vault entry speed survives a collision that zeroes forward velocity")
	p.free()
	p = _hang(6.0)
	_near(p.ledge_entry_speed, 6.0, "Grab records incoming speed before collision or hanging clears it")
	p.simulate(DT, {"forward": true})
	_finish(p)
	_near(p.velocity.length(), 6.9, "Fast vault carries 6 m/s approach plus 0.9 m/s boost")
	_check(p.velocity.z < 0 and is_zero_approx(p.velocity.y), "Boost points across the lip without an extra upward jump")
	p.free()
	p = _hang(7.8)
	p.simulate(DT, {"forward": true})
	_finish(p)
	_near(p.velocity.length(), 8.7, "Full-sprint vault gets a bounded speed boost")
	p.free()
	p = _hang(30.0)
	p.simulate(DT, {"forward": true})
	_finish(p)
	_check(p.velocity.length() <= 8.701, "Extreme approach speed cannot create an unbounded vault boost")
	p.free()
	p = _hang()
	p.sprint_time = 2.5
	p.simulate(DT, {"forward": true, "sprint": true})
	_finish(p)
	_near(p.sprint_time, 2.5, "Vault preserves accumulated sprint buildup")
	p.free()

func _test_halfway_assist() -> void:
	var p := _player(Vector3(0, 2.5, -0.5))
	var start_y: float = p.position.y
	p.simulate(DT, {"forward": true})
	_check(p.state == "climb" and p.quick_vault and p.assisted_vault, "Body already halfway above a lip clears automatically with assist metadata")
	_near(p.climb_duration, 0.32, "Halfway assistance uses a controlled 0.32-second pull-over")
	_check(p.position.y >= start_y - 0.003, "Halfway assistance does not snap the player down to hanging height")
	var result := _finish(p)
	_check(result["minimum_height"] >= start_y - 0.003 and result["clear"], "Assisted path rises cleanly without sinking into the lip")
	_check(result["maximum_up_step"] < 0.04 and result["rises_before_crossing"], "Assisted climb lifts gradually and clears the lip before crossing")
	_near(result["maximum_height"], 3.0, "Assisted climb has no floating arc above the platform")
	_check(result["ticks"] >= 38 and result["ticks"] <= 40 and p.grounded, "Halfway assist lands on top promptly")
	_near(-p.velocity.z, 3.12, "Low-speed halfway assistance exits forward at the scaled walk speed")
	_near(p.velocity.y, 0.0, "Assisted climb ends standing without upward launch velocity")
	p.free()
	p = _player(Vector3(0, 2.5, -0.5))
	p.velocity = Vector3(0, 7, -8)
	p.simulate(DT, {"forward": true})
	_check(p.state == "climb" and p.quick_vault, "Halfway assistance works while the jump is still rising quickly")
	p.free()
	p = _player(Vector3(0, 2.5, -0.5))
	p.velocity.z = -8
	p.simulate(DT, {})
	_check(p.state == "climb" and p.quick_vault, "Forward air momentum can clear a halfway-height lip without fresh input")
	p.free()
	p = _player(Vector3(0, 2.5, -0.64))
	p.velocity.z = -8
	p.simulate(DT, {})
	_check(not p.hit.is_empty() and p.state == "climb" and p.quick_vault, "No-input momentum still assists after actual wall contact clears forward velocity")
	_near(p.ledge_entry_speed, 8.0, "Momentum-only halfway assist remembers the speed from before contact")
	p.free()
	p = _player(Vector3(0, 2.414, -0.5))
	p.simulate(DT, {"forward": true})
	_check(p.state != "climb", "A lip above the halfway threshold is not automatically cleared")
	p.free()
	p = _player(Vector3(0, 2.5, -0.5))
	p.simulate(DT, {})
	_check(p.state != "climb", "Standing still in midair does not trigger a vault")
	p.free()
	p = _player(Vector3(0, 2.5, -0.5))
	p.velocity.z = 8
	p.simulate(DT, {})
	_check(p.state != "climb", "Moving away from a ledge does not trigger assistance")
	p.free()

func _test_safety() -> void:
	var p := _player(Vector3(0, 2.5, -0.5))
	p.simulate(DT, {"forward": true, "drop": true})
	_check(p.state != "climb", "Ctrl takes priority over halfway assistance")
	p.free()
	p = _player(Vector3(0, 2.5, -0.5))
	p.ledge_cooldown = 0.3
	p.simulate(DT, {"forward": true})
	_check(p.state != "climb", "Respawn/drop cooldown prevents automatic re-vaulting")
	p.free()
	var landing_ceiling := AABB(Vector3(-1, 3.7, -2), Vector3(2, 1, 1))
	p = _hang(8.0, [landing_ceiling])
	p.simulate(DT, {"forward": true})
	_check(p.state == "hang", "Fast follow-up refuses an occupied standing destination")
	p.free()
	p = _player(Vector3(0, 2.5, -0.5), [landing_ceiling])
	p.simulate(DT, {"forward": true})
	_check(p.state != "climb", "Halfway assist refuses an occupied standing destination")
	p.free()
	# The endpoint is clear, but this low ceiling covers the upward part of the path.
	var rise_ceiling := AABB(Vector3(-1, 3.15, -0.95), Vector3(2, 0.2, 0.75))
	p = _hang(8.0, [rise_ceiling])
	p.simulate(DT, {"forward": true})
	_check(p.state == "hang", "Vault checks the whole rise path instead of only its endpoint")
	p.free()
	p = _hang(6.0)
	p.simulate(DT, {"forward": true})
	# A newly inserted blocker must not be tunneled through mid-vault.
	p.boxes.append(landing_ceiling)
	var safe: bool = true
	for _i in 40:
		p.simulate(DT, {})
		safe = safe and not p.blocked(p.position + Vector3.UP * 0.0001)
	_check(safe, "A blocker appearing during a vault cannot be crossed or penetrated")
	p.free()

func _test_resets() -> void:
	var p := _hang(6.0)
	p.simulate(DT, {"drop": true})
	_check(p.state == "move" and not p.quick_vault and is_zero_approx(p.ledge_entry_speed), "Dropping clears stored vault momentum")
	p.free()
	p = _hang(6.0)
	p.simulate(DT, {"forward": true})
	p.respawn(Vector3(2, 7, 1))
	_check(p.state == "move" and not p.quick_vault and not p.assisted_vault and is_zero_approx(p.ledge_entry_speed), "Respawn clears active vault flags and saved entry speed")
	_near(p.climb_duration, 0.95, "Respawn restores regular climb timing")
	_check(p.velocity == Vector3.ZERO and p.position == Vector3(2, 7, 1), "Respawn cannot carry a pending vault boost into the checkpoint")
	p.free()
