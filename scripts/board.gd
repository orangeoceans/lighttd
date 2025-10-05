
extends Node3D

class_name Board



###


@export var hex_size: float = 1.05                 # center -> corner radius
@export var buildable_scene: PackedScene          # for '.' grass/buildable
@export var road_scene: PackedScene               # for 'R' road tiles
@export var spawn_scene: PackedScene              # for 'S'
@export var goal_scene: PackedScene               # for 'G'
@onready var scenePath: Path3D = $Path3D


###


@onready var basicEnemy : PackedScene = preload("res://scenes/enemies/basicEnemy.tscn")

var enemiesToSpawn : int = 3 ### number of enemies to spawn per round

var canSpawnEnemiesCooldown : bool = true; 

@onready var spawn_timer: Timer = $"../utilities/spawnTimer"
@onready var mirrorTower : PackedScene = preload("res://scenes/towers/mirror.tscn")

@onready var camera = Globals.cameraNode

# Light ray system - support for 7 rays
const NUM_RAYS: int = 7
var light_beam_meshes: Array[ImmediateMesh] = []
var beam_start_positions: Array[Vector3] = []
var beam_directions: Array[Vector2] = []
var beam_colors: Array[Color] = []

# Light ray tracing variables
var max_ray_length: float = 2000.0
var max_bounces: int = 20
var initial_beam_width: float = 0.3
var min_beam_width: float = 0.05  # Minimum beam width (never thinner)
var max_beam_width: float = 1.2  # Maximum beam width (never wider)
var convex_lens_multiplier: float = 0.5  # Each convex lens narrows beam to 50% of current width
var concave_lens_multiplier: float = 1.5  # Each concave lens widens beam to 150% of current width



func _ready() -> void:
	
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




func _process (_delta):
	spawner()
	# Update all light rays
	for i in range(NUM_RAYS):
		update_light_ray(i)





func spawner() -> void:
	if enemiesToSpawn > 0 and canSpawnEnemiesCooldown:
		spawn_timer.start()
		var currentEnemy = basicEnemy.instantiate()
		# Safety: ensure scenePath exists and is valid
		if !is_instance_valid(scenePath):
			# Recreate it if you ever change _clear_kids() again
			scenePath = Path3D.new()
			scenePath.name = "EnemyPath"
			add_child(scenePath)
		scenePath.add_child(currentEnemy)  # now safe
		enemiesToSpawn -= 1
		canSpawnEnemiesCooldown = false



func _on_spawn_timer_timeout() -> void:
	canSpawnEnemiesCooldown = true



	
func setUpBoard(rows: Array) -> void:
	_clear_kids()

	var tiles_root := Node3D.new()
	tiles_root.name = "Tiles"
	add_child(tiles_root)
	
	# Define colors for each ray (rainbow spectrum)
	var ray_colors = [
		Color(1.0, 0.0, 0.0),  # Red
		Color(1.0, 0.5, 0.0),  # Orange
		Color(1.0, 1.0, 0.0),  # Yellow
		Color(0.0, 1.0, 0.0),  # Green
		Color(0.0, 1.0, 1.0),  # Cyan
		Color(0.0, 0.0, 1.0),  # Blue
		Color(0.5, 0.0, 1.0),  # Purple
	]
	
	# Create all light beams
	for i in range(NUM_RAYS):
		var light_beam := Node3D.new()
		light_beam.name = "LightBeam" + str(i)
		
		var beam_line := MeshInstance3D.new()
		beam_line.name = "BeamLine" + str(i)
		
		var mesh := ImmediateMesh.new()
		beam_line.mesh = mesh
		
		var ray_color = ray_colors[i]
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = ray_color
		material.emission_enabled = true
		material.emission = ray_color
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		beam_line.material_override = material
		
		light_beam.add_child(beam_line)
		add_child(light_beam)
		light_beam_meshes.append(mesh)
		beam_colors.append(ray_color)

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
						blocked.position = pos
						tiles_root.add_child(blocked)
				'.':
					if buildable_scene:
						var gnd = buildable_scene.instantiate() as Node3D
						gnd.position = pos
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
	
	# Initialize beam starting positions and directions
	var board_height = h * hex_size * 1.5
	var beam_y = 0.5  # Slightly above ground
	
	# Distribute rays evenly across the left edge, shooting right
	var spacing_vertical = board_height / float(NUM_RAYS + 1)
	for i in range(NUM_RAYS):
		# Start from left side, evenly spaced vertically
		var start_z = spacing_vertical * (i + 1)
		beam_start_positions.append(Vector3(0.0, beam_y, start_z))
		# All shoot to the right initially
		beam_directions.append(Vector2(1, 0))
	
	# Initial beams will be updated by ray tracing
	for i in range(NUM_RAYS):
		update_light_ray(i)
	
	
	
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



