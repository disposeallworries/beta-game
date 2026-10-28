extends SceneTree
## Resource/phase coverage without bypassing run rules or loading scene visuals.
const StateScript = preload("res://scripts/run_state.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_start_and_core()
	_test_harvest_and_inventory()
	_test_portal_and_defense()
	_test_spending_and_failures()
	_test_results_and_reset()
	_test_timestep_equivalence()
	print("Run state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _new_state() -> StateScript:
	var state := StateScript.new()
	root.add_child(state)
	return state


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUN STATE: " + message)


func _near(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	_check(absf(actual - expected) < tolerance, "%s (%.5f vs %.5f)" % [message, actual, expected])


func _test_start_and_core() -> void:
	var state := _new_state()
	_check(state.phase == "explore" and not state.started, "First phase waits for player input")
	_near(state.mana, 0.0, "Mana must be collected, not granted")
	_near(state.core_time, 180.0, "Core starts with three minutes")
	state.tick(20.0)
	_near(state.core_time, 180.0, "Reading intro does not consume the core")
	_near(state.elapsed, 0.0, "Idle intro does not start elapsed clock")
	state.start()
	state.tick(12.5)
	_near(state.core_time, 167.5, "Moving starts core countdown")
	_near(state.elapsed, 12.5, "Elapsed time tracks active run")
	state.start()
	_near(state.core_time, 167.5, "Repeated start does not refill the core")
	state.tick(-100.0)
	state.tick(INF)
	_near(state.core_time, 167.5, "Invalid time cannot refill or corrupt core")
	state.tick(167.5)
	_check(state.phase == "transition", "Expiring core forces portal transition")
	_near(state.core_time, 0.0, "Core clamps at zero")
	_near(state.transition_time, 3.0, "Forced transfer has visible three-second countdown")
	state.tick(3.0)
	_check(state.phase == "lost" and state.loss_reason.contains("without any mana"), "Unprepared forced transfer loses with a concrete reason")
	state.free()


func _test_harvest_and_inventory() -> void:
	var state := _new_state()
	var changes: Array[float] = []
	state.mana_changed.connect(func(value: float) -> void: changes.append(value))
	_near(state.add_mana(42.0), 42.0, "Harvest returns the mana actually accepted")
	_near(state.total_collected, 42.0, "Accepted harvest counts toward run result")
	_near(state.add_mana(600.0), 558.0, "Near-full reserve accepts only remaining capacity")
	_near(state.mana, 600.0, "Reserve caps at 600")
	_near(state.add_mana(50.0), 0.0, "Full reserve leaves the pool's unused mana available")
	_near(state.total_collected, 600.0, "Overflow does not inflate harvested total")
	_check(changes.size() == 2 and changes[0] == 42.0 and changes[1] == 600.0, "Only accepted changes notify HUD")
	_near(state.add_mana(-100.0), 0.0, "Negative harvest cannot subtract mana")
	_near(state.add_mana(INF), 0.0, "Non-finite harvest cannot corrupt the reserve")
	state.record_pool(2)
	state.record_pool(2)
	state.record_pool(5)
	state.record_pool(-1)
	_check(state.pools_visited.size() == 2 and state.pools_visited.has(2), "Visited pools count uniquely")
	_check(state.sword_level == 0, "No free sword before a pickup")
	_check(state.collect_sword(1) and state.sword_level == 1, "Finding first sword unlocks melee")
	_check(not state.collect_sword(1), "Duplicate sword does not stack arbitrary damage")
	_check(state.collect_sword(2) and state.sword_level == 2, "Stronger map pickup upgrades sword")
	_check(not state.collect_sword(1) and state.sword_level == 2, "Later weak sword cannot downgrade inventory")
	_check(not state.collect_sword(99) and state.sword_level == 2, "Sword level stays within implemented equipment tiers")
	state.free()


func _test_portal_and_defense() -> void:
	var state := _new_state()
	var phases: Array[String] = []
	state.phase_changed.connect(func(value: String) -> void: phases.append(value))
	_check(not state.request_portal(), "Empty core cannot voluntarily enter defense")
	state.add_mana(59.0)
	_check(not state.request_portal(), "Portal minimum is meaningful")
	state.add_mana(1.0)
	state.collect_sword(2)
	state.record_pool(1)
	_check(state.request_portal(), "Exactly 60 mana unlocks voluntary portal")
	_check(state.phase == "transition" and state.started, "Portal request begins timed transfer")
	_near(state.mana, 60.0, "Entering portal does not consume prepared reserve")
	_check(not state.request_portal(true), "Repeated portal input cannot restart countdown")
	state.tick(2.5)
	_check(state.phase == "transition", "Arena does not begin before transfer completes")
	_near(state.transition_time, 0.5, "Transition ticks independently of core timer")
	state.tick(0.5)
	_check(state.phase == "defend", "Transfer enters actual defense phase")
	_check(state.sword_level == 2 and state.pools_visited.has(1), "Equipment and gathering progress survive portal")
	_check(phases == ["transition", "defend"], "Phase notifications report ordered transition once each")
	state.tick(10.0)
	_near(state.mana, 54.0, "Defending consumes reserve at 0.6 mana per second")
	_near(state.core_time, 180.0, "Exploration core countdown no longer runs in defense")
	_near(state.elapsed, 13.0, "Elapsed timer includes portal and defense")
	state.complete_transition()
	_check(state.phase == "defend", "Calling completed transfer again cannot reset defense")
	state.free()


func _test_spending_and_failures() -> void:
	var state := _new_state()
	state.add_mana(120.0)
	_check(not state.spend_mana(121.0), "Unaffordable attack is rejected")
	_near(state.mana, 120.0, "Failed attack does not consume partial reserve")
	_check(not state.spend_mana(-1.0) and not state.spend_mana(INF), "Invalid costs cannot manufacture mana")
	_check(state.spend_mana(0.0), "Free sword action can carry a zero mana cost")
	_check(state.spend_mana(8.0), "Affordable spell spends mana")
	_near(state.mana, 112.0, "Spell cost subtracts exactly once")
	_near(state.drain_mana(200.0), 112.0, "Fall penalty drains only available balance")
	_check(state.phase == "explore" and is_zero_approx(state.mana), "Exploration can recover at pools from empty reserve")
	state.add_mana(10.0)
	state.request_portal(true)
	state.complete_transition()
	_check(state.phase == "defend", "Forced transition permits small prepared reserve")
	_check(state.spend_mana(10.0), "Spending last mana is an actual paid action")
	_check(state.phase == "lost" and state.loss_reason.contains("empty"), "Spending last defense mana loses immediately")
	_near(state.mana, 0.0, "Defeated reserve never becomes negative")
	state.free()
	state = _new_state()
	state.add_mana(0.3)
	state.request_portal(true)
	state.complete_transition()
	state.tick(1.0)
	_check(state.phase == "lost", "Passive drain can exhaust core without attack input")
	_near(state.elapsed, 0.5, "Run clock stops at the actual moment mana runs out")
	state.free()


func _test_results_and_reset() -> void:
	var state := _new_state()
	var ends: Array[Dictionary] = []
	state.run_ended.connect(func(won: bool, reason: String) -> void: ends.append({"won": won, "reason": reason}))
	state.win()
	_check(state.phase == "explore", "Victory cannot occur before defense")
	state.add_mana(250.0)
	state.collect_sword(2)
	state.record_pool(3)
	state.start()
	state.tick(12.0)
	state.request_portal()
	state.complete_transition()
	state.win()
	_check(state.phase == "won" and ends.size() == 1 and ends[0]["won"], "Winning emits one successful result")
	var frozen_time: float = state.elapsed
	var frozen_mana: float = state.mana
	state.tick(500.0)
	state.add_mana(20.0)
	state.drain_mana(20.0)
	state.lose("late damage")
	state.win()
	_near(state.elapsed, frozen_time, "Won runs stop ticking")
	_near(state.mana, frozen_mana, "Terminal results freeze resources")
	_check(ends.size() == 1 and state.phase == "won", "Late damage cannot overwrite win or duplicate result")
	state.reset()
	_check(state.phase == "explore" and not state.started and is_zero_approx(state.mana), "Restart returns to unstarted exploration")
	_check(state.sword_level == 0 and state.pools_visited.is_empty(), "Restart clears equipment and pool history")
	_check(state.loss_reason.is_empty() and is_zero_approx(state.total_collected) and is_zero_approx(state.elapsed), "Restart clears prior result metadata")
	_near(state.core_time, 180.0, "Restart restores full core lifetime")
	_near(state.transition_time, 0.0, "Restart cancels any portal countdown")
	state.lose("The tower was destroyed.")
	_check(ends.size() == 2 and not ends[1]["won"] and state.loss_reason.contains("tower"), "Tower failure can end the run with its own reason")
	state.free()


func _test_timestep_equivalence() -> void:
	var coarse := _new_state()
	var fine := _new_state()
	for state: StateScript in [coarse, fine]:
		state.add_mana(120.0)
		state.start()
	coarse.tick(188.0)
	for i in 1880:
		fine.tick(0.1)
	_check(coarse.phase == "defend" and fine.phase == "defend", "Large and small ticks both cross the portal")
	_near(coarse.mana, 117.0, "Surplus tick time is charged to defense after transfer")
	_near(coarse.mana, fine.mana, "Mana consumption is independent of tick size", 0.0002)
	_near(coarse.elapsed, fine.elapsed, "Elapsed timer is independent of tick size", 0.0002)
	coarse.free()
	fine.free()
