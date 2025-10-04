
extends Node3D

class_name Board

@export var gridSize: Vector2i = Vector2i(4,4) ###change this as necessary
@export var cellSize: float = 1.0
@export var boardHeight: float = 0.0


var occupiedSpaces := {}
@onready var _aabb := AABB(Vector3.ZERO, Vector3(gridSize.x * cellSize, 0.1, gridSize.y * cellSize))



func _ready() -> void:
	Globals.emit_signal("board_ready", self)
	
	
func gridToWorldCoords (cell: Vector2i) -> Vector3:
	return Vector3(
		(cell.x + 0.5) * cellSize,
		boardHeight,
		(cell.y + 0.5) * cellSize
	)
	
	
	
func worldToGridCoords (p: Vector3) -> Vector2i:
	var x := int(floor(p.x / cellSize))
	var y := int(floor(p.y / cellSize))
	return Vector2i(clamp(x, 0, gridSize.x - 1), clamp(y, 0, gridSize.y - 1))
	
	
	
func isFree(cell: Vector2i) -> bool:
	return !occupiedSpaces.has(cell)
	
	
	
func occupy(cell: Vector2i, val: bool) -> void:
	if val:
		occupiedSpaces[cell] = true
	else:
		occupiedSpaces.erase(cell)
		


func _draw() -> void:
	var cs := cellSize
	for x in range(cellSize + 1):
		var a := Vector3(x * cs, boardHeight + 0.01, 0)
		var b := Vector3(x * cs, boardHeight + 0.01, cellSize * cs)
		get_viewport().debug_draw_line_3d(a, b, Color(0.1,0.8,1,0.5))
		
	for y in range(cellSize + 1):
		var a := Vector3(0, boardHeight + 0.01, y * cellSize)
		var b := Vector3(cellSize * cs, boardHeight + 0.01, y * cs)
		get_viewport().debug_draw_line_3d(a, b, Color(0.1,0.8,1,0.5))
