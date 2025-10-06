extends Node3D

# Player input and tower interaction controller

@export var hud: Control
@export var level: Level
@export var camera_rig: Node3D
@export var choose_three_container: HBoxContainer
@export var max_active_beams: int = 2  # Maximum number of beams that can be active at once
@export var color_ratio_box: Control

# State tracking
var right_mouse_was_pressed: bool = false
var dragging_tower: TowerLine = null
var drag_offset: Vector3 = Vector3.ZERO
var original_parent: Node = null

var selected_tower: TowerLine = null

# Camera control variables
var is_panning: bool = false
var is_rotating: bool = false
var pan_start_position: Vector2
var rotation_start_position: Vector2
var camera_rotation_sensitivity: float = 0.005
var camera_pan_sensitivity: Vector2 = Vector2(0.01, 0.02)
var camera_zoom_sensitivity: float = 0.5
var min_zoom: float = 10.0  # Minimum FOV/size (zoomed in)
var max_zoom: float = 120.0  # Maximum FOV/size (zoomed out)

# Default camera settings (stored on first frame)
var default_camera_rig_position: Vector3
var default_camera_rig_rotation: Vector3
var default_camera_fov: float = 75.0  # Default perspective FOV
var default_camera_size: float = 20.0  # Default orthogonal size
var camera_defaults_stored: bool = false

# Beam activation tracking
var active_beams: Array[Beam] = []  # Currently active beams

# UI References
var tower_option_control: Control = null
var mirror_option_button: Button = null
var concave_option_button: Button = null
var convex_option_button: Button = null
var collector_option_button: Button = null
var move_button: Button = null
var delete_button: Button = null
var tower_name_label: RichTextLabel = null
var tower_controls_bg: ColorRect = null
var tower_options_bg: ColorRect = null
var tower_controls_tween: Tween = null
var tower_options_tween: Tween = null

# Upgrade system
var upgrade_panels: Array[ColorRect] = []
var upgrade_name_labels: Array[RichTextLabel] = []
var upgrade_desc_labels: Array[RichTextLabel] = []
var choose_buttons: Array[Button] = []
var current_upgrade_choices: Array = []  # Store the current displayed upgrades

# Tutorial system
var tutorial_container: Control = null
var tutorial_title_label: RichTextLabel = null
var tutorial_desc_label: RichTextLabel = null
var tutorial_ok_button: Button = null
var tutorial_shown: Dictionary = {
	"game_start": false,
	"first_tower": false,
	"collector_unlock": false
}

# Player progression
var unlocked_beam_colors: Array[String] = ["red"]  # Start with red only
var unlocked_tower_types: Array[String] = ["mirror"]  # Start with mirrors only
var ccollector_tower_unlocked: bool = false
var collector_tower_placed: bool = false
var any_tower_placed: bool = false  # Track if any towers have been placed

