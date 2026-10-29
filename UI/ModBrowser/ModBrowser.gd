extends Control

onready var http_request = $HTTPRequest
onready var http_request_mod = $HTTPRequestMod
var modEntryScene = preload("res://UI/ModBrowser/ModBrowserEntry.tscn")
const ModBrowserState = preload("res://UI/ModBrowser/ModBrowserState.gd")
onready var modList = $VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer/ScrollContainer/ModList
onready var modDescriptionLabel = $VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer2/VBoxContainer/RichTextLabel
onready var filterOption = $VBoxContainer/HBoxContainer/PanelContainer/VBoxContainer/HFlowContainer/FilterOption
onready var downloadModButton = $VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer2/VBoxContainer/HFlowContainer/DownloadModButton
onready var favoriteButton = $VBoxContainer/HBoxContainer/VBoxContainer/PanelContainer2/VBoxContainer/HFlowContainer/FavoriteButton
onready var downloadingContainer = $DownloadingContrainer
onready var messageDialog = $MessageDialog
onready var replaceDialog = $ReplaceDialog

var allMods = []
var pickedModEntry:ModEntry
var visualModEntries = []
var state = ModBrowserState.new()

var sortType = "newest" #newest, oldest, name
var filterType = "all" #all, favorites, installed, updates
var searchText = ""
var downloadedMods = false

var downloadingEntry:ModEntry
var downloadOldFiles:Array = [] # Files of the same mod that get deleted after the download finishes
var replaceDialogEntry:ModEntry
var replaceDialogOldFiles:Array = []

const FILTERS = [["all", "All mods"], ["favorites", "Favorites"], ["installed", "Installed"], ["updates", "Updates"]]

signal closePressed
signal modFilesReplaced(oldPaths, newPath) # The launcher puts newPath at the load order position of the old files

func _ready():
	for filter in FILTERS:
		filterOption.add_item(filter[1])
	replaceDialog.get_ok().text = "Replace"
	replaceDialog.add_button("Keep both", true, "keep")

func _on_ModBrowser_visibility_changed():
	if(visible && !downloadedMods):
		downloadedMods = true
		var error = http_request.request("https://raw.githubusercontent.com/Alexofp/BDCCMods/main/allmods.json")
		if error != OK:
			Log.printerr("[ModBrowser] An error occurred in the HTTP request.")
	elif(visible && !allMods.empty()):
		# Mods could have been deleted in the launcher since the last time
		refreshInstalled()

func resetMods():
	pickedModEntry = null
	Util.delete_children(modList)
	allMods.clear()

func updateModList():
	visualModEntries.clear()
	Util.delete_children(modList)
	for modEntry in getVisibleMods():
		var newBrowserEntry = modEntryScene.instance()
		modList.add_child(newBrowserEntry)
		newBrowserEntry.setModEntry(modEntry, getDisplayStatus(modEntry), state.isFavorite(modEntry.group))
		var _ok = newBrowserEntry.connect("onSelected", self, "onModEntrySelected")
		if(modEntry == pickedModEntry):
			newBrowserEntry.makeActive()
		visualModEntries.append(newBrowserEntry)

func getVisibleMods() -> Array:
	var result = []
	for mod in allMods:
		if(filterType != "all"):
			if(!isLatestListing(mod)):
				continue
			if(filterType == "favorites" && !state.isFavorite(mod.group)):
				continue
			if(filterType == "installed" && ModBrowserState.getStatus(mod.group) == ""):
				continue
			if(filterType == "updates" && !(ModBrowserState.getStatus(mod.group) in ["update", "duplicate"])):
				continue
		if(searchText != ""):
			if searchText.begins_with("@"):
				if mod.author.to_lower().find(searchText.to_lower().trim_prefix("@")) == -1:
					continue
			elif !(searchText.to_lower() in mod.name.to_lower()):
				continue
		result.append(mod)
	return result

# Some mods are listed more than once, the last listing is the current version
func isLatestListing(mod:ModEntry) -> bool:
	return mod.group == null || mod.group["latestIndex"] == mod.index

