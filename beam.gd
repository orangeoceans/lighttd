extends Node3D
class_name Beam

var board : Board = null
var mesh_instance : MeshInstance3D = null
var debug_points_parent : Node3D = null

@onready var current_beam_segments: Array = []  # Store beam segments for damage calculation [{p1, p2, width1, width2}]
@onready var is_active : bool = false
@onready var time_elapsed: float = 0.0  # For pulsating effect

@export var show_debug_points: bool = true  # Toggle debug point visualization

@export var color : Color = Color.WHITE
@export var base_dps: float = 5.0  # Base damage for beam at initial_beam_width
@export var key: int = 0

var beam_start_position : Vector3 = Vector3.ZERO
var beam_start_direction : Vector2 = Vector2.ONE
var max_ray_length: float = 2000.0
var max_bounces: int = 20
var initial_beam_width: float = 0.3
var inactive_beam_width: float = 0.08  # Thin width for inactive beams
var min_beam_width: float = 0.05  # Minimum beam width (never thinner)
var max_beam_width: float = 1.2  # Maximum beam width (never wider)
var convex_lens_multiplier: float = 0.5  # Each convex lens narrows beam to 50% of current width
var concave_lens_multiplier: float = 1.5  # Each concave lens widens beam to 150% of current width
var pulse_speed: float = 3.0  # Speed of pulsating effect
var pulse_amount: float = 0.15  # How much the beam pulses (0.0 to 1.0)
var damage_width_multiplier: float = 2.0  # Damage scales with width

func _process(delta: float) -> void:
	if self.board == null:
		return
	update_light_path()

	if is_active:
		apply_beam_damage_to_enemies(delta)
		time_elapsed += delta

func initialize(board: Board, color : Color, position: Vector3, direction: Vector2, key: int):
	print("Initializing beam with color: ", color)
	self.board = board
	self.color = color
	self.key = key
	if color not in Globals.collector_beam_counts:
		Globals.collector_beam_counts[color] = 0

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "BeamLine"
	add_child(mesh_instance)
	mesh_instance.mesh = ImmediateMesh.new()
	mesh_instance.material_override = material
	mesh_instance.material_override.albedo_color = color
	mesh_instance.material_override.emission = color

	# Create parent for debug points
	debug_points_parent = Node3D.new()
	debug_points_parent.name = "DebugPoints"
	add_child(debug_points_parent)

	beam_start_position = position
	beam_start_direction = direction

func cast_ray(origin: Vector2, direction: Vector2, max_distance: float) -> Dictionary:
	var closest_hit = {}
	var closest_distance = max_distance
	
	# Check all TowerLine nodes in the scene tree
	for child in board.get_tree().get_nodes_in_group("tower_line"):
		if child is TowerLine:
			var hit = ray_line_intersection(origin, direction, max_distance, child.start_point, child.end_point)
			if hit and hit.has("distance") and hit.distance < closest_distance:
				closest_distance = hit.distance
				closest_hit = hit
				# Add tower type to hit info
				closest_hit["tower_type"] = child.tower_type
	
	return closest_hit

func ray_line_intersection(ray_origin: Vector2, ray_dir: Vector2, max_dist: float, line_start: Vector2, line_end: Vector2) -> Dictionary:
	# Ray: P = ray_origin + t * ray_dir
	# Line segment: Q = line_start + s * (line_end - line_start), where 0 <= s <= 1
	
	var line_vec = line_end - line_start
	var line_to_ray = ray_origin - line_start
	
	var cross_dir_line = ray_dir.cross(line_vec)
	if abs(cross_dir_line) < 0.0001:
		return {}  # Parallel or collinear
	
	var t = line_vec.cross(line_to_ray) / cross_dir_line
	var s = ray_dir.cross(line_to_ray) / cross_dir_line
	
	if t > 0.0001 and t <= max_dist and s >= 0 and s <= 1:
		var hit_position = ray_origin + ray_dir * t
		# Calculate perpendicular to line segment
		var normal = Vector2(-line_vec.y, line_vec.x).normalized()
		# Flip normal to point away from incoming ray (match 2D working version)
		if normal.dot(ray_dir) < 0:
			normal = -normal
		
		return {
			"position": hit_position,
			"normal": normal,
			"distance": t
		}
	
	return {}