func _ready():
	# Add to group for HUD to find
	add_to_group("player_controller")
	
	# Connect to wave system
	var enemy_controller = get_tree().get_first_node_in_group("enemy_controller")
	if enemy_controller:
		enemy_controller.all_enemies_cleared.connect(_on_wave_completed)
	
	# Find the tower option buttons from HUD
	if hud:
		tower_option_control = hud.get_node_or_null("TopBar/TowerOption")
		if tower_option_control:
			mirror_option_button = tower_option_control.get_node_or_null("MirrorOption")
			concave_option_button = tower_option_control.get_node_or_null("ConcaveOption")
			convex_option_button = tower_option_control.get_node_or_null("ConvexOption")
			collector_option_button = tower_option_control.get_node_or_null("CollectorOption")
			
			# Find TowerOptionsBG
			tower_options_bg = tower_option_control.get_node_or_null("TowerOptionsBG")
			if not tower_options_bg:
				print("WARNING: TowerOptionsBG not found in TowerOption")
			
			# Connect button signals
			if mirror_option_button:
				mirror_option_button.toggled.connect(_on_mirror_option_toggled)
			if concave_option_button:
				concave_option_button.toggled.connect(_on_concave_option_toggled)
			if convex_option_button:
				convex_option_button.toggled.connect(_on_convex_option_toggled)
			if collector_option_button:
				collector_option_button.toggled.connect(_on_collector_option_toggled)
		else:
			print("WARNING: TowerOption control not found in HUD")
		
		# Find and connect MoveButton
		move_button = hud.get_node_or_null("TowerControls/MoveButton")
		if move_button:
			move_button.pressed.connect(_on_move_button_pressed)
			move_button.visible = false  # Hide initially since no tower is selected
		else:
			print("WARNING: MoveButton not found in HUD")
		
		# Find and connect DeleteButton
		delete_button = hud.get_node_or_null("TowerControls/DeleteButton")
		if delete_button:
			delete_button.pressed.connect(_on_delete_button_pressed)
			delete_button.visible = false  # Hide initially since no tower is selected
		else:
			print("WARNING: DeleteButton not found in HUD")
		
		# Find TowerName label
		tower_name_label = hud.get_node_or_null("TowerControls/TowerName")
		if not tower_name_label:
			print("WARNING: TowerName label not found in HUD")
		
		# Find TowerControlsBG
		tower_controls_bg = hud.get_node_or_null("TowerControls/TowerControlsBG")
		if tower_controls_bg:
			tower_controls_bg.visible = false  # Hide initially since no tower is selected
		else:
			print("WARNING: TowerControlsBG not found in HUD")
		
		# Find ChooseThree upgrade interface
		setup_choose_three_interface()
		
		# Setup tutorial interface
		setup_tutorial_interface()
		
		# Hide color ratio container initially and update UI based on initial progression state
		if color_ratio_box:
			color_ratio_box.visible = false
		
		update_progression_ui()
		
		# Start tower options pulsating since no towers are placed initially
		start_tower_options_pulsate()
		
		# Show game start tutorial after a brief delay
		call_deferred("show_game_start_tutorial")
	else:
		print("WARNING: HUD reference not set in PlayerController")

func _process(_delta):
	# Store default camera settings on first frame
	if not camera_defaults_stored and camera_rig:
		store_default_camera_settings()
	handle_beam_activation()
	handle_camera_controls()
	handle_player_controls()
	
	# Debug: Test upgrade interface with U key
	if Input.is_action_just_pressed("ui_up"):  # U key for testing
		print("DEBUG: Manually triggering upgrade interface")
		show_upgrade_choices()

func get_selected_tower_type() -> String:
	# Check which button is pressed and if tower type is unlocked
	if mirror_option_button and mirror_option_button.button_pressed and "mirror" in unlocked_tower_types:
		return "mirror"
	elif concave_option_button and concave_option_button.button_pressed and "concave_lens" in unlocked_tower_types:
		return "concave_lens"
	elif convex_option_button and convex_option_button.button_pressed and "convex_lens" in unlocked_tower_types:
		return "convex_lens"
	elif collector_option_button and collector_option_button.button_pressed and ccollector_tower_unlocked and not collector_tower_placed:
		return "collector"
	
	# Return first unlocked tower type as fallback
	if unlocked_tower_types.size() > 0:
		return unlocked_tower_types[0]
	return "mirror"  # Ultimate fallback

func handle_beam_activation() -> void:
	if not level:
		return
	
	# Get board from level
	var board = level.board
	if not board:
		return
	
	var all_beams = board.beams
	if all_beams.is_empty():
		return

	# Check for key presses and toggle beam activation
	for i in range(all_beams.size()):
		var beam = all_beams[i]
		if not is_instance_valid(beam):
			continue
		
		# Check if this beam's key is pressed
		if Input.is_key_pressed(beam.key):
			# Try to activate this beam
			if not beam.is_active:
				# Check if we're at the limit
				if active_beams.size() >= max_active_beams:
					# Deactivate oldest beam
					var oldest_beam = active_beams[0]
					oldest_beam.is_active = false
					active_beams.erase(oldest_beam)
				
				# Activate this beam
				beam.is_active = true
				active_beams.append(beam)
				print("Beam ", i, " (", char(beam.key), ") activated")
		else:
			# Key not pressed, deactivate this beam
			if beam.is_active:
				beam.is_active = false
				active_beams.erase(beam)
				print("Beam ", i, " (", char(beam.key), ") deactivated")

