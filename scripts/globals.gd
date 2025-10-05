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

var collector_tower_instance: TowerLine = null  # Track the single collector instance
var collector_beam_counts: Dictionary = {}  # Track beam counts by color name

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
