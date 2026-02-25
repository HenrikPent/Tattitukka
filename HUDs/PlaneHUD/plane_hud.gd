extends Control

# Haetaan viittaus lentokoneeseen (joka on HUD-CanvasLayerin parent)
@onready var plane = get_parent().get_parent() 

@onready var thrust_bar = $ThrustBar
@onready var thrust_label = $ThrustLabel

func _process(_delta):
	if not is_instance_valid(plane): return
	
	# Päivitetään työntövoiman visualisointi
	if thrust_bar:
		thrust_bar.value = plane.sync_thrust
	
	if thrust_label:
		thrust_label.text = str(int(plane.sync_thrust))
	
	# vaihtaa palkin väriä kun ollaan täysillä
	if plane.sync_thrust > 550:
		thrust_bar.modulate = Color.ORANGE_RED
	else:
		thrust_bar.modulate = Color.WHITE
