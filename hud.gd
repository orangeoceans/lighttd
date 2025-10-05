extends Control

@onready var mirror_controls = $TowerControls/MirrorControls
@onready var rotation_bar = $TowerControls/MirrorControls/RotationBar

var current_tower: TowerLine = null

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

func _on_tower_selected(tower: TowerLine):
	current_tower = tower
	
	# Show MirrorControls only for mirrors
	if tower.tower_type == "mirror":
		if mirror_controls:
			mirror_controls.visible = true
		
		# Update rotation bar to match current rotation (disconnect to avoid feedback)
		if rotation_bar and rotation_bar is Range:
			rotation_bar.value_changed.disconnect(_on_rotation_changed)
			# Normalize rotation to 0-TAU range and map to slider range
			var normalized_rotation = fposmod(tower.rotation.y, TAU)
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
		current_tower.rotation.y = normalized_value * TAU
