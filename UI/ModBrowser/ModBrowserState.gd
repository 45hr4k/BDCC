extends Reference

# Remembers favorite mods and which installed file belongs to which mod, so the mod browser can
# show installed mods, offer updates and replace the old file instead of downloading a second copy next to it.
# The version and the file name usually change between updates, so a mod is identified by its name
# plus at least one shared author (different mods sometimes share the same name).

const STATE_PATH = "user://modBrowser.json"

var favorites:Array = [] # [{name, authors}]
var installed:Array = [] # [{name, authors, file, version}] files that were downloaded by the browser

# One group per mod, all listings of the same mod share it. Filled by buildGroups()
# {name, nname, authors, latestVersion, latestFile, latestIndex, files:[{file, version}]}
var groups:Array = []

var versionRegex:RegEx

func _init():
	versionRegex = RegEx.new()
	var _ok = versionRegex.compile("(?i)[ _\\-]*(v|ver)?\\d+(\\.\\d+)*([a-z]+\\d*)?$")
	loadState()

static func normName(text:String) -> String:
	var result:String = ""
	for c in text.to_lower():
		if((c >= "a" && c <= "z") || (c >= "0" && c <= "9")):
			result += c
	return result

static func splitAuthors(text:String) -> Array:
	var result:Array = []
	for part in text.replace("/", ",").replace("&", ",").replace(" and ", ",").split(","):
		var author:String = normName(part)
		if(author != "" && !(author in result)):
			result.append(author)
	return result

static func authorsOverlap(a:Array, b:Array) -> bool:
	if(a.empty() || b.empty()):
		return true
	for author in a:
		if(author in b):
			return true
	return false

# "0.10.7[color=red]" -> "0.10.7", "v1.2" -> "1.2"
static func cleanVersion(text:String) -> String:
	var bbcodeStart:int = text.find("[")
	if(bbcodeStart >= 0):
		text = text.substr(0, bbcodeStart)
	text = text.strip_edges().to_lower()
	if(text.begins_with("v")):
		text = text.substr(1)
	return text

# "SongsHoofySpecies_v0.9.7fix1.zip" -> "songshoofyspecies"
func fileStem(file:String) -> String:
	return normName(versionRegex.sub(file.get_basename(), ""))

func buildGroups(modEntries:Array):
	groups.clear()
	var sortedEntries:Array = modEntries.duplicate()
	sortedEntries.sort_custom(self, "sort_index")
	for modEntry in sortedEntries:
		var nname:String = normName(modEntry.name)
		var authors:Array = splitAuthors(modEntry.author)
		var group = findGroup(nname, authors)
		if(group == null):
			group = {name = modEntry.name, nname = nname, authors = [], files = []}
			groups.append(group)
		for author in authors:
			if(!(author in group["authors"])):
				group["authors"].append(author)
		# Later listings are newer, so the last one is the current version
		group["latestVersion"] = modEntry.modversion
		group["latestFile"] = modEntry.download.get_file()
		group["latestIndex"] = modEntry.index
		modEntry.group = group

static func sort_index(a, b):
	return a.index < b.index

func findGroup(nname:String, authors:Array):
	for group in groups:
		if(group["nname"] == nname && authorsOverlap(group["authors"], authors)):
			return group
	return null

# Finds out which files in the mods folder belong to which mod
func scanInstalled(modEntries:Array):
	modInfoCache.clear()
	for group in groups:
		group["files"] = []

	var byFile:Dictionary = {} # listing file name -> [group, version]
	var byStem:Dictionary = {} # file name without version -> group, null if more than one mod has it
	var byName:Dictionary = {} # normalized mod name -> group, null if ambiguous
	for modEntry in modEntries:
		var group = modEntry.group
		var file:String = modEntry.download.get_file()
		byFile[file.to_lower()] = [group, modEntry.modversion]
		addUnique(byStem, fileStem(file), group)
		addUnique(byName, group["nname"], group)

	var stillInstalled:Array = []
	for path in GlobalRegistry.getRawModList():
		var file:String = path.get_file()
		if(file == "BDCC.pck"):
			continue
		var group = null
		var version:String = ""

		var record = getRecord(file)
		if(record != null):
			group = findGroup(record["name"], record["authors"])
			version = record["version"]
			if(group != null):
				stillInstalled.append(record)
		if(group == null && byFile.has(file.to_lower())):
			group = byFile[file.to_lower()][0]
			version = readModInfo(path).get("modversion", byFile[file.to_lower()][1])
		if(group == null && byStem.get(fileStem(file)) != null):
			group = byStem[fileStem(file)]
			version = readModInfo(path).get("modversion", "")
		if(group == null):
			var nname:String = normName(readModInfo(path).get("name", ""))
			if(byName.get(nname) != null):
				group = byName[nname]
				version = readModInfo(path).get("modversion", "")

		if(group != null):
			group["files"].append({file = file, version = str(version), upToDate = isUpToDate(group, file, str(version))})

	if(stillInstalled.size() != installed.size()):
		installed = stillInstalled
		saveState()