func getDisplayStatus(mod:ModEntry) -> String:
	if(!isLatestListing(mod)):
		return "old"
	return ModBrowserState.getStatus(mod.group)

func refreshInstalled():
	state.scanInstalled(allMods)
	updateModList()
	updatePickedModEntry()

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

	state.buildGroups(allMods)
	state.scanInstalled(allMods)

	sortType = "newest"
	allMods.sort_custom(self, "sort_newest")
	updateModList()

func updatePickedModEntry():
	for visualModEntry in visualModEntries:
		if(visualModEntry.storedEntry == pickedModEntry):
			visualModEntry.makeActive()
		else:
			visualModEntry.makeInactive()

	favoriteButton.disabled = (pickedModEntry == null)
	downloadModButton.text = "Download mod"

	if(pickedModEntry == null):
		modDescriptionLabel.bbcode_text = "Select a mod on the left"
	else:
		var group = pickedModEntry.group
		var status:String = ModBrowserState.getStatus(group)
		favoriteButton.text = "Remove from favorites" if state.isFavorite(group) else "Add to favorites"
		if(!isLatestListing(pickedModEntry)):
			downloadModButton.text = "Download older version"
		elif(status in ["update", "duplicate"]):
			downloadModButton.text = "Update mod"
		elif(status == "installed"):
			downloadModButton.text = "Download again"

		var text = ""
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

		if(!isLatestListing(pickedModEntry)):
			text += "[color=yellow]This is an older listing, there is a newer one with version "+str(group["latestVersion"])+"[/color]\n"
		if(group != null):
			for fileData in group["files"]:
				text += "Installed: "+str(fileData["file"])+(" (version "+str(fileData["version"])+")" if fileData["version"] != "" else "")+"\n"
		if(status == "update"):
			text += "[color=lime]Update available: version "+str(group["latestVersion"])+"[/color]\n"
		elif(status == "duplicate"):
			text += "[color=#ff9944]More than one file of this mod is installed, updating replaces all of them[/color]\n"

		text += "\n"
		text += str(pickedModEntry.description)

		modDescriptionLabel.bbcode_text = text

func onModEntrySelected(theModEntry):
	pickedModEntry = theModEntry
	updatePickedModEntry()




func _on_DownloadModButton_pressed():
	if(pickedModEntry == null || downloadingEntry != null):
		return

	var fileName = pickedModEntry.download.get_file()
	var oldFiles = []
	# An older listing never replaces anything, it would delete the newer version
	if(pickedModEntry.group != null && isLatestListing(pickedModEntry)):
		for fileData in pickedModEntry.group["files"]:
			# Windows file names ignore case, so "mod.zip" is the same file as "Mod.zip"
			if(fileData["file"].to_lower() != fileName.to_lower()):
				oldFiles.append(fileData["file"])

	if(oldFiles.empty()):
		startDownload(pickedModEntry, [])
		return

	replaceDialogEntry = pickedModEntry
	replaceDialogOldFiles = oldFiles
	replaceDialog.dialog_text = "'"+pickedModEntry.name+"' is already installed. After the download these files will be deleted and "+fileName+" takes their place in the load order:\n\n"+PoolStringArray(oldFiles).join("\n")+"\n\n'Keep both' downloads without deleting anything."
	replaceDialog.popup_centered()

func _on_ReplaceDialog_confirmed():
	startDownload(replaceDialogEntry, replaceDialogOldFiles)

func _on_ReplaceDialog_custom_action(action):
	if(action == "keep"):
		replaceDialog.hide()
		startDownload(replaceDialogEntry, [])

func getTempDownloadPath(modEntry:ModEntry) -> String:
	# Not a .zip so the launcher never picks up a half-downloaded file
	return GlobalRegistry.getModsFolder().plus_file(modEntry.download.get_file()+".part")

