extends "res://scripts/basicEnemy.gd"

# Martin: Speedy enemy

func _ready():
	# Set stats before calling super._ready() so health bar initializes correctly
	base_speed = 4.0  # Fast speed
	health = 100.0     # Lower health
	max_health = 100.0
	
	super._ready()
	
	# Ensure health bar is updated with correct values
	if health_bar:
		health_bar.update_health(health, max_health)
