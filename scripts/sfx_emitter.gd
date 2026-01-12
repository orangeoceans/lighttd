extends FmodEventEmitter3D

func play_action(action: String):
	set_parameter('action', action)
	play_one_shot()
