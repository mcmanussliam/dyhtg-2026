class_name ProfileStore
extends RefCounted
## Shared ConfigFile persistence for local preferences and cosmetic profiles.


static func load_file(path: String) -> ConfigFile:
	var file := ConfigFile.new()
	file.load(path)
	return file


static func save_file(file: ConfigFile, path: String) -> Error:
	var temporary := path + ".tmp"
	var error := file.save(temporary)
	if error != OK:
		return error
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)
	)