func startDownload(modEntry:ModEntry, oldFiles:Array):
	if(modEntry == null || downloadingEntry != null):
		return
	downloadingEntry = modEntry
	downloadOldFiles = oldFiles

	downloadingContainer.visible = true
	http_request_mod.download_file = getTempDownloadPath(modEntry)
	var error = http_request_mod.request(modEntry.download)
	if error != OK:
		downloadingEntry = null
		downloadingContainer.visible = false
		Log.printerr("[ModBrowser] An error occurred in the HTTP request.")
		showMessage("An error occurred in the HTTP request.")
	else:
		Log.print("Downloading mod: "+str(modEntry.download))


func _on_HTTPRequestMod_request_completed(result, response_code, _headers, _body):
	downloadingContainer.visible = false
	var modEntry:ModEntry = downloadingEntry
	downloadingEntry = null
	if(modEntry == null):
		return

	var dir = Directory.new()
	var tempPath = getTempDownloadPath(modEntry)
	if result != HTTPRequest.RESULT_SUCCESS || response_code >= 400:
		if(dir.file_exists(tempPath)):
			var _ok = dir.remove(tempPath)
		Log.printerr("[ModBrowser] Couldn't download mod (result "+str(result)+", code "+str(response_code)+")")
		showMessage("Couldn't download mod")
		return

	var modsFolder = GlobalRegistry.getModsFolder()
	var fileName = modEntry.download.get_file()
	var finalPath = modsFolder.plus_file(fileName)
	# Keep the file that is replaced until the new one is in place
	var backupPath = finalPath+".old"
	var hadOldFile = dir.file_exists(finalPath)
	if(hadOldFile):
		if(dir.file_exists(backupPath)):
			var _ok = dir.remove(backupPath)
		if(dir.rename(finalPath, backupPath) != OK):
			var _ok = dir.remove(tempPath)
			Log.printerr("[ModBrowser] Couldn't move "+finalPath+" out of the way")
			showMessage("Couldn't save "+fileName)
			return
	if(dir.rename(tempPath, finalPath) != OK):
		if(hadOldFile):
			var _ok = dir.rename(backupPath, finalPath)
		Log.printerr("[ModBrowser] Couldn't move "+tempPath+" to "+finalPath)
		showMessage("Couldn't save "+fileName)
		return
	if(hadOldFile):
		var _ok = dir.remove(backupPath)

	var removedPaths = []
	for oldFile in downloadOldFiles:
		if(oldFile.to_lower() == fileName.to_lower()):
			continue
		var oldPath = modsFolder.plus_file(oldFile)
		if(dir.remove(oldPath) == OK):
			removedPaths.append(oldPath)
		else:
			Log.printerr("[ModBrowser] Couldn't delete the old mod file "+oldPath)
	if(!removedPaths.empty()):
		emit_signal("modFilesReplaced", removedPaths, finalPath)

	if(modEntry.group != null):
		state.recordDownload(modEntry.group, fileName, modEntry.modversion)
	refreshInstalled()

	Log.print("Mod downloaded")
	if(!removedPaths.empty()):
		var removedFiles = []
		for removedPath in removedPaths:
			removedFiles.append(removedPath.get_file())
		Log.print("Replaced old mod files: "+str(removedFiles))
		showMessage("Updated '"+modEntry.name+"'. Replaced:\n"+PoolStringArray(removedFiles).join("\n"))

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

func _on_FilterOption_item_selected(index):
	filterType = FILTERS[index][0]
	updateModList()

func _on_FavoriteButton_pressed():
	if(pickedModEntry == null || pickedModEntry.group == null):
		return
	state.toggleFavorite(pickedModEntry.group)
	updateModList()
	updatePickedModEntry()

func _on_CloseButton_pressed():
	emit_signal("closePressed")


func _on_RichTextLabel_meta_clicked(meta):
	var _ok = Util.fixed_shell_open(meta)


func _on_ModSearch_text_changed(new_text: String):
	if new_text.length() > 2 || new_text.length() == 0:
		searchText = new_text
		updateModList()

