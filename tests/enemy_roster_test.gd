extends SceneTree

const FIELD := Rect2(0, 0, 1000, 500)
var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_echo_shield()
	_test_boss_checkpoints()
	_test_compiled_deadlines()
	for mode in [EncounterDirector.Mode.JAM, EncounterDirector.Mode.RHYTHM, EncounterDirector.Mode.DEMO]:
		_test_modes(mode)
	_test_practice_roster()
	_test_new_room_has_fresh_bays()
	if _failures.is_empty():
		print("Enemy roster tests passed (%d checks)." % _checks)
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _test_echo_shield() -> void:
	var sentry := SilencerSentry.new()
	sentry.configure_echo(0, 60, 1.0, 0.05)
	_check(sentry.demand_size() == 2, "A Sentry always starts with shield and core.")
	_check(sentry.accepts_pitch_class(0), "Its first demand is the authored pitch class.")
	_check(sentry.strike() and sentry.is_targetable(), "Breaking the shield is a hit, not a kill.")
	_check(sentry.required_note == 60 and sentry.demand_size() == 1, "The core repeats the same note.")
	sentry.on_wrong_note()
	_check(sentry.cursor() == 1, "A wrong note never regenerates a shattered shield.")
	_check(sentry.strike() and not sentry.is_targetable(), "The second matching attack destroys the core.")
	_check(not sentry.strike(), "The destroyed Sentry cannot score another note.")
	sentry.configure_echo(2, 67, 1.0, 0.05)
	_check(sentry.cursor() == 0 and sentry.required_note == 67, "Reconfiguration restores shield and note.")
	_check(is_equal_approx(sentry.windup_seconds, SilencerSentry.windup_for()), "The shield's second beat fits its deadline.")
	sentry.free()


func _test_boss_checkpoints() -> void:
	var boss := DmjConductor.new()
	boss.configure_motif(1, [60, 62, 64, 65, 69], 1.0, 0.05)
	_check(boss.notes == [60, 62, 64, 65], "Long motifs use four notes, not an unbounded boss.")
	boss.strike()
	boss.on_wrong_note()
	_check(boss.cursor() == 0 and boss.required_note == 60, "A broken first pair restarts at the first note.")
	_check(is_equal_approx(boss.time_to_beat(), -DmjConductor.NOTE_SECONDS), "A reset also moves the next beat into the future.")
	boss.strike()
	boss.strike()
	boss.on_wrong_note()
	_check(boss.cursor() == 2 and boss.required_note == 64, "A completed pair is a persistent checkpoint.")
	boss.strike()
	boss.on_wrong_note()
	_check(boss.cursor() == 2 and boss.demand_size() == 2, "A mistake in the last pair never restores the first pair.")
	boss.strike()
	boss.strike()
	_check(boss.state == JamBot.State.DEAD, "Finishing the motif defeats the boss.")
	boss.configure_motif(0, [60, 62], 1.0, 0.05)
	_check(boss.notes == [60, 62, 60, 62] and boss.cursor() == 0, "Short motifs repeat to four fresh steps.")
	boss.free()


func _test_compiled_deadlines() -> void:
	var chart := JamChart.new()
	var section := JamSection.new()
	for key in ["silencer_sentry", "conductor"]:
		var beat := JamBeat.new()
		beat.enemy = key
		beat.note = 60
		beat.notes = [60, 62]
		beat.duration = 0.1
		beat.time = section.beats.size() * 4.0
		section.beats.append(beat)
	chart.sections = [section]
	var track := chart.to_track()
	var director := EncounterDirector.new()
	for plan: Dictionary in track[0]["drones"]:
		var bot: JamBot = director.call("_build_bot", plan, 1, plan["approach"], plan["windup"])
		_check(is_equal_approx(bot.windup_seconds, float(plan["windup"])), "Runtime and compiled attack deadlines agree.")
		_check(bot.demand_size() == (2 if bot is SilencerSentry else 4), "The compiler stages the complete enemy demand.")
		bot.free()
	_check(is_equal_approx(chart.duration(), DmjTrackBuilder.duration(track)), "The round timer prices the new enemies' complete phrases.")
	director.free()


