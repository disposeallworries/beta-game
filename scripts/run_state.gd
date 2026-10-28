extends Node
class_name RunState
## Shared resources and phase rules for a complete gather -> portal -> defend run.
## World objects draw only accepted mana; combat always spends through this node.

signal phase_changed(phase: String)
signal mana_changed(value: float)
signal run_ended(won: bool, reason: String)

const CORE_DURATION: float = 180.0
const MANA_CAP: float = 600.0
const MIN_PORTAL_MANA: float = 60.0
const TRANSITION_DURATION: float = 3.0
const DEFENSE_DRAIN: float = 0.6

var phase: String = "explore"
var started: bool = false
var mana: float = 0.0
var core_time: float = CORE_DURATION
var elapsed: float = 0.0
var transition_time: float = 0.0
var sword_level: int = 0
var pools_visited: Dictionary = {}
var loss_reason: String = ""
var total_collected: float = 0.0


func reset() -> void:
	var old_mana: float = mana
	started = false
	mana = 0.0
	core_time = CORE_DURATION
	elapsed = 0.0
	transition_time = 0.0
	sword_level = 0
	pools_visited.clear()
	loss_reason = ""
	total_collected = 0.0
	_set_phase("explore")
	if not is_zero_approx(old_mana):
		mana_changed.emit(mana)


func start() -> void:
	if phase == "explore":
		started = true


func tick(dt: float) -> void:
	if not is_finite(dt) or dt <= 0.0 or phase in ["won", "lost"]:
		return
	if phase == "explore" and not started:
		return
	# Carry surplus time through transitions. A low frame rate must not grant
	# additional gathering time or skip the mana cost of defending the tower.
	var remaining: float = dt
	while remaining > 0.0:
		match phase:
			"explore":
				var consumed: float = minf(remaining, core_time)
				core_time = maxf(core_time - consumed, 0.0)
				elapsed += consumed
				remaining -= consumed
				if core_time <= 0.0:
					request_portal(true)
				else:
					return
			"transition":
				var consumed: float = minf(remaining, transition_time)
				transition_time = maxf(transition_time - consumed, 0.0)
				elapsed += consumed
				remaining -= consumed
				if transition_time <= 0.0:
					complete_transition()
				else:
					return
			"defend":
				if mana <= 0.0:
					lose("Your mana reserve is empty.")
					return
				var consumed: float = minf(remaining, mana / DEFENSE_DRAIN)
				elapsed += consumed
				drain_mana(consumed * DEFENSE_DRAIN)
				return
			_:
				return


func add_mana(amount: float) -> float:
	if phase in ["won", "lost"] or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var accepted: float = minf(amount, MANA_CAP - mana)
	if accepted <= 0.0:
		return 0.0
	mana += accepted
	total_collected += accepted
	mana_changed.emit(mana)
	return accepted


func spend_mana(amount: float) -> bool:
	if phase in ["won", "lost"] or not is_finite(amount) or amount < 0.0 or amount > mana:
		return false
	if amount > 0.0:
		drain_mana(amount)
	return true


func drain_mana(amount: float) -> float:
	if phase in ["won", "lost"] or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var drained: float = minf(amount, mana)
	mana = maxf(mana - drained, 0.0)
	if drained > 0.0:
		mana_changed.emit(mana)
	if phase == "defend" and mana <= 0.0:
		lose("Your mana reserve is empty.")
	return drained


func collect_sword(level: int) -> bool:
	if phase in ["won", "lost"] or level <= sword_level or level <= 0:
		return false
	var next_level: int = mini(level, 2)
	if next_level <= sword_level:
		return false
	sword_level = next_level
	return true


func record_pool(id: int) -> void:
	if id >= 0 and phase not in ["won", "lost"]:
		pools_visited[id] = true


func request_portal(force: bool = false) -> bool:
	if phase != "explore" or (not force and mana < MIN_PORTAL_MANA):
		return false
	started = true
	transition_time = TRANSITION_DURATION
	_set_phase("transition")
	return true


func complete_transition() -> void:
	if phase != "transition":
		return
	transition_time = 0.0
	if mana <= 0.0:
		lose("Your core reached the portal without any mana.")
	else:
		_set_phase("defend")


func win() -> void:
	if phase != "defend":
		return
	_set_phase("won")
	run_ended.emit(true, "The tower is safe. Your core endures.")


func lose(reason: String) -> void:
	if phase in ["won", "lost"]:
		return
	loss_reason = reason
	_set_phase("lost")
	run_ended.emit(false, loss_reason)


func _set_phase(next_phase: String) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	phase_changed.emit(phase)