func handle_camera_controls():
	if not camera_rig:
		return
	
	# Handle camera panning (left + right click)
	if Input.is_action_pressed("interact") and Input.is_action_pressed("interact_2"):
		if not is_panning:
			is_panning = true
			pan_start_position = get_viewport().get_mouse_position()
		else:
			var mouse_delta = get_viewport().get_mouse_position() - pan_start_position
			var pan_vector = Vector3(-mouse_delta.x * camera_pan_sensitivity.x + mouse_delta.y * camera_pan_sensitivity.y, 0, - mouse_delta.x * camera_pan_sensitivity.x - mouse_delta.y * camera_pan_sensitivity.y)
			camera_rig.global_position += pan_vector
			pan_start_position = get_viewport().get_mouse_position()
	else:
		is_panning = false
	
	# Handle camera rotation (right click drag) - orbit around pivot
	if Input.is_action_pressed("interact_2") and not Input.is_action_pressed("interact"):
		if not is_rotating:
			is_rotating = true
			rotation_start_position = get_viewport().get_mouse_position()
		else:
			var mouse_delta = get_viewport().get_mouse_position() - rotation_start_position
			
			# Rotate the entire rig around its origin (the pivot point)
			# Horizontal rotation (Y-axis) - left/right mouse movement
			camera_rig.rotation.y -= mouse_delta.x * camera_rotation_sensitivity
			
			# Vertical rotation (X-axis) - up/down mouse movement  
			camera_rig.rotation.x -= mouse_delta.y * camera_rotation_sensitivity
			
			# Clamp vertical rotation to prevent camera flipping upside down
			camera_rig.rotation.x = clamp(camera_rig.rotation.x, -PI/2 + 0.1, PI/2 - 0.1)
			
			rotation_start_position = get_viewport().get_mouse_position()
	else:
		is_rotating = false

func _input(event):
	# Handle zoom with scroll wheel
	if event is InputEventMouseButton and camera_rig:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(-camera_zoom_sensitivity)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(camera_zoom_sensitivity)

func zoom_camera(zoom_delta: float):
	if not camera_rig:
		return
	
	# Find the Camera3D node in the hierarchy
	var camera = find_camera_in_rig()
	if not camera:
		return
	
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		# For perspective cameras, adjust FOV
		var current_fov = camera.fov
		var new_fov = clamp(current_fov + zoom_delta * 10, min_zoom, max_zoom)  # Scale zoom_delta for FOV
		camera.fov = new_fov
	elif camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# For orthogonal cameras, adjust size
		var current_size = camera.size
		var new_size = clamp(current_size + zoom_delta, min_zoom, max_zoom)
		camera.size = new_size

func find_camera_in_rig() -> Camera3D:
	if not camera_rig:
		return null
	
	# Recursively search for Camera3D in the rig hierarchy
	return find_camera_recursive(camera_rig)

func find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	
	for child in node.get_children():
		var camera = find_camera_recursive(child)
		if camera:
			return camera
	
	return null

func store_default_camera_settings():
	if not camera_rig:
		return
	
	# Store camera rig position and rotation
	default_camera_rig_position = camera_rig.global_position
	default_camera_rig_rotation = camera_rig.rotation
	
	# Store camera FOV/size
	var camera = find_camera_in_rig()
	if camera:
		if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
			default_camera_fov = camera.fov
		elif camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			default_camera_size = camera.size
	
	camera_defaults_stored = true
	print("Camera defaults stored")

func reset_camera():
	if not camera_rig or not camera_defaults_stored:
		return
	
	# Reset camera rig position and rotation
	camera_rig.global_position = default_camera_rig_position
	camera_rig.rotation = default_camera_rig_rotation
	
	# Reset camera FOV/size
	var camera = find_camera_in_rig()
	if camera:
		if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
			camera.fov = default_camera_fov
		elif camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			camera.size = default_camera_size
	
	print("Camera reset to defaults")

