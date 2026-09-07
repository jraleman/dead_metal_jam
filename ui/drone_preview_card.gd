class_name DmjDronePreviewCard
extends PanelContainer

@onready var _title: Label = %DroneTitle
@onready var _status: Label = %DroneStatus
@onready var _description: Label = %DroneDescription
@onready var _stage: Control = %Artwork

var _art: DmjDroneArt


func _ready() -> void:
	_stage.resized.connect(_fit_art)
	_stage.draw.connect(_draw_stage)


func configure(title: String, status: String, description: String, art: DmjDroneArt) -> void:
	_title.text = title
	_status.text = status
	_description.text = description
	if _art != null:
		_art.queue_free()
	_art = art
	_stage.add_child(_art)
	_fit_art()


func _fit_art() -> void:
	_stage.queue_redraw()
	if _art == null or _stage.size.x <= 0.0 or _stage.size.y <= 0.0:
		return
	var bounds := _art.framed_bounds()
	var available := (_stage.size - Vector2(32.0, 36.0)).max(Vector2.ONE)
	var fit := minf(1.55, minf(available.x / bounds.size.x, available.y / bounds.size.y))
	_art.scale = Vector2.ONE * fit
	_art.position = _stage.size * 0.5 - bounds.get_center() * fit


func _draw_stage() -> void:
	var width := _stage.size.x
	var baseline := _stage.size.y * 0.85
	for index in range(4):
		var y := baseline + float(index) * 9.0
		_stage.draw_line(
			Vector2(width * 0.12, y), Vector2(width * 0.88, y),
			Color(DmjPalette.LINE, 0.16), 1.0
		)
