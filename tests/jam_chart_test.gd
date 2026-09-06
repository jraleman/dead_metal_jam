extends SceneTree

## Headless tests for the two things that produce a track: the chart format —
## [JamBeat], [JamSection] and the [JamChart] compiler, plus the three shipped
## songs (§10) — and [DmjTrackBuilder], which generates the practice ramp when
## no chart is selected.
##
## They live together because they answer the same question from opposite ends.
## A chart is a song someone wrote down; a ramp is a song nobody wrote. Both
## must come out as the identical plain-data track the director consumes, and
## `_test_duration_matches_the_builder()` is the seam where that is checked.
##
## The compiler is where a song becomes rules, so it is tested the same way the
## rules are: by building charts by hand and reading the plain data that comes
## out. Nothing here renders and nothing here touches an autoload, which is
## what lets it run under `--script` (§9.8).
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/jam_chart_test.gd

## Every chart the options menu can select, in menu order.
##
## Read from [DmjOptions] rather than listed again here, so a fourth song
## cannot be added to the menu without these tests picking it up. The
## alternative — a copy of the list — is a test that passes because it is
## checking the songs it already knew about (§10).
const SHIPPED := DmjOptions.CHART_PATHS

## Tolerance for a float that has been through a `.tres` round trip.
const EPSILON := 0.002

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_test_beat_phrase()
	_test_section_orders_its_beats()
	_test_section_start_time()

	_test_archetypes_are_a_closed_set()
	_test_unknown_archetype_falls_back()
	_test_compiles_one_wave_per_section()
	_test_arrivals_survive_the_offset()
	_test_beat_duration_overrides_the_windup()
	_test_auto_lanes_spread()
	_test_named_lane_is_kept_and_clamped()
	_test_phrase_is_compiled_with_a_playable_windup()
	_test_empty_sections_are_skipped()
	_test_duration_matches_the_builder()

	_test_shipped_charts_are_the_menu()
	for track: int in SHIPPED:
		var path: String = SHIPPED[track]
		_test_shipped_chart_loads(path)
		_test_shipped_chart_is_playable(path)
		_test_shipped_chart_plays_the_whole_song(path)

	_test_track_builder_shape()
	_test_track_builder_avoids_repeats()
	_test_track_builder_is_seedable()
	_test_track_builder_handles_empty_pool()
	_test_track_builder_stages_a_plated_knuckle()
	_finish()


# --------------------------------------------------------------------------
# JamBeat / JamSection


func _test_beat_phrase() -> void:
	var bare := JamBeat.new()
	bare.note = 45
	_check(str(bare.phrase()) == "[45]", "A bare note is a one-note phrase.")

	var written := JamBeat.new()
	written.note = 40
	written.notes = [40, 45, 50]
	_check(
		str(written.phrase()) == "[40, 45, 50]",
		"A written phrase is used as written."
	)


## Charts are hand-written, so a beat typed out of order must stage late rather
## than scramble the wave it is in.
func _test_section_orders_its_beats() -> void:
	var section := JamSection.new()
	section.beats = [_beat(4.0, 50), _beat(1.0, 40), null, _beat(2.5, 45)]

	var ordered := section.ordered_beats()
	_check(ordered.size() == 3, "A null beat is dropped, not carried.")
	_check(
		ordered[0].time == 1.0 and ordered[1].time == 2.5 and ordered[2].time == 4.0,
		"Beats come back in playing order."
	)


func _test_section_start_time() -> void:
	var section := JamSection.new()
	section.beats = [_beat(9.0, 50), _beat(6.0, 40)]
	_check(section.start_time() == 6.0, "A section starts at its first arrival.")

	var empty := JamSection.new()
	_check(empty.start_time() == 0.0, "An empty section starts at zero, not a crash.")


# --------------------------------------------------------------------------
# JamChart — the compiler