func handle_player_controls():	
	if not Globals.cameraNode:
		return
	
	var spaceState = get_world_3d().direct_space_state
	var mousePos : Vector2 = get_viewport().get_mouse_position()
	
	var origin : Vector3 = Globals.cameraNode.project_ray_origin(mousePos)
	var end : Vector3 = origin + Globals.cameraNode.project_ray_normal(mousePos) * 100
	var ray : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	
	ray.collide_with_bodies = true
	# Exclude dragging tower from main raycast
	if dragging_tower:
		ray.exclude = [dragging_tower]
	
	var rayResult : Dictionary = spaceState.intersect_ray(ray)
	
	var mouse_over_obj : CollisionObject3D = null
	if rayResult.size() > 0:
		mouse_over_obj = rayResult.get("collider")

	# Skip tower interactions if camera controls are active
	if is_panning or is_rotating:
		return
	
	elif Input.is_action_just_pressed("interact"):
		# Block tower placement when ChooseThree interface or tutorial is visible
		if (choose_three_container and choose_three_container.visible) or (tutorial_container and tutorial_container.visible):
			return
			
		if dragging_tower:
			stop_dragging(mouse_over_obj)
		elif mouse_over_obj and mouse_over_obj.is_in_group("emptyTile"):
			# Check if tile already has a tower
			for child in mouse_over_obj.get_children():
				if child.is_in_group("tower_line") and child is TowerLine:
					cancel_dragging()
					select_tower(child)
					return
			if dragging_tower:
				stop_dragging(mouse_over_obj)
			else:
				# Get selected tower type from dropdown
				var tower_type = get_selected_tower_type()
				var new_tower = Globals.create_tower(tower_type, mouse_over_obj)
				select_tower(new_tower)
				
				# Handle first tower placement
				if not any_tower_placed:
					any_tower_placed = true
					# Stop tower options pulsating and hide background since a tower has been placed
					stop_tower_options_pulsate()
					if tower_options_bg:
						tower_options_bg.visible = false
					# Show first tower tutorial
					show_first_tower_tutorial()
				
				# Check if collector tower was placed
				if tower_type == "collector":
					collector_tower_placed = true
					print("Collector tower placed! Disabling collector button.")
					update_progression_ui()
		elif mouse_over_obj is TowerLine:
			cancel_dragging()
			select_tower(mouse_over_obj)
		return

	elif Input.is_action_just_pressed("interact_2"):
		# Block tower interactions when ChooseThree interface or tutorial is visible
		if (choose_three_container and choose_three_container.visible) or (tutorial_container and tutorial_container.visible):
			return
			
		if dragging_tower:
			cancel_dragging()
		return
	
	elif Input.is_action_just_pressed("toggle_move"):
		# Block tower interactions when ChooseThree interface or tutorial is visible
		if (choose_three_container and choose_three_container.visible) or (tutorial_container and tutorial_container.visible):
			return
			
		if dragging_tower:
			cancel_dragging()
		elif selected_tower and is_instance_valid(selected_tower):
			start_dragging(selected_tower, selected_tower.global_position)
		return
	
	elif Input.is_action_just_pressed("cancel"):
		if dragging_tower:
			cancel_dragging()
		else:
			deselect_tower()
		return
	
	# Handle dragging if a tower is being moved
	if dragging_tower:
		# Use the main raycast result (already excludes dragging tower)
		if rayResult.size() > 0:
			var hit_pos = rayResult.position
			var hover_collider = rayResult.get("collider")
			
			# Snap to grid tile if hovering over one
			if hover_collider and hover_collider.is_in_group("emptyTile"):
				dragging_tower.global_position = Vector3(hover_collider.global_position.x, dragging_tower.global_position.y, hover_collider.global_position.z)
			else:
				# Free movement if not over a tile
				dragging_tower.global_position = Vector3(hit_pos.x, dragging_tower.global_position.y, hit_pos.z)
		return  # Don't process clicks while dragging

