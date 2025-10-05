extends CharacterBody3D

### This enemy can be extended from its basic form to create a variety of enemies 


@export var speed : int = 2 ### Speed
@export var health : int = 10 ### HP
@export var max_health : int = 10 ### Max HP

var collision_radius: float = 0.5  # Radius for beam collision detection

@onready var path : PathFollow3D = get_parent()

func _ready():
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	path.set_progress(path.get_progress() + speed * delta)
	
	if path.get_progress_ratio() >= 0.99:
		
		###TODO: remove health if enemy makes it to the end 
		
		path.queue_free()

func take_damage(damage: float) -> void:
	health -= damage
	if health <= 0:
		die()

func die() -> void:
	print("Enemy destroyed!")
	if path:
		path.queue_free()
	else:
		queue_free()
