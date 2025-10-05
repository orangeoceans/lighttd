extends Node3D

# Player input and tower interaction controller

@export var hud: Control

# State tracking
var right_mouse_was_pressed: bool = false
var dragging_tower: TowerLine = null
var drag_offset: Vector3 = Vector3.ZERO
var original_parent: Node = null

var selected_tower: TowerLine = null

# UI References
var tower_option_dropdown: OptionButton = null

func _ready():
	# Find the tower type dropdown from HUD
	if hud:
		tower_option_dropdown = hud.get_node_or_null("TowerBar/TowerOption")
		if not tower_option_dropdown:
			print("WARNING: TowerOption dropdown not found in HUD")
	else:
		print("WARNING: HUD reference not set in PlayerController")

func _process(_delta: float) -> void:
	handle_player_controls()

func get_selected_tower_type() -> String:
	if not tower_option_dropdown:
		return "mirror" 
	
	var selected_idx = tower_option_dropdown.selected
	match selected_idx:
		0:
			return "mirror"
		1:
			return "concave_lens"
		2:
			return "convex_lens"
		_:
			return "mirror"

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
				dragging_tower.global_position = hover_collider.global_position + Vector3(0, 0.2, 0)
			else:
				# Free movement if not over a tile
				dragging_tower.global_position = Vector3(hit_pos.x, dragging_tower.global_position.y, hit_pos.z)
		return  # Don't process clicks while dragging

func select_tower(tower: TowerLine):
	# Deselect previous tower
	if selected_tower and is_instance_valid(selected_tower):
		selected_tower.hide_indicators()
	
	# Select new tower
	selected_tower = tower
	if selected_tower:
		selected_tower.show_indicators()
		print("SELECTED TOWER: ", selected_tower.tower_type)
		# Emit signal for UI to respond
		Globals.tower_selected.emit(selected_tower)

func deselect_tower():
	if selected_tower and is_instance_valid(selected_tower):
		selected_tower.hide_indicators()
		print("DESELECTED TOWER")
	selected_tower = null
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
		dragging_tower.global_position = original_parent.global_position + Vector3(0, 0.2, 0)
	
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
			dragging_tower.global_position = empty_tile.global_position + Vector3(0, 0.2, 0)
			print("SNAPPED TO TILE")
			select_tower(dragging_tower)
	else:
		print("NOT OVER TILE - RETURNING TO ORIGINAL")
		cancel_dragging()
	
	dragging_tower = null
	original_parent = null
	drag_offset = Vector3.ZERO
