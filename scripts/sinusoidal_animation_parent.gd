extends Node3D

const TRANSLATION_DISTANCE := 0.2
const TRANSLATION_SPEED := 2.0
const ROTATION_SPEED := 0.5
@export var _reverse_direction := false
var _time := 0.0
@onready var _default_transform: Transform3D = get_transform()



func _process(delta: float) -> void:
	self._time += delta
	self.transform = get_animated_transform(
		self._default_transform, self._time, self._reverse_direction
	)



static func get_animated_transform(
	p_default_transform: Transform3D, p_time: float, p_reverse_direction: bool
) -> Transform3D:
	var rotation = Vector3.ZERO # * p_time * ROTATION_SPEED
	var translation_direction := -1 if p_reverse_direction else 1
	var y_pos := sin(p_time * TRANSLATION_SPEED) * TRANSLATION_DISTANCE * translation_direction
	var offset_transform := Transform3D(Basis.from_euler(rotation), Vector3.UP * y_pos)
	return p_default_transform * offset_transform
	
	
