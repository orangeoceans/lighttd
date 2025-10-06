extends "res://scripts/basicEnemy.gd"

# Spider: Fast, and leaps forward in bursts

var leap_timer: float = 0.0
var leap_interval: float = 0.5  # Leap every 0.5 seconds
var leap_distance_min: float = 1  # Minimum leap distance
var leap_distance_max: float = 2  # Maximum leap distance
var is_leaping: bool = false

func _ready():
	# Set stats before calling super._ready() so health bar initializes correctly
	base_speed = 3.0   # Fast base speed
	health = 80.0      # Medium health
	max_health = 80.0
	
	super._ready()
	
	# Update health bar if it exists
	if health_bar:
		health_bar.update_health(health, max_health)

func _physics_process(delta: float) -> void:
	# Handle leap timing
	leap_timer += delta
	
	# Check if it's time to leap
	if leap_timer >= leap_interval and not is_leaping:
		perform_leap()
		leap_timer = 0.0
	
	# Call parent physics process
	super._physics_process(delta)

func perform_leap():
	if not path:
		return
	
	is_leaping = true
	
	# Calculate random leap distance
	var random_leap_distance = randf_range(leap_distance_min, leap_distance_max)
	
	# Leap forward by adding to progress
	var current_progress = path.get_progress()
	path.set_progress(current_progress + random_leap_distance)
	
	# Reset leap flag after a short delay
	await get_tree().create_timer(0.2).timeout
	is_leaping = false

func calculate_speed() -> float:
	# Spider doesn't move continuously - only via leaps
	return 0.0
