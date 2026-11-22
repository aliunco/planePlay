class_name AudioManager
extends Node
## Tiny synthesized sound set. No audio files to ship or license: every effect is
## generated as a 16-bit mono WAV at load time and played through a small pool.

const MIX_RATE: int = 22050
const POOL_SIZE: int = 8
## The looping engine note: its length must hold a whole number of cycles of every
## partial, so the loop point cannot click.
const ENGINE_LOOP_SECONDS: float = 0.5
const ENGINE_BASE_HZ: float = 82.0
## How quickly the engine note slides to a new pitch and volume, per second.
const ENGINE_SMOOTHING: float = 8.0
## Once the note has faded below this it is stopped instead of left playing.
const ENGINE_SILENT_DB: float = -55.0

@export var enabled: bool = true
@export var volume_db: float = -11.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []

# Continuous engine drone, driven by the airplane that is flying it.
var _engine_player: AudioStreamPlayer
var _engine_active: bool = false
var _engine_pitch: float = 1.0
var _engine_volume: float = ENGINE_SILENT_DB - 5.0
var _engine_target_pitch: float = 1.0
var _engine_target_volume: float = ENGINE_SILENT_DB - 5.0


func _ready() -> void:
	_streams = {
		"shoot": _synthesize(760.0, 220.0, 0.09, 0.55, 0.18, 2.2),
		"hit": _synthesize(320.0, 120.0, 0.14, 0.6, 0.55, 2.6),
		"explode": _synthesize(180.0, 40.0, 0.65, 0.85, 0.92, 1.4),
		"launch": _synthesize(180.0, 620.0, 0.30, 0.4, 0.1, 1.2),
		# Throttle shifts: a short engine note that jumps a step, up or down.
		"gear_up": _synthesize(300.0, 780.0, 0.24, 0.46, 0.16, 1.7),
		"gear_down": _synthesize(720.0, 320.0, 0.24, 0.42, 0.16, 1.7),
		"ui": _synthesize(900.0, 1250.0, 0.05, 0.35, 0.0, 2.0),
		# Pickups: a bright chime for a repair, a heavier thunk for a crate, and a
		# deeper bark for the crate rounds themselves.
		"repair": _synthesize(560.0, 1180.0, 0.22, 0.45, 0.0, 1.6),
		"special": _synthesize(220.0, 660.0, 0.28, 0.5, 0.25, 1.5),
		"special_shot": _synthesize(420.0, 90.0, 0.22, 0.6, 0.6, 2.0),
		# A bomb leaving the rack: a dull clunk, quieter than the burst it makes.
		"bomb": _synthesize(150.0, 70.0, 0.2, 0.5, 0.45, 2.3),
		# The jet boost: a short bright whoosh as the flame lights.
		"boost": _synthesize(240.0, 980.0, 0.42, 0.34, 0.22, 1.5),
		# Flares: a bright hiss that spits and drops away.
		"flare": _synthesize(1400.0, 380.0, 0.55, 0.3, 0.55, 1.8),
		# The shield coming up: a low sweep that rises into a steady hum.
		"shield": _synthesize(180.0, 720.0, 0.75, 0.32, 0.18, 1.4),
	}
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.volume_db = volume_db
		add_child(player)
		_players.append(player)

	# The drone keeps sliding towards its new pitch and volume even while the
	# match is paused, so pausing ducks the engine instead of freezing it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = _build_engine_loop()
	_engine_player.volume_db = _engine_volume
	add_child(_engine_player)


## Drives the continuous engine note. The airplane decides the pitch and volume
## (idle, rolling, or one step per throttle gear) and this smooths towards them,
## so a gear change is heard as the engine climbing rather than a jump.
func set_engine(active: bool, pitch: float = 1.0, volume_db: float = ENGINE_SILENT_DB) -> void:
	if not enabled:
		_engine_active = false
		return
	_engine_active = active
	_engine_target_pitch = clampf(pitch, 0.3, 3.0)
	_engine_target_volume = volume_db


func _process(delta: float) -> void:
	if _engine_player == null:
		return
	var blend := clampf(delta * ENGINE_SMOOTHING, 0.0, 1.0)
	var target_volume := _engine_target_volume if _engine_active else ENGINE_SILENT_DB - 5.0
	_engine_pitch = lerpf(_engine_pitch, _engine_target_pitch, blend)
	_engine_volume = lerpf(_engine_volume, target_volume, blend)
	_engine_player.pitch_scale = _engine_pitch
	_engine_player.volume_db = _engine_volume
	if _engine_active:
		if not _engine_player.playing:
			_engine_player.play()
	elif _engine_player.playing and _engine_volume <= ENGINE_SILENT_DB:
		_engine_player.stop()


## `pitch` shifts the whole effect up or down, which the throttle uses so the
## upper gears rev higher than the lower ones.
func play(sound: StringName, pitch: float = 1.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	for player in _players:
		if not player.playing:
			_start(player, sound, pitch)
			return
	# All busy: steal the first one rather than dropping the sound entirely.
	_start(_players[0], sound, pitch)


func _start(player: AudioStreamPlayer, sound: StringName, pitch: float) -> void:
	player.stream = _streams[sound]
	player.pitch_scale = pitch
	player.play()


## A seamless engine note: a low fundamental with two harmonics and a slow
## propeller beat. At 82 Hz over half a second every partial completes a whole
## number of cycles, which is what makes it loop without a click.
func _build_engine_loop() -> AudioStreamWAV:
	var sample_count := int(MIX_RATE * ENGINE_LOOP_SECONDS)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(MIX_RATE)
		var phase := TAU * ENGINE_BASE_HZ * t
		var wave := sin(phase) * 0.62 + sin(phase * 2.0) * 0.24 + sin(phase * 3.0) * 0.12
		# Four beats a second: also a whole number of cycles in the loop.
		wave *= 0.88 + 0.12 * sin(TAU * 4.0 * t)
		data.encode_s16(i * 2, int(clampf(wave * 0.55, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	return stream


## Builds a short pitched blip with an optional noise layer.
func _synthesize(
	freq_start: float,
	freq_end: float,
	duration: float,
	amplitude: float,
	noise_amount: float,
	decay_power: float
) -> AudioStreamWAV:
	var sample_count := maxi(1, int(MIX_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for i in sample_count:
		var t := float(i) / float(sample_count)
		var frequency := lerpf(freq_start, freq_end, t)
		phase += TAU * frequency / float(MIX_RATE)
		var envelope := pow(1.0 - t, decay_power)
		var wave := sin(phase) * (1.0 - noise_amount)
		wave += randf_range(-1.0, 1.0) * noise_amount
		var value := int(clampf(wave * envelope * amplitude, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