## Archetypes are the whole of what a chart controls about pacing. If one is
## missing a field the compiler silently stages something else.
func _test_archetypes_are_a_closed_set() -> void:
	_check(
		JamChart.ARCHETYPES.has(JamChart.DEFAULT_ARCHETYPE),
		"The default archetype exists."
	)
	for key: String in JamChart.ARCHETYPES:
		var profile: Dictionary = JamChart.ARCHETYPES[key]
		_check(
			profile.has("approach") and profile.has("windup") and profile.has("advance"),
			"Archetype '%s' declares approach, wind-up and advance." % key
		)
		_check(
			float(profile["approach"]) >= DmjTrackBuilder.MIN_APPROACH_SECONDS,
			"Archetype '%s' is still readable." % key
		)
		_check(JamChart.has_archetype(key), "'%s' reports itself known." % key)


## A typo in one section name must not be a track that refuses to load on jam
## night.
func _test_unknown_archetype_falls_back() -> void:
	_check(
		not JamChart.has_archetype("breakdown"),
		"An unknown archetype is reported unknown."
	)
	_check(
		JamChart.archetype("breakdown") == JamChart.ARCHETYPES[JamChart.DEFAULT_ARCHETYPE],
		"But it still stages, using the default."
	)

	var chart := _chart([_section("ODD", "breakdown", [_beat(0.0, 40)])])
	var wave: Dictionary = chart.to_track()[0]
	var plan: Dictionary = wave["drones"][0]
	var fallback: Dictionary = JamChart.ARCHETYPES[JamChart.DEFAULT_ARCHETYPE]
	_check(
		absf(float(plan["approach"]) - float(fallback["approach"])) < EPSILON,
		"The compiled bot uses the default approach."
	)
	_check(
		absf(float(wave["advance"]) - float(fallback["advance"])) < EPSILON,
		"And the default rail advance."
	)


func _test_compiles_one_wave_per_section() -> void:
	var chart := _chart([
		_section("INTRO", "walk_in", [_beat(0.0, 40), _beat(2.0, 45)]),
		_section("CHORUS", "press", [_beat(8.0, 50)]),
	])
	var track := chart.to_track()

	_check(track.size() == 2, "One section is one wave, got %d" % track.size())
	_check(str(track[0]["section"]) == "INTRO", "Waves carry their section name.")
	_check(str(track[0]["archetype"]) == "walk_in", "And their archetype.")
	_check(
		absf(float(track[1]["advance"]) - JamChart.ARCHETYPES["press"]["advance"]) < EPSILON,
		"And the rail the archetype asks for."
	)
	_check(
		",".join(chart.section_names()) == "INTRO,CHORUS",
		"Section names come back in playing order."
	)
	for plan: Dictionary in track[0]["drones"]:
		_check(
			str(plan.get("enemy", "")) == "rusty_clanky",
			"A beat that names no enemy stages the default one."
		)


## A beat's `time` is an arrival. Clamping the first spawn to zero would drag
## that arrival late and shear the section's rhythm, so the whole section is
## offset instead and every interval inside it survives exactly.
func _test_arrivals_survive_the_offset() -> void:
	var chart := _chart([
		_section("VERSE", "march", [_beat(10.0, 40), _beat(11.5, 45), _beat(14.0, 50)]),
	])
	var drones: Array = chart.to_track()[0]["drones"]

	_check(absf(float(drones[0]["at"])) < EPSILON, "The first bot spawns at once.")
	_check(
		absf(float(drones[1]["at"]) - 1.5) < EPSILON,
		"The second keeps its 1.5 s interval, got %.3f" % float(drones[1]["at"])
	)
	_check(
		absf(float(drones[2]["at"]) - 4.0) < EPSILON,
		"And the third its 4.0 s, got %.3f" % float(drones[2]["at"])
	)

	var approach := float(JamChart.ARCHETYPES["march"]["approach"])
	for plan: Dictionary in drones:
		_check(
			absf(float(plan["approach"]) - approach) < EPSILON,
			"Every bot in a section walks in at the section's pace."
		)


