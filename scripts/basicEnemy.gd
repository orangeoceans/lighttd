extends CharacterBody3D

### This enemy can be extended from its basic form to create a variety of enemies 


@export var speed : int = 2 ### Speed
@export var health : int = 10 ### HP
@export var max_health : int = 10 ### Max HP
@export var health_bar_scene: PackedScene = null  # Assign health bar scene in editor

var collision_radius: float = 0.5  # Radius for beam collision detection
var health_bar: EnemyHealthBar = null
var health_bar_offset_y: float = 1.5  # Height above enemy

@onready var path : PathFollow3D = get_parent()

func _ready():
	add_to_group("enemies")
	
	# Create health bar if scene is assigned
	if health_bar_scene:
		health_bar = health_bar_scene.instantiate()
		add_child(health_bar)
		health_bar.position.y = health_bar_offset_y 
		health_bar.update_health(health, max_health)

func _physics_process(delta: float) -> void:
	path.set_progress(path.get_progress() + speed * delta)
	
	if path.get_progress_ratio() >= 0.99:
		
		###TODO: remove health if enemy makes it to the end 
		
		path.queue_free()

func take_damage(damage: float) -> void:
	health -= damage
	
	# Update health bar
	if health_bar:
		health_bar.update_health(health, max_health)
	
	if health <= 0:
		die()

func die() -> void:
	print("Enemy destroyed!")
	if path:
		path.queue_free()
	else:
		queue_free()