func update_light_ray(ray_index: int) -> void:
	if ray_index < 0 or ray_index >= NUM_RAYS:
		return
	if ray_index >= light_beam_meshes.size():
		return
	
	var ray_points := PackedVector3Array()
	var ray_widths := PackedFloat32Array()
	var beam_start = beam_start_positions[ray_index]
	var ray_origin_xz = Vector2(beam_start.x, beam_start.z)
	var ray_direction = beam_directions[ray_index]
	var remaining_length = max_ray_length
	var current_width = initial_beam_width
	
	ray_points.append(beam_start)
	ray_widths.append(current_width)
	
	for bounce in range(max_bounces):
		if remaining_length <= 0:
			break
		
		var hit_info = cast_ray(ray_origin_xz, ray_direction, remaining_length)
		
		if not hit_info.is_empty():
			var distance_2d = ray_origin_xz.distance_to(hit_info.position)
			remaining_length -= distance_2d
			
			# Add hit point with current width (before lens effect)
			var hit_pos_3d = Vector3(hit_info.position.x, beam_start.y, hit_info.position.y)
			ray_points.append(hit_pos_3d)
			ray_widths.append(current_width)
			ray_origin_xz = hit_info.position
			
			# Apply lens/mirror effect for next segment
			if hit_info.tower_type == "convex_lens":
				# Convex lens: narrow the beam instantly
				current_width *= convex_lens_multiplier
				current_width = clamp(current_width, min_beam_width, max_beam_width)
				# Add duplicate point with new narrow width for instant transition
				ray_points.append(hit_pos_3d)
				ray_widths.append(current_width)
				# Direction stays the same
			elif hit_info.tower_type == "concave_lens":
				# Concave lens: widen the beam instantly
				current_width *= concave_lens_multiplier
				current_width = clamp(current_width, min_beam_width, max_beam_width)
				# Add duplicate point with new wide width for instant transition
				ray_points.append(hit_pos_3d)
				ray_widths.append(current_width)
				# Direction stays the same
			else:
				# Mirror: reflect the ray
				var dot_product = ray_direction.dot(hit_info.normal)
				ray_direction = ray_direction - 2 * dot_product * hit_info.normal
				ray_direction = ray_direction.normalized()
		else:
			# No hit, extend to max length
			var end_xz = ray_origin_xz + ray_direction * remaining_length
			ray_points.append(Vector3(end_xz.x, beam_start.y, end_xz.y))
			ray_widths.append(current_width)
			break
	
	update_light_beam(ray_index, ray_points, ray_widths)


func cast_ray(origin: Vector2, direction: Vector2, max_distance: float) -> Dictionary:
	var closest_hit = {}
	var closest_distance = max_distance
	
	# Check all TowerLine nodes in the scene tree
	for child in get_tree().get_nodes_in_group("tower_line"):
		if child is TowerLine:
			var hit = ray_line_intersection(origin, direction, max_distance, child.start_point, child.end_point)
			if hit and hit.has("distance") and hit.distance < closest_distance:
				closest_distance = hit.distance
				closest_hit = hit
				# Add tower type to hit info
				closest_hit["tower_type"] = child.tower_type
	
	return closest_hit

