extends Node3D


### I usually put variables that are accessible anywhere in this global autoload (singleton) 

### eg player health, anything you want displayed on the HUD like wave or enemy count 
@onready var cameraNode 
@onready var mirrorTower : PackedScene = preload("res://scenes/towers/mirror.tscn")
@onready var convexLensTower : PackedScene = preload("res://scenes/towers/convex_lens.tscn")
@onready var concaveLensTower : PackedScene = preload("res://scenes/towers/concave_lens.tscn")

var right_mouse_was_pressed: bool = false



func _ready() -> void:
	pass 
	
func _process(delta: float) -> void:
	handlePlayerControls()

### handle the player movement and input here since there is no player controller per se 

func handlePlayerControls():
	
	if !cameraNode: return
	
	var spaceState = get_world_3d().direct_space_state 
	var mousePos : Vector2 = get_viewport().get_mouse_position()
	
	var origin : Vector3 = cameraNode.project_ray_origin(mousePos)
	var end : Vector3 = origin + cameraNode.project_ray_normal(mousePos) * 100
	var ray : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	
	ray.collide_with_bodies = true 
	
	var rayResult : Dictionary = spaceState.intersect_ray(ray)
	
	if rayResult.size() > 0: 
		var collider : CollisionObject3D = rayResult.get("collider")
		
		# Check if clicking directly on a tower
		if collider is TowerLine:
			var right_mouse_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			if right_mouse_pressed and not right_mouse_was_pressed:
				# Right click on tower: cycle lens types (only works on lenses)
				if collider.tower_type == "convex_lens":
					collider.tower_type = "concave_lens"
					print("SWITCHED TO CONCAVE LENS")
				elif collider.tower_type == "concave_lens":
					collider.tower_type = "convex_lens"
					print("SWITCHED TO CONVEX LENS")
			right_mouse_was_pressed = right_mouse_pressed
			return
		
		elif collider.is_in_group("emptyTile"):
			# Check if tile has a tower
			var tower_on_tile = null
			for child in collider.get_children():
				if child.is_in_group("tower_line") and child is TowerLine:
					tower_on_tile = child
					break
			
			# Handle right click
			var right_mouse_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			if right_mouse_pressed and not right_mouse_was_pressed:
				if tower_on_tile:
					# Right click on existing tower: cycle lens types (only works on lenses)
					if tower_on_tile.tower_type == "convex_lens":
						tower_on_tile.tower_type = "concave_lens"
						print("SWITCHED TO CONCAVE LENS")
					elif tower_on_tile.tower_type == "concave_lens":
						tower_on_tile.tower_type = "convex_lens"
						print("SWITCHED TO CONVEX LENS")
					# If it's a mirror, do nothing on right-click
				else:
					# No tower exists: place convex lens
					print("PLACING CONVEX LENS")
					var newTower = convexLensTower.instantiate()
					collider.add_child(newTower)
					newTower.global_position = collider.global_position + Vector3(0,0.2,0)
					newTower.rotation.y = randf() * TAU
					newTower.add_to_group("tower_line")
					if newTower.has_method("set") and "tower_type" in newTower:
						newTower.tower_type = "convex_lens"
			
			# Block placement if tower already exists
			if tower_on_tile:
				right_mouse_was_pressed = right_mouse_pressed
				return  # Don't place another tower
			
			# Left click for mirror
			if Input.is_action_just_pressed("interact"):
				print("PLACING MIRROR")
				var newTower = mirrorTower.instantiate()
				collider.add_child(newTower)
				newTower.global_position = collider.global_position + Vector3(0,0.2,0)
				newTower.rotation.y = randf() * TAU
				newTower.add_to_group("tower_line")
				# Mirror tower has default tower_type = "mirror"
			
			# Update right mouse state at end
			right_mouse_was_pressed = right_mouse_pressed
				