## `duration` in the JSON is a window centred on the beat. The early half is
## already the approach, so what it actually buys the player is the late half —
## the wind-up (§10).
func _test_beat_duration_overrides_the_windup() -> void:
	var wide := _beat(0.0, 40)
	wide.duration = 5.0
	var chart := _chart([_section("HOLD", "press", [wide, _beat(2.0, 45)])])
	var drones: Array = chart.to_track()[0]["drones"]

	_check(
		absf(float(drones[0]["windup"]) - 2.5) < EPSILON,
		"Half the window is the wind-up, got %.3f" % float(drones[0]["windup"])
	)
	_check(
		absf(float(drones[1]["windup"]) - JamChart.ARCHETYPES["press"]["windup"]) < EPSILON,
		"A beat that asks for nothing uses the archetype's wind-up."
	)


## A chart that never names a lane still has to stage across all three, or the
## rail reads as one file of robots (§8.1).
func _test_auto_lanes_spread() -> void:
	var beats: Array[JamBeat] = []
	for index in range(6):
		beats.append(_beat(float(index), 40 + index))
	var chart := _chart([_section("RUN", "march", beats)])

	var seen := {}
	for plan: Dictionary in chart.to_track()[0]["drones"]:
		var lane := int(plan["lane"])
		_check(
			lane >= 0 and lane < EncounterDirector.LANE_COUNT,
			"Auto lane %d is on the field." % lane
		)
		seen[lane] = true
	_check(
		seen.size() == EncounterDirector.LANE_COUNT,
		"Six auto beats use all three lanes, got %d" % seen.size()
	)


func _test_named_lane_is_kept_and_clamped() -> void:
	var left := _beat(0.0, 40)
	left.lane = 0
	var right := _beat(1.0, 45)
	right.lane = 2
	var absurd := _beat(2.0, 50)
	absurd.lane = 9
	var chart := _chart([_section("SIDES", "march", [left, right, absurd])])
	var drones: Array = chart.to_track()[0]["drones"]

	_check(int(drones[0]["lane"]) == 0, "A named lane is honoured.")
	_check(int(drones[1]["lane"]) == 2, "Including the far one.")
	_check(
		int(drones[2]["lane"]) == EncounterDirector.LANE_COUNT - 1,
		"A lane off the field is clamped onto it rather than dropped."
	)

	var narrow: Array = chart.to_track(2)[0]["drones"]
	_check(
		int(narrow[1]["lane"]) <= 1,
		"A narrower field clamps the chart instead of spawning off it."
	)


## The round timer is read from the plan (§2), so a wind-up the phrase needs
## has to be written into the plan and not widened later by the bot.
func _test_phrase_is_compiled_with_a_playable_windup() -> void:
	var beat := _beat(0.0, 40)
	beat.notes = [40, 45, 50]
	beat.enemy = "plated_knuckle"
	var chart := _chart([_section("BRIDGE", "press", [beat])])
	var plan: Dictionary = chart.to_track()[0]["drones"][0]

	_check(str(plan["enemy"]) == "plated_knuckle", "The enemy key reaches the plan.")
	_check(
		(plan["notes"] as Array) == [40, 45, 50],
		"So does the phrase, in order."
	)
	_check(int(plan["note"]) == 40, "The called note is the phrase's first note.")
	_check(
		float(plan["windup"]) >= PlatedKnuckle.windup_for(3),
		"The wind-up is long enough to play three plates in, got %.3f"
		% float(plan["windup"])
	)

	var bare := _beat(0.0, 55)
	bare.enemy = "plated_knuckle"
	var one: Dictionary = _chart([_section("X", "march", [bare])]).to_track()[0]["drones"][0]
	_check(
		(one["notes"] as Array) == [55],
		"A phrase-less phrase enemy falls back to its single note."
	)


## A section with no beats would compile to a wave that is over on the frame it
## starts, which reads on screen as a skipped section.
func _test_empty_sections_are_skipped() -> void:
	var chart := _chart([
		_section("SILENCE", "march", []),
		_section("REAL", "march", [_beat(0.0, 40)]),
	])
	_check(chart.to_track().size() == 1, "An empty section compiles to nothing.")
	_check(
		",".join(chart.section_names()) == "REAL",
		"And is not named on the HUD either."
	)
	_check(
		JamChart.new().to_track().is_empty(),
		"A chart with no sections compiles to an empty track, not a crash."
	)


