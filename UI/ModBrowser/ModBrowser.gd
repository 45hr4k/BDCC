extends Control

onready var http_request = $HTTPRequest
onready var http_request_mod = $HTTPRequestMod
var modEntryScene = preload("res://UI/ModBrowser/ModBrowserEntry.tscn")
onready var modList = $VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer/ScrollContainer/ModList
onready var modDescriptionLabel = $VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer2/VBoxContainer/RichTextLabel
onready var downloadingContainer = $DownloadingContrainer
onready var messageDialog = $MessageDialog
onready var pinModButton = $VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer2/VBoxContainer/HFlowContainer/PinModButton

var allMods = []
var pickedModEntry:ModEntry
var visualModEntries = []

var sortType = "newest" #newest, oldest, name
var downloadedMods = false

# Pinned mods are remembered by their name
const pinnedModsPath = "user://modBrowserPinned.json"
var pinnedModNames:Array = []
var showOnlyPinned:bool = false
var searchText:String = ""

signal closePressed

func _ready():
	loadPinnedMods()

func loadPinnedMods():
	pinnedModNames.clear()
	var file = File.new()
	if(!file.file_exists(pinnedModsPath)):
		return
	if(file.open(pinnedModsPath, File.READ) != OK):
		Log.printerr("[ModBrowser] Couldn't open "+pinnedModsPath)
		return
	var jsonResult = JSON.parse(file.get_as_text())
	file.close()
	if(jsonResult.error != OK || !(jsonResult.result is Array)):
		Log.printerr("[ModBrowser] Couldn't parse "+pinnedModsPath)
		return
	for modName in jsonResult.result:
		if(modName is String && !pinnedModNames.has(modName)):
			pinnedModNames.append(modName)

func savePinnedMods():
	var file = File.new()
	if(file.open(pinnedModsPath, File.WRITE) != OK):
		Log.printerr("[ModBrowser] Couldn't save "+pinnedModsPath)
		return
	file.store_string(JSON.print(pinnedModNames, "\t"))
	file.close()

func isModPinned(modEntry) -> bool:
	return modEntry != null && pinnedModNames.has(modEntry.name)

func togglePinned(modEntry):
	if(modEntry == null):
		return
	if(isModPinned(modEntry)):
		pinnedModNames.erase(modEntry.name)
	else:
		pinnedModNames.append(modEntry.name)
	savePinnedMods()
	updateModList()
	updatePickedModEntry()

# Applies search + pinned filter, pinned mods go first (keeping the current sort order)
func getFilteredMods() -> Array:
	var pinned = []
	var others = []
	for mod in allMods:
		if(searchText != ""):
			if searchText.begins_with("@"):
				if mod.author.to_lower().find(searchText.to_lower().trim_prefix("@")) == -1:
					continue
			else:
				if !(searchText.to_lower() in mod.name.to_lower()):
					continue
		if(isModPinned(mod)):
			pinned.append(mod)
		elif(!showOnlyPinned):
			others.append(mod)
	return pinned + others

func _on_ModBrowser_visibility_changed():
	if(visible && !downloadedMods):
		downloadedMods = true
		var error = http_request.request("https://raw.githubusercontent.com/Alexofp/BDCCMods/main/allmods.json")
		if error != OK:
			Log.printerr("[ModBrowser] An error occurred in the HTTP request.")

func resetMods():
	pickedModEntry = null
	Util.delete_children(modList)
	allMods.clear()

func updateModList():
	visualModEntries.clear()
	Util.delete_children(modList)
	var modsArray = getFilteredMods()
	if(modsArray.empty() && showOnlyPinned && !allMods.empty()):
		var emptyLabel = Label.new()
		emptyLabel.text = "\nNo pinned mods found.\nUse the Pin button next to a mod to pin it."
		emptyLabel.align = Label.ALIGN_CENTER
		modList.add_child(emptyLabel)
	for modEntry in modsArray:
		var newBrowserEntry = modEntryScene.instance()
		modList.add_child(newBrowserEntry)
		newBrowserEntry.setModEntry(modEntry, isModPinned(modEntry))
		var _ok = newBrowserEntry.connect("onSelected", self, "onModEntrySelected")
		var _ok2 = newBrowserEntry.connect("onPinToggled", self, "togglePinned")
		if(modEntry == pickedModEntry):
			newBrowserEntry.makeActive()
		visualModEntries.append(newBrowserEntry)