func _test_modes(mode: EncounterDirector.Mode) -> void:
	var director := EncounterDirector.new()
	root.add_child(director)
	director.apply_mode(mode)
	director.set_track([{"advance": 0.0, "drones": [
		{"enemy": "silencer_sentry", "lane": 0, "note": 60, "approach": 0.6, "windup": 2.0},
		{"enemy": "conductor", "lane": 2, "notes": [62, 64, 65, 67], "approach": 0.6, "windup": 4.0},
	]}])
	var fired := [0]
	director.drone_fired.connect(func(_bot: JamBot) -> void: fired[0] += 1)
	director.begin()
	director.advance(0.01, FIELD)
	if mode != EncounterDirector.Mode.RHYTHM:
		var wrong := director.resolve_note(11, 0)
		_check(int(wrong["kind"]) == EncounterDirector.Judgement.WRONG_NOTE, "New enemies never accept the wrong pitch in Jam or Demo.")
	var hits := 0
	for frame in range(600):
		director.advance(0.02, FIELD)
		var live := director.live_drones()
		if live.is_empty():
			if director.is_finished():
				break
			continue
		var target := live[0]
		if mode != EncounterDirector.Mode.JAM and target.time_to_beat() < 0.0:
			continue
		if director.is_time_stopped():
			var before := director.world_time()
			director.advance(0.4, FIELD)
			_check(is_equal_approx(before, director.world_time()), "Demo holds every new enemy's phrase beat.")
		var pitch := 11 if mode == EncounterDirector.Mode.RHYTHM else target.pitch_class()
		var result := director.resolve_note(pitch, hits)
		var hit := int(result["kind"]) == EncounterDirector.Judgement.HIT
		_check(
			hit, "%s's beat stays answerable in %s at %.3f seconds." % [
				target.roster_key(), EncounterDirector.mode_name(mode), target.time_to_beat(),
			]
		)
		if not hit:
			break
		hits += 1
	_check(hits == 6 and director.is_finished(), "Two shield notes and four boss notes clear the encounter.")
	_check(fired[0] == 0, "Correctly played new enemies do not fire through their beat windows.")
	director.free()


func _test_practice_roster() -> void:
	for pool: Array in [[60], [60, 62], [40, 45, 50, 55, 59, 64]]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 123
		var track := DmjTrackBuilder.build(pool, 4, rng)
		var roster: Array[String] = []
		for wave in range(track.size()):
			for plan: Dictionary in track[wave]["drones"]:
				var enemy := str(plan["enemy"])
				roster.append(enemy)
				_check(pool.has(int(plan["note"])), "New enemy demands stay in the selected instrument's note pool.")
				if wave == 0:
					_check(enemy == "rusty_clanky", "The opening wave still teaches one note, one kill.")
				if enemy == "conductor":
					_check((plan["notes"] as Array).size() == 4, "Even a one-note pool supplies a four-hit boss.")
					_check(float(plan["windup"]) >= DmjConductor.windup_for(), "Practice bosses have playable planned deadlines.")
		for key in ["rusty_clanky", "plated_knuckle", "silencer_sentry", "conductor"]:
			_check(roster.has(key), "The default four-wave ramp introduces %s." % key)


func _test_new_room_has_fresh_bays() -> void:
	var director := EncounterDirector.new()
	root.add_child(director)
	var wave := {"advance": 0.0, "drones": [
		{"enemy": "rusty_clanky", "lane": 1, "note": 60, "approach": 4.0, "windup": 2.0},
	]}
	director.set_track([wave, wave])
	director.begin()
	director.advance(0.01, FIELD)
	director.live_drones()[0].kill()
	director.advance(0.01, FIELD)
	director.advance(0.01, FIELD)
	var next := director.live_drones()[0]
	_check(next.arena_index == 1 and next.firing_slot == 0, "Wreckage in the previous room cannot reserve a new firing bay.")
	director.free()


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)