func select_tower(tower: TowerLine):
	# Deselect previous tower
	if selected_tower and is_instance_valid(selected_tower):
		selected_tower.hide_indicators()
	
	selected_tower = tower
	if selected_tower:
		selected_tower.show_indicators()
		print("SELECTED TOWER: ", selected_tower.tower_type)
		
		# Update tower name display and show move/delete buttons
		update_tower_name_display()
		if move_button:
			move_button.visible = true
		if delete_button:
			delete_button.visible = true
		
		# Show and animate tower controls background
		if tower_controls_bg:
			tower_controls_bg.visible = true
			start_tower_controls_pulsate()
		
		# Emit signal for UI to respond
		Globals.tower_selected.emit(selected_tower)

func deselect_tower():
	if selected_tower and is_instance_valid(selected_tower):
		selected_tower.hide_indicators()
		print("DESELECTED TOWER")
	selected_tower = null
	
	# Update tower name display (clear it) and hide move/delete buttons
	update_tower_name_display()
	if move_button:
		move_button.visible = false
	if delete_button:
		delete_button.visible = false
	
	# Hide tower controls background and stop animation
	if tower_controls_bg:
		tower_controls_bg.visible = false
		stop_tower_controls_pulsate()
	
	# Emit signal for UI to respond
	Globals.tower_deselected.emit()

func delete_selected_tower():
	if not selected_tower or not is_instance_valid(selected_tower):
		return
	
	print("DELETING TOWER: ", selected_tower.tower_type)
	
	# Check if it's a collector tower being deleted
	if selected_tower.tower_type == "collector":
		collector_tower_placed = false
		print("Collector tower deleted! Re-enabling collector button.")
		update_progression_ui()
	
	# Remove the tower from the scene
	selected_tower.queue_free()
	
	# Clear selection and update UI
	selected_tower = null
	deselect_tower()

func start_dragging(tower: TowerLine, _hit_position: Vector3):
	dragging_tower = tower
	original_parent = tower.get_parent()
	# No offset needed for spacebar toggle mode
	drag_offset = Vector3.ZERO
	print("STARTED MOVING: ", tower.tower_type)

func cancel_dragging():
	# Cancel move and return tower to original position
	if not dragging_tower:
		return
	
	print("CANCELED MOVE - RETURNING TO ORIGINAL")
	
	# Return to original position
	if original_parent and is_instance_valid(original_parent):
		dragging_tower.global_position = Vector3(original_parent.global_position.x, dragging_tower.global_position.y, original_parent.global_position.z)
	
	# Keep the tower selected
	select_tower(dragging_tower)
	
	# Clear drag state
	dragging_tower = null
	original_parent = null
	drag_offset = Vector3.ZERO

func stop_dragging(empty_tile: CollisionObject3D):
	if not dragging_tower:
		return
	
	print("CONFIRMING PLACEMENT")
	if empty_tile.is_in_group("emptyTile"):
		for child in empty_tile.get_children():
			if child.is_in_group("tower_line") and child != dragging_tower:
				cancel_dragging()
				return

		if dragging_tower.get_parent() != empty_tile:
			dragging_tower.get_parent().remove_child(dragging_tower)
			empty_tile.add_child(dragging_tower)
			dragging_tower.global_position = Vector3(empty_tile.global_position.x, dragging_tower.global_position.y, empty_tile.global_position.z)
			print("SNAPPED TO TILE")
			select_tower(dragging_tower)
	else:
		print("NOT OVER TILE - RETURNING TO ORIGINAL")
		cancel_dragging()
	
	dragging_tower = null
	original_parent = null
	drag_offset = Vector3.ZERO

# Tower option button signal handlers
func _on_mirror_option_toggled(pressed: bool):
	if pressed:
		# Unpress other buttons
		if concave_option_button:
			concave_option_button.button_pressed = false
		if convex_option_button:
			convex_option_button.button_pressed = false
		if collector_option_button:
			collector_option_button.button_pressed = false

