extends "res://scripts/basicEnemy.gd"

# Acorn: All around average enemy

func _ready():
	# Set stats before calling super._ready() so health bar initializes correctly
	base_speed = 2.0   # Average speed
	health = 100.0     # Average health
	max_health = 100.0
	
	super._ready()
	
	# Ensure health bar is updated with correct values
	if health_bar:
		health_bar.update_health(health, max_health)
