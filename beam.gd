extends Node3D
class_name Beam

var board : Board = null
var mesh_instance : MeshInstance3D = null
var debug_points_parent : Node3D = null

@onready var current_beam_segments: Array = []  # Store beam segments for damage calculation [{p1, p2, width1, width2}]
@onready var current_scatter_segments: Array = []  # Store scatter beam segments for rendering
@onready var is_active : bool = false
@onready var time_elapsed: float = 0.0  # For pulsating effect

@export var show_debug_points: bool = true  # Toggle debug point visualization

@export var base_dps: float = 2.0  # Base damage for beam at initial_beam_width
@export var key: int = 0

var beam_color_enum: Globals.BeamColor  # Single source of truth for beam color
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

# Yellow scatter beam settings
var scatter_beam_count: int = 4
var scatter_beam_damage_multiplier: float = 0.4  # 40% of main beam damage
var scatter_beam_width: float = 0.1

# Status effect damage bonuses
var red_burn_bonus: float = 0.5  # Red beam +50% damage to burned enemies
var purple_frozen_bonus: float = 0.5  # Purple beam +50% damage to frozen enemies

func _process(delta: float) -> void:
	if self.board == null:
		return
	update_light_path()

	if is_active:
		apply_beam_damage_to_enemies(delta)
		time_elapsed += delta

func initialize(board: Board, beam_color_enum: Globals.BeamColor, position: Vector3, direction: Vector2, key: int):
	print("Initializing beam with color enum: ", beam_color_enum)
	self.board = board
	self.beam_color_enum = beam_color_enum
	self.key = key
	
	# Get color from enum
	var beam_color = Globals.get_beam_color(beam_color_enum)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = beam_color
	material.emission_enabled = true
	material.emission = beam_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "BeamLine"
	add_child(mesh_instance)
	mesh_instance.mesh = ImmediateMesh.new()
	mesh_instance.material_override = material
	mesh_instance.material_override.albedo_color = beam_color
	mesh_instance.material_override.emission = beam_color

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
					Globals.increment_beam_count(beam_color_enum, 1.0)
					# print("Collector absorbed ", beam_color_enum, " beam! Total counts: ", Globals.collector_beam_counts)
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
		
		# Get beam color from enum
		var beam_color = Globals.get_beam_color(beam_color_enum)
		var color1 = Color(beam_color.r * brightness_mult, beam_color.g * brightness_mult, beam_color.b * brightness_mult, alpha1)
		var color2 = Color(beam_color.r * brightness_mult, beam_color.g * brightness_mult, beam_color.b * brightness_mult, alpha2)
		
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
	
	# Render scatter beams for yellow beam
	if beam_color_enum == Globals.BeamColor.YELLOW and is_active:
		render_scatter_beams(mesh)
	
	mesh.surface_end()

func render_scatter_beams(mesh: ImmediateMesh) -> void:
	# Render all scatter beam segments
	for segment in current_scatter_segments:
		var p1 = segment.p1
		var p2 = segment.p2
		
		# Direction for perpendicular calculation
		var direction = (p2 - p1).normalized()
		
		# Get beam color (slightly dimmer than main beam)
		var beam_color = Globals.get_beam_color(beam_color_enum)
		var brightness_mult = 0.6  # Dimmer than main beam
		var alpha = 0.3  # More transparent
		var color = Color(beam_color.r * brightness_mult, beam_color.g * brightness_mult, beam_color.b * brightness_mult, alpha)
		
		# Create perpendicular for width (use up vector)
		var perp = Vector3(0, 1, 0).cross(direction).normalized() * scatter_beam_width
		
		# Create quad as two triangles
		var v1 = p1 + perp
		var v2 = p1 - perp
		var v3 = p2 + perp
		var v4 = p2 - perp
		
		# Triangle 1
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v1)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v2)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v3)
		
		# Triangle 2
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v2)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v4)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(v3)

func apply_beam_damage_to_enemies(delta: float) -> void:
	# Clear previous scatter segments
	current_scatter_segments.clear()
	
	# Get all enemies in the scene
	var enemies = board.get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	
	# Track enemies hit by main beam (for scatter logic)
	var hit_enemies: Array = []
	
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
				# Calculate damage based on beam width and color
				var width_ratio = avg_width / initial_beam_width
				var color_multiplier = get_damage_multiplier()
				var damage = base_dps * width_ratio * damage_width_multiplier * color_multiplier * delta
				
				# Apply balance multiplier and status effect damage bonuses
				if damage > 0:
					var balance_multiplier = Globals.get_balance_multiplier()
					var status_bonus = get_status_damage_bonus(enemy)
					damage *= balance_multiplier * status_bonus
					enemy.take_damage(damage)
				
				# Apply status effects based on beam color
				if enemy.has_method("accumulate_status"):
					apply_status_effect_to_enemy(enemy, delta)
				
				# Track hit for scatter beams (yellow only)
				if beam_color_enum == Globals.BeamColor.YELLOW and not hit_enemies.has(enemy):
					hit_enemies.append(enemy)
	
	# Apply scatter beams for yellow beam
	if beam_color_enum == Globals.BeamColor.YELLOW:
		apply_scatter_beams(hit_enemies, enemies, delta)

