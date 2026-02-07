extends Control


func _ready():
	hide()


func _input(event):
	if event.is_action_pressed("escape"): # ESC
		visible = !visible
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) #kursori näkyviin


func _on_continue_button_pressed():
	#menu piiloon
	hide() 
	#vaihdetaan hiiri kameran ohajus modeen
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
