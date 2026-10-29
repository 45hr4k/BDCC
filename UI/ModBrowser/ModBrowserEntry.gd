extends PanelContainer

var storedEntry = null

signal onSelected(modEntry)

const STATUS_TEXTS = {
	"installed": ["Installed", Color(0.6, 0.6, 0.6)],
	"update": ["Update available", Color(0.4, 1.0, 0.4)],
	"duplicate": ["Installed twice", Color(1.0, 0.6, 0.3)],
	"old": ["Older listing", Color(0.6, 0.6, 0.6)],
}

func setModEntry(modEntry:ModEntry, status:String = "", isFavorite:bool = false):
	$HBoxContainer/Label.text = modEntry.name+" [by "+modEntry.author+"]"
	storedEntry = modEntry
	$HBoxContainer/StatusLabel.visible = STATUS_TEXTS.has(status)
	if(STATUS_TEXTS.has(status)):
		$HBoxContainer/StatusLabel.text = STATUS_TEXTS[status][0]
		$HBoxContainer/StatusLabel.add_color_override("font_color", STATUS_TEXTS[status][1])
	$HBoxContainer/Label.add_color_override("font_color", Color(1.0, 0.85, 0.4) if isFavorite else Color(1, 1, 1))

func _on_TextureButton_pressed():
	emit_signal("onSelected", storedEntry)

func makeActive():
	$Panel.visible = true

func makeInactive():
	$Panel.visible = false