## A song and a practice ramp have to be priced by the same rule, or the round
## timer means something different depending on what the player picked.
func _test_duration_matches_the_builder() -> void:
	var chart := _chart([
		_section("A", "walk_in", [_beat(0.0, 40), _beat(2.0, 45)]),
		_section("B", "press", [_beat(8.0, 50)]),
	])
	_check(
		absf(chart.duration() - DmjTrackBuilder.duration(chart.to_track())) < EPSILON,
		"The chart is priced with the builder's own rule."
	)
	_check(chart.duration() > 0.0, "And a real chart has a real length.")


# --------------------------------------------------------------------------
# The shipped tracks


## The menu and the chart map have to describe the same set of songs.
##
## They are two different lists — one for the player, one for the loader — and
## a song added to only one of them fails in a way nobody would see in a test
## that just loaded charts: either a menu entry that cannot start a round, or a
## chart that ships with no way to reach it.
func _test_shipped_charts_are_the_menu() -> void:
	var offered: Array[int] = []
	for choice: Dictionary in DmjOptions.TRACK_CHOICES:
		offered.append(int(choice["value"]))

	_check(
		offered.has(DmjOptions.TRACK_PRACTICE),
		"The practice ramp is still offered."
	)
	_check(
		not SHIPPED.has(DmjOptions.TRACK_PRACTICE),
		"And is generated, so it has no chart file."
	)
	_check(
		SHIPPED.size() >= 3,
		"Milestone 8 ships three songs, got %d." % SHIPPED.size()
	)

	for track: int in SHIPPED:
		_check(
			offered.has(track),
			"Chart %d can be reached from the menu." % track
		)
		_check(
			DmjOptions.is_song(track),
			"Chart %d counts as a song, not the ramp." % track
		)
		_check(
			DmjOptions.chart_path(track) == SHIPPED[track],
			"And `chart_path(%d)` returns it." % track
		)

	for track in offered:
		_check(
			SHIPPED.has(track) or track == DmjOptions.TRACK_PRACTICE,
			"Menu entry %d is a song with a chart or the ramp." % track
		)

	_check(
		DmjOptions.chart_path(DmjOptions.TRACK_PRACTICE).is_empty(),
		"Asking the ramp for a chart path gets nothing, not a broken path."
	)
	_check(
		not DmjOptions.is_song(DmjOptions.TRACK_PRACTICE),
		"And the ramp is not a song."
	)

	var titles: Array[String] = []
	for choice: Dictionary in DmjOptions.TRACK_CHOICES:
		var title := str(choice["title"])
		_check(not titles.has(title), "Track '%s' is named once." % title)
		titles.append(title)


func _test_shipped_chart_loads(path: String) -> void:
	_check(ResourceLoader.exists(path), "%s is where the game looks." % path)
	var chart := load(path) as JamChart
	if chart == null:
		_check(false, "%s loads as a JamChart." % path)
		return

	var song := chart.title if not chart.title.is_empty() else path.get_file()
	_check(chart.audio != null, "%s carries the track's audio." % song)
	_check(chart.bpm > 0.0, "%s has a tempo." % song)
	_check(not chart.title.is_empty(), "%s is titled for the banner." % path.get_file())
	_check(
		chart.sections.size() >= 3,
		"%s has more than a couple of sections." % song
	)

	for section in chart.sections:
		_check(section != null, "No section of %s is missing." % song)
		_check(
			not section.name.is_empty(),
			"Every section of %s is named for the banner." % song
		)
		_check(
			JamChart.has_archetype(section.wave_archetype),
			"%s section '%s' names a real archetype." % [song, section.name]
		)

	var previous := -1.0
	for section in chart.sections:
		var start := section.start_time()
		_check(
			start > previous,
			"%s section '%s' starts after the one before it." % [song, section.name]
		)
		previous = start


