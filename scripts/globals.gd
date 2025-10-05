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
