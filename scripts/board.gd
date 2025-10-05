
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

var enemiesToSpawn : int = 30 ### number of enemies to spawn per round

var canSpawnEnemiesCooldown : bool = true; 

@onready var spawn_timer: Timer = $"../utilities/spawnTimer"
@onready var mirrorTower : PackedScene = preload("res://scenes/towers/mirror.tscn")

@onready var camera = Globals.cameraNode

@onready var beam : PackedScene = preload("res://scenes/beam.tscn")

# Light ray system - support for 7 rays
const NUM_RAYS: int = 7
var beams: Array[Beam] = []  # Store all beam instances
var beam_start_positions: Array[Vector3] = []
var beam_directions: Array[Vector2] = []


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
	
	# Place Collector tower near the goal
	place_collector_tower(rows, goal, tiles_root)
	
	# Create all light beams
	for i in range(NUM_RAYS):
		var board_height = rows.size() * hex_size * 1.5
		var beam_y = 0.5  # Slightly above ground
		var spacing_vertical = board_height / float(NUM_RAYS + 1)
		var start_z = spacing_vertical * (i + 1)
		var beam_color_enum = i as Globals.BeamColor  # Use enum index

		var beam_instance := beam.instantiate()
		beam_instance.initialize(self, beam_color_enum, Vector3(0.0, beam_y, start_z), Vector2(1, 0), beam_keys[i])
		add_child(beam_instance)
		beams.append(beam_instance)
	
	
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
	if Globals.collector_tower_instance and is_instance_valid(Globals.collector_tower_instance):
		return
	
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
				# Find the actual tile node
				for tile in tiles_root.get_children():
					var tile_pos = _hex_center(nc, nr)
					if tile.position.distance_to(tile_pos) < 0.1:
						collector_tile = tile
						break
				if collector_tile:
					break
	
	# Place collector tower if we found a suitable tile
	if collector_tile:
		for child in collector_tile.get_children():
			if child.is_in_group("emptyTile"):
				Globals.create_tower("collector", child)
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
