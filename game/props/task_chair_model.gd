@tool
extends StaticBody3D
## The gameplay chair reused as ordinary empty office seating, in native metres.


func _ready() -> void:
	var chair := OfficeChairModel.new()
	chair.name = "ChairModel"
	add_child(chair)
	chair.build(Color("8aa6a2"))
