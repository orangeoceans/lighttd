extends CharacterBody3D

### This enemy can be extended from its basic form to create a variety of enemies 

signal enemy_died
signal enemy_left_board

# Status effect enum
enum StatusEffect {
	BURNED,
	POISONED,
	FROZEN,
	WEAKENED
}

@export var base_speed : float = 2.0 ### Base Speed
@export var health : float = 100.0 ### HP
@export var max_health : float = 100.0 ### Max HP
@export var health_bar_scene: PackedScene = null  # Assign health bar scene in editor

var collision_radius: float = 0.5  # Radius for beam collision detection
var health_bar: EnemyHealthBar = null
var health_bar_offset_y: float = 2  # Height above enemy

# Status effect tracking: {StatusEffect: {accumulated: float, stacks: int, duration: float}}
var status_effects: Dictionary = {}

# Status effect configuration
const BURN_DAMAGE_PER_STACK: float = 4.0  # Damage per second per stack
const BURN_DECAY_RATE: float = 0.9  # Decay multiplier per second
const BURN_SPEED_BOOST: float = 0.5  # Constant speed boost when burned
const BURN_DURATION: float = 5.0  # Duration per stack

const POISON_DAMAGE_PER_STACK: float = 1.5  # Damage per second per stack
const POISON_DURATION: float = 8.0  # Duration per stack

const FREEZE_SLOW_PER_STACK: float = 0.15  # 15% slow per stack
const FREEZE_DURATION: float = 3.0  # Duration per stack
const FREEZE_DECAY_RATE: float = 0.85  # 15% decay per second

const WEAKEN_MULTIPLIER_PER_STACK: float = 0.1  # 10% extra damage per stack
const WEAKEN_DURATION: float = 6.0  # Duration per stack
const WEAKEN_DECAY_RATE: float = 0.9  # 10% decay per second

@onready var path : PathFollow3D = get_parent()

func _ready():
	add_to_group("enemies")
	
	# Create health bar if scene is assigned
	if health_bar_scene:
		health_bar = health_bar_scene.instantiate()
		add_child(health_bar)
		health_bar.position.y = health_bar_offset_y 
		health_bar.update_health(health, max_health)

func _process(delta: float) -> void:
	# Process status effects (visual and gameplay timing)
	process_status_effects(delta)
	
	# Update status effect display
	update_status_effect_display()

func _physics_process(delta: float) -> void:
	# Calculate current speed with status effect modifiers
	var current_speed = calculate_speed()
	
	path.set_progress(path.get_progress() + current_speed * delta)
	
	if path.get_progress_ratio() >= 0.99:
		###TODO: remove health if enemy makes it to the end 
		enemy_left_board.emit()  # Emit signal for EnemyController tracking
		# Use call_deferred to ensure signal is processed before freeing
		path.call_deferred("queue_free")

func take_damage(damage: float, apply_weakened: bool = true) -> void:
	var final_damage = damage
	
	# Apply weakened multiplier (exponential - each stack multiplies)
	if apply_weakened and has_status(StatusEffect.WEAKENED):
		var weaken_stacks = status_effects[StatusEffect.WEAKENED].stacks
		# Each stack multiplies damage by (1 + WEAKEN_MULTIPLIER_PER_STACK)
		# e.g., 4 stacks: 1.1^4 = 1.4641 (46.41% more damage)
		var multiplier = pow(1.0 + WEAKEN_MULTIPLIER_PER_STACK, weaken_stacks)
		final_damage *= multiplier
	
	health -= final_damage
	
	# Update health bar
	if health_bar:
		health_bar.update_health(health, max_health)
	
	if health <= 0:
		die()

func die() -> void:
	enemy_died.emit()  # Emit signal for EnemyController tracking
	if path:
		path.queue_free()
	else:
		queue_free()

func scale_health_for_wave(wave_number: int, scaling_factor: float) -> void:
	# Scale health based on wave number
	var health_multiplier = pow(scaling_factor, wave_number - 1)
	health *= health_multiplier
	max_health *= health_multiplier
	
	# Update health bar with new values
	if health_bar:
		health_bar.update_health(health, max_health)

# Accumulate status effect (fractional values)
func accumulate_status(effect: StatusEffect, amount: float) -> void:
	if effect in status_effects:
		# Add to existing accumulated value
		status_effects[effect].accumulated += amount
	else:
		# Create new status effect
		status_effects[effect] = {
			"accumulated": amount,
			"stacks": 0,
			"duration": get_status_duration(effect)
		}
	
	# Convert accumulated value to stacks using logarithmic function
	var new_stacks = convert_accumulated_to_stacks(status_effects[effect].accumulated)
	status_effects[effect].stacks = new_stacks

