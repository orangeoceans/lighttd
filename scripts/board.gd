
extends Node3D
class_name Board

###


@export var hex_size: float = 1.0                 # center -> corner radius
@export var buildable_scene: PackedScene          # for '.' grass/buildable
@export var road_scene: PackedScene               # for 'R' road tiles
@export var spawn_scene: PackedScene              # for 'S'
@export var goal_scene: PackedScene               # for 'G'
@onready var scenePath: Path3D = $Path3D


###


@onready var mirrorTower : PackedScene = preload("res://scenes/towers/mirror.tscn")

@onready var camera = Globals.cameraNode

@onready var beam : PackedScene = preload("res://scenes/beam.tscn")

# Background tower scenes
@onready var bg_tower_scenes: Array[PackedScene] = [
	preload("res://scenes/towers/bg_tower_1.tscn"),
	preload("res://scenes/towers/bg_tower_2.tscn"),
	preload("res://scenes/towers/bg_tower_3.tscn"),
	preload("res://scenes/towers/bg_tower_4.tscn")
]

# Light ray system - support for 7 rays
const NUM_RAYS: int = 7
var beams: Array[Beam] = []  # Store all beam instances
var beam_start_positions: Array[Vector3] = []
var beam_directions: Array[Vector2] = []


func _ready() -> void:
	# Add to board group so HUD can find it
	add_to_group("board")
	
	var map := [
	
	".............",
	".............",
	"SRR.......RRG",
	"..R......R...",
	"...RRRR..R...",
	"......RRR....",
	".............",
	".............",
	]	
	setUpBoard(map)
	
	# Generate background layer after main board
	generate_background_layer(map)

func setUpBoard(rows: Array) -> void:
	_clear_kids()

	var tiles_root := Node3D.new()
	tiles_root.name = "Tiles"
	add_child(tiles_root)
	
	var beam_keys = [KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J]

	var w = rows[0].length()
	var h := rows.size()

	var spawn := Vector2i(-1, -1)
	var goal  := Vector2i(-1, -1)

	# 1) Drop tiles in a perfect hex lattice (pointy-top, odd-r offset)
	for r in h:
		var line: String = rows[r]
		for c in w:
			var ch := line[c]
			var pos := _hex_center(c, r)  # XZ plane, Y up

			match ch:
				'S':
					if spawn_scene:
						var s = spawn_scene.instantiate() as Node3D
						s.position = pos
						tiles_root.add_child(s)
					if road_scene:
						var rs = road_scene.instantiate() as Node3D
						rs.position = pos
						tiles_root.add_child(rs)
					spawn = Vector2i(c, r)
					scenePath.global_position = Vector3(spawn.x, spawn.y-1, 0)
				'G':
					if goal_scene:
						var g = goal_scene.instantiate() as Node3D
						g.position = pos
						tiles_root.add_child(g)
					if road_scene:
						var rg = road_scene.instantiate() as Node3D
						rg.position = pos
						tiles_root.add_child(rg)
					goal = Vector2i(c, r)
				'R':
					if road_scene:
						var rhex = road_scene.instantiate() as Node3D
						rhex.position = pos
						tiles_root.add_child(rhex)
				'#':
					if buildable_scene:
						var blocked = buildable_scene.instantiate() as Node3D
						# Add slight random height variation
						var height_variation = randf_range(-0.2, 0.2) + 5
						blocked.position = pos + Vector3(0, height_variation, 0)
						tiles_root.add_child(blocked)
				'.':
					if buildable_scene:
						var gnd = buildable_scene.instantiate() as Node3D
						# Add slight random height variation
						var height_variation = randf_range(-0.2, 0.2)
						gnd.position = pos + Vector3(0, height_variation, 0)
						tiles_root.add_child(gnd)
				_:
					# Unknown symbol: skip silently for jam speed
					pass

	# 2) Trace the road by walking neighbors from S to G (no branches)
	if spawn.x == -1 or goal.x == -1:
		push_warning("Map must contain one 'S' and one 'G'.")
		return

	var path_points := PackedVector3Array()
	var cur := spawn
	var prev := Vector2i(-999, -999)
	var guard = w * h + 8  # loop guard

	path_points.append(_hex_center(cur.x, cur.y))

	while cur != goal and guard > 0:
		guard -= 1
		var nexts := _road_neighbors(cur, rows)
		# Prefer not going back to where we came from
		var chosen := Vector2i(-1, -1)
		for n in nexts:
			if n != prev:
				chosen = n
				break
		if chosen == Vector2i(-1, -1):
			# Dead end or loop; bail
			push_warning("Road trace failed (branching or break). Ensure a single continuous path.")
			return
		prev = cur
		cur = chosen
		path_points.append(_hex_center(cur.x, cur.y))

	if cur != goal:
		push_warning("Could not reach 'G' from 'S'.")
		return

	# 3) Conjure a Path3D from the traced centers
	var curve := Curve3D.new()
	for p in path_points:
		curve.add_point(p)
	curve.bake_interval = hex_size * 0.25


	scenePath.name = "EnemyPath"
	scenePath.curve = curve
	
	# Collector tower will be placed manually by player when unlocked
	# place_collector_tower(rows, goal, tiles_root)
	
	# Create light beams only for unlocked colors
	var player_controller = get_tree().get_first_node_in_group("player_controller")
	var unlocked_colors = ["red"]  # Default fallback
	if player_controller:
		unlocked_colors = player_controller.unlocked_beam_colors
	
	var beam_index = 0
	for i in range(NUM_RAYS):
		var beam_color_enum = i as Globals.BeamColor
		var color_name = get_color_name_from_enum(beam_color_enum)
		
		# Only create beam if color is unlocked
		if color_name in unlocked_colors:
			var board_height = rows.size() * hex_size * 1.5
			var beam_y = 1  # Slightly above ground
			var spacing_vertical = board_height / float(NUM_RAYS + 1)
			var start_z = spacing_vertical * (beam_index + 1)

			var beam_instance := beam.instantiate()
			beam_instance.initialize(self, beam_color_enum, Vector3(0.0, beam_y, start_z), Vector2(1, 0), beam_keys[beam_index])
			add_child(beam_instance)
			beams.append(beam_instance)
			beam_index += 1

