# AUDIO BAKER - makes all the placeholder sounds from scratch, in code.
#
# Run the scene tools/audio_baker.tscn ONCE and it writes every sound the game
# needs into res://audio/ as ready-to-play .res files, prints AUDIO BAKE DONE,
# and quits. (Same idea as the map builder.)
#
# Why .res and not .wav? A .wav needs the Godot editor to "import" it before
# the game can load it. A .res is already a Godot resource, so it just works.
# When we get real recorded sounds later, we re-run this or swap the loads.
#
# Every sound is built the same way: we fill an array with numbers between
# -1 and 1 (the speaker position for each moment in time), then save it.

extends Node

const RATE := 32000  # samples per second - plenty for spooky sounds

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 20260702  # fixed seed = same sounds every bake
	DirAccess.make_dir_recursive_absolute("res://audio")

	# --- movement sounds ---
	for i in 3:
		_save("step_player_%d" % (i + 1), _footstep_player())
		_save("step_entity_%d" % (i + 1), _footstep_entity())

	# --- body sounds ---
	_save("heartbeat", _heartbeat())
	_save("breath_1", _breath(620.0))
	_save("breath_2", _breath(880.0))

	# --- camcorder raise / lower ---
	_save("cam_up", _cam_whir(true))
	_save("cam_down", _cam_whir(false))

	# --- entity scream (loops while it's being filmed) ---
	_save("scream_loop", _scream(), true)

	# --- ambience loops ---
	_save("buzz_loop", _buzz(), true)
	_save("roomtone_loop", _roomtone(), true)

	# --- one-shot ambience ---
	_save("flicker_1", _flicker())
	_save("flicker_2", _flicker())
	_save("creak_1", _creak(420.0))
	_save("creak_2", _creak(540.0))
	_save("door_slam", _door_slam())
	_save("clank_1", _clank(1.0))
	_save("clank_2", _clank(1.31))
	_save("drip", _drip())

	# --- collecting a page ---
	_save("page_pickup", _page_pickup())

	print("AUDIO BAKE DONE")


# ---------------------------------------------------------------------------
# saving: floats (-1..1) -> 16-bit sound file the game can load directly
# ---------------------------------------------------------------------------
func _save(sound_name: String, samples: PackedFloat32Array, loop: bool = false) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		# turn the -1..1 float into a 16-bit whole number
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		# the sound repeats forever from start to end
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()

	var err := ResourceSaver.save(stream, "res://audio/%s.res" % sound_name)
	if err != OK:
		push_error("could not save %s (error %d)" % [sound_name, err])
	else:
		print("baked %s (%.2f s)" % [sound_name, float(samples.size()) / RATE])


# For looping sounds: blend the tail into the head so the loop has no click.
func _make_seamless(samples: PackedFloat32Array, fade_seconds: float) -> PackedFloat32Array:
	var fade := int(fade_seconds * RATE)
	var out_len := samples.size() - fade
	for i in fade:
		var w := float(i) / float(fade)  # 0 at the start of the blend, 1 at the end
		samples[i] = samples[i] * w + samples[out_len + i] * (1.0 - w)
	samples.resize(out_len)
	return samples


# ---------------------------------------------------------------------------
# little building blocks
# ---------------------------------------------------------------------------

# A low "thump" - a deep tone that drops in pitch and dies away fast.
# Used for footsteps, heartbeats and the door slam.
func _thump(dur: float, f_start: float, f_end: float, die_speed: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(f_start, f_end, t / dur)  # pitch slides down
		phase += f / RATE
		var env := minf(t * 300.0, 1.0) * exp(-t * die_speed)  # snap in, die out
		out[i] = sin(TAU * phase) * env * amp
	return out


# Mix sound b into sound a, starting at a time offset. a keeps its length.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, at_seconds: float = 0.0) -> PackedFloat32Array:
	var start := int(at_seconds * RATE)
	for i in b.size():
		var j := start + i
		if j >= a.size():
			break
		a[j] += b[i]
	return a


# ---------------------------------------------------------------------------
# the actual sounds
# ---------------------------------------------------------------------------

# Player footstep: soft thud + a short scuff of noise. ~0.22 s
func _footstep_player() -> PackedFloat32Array:
	var n := int(0.22 * RATE)
	var out := _thump(0.22, rng.randf_range(80.0, 95.0), 50.0, 28.0, 0.65)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		# scuff: noise that fades out very fast, dulled with a simple filter
		lp += 0.35 * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] += lp * exp(-t * 45.0) * 0.55
	return out