func _test_shipped_chart_is_playable(path: String) -> void:
	var chart := load(path) as JamChart
	if chart == null:
		return
	var song := chart.title if not chart.title.is_empty() else path.get_file()

	var track := chart.to_track()
	_check(not track.is_empty(), "%s compiles to a real track." % song)

	var bots := 0
	var plated := 0
	for wave: Dictionary in track:
		var drones: Array = wave["drones"]
		_check(not drones.is_empty(), "Every compiled wave of %s has bots in it." % song)
		bots += drones.size()

		var last_at := -1.0
		for plan: Dictionary in drones:
			_check(float(plan["at"]) >= last_at, "%s spawns are ordered." % song)
			last_at = float(plan["at"])
			_check(
				float(plan["approach"]) >= DmjTrackBuilder.MIN_APPROACH_SECONDS,
				"No bot in %s is unreadable." % song
			)
			_check(int(plan["note"]) >= 0, "Every bot in %s asks for a real note." % song)
			if str(plan.get("enemy", "")) != "plated_knuckle":
				continue
			plated += 1
			var phrase: Array = plan["notes"]
			_check(
				phrase.size() >= PlatedKnuckle.MIN_PLATES
				and phrase.size() <= PlatedKnuckle.MAX_PLATES,
				"A phrase in %s is between two and three notes." % song
			)
			_check(
				float(plan["windup"]) >= PlatedKnuckle.windup_for(phrase.size()),
				"And can physically be finished before the bot fires."
			)

	_check(bots >= 12, "%s is long enough to be a round, got %d bots." % [song, bots])
	_check(plated >= 1, "%s introduces the second enemy, got %d." % [song, plated])
	_check(
		chart.duration() < 180.0,
		"%s still fits the round timer's ceiling, got %.1f s."
		% [song, chart.duration()]
	)


## The song plays through once and outlasts the chart written over it.
##
## Neither half is visible in the chart file, and the first build got both
## wrong: it shipped a sixty-second trim with `loop` set, which kept every
## test green — the encounter is driven by the chart's clock, not the
## stream's — while the player heard one minute of music repeat under a round
## twice that long. A jam that loops back on itself mid-phrase is the one
## thing this game cannot sound like.
##
## Looping is a property of the *import*, not of anything in code, so this is
## the only place it can be caught.
func _test_shipped_chart_plays_the_whole_song(path: String) -> void:
	var chart := load(path) as JamChart
	if chart == null:
		return
	var song := chart.title if not chart.title.is_empty() else path.get_file()
	var audio := chart.audio
	if audio == null:
		_check(false, "%s carries audio to check." % song)
		return

	_check(
		"loop" in audio,
		"%s's stream exposes a loop flag to be checked at all." % song
	)
	_check(
		not bool(audio.get("loop")),
		"%s does not loop; it is played once and the round ends with it." % song
	)

	var length := audio.get_length()
	var charted := chart.duration()
	_check(
		length >= charted,
		"%s outlasts its own chart: %.1f s of audio for %.1f s of bots."
		% [song, length, charted]
	)
	# A margin, not just "longer": a stream that ends the instant the last bot
	# does would fade the round out on silence.
	_check(
		length >= charted + 30.0,
		"%s has room left over at the end, got %.1f s spare."
		% [song, length - charted]
	)


# --------------------------------------------------------------------------
# DmjTrackBuilder


func _test_track_builder_shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pool: Array = [40, 45, 50, 55, 59, 64]
	var track := DmjTrackBuilder.build(pool, 4, rng)

	_check(track.size() == 4, "Four waves were asked for, got %d" % track.size())

	var previous_count := 0
	for wave_index in range(track.size()):
		var drones: Array = track[wave_index]["drones"]
		_check(not drones.is_empty(), "Wave %d has drones." % wave_index)
		_check(
			drones.size() >= previous_count,
			"Waves never get easier as the track goes on."
		)
		previous_count = drones.size()

		var last_at := -1.0
		for plan: Dictionary in drones:
			var lane := int(plan["lane"])
			_check(
				lane >= 0 and lane < EncounterDirector.LANE_COUNT,
				"Lane %d is on the field." % lane
			)
			_check(pool.has(int(plan["note"])), "Notes come from the game's pool.")
			var at := float(plan["at"])
			_check(at >= last_at, "Spawns are ordered, so arrivals are too.")
			last_at = at
			_check(
				float(plan["approach"]) >= DmjTrackBuilder.MIN_APPROACH_SECONDS,
				"No wave asks for an unreadable approach."
			)