func get_color_name_from_enum(beam_color_enum: Globals.BeamColor) -> String:
	match beam_color_enum:
		Globals.BeamColor.RED:
			return "red"
		Globals.BeamColor.ORANGE:
			return "orange"
		Globals.BeamColor.YELLOW:
			return "yellow"
		Globals.BeamColor.GREEN:
			return "green"
		Globals.BeamColor.CYAN:
			return "cyan"
		Globals.BeamColor.BLUE:
			return "blue"
		Globals.BeamColor.PURPLE:
			return "purple"
		_:
			return "red"  # Default fallback

func refresh_beams_for_unlocked_colors():
	print("Board: Refreshing beams for unlocked colors")
	
	# Get current unlocked colors from player controller
	var player_controller = get_tree().get_first_node_in_group("player_controller")
	if not player_controller:
		print("ERROR: Could not find player controller")
		return
	
	var unlocked_colors = player_controller.unlocked_beam_colors
	print("Current unlocked colors: ", unlocked_colors)
	
	# Remove all existing beams
	for beam_instance in beams:
		if is_instance_valid(beam_instance):
			beam_instance.queue_free()
	beams.clear()
	
	# Define beam keys (same as in setUpBoard)
	var beam_keys = [KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J]
	
	# Recreate beams for unlocked colors only
	var beam_index = 0
	for i in range(NUM_RAYS):
		var beam_color_enum = i as Globals.BeamColor
		var color_name = get_color_name_from_enum(beam_color_enum)
		
		# Only create beam if color is unlocked
		if color_name in unlocked_colors:
			var board_height = 8 * hex_size * 1.5  # Assuming 8 rows like in original setup
			var beam_y = 1  # Slightly above ground
			var spacing_vertical = board_height / float(NUM_RAYS + 1)
			var start_z = spacing_vertical * (beam_index + 1)

			var beam_instance := beam.instantiate()
			beam_instance.initialize(self, beam_color_enum, Vector3(0.0, beam_y, start_z), Vector2(1, 0), beam_keys[beam_index])
			add_child(beam_instance)
			beams.append(beam_instance)
			beam_index += 1
			print("Created beam for color: ", color_name)
	
	print("Beam refresh complete. Total beams: ", beams.size())
	
# ===== Helpers: pointy-top, odd-r layout =====
func _hex_center(col: int, row: int) -> Vector3:
	# Pointy-top hex spacing:
	# horizontal step = sqrt(3) * size
	# vertical step   = 1.5 * size
	var x := hex_size * sqrt(3.0) * (col + 0.5 * (row & 1))
	var z := hex_size * 1.5 * row
	return Vector3(x, 0.0, z)