# Entity footstep: heavier, longer, with a second smaller impact (heel, toe).
func _footstep_entity() -> PackedFloat32Array:
	var out := _thump(0.5, rng.randf_range(60.0, 72.0), 36.0, 13.0, 0.95)
	out = _mix(out, _thump(0.3, 52.0, 34.0, 18.0, 0.4), 0.08)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += 0.2 * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] += lp * exp(-t * 20.0) * 0.35  # gritty debris under the foot
	return out


# One "lub-dub" heartbeat. The player script decides how often it repeats.
func _heartbeat() -> PackedFloat32Array:
	var out := _thump(0.55, 58.0, 40.0, 20.0, 0.95)      # lub
	out = _mix(out, _thump(0.35, 52.0, 38.0, 22.0, 0.6), 0.16)  # dub
	return out


# One breath: a soft swell of hissy noise. "center" sets how bright it sounds.
func _breath(center: float) -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp_hi := 0.0
	var lp_lo := 0.0
	var k_hi := minf(TAU * center * 1.6 / RATE, 0.9)
	var k_lo := minf(TAU * center * 0.4 / RATE, 0.9)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		# band-pass = keep the middle frequencies, drop deep rumble and sharp hiss
		lp_hi += k_hi * (w - lp_hi)
		lp_lo += k_lo * (w - lp_lo)
		var env := pow(sin(PI * t / 1.1), 1.6)  # swells up then away, like real breath
		out[i] = (lp_hi - lp_lo) * env * 0.8
	return out


# Camcorder motor: a tiny click, then a little servo whir. The whir rises
# in pitch when raising the camera, falls when lowering (plus a soft clunk
# as it settles against your side).
func _cam_whir(up: bool) -> PackedFloat32Array:
	var dur := 0.32
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		# the motor tone slides up or down depending on direction
		var f: float = lerpf(780.0, 1280.0, t / dur) if up else lerpf(1280.0, 700.0, t / dur)
		phase += f / RATE
		var s := sin(TAU * phase) + 0.4 * sin(TAU * phase * 2.0)
		s = tanh(s * 1.5) * 0.12                       # quiet - it's a small motor
		lp += 0.4 * (rng.randf_range(-1.0, 1.0) - lp)
		s += lp * 0.04                                  # faint mechanical hiss
		s *= sin(PI * t / dur)                          # ease in and out
		# the click of the button / latch right at the start
		s += lp * exp(-t * 250.0) * 0.8
		out[i] = s
	if not up:
		# lowering ends with a soft clunk against your body
		out = _mix(out, _thump(0.12, 170.0, 90.0, 40.0, 0.35), dur - 0.13)
	return out


# The scream: two detuned wailing tones with a shaky throat tremor and a hiss
# of breath, distorted so it sounds raw. Loops seamlessly.
func _scream() -> PackedFloat32Array:
	var dur := 1.8
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase1 := 0.0
	var phase2 := 0.0
	var wander := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		# the pitch howls up and down and also drifts randomly
		wander += 0.002 * (rng.randf_range(-150.0, 150.0) - wander)
		var f := 760.0 + 230.0 * sin(TAU * 2.7 * t) + wander
		phase1 += f / RATE
		phase2 += f * 1.017 / RATE  # second voice slightly off-pitch = unsettling
		var s := sin(TAU * phase1) + 0.8 * sin(TAU * phase2)
		s += 0.35 * sin(TAU * phase1 * 2.0) + 0.2 * sin(TAU * phase1 * 3.02)
		s *= 0.8 + 0.2 * sin(TAU * 31.0 * t)   # fast throat tremor
		lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
		s += lp * 0.5                           # raspy breath under the tone
		s = tanh(s * 2.2)                       # overdrive = raw, torn sound
		out[i] = s * (0.55 + 0.1 * sin(TAU * 5.0 * t))
	return _make_seamless(out, 0.15)


# Fluorescent-light buzz: a nasal electrical hum. Loops.
func _buzz() -> PackedFloat32Array:
	var dur := 2.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# 100 Hz mains hum plus its overtones, squashed to sound electric
		var s := sin(TAU * 100.0 * t) + 0.6 * sin(TAU * 200.0 * t)
		s += 0.45 * sin(TAU * 300.0 * t) + 0.3 * sin(TAU * 400.0 * t)
		s = tanh(s * 2.5) * 0.5
		s *= 0.9 + 0.1 * sin(TAU * 7.0 * t)  # slight unsteady flutter
		out[i] = s * 0.5
	return out  # built only from tones that fit the loop exactly, so no blend needed


# Room tone: a deep, airy building rumble. The quiet bed under everything. Loops.
func _roomtone() -> PackedFloat32Array:
	var dur := 6.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		# "brown" noise = a slow random drift, sounds like distant rumble
		brown = brown * 0.997 + rng.randf_range(-1.0, 1.0) * 0.035
		lp += 0.02 * (rng.randf_range(-1.0, 1.0) - lp)  # faint air hiss
		var swell := 0.8 + 0.2 * sin(TAU * t / dur)      # slow rise and fall
		out[i] = (brown * 0.9 + lp * 0.5) * swell * 0.55
	return _make_seamless(out, 0.3)