func trace_scatter_beam(origin: Vector3, direction: Vector2) -> Array:
	# Trace a scatter beam through mirrors, returning array of segments
	var segments = []
	var ray_origin_xz = Vector2(origin.x, origin.z)
	var ray_direction = direction.normalized()
	var remaining_length = max_ray_length
	var current_pos_3d = origin
	
	for bounce in range(max_bounces):
		if remaining_length <= 0:
			break
		
		var hit_info = cast_ray(ray_origin_xz, ray_direction, remaining_length)
		
		if not hit_info.is_empty():
			var distance_2d = ray_origin_xz.distance_to(hit_info.position)
			remaining_length -= distance_2d
			
			var hit_pos_3d = Vector3(hit_info.position.x, origin.y, hit_info.position.y)
			
			# Store segment
			segments.append({
				"p1": current_pos_3d,
				"p2": hit_pos_3d
			})
			
			# Stop at collectors
			if hit_info.tower_type == "collector":
				break
			
			# Lenses don't change direction, mirrors do
			if hit_info.tower_type == "mirror":
				var dot_product = ray_direction.dot(hit_info.normal)
				ray_direction = ray_direction - 2 * dot_product * hit_info.normal
				ray_direction = ray_direction.normalized()
			
			# Update position for next bounce
			ray_origin_xz = hit_info.position
			current_pos_3d = hit_pos_3d
		else:
			# No hit, extend to max length
			var end_xz = ray_origin_xz + ray_direction * remaining_length
			var end_pos_3d = Vector3(end_xz.x, origin.y, end_xz.y)
			segments.append({
				"p1": current_pos_3d,
				"p2": end_pos_3d
			})
			break
	
	return segments

func apply_scatter_beams(hit_enemies: Array, all_enemies: Array, delta: float) -> void:
	# For each enemy hit by the main beam, create scatter beams
	for hit_enemy in hit_enemies:
		if not is_instance_valid(hit_enemy):
			continue
		
		var scatter_origin = hit_enemy.global_position
		
		# Use enemy instance ID as seed for consistent random directions
		var enemy_seed = hit_enemy.get_instance_id()
		
		# Create scatter beams in consistent random directions
		for i in range(scatter_beam_count):
			# Generate consistent angle using seed
			seed(enemy_seed + i)
			var angle = randf() * TAU  # TAU = 2*PI
			var scatter_direction = Vector2(cos(angle), sin(angle))
			
			# Trace scatter beam through mirrors
			var scatter_segments = trace_scatter_beam(scatter_origin, scatter_direction)
			
			# Store all segments for rendering
			for segment in scatter_segments:
				current_scatter_segments.append(segment)
				
				# Check if this segment hits any enemies
				for target_enemy in all_enemies:
					if not is_instance_valid(target_enemy) or target_enemy == hit_enemy:
						continue
					
					var target_pos = target_enemy.global_position
					var distance = point_to_line_segment_distance(target_pos, segment.p1, segment.p2)
					
					var collision_radius = target_enemy.collision_radius if "collision_radius" in target_enemy else 0.5
					if distance <= (scatter_beam_width + collision_radius):
						# Apply reduced damage with balance multiplier
						var balance_multiplier = Globals.get_balance_multiplier()
						var scatter_damage = base_dps * scatter_beam_damage_multiplier * balance_multiplier * delta
						target_enemy.take_damage(scatter_damage)
	
	# Reset random seed to avoid affecting other random calls
	randomize()

func get_status_damage_bonus(enemy) -> float:
	# Check for status effect damage bonuses
	var bonus = 1.0
	
	# Red beam bonus on burned enemies
	if beam_color_enum == Globals.BeamColor.RED:
		if enemy.has_method("has_status") and enemy.has_status(enemy.StatusEffect.BURNED):
			bonus += red_burn_bonus
	
	# Purple beam bonus on frozen enemies
	elif beam_color_enum == Globals.BeamColor.PURPLE:
		if enemy.has_method("has_status") and enemy.has_status(enemy.StatusEffect.FROZEN):
			bonus += purple_frozen_bonus
	
	return bonus

func get_damage_multiplier() -> float:
	# Different beams have different damage profiles
	match beam_color_enum:
		Globals.BeamColor.ORANGE:
			return 0.3  # Below average - relies on burn DOT
		Globals.BeamColor.GREEN:
			return 0.0  # No direct damage - pure poison
		Globals.BeamColor.CYAN:
			return 0.0  # No direct damage - pure support (weakened)
		Globals.BeamColor.BLUE:
			return 0.0  # No direct damage - pure crowd control (freeze)
		Globals.BeamColor.RED:
			return 1.0  # Standard damage
		Globals.BeamColor.YELLOW:
			return 1.0  # Standard damage
		Globals.BeamColor.PURPLE:
			return 1.0  # Standard damage
		_:
			return 1.0

func apply_status_effect_to_enemy(enemy, delta: float) -> void:
	# Apply status effect at a fixed rate (accumulated as float)
	var application_rate = 10.0  # Base rate per second
	var amount_to_apply = application_rate * delta
	
	match beam_color_enum:
		Globals.BeamColor.ORANGE:
			# Orange -> Burned
			enemy.accumulate_status(enemy.StatusEffect.BURNED, amount_to_apply)
		Globals.BeamColor.GREEN:
			# Green -> Poisoned
			enemy.accumulate_status(enemy.StatusEffect.POISONED, amount_to_apply)
		Globals.BeamColor.CYAN:
			# Cyan -> Weakened
			enemy.accumulate_status(enemy.StatusEffect.WEAKENED, amount_to_apply)
		Globals.BeamColor.BLUE:
			# Blue -> Frozen
			enemy.accumulate_status(enemy.StatusEffect.FROZEN, amount_to_apply)

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
		var beam_color = Globals.get_beam_color(beam_color_enum)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = beam_color
		material.emission_enabled = true
		material.emission = beam_color
		material.emission_energy_multiplier = 2.0
		
		mesh_instance.material_override = material
		debug_points_parent.add_child(mesh_instance)