func _on_concave_option_toggled(pressed: bool):
	if pressed:
		# Unpress other buttons
		if mirror_option_button:
			mirror_option_button.button_pressed = false
		if convex_option_button:
			convex_option_button.button_pressed = false
		if collector_option_button:
			collector_option_button.button_pressed = false

func _on_convex_option_toggled(button_pressed: bool):
	if button_pressed:
		# Deselect other buttons
		if mirror_option_button:
			mirror_option_button.button_pressed = false
		if concave_option_button:
			concave_option_button.button_pressed = false
		if collector_option_button:
			collector_option_button.button_pressed = false

func _on_collector_option_toggled(button_pressed: bool):
	if button_pressed:
		# Deselect other buttons
		if mirror_option_button:
			mirror_option_button.button_pressed = false
		if concave_option_button:
			concave_option_button.button_pressed = false
		if convex_option_button:
			convex_option_button.button_pressed = false

func _on_move_button_pressed():
	# Activate move mode (same as pressing M key)
	if dragging_tower:
		cancel_dragging()
	elif selected_tower and is_instance_valid(selected_tower):
		start_dragging(selected_tower, selected_tower.global_position)

func _on_delete_button_pressed():
	# Delete the currently selected tower
	if selected_tower and is_instance_valid(selected_tower):
		delete_selected_tower()

func update_tower_name_display():
	if not tower_name_label:
		return
	
	if selected_tower and is_instance_valid(selected_tower):
		# Display the tower type name (capitalize first letter)
		var tower_name = selected_tower.tower_type.capitalize()
		tower_name_label.text = tower_name
	else:
		# Clear the display when no tower is selected
		tower_name_label.text = ""

# Upgrade system functions
func setup_choose_three_interface():
		# Find the three panels and their labels
	for i in range(3):
		var panel = choose_three_container.get_child(i) as ColorRect
		if panel:
			print("Found panel ", i)
			upgrade_panels.append(panel)
			
			var name_label = panel.get_node_or_null("UpgradeName") as RichTextLabel
			var desc_label = panel.get_node_or_null("UpgradeDesc") as RichTextLabel
			var choose_button = panel.get_node_or_null("ChooseButton") as Button
			
			upgrade_name_labels.append(name_label)
			upgrade_desc_labels.append(desc_label)
			choose_buttons.append(choose_button)
			
			# Connect button click
			if choose_button:
				print("Connecting button ", i)
				choose_button.pressed.connect(_on_choose_button_pressed.bind(i))
			else:
				print("ERROR: ChooseButton not found in panel ", i)
	
	# Hide initially
	choose_three_container.visible = false

func setup_tutorial_interface():
	if not hud:
		print("ERROR: HUD not found for tutorial setup")
		return
	
	tutorial_container = hud.get_node_or_null("Tutorial")
	if not tutorial_container:
		print("ERROR: Tutorial container not found in HUD")
		return
	
	tutorial_title_label = tutorial_container.get_node_or_null("TutorialTitle")
	tutorial_desc_label = tutorial_container.get_node_or_null("TutorialDesc")
	tutorial_ok_button = tutorial_container.get_node_or_null("OKButton")
	
	if not tutorial_title_label:
		print("ERROR: TutorialTitle not found")
	if not tutorial_desc_label:
		print("ERROR: TutorialDesc not found")
	if not tutorial_ok_button:
		print("ERROR: OKButton not found")
	else:
		tutorial_ok_button.pressed.connect(_on_tutorial_ok_pressed)
	
	# Hide initially
	tutorial_container.visible = false