# A light flickering: sputtering bursts of buzz, like a dying tube.
func _flicker() -> PackedFloat32Array:
	var dur := 0.35
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var gate := 1.0
	var gate_timer := 0
	for i in n:
		var t := float(i) / RATE
		# randomly cut the sound on and off in tiny chunks = sputter
		gate_timer -= 1
		if gate_timer <= 0:
			gate_timer = rng.randi_range(200, 900)
			gate = 1.0 if rng.randf() > 0.4 else 0.0
		var s := sin(TAU * 100.0 * t) + 0.5 * sin(TAU * 300.0 * t)
		s = tanh(s * 3.0)
		out[i] = s * gate * exp(-t * 6.0) * 0.5
	return out


# Door creak: a squeaky tone that wobbles and sticks like dry hinges.
func _creak(base_freq: float) -> PackedFloat32Array:
	var dur := 1.1
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var wander := 0.0
	var grip := 0.0
	for i in n:
		var t := float(i) / RATE
		wander += 0.001 * (rng.randf_range(-120.0, 120.0) - wander)
		var f := base_freq * (1.0 + 0.22 * sin(TAU * 1.6 * t)) + wander
		phase += f / RATE
		var s := sin(TAU * phase) + 0.5 * sin(TAU * phase * 2.0) + 0.3 * sin(TAU * phase * 3.0)
		s = tanh(s * 1.8)
		# "grip" makes the squeak catch and release, like a sticky hinge
		grip += 0.004 * (rng.randf_range(0.0, 1.0) - grip)
		var env := sin(PI * t / dur)  # fade in and out over the swing
		out[i] = s * env * (0.25 + grip * 0.9) * 0.6
	return out


# Door slam: one big thump plus a crack and a short frame rattle.
func _door_slam() -> PackedFloat32Array:
	var out := _thump(0.45, 75.0, 35.0, 11.0, 1.0)
	var lp := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lp += 0.5 * (rng.randf_range(-1.0, 1.0) - lp)
		out[i] += lp * exp(-t * 60.0) * 0.8                 # the crack
		out[i] += sin(TAU * 241.0 * t) * exp(-t * 16.0) * 0.2  # frame ringing
		out[i] += sin(TAU * 173.0 * t) * exp(-t * 13.0) * 0.15
	return out


# Distant metal clank: a few clashing metallic tones ringing out.
func _clank(pitch: float) -> PackedFloat32Array:
	var dur := 1.4
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# metal rings at overtones that DON'T line up neatly - that's the clang
	var freqs := [520.0, 1247.0, 2213.0, 3178.0]
	var amps := [1.0, 0.6, 0.4, 0.25]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p in freqs.size():
			s += sin(TAU * freqs[p] * pitch * t) * amps[p] * exp(-t * (4.0 + p * 2.0))
		out[i] = tanh(s) * 0.45
	return out


# Picking up a page: a quick paper crinkle, then a deep dramatic boom
# underneath (the classic Slender "you took one" hit).
func _page_pickup() -> PackedFloat32Array:
	var dur := 1.2
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	# The crinkle: tiny random snaps of bright noise over the first 0.28 s.
	var lp := 0.0
	var gate := 0.0
	var gate_timer := 0
	for i in int(0.28 * RATE):
		var t := float(i) / RATE
		gate_timer -= 1
		if gate_timer <= 0:
			gate_timer = rng.randi_range(80, 500)
			gate = rng.randf_range(0.3, 1.0) if rng.randf() > 0.35 else 0.0
		lp += 0.75 * (rng.randf_range(-1.0, 1.0) - lp)  # bright = papery
		out[i] = lp * gate * 0.5 * (1.0 - t * 1.5)
	# The boom: one long deep hit that slowly rings away.
	# (amplitude lowered 0.9 -> 0.45 so the deep bass is much softer)
	out = _mix(out, _thump(1.15, 55.0, 30.0, 4.5, 0.45), 0.03)
	return out


# Water drip: a tiny falling blip with one faint echo.
func _drip() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(0.35 * RATE)
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 1400.0 * exp(-t * 9.0) + 320.0  # pitch falls quickly
		phase += f / RATE
		out[i] = sin(TAU * phase) * exp(-t * 25.0) * 0.5
	# the echo: same blip again, quieter, a moment later
	var echo := out.duplicate()
	for i in echo.size():
		echo[i] *= 0.35
	return _mix(out, echo, 0.13)
