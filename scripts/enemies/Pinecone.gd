extends "res://scripts/basicEnemy.gd"

# Pinecone: Bulky but average speed

func _ready():
	# Set stats before calling super._ready() so health bar initializes correctly
	base_speed = 2.0   # Average speed
	health = 250.0     # High health (bulky)
	max_health = 250.0
	
	super._ready()
	
	# Ensure health bar is updated with correct values
	if health_bar:
		health_bar.update_health(health, max_health)