func show_upgrade_choices():
	print("show_upgrade_choices called")
	if not choose_three_container:
		print("ERROR: choose_three_container is null")
		return
	
	var available_upgrades = get_available_upgrades()
	print("Available upgrades: ", available_upgrades.size())
	available_upgrades.shuffle()
	
	# Store the shuffled upgrades for later use
	current_upgrade_choices.clear()
	for i in range(min(3, available_upgrades.size())):
		current_upgrade_choices.append(available_upgrades[i])
	
	# Show up to 3 random upgrades
	for i in range(current_upgrade_choices.size()):
		var upgrade = current_upgrade_choices[i]
		print("Setting upgrade ", i, ": ", upgrade.name)
		
		if i < upgrade_name_labels.size() and upgrade_name_labels[i]:
			upgrade_name_labels[i].text = upgrade.name
		if i < upgrade_desc_labels.size() and upgrade_desc_labels[i]:
			upgrade_desc_labels[i].text = upgrade.description
	
	print("Making ChooseThree visible")
	choose_three_container.visible = true

func get_available_upgrades() -> Array:
	var upgrades = []
	
	# Beam color upgrades (matching the actual enum order)
	var beam_descriptions = {
		"orange": "30% direct damage + applies Burn DOT (4 dmg/sec per stack)",
		"yellow": "100% damage + scatters 4 beams (40% dmg each) for AOE",
		"green": "0% direct damage + applies Poison DOT (1.5 dmg/sec per stack)",
		"cyan": "0% direct damage + applies Weakened (1.1× dmg taken per stack)",
		"blue": "0% direct damage + applies Frozen (15% slow per stack)",
		"purple": "100% damage + 50% bonus damage vs Frozen enemies"
	}
	
	var all_colors = ["orange", "yellow", "green", "cyan", "blue", "purple"]
	for color in all_colors:
		if color not in unlocked_beam_colors:
			upgrades.append({
				"name": color.capitalize() + " Beam",
				"description": beam_descriptions[color],
				"type": "beam_color",
				"value": color
			})
	
	# Tower type upgrades
	if "concave_lens" not in unlocked_tower_types:
		upgrades.append({
			"name": "Concave Lens",
			"description": "Spreads beams wider for area coverage",
			"type": "tower_type",
			"value": "concave_lens"
		})
	
	if "convex_lens" not in unlocked_tower_types:
		upgrades.append({
			"name": "Convex Lens", 
			"description": "Focuses beams for concentrated damage",
			"type": "tower_type",
			"value": "convex_lens"
		})
	
	# Ccollector tower upgrade
	if not ccollector_tower_unlocked:
		upgrades.append({
			"name": "Collector Tower",
			"description": "Enables color mixing and balance multipliers",
			"type": "ccollector_tower",
			"value": true
		})
	
	return upgrades

func _on_choose_button_pressed(panel_index: int):
	print("Button ", panel_index, " pressed!")
	apply_upgrade(panel_index)

func apply_upgrade(panel_index: int):
	print("Applying upgrade for panel ", panel_index, ", stored choices: ", current_upgrade_choices.size())
	
	if panel_index >= current_upgrade_choices.size():
		print("ERROR: Panel index out of range")
		return
	
	var upgrade = current_upgrade_choices[panel_index]
	print("Applying upgrade: ", upgrade.name, " (", upgrade.type, ")")
	
	match upgrade.type:
		"beam_color":
			unlocked_beam_colors.append(upgrade.value)
			print("Unlocked ", upgrade.value, " beam. Total unlocked colors: ", unlocked_beam_colors)
			# Refresh beams to add new color
			refresh_beams()
		"tower_type":
			unlocked_tower_types.append(upgrade.value)
			print("Unlocked ", upgrade.value, " tower. Total unlocked towers: ", unlocked_tower_types)
		"ccollector_tower":
			ccollector_tower_unlocked = true
			print("Unlocked ccollector tower")
			# Show collector tutorial when unlocked
			show_collector_tutorial()
	
	# Update UI to reflect new unlocks
	update_progression_ui()
	
	# Hide upgrade interface
	choose_three_container.visible = false

func update_progression_ui():
	# Update tower option buttons based on unlocked types
	if concave_option_button:
		concave_option_button.disabled = "concave_lens" not in unlocked_tower_types
	if convex_option_button:
		convex_option_button.disabled = "convex_lens" not in unlocked_tower_types
	if collector_option_button:
		collector_option_button.disabled = not ccollector_tower_unlocked or collector_tower_placed
	
	# Hide/show color ratio bar based on ccollector tower unlock AND placement
	if color_ratio_box:
		color_ratio_box.visible = ccollector_tower_unlocked and collector_tower_placed

