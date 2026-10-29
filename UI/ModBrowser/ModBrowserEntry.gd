extends PanelContainer

var storedEntry = null

signal onSelected(modEntry)
signal onPinToggled(modEntry)

func setModEntry(modEntry:ModEntry, isPinned:bool = false):
	$HBoxContainer/Label.text = modEntry.name+" [by "+modEntry.author+"]"
	storedEntry = modEntry
	setPinned(isPinned)

func setPinned(isPinned:bool):
	$HBoxContainer/PinButton.text = "Unpin" if isPinned else "Pin"
	$HBoxContainer/PinButton.hint_tooltip = "Remove this mod from your pinned mods" if isPinned else "Pin this mod to the top of the list"
	self_modulate = Color(1.0, 0.85, 0.5) if isPinned else Color(1, 1, 1)

func _on_TextureButton_pressed():
	emit_signal("onSelected", storedEntry)

func _on_PinButton_pressed():
	emit_signal("onPinToggled", storedEntry)

func makeActive():
	$Panel.visible = true

func makeInactive():
	$Panel.visible = false
