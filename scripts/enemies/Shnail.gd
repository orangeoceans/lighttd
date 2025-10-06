extends "res://scripts/basicEnemy.gd"

# Shnail: Very bulky but slow

func _ready():
	# Set stats before calling super._ready() so health bar initializes correctly
	base_speed = 1.0   # Slow speed
	health = 500.0     # Very high health (very bulky)
	max_health = 500.0
	
	super._ready()
	
	# Ensure health bar is updated with correct values
	if health_bar:
		health_bar.update_health(health, max_health)