func refresh_beams():
	print("Refreshing beams with new unlocked colors...")
	# Get the board and tell it to refresh its beams
	if level and level.board:
		level.board.refresh_beams_for_unlocked_colors()

func _on_wave_completed():
	print("Wave completed! Showing upgrade choices...")
	# Show upgrade choices after each wave
	show_upgrade_choices()

# Tutorial system functions
func _on_tutorial_ok_pressed():
	if tutorial_container:
		tutorial_container.visible = false

func show_tutorial(title: String, description: String):
	if not tutorial_container or not tutorial_title_label or not tutorial_desc_label:
		print("ERROR: Tutorial UI not properly initialized")
		return
	
	tutorial_title_label.text = title
	tutorial_desc_label.text = description
	tutorial_container.visible = true

func show_game_start_tutorial():
	if tutorial_shown["game_start"]:
		return
	
	tutorial_shown["game_start"] = true
	show_tutorial(
		"Welcome to Light Tower Defense!",
		"Use mirrors to redirect the red laser beam and hit enemies. Click on empty tiles to place mirror towers. Press A key to activate the red beam and start defending!"
	)

func show_first_tower_tutorial():
	if tutorial_shown["first_tower"]:
		return
	
	tutorial_shown["first_tower"] = true
	show_tutorial(
		"Tower Controls",
		"Great! You placed your first tower. You can select towers by clicking on them, then use the controls in the bottom right to rotate them. You can also press M key to move towers to different positions."
	)

func show_collector_tutorial():
	if tutorial_shown["collector_unlock"]:
		return
	
	tutorial_shown["collector_unlock"] = true
	show_tutorial(
		"Collector Tower Unlocked!",
		"The Collector Tower absorbs light beams that hit it. Different beam colors create a color ratio that provides damage multipliers - the more balanced your colors, the higher your damage bonus! Place it strategically to collect multiple beam colors."
	)

# Tower controls background animation
func start_tower_controls_pulsate():
	if not tower_controls_bg:
		return
	
	# Stop any existing animation
	stop_tower_controls_pulsate()
	
	# Create a gentle pulsating tween animation
	tower_controls_tween = create_tween()
	tower_controls_tween.set_loops()  # Loop indefinitely
	
	# Animate modulate alpha from 1.0 to 0.0 and back
	tower_controls_tween.tween_property(tower_controls_bg, "modulate:a", 0., 1.0)
	tower_controls_tween.tween_property(tower_controls_bg, "modulate:a", 1., 1.0)

func stop_tower_controls_pulsate():
	if not tower_controls_bg:
		return
	
	# Kill the specific tween if it exists
	if tower_controls_tween and tower_controls_tween.is_valid():
		tower_controls_tween.kill()
		tower_controls_tween = null
	
	# Reset to full opacity
	tower_controls_bg.modulate.a = 1.0

# Tower options background animation
func start_tower_options_pulsate():
	if not tower_options_bg:
		return
	
	# Stop any existing animation
	stop_tower_options_pulsate()
	
	# Create a gentle pulsating tween animation
	tower_options_tween = create_tween()
	tower_options_tween.set_loops()  # Loop indefinitely
	
	# Animate modulate alpha from 1.0 to 0.0 and back
	tower_options_tween.tween_property(tower_options_bg, "modulate:a", 0., 1.0)
	tower_options_tween.tween_property(tower_options_bg, "modulate:a", 1., 1.0)

func stop_tower_options_pulsate():
	if not tower_options_bg:
		return
	
	# Kill the specific tween if it exists
	if tower_options_tween and tower_options_tween.is_valid():
		tower_options_tween.kill()
		tower_options_tween = null
	
	# Reset to full opacity
	tower_options_bg.modulate.a = 1.0
