
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
@onready var mirrorTower : PackedScene = preload("res://scenes/towers/tower.tscn")

@onready var camera = Globals.cameraNode

var light_beam_mesh: ImmediateMesh = null
var light_beam_mesh_2: ImmediateMesh = null

# Light ray tracing variables
var max_ray_length: float = 2000.0
var max_bounces: int = 20
var beam_start_position: Vector3
var beam_direction: Vector2 = Vector2(1, 0)  # Shoots right in XZ plane
var beam_start_position_2: Vector3
var beam_direction_2: Vector2 = Vector2(0, 1)  # Shoots down in XZ plane



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
	update_light_ray()
	update_light_ray_2()





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
	
	# Create first light beam
	var light_beam := Node3D.new()
	light_beam.name = "LightBeam"
	
	var beam_line := MeshInstance3D.new()
	beam_line.name = "BeamLine"
	
	var mesh := ImmediateMesh.new()
	beam_line.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 1, 0, 1)  # Yellow light
	material.emission_enabled = true
	material.emission = Color(1, 1, 0, 1)
	beam_line.material_override = material
	
	light_beam.add_child(beam_line)
	add_child(light_beam)
	light_beam_mesh = mesh
	
	# Create second light beam
	var light_beam_2 := Node3D.new()
	light_beam_2.name = "LightBeam2"
	
	var beam_line_2 := MeshInstance3D.new()
	beam_line_2.name = "BeamLine2"
	
	var mesh_2 := ImmediateMesh.new()
	beam_line_2.mesh = mesh_2
	
	var material_2 := StandardMaterial3D.new()
	material_2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_2.albedo_color = Color(0, 1, 1, 1)  # Cyan light
	material_2.emission_enabled = true
	material_2.emission = Color(0, 1, 1, 1)
	beam_line_2.material_override = material_2
	
	light_beam_2.add_child(beam_line_2)
	add_child(light_beam_2)
	light_beam_mesh_2 = mesh_2

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
	
	# Create initial light beams
	var board_width = w * hex_size * sqrt(3.0)
	var board_height = h * hex_size * 1.5
	var beam_y = 0.5  # Slightly above ground
	
	# First beam: shoots from left to right across the middle
	beam_start_position = Vector3(0.0, beam_y, board_height / 2.0)
	beam_direction = Vector2(1, 0)  # Right in XZ plane
	
	# Second beam: shoots from top to bottom across the middle (at right angle)
	beam_start_position_2 = Vector3(board_width / 2.0, beam_y, 0.0)
	beam_direction_2 = Vector2(0, 1)  # Down in XZ plane
	
	# Initial beams will be updated by ray tracing
	update_light_ray()
	update_light_ray_2()
	
	
	
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



func update_light_ray() -> void:
	if light_beam_mesh == null:
		return
	
	var ray_points := PackedVector3Array()
	var ray_origin_xz = Vector2(beam_start_position.x, beam_start_position.z)
	var ray_direction = beam_direction
	var remaining_length = max_ray_length
	
	ray_points.append(beam_start_position)
	
	for bounce in range(max_bounces):
		if remaining_length <= 0:
			break
		
		var hit_info = cast_ray(ray_origin_xz, ray_direction, remaining_length)
		
		if not hit_info.is_empty():
			# Hit a mirror
			var hit_pos_3d = Vector3(hit_info.position.x, beam_start_position.y, hit_info.position.y)
			ray_points.append(hit_pos_3d)
			var distance_2d = ray_origin_xz.distance_to(hit_info.position)
			remaining_length -= distance_2d
			
			# Reflect the ray manually
			ray_origin_xz = hit_info.position
			var dot_product = ray_direction.dot(hit_info.normal)
			ray_direction = ray_direction - 2 * dot_product * hit_info.normal
			ray_direction = ray_direction.normalized()
		else:
			# No hit, extend to max length
			var end_xz = ray_origin_xz + ray_direction * remaining_length
			ray_points.append(Vector3(end_xz.x, beam_start_position.y, end_xz.y))
			break
	
	update_light_beam(ray_points)

func update_light_ray_2() -> void:
	if light_beam_mesh_2 == null:
		return
	
	var ray_points := PackedVector3Array()
	var ray_origin_xz = Vector2(beam_start_position_2.x, beam_start_position_2.z)
	var ray_direction = beam_direction_2
	var remaining_length = max_ray_length
	
	ray_points.append(beam_start_position_2)
	
	for bounce in range(max_bounces):
		if remaining_length <= 0:
			break
		
		var hit_info = cast_ray(ray_origin_xz, ray_direction, remaining_length)
		
		if not hit_info.is_empty():
			# Hit a mirror
			var hit_pos_3d = Vector3(hit_info.position.x, beam_start_position_2.y, hit_info.position.y)
			ray_points.append(hit_pos_3d)
			var distance_2d = ray_origin_xz.distance_to(hit_info.position)
			remaining_length -= distance_2d
			
			# Reflect the ray manually
			ray_origin_xz = hit_info.position
			var dot_product = ray_direction.dot(hit_info.normal)
			ray_direction = ray_direction - 2 * dot_product * hit_info.normal
			ray_direction = ray_direction.normalized()
		else:
			# No hit, extend to max length
			var end_xz = ray_origin_xz + ray_direction * remaining_length
			ray_points.append(Vector3(end_xz.x, beam_start_position_2.y, end_xz.y))
			break
	
	update_light_beam_2(ray_points)

func cast_ray(origin: Vector2, direction: Vector2, max_distance: float) -> Dictionary:
	var closest_hit = {}
	var closest_distance = max_distance
	
	# Check all TowerMirror nodes in the scene tree
	for child in get_tree().get_nodes_in_group("tower_mirror"):
		if child is TowerMirror:
			var hit = ray_line_intersection(origin, direction, max_distance, child.start_point, child.end_point)
			if hit and hit.has("distance") and hit.distance < closest_distance:
				closest_distance = hit.distance
				closest_hit = hit
	
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

func update_light_beam(points: PackedVector3Array) -> void:
	if light_beam_mesh == null:
		return
	
	light_beam_mesh.clear_surfaces()
	
	if points.size() < 2:
		return
	
	light_beam_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		light_beam_mesh.surface_add_vertex(point)
	light_beam_mesh.surface_end()

func update_light_beam_2(points: PackedVector3Array) -> void:
	if light_beam_mesh_2 == null:
		return
	
	light_beam_mesh_2.clear_surfaces()
	
	if points.size() < 2:
		return
	
	light_beam_mesh_2.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		light_beam_mesh_2.surface_add_vertex(point)
	light_beam_mesh_2.surface_end()

func _clear_kids() -> void: ### the IDF is interested in this one 
	for child in get_children():
		if is_instance_valid(scenePath) and child == scenePath:
			# Optional: reset its curve so it’s clean for the next run
			scenePath.curve = Curve3D.new()
			continue
		child.queue_free()
		
		
		
