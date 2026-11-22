class_name PlaneRoster
extends RefCounted
## The ten fighters a pilot can take into a match, oldest first: fabric-and-piston
## props, then the jets, and last a fighter that never existed.
##
## Every airframe has its own top speed, turn rate, rate of fire and armour. The
## numbers follow the design of the aircraft rather than a tidy curve: speed and
## fire rate climb from the props to the jets, turn rate climbs with them, and
## armour is spread the other way - the heavy twin-boom is the toughest machine in
## the list and the experimental Aurora the most fragile. Nothing is rolled at
## runtime, so both ends of a LAN match fly exactly the same aircraft.
##
## Health is kept inside the 137..169 window on purpose: the game's five-hit rule
## depends on it, whatever the armour.

## Display scale for the picker's bars: each property is normalised against the
## full spread of the roster, so the Kestrel sits low on the bar and the Aurora at
## the top of the same scale.
const SPEED_MIN: float = 142.0
const SPEED_MAX: float = 212.0
const TURN_MIN: float = 82.0
const TURN_MAX: float = 128.0
## Rounds per second, derived from each fighter's fire cooldown.
const FIRE_MIN: float = 2.6
const FIRE_MAX: float = 5.0
const ARMOUR_MIN: float = 134.0
const ARMOUR_MAX: float = 172.0

static var _planes: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _planes.is_empty():
		_build()
	return _planes


static func count() -> int:
	return all().size()


static func entry(index: int) -> Dictionary:
	var planes := all()
	return planes[posmod(index, planes.size())]


static func plane_name(index: int) -> String:
	return str(entry(index)["name"])


## Rounds per second a fighter can put out.
static func fire_rate(index: int) -> float:
	return 1.0 / maxf(0.05, float(entry(index)["cooldown"]))


## A rival for the AI pilot: a different airframe from the player's, drawn from the
## session key, so a match pairs a prop with a jet or a jet with a stealth fighter.
static func rival_for(player_index: int, seed_value: int) -> int:
	if count() < 2:
		return player_index
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pick := rng.randi_range(0, count() - 2)
	if pick >= posmod(player_index, count()):
		pick += 1
	return pick


## Writes one roster entry into a plane config. `own_livery` keeps the fighter's
## own paint; false leaves the caller's colours alone, which is how the opponent
## stays crimson whatever airframe it flies.
static func apply(config: PlaneConfig, index: int, own_livery: bool = true) -> void:
	if config == null:
		return
	var plane := entry(index)
	config.plane_silhouette = int(plane["silhouette"])
	config.plane_name = str(plane["name"])
	if own_livery:
		config.livery_body = plane["body"]
		config.livery_accent = plane["accent"]
		config.livery_belly = plane["belly"]
	config.plane_speed = float(plane["speed"])
	config.rotation_speed = float(plane["turn"])
	config.fire_cooldown = maxf(0.08, float(plane["cooldown"]))
	config.max_health = clampi(int(plane["health"]), 137, 169)


## The four bars the picker draws: label, 0..1 fill and the number itself.
static func stat_rows(index: int) -> Array[Dictionary]:
	var plane := entry(index)
	return [
		{
			"label": "SPEED",
			"ratio": _ratio(float(plane["speed"]), SPEED_MIN, SPEED_MAX),
			"value": "%d" % int(plane["speed"]),
		},
		{
			"label": "TURN",
			"ratio": _ratio(float(plane["turn"]), TURN_MIN, TURN_MAX),
			"value": "%d" % int(plane["turn"]),
		},
		{
			"label": "FIRE",
			"ratio": _ratio(1.0 / float(plane["cooldown"]), FIRE_MIN, FIRE_MAX),
			"value": "%.1f" % (1.0 / float(plane["cooldown"])),
		},
		{
			"label": "ARMOUR",
			"ratio": _ratio(float(plane["health"]), ARMOUR_MIN, ARMOUR_MAX),
			"value": "%d" % int(plane["health"]),
		},
	]


static func _ratio(value: float, low: float, high: float) -> float:
	return clampf((value - low) / maxf(0.001, high - low), 0.0, 1.0)