func ray_line_intersection(ray_origin: Vector2, ray_dir: Vector2, max_dist: float, line_start: Vector2, line_end: Vector2) -> Dictionary:
	# Ray: P = ray_origin + t * ray_dir
	# Line segment: Q = line_start + s * (line_end - line_start), where 0 <= s <= 1
	
	var line_vec = line_end - line_start
	var line_to_ray = ray_origin - line_start
	
	var cross_dir_line = ray_dir.cross(line_vec)
	if abs(cross_dir_line) < 0.0001:
		return {}  # Parallel or collinear
	
	var t = line_vec.cross(line_to_ray) / cross_dir_line
	var s = ray_dir.cross(line_to_ray) / cross_dir_line
	
	if t > 0.0001 and t <= max_dist and s >= 0 and s <= 1:
		var hit_position = ray_origin + ray_dir * t
		# Calculate perpendicular to line segment
		var normal = Vector2(-line_vec.y, line_vec.x).normalized()
		# Flip normal to point away from incoming ray (match 2D working version)
		if normal.dot(ray_dir) < 0:
			normal = -normal
		
		return {
			"position": hit_position,
			"normal": normal,
			"distance": t
		}
	
	return {}

func update_light_beam(ray_index: int, points: PackedVector3Array, widths: PackedFloat32Array) -> void:
	if ray_index < 0 or ray_index >= NUM_RAYS:
		return
	if ray_index >= light_beam_meshes.size():
		return
	
	var mesh = light_beam_meshes[ray_index]
	if mesh == null:
		return
	
	mesh.clear_surfaces()
	
	if points.size() < 2:
		return
	
	# Draw beam as triangles to show thickness
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var ray_color = beam_colors[ray_index]
	
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i + 1]
		var direction = (p2 - p1).normalized()
		
		# Use width at each point for tapering effect
		var width1 = widths[i] if i < widths.size() else initial_beam_width
		var width2 = widths[i + 1] if (i + 1) < widths.size() else initial_beam_width
		
		# Calculate alpha based on width (wider = more transparent)
		# Map width to alpha: narrower beams are more opaque, wider beams are more transparent
		var width_ratio1 = width1 / max_beam_width
		var width_ratio2 = width2 / max_beam_width
		var alpha1 = clamp(1.0 - width_ratio1 * 0.6, 0.2, 1.0)
		var alpha2 = clamp(1.0 - width_ratio2 * 0.6, 0.2, 1.0)
		var color1 = Color(ray_color.r, ray_color.g, ray_color.b, alpha1)
		var color2 = Color(ray_color.r, ray_color.g, ray_color.b, alpha2)
		
		# Create perpendicular for width (use up vector)
		var perp1 = Vector3(0, 1, 0).cross(direction).normalized() * width1
		var perp2 = Vector3(0, 1, 0).cross(direction).normalized() * width2
		
		# Create quad as two triangles with varying width
		var v1 = p1 + perp1
		var v2 = p1 - perp1
		var v3 = p2 + perp2
		var v4 = p2 - perp2
		
		# Triangle 1 with vertex colors
		mesh.surface_set_color(color1)
		mesh.surface_add_vertex(v1)
		mesh.surface_set_color(color1)
		mesh.surface_add_vertex(v2)
		mesh.surface_set_color(color2)
		mesh.surface_add_vertex(v3)
		
		# Triangle 2 with vertex colors
		mesh.surface_set_color(color1)
		mesh.surface_add_vertex(v2)
		mesh.surface_set_color(color2)
		mesh.surface_add_vertex(v4)
		mesh.surface_set_color(color2)
		mesh.surface_add_vertex(v3)
	
	mesh.surface_end()

func _clear_kids() -> void: ### the IDF is interested in this one 
	for child in get_children():
		if is_instance_valid(scenePath) and child == scenePath:
			# Optional: reset its curve so it’s clean for the next run
			scenePath.curve = Curve3D.new()
			continue
		child.queue_free()
		
		
		
