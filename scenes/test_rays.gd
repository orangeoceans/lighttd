extends Node2D

@onready var light: Line2D = $Light
var max_ray_length: float = 2000.0
var max_bounces: int = 20

func _ready():
	update_light_ray()

func _process(_delta):
	update_light_ray()

func update_light_ray():
	var ray_points: Array[Vector2] = []
	var ray_origin = light.global_position
	if light.points.size() > 0:
		ray_origin = light.to_global(light.points[0])
	var ray_direction = Vector2(0, 1)
	var remaining_length = max_ray_length
	
	ray_points.append(light.to_local(ray_origin))
	
	for bounce in range(max_bounces):
		if remaining_length <= 0:
			break
		
		var hit_info = cast_ray(ray_origin, ray_direction, remaining_length)
		
		if not hit_info.is_empty():
			# Hit a mirror
			ray_points.append(light.to_local(hit_info.position))
			remaining_length -= ray_origin.distance_to(hit_info.position)
			
			# Reflect the ray manually: reflected = incident - 2 * (incident · normal) * normal
			ray_origin = hit_info.position
			var dot_product = ray_direction.dot(hit_info.normal)
			ray_direction = ray_direction - 2 * dot_product * hit_info.normal
		else:
			# No hit, extend to max length
			ray_points.append(light.to_local(ray_origin + ray_direction * remaining_length))
			break
	
	light.points = ray_points

func cast_ray(origin: Vector2, direction: Vector2, max_distance: float) -> Dictionary:
	var closest_hit = {}
	var closest_distance = max_distance
	
	for child in get_children():
		if child is Mirror:
			var hit = ray_line_intersection(origin, direction, max_distance, child.start_point, child.end_point)
			if hit and hit.has("distance") and hit.distance < closest_distance:
				closest_distance = hit.distance
				closest_hit = hit
	
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
		var normal = Vector2(-line_vec.y, line_vec.x).normalized()		
		if normal.dot(ray_dir) < 0:
			normal = -normal
		
		return {
			"position": hit_position,
			"normal": normal,
			"distance": t
		}
	
	return {}