func _on_HTTPRequest_request_completed(result, _response_code, _headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		Log.printerr("[ModBrowser] Couldn't download mods data from github")
		return
	
	var jsonResult = JSON.parse(body.get_string_from_utf8())
	if(jsonResult.error != OK):
		Log.printerr("[ModBrowser] Couldn't parse json data from github.")
		return
	
	var modsData = jsonResult.result
	
	resetMods()
	
	if(!(modsData is Dictionary)):
		return
	
	if(!modsData.has("mods")):
		return
	
	var modsStuff = modsData["mods"]
	if(!(modsStuff is Array)):
		return
	
	var _i = 0
	var requiredFields = ["name", "author", "download", "description", "modversion", "gameversion"]
	for theModEntry in modsStuff:
		if(!(theModEntry is Dictionary)):
			continue
		
		for requiredField in requiredFields:
			if(!theModEntry.has(requiredField) || !(theModEntry[requiredField] is String)):
				continue
		
		var newModEntry = ModEntry.new()
		newModEntry.name = theModEntry["name"]
		newModEntry.author = theModEntry["author"]
		newModEntry.description = theModEntry["description"]
		newModEntry.modversion = theModEntry["modversion"]
		newModEntry.gameversion = theModEntry["gameversion"]
		newModEntry.download = theModEntry["download"]
		newModEntry.index = _i
		_i += 1
		
		allMods.append(newModEntry)

	sortType = "newest"
	allMods.sort_custom(self, "sort_newest")
	updateModList()

func updatePickedModEntry():
	for visualModEntry in visualModEntries:
		if(visualModEntry.storedEntry == pickedModEntry):
			visualModEntry.makeActive()
		else:
			visualModEntry.makeInactive()
	
	pinModButton.disabled = (pickedModEntry == null)
	pinModButton.text = "Unpin" if isModPinned(pickedModEntry) else "Pin"

	if(pickedModEntry == null):
		modDescriptionLabel.bbcode_text = "Select a mod on the left"
	else:
		var text = ""
		if(isModPinned(pickedModEntry)):
			text += "[color=#ffd980]Pinned[/color]\n"
		text += "Name: "+str(pickedModEntry.name)+"\n"
		text += "Author: "+str(pickedModEntry.author)+"\n"
		text += "Mod version: "+str(pickedModEntry.modversion)+"\n"
		if(!GlobalRegistry.isVersionListHasCompatible(str(pickedModEntry.gameversion))):
			text += "[color=red]Game version: " + str(pickedModEntry.gameversion)+" (You are running version "+GlobalRegistry.getGameVersionString()+")[/color]\n"
		else:
			if(pickedModEntry.gameversion == "*"):
				text += "Game version: Any\n"
			else:
				text += "Game version: " + str(pickedModEntry.gameversion)+"\n"
		text += "Filename: "+str(pickedModEntry.download.get_file())+"\n"
		
		text += "\n"
		text += str(pickedModEntry.description)
		
		modDescriptionLabel.bbcode_text = text

func onModEntrySelected(theModEntry):
	pickedModEntry = theModEntry
	updatePickedModEntry()
	
	


func _on_DownloadModButton_pressed():
	if(pickedModEntry == null):
		return
	
	var fileName = pickedModEntry.download.get_file()
	
	downloadingContainer.visible = true
	http_request_mod.download_file = GlobalRegistry.getModsFolder().plus_file(fileName)
	var error = http_request_mod.request(pickedModEntry.download)
	if error != OK:
		Log.printerr("[ModBrowser] An error occurred in the HTTP request.")
		showMessage("An error occurred in the HTTP request.")
	else:
		Log.print("Downloading mod: "+str(pickedModEntry.download))


func _on_HTTPRequestMod_request_completed(result, _response_code, _headers, _body):
	downloadingContainer.visible = false

	if result != HTTPRequest.RESULT_SUCCESS:
		Log.printerr("[ModBrowser] Couldn't download mod")
		showMessage("Couldn't download mod")
		return
	
	Log.print("Mod downloaded")

func showMessage(text):
	messageDialog.dialog_text = text
	messageDialog.show()


static func sort_name(a, b):
	if a.name < b.name:
		return true
	return false

static func sort_newest(a, b):
	if a.index > b.index:
		return true
	return false

static func sort_oldest(a, b):
	if a.index < b.index:
		return true
	return false

func _on_SortNameButton_pressed():
	sortType = "name"
	allMods.sort_custom(self, "sort_name")
	updateModList()


func _on_SortNewestFirstButton_pressed():
	sortType = "newest"
	allMods.sort_custom(self, "sort_newest")
	updateModList()


func _on_SortOldestFirstButton_pressed():
	sortType = "oldest"
	allMods.sort_custom(self, "sort_oldest")
	updateModList()

func _on_CloseButton_pressed():
	emit_signal("closePressed")


func _on_RichTextLabel_meta_clicked(meta):
	var _ok = Util.fixed_shell_open(meta)


func _on_ModSearch_text_changed(new_text: String):
	if new_text.length() > 2:
		searchText = new_text
		updateModList()
	if new_text.length() == 0:
		searchText = ""
		updateModList()

func _on_OnlyPinnedCheckBox_toggled(button_pressed: bool):
	showOnlyPinned = button_pressed
	updateModList()

func _on_PinModButton_pressed():
	togglePinned(pickedModEntry)
	
