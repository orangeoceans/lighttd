extends Node3D
class_name SimpleHealthBar

@onready var health_mesh: MeshInstance3D = $HealthBarMesh
@onready var background_mesh: MeshInstance3D = $BackgroundMesh

var bar_width: float = 1.0
var bar_height: float = 0.1

func _ready():
	create_health_bar_meshes()

func create_health_bar_meshes():
	# Create background (black bar)
	var bg_mesh = QuadMesh.new()
	bg_mesh.size = Vector2(bar_width, bar_height)
	background_mesh.mesh = bg_mesh
	
	var bg_material = StandardMaterial3D.new()
	bg_material.albedo_color = Color.BLACK
	bg_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	background_mesh.material_override = bg_material
	
	# Create health bar (green/red bar)
	var health_mesh_quad = QuadMesh.new()
	health_mesh_quad.size = Vector2(bar_width, bar_height)
	health_mesh.mesh = health_mesh_quad
	health_mesh.position.z = -0.01  # Slightly in front of background
	
	var health_material = StandardMaterial3D.new()
	health_material.albedo_color = Color.GREEN
	health_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	health_mesh.material_override = health_material

func update_health(current: float, maximum: float):
	var health_percent = clamp(current / maximum, 0.0, 1.0)
	
	# Scale the health bar
	health_mesh.scale.x = health_percent
	
	# Adjust position (keep left-aligned)
	health_mesh.position.x = -bar_width * 0.5 * (1.0 - health_percent)
	
	# Color based on health
	var health_color: Color
	if health_percent > 0.6:
		health_color = Color.GREEN
	elif health_percent > 0.3:
		health_color = Color.YELLOW
	else:
		health_color = Color.RED
	
	health_mesh.material_override.albedo_color = health_color