## The whole roster, built once. `speed` is the gear-2 cruise in px/s and `turn`
## the nose rate in degrees per second; both are read straight into PlaneConfig.
static func _build() -> void:
	_planes = [
		{
			"name": "Kestrel Mk I",
			"role": "Prop fighter",
			"silhouette": PlaneModel3D.Silhouette.PROP,
			"body": Color("4c5c36"),
			"accent": Color("e6b93f"),
			"belly": Color("4c5643"),
			"speed": 152.0,
			"turn": 96.0,
			"cooldown": 0.36,
			"health": 150,
		},
		{
			"name": "Corsair FB",
			"role": "Gull-wing fighter",
			"silhouette": PlaneModel3D.Silhouette.GULL,
			"body": Color("2d3f63"),
			"accent": Color("e8dcc0"),
			"belly": Color("26314a"),
			"speed": 156.0,
			"turn": 92.0,
			"cooldown": 0.34,
			"health": 162,
		},
		{
			"name": "Spitfire IX",
			"role": "Interceptor",
			"silhouette": PlaneModel3D.Silhouette.ELLIPSE,
			"body": Color("6f7f5c"),
			"accent": Color("b8352f"),
			"belly": Color("5d6b4e"),
			"speed": 161.0,
			"turn": 110.0,
			"cooldown": 0.33,
			"health": 144,
		},
		{
			"name": "Mustang P-51",
			"role": "Long-range escort",
			"silhouette": PlaneModel3D.Silhouette.LONGNOSE,
			"body": Color("b9bec2"),
			"accent": Color("c0392b"),
			"belly": Color("969ca0"),
			"speed": 168.0,
			"turn": 101.0,
			"cooldown": 0.31,
			"health": 150,
		},
		{
			"name": "Lightning P-38",
			"role": "Twin-boom heavy",
			"silhouette": PlaneModel3D.Silhouette.TWIN_BOOM,
			"body": Color("7c8488"),
			"accent": Color("d9b23c"),
			"belly": Color("666d70"),
			"speed": 163.0,
			"turn": 88.0,
			"cooldown": 0.28,
			"health": 168,
		},
		{
			"name": "Sabre F-86",
			"role": "Swept-wing jet",
			"silhouette": PlaneModel3D.Silhouette.EARLY_JET,
			"body": Color("b6bcc4"),
			"accent": Color("4f7fb5"),
			"belly": Color("8e959c"),
			"speed": 178.0,
			"turn": 104.0,
			"cooldown": 0.30,
			"health": 150,
		},
		{
			"name": "Mirage Delta",
			"role": "Delta interceptor",
			"silhouette": PlaneModel3D.Silhouette.DELTA,
			"body": Color("9fb6c4"),
			"accent": Color("e07a2f"),
			"belly": Color("8095a1"),
			"speed": 185.0,
			"turn": 100.0,
			"cooldown": 0.27,
			"health": 146,
		},
		{
			"name": "Eagle F-15",
			"role": "Air-superiority jet",
			"silhouette": PlaneModel3D.Silhouette.TWIN_TAIL,
			"body": Color("8d9aa4"),
			"accent": Color("3f86c9"),
			"belly": Color("727e88"),
			"speed": 192.0,
			"turn": 111.0,
			"cooldown": 0.25,
			"health": 155,
		},
		{
			"name": "Raptor F-22",
			"role": "Stealth fighter",
			"silhouette": PlaneModel3D.Silhouette.STEALTH,
			"body": Color("4a5058"),
			"accent": Color("69e0ff"),
			"belly": Color("383e46"),
			"speed": 199.0,
			"turn": 118.0,
			"cooldown": 0.23,
			"health": 148,
		},
		{
			"name": "Aurora X",
			"role": "Experimental",
			"silhouette": PlaneModel3D.Silhouette.SCIFI,
			"body": Color("2b2440"),
			"accent": Color("5ff5e0"),
			"belly": Color("1f1a30"),
			"speed": 208.0,
			"turn": 124.0,
			"cooldown": 0.20,
			"health": 139,
		},
	]