func _road_neighbors(p: Vector2i, rows: Array) -> Array[Vector2i]:
	var w = rows[0].length()
	var h := rows.size()
	var r := p.y
	var c := p.x
	var odd := (r & 1) == 1

	# odd-r neighbor sets
	var deltas_even := [Vector2i(+1,0), Vector2i(0,-1), Vector2i(-1,-1), Vector2i(-1,0), Vector2i(-1,+1), Vector2i(0,+1)]
	var deltas_odd  := [Vector2i(+1,0), Vector2i(+1,-1), Vector2i(0,-1), Vector2i(-1,0), Vector2i(0,+1), Vector2i(+1,+1)]
	var deltas :=  deltas_odd if odd else deltas_even

	var out: Array[Vector2i] = []
	for d in deltas:
		var nc = c + d.x
		var nr = r + d.y
		if nc >= 0 and nc < w and nr >= 0 and nr < h:
			var ch := (rows[nr] as String)[nc]
			if ch == 'R' or ch == 'S' or ch == 'G':
				out.append(Vector2i(nc, nr))
	return out

func place_collector_tower(rows: Array, goal: Vector2i, tiles_root: Node3D) -> void:
	# Only place if one doesn't already exist
	print("PLACING COLLECTOR")
	if Globals.collector_tower_instance and is_instance_valid(Globals.collector_tower_instance):
		return
	print("PLACING COLLECTOR 2")
	
	var w = rows[0].length()
	var h := rows.size()
	var r := goal.y
	var c := goal.x
	var odd := (r & 1) == 1
	
	# Get all neighbors around the goal
	var deltas_even := [Vector2i(+1,0), Vector2i(0,-1), Vector2i(-1,-1), Vector2i(-1,0), Vector2i(-1,+1), Vector2i(0,+1)]
	var deltas_odd  := [Vector2i(+1,0), Vector2i(+1,-1), Vector2i(0,-1), Vector2i(-1,0), Vector2i(0,+1), Vector2i(+1,+1)]
	var deltas :=  deltas_odd if odd else deltas_even
	
	# Find a buildable tile (.) near the goal
	var collector_tile = null
	for d in deltas:
		var nc = c + d.x
		var nr = r + d.y
		if nc >= 0 and nc < w and nr >= 0 and nr < h:
			var ch := (rows[nr] as String)[nc]
			if ch == '.':
				# Find the actual tile node (compare only XZ, ignore Y height)
				for tile in tiles_root.get_children():
					var tile_pos = _hex_center(nc, nr)
					var tile_xz = Vector2(tile.position.x, tile.position.z)
					var target_xz = Vector2(tile_pos.x, tile_pos.z)
					if tile_xz.distance_to(target_xz) < 0.1:
						collector_tile = tile
						break
				if collector_tile:
					break
	
	# Place collector tower if we found a suitable tile
	if collector_tile:
		print("PLACING COLLECTOR 3")
		for child in collector_tile.get_node("BasicTile").get_children():
			if child.is_in_group("emptyTile"):
				Globals.create_tower("collector", child)
				print("PLACED COLLECTOR")
				break


func _clear_kids() -> void: ### the IDF is interested in this one 
	for child in get_children():
		if is_instance_valid(scenePath) and child == scenePath:
			# Optional: reset its curve so it's clean for the next run
			scenePath.curve = Curve3D.new()
			continue
		child.queue_free()
	
	# Clear ray arrays
	beams.clear()
	beam_start_positions.clear()
	beam_directions.clear()
	
	# Reset collector tower reference and beam counts
	Globals.collector_tower_instance = null
	Globals.collector_beam_counts.clear()
	
	# Initialize all beam colors to equal values
	var equal_value = Globals.collector_total_count / 7.0
	for i in range(Globals.BeamColor.size()):
		var beam_color_enum = i as Globals.BeamColor
		Globals.collector_beam_counts[beam_color_enum] = equal_value