# Convert accumulated float to integer stacks using logarithmic scaling
# This creates diminishing returns: each stack requires exponentially more accumulation
func convert_accumulated_to_stacks(accumulated: float) -> int:
	if accumulated <= 0:
		return 0
	# log2(accumulated + 1) creates natural breakpoints:
	# 0.0 -> 0, 1.0 -> 1, 3.0 -> 2, 7.0 -> 3, 15.0 -> 4, etc.
	return int(log(accumulated + 1.0) / log(2.0))

func has_status(effect: StatusEffect) -> bool:
	return effect in status_effects

func get_status_stacks(effect: StatusEffect) -> int:
	if has_status(effect):
		return status_effects[effect].stacks
	return 0

func get_status_duration(effect: StatusEffect) -> float:
	match effect:
		StatusEffect.BURNED:
			return BURN_DURATION
		StatusEffect.POISONED:
			return POISON_DURATION
		StatusEffect.FROZEN:
			return FREEZE_DURATION
		StatusEffect.WEAKENED:
			return WEAKEN_DURATION
	return 0.0

# Process all active status effects
func process_status_effects(delta: float) -> void:
	var effects_to_remove = []
	
	for effect in status_effects.keys():
		var effect_data = status_effects[effect]
		
		# Decrease duration
		effect_data.duration -= delta
		
		if effect_data.duration <= 0:
			effects_to_remove.append(effect)
			continue
		
		# Process effect-specific behavior
		match effect:
			StatusEffect.BURNED:
				process_burn(effect_data, delta)
			StatusEffect.POISONED:
				process_poison(effect_data, delta)
			StatusEffect.FROZEN:
				process_freeze(effect_data, delta)
			StatusEffect.WEAKENED:
				process_weaken(effect_data, delta)
	
	# Remove expired effects
	for effect in effects_to_remove:
		status_effects.erase(effect)

func process_burn(effect_data: Dictionary, delta: float) -> void:
	# Decay accumulated value over time
	effect_data.accumulated *= pow(BURN_DECAY_RATE, delta)
	
	# Recalculate stacks based on decayed accumulation
	effect_data.stacks = convert_accumulated_to_stacks(effect_data.accumulated)
	
	# Apply continuous damage based on current stacks with balance multiplier
	if effect_data.stacks > 0:
		var balance_multiplier = Globals.get_balance_multiplier()
		var damage = BURN_DAMAGE_PER_STACK * effect_data.stacks * balance_multiplier * delta
		take_damage(damage, false)  # Don't apply weakened to DOT

func process_poison(effect_data: Dictionary, delta: float) -> void:
	# Apply continuous damage based on stacks with balance multiplier
	if effect_data.stacks > 0:
		var balance_multiplier = Globals.get_balance_multiplier()
		var damage = POISON_DAMAGE_PER_STACK * effect_data.stacks * balance_multiplier * delta
		take_damage(damage, false)  # Don't apply weakened to DOT

func process_freeze(effect_data: Dictionary, delta: float) -> void:
	# Decay accumulated value over time
	effect_data.accumulated *= pow(FREEZE_DECAY_RATE, delta)
	
	# Recalculate stacks based on decayed accumulation
	effect_data.stacks = convert_accumulated_to_stacks(effect_data.accumulated)

func process_weaken(effect_data: Dictionary, delta: float) -> void:
	# Decay accumulated value over time
	effect_data.accumulated *= pow(WEAKEN_DECAY_RATE, delta)
	
	# Recalculate stacks based on decayed accumulation
	effect_data.stacks = convert_accumulated_to_stacks(effect_data.accumulated)

func calculate_speed() -> float:
	var speed = base_speed
	
	# Burn speed boost (constant regardless of stacks)
	if has_status(StatusEffect.BURNED):
		speed += BURN_SPEED_BOOST
	
	# Freeze slow (stacks are already logarithmic from accumulation)
	if has_status(StatusEffect.FROZEN):
		var freeze_stacks = status_effects[StatusEffect.FROZEN].stacks
		var slow_multiplier = 1.0 - (freeze_stacks * FREEZE_SLOW_PER_STACK)
		slow_multiplier = max(slow_multiplier, 0.1)  # Minimum 10% speed
		speed *= slow_multiplier
	
	return speed

# Update the status effect display on the health bar
func update_status_effect_display() -> void:
	if health_bar and health_bar.has_method("update_status_effects"):
		health_bar.update_status_effects(status_effects)
