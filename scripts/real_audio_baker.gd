# REAL AUDIO BAKER - turns the downloaded recordings in res://audio/real audio/
# into the small, ready-to-play .res files the game actually loads.
#
# Run tools/real_audio_baker.tscn ONCE (like the map builder). It overwrites
# the old synthesized placeholders where a real recording exists, prints
# REAL AUDIO BAKE DONE, and quits.
#
# NOTE: if you ever re-run the OLD audio_baker.tscn (the synth one), run this
# one again afterwards, because the synth baker writes the same file names.
#
# What each recording becomes:
#  - footsteps-in-factory-hall  -> step_player_1..3 (cut out single steps)
#                                  step_entity_1..3 (same steps, slowed down = heavier)
#  - heavy-breathing            -> breath_1, breath_2 (single breaths, calm)
#  - heavy-breathing-sprint     -> breath_sprint_1, breath_sprint_2 (panic breaths)
#  - door_wood_creak            -> creak_1, creak_2 (second one slowed a little)
#  - monster-roar               -> roar.res (plays when filming scares it away)
#  - monster-scream-death       -> jumpscare.res (for the catch/game-over, coming next)

extends Node

const SRC := "res://audio/real audio/"

const F_STEPS := SRC + "155858__rutgermuller__footsteps-in-factory-hall-on-wood-and-concrete.wav"
const F_BREATH := SRC + "491997__gm180259__heavy-breathing.wav"
const F_BREATH_SPRINT := SRC + "163383__under7dude__heavy-breathing-sprint.wav"
const F_CREAK := SRC + "475484__o_ciz__door_wood_creak_2.wav"
const F_SCREAM := SRC + "398802__dangadv64__monster-scream-death.wav"
const F_ROAR := SRC + "347410__zerokingfull__monster-roar-02.ogg"
const F_INDUSTRIAL := SRC + "835070__looplicator__105-bpm-industrial-ambient-loop-15652-wav.wav"


func _ready() -> void:
	print("REAL AUDIO BAKE starting...")
	_bake_footsteps()
	_bake_breathing()
	_bake_creaks()
	_bake_monster()
	_bake_industrial()
	print("REAL AUDIO BAKE DONE")
	# keep the window alive a moment so errors can be read, then quit
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()


# ---------------------------------------------------------------------------
# the four bake jobs
# ---------------------------------------------------------------------------

func _bake_footsteps() -> void:
	var rec := _load_wav(F_STEPS)
	if rec.is_empty():
		return
	# find single footsteps in the long recording (loud, sharp hits)
	var hits := _find_hits(rec, 3, 0.01, 0.4, 0.02, 0.45, 0.3)
	for i in hits.size():
		# player steps: the slice as-is
		var s: PackedFloat32Array = (hits[i] as PackedFloat32Array).duplicate()
		_save("step_player_%d" % (i + 1), _normalize(s, 0.8), rec.rate)
		# entity steps: same step but slowed down 1.4x = deeper and heavier
		var e := _stretch(hits[i], 1.4)
		_save("step_entity_%d" % (i + 1), _normalize(e, 0.95), rec.rate)


func _bake_breathing() -> void:
	# calm breathing -> breath_1 / breath_2
	var calm := _load_wav(F_BREATH)
	if not calm.is_empty():
		var swells := _find_hits(calm, 2, 0.05, 1.6, 0.2, 0.3, 1.2)
		for i in swells.size():
			_save("breath_%d" % (i + 1), _normalize(swells[i], 0.7), calm.rate)
	# sprint/panic breathing -> breath_sprint_1 / breath_sprint_2
	var panic := _load_wav(F_BREATH_SPRINT)
	if not panic.is_empty():
		var swells := _find_hits(panic, 2, 0.05, 1.2, 0.15, 0.3, 0.8)
		for i in swells.size():
			_save("breath_sprint_%d" % (i + 1), _normalize(swells[i], 0.7), panic.rate)


func _bake_creaks() -> void:
	var rec := _load_wav(F_CREAK)
	if rec.is_empty():
		return
	var s := _trim(rec.samples, rec.rate)
	_save("creak_1", _normalize(s.duplicate(), 0.6), rec.rate)
	# second variation: same creak slowed 15% so no two doors sound identical
	_save("creak_2", _normalize(_stretch(s, 1.15), 0.6), rec.rate)


func _bake_monster() -> void:
	# the death scream: saved whole, for the jumpscare (feature comes next)
	var scream := _load_wav(F_SCREAM)
	if not scream.is_empty():
		var s := _trim(scream.samples, scream.rate)
		_save("jumpscare", _normalize(s, 0.95), scream.rate)
	# the roar: it's an .ogg, which Godot can save as a resource directly
	var roar := AudioStreamOggVorbis.load_from_file(F_ROAR)
	if roar == null:
		push_error("could not load " + F_ROAR)
	else:
		var err := ResourceSaver.save(roar, "res://audio/roar.res")
		if err != OK:
			push_error("could not save roar (error %d)" % err)
		else:
			print("baked roar (%.2f s)" % roar.get_length())


func _bake_industrial() -> void:
	# the background machine hum - saved whole, set to loop forever
	var rec := _load_wav(F_INDUSTRIAL)
	if rec.is_empty():
		return
	_save("industrial_loop", _normalize(rec.samples, 0.7), rec.rate, true)


