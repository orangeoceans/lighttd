extends Node

class_name Game

signal board_ready(board)
signal beam_updated(points: PackedVector3Array)
signal tower_placed(grid_pos: Vector2i, scene_path: String)

const LAYER = {
	"BOARD": 1,
	"TOWER": 2,
	"ENEMY": 3,
	"LIGHT": 4,
	"UI": 5,
}

# Helper to turn a 1-based layer idx into a bit
static func layer_bit(idx:int) -> int:
	return 1 << (idx - 1)
