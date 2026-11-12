extends Node
## 程序化音效：全部声音在运行时用 AudioStreamGenerator 合成，无外部音频资源
const SAMPLE_RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _player_idx: int = 0
const PLAYER_COUNT := 10


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in PLAYER_COUNT:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_sounds()


func _build_sounds() -> void:
	_streams["pistol"] = _gen_shot(0.12, 0.55, 220.0)
	_streams["shotgun"] = _gen_shot(0.28, 0.9, 110.0)
	_streams["rifle"] = _gen_shot(0.09, 0.4, 300.0)
	_streams["hit"] = _gen_hit()
	_streams["hurt"] = _gen_hurt()
	_streams["reload"] = _gen_reload()
	_streams["kill"] = _gen_kill()
	_streams["empty"] = _gen_empty()
	_streams["buy"] = _gen_buy()
	_streams["wave"] = _gen_wave()
	_streams["shooter_telegraph"] = _gen_telegraph()
	_streams["enemy_die"] = _gen_enemy_die()


func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not _streams.has(name):
		return
	var p: AudioStreamPlayer = _players[_player_idx]
	_player_idx = (_player_idx + 1) % PLAYER_COUNT
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


# ---------- 合成工具 ----------
func _new_stream(seconds: float) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.stereo = false
	s.data = PackedByteArray()
	s.data.resize(int(seconds * SAMPLE_RATE) * 2)
	return s


func _write(s: AudioStreamWAV, frames: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(frames.size() * 2)
	for i in frames.size():
		var v: int = int(clamp(frames[i], -1.0, 1.0) * 32767.0)
		if v < 0:
			v += 65536
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	s.data = bytes
	return s


## 枪声：短促噪声爆发 + 低频扫频，快速指数衰减
func _gen_shot(seconds: float, amp: float, base_freq: float) -> AudioStreamWAV:
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	var t := 0.0
	for i in n:
		t = float(i) / SAMPLE_RATE
		var env := exp(-t * 18.0)
		var noise := randf_range(-1.0, 1.0)
		var tone := sin(TAU * base_freq * exp(-t * 9.0) * t)
		frames[i] = amp * env * (0.75 * noise + 0.25 * tone)
	return _write(_new_stream(seconds), frames)


## 命中：高频短促“嗒”
func _gen_hit() -> AudioStreamWAV:
	var seconds := 0.07
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 40.0)
		frames[i] = 0.4 * env * sin(TAU * (900.0 - 3000.0 * t) * t)
	return _write(_new_stream(seconds), frames)


## 受伤：低闷“咚”
func _gen_hurt() -> AudioStreamWAV:
	var seconds := 0.22
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 12.0)
		frames[i] = 0.55 * env * sin(TAU * (140.0 - 200.0 * t) * t)
	return _write(_new_stream(seconds), frames)


## 装填：两段机械咔哒
func _gen_reload() -> AudioStreamWAV:
	var seconds := 0.35
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var v := 0.0
		for click_t in [0.03, 0.2]:
			var dt: float = t - click_t
			if dt >= 0.0 and dt < 0.04:
				v += 0.35 * exp(-dt * 120.0) * randf_range(-1.0, 1.0)
		frames[i] = v
	return _write(_new_stream(seconds), frames)


## 击杀：下行音
func _gen_kill() -> AudioStreamWAV:
	var seconds := 0.25
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 10.0)
		var freq: float = lerp(660.0, 180.0, t / seconds)
		frames[i] = 0.4 * env * sin(TAU * freq * t)
	return _write(_new_stream(seconds), frames)


## 空仓：干巴巴的单击
func _gen_empty() -> AudioStreamWAV:
	var seconds := 0.05
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		frames[i] = 0.3 * exp(-t * 150.0) * randf_range(-1.0, 1.0)
	return _write(_new_stream(seconds), frames)


## 购买：上行双音
func _gen_buy() -> AudioStreamWAV:
	var seconds := 0.3
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var freq := 523.0 if t < 0.15 else 784.0
		frames[i] = 0.3 * exp(-fmod(t, 0.15) * 14.0) * sin(TAU * freq * t)
	return _write(_new_stream(seconds), frames)


## 波次提示：号角般的两连音
func _gen_wave() -> AudioStreamWAV:
	var seconds := 0.5
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var freq := 392.0 if t < 0.25 else 523.0
		frames[i] = 0.35 * exp(-fmod(t, 0.25) * 8.0) * sin(TAU * freq * t)
	return _write(_new_stream(seconds), frames)


## 射手预警：尖锐短鸣
func _gen_telegraph() -> AudioStreamWAV:
	var seconds := 0.18
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		frames[i] = 0.25 * sin(TAU * 1200.0 * t) * (0.5 + 0.5 * sin(TAU * 30.0 * t))
	return _write(_new_stream(seconds), frames)


## 敌人死亡：噪声泄气
func _gen_enemy_die() -> AudioStreamWAV:
	var seconds := 0.35
	var n := int(seconds * SAMPLE_RATE)
	var frames := PackedFloat32Array()
	frames.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 9.0)
		var freq: float = lerp(300.0, 60.0, t / seconds)
		frames[i] = 0.4 * env * (0.6 * randf_range(-1.0, 1.0) + 0.4 * sin(TAU * freq * t))
	return _write(_new_stream(seconds), frames)