# ---------------------------------------------------------------------------
# loading: wav file -> mono floats (-1..1) + its sample rate
# ---------------------------------------------------------------------------
func _load_wav(path: String) -> Dictionary:
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		push_error("could not load " + path)
		return {}
	var bytes := stream.data
	var out := PackedFloat32Array()
	match stream.format:
		AudioStreamWAV.FORMAT_16_BITS:
			if stream.stereo:
				out.resize(bytes.size() / 4)
				for i in out.size():
					# average left+right into one mono sample
					out[i] = (bytes.decode_s16(i * 4) + bytes.decode_s16(i * 4 + 2)) / 65536.0
			else:
				out.resize(bytes.size() / 2)
				for i in out.size():
					out[i] = bytes.decode_s16(i * 2) / 32768.0
		AudioStreamWAV.FORMAT_8_BITS:
			var step := 2 if stream.stereo else 1
			out.resize(bytes.size() / step)
			for i in out.size():
				out[i] = bytes.decode_s8(i * step) / 128.0
		_:
			push_error(path + ": unexpected format %d - can't slice it" % stream.format)
			return {}
	print("loaded %s (%.1f s, %d Hz)" % [path.get_file(), float(out.size()) / stream.mix_rate, stream.mix_rate])
	return {"samples": out, "rate": stream.mix_rate}


# ---------------------------------------------------------------------------
# slicing: find the loud moments in a recording and cut them out
# ---------------------------------------------------------------------------
# rec        = what _load_wav returned
# count      = how many slices we want
# pre        = seconds to keep BEFORE the loud moment starts
# length     = how long each slice is (seconds)
# block_s    = we scan the recording in chunks this long (small = sharp hits,
#              bigger = slow swells like breathing)
# thresh     = how loud (0..1 of the recording's loudest point) counts as a hit
# min_gap    = two hits closer together than this count as one
func _find_hits(rec: Dictionary, count: int, block_s: float, length: float,
		pre: float, thresh: float, min_gap: float) -> Array:
	var samples: PackedFloat32Array = rec.samples
	var rate: int = rec.rate

	# 1) loudness of each little chunk of the recording
	var block := maxi(int(rate * block_s), 1)
	var peaks := PackedFloat32Array()
	peaks.resize(samples.size() / block)
	var loudest := 0.0001
	for b in peaks.size():
		var p := 0.0
		for i in block:
			p = maxf(p, absf(samples[b * block + i]))
		peaks[b] = p
		loudest = maxf(loudest, p)

	# 2) a "hit" is a chunk that crosses the loudness line from below
	var line := loudest * thresh
	var hits: Array = []  # each entry = [how loud, where in seconds]
	for b in range(1, peaks.size()):
		if peaks[b] >= line and peaks[b - 1] < line:
			hits.append([peaks[b], float(b) * block_s])

	# 3) keep the strongest hits, skipping any too close to one we already took
	hits.sort_custom(func(a, b): return a[0] > b[0])
	var picked: Array = []
	for h in hits:
		var ok := true
		for p in picked:
			if absf(h[1] - p) < min_gap:
				ok = false
				break
		if ok:
			picked.append(h[1])
			if picked.size() >= count:
				break

	if picked.size() < count:
		push_warning("only found %d/%d hits in a recording - reusing the last one" %
				[picked.size(), count])
		while picked.size() < count and picked.size() > 0:
			picked.append(picked[picked.size() - 1])
	if picked.is_empty():
		push_error("found no hits at all in the recording")
		return []

	# 4) cut each slice out, with soft edges so there's no click
	var out: Array = []
	for t in picked:
		var start := maxi(int((t - pre) * rate), 0)
		var stop := mini(start + int(length * rate), samples.size())
		var s := samples.slice(start, stop)
		_fade(s, rate, 0.005, length * 0.3)
		out.append(s)
	return out


# ---------------------------------------------------------------------------
# little helpers
# ---------------------------------------------------------------------------

# make the loudest point of the sound hit exactly "target" (0..1)
func _normalize(samples: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := target / peak
	for i in samples.size():
		samples[i] *= gain
	return samples


# play the sound slower: factor 1.4 = 40% longer AND deeper (like slowing a tape)
func _stretch(samples: PackedFloat32Array, factor: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(samples.size() * factor))
	for i in out.size():
		var pos := float(i) / factor
		var j := int(pos)
		var next := mini(j + 1, samples.size() - 1)
		out[i] = lerpf(samples[j], samples[next], pos - j)
	return out


# cut the silence off the start and end (keeping a tiny pad)
func _trim(samples: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	# "silence" is measured against the recording's own loudest point,
	# so quiet recordings don't get eaten by the trim
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var floor_level := peak * 0.03
	var first := 0
	var last := samples.size() - 1
	while first < last and absf(samples[first]) < floor_level:
		first += 1
	while last > first and absf(samples[last]) < floor_level:
		last -= 1
	first = maxi(first - int(0.05 * rate), 0)
	last = mini(last + int(0.1 * rate), samples.size() - 1)
	return samples.slice(first, last + 1)


# soften the very start and end of a slice so it doesn't click
func _fade(samples: PackedFloat32Array, rate: int, in_s: float, out_s: float) -> void:
	var fi := mini(int(in_s * rate), samples.size())
	for i in fi:
		samples[i] *= float(i) / fi
	var fo := mini(int(out_s * rate), samples.size())
	for i in fo:
		samples[samples.size() - 1 - i] *= float(i) / fo


# floats -> 16-bit .res file the game can load with no import step
# (same as the synth baker's _save, but the sample rate comes from the recording)
func _save(sound_name: String, samples: PackedFloat32Array, rate: int, loop: bool = false) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
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
		print("baked %s (%.2f s)" % [sound_name, float(samples.size()) / rate])
