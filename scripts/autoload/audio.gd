extends Node
## Procedural audio: every sound effect and ambient loop is synthesized at startup,
## so the game ships with zero audio files.

const RATE := 22050
const POOL := 20

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last_play: Dictionary = {}
var _ambient: AudioStreamPlayer
var _ambient_name := ""
var _noise_rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise_rng.seed = 1337
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Ambient"
	add_child(_ambient)
	_build_all()


func play(sound: String, volume_db: float = 0.0, pitch_var: float = 0.08, min_interval: float = 0.035) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(sound, -1.0)) < min_interval:
		return
	_last_play[sound] = now
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[0]
		_players.push_back(_players.pop_front())
	player.stream = s
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	player.play()


func set_ambient(kind: String) -> void:
	if kind == _ambient_name:
		return
	_ambient_name = kind
	var s: AudioStream = _streams.get("amb_" + kind)
	if s == null:
		_ambient.stop()
		return
	_ambient.stream = s
	_ambient.volume_db = -6.0
	_ambient.play()


# ------------------------------------------------------------------ synthesis

func _build_all() -> void:
	_streams["swing"] = _wav(_tone(0.16, 0, 0, "noise", 0.55, 0.03, 2.0, 0.0, 0.32))
	_streams["hit"] = _wav(_mix(_tone(0.15, 170, 55, "sine", 0.9, 0.003, 2.2), _tone(0.08, 0, 0, "noise", 0.5, 0.002, 3.0, 0.0, 0.5)))
	_streams["crit"] = _wav(_mix(_mix(_tone(0.18, 190, 50, "sine", 0.9, 0.003, 2.0), _tone(0.1, 0, 0, "noise", 0.55, 0.002, 3.0, 0.0, 0.6)), _tone(0.14, 1500, 1900, "square", 0.22, 0.003, 2.0)))
	_streams["enemy_die"] = _wav(_crush(_mix(_tone(0.38, 620, 70, "square", 0.45, 0.005, 1.4), _tone(0.3, 0, 0, "noise", 0.35, 0.002, 2.0, 0.0, 0.4)), 6))
	_streams["hurt"] = _wav(_mix(_tone(0.24, 240, 110, "saw", 0.5, 0.003, 1.6, 0.0, 0.35), _tone(0.12, 0, 0, "noise", 0.4, 0.002, 2.5, 0.0, 0.5)))
	_streams["data"] = _wav(_tone(0.09, 900, 1500, "sine", 0.32, 0.003, 1.5))
	_streams["gold"] = _wav(_cat(_tone(0.05, 1318, 1318, "square", 0.16, 0.002, 1.0, 0.0, 0.5), _tone(0.12, 1760, 1760, "square", 0.16, 0.002, 1.8, 0.0, 0.5)))
	_streams["item"] = _wav(_cat(_cat(_tone(0.07, 523, 523, "tri", 0.4, 0.003, 1.0), _tone(0.07, 659, 659, "tri", 0.4, 0.003, 1.0)), _tone(0.2, 784, 784, "tri", 0.4, 0.003, 1.5)))
	_streams["levelup"] = _wav(_cat(_cat(_cat(_tone(0.09, 523, 523, "square", 0.25, 0.003, 0.8, 0.0, 0.6), _tone(0.09, 659, 659, "square", 0.25, 0.003, 0.8, 0.0, 0.6)), _tone(0.09, 784, 784, "square", 0.25, 0.003, 0.8, 0.0, 0.6)), _tone(0.5, 1046, 1046, "square", 0.25, 0.003, 1.5, 0.0, 0.6)))
	_streams["dodge"] = _wav(_tone(0.24, 0, 0, "noise", 0.45, 0.08, 1.5, 0.0, 0.15))
	_streams["ui_click"] = _wav(_tone(0.035, 1200, 900, "sine", 0.3, 0.001, 2.0))
	_streams["ui_hover"] = _wav(_tone(0.02, 1500, 1500, "sine", 0.12, 0.001, 2.0))
	_streams["notify"] = _wav(_cat(_tone(0.12, 784, 784, "sine", 0.32, 0.004, 1.2), _tone(0.28, 1175, 1175, "sine", 0.3, 0.004, 1.8)))
	_streams["boss_roar"] = _wav(_crush(_mix(_tone(1.3, 95, 42, "saw", 0.6, 0.05, 1.0, 0.0, 0.3), _tone(1.3, 0, 0, "noise", 0.35, 0.05, 1.2, 0.0, 0.2)), 4))
	_streams["slam"] = _wav(_mix(_tone(0.55, 80, 30, "sine", 1.0, 0.002, 1.6), _tone(0.45, 0, 0, "noise", 0.6, 0.002, 2.0, 0.0, 0.18)))
	_streams["shoot"] = _wav(_tone(0.13, 950, 280, "square", 0.2, 0.002, 1.5, 0.0, 0.5))
	_streams["teleport"] = _wav(_mix(_tone(0.45, 300, 1800, "sine", 0.35, 0.01, 1.2), _tone(0.45, 150, 900, "tri", 0.2, 0.01, 1.2)))
	_streams["door"] = _wav(_mix(_tone(0.1, 110, 90, "square", 0.3, 0.002, 2.0, 0.0, 0.3), _tone(0.18, 0, 0, "noise", 0.3, 0.002, 2.0, 0.0, 0.3)))
	_streams["explosion"] = _wav(_crush(_mix(_tone(0.7, 0, 0, "noise", 0.7, 0.002, 1.3, 0.0, 0.25), _tone(0.6, 90, 28, "sine", 0.8, 0.002, 1.5)), 3))
	_streams["unlock"] = _wav(_cat(_cat(_tone(0.1, 659, 659, "tri", 0.4, 0.003, 0.8), _tone(0.1, 880, 880, "tri", 0.4, 0.003, 0.8)), _tone(0.45, 1318, 1318, "tri", 0.4, 0.003, 1.6)))
	_streams["deny"] = _wav(_cat(_tone(0.09, 220, 200, "square", 0.22, 0.002, 1.0, 0.0, 0.4), _tone(0.14, 180, 160, "square", 0.22, 0.002, 1.5, 0.0, 0.4)))
	_streams["buy"] = _wav(_cat(_tone(0.06, 1046, 1046, "square", 0.18, 0.002, 1.0, 0.0, 0.5), _tone(0.2, 1568, 1568, "sine", 0.3, 0.002, 1.8)))
	_streams["forge"] = _wav(_mix(_tone(0.35, 1800, 1700, "sine", 0.35, 0.001, 3.0), _tone(0.12, 0, 0, "noise", 0.5, 0.001, 3.0, 0.0, 0.7)))
	_streams["enchant"] = _wav(_mix(_tone(0.6, 400, 1600, "sine", 0.3, 0.02, 1.2), _tone(0.6, 600, 2400, "tri", 0.15, 0.02, 1.2)))
	_streams["telegraph"] = _wav(_tone(0.22, 440, 660, "square", 0.12, 0.005, 1.0, 0.0, 0.4))
	_streams["zap"] = _wav(_crush(_tone(0.16, 2200, 400, "saw", 0.25, 0.001, 1.5, 0.0, 0.6), 3))
	_streams["shield"] = _wav(_tone(0.3, 500, 1200, "tri", 0.3, 0.01, 1.4))
	_streams["block"] = _wav(_mix(_tone(0.12, 900, 700, "square", 0.25, 0.001, 2.0, 0.0, 0.4), _tone(0.08, 0, 0, "noise", 0.3, 0.001, 3.0, 0.0, 0.6)))
	_streams["death"] = _wav(_crush(_tone(1.2, 400, 40, "saw", 0.5, 0.01, 1.0, 0.0, 0.4), 5))
	_streams["chest"] = _wav(_cat(_tone(0.15, 0, 0, "noise", 0.4, 0.002, 2.0, 0.0, 0.3), _tone(0.6, 523, 1046, "tri", 0.4, 0.01, 1.5)))
	_streams["amb_hub"] = _wav(_ambient_office(0.6), true)
	_streams["amb_office"] = _wav(_ambient_office(1.0), true)
	_streams["amb_dungeon"] = _wav(_ambient_dungeon(), true)
	_streams["amb_menu"] = _wav(_ambient_office(0.45), true)


