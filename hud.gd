extends Control

@onready var mirror_controls = $TowerControls/MirrorControls
@onready var rotation_bar = $TowerControls/MirrorControls/RotationBar
@onready var start_wave_button = $BottomBar/StartWave
@onready var reset_camera_button = $BottomBar/ResetCamera
@onready var wave_counter = $BottomBar/WaveCounter

var current_tower: TowerLine = null
var enemy_controller: EnemyController = null
var player_controller = null

func _ready():
	# Hide controls by default
	if mirror_controls:
		mirror_controls.visible = false
	
	# Connect to globals signals
	if Globals:
		Globals.tower_selected.connect(_on_tower_selected)
		Globals.tower_deselected.connect(_on_tower_deselected)
	
	# Connect rotation bar signal
	if rotation_bar and rotation_bar is Range:
		rotation_bar.value_changed.connect(_on_rotation_changed)
	
	# Connect StartWave button
	if start_wave_button:
		start_wave_button.pressed.connect(_on_start_wave_pressed)
	
	# Connect ResetCamera button
	if reset_camera_button:
		reset_camera_button.pressed.connect(_on_reset_camera_pressed)
	
	# Initialize wave counter
	update_wave_counter(1)
	
	# Find controllers
	call_deferred("_find_controllers")

func _find_controllers():
	# Find EnemyController
	enemy_controller = get_tree().get_first_node_in_group("enemy_controller")
	if not enemy_controller:
		var nodes = get_tree().get_nodes_in_group("enemy_controller")
		if nodes.size() > 0:
			enemy_controller = nodes[0]
	
	# Find PlayerController
	player_controller = get_tree().get_first_node_in_group("player_controller")
	if not player_controller:
		# Look for PlayerController by class/script
		var all_nodes = get_tree().get_nodes_in_group("player_controller")
		if all_nodes.size() > 0:
			player_controller = all_nodes[0]
	
	# Enable buttons if controllers found
	if enemy_controller and start_wave_button:
		start_wave_button.disabled = false
	if player_controller and reset_camera_button:
		reset_camera_button.disabled = false

func _on_start_wave_pressed():
	if enemy_controller and enemy_controller.is_wave_ready():
		enemy_controller.start_wave()

func _on_wave_started(wave_number: int):
	# Disable button when wave starts
	if start_wave_button:
		start_wave_button.disabled = true
	
	# Update wave counter display
	update_wave_counter(wave_number)

func _on_all_enemies_cleared():
	# Enable button when all enemies are cleared
	if start_wave_button:
		start_wave_button.disabled = false

func _on_reset_camera_pressed():
	if player_controller and player_controller.has_method("reset_camera"):
		player_controller.reset_camera()

func update_wave_counter(wave_number: int):
	if wave_counter:
		wave_counter.text = "WAVE " + str(wave_number)

func _on_tower_selected(tower: TowerLine):
	current_tower = tower
	
	# Show MirrorControls only for mirrors
	if tower.tower_type == "mirror":
		if mirror_controls:
			mirror_controls.visible = true
		
		# Update rotation bar to match current rotation (disconnect to avoid feedback)
		if rotation_bar and rotation_bar is Range:
			rotation_bar.value_changed.disconnect(_on_rotation_changed)
			# Get effective rotation from gem_node if it exists, otherwise from tower
			var current_rotation = tower.gem_node.rotation.y if tower.gem_node else tower.rotation.y
			# Normalize rotation to 0-TAU range and map to slider range
			var normalized_rotation = fposmod(current_rotation, TAU)
			var slider_range = rotation_bar.max_value - rotation_bar.min_value
			rotation_bar.value = rotation_bar.min_value + (normalized_rotation / TAU) * slider_range
			rotation_bar.value_changed.connect(_on_rotation_changed)
	else:
		# Hide for non-mirror towers
		if mirror_controls:
			mirror_controls.visible = false

func _on_tower_deselected():
	current_tower = null
	
	# Hide controls when nothing is selected
	if mirror_controls:
		mirror_controls.visible = false

func _on_rotation_changed(value: float):
	# Update the selected tower's rotation
	if current_tower and is_instance_valid(current_tower) and current_tower.tower_type == "mirror":
		# Map slider value to 0-TAU range
		var slider_range = rotation_bar.max_value - rotation_bar.min_value
		var normalized_value = (value - rotation_bar.min_value) / slider_range
		current_tower.set_tower_rotation(normalized_value * TAU)
