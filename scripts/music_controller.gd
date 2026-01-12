extends Node

@export var bgm_emitter: FmodEventEmitter2D

func _ready() -> void:
	bgm_emitter.play()

func _on_wave_started(wave_number: int) -> void:
	FmodServer.set_global_parameter_by_name("phase", 1.0)
	
func _on_all_enemies_cleared() -> void:
	FmodServer.set_global_parameter_by_name("phase", 0.0)
