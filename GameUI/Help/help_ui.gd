extends Control


func _ready():
	# Lukitaan elementti oikeaan yläkulmaan
	# PRESET_TOP_RIGHT = 1, PRESET_BOTTOM_RIGHT = 3, jne.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	
