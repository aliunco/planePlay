class_name SurvivalRecord
extends RefCounted
## The best survival run on this device. Kept in the user data folder, so it
## survives app restarts and reinstalls of the executable.

const PATH := "user://survival_best.cfg"
const SECTION := "survival"
const KEY := "best"


static func load_best() -> int:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return 0
	return maxi(0, int(file.get_value(SECTION, KEY, 0)))


static func save_best(value: int) -> void:
	var file := ConfigFile.new()
	# Keep anything else already stored in the file.
	file.load(PATH)
	file.set_value(SECTION, KEY, maxi(0, value))
	file.save(PATH)