# Generate background layer with towers and empty tiles
func generate_background_layer(rows: Array) -> void:
	print("Generating background layer...")
	
	# Create background layer container
	var bg_layer := Node3D.new()
	bg_layer.name = "BackgroundLayer"
	add_child(bg_layer)
	
	# Add pink layer under the game board
	add_pink_layer()
	
	var w = rows[0].length()
	var h := rows.size()
	
	# Background layer settings
	var bg_y_offset: float = -12.0  # Place background layer much further below main tiles (at least twice as far)
	var tower_spawn_chance: float = 0.2  # 20% chance for a tower, 80% for empty (lower density for larger area)
	var bg_expansion: int = 27  # Expand background grid by this many tiles in each direction (9x wider)
	
	# Generate background tiles for expanded area
	for r in range(-bg_expansion, h + bg_expansion):
		for c in range(-bg_expansion, w + bg_expansion):
			var pos := _hex_center(c, r)
			pos.y += bg_y_offset  # Lower the background layer
			
			# Always place a background tile first (if buildable_scene exists)
			if buildable_scene:
				var bg_tile = buildable_scene.instantiate() as Node3D
				bg_tile.position = pos
				# Add slight random height variation for background tiles
				var tile_height_variation = randf_range(-0.3, 0.3)
				bg_tile.position.y += tile_height_variation
				# Make background tile non-interactive
				make_non_interactive(bg_tile)
				bg_layer.add_child(bg_tile)
			
			# Then randomly decide if this position gets a tower on top
			if randf() < tower_spawn_chance:
				# Place a random background tower
				var tower_scene = bg_tower_scenes[randi() % bg_tower_scenes.size()]
				var tower_instance = tower_scene.instantiate() as Node3D
				
				# Set position (slightly above the background tile)
				tower_instance.position = pos
				tower_instance.position.y += 0.2  # Raise tower slightly above background tile
				
				# Random rotation in 90-degree increments (0, 90, 180, 270 degrees)
				var rotation_steps = randi() % 4  # 0, 1, 2, or 3
				var rotation_angle = rotation_steps * PI / 2.0  # Convert to radians
				tower_instance.rotation.y = rotation_angle
				
				# Add some random height variation for visual interest
				var height_variation = randf_range(-0.1, 0.1)
				tower_instance.position.y += height_variation
				
				# Make background tower non-interactive
				make_non_interactive(tower_instance)
				bg_layer.add_child(tower_instance)
				
				# Debug output
				print("Placed bg_tower at (", c, ", ", r, ") with rotation ", rotation_steps * 90, " degrees")
	
	print("Background layer generation complete!")

# Add a semi-opaque pink layer under the game board
func add_pink_layer() -> void:
	print("Adding pink layer under game board...")
	
	# Create a large pink plane underneath the game board
	var pink_layer := MeshInstance3D.new()
	pink_layer.name = "PinkLayer"
	
	# Create a large plane mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(100.0, 100.0)  # Large enough to cover the entire area
	pink_layer.mesh = plane_mesh
	
	# Create pink semi-transparent material
	var pink_material = StandardMaterial3D.new()
	pink_material.albedo_color = Color(1.0, 0.7, 0.8, 0.3)  # Semi-opaque pink
	pink_material.flags_transparent = true
	pink_material.flags_unshaded = true  # Flat color, no lighting
	pink_material.no_depth_test = false
	pink_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	
	pink_layer.material_override = pink_material
	
	# Position the pink layer between background and game board
	pink_layer.position = Vector3(0, -6.0, 0)  # Halfway between game board (0) and background (-12)
	pink_layer.rotation.x = 0  # Flat horizontal plane
	
	# Make it non-interactive
	make_non_interactive(pink_layer)
	
	add_child(pink_layer)
	print("Pink layer added successfully!")

# Recursively apply material to all MeshInstance3D nodes
func apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		mesh_instance.material_override = material
	
	for child in node.get_children():
		apply_material_recursive(child, material)

# Make a node and all its children non-interactive
func make_non_interactive(node: Node) -> void:
	# Disable collision layers for physics bodies
	if node is RigidBody3D:
		var rigid_body = node as RigidBody3D
		rigid_body.collision_layer = 0
		rigid_body.collision_mask = 0
		rigid_body.freeze = true
	elif node is StaticBody3D:
		var static_body = node as StaticBody3D
		static_body.collision_layer = 0
		static_body.collision_mask = 0
	elif node is CharacterBody3D:
		var char_body = node as CharacterBody3D
		char_body.collision_layer = 0
		char_body.collision_mask = 0
	elif node is Area3D:
		var area = node as Area3D
		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
	
	# Disable input processing
	if node is Control:
		var control = node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif node is CollisionObject3D:
		var collision_obj = node as CollisionObject3D
		collision_obj.input_ray_pickable = false
	
	# Recursively apply to all children
	for child in node.get_children():
		make_non_interactive(child)
