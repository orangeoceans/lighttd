extends Node3D
class_name EnemyController

signal wave_started
signal wave_completed
signal all_enemies_cleared

@export var enemies_per_wave: int = 10
@export var spawn_cooldown: float = 0.5

@export var hud: Control
@export var level: Level

@onready var basicEnemy: PackedScene = preload("res://scenes/enemies/basicEnemy.tscn")
@onready var spawn_timer: Timer = Timer.new()

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
	
	wave_active = true
	enemies_to_spawn = enemies_per_wave
	active_enemies.clear()
	wave_started.emit()

func spawn_enemies():
	if enemies_to_spawn > 0 and can_spawn:
		if not is_instance_valid(scene_path):
			push_error("EnemyController: scene_path is invalid")
			return
		
		spawn_timer.start()
		var enemy_scene = basicEnemy.instantiate()
		scene_path.add_child(enemy_scene)
		
		# The actual enemy with the script is a child of the PathFollow3D
		var enemy = null
		if enemy_scene.get_child_count() > 0:
			enemy = enemy_scene.get_child(0)  # Get first child (CharacterBody3D with script)
		else:
			enemy = enemy_scene  # Fallback to root node
		
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
		all_enemies_cleared.emit()

func _on_enemy_left_board(enemy):
	# Remove the enemy from the active list
	if enemy in active_enemies:
		active_enemies.erase(enemy)
	
	# TODO: Apply damage to player, reduce lives, etc.
	
	# Check if all enemies are cleared
	if active_enemies.size() <= 0 and enemies_to_spawn <= 0 and wave_active:
		wave_active = false
		all_enemies_cleared.emit()

func is_wave_ready() -> bool:
	return not wave_active and active_enemies.size() <= 0
