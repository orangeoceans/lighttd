extends Node3D

# Signals for tower selection
signal tower_selected(tower: TowerLine)
signal tower_deselected()

### I usually put variables that are accessible anywhere in this global autoload (singleton) 

### eg player health, anything you want displayed on the HUD like wave or enemy count 
@onready var cameraNode 
@onready var mirrorTower : PackedScene = preload("res://scenes/towers/mirror.tscn")
@onready var convexLensTower : PackedScene = preload("res://scenes/towers/convex_lens.tscn")
@onready var concaveLensTower : PackedScene = preload("res://scenes/towers/concave_lens.tscn")
@onready var collectorTower : PackedScene = preload("res://scenes/towers/collector.tscn")

# Beam color enum
enum BeamColor {
	RED,
	ORANGE,
	YELLOW,
	GREEN,
	CYAN,
	BLUE,
	PURPLE
}

# Function to get Color from enum
static func get_beam_color(beam_color: BeamColor) -> Color:
	match beam_color:
		BeamColor.RED:
			return Color(1.0, 0.0, 0.0)
		BeamColor.ORANGE:
			return Color(1.0, 0.5, 0.0)
		BeamColor.YELLOW:
			return Color(1.0, 1.0, 0.0)
		BeamColor.GREEN:
			return Color(0.0, 1.0, 0.0)
		BeamColor.CYAN:
			return Color(0.0, 1.0, 1.0)
		BeamColor.BLUE:
			return Color(0.0, 0.0, 1.0)
		BeamColor.PURPLE:
			return Color(0.5, 0.0, 1.0)
		_:
			return Color.WHITE

var collector_tower_instance: TowerLine = null  # Track the single collector instance
var collector_beam_counts: Dictionary = {}  # Track beam counts by BeamColor enum
var collector_total_count: int = 1400  # Fixed total - stays constant after normalization

# Increment a beam color count and normalize all counts
func increment_beam_count(beam_color_enum: BeamColor, increment_amount: float = 1.0) -> void:
	# Increment the target color
	if beam_color_enum in collector_beam_counts:
		collector_beam_counts[beam_color_enum] += increment_amount
	else:
		collector_beam_counts[beam_color_enum] = increment_amount
	
	# Calculate current total
	var current_total = 0.0
	for color in collector_beam_counts.keys():
		current_total += collector_beam_counts[color]
	
	# Normalize all counts to maintain fixed total
	if current_total > 0:
		var scale_factor = float(collector_total_count) / current_total
		for color in collector_beam_counts.keys():
			collector_beam_counts[color] *= scale_factor

func create_tower(tower_type: String, tile: Node) -> TowerLine:
	print("PLACING ", tower_type)
	var new_tower = null
	match tower_type:
		"collector":
			new_tower = Globals.collectorTower.instantiate()
			new_tower.add_to_group("tower_line")
			# Track the collector instance
			Globals.collector_tower_instance = new_tower
		"convex_lens":
			new_tower = Globals.convexLensTower.instantiate()
			new_tower.add_to_group("tower_line")
		"concave_lens":
			new_tower = Globals.concaveLensTower.instantiate()
			new_tower.add_to_group("tower_line")
		_:
			new_tower = Globals.mirrorTower.instantiate()
			new_tower.add_to_group("tower_line")
	tile.add_child(new_tower)
	new_tower.global_position = tile.global_position + Vector3(0,0.2,0)
	new_tower.rotation.y = TAU
	new_tower.tower_type = tower_type
	return new_tower
