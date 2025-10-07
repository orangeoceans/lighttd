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
var collector_total_count: int = 700  # Fixed total - stays constant after normalization

# Balance multiplier settings
const MAX_BALANCE_MULTIPLIER: float = 10.0  # Maximum damage boost at perfect balance
const MIN_BALANCE_MULTIPLIER: float = 1.0   # No boost when unbalanced
const TOTAL_BEAM_COLORS: int = 7            # Number of beam colors

# Cached balance multiplier (recalculated only when beam counts change)
var _cached_balance_multiplier: float = 10.0

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
	
	# Recalculate cached balance multiplier
	_update_balance_multiplier()

# Get the cached balance multiplier (fast, no calculation)
func get_balance_multiplier() -> float:
	return _cached_balance_multiplier

# Internal function to update the cached balance multiplier
func _update_balance_multiplier() -> void:
	# Only apply balance multiplier if a Collector tower exists
	if not collector_tower_instance or not is_instance_valid(collector_tower_instance):
		_cached_balance_multiplier = 1.0  # No multiplier without collector
		return
	
	if collector_beam_counts.is_empty():
		_cached_balance_multiplier = MIN_BALANCE_MULTIPLIER
		return
	
	# Calculate total count
	var total = 0.0
	for count in collector_beam_counts.values():
		total += count
	
	if total <= 0:
		_cached_balance_multiplier = MIN_BALANCE_MULTIPLIER
		return
	
	# Calculate Shannon entropy
	var entropy = 0.0
	for count in collector_beam_counts.values():
		if count > 0:
			var proportion = count / total
			entropy -= proportion * log(proportion) / log(2.0)  # log base 2
	
	# Maximum entropy occurs when all colors are equally distributed
	# For 7 colors: max_entropy = log2(7) ≈ 2.807
	var max_entropy = log(TOTAL_BEAM_COLORS) / log(2.0)
	
	# Normalize entropy to range [0, 1]
	var normalized_entropy = entropy / max_entropy
	
	# Apply exponential curve: use ^3 to heavily favor near-perfect balance
	# This makes 50/50 give ~1.4×, while perfect balance still gives 10×
	var curved_value = pow(normalized_entropy, 4.0)
	
	# Map to multiplier range [1.0, 10.0]
	_cached_balance_multiplier = MIN_BALANCE_MULTIPLIER + (MAX_BALANCE_MULTIPLIER - MIN_BALANCE_MULTIPLIER) * curved_value

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
	new_tower.global_position = tile.global_position + Vector3(0,1,0)
	new_tower.set_tower_rotation(TAU)
	new_tower.tower_type = tower_type
	return new_tower
