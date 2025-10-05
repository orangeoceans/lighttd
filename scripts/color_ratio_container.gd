extends HBoxContainer
class_name ColorRatioContainer

var color_rects: Array[ColorRect] = []
var min_stretch_ratio: float = 0.0  # Minimum size for colors with 0 count

func _ready():
	print("ColorRatioContainer _ready() called")
	
	# Remove spacing between boxes
	add_theme_constant_override("separation", 0)
	
	# Create ColorRect for each beam color using the enum
	for i in range(Globals.BeamColor.size()):
		var beam_color_enum = i as Globals.BeamColor
		var color_rect = ColorRect.new()
		color_rect.color = Globals.get_beam_color(beam_color_enum)
		color_rect.size_flags_horizontal = SIZE_EXPAND_FILL
		color_rect.size_flags_stretch_ratio = 1.0  # Start equal
		# color_rect.custom_minimum_size = Vector2(5, 0)  # Minimum width
		
		add_child(color_rect)
		color_rects.append(color_rect)
	
	print("Created ", color_rects.size(), " color boxes")

func _process(_delta: float):
	update_ratios()

func update_ratios():
	# Get the collector beam counts
	var counts = Globals.collector_beam_counts
	
	if counts.is_empty():
		return  # No data yet
	
	# Calculate total count across all colors
	var total_count = 0
	for beam_color_enum in counts.keys():
		total_count += counts[beam_color_enum]
	
	if total_count == 0:
		return  # No beams absorbed yet
	
	# Update each ColorRect based on its enum index
	for i in range(Globals.BeamColor.size()):
		var beam_color_enum = i as Globals.BeamColor
		var count = counts.get(beam_color_enum, 0)
		
		# Calculate ratio based on count
		var ratio = float(count) / float(total_count)
		
		# Set stretch ratio
		if count > 0:
			color_rects[i].size_flags_stretch_ratio = max(ratio, min_stretch_ratio)
		else:
			# Hide colors with no count
			color_rects[i].size_flags_stretch_ratio = min_stretch_ratio
