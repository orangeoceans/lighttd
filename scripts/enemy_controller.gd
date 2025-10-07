extends Node3D
class_name EnemyController

signal wave_started(wave_number: int)
signal wave_completed
signal all_enemies_cleared
signal enemy_reached_end

@export var enemies_per_wave: int = 10
@export var spawn_cooldown: float = 1

var current_wave: int = 1

@export var hud: Control
@export var level: Level

# Enemy scenes
@onready var enemy_scenes: Dictionary = {
	"Martin": preload("res://scenes/enemies/Martin.tscn"),
	"Acorn": preload("res://scenes/enemies/Acorn.tscn"), 
	"Spider": preload("res://scenes/enemies/Spider.tscn"),
	"Pinecone": preload("res://scenes/enemies/Pinecone.tscn"),
	"Shnail": preload("res://scenes/enemies/Shnail.tscn")
}

@onready var spawn_timer: Timer = Timer.new()

var current_wave_enemy_types: Array[String] = []  # Multiple enemy types per wave
var health_scaling_per_wave: float = 1.1  # 10% more health per wave

var scene_path: Path3D = null
var enemies_to_spawn: int = 0
var active_enemies: Array = []  # List of active enemy instances
var wave_active: bool = false
var can_spawn: bool = true

func _ready():
	# Add to group for easy finding
	add_to_group("enemy_controller")
	
	# Create spawn timer
	add_child(spawn_timer)
	spawn_timer.wait_time = spawn_cooldown
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	
	# Find the path from level's board
	if level and level.board and level.board.has_node("Path3D"):
		scene_path = level.board.get_node("Path3D")
	
	# Connect to HUD if available
	if hud:
		all_enemies_cleared.connect(hud._on_all_enemies_cleared)
		wave_started.connect(hud._on_wave_started)

func _process(_delta):
	if wave_active:
		spawn_enemies()

func start_wave():
	if wave_active or active_enemies.size() > 0:
		return  # Can't start wave if one is active or enemies still alive
	
	# Select multiple enemy types based on wave number
	current_wave_enemy_types = select_enemy_types_for_wave()
	
	wave_active = true
	enemies_to_spawn = enemies_per_wave
	active_enemies.clear()
	
	wave_started.emit(current_wave)

func select_enemy_types_for_wave() -> Array[String]:
	var enemy_types = enemy_scenes.keys()
	var selected_types: Array[String] = []
	
	# Calculate number of different enemy types based on wave
	# Wave 1: 1 type, Wave 2-3: 1-2 types, Wave 4-6: 1-3 types, Wave 7+: 1-4 types
	var max_types: int
	if current_wave <= 1:
		max_types = 1
	elif current_wave <= 3:
		max_types = 2
	elif current_wave <= 6:
		max_types = 3
	else:
		max_types = 4
	
	# Randomly select 1 to max_types different enemy types
	var num_types = randi_range(1, max_types)
	
	# Shuffle enemy types and pick the first num_types
	enemy_types.shuffle()
	for i in range(min(num_types, enemy_types.size())):
		selected_types.append(enemy_types[i])
	
	return selected_types

func spawn_enemies():
	if enemies_to_spawn > 0 and can_spawn:
		if not is_instance_valid(scene_path):
			push_error("EnemyController: scene_path is invalid")
			return
		
		if current_wave_enemy_types.is_empty():
			push_error("EnemyController: No enemy types selected for wave")
			return
		
		# Randomly select an enemy type from this wave's types
		var selected_enemy_type = current_wave_enemy_types[randi() % current_wave_enemy_types.size()]
		
		spawn_timer.start()
		var enemy_scene = enemy_scenes[selected_enemy_type].instantiate()
		scene_path.add_child(enemy_scene)
		
		# The actual enemy with the script is a child of the PathFollow3D
		var enemy = null
		if enemy_scene.get_child_count() > 0:
			enemy = enemy_scene.get_child(0)  # Get first child (CharacterBody3D with script)
		else:
			enemy = enemy_scene  # Fallback to root node
		
		# Apply health scaling based on wave number
		if enemy and enemy.has_method("scale_health_for_wave"):
			enemy.scale_health_for_wave(current_wave, health_scaling_per_wave)
		
		# Connect to enemy signals to track active count
		if enemy.has_signal("enemy_died"):
			enemy.enemy_died.connect(_on_enemy_died.bind(enemy))
		if enemy.has_signal("enemy_left_board"):
			enemy.enemy_left_board.connect(_on_enemy_left_board.bind(enemy))
		
		enemies_to_spawn -= 1
		active_enemies.append(enemy)
		can_spawn = false
		
		# Check if wave spawning is complete
		if enemies_to_spawn <= 0:
			wave_completed.emit()

func _on_spawn_timer_timeout():
	can_spawn = true

func _on_enemy_died(enemy):
	# Remove the enemy from the active list
	if enemy in active_enemies:
		active_enemies.erase(enemy)
	
	# Check if all enemies are cleared
	if active_enemies.size() <= 0 and enemies_to_spawn <= 0 and wave_active:
		wave_active = false
		current_wave += 1  # Increment wave number for next wave
		all_enemies_cleared.emit()

func _on_enemy_left_board(enemy):
	# Remove the enemy from the active list
	if enemy in active_enemies:
		active_enemies.erase(enemy)
	
	# Emit signal to notify player controller to lose a life
	enemy_reached_end.emit()
	
	# Check if all enemies are cleared
	if active_enemies.size() <= 0 and enemies_to_spawn <= 0 and wave_active:
		wave_active = false
		current_wave += 1  # Increment wave number for next wave
		all_enemies_cleared.emit()

func is_wave_ready() -> bool:
	return not wave_active and active_enemies.size() <= 0
