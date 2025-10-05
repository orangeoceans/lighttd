extends Node3D


### I usually put variables that are accessible anywhere in this global autoload (singleton) 

### eg player health, anything you want displayed on the HUD like wave or enemy count 
@onready var cameraNode 
@onready var mirrorTower : PackedScene = preload("res://scenes/towers/mirror.tscn")
@onready var convexLensTower : PackedScene = preload("res://scenes/towers/convex_lens.tscn")

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
		
		if collider.is_in_group("emptyTile"):
			# Left click for mirror
			if Input.is_action_just_pressed("interact"):
				print("PLACING MIRROR")
				var newTower = mirrorTower.instantiate()
				collider.add_child(newTower)
				newTower.global_position = collider.global_position + Vector3(0,0.2,0)
				newTower.rotation.y = randf() * TAU
				newTower.add_to_group("tower_line")
				# Mirror tower has default tower_type = "mirror"
			
			# Right click for convex lens
			var right_mouse_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			if right_mouse_pressed and not right_mouse_was_pressed:
				print("PLACING CONVEX LENS")
				var newTower = convexLensTower.instantiate()
				collider.add_child(newTower)
				newTower.global_position = collider.global_position + Vector3(0,0.2,0)
				newTower.rotation.y = randf() * TAU
				newTower.add_to_group("tower_line")
				# Set tower type to convex_lens
				if newTower.has_method("set") and "tower_type" in newTower:
					newTower.tower_type = "convex_lens"
			right_mouse_was_pressed = right_mouse_pressed
				