func update_light_path() -> void:
	current_beam_segments.clear()
	
	var ray_points := PackedVector3Array()
	var ray_widths := PackedFloat32Array()
	var ray_direction := beam_start_direction
	var ray_origin_xz = Vector2(beam_start_position.x, beam_start_position.z)
	var remaining_length = max_ray_length
	
	# Calculate base width with pulsating effect for active beams
	var base_width: float
	if is_active:
		# Pulsating effect using sine wave
		var pulse = sin(time_elapsed * pulse_speed) * pulse_amount
		base_width = initial_beam_width * (1.0 + pulse)
	else:
		# Thin width for inactive beams
		base_width = inactive_beam_width
	
	var current_width = base_width
	
	ray_points.append(beam_start_position)
	ray_widths.append(current_width)
	
	for bounce in range(max_bounces):
		if remaining_length <= 0:
			break
		
		var hit_info = cast_ray(ray_origin_xz, ray_direction, remaining_length)
		
		if not hit_info.is_empty():
			var distance_2d = ray_origin_xz.distance_to(hit_info.position)
			remaining_length -= distance_2d
			
			# Add hit point with current width (before lens effect)
			var hit_pos_3d = Vector3(hit_info.position.x, beam_start_position.y, hit_info.position.y)
			ray_points.append(hit_pos_3d)
			ray_widths.append(current_width)
			ray_origin_xz = hit_info.position
			
			# Apply lens/mirror/collector effect for next segment
			if hit_info.tower_type == "collector":
				# Collector: absorb the beam (stop tracing)
				# Only increment count if this is the active beam
				if is_active:
					Globals.collector_beam_counts[color] += 1
					print("Collector absorbed ", color, " beam! Total counts: ", Globals.collector_beam_counts)
				break
			elif hit_info.tower_type == "convex_lens":
				# Convex lens: narrow the beam instantly
				current_width *= convex_lens_multiplier
				current_width = clamp(current_width, min_beam_width, max_beam_width)
				# Add duplicate point with new narrow width for instant transition
				ray_points.append(hit_pos_3d)
				ray_widths.append(current_width)
				# Direction stays the same
			elif hit_info.tower_type == "concave_lens":
				# Concave lens: widen the beam instantly
				current_width *= concave_lens_multiplier
				current_width = clamp(current_width, min_beam_width, max_beam_width)
				# Add duplicate point with new wide width for instant transition
				ray_points.append(hit_pos_3d)
				ray_widths.append(current_width)
				# Direction stays the same
			else:
				# Mirror: reflect the ray
				var dot_product = ray_direction.dot(hit_info.normal)
				ray_direction = ray_direction - 2 * dot_product * hit_info.normal
				ray_direction = ray_direction.normalized()
		else:
			# No hit, extend to max length
			var end_xz = ray_origin_xz + ray_direction * remaining_length
			ray_points.append(Vector3(end_xz.x, beam_start_position.y, end_xz.y))
			ray_widths.append(current_width)
			break
	
	update_beam_mesh(ray_points, ray_widths, is_active)
	
	if show_debug_points:
		update_debug_points(ray_points)

