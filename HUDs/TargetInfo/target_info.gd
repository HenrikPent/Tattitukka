extends Control

@onready var info_label = $TargetInfo # Varmista että polku on oikein

func _ready():
	# Piilotetaan koko skene alussa
	visible = false

func _process(_delta: float) -> void:
	var target = CameraData.hit_node
	
	if is_instance_valid(target) and target.is_in_group("Units"):
		# 1. Näytetään koko TargetUI-skene
		visible = true
		
		# 2. Haetaan etäisyys
		var dist_text = ""
		var my_ship = UnitManager.controlled_unit
		if is_instance_valid(my_ship):
			var dist = my_ship.global_position.distance_to(target.global_position)
			dist_text = str(int(dist)) + " m"
		
		# 3. Päivitetään teksti (nimi ja etäisyys)
		# Huom: Jos käytät Labelia jossa on jo asettelut kunnossa, tämä vain vaihtaa sisällön
		info_label.text = "%s\n%s" % [target.name.to_upper(), dist_text]
		
	else:
		# 4. Jos ei targetia, koko skene piiloon
		visible = false