## A repeat inside a wave would leave the readout unchanged after a kill, so
## the player cannot tell whether their note registered.
func _test_track_builder_avoids_repeats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var track := DmjTrackBuilder.build([40, 45], 6, rng)

	for wave: Dictionary in track:
		var drones: Array = wave["drones"]
		for index in range(1, drones.size()):
			_check(
				int(drones[index]["note"]) != int(drones[index - 1]["note"]),
				"A wave never calls the same note twice in a row."
			)


func _test_track_builder_is_seedable() -> void:
	var first := RandomNumberGenerator.new()
	first.seed = 1234
	var second := RandomNumberGenerator.new()
	second.seed = 1234

	var left := DmjTrackBuilder.build([40, 45, 50], 3, first)
	var right := DmjTrackBuilder.build([40, 45, 50], 3, second)
	_check(str(left) == str(right), "The same seed builds the same track.")


func _test_track_builder_handles_empty_pool() -> void:
	var rng := RandomNumberGenerator.new()
	_check(
		DmjTrackBuilder.build([], 3, rng).is_empty(),
		"No notes means no track, rather than a crash."
	)
	_check(
		DmjTrackBuilder.build([40], 0, rng).is_empty(),
		"Zero waves means no track."
	)


## The practice ramp has to introduce the second enemy or a player who never
## opens the song never meets it — and it must write the phrase's wind-up into
## the plan, because the round timer is derived from the plan (§2).
func _test_track_builder_stages_a_plated_knuckle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var track := DmjTrackBuilder.build([40, 45, 50, 55], 4, rng)

	var first: Array = track[0]["drones"]
	for plan: Dictionary in first:
		_check(
			str(plan.get("enemy", "")) != "plated_knuckle",
			"The first wave is one note per robot."
		)

	var plated := 0
	for index in range(track.size()):
		var drones: Array = track[index]["drones"]
		var last: Dictionary = drones[drones.size() - 1]
		var is_plated := str(last.get("enemy", "")) == "plated_knuckle"
		_check(
			is_plated == (index >= DmjTrackBuilder.PHRASE_FROM_WAVE),
			"Wave %d stages a phrase only once the core verb is taught." % index
		)
		if not is_plated:
			continue
		plated += 1
		var phrase: Array = last["notes"]
		_check(phrase.size() >= 2, "A phrase is at least two notes.")
		_check(
			int(last["note"]) == int(phrase[0]),
			"The called note is the first note of the phrase."
		)
		_check(
			float(last["windup"]) >= PlatedKnuckle.windup_for(phrase.size()),
			"The plan carries a wind-up the phrase can actually be played in."
		)
	_check(plated > 0, "A four-wave ramp introduces the second enemy at least once.")

	_check(
		DmjTrackBuilder.duration(track) > 0.0,
		"The builder can still price a track that contains a phrase."
	)



# --------------------------------------------------------------------------
# Harness


func _beat(time: float, note: int) -> JamBeat:
	var beat := JamBeat.new()
	beat.time = time
	beat.note = note
	return beat


func _section(name: String, archetype: String, beats: Array) -> JamSection:
	var section := JamSection.new()
	section.name = name
	section.wave_archetype = archetype
	var typed: Array[JamBeat] = []
	for beat: JamBeat in beats:
		typed.append(beat)
	section.beats = typed
	return section


func _chart(sections: Array) -> JamChart:
	var chart := JamChart.new()
	var typed: Array[JamSection] = []
	for section: JamSection in sections:
		typed.append(section)
	chart.sections = typed
	return chart


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Chart tests passed. (%d checks)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("Chart tests FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)