func update_beam_mesh(points: PackedVector3Array, widths: PackedFloat32Array, is_active: bool) -> void:
	var mesh = mesh_instance.mesh
	if mesh == null:
		return
	
	mesh.clear_surfaces()
	
	if points.size() < 2:
		return
	
	# Draw beam as triangles to show thickness
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i + 1]
		var direction = (p2 - p1).normalized()
		
		# Use width at each point for tapering effect
		var width1 = widths[i] if i < widths.size() else initial_beam_width
		var width2 = widths[i + 1] if (i + 1) < widths.size() else initial_beam_width
		
		# Store beam segment for damage calculation if this is the active beam
		if is_active:
			current_beam_segments.append({
				"p1": p1,
				"p2": p2,
				"width1": width1,
				"width2": width2
			})
		
		# Calculate alpha and brightness based on active state
		var alpha1: float
		var alpha2: float
		var brightness_mult: float
		
		if is_active:
			# Active beams: brighter, more opaque, pulsating glow
			var width_ratio1 = width1 / max_beam_width
			var width_ratio2 = width2 / max_beam_width
			alpha1 = clamp(1.0 - width_ratio1 * 0.5, 0.4, 1.0)
			alpha2 = clamp(1.0 - width_ratio2 * 0.5, 0.4, 1.0)
			# Add pulsating brightness
			var pulse = sin(time_elapsed * pulse_speed * 2.0) * 0.3 + 0.7  # Range 0.4 to 1.0
			brightness_mult = 1.2 * pulse  # Brighter and pulsating
		else:
			# Inactive beams: dimmer, more transparent
			alpha1 = 0.25
			alpha2 = 0.25
			brightness_mult = 0.5  # Dimmer
		
		var color1 = Color(color.r * brightness_mult, color.g * brightness_mult, color.b * brightness_mult, alpha1)
		var color2 = Color(color.r * brightness_mult, color.g * brightness_mult, color.b * brightness_mult, alpha2)
		
		# Create perpendicular for width (use up vector)
		var perp1 = Vector3(0, 1, 0).cross(direction).normalized() * width1
		var perp2 = Vector3(0, 1, 0).cross(direction).normalized() * width2
		
		# Create quad as two triangles with varying width
		var v1 = p1 + perp1
		var v2 = p1 - perp1
		var v3 = p2 + perp2
		var v4 = p2 - perp2
		
		# Triangle 1 with vertex colors
		mesh.surface_set_color(color1)
		mesh.surface_add_vertex(v1)
		mesh.surface_set_color(color1)
		mesh.surface_add_vertex(v2)
		mesh.surface_set_color(color2)
		mesh.surface_add_vertex(v3)
		
		# Triangle 2 with vertex colors
		mesh.surface_set_color(color1)
		mesh.surface_add_vertex(v2)
		mesh.surface_set_color(color2)
		mesh.surface_add_vertex(v4)
		mesh.surface_set_color(color2)
		mesh.surface_add_vertex(v3)
	
	mesh.surface_end()

func apply_beam_damage_to_enemies(delta: float) -> void:
	# Get all enemies in the scene
	var enemies = board.get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	
	# Check each beam segment against all enemies
	for segment in current_beam_segments:
		var p1 = segment.p1
		var p2 = segment.p2
		var width1 = segment.width1
		var width2 = segment.width2
		
		# Average width for this segment
		var avg_width = (width1 + width2) / 2.0
		
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			
			var enemy_pos = enemy.global_position
			var distance = point_to_line_segment_distance(enemy_pos, p1, p2)
			
			# Check if enemy is within beam radius
			var collision_radius = enemy.collision_radius if "collision_radius" in enemy else 0.5
			if distance <= (avg_width + collision_radius):
				# Calculate damage based on beam width
				var width_ratio = avg_width / initial_beam_width
				var damage = base_dps * width_ratio * damage_width_multiplier * delta
				enemy.take_damage(damage)

func point_to_line_segment_distance(point: Vector3, line_start: Vector3, line_end: Vector3) -> float:
	# Calculate the closest point on the line segment to the point
	var line_vec = line_end - line_start
	var line_length_sq = line_vec.length_squared()
	
	if line_length_sq == 0:
		# Line segment is a point
		return point.distance_to(line_start)
	
	# Project point onto line, clamped to segment
	var t = clamp((point - line_start).dot(line_vec) / line_length_sq, 0.0, 1.0)
	var projection = line_start + t * line_vec
	
	return point.distance_to(projection)

func update_debug_points(points: PackedVector3Array) -> void:
	# Clear existing debug points
	for child in debug_points_parent.get_children():
		child.queue_free()
	
	# Create debug spheres at each ray point
	for i in range(points.size()):
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.1
		sphere_mesh.height = 0.2
		
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = sphere_mesh
		mesh_instance.position = points[i]
		
		# Create material for the debug point
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
		
		mesh_instance.material_override = material
		debug_points_parent.add_child(mesh_instance)