static func addUnique(dict:Dictionary, key:String, group):
	if(key == ""):
		return
	if(dict.has(key) && dict[key] != group):
		dict[key] = null
	else:
		dict[key] = group

func getRecord(file:String):
	for record in installed:
		if(record["file"] == file):
			return record
	return null

var modInfoCache:Dictionary = {}
# Reads name and modversion from the json file inside the mod zip
func readModInfo(path:String) -> Dictionary:
	if(modInfoCache.has(path)):
		return modInfoCache[path]
	var result:Dictionary = {}
	modInfoCache[path] = result
	if(path.get_extension() != "zip"):
		return result
	var gdunzip = GDUnzip.new()
	if(!gdunzip.load(path) || gdunzip.files == null):
		return result
	var jsonFile:String = path.get_file().get_basename()+".json"
	if(!gdunzip.files.has(jsonFile)):
		jsonFile = ""
		for file in gdunzip.files:
			if(file.get_extension() == "json" && !("/" in file)):
				jsonFile = file
				break
	if(jsonFile == ""):
		return result
	var uncompressed = gdunzip.uncompress(jsonFile)
	if(!uncompressed):
		return result
	var jsonResult = JSON.parse(uncompressed.get_string_from_utf8())
	if(jsonResult.error != OK || !(jsonResult.result is Dictionary)):
		return result
	for field in ["name", "modversion"]:
		if(jsonResult.result.has(field) && jsonResult.result[field] is String):
			result[field] = jsonResult.result[field]
	return result

# "" (not installed), "installed", "update" or "duplicate" (more than one file of this mod)
static func getStatus(group) -> String:
	if(group == null || group["files"].empty()):
		return ""
	if(group["files"].size() > 1):
		return "duplicate"
	if(group["files"][0]["upToDate"]):
		return "installed"
	return "update"

func isUpToDate(group, file:String, version:String) -> bool:
	if(file == group["latestFile"]):
		# A file name with a version in it ("Mod_v1.2.zip") means it's the same version,
		# the version inside the zip doesn't always match the listing ("0.9.7fix1" vs "0.9.7")
		if(fileStem(file) != normName(file.get_basename())):
			return true
		# Same name for every version ("Mod.zip"), only the version can tell
		return version == "" || cleanVersion(version) == cleanVersion(group["latestVersion"])
	return version != "" && cleanVersion(version) == cleanVersion(group["latestVersion"])

func recordDownload(group, file:String, version:String):
	var newInstalled:Array = []
	for record in installed:
		if(record["file"] == file):
			continue
		if(findGroup(record["name"], record["authors"]) == group):
			continue
		newInstalled.append(record)
	newInstalled.append({name = group["nname"], authors = group["authors"], file = file, version = version})
	installed = newInstalled
	saveState()

func isFavorite(group) -> bool:
	return getFavoriteIndex(group) >= 0

func getFavoriteIndex(group) -> int:
	if(group == null):
		return -1
	for i in range(favorites.size()):
		if(favorites[i]["name"] == group["nname"] && authorsOverlap(favorites[i]["authors"], group["authors"])):
			return i
	return -1

func toggleFavorite(group):
	var index:int = getFavoriteIndex(group)
	if(index >= 0):
		favorites.remove(index)
	else:
		favorites.append({name = group["nname"], authors = group["authors"]})
	saveState()

func loadState():
	if(!File.new().file_exists(STATE_PATH)):
		return
	var jsonResult = JSON.parse(Util.readFile(STATE_PATH))
	if(jsonResult.error != OK || !(jsonResult.result is Dictionary)):
		return
	var data:Dictionary = jsonResult.result
	favorites = []
	for favorite in data.get("favorites", []):
		if(favorite is Dictionary && favorite.get("name") is String && favorite.get("authors") is Array):
			favorites.append(favorite)
	installed = []
	for record in data.get("installed", []):
		if(record is Dictionary && record.get("name") is String && record.get("authors") is Array && record.get("file") is String && record.get("version") is String):
			installed.append(record)

func saveState():
	var file = File.new()
	if(file.open(STATE_PATH, File.WRITE) != OK):
		Log.printerr("[ModBrowser] Couldn't save "+STATE_PATH)
		return
	file.store_string(JSON.print({favorites = favorites, installed = installed}, "\t"))
	file.close()
