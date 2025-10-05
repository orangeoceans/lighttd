extends Node3D
class_name EnemyHealthBar

@onready var sprite_3d: Sprite3D = $Sprite3D
@onready var sub_viewport: SubViewport = $SubViewport
@onready var progress_bar: ProgressBar = $SubViewport/ProgressBar

func _ready():
	print("EnemyHealthBar _ready() called")
	
	# Configure SubViewport first
	sub_viewport.size = Vector2i(200, 40)
	# sub_viewport.transparent_bg = true
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	print("SubViewport configured: size=", sub_viewport.size)
	
	# Configure ProgressBar sizing and style
	if progress_bar:
		progress_bar.size = Vector2(180, 20)
		progress_bar.position = Vector2(10, 10)
		progress_bar.show_percentage = false
		progress_bar.min_value = 0
		progress_bar.max_value = 100
		progress_bar.value = 50  # Set initial value for testing
		
		# Create a simple style if none exists
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style_bg.border_width_left = 1
		style_bg.border_width_right = 1
		style_bg.border_width_top = 1
		style_bg.border_width_bottom = 1
		style_bg.border_color = Color.BLACK
		progress_bar.add_theme_stylebox_override("background", style_bg)
		
		print("ProgressBar configured: size=", progress_bar.size, " pos=", progress_bar.position, " value=", progress_bar.value)
	else:
		print("ERROR: ProgressBar not found!")
	
	# Wait a frame for viewport to render
	await get_tree().process_frame
	
	# Set Sprite3D to use SubViewport texture
	sprite_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_3d.no_depth_test = true  # Draw on top, always visible
	sprite_3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite_3d.pixel_size = 0.01

	print("EnemyHealthBar setup complete - pixel_size: ", sprite_3d.pixel_size)

func update_health(current: float, maximum: float) -> void:
	if not progress_bar:
		return
	
	progress_bar.max_value = maximum
	progress_bar.value = current
	
	# Optional: Color based on health percentage
	var health_percent = current / maximum
	var style_fg = StyleBoxFlat.new()
	if health_percent > 0.6:
		style_fg.bg_color = Color.GREEN
	elif health_percent > 0.3:
		style_fg.bg_color = Color.YELLOW
	else:
		style_fg.bg_color = Color.RED
	progress_bar.add_theme_stylebox_override("fill", style_fg)

func _process(_delta: float) -> void:
	# Always face camera
	if Globals.cameraNode:
		look_at(Globals.cameraNode.global_position, Vector3.UP)