func _tone(dur: float, f0: float, f1: float, wave: String, vol: float, attack: float, decay_pow: float, noise_mix: float = 0.0, lp: float = 1.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp_state := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := f0 * pow(f1 / f0, t) if f0 > 0.0 and f1 > 0.0 else f0
		phase += f / RATE
		var p := fmod(phase, 1.0)
		var s := 0.0
		match wave:
			"sine": s = sin(TAU * p)
			"square": s = 1.0 if p < 0.5 else -1.0
			"saw": s = 2.0 * p - 1.0
			"tri": s = 4.0 * absf(p - 0.5) - 1.0
			"noise": s = _noise_rng.randf_range(-1.0, 1.0)
		if noise_mix > 0.0:
			s = lerpf(s, _noise_rng.randf_range(-1.0, 1.0), noise_mix)
		lp_state += (s - lp_state) * lp
		var env := minf(1.0, float(i) / maxf(1.0, attack * RATE)) * pow(1.0 - t, decay_pow)
		out[i] = lp_state * env * vol
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out


func _cat(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	out.append_array(b)
	return out


func _crush(a: PackedFloat32Array, hold: int) -> PackedFloat32Array:
	var out := a.duplicate()
	for i in out.size():
		out[i] = a[i - (i % hold)]
	return out


func _ambient_office(level: float) -> PackedFloat32Array:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * 60.0 * t) * 0.12 + sin(TAU * 120.0 * t) * 0.07 + sin(TAU * 180.0 * t) * 0.025
		s += sin(TAU * 3400.0 * t) * 0.004
		lp += (_noise_rng.randf_range(-1.0, 1.0) - lp) * 0.04
		s += lp * 0.25
		out[i] = s * level
	return out


func _ambient_dungeon() -> PackedFloat32Array:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var saw1 := 2.0 * fmod(55.0 * t, 1.0) - 1.0
		var saw2 := 2.0 * fmod(55.5 * t, 1.0) - 1.0
		lp += ((saw1 + saw2) * 0.5 - lp) * 0.03
		var s := lp * 0.35 + sin(TAU * 41.0 * t) * 0.18 + sin(TAU * 60.0 * t) * 0.05
		if _noise_rng.randf() < 0.0008:
			s += _noise_rng.randf_range(-0.6, 0.6)
		out[i] = s * 0.9
	return out


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
