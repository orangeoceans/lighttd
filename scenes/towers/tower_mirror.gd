extends StaticBody3D
class_name TowerMirror

@export var length: float = 1.0:
	set(value):
		length = value
		update_endpoints()

@export var rotation_speed: float = 0.5  # Radians per second

# Start and end points in XZ plane (Vector2 represents X and Z coordinates)
var start_point: Vector2
var end_point: Vector2
var _cached_position: Vector3
var _cached_rotation: float

# Debug visualization
var debug_start_mesh: MeshInstance3D
var debug_end_mesh: MeshInstance3D

func _ready():
	# Create debug visualization spheres
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	
	debug_start_mesh = MeshInstance3D.new()
	debug_start_mesh.mesh = sphere_mesh
	var mat_start = StandardMaterial3D.new()
	mat_start.albedo_color = Color.RED
	mat_start.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_start_mesh.material_override = mat_start
	add_child(debug_start_mesh)
	
	debug_end_mesh = MeshInstance3D.new()
	debug_end_mesh.mesh = sphere_mesh
	var mat_end = StandardMaterial3D.new()
	mat_end.albedo_color = Color.GREEN
	mat_end.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_end_mesh.material_override = mat_end
	add_child(debug_end_mesh)
	
	update_endpoints()

func _process(delta):
	# Slowly rotate the mirror
	rotation.y += rotation_speed * delta
	
	if global_position != _cached_position or global_rotation.y != _cached_rotation:
		update_endpoints()

func update_endpoints():
	# Extract XZ plane rotation (Y-axis rotation in 3D)
	var rotation_y = global_rotation.y
	# Rotation directly defines the mirror line orientation
	var mirror_direction = Vector2(sin(rotation_y), cos(rotation_y))
	
	# Get XZ position (ignore Y coordinate)
	var pos_xz = Vector2(global_position.x, global_position.z)
	
	# Calculate global coordinates in XZ plane along the mirror line
	start_point = pos_xz - mirror_direction * length
	end_point = pos_xz + mirror_direction * length
	
	# Update debug visualization
	if debug_start_mesh:
		debug_start_mesh.global_position = Vector3(start_point.x, global_position.y, start_point.y)
	if debug_end_mesh:
		debug_end_mesh.global_position = Vector3(end_point.x, global_position.y, end_point.y)
	
	# Update cache
	_cached_position = global_position
	_cached_rotation = rotation_y
