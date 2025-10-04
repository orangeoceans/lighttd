extends Line2D
class_name Mirror

@export var length: float = 1.0:
	set(value):
		length = value
		update_endpoints()

var start_point: Vector2
var end_point: Vector2
var _cached_position: Vector2
var _cached_rotation: float

func _ready():
	update_endpoints()

func _process(_delta):
	if position != _cached_position or rotation != _cached_rotation:
		update_endpoints()

func update_endpoints():
	var direction = Vector2(cos(rotation), sin(rotation))
	
	# Global coordinates
	start_point = position - direction * length
	end_point = position + direction * length
	
	# Local coordinates
	points = [Vector2(-length, 0), Vector2(length, 0)]
	
	_cached_position = position
	_cached_rotation = rotation
