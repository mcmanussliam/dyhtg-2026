class_name MachineName
extends RefCounted
## The local player's display name: `--name=` override, computer name, user name, "Player".

const MAX_LENGTH := 24
const FALLBACK := "Player"

static var _cached := ""


## Resolved once per run; never empty.
static func local() -> String:
	if _cached.is_empty():
		_cached = resolve(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	return _cached


static func resolve(args: PackedStringArray) -> String:
	var name := clean(override(args))
	if name.is_empty():
		name = clean(_computer_name())
	if name.is_empty():
		name = clean(_user_name())
	return name if not name.is_empty() else FALLBACK


## The `--name=<name>` value, or "" when absent.
static func override(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--name="):
			return arg.substr(7)
	return ""


## Trimmed, single-spaced and short enough for menus; may be empty.
static func clean(raw: String) -> String:
	var spaced := RegEx.create_from_string("\\s+").sub(raw, " ", true)
	return spaced.strip_edges().left(MAX_LENGTH).strip_edges()


static func _computer_name() -> String:
	match OS.get_name():
		"Windows":
			return OS.get_environment("COMPUTERNAME")
		"macOS":
			return _command("scutil", ["--get", "ComputerName"])
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var name := OS.get_environment("HOSTNAME")
			if name.strip_edges().is_empty() and FileAccess.file_exists("/etc/hostname"):
				name = FileAccess.get_file_as_string("/etc/hostname")
			if name.strip_edges().is_empty():
				name = _command("hostname", [])
			return name
	return ""


static func _user_name() -> String:
	var name := OS.get_environment("USER")
	return name if not name.is_empty() else OS.get_environment("USERNAME")


static func _command(path: String, arguments: PackedStringArray) -> String:
	var output := []
	if OS.execute(path, arguments, output) != 0 or output.is_empty():
		return ""
	return str(output[0])
