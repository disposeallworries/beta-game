extends SceneTree
## Combat visuals remain attached to the real original mesh and never move physics.
const STEP := 1.0 / 120.0
const HAND_TIP := Vector3(0, -0.475, 0)
const SWORD_TIP := Vector3(0, -0.765, 0)
var player: ParkourPlayer
var visual: BlobVisual
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	player = ParkourPlayer.new()
	visual = BlobVisual.new()
	# These public APIs also work before the model has finished setup.
	visual.set_weapon(0)
	visual.set_core_charge(0.4)
	root.add_child(player)
	root.add_child(visual)
	player.position = Vector3(2, 3, 4)
	player.grounded = true
	player.yaw = 0
	player.yaw_target = 0
	visual.setup(player)
	await process_frame
	visual.tick(STEP)
	_check(not visual._sword.visible, "The sword is locked and invisible at level zero")
	_check(not visual.play_attack("sword"), "A locked sword cannot start its attack animation")
	_check(visual.play_attack("bolt"), "Mana bolts work before the sword unlocks")
	visual.tick(STEP)
	visual.set_weapon(1)
	_check(visual._sword.visible and visual._weapon_level == 1, "The first sword becomes visible on unlock")
	_check(visual._sword.get_parent() == visual.bones[2], "Sword grip is a child of the actual right arm")
	_check(visual._sword.position.is_equal_approx(HAND_TIP), "Sword grip is placed at the actual right-hand mesh endpoint")
	_check(SWORD_TIP.length() + 0.085 < 0.9, "The complete sword remains less than 90 cm long")
	var normal_color: Color = visual._blade_material.albedo_color
	visual.set_weapon(2)
	_check(visual._blade_material.albedo_color != normal_color and visual._blade_material.emission_enabled, "The stronger sword has a distinct calm cyan blade")
	visual.set_weapon(5)
	_check(visual._weapon_level == 2, "Sword level is clamped to the strongest available blade")
	visual.set_core_charge(-4)
	_check(is_zero_approx(visual._core_charge), "Mana charge clamps below zero")
	var empty_energy: float = visual._core_material.emission_energy_multiplier
	visual.set_core_charge(10)
	_check(is_equal_approx(visual._core_charge, 1), "Mana charge clamps above one")
	var full_energy: float = visual._core_material.emission_energy_multiplier
	_check(full_energy > empty_energy and full_energy < 1.0, "Core brightness shows charge with restrained emission")
	for kind: String in ["sword", "bolt"]:
		_check(visual.play_attack(kind), "The %s attack starts" % kind)
		var start_position: Vector3 = player.position
		var start_velocity: Vector3 = player.velocity
		var endpoints: Array[Vector3] = []
		for i in range(60):
			visual.tick(STEP)
			var grip: Vector3 = visual._sword.global_position
			var hand: Vector3 = visual.bones[2].to_global(HAND_TIP)
			_check(grip.distance_to(hand) < 0.0001, "The %s grip follows the actual moving hand" % kind)
			var expected_tip: Vector3 = visual.bones[2].to_global(HAND_TIP + SWORD_TIP)
			_check(visual._sword.to_global(SWORD_TIP).distance_to(expected_tip) < 0.0001, "The complete held blade follows the arm transform")
			_check(player.position.is_equal_approx(start_position) and player.velocity.is_equal_approx(start_velocity), "Attack animation adds no physical motion")
			if not visual._attack_kind.is_empty():
				_check(visual.bones[0].position.is_zero_approx(), "Attack pose has no extra vertical root displacement")
			endpoints.append(visual._sword.to_global(SWORD_TIP))
		_check(visual._attack_kind.is_empty() and is_zero_approx(visual._attack_time), "The %s timer completes and returns to locomotion" % kind)
		if kind == "sword":
			var largest_sweep := 0.0
			for endpoint: Vector3 in endpoints:
				largest_sweep = maxf(largest_sweep, endpoint.distance_to(endpoints[0]))
			_check(largest_sweep > 0.6, "The attached sword makes a readable side-to-side cut")
	_check(is_equal_approx(visual._core_material.emission_energy_multiplier, full_energy), "The mana core does not flash or pulse while time advances")
	visual.play_attack("sword")
	player.state = "hang"
	player.position = Vector3(0, 1.9, 0.35)
	player.ledge = {"ax": 0.0, "az": -1.0, "top": 3.0}
	player.ledge_front = 0.0
	player.yaw_target = PI
	player.grounded = false
	visual.tick(STEP)
	_check(visual._attack_kind.is_empty(), "Ledge contact cancels a combat attack immediately")
	_check(not visual._sword.visible, "The sword is stowed while both hands grip a ledge")
	_check(not visual.play_attack("bolt") and not visual.play_attack("sword"), "Ledge contact rejects new attack poses")
	for i in range(2):
		var hand: Vector3 = visual.bones[i + 1].to_global(HAND_TIP)
		_check(hand.distance_to(visual._grip_anchors[i]) < 0.002, "Combat never overrides the anchored hand pose")
	player.state = "move"
	player.grounded = true
	visual.tick(STEP)
	_check(visual._sword.visible, "The unlocked sword returns after leaving contact")
	visual.set_weapon(-1)
	_check(visual._weapon_level == 0 and not visual._sword.visible, "Removing the unlock hides the sword again")
	_check(not visual.play_attack("unknown"), "Unknown attack names are ignored safely")
	visual.free()
	player.free()
	print("Combat animation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
