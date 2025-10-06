extends Node3D

# Player input and tower interaction controller

@export var hud: Control
@export var level: Level
@export var camera_rig: Node3D
@export var max_active_beams: int = 2  # Maximum number of beams that can be active at once

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
var move_button: Button = null
var tower_name_label: RichTextLabel = null

func _ready():
	# Add to group for HUD to find
	add_to_group("player_controller")
	
	# Find the tower option buttons from HUD
	if hud:
		tower_option_control = hud.get_node_or_null("TopBar/TowerOption")
		if tower_option_control:
			mirror_option_button = tower_option_control.get_node_or_null("MirrorOption")
			concave_option_button = tower_option_control.get_node_or_null("ConcaveOption")
			convex_option_button = tower_option_control.get_node_or_null("ConvexOption")
			
			# Connect button signals
			if mirror_option_button:
				mirror_option_button.toggled.connect(_on_mirror_option_toggled)
			if concave_option_button:
				concave_option_button.toggled.connect(_on_concave_option_toggled)
			if convex_option_button:
				convex_option_button.toggled.connect(_on_convex_option_toggled)
		else:
			print("WARNING: TowerOption control not found in HUD")
		
		# Find and connect MoveButton
		move_button = hud.get_node_or_null("TowerControls/MoveButton")
		if move_button:
			move_button.pressed.connect(_on_move_button_pressed)
		else:
			print("WARNING: MoveButton not found in HUD")
		
		# Find TowerName label
		tower_name_label = hud.get_node_or_null("TowerControls/TowerName")
		if not tower_name_label:
			print("WARNING: TowerName label not found in HUD")
	else:
		print("WARNING: HUD reference not set in PlayerController")

func _process(_delta):
	# Store default camera settings on first frame
	if not camera_defaults_stored and camera_rig:
		store_default_camera_settings()
	handle_beam_activation()
	handle_camera_controls()
	handle_player_controls()

func get_selected_tower_type() -> String:
	# Check which button is pressed
	if mirror_option_button and mirror_option_button.button_pressed:
		return "mirror"
	elif concave_option_button and concave_option_button.button_pressed:
		return "concave_lens"
	elif convex_option_button and convex_option_button.button_pressed:
		return "convex_lens"
	return "mirror"  # Default fallback

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
	
	if Input.is_action_just_pressed("interact"):
		if mouse_over_obj and mouse_over_obj.is_in_group("emptyTile"):
			print(mouse_over_obj.get_children())
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
				select_tower(Globals.create_tower(tower_type, mouse_over_obj))
		elif mouse_over_obj is TowerLine:
			cancel_dragging()
			select_tower(mouse_over_obj)
		return

	elif Input.is_action_just_pressed("interact_2"):
		if dragging_tower:
			cancel_dragging()
		return
	
	elif Input.is_action_just_pressed("toggle_move"):
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
		
		# Update tower name display
		update_tower_name_display()
		
		# Emit signal for UI to respond
		Globals.tower_selected.emit(selected_tower)

func deselect_tower():
	if selected_tower and is_instance_valid(selected_tower):
		selected_tower.hide_indicators()
		print("DESELECTED TOWER")
	selected_tower = null
	
	# Update tower name display (clear it)
	update_tower_name_display()
	
	# Emit signal for UI to respond
	Globals.tower_deselected.emit()

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

func _on_concave_option_toggled(pressed: bool):
	if pressed:
		# Unpress other buttons
		if mirror_option_button:
			mirror_option_button.button_pressed = false
		if convex_option_button:
			convex_option_button.button_pressed = false

func _on_convex_option_toggled(pressed: bool):
	if pressed:
		# Unpress other buttons
		if mirror_option_button:
			mirror_option_button.button_pressed = false
		if concave_option_button:
			concave_option_button.button_pressed = false

func _on_move_button_pressed():
	# Activate move mode (same as pressing M key)
	if dragging_tower:
		cancel_dragging()
	elif selected_tower and is_instance_valid(selected_tower):
		start_dragging(selected_tower, selected_tower.global_position)

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
