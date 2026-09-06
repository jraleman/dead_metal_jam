# Dead Metal Jam — Game Design Document

> **Status:** design draft, pre-implementation. The first build is a **proof of
> concept for a game jam**, so "MVP" throughout this document means *the jam
> build*: the smallest thing that proves the concept against a deadline.
> **Target engine:** Godot 4.7, `gl_compatibility` renderer, built as a game
> folder inside the existing `dcs_games` base project.
> **Platforms:** **desktop first, web and mobile in scope** (§4.7). The jam
> build targets Linux / Windows / macOS; the other two follow, and nothing in
> this design may foreclose them.
> **Location:** this repository is checked out at
> `dcs_games/godot-base/games/dead_metal_jam/` — one self-contained game folder
> beside `target_rush` and `slice_and_slash`, discovered by `GameCatalog` at
> startup.
> **This document covers gameplay systems only.** Menus, settings persistence,
> boot flow, pause, results, share cards, achievements, accessibility **and the
> shared lives round mode** already exist in `dcs_games/godot-base` and are
> consumed, not rebuilt.
> **The base is shared, so changes to it are additive and game-agnostic.** More
> games are planned on the same base. Dead Metal Jam customises it through data
> — a `GameManifest` plus a per-game `game.cfg` covering colours, assets and
> music (§9.9) — and never by editing framework behaviour or naming itself
> inside framework code.

---

## 1. Concept

*Dead Metal Jam* is **Typing of the Dead with a musical instrument instead of a
keyboard, and robots instead of zombies** — the pitch written in this repo's
`README.md` in 2018, unchanged.

The player rides a fixed rail through a derelict industrial world. Scrap robots
climb out of the machinery and walk toward the camera. Each one is branded with
a **note**. Playing that note on a real instrument — a MIDI controller, or any
monophonic instrument through a microphone — destroys it. Robots that reach the
camera fire, and the player takes damage.

There is no trigger button. The instrument *is* the gun.

### Locked pillars

| Pillar | Decision |
| --- | --- |
| Genre | On-rails shooter. Movement is automatic; the player only aims-by-pitch and times. |
| Reference points | *Time Crisis* / *House of the Dead* for pacing and staging; *SUPERHOT* for the look. |
| Weapon | A real instrument. Note identity matters — a C must be told apart from an E. |
| Presentation | **2.5D fake depth inside the existing 2D playfield.** Enemies scale and translate along lanes; no `Node3D`. Keeps `gl_compatibility` and the `%Playfield` contract intact. |
| Instrument target | **Any monophonic instrument, one note at a time** — guitar, bass, voice, wind, or one key at a time. Chords are stretch. |
| Platform | **Desktop first; web and mobile in scope.** The jam build ships Linux / Windows / macOS. Web and mobile follow, and the input layer is designed so reaching them is a source swap, not a rewrite (§4.7). The base's `gl_compatibility` renderer already exports to all three unchanged. |
| Modes | **All three from `README.md` ship in MVP:** Demo, Rhythm, Jam. |

### Look and tone

*SUPERHOT* aesthetics filtered through the base project's palette
(`scripts/studio_info.gd`): a near-monochrome world in `INK` / `DEEP` / `SLATE`
with `CREAM` highlights, and one saturated hostile red reserved *exclusively*
for enemies and damage. Nothing friendly is ever red. Everything is drawn
procedurally, as both existing games in the base already are — no art pipeline
is required to reach a playable build.

---

## 2. Core gameplay loop

```
        ┌──────────────────────────────────────────────────────┐
        │  Soundcheck (game-owned pre-round overlay)            │
        │  pick mode · pick input device · calibrate latency    │
        │  live note readout proves the instrument is heard     │
        └───────────────────────────┬──────────────────────────┘
                                    ▼
        ┌──────────────────────────────────────────────────────┐
        │  RAIL ADVANCES  — camera slides to the next stage     │
        │  ambient robots, no threat, chart plays the bar count │
        └───────────────────────────┬──────────────────────────┘
                                    ▼
        ┌──────────────────────────────────────────────────────┐
        │  ENCOUNTER — rail halts at a stage mark               │
        │  wave spawns; each bot carries a required note        │
        │  ┌────────────────────────────────────────────────┐  │
        │  │ player plays a note                            │  │
        │  │   → NoteRouter resolves it to a pitch class    │  │
        │  │   → readout shows what was heard               │  │
        │  │   → matches the front-most valid bot?          │  │
        │  │        yes → kill, score by timing tier, combo │  │
        │  │        no  → noise, combo decays               │  │
        │  │ bot's wind-up completes un-killed              │  │
        │  │   → bot fires, −1 life, combo reset            │  │
        │  └────────────────────────────────────────────────┘  │
        │  wave cleared → section-clear bonus                   │
        └───────────────────────────┬──────────────────────────┘
                                    ▼
             lives > 0 and chart remains? ──yes──► RAIL ADVANCES
                                    │
                                    no
                                    ▼
        ┌──────────────────────────────────────────────────────┐
        │  Round over — GameShell results + stats + share card  │
        └──────────────────────────────────────────────────────┘
```

A **round is one track.** The chart's total length sets the round duration. The
diagram above shows the shared *Lives* round mode; under the default *Timer*
mode the same loop runs with no pool — a bot that fires costs points and combo,
and the run simply ends with the chart. Neither shape is game-specific: both
come from the base (§7).

> **Implementation note.** The shell reads `round_duration` when it resets the
> round, and `_load_round_settings()` runs before that, so the track is built
> there and sets the duration from its own length. The figure is a worst case —
> it assumes nothing is ever killed — which makes the timer a backstop and
> `TRACK CLEARED` the normal way a round ends. Leaving the base 30 s default in
> place would have silently truncated every track longer than it.

---

## 3. Modes

All three ship in MVP. They are one code path with three rule flags, not three
games.

| Mode | Pitch matters | Timing matters | Damage | Purpose |
| --- | --- | --- | --- | --- |
| **Demo** | Yes | Yes, but forgiving | **No** | Tutorial and metronome practice. **Time stops until the player hits the beat.** The rail, enemy wind-ups and the chart clock all pause at each beat mark and resume the instant a correct note lands. Nobody can die; the run always finishes. |
| **Rhythm** | **No** — any note counts | Yes, strict | Yes | Onset-only. Kills the pitch-detection dependency entirely, so it is the honest fallback for a noisy room, an unusual instrument, or a player who just wants to hit things. Also the drummer's mode. |
| **Jam** | Yes | Yes | Yes | The standard game. |

**Implementation note.** Demo's "stop time" is scoped deliberately: it freezes
the rail transform, enemy wind-up timers and the chart cursor. It is *not* a
global `Engine.time_scale` change — that would fight `GameShell`'s round timer,
its tweens and the pause overlay. The chart clock is game-owned and already
independent, so freezing it is a one-line gate.

**Damage** in the table above means "this mode reports mistakes to the shell".
What a mistake actually costs is the player's *round mode*, not the game's
choice (§7). Demo is the exception that stays game-owned: it never reports a
mistake at all, so nobody can die in Demo under either round mode.

**Mode selection** happens in the game-owned **Soundcheck** overlay, not the
framework's `mode_select` screen. `mode_select` in `dcs_games` means *player
count*, which is a different axis; overloading it would require framework
edits. See §9.

---

## 4. Input system

This is the load-bearing system. Everything else is a normal rail shooter.

### 4.1 Architecture

Three interchangeable sources feed one router. Gameplay code never knows which
one is live.

```
 ┌───────────────────┐
 │  MidiNoteSource   │──┐   InputEventMIDI → exact pitch
 └───────────────────┘  │
 ┌───────────────────┐  │   ┌──────────────┐    ┌─────────────────┐
 │  MicNoteSource    │──┼──►│  NoteRouter  │───►│  gameplay        │
 │   └ PitchDetector │  │   │  merge       │    │  (dead_metal_    │
 └───────────────────┘  │   │  dedupe      │    │   jam.gd)        │
 ┌───────────────────┐  │   │  latency     │    └─────────────────┘
 │ KeyboardNoteSource│──┘   │  offset      │           │
 └───────────────────┘      └──────┬───────┘           ▼
   (dev / headless / no gear)      └──────────►  NoteReadout UI
```

Every source emits the same value object:

```gdscript
class_name NoteEvent
extends RefCounted

var midi_note: int      # 0-127; -1 when only an onset is known (Rhythm mode)
var pitch_class: int    # midi_note % 12, or -1
var velocity: float     # 0.0-1.0
var cents_off: float    # signed deviation from equal temperament; 0.0 for MIDI
var confidence: float   # 0.0-1.0; always 1.0 for MIDI
var source: int         # MIDI | MIC | KEYBOARD
var timestamp_us: int   # Time.get_ticks_usec() at detection, pre-offset
```

`NoteRouter` owns the only public gameplay surface:
```gdscript
signal note_started(event: NoteEvent)
signal note_ended(midi_note: int)
signal input_level_changed(rms: float)   # drives the readout meter
```

**Hard requirement:** the router must construct and run with **zero sources
attached**. `tests/game_shell_test.gd` iterates `GameCatalog.all()` and drives
every registered game through a full headless round — with no MIDI device and
no microphone. If the input layer blocks, polls a null device, or throws on an
absent audio driver, it breaks the framework's own test suite.

**This is also the platform strategy.** *Which* sources exist is a per-platform
decision (§4.7); gameplay only ever sees `NoteEvent`. Shipping web or mobile
later therefore means adding or dropping a source behind the router — never
touching gameplay, scoring, the chart or the HUD. A source that cannot run on
the current platform simply is not constructed, which is the same code path as
"no device plugged in", and that path is already the tested one.

**What ships today.** All of it: `note_event.gd`, `note_source.gd`, all three
sources and `note_router.gd`. `gameplay.gd` now talks only to the router and
cannot tell a guitar from a MIDI keyboard from the `A` key. Four decisions came
out of building it:

- **A source that fails stays attached.** It reports `is_available() == false`
  with a reason instead of being dropped, so a dead microphone can say *why* on
  screen. Losing the microphone no longer stalls a round either: the other
  sources are attached independently, so play continues on whatever still works
  and the message says so.
- **Latency compensation belongs to the source, not the router.** Each source
  reports its own `latency_ms()` and the router subtracts it. The measured
  round trip in `DmjProfile` (§4.6) is a fact about the *microphone* path;
  applying it to MIDI — which is quantised to the frame and nothing else —
  would push those notes early by the width of the window they are being judged
  against.
- **Duplicates are merged across sources, never within one.** A guitar heard by
  a pickup and a microphone at once is one note, so the second report of the
  same pitch class within 150 ms is dropped. Two notes from *the same* source
  are always two notes: re-striking a string is exactly what the game is
  listening for, and each source already has its own repeat guard.
- **The router has a gate.** `set_accepting(false)` drops everything, which is
  how the soundcheck, the gaps between rounds and the results screen ignore
  playing without every source having to learn what a round is. Before this,
  only the microphone was quiet during the soundcheck — a MIDI note would have
  scored during a countdown the player could not see.

### 4.2 MIDI path (primary)

Godot exposes MIDI natively; no addon is required.

```gdscript
func _ready() -> void:
    OS.open_midi_inputs()
    _devices = OS.get_connected_midi_inputs()

func _input(event: InputEvent) -> void:
    var midi := event as InputEventMIDI
    if midi == null:
        return
    match midi.message:
        MIDI_MESSAGE_NOTE_ON:
            # Velocity 0 is a Note Off in disguise — the classic MIDI trap.
            if midi.velocity == 0:
                _emit_note_off(midi.pitch)
            else:
                _emit_note_on(midi.pitch, midi.velocity / 127.0)
        MIDI_MESSAGE_NOTE_OFF:
            _emit_note_off(midi.pitch)
```

Notes and caveats:

- `OS.open_midi_inputs()` opens **every** connected device at once; there is no
  per-device open. Filter in `MidiNoteSource` using `InputEvent.device` against
  the index chosen in Soundcheck. **Verified on Windows with Godot 4.7.2**: an
  Akai MPK mini Play mk3 reported `device = 0`, matching its index in
  `OS.get_connected_midi_inputs()`, so the field *is* populated and a per-device
  picker is possible. `MidiNoteSource.observed_devices()` records every id seen
  — including ids filtered out — so the same check can be repeated on a platform
  that has not been tried yet. If it ever comes back empty after real playing,
  the picker degrades to "all devices" and stays a no-op.
- Call `OS.close_midi_inputs()` on `_exit_tree()`. Leaving ports open across
  scene changes has caused stuck handles on some ALSA setups.
- MIDI arrives through the normal input pipeline, so it is quantised to the
  frame (~16 ms at 60 fps). Timestamp on arrival and accept that floor; it is
  well inside the "Perfect" window defined in §6.
- Velocity is real data on this path and feeds scoring flavour (a loud kill
  gets a bigger hit reaction). It is *never* a gate — a quiet correct note is
  still a correct note. **Confirmed live**: an MPK mini produced velocities
  across 0.06–0.53 in ordinary playing, so the range is worth reacting to.
- Sustain pedal (`MIDI_MESSAGE_CONTROL_CHANGE`, controller 64) is ignored in
  MVP. Ignoring it explicitly is important: without that, a held pedal makes
  every note look sustained to the Amp Golem check.
- **Platform reach.** `OS.open_midi_inputs()` is native on desktop *and* on
  Android and iOS, where a USB-OTG or Bluetooth MIDI controller shows up as an
  ordinary device. It is **not** available in Godot's web export — WebMIDI is
  not in core, and calling it there errors. Web needs a small
  `JavaScriptBridge` shim over the browser's Web MIDI API, kept in
  `input/web_midi_bridge.gd` behind the same `MidiNoteSource` interface. That
  is a game-owned file, not a framework change, and it is post-jam work (§4.7).

### 4.3 Microphone path (fallback)

Required so a player with no MIDI gear can play. Three parts: enabling capture,
getting samples, and turning samples into a note.

**Enabling capture.** `audio/driver/enable_input` must be `true` in
`project.godot`. It is read when the audio driver initialises, so it cannot be
toggled at runtime — it goes in the project file, and Soundcheck reports
clearly if it is off rather than silently hearing nothing.

**Bus routing.** Create the capture bus **at runtime from the game's own code**
rather than editing the shared `default_bus_layout.tres` — the bus layout is
framework-owned and used by both existing games.

```gdscript
func _create_capture_bus() -> void:
    var index := AudioServer.bus_count
    AudioServer.add_bus(index)
    AudioServer.set_bus_name(index, "Instrument")
    # Critical: never let the live mic reach the speakers, or the player's
    # output feeds the player's microphone and the room howls. Bus volume is
    # applied *after* the effect chain, so the analyser still sees full-scale
    # audio while nothing is audible.
    AudioServer.set_bus_volume_db(index, -80.0)
    _capture = AudioEffectCapture.new()
    _capture.buffer_length = 0.1
    AudioServer.add_bus_effect(index, _capture)

    _player = AudioStreamPlayer.new()
    _player.stream = AudioStreamMicrophone.new()
    _player.bus = "Instrument"
    add_child(_player)
    _player.play()
```

Input device selection uses `AudioServer.get_input_device_list()` and the
`AudioServer.input_device` property, both surfaced in Soundcheck.

**Detecting a dead microphone — the trap.** `AudioEffectCapture` taps the
**bus**, not the device. When the OS refuses the microphone (Windows privacy
settings, no device, a browser permission denial) the bus keeps producing
frames and the capture keeps handing them over, all of them zero. **"No frames
arrived" is therefore not a usable failure signal, and the obvious guard never
fires.** The signal that does work is *perfect digital silence* across the
calibration window: a working microphone always has self-noise, so an exactly
zero peak means nothing is connected. That is what Soundcheck tests, and it
reports the cause rather than showing a flat meter (see the web note below —
the failure mode to design against is a silent one).

**Pulling samples.** Each frame, drain what is available and hand it to the
detector:

```gdscript
var available := _capture.get_frames_available()
if available >= HOP:
    var frames := _capture.get_buffer(available)   # PackedVector2Array
```

Read the buffer on the main thread and hand the array to a worker `Thread`;
`AudioEffectCapture` is not documented as thread-safe for concurrent reads.
Watch `get_discarded_frames()` in Soundcheck — a nonzero value means the game
is not draining fast enough and the readout should say so.

**Off desktop.** The mic is the path that reaches every platform, and it is the
*only* one that reaches web without a shim, so it is worth building well even
though the jam build will mostly be played on MIDI. Three known constraints,
all to be confirmed in the spike rather than assumed:

- **Web** needs a secure context (HTTPS), a permission prompt, and a user
  gesture before the browser will start an `AudioContext` at all. Soundcheck is
  already a gate the player has to press through, so it is the natural place to
  do the unlock — one more reason the overlay exists.
- **Mobile** needs the platform's record permission declared in the export
  preset and requested at runtime. Android's audio input path is also the
  highest-latency one of any target, which the calibration step (§4.6) exists
  to absorb.
- **Threads** are unavailable in single-threaded web builds. The detector must
  therefore degrade to a main-thread budget — a smaller window at a lower hop
  rate — rather than assuming a `Thread` is always available (§4.7).

### 4.4 Pitch detection

**Approach: McLeod Pitch Method (MPM) over the Normalised Square Difference
Function, implemented in pure GDScript.** No GDExtension, no native
dependency — matching how the base project vendors only MIT GDScript
(`third_party/greaby_qrcode`) and synthesises all its audio at runtime.

MPM over YIN because MPM's peak clarity value doubles as a confidence score,
which the readout needs anyway, and it is markedly less octave-error-prone on
plucked strings than plain autocorrelation.

`AudioEffectSpectrumAnalyzer` is deliberately **not** used. Its
`get_magnitude_for_frequency_range()` is a coarse band-energy query; at the low
end of a guitar or bass its bin resolution cannot separate adjacent semitones,
which is exactly the "tell a C from an E" requirement.

**Pipeline, per hop:**

1. **Mono-sum** the `PackedVector2Array`, subtract the window mean. Removing
   the mean is an exact DC notch and needs no state, so the per-window entry
   point stays pure and the unit test stays deterministic.
2. **Decimate 44100 → 11025 Hz**, 4:1, with a short box pre-filter to avoid
   aliasing. Nyquist at 11 kHz is ~5.5 kHz, far above the highest fundamental
   we accept, and it cuts the inner-loop cost by 4×.
3. **RMS gate.** Below the noise floor measured during Soundcheck, emit
   silence and skip the rest. This is what keeps room hum from firing the gun.
4. **NSDF** over a **512-sample window** (~46 ms) with a **256-sample hop**
   (~23 ms), evaluated only across the lag range implied by the playable pitch
   range — **E2 (82.4 Hz) to C6 (1046.5 Hz)** — plus **a semitone of headroom
   at each end**, giving lags **9 to 142** at 11025 Hz. The headroom is not
   optional: without it a guitar tuned 30 cents flat needs lag 136 and a range
   stopping at E2 exactly stops at 134, so the low string simply goes unheard.
   That is ~64k multiply-adds per hop, ~43 hops/sec. The lag bounds are derived
   from the capture rate at runtime, so a 48 kHz driver widens them to 10–155
   rather than detuning every reading.
5. **Peak pick** with MPM's threshold rule — first peak at or above
   `k · max_peak` with `k = 0.9` — then **parabolic interpolation** around it
   for sub-sample lag precision. The threshold compares peaks *after*
   interpolation. Comparing raw NSDF samples instead silently loses the top
   octave: A5 is only 12.5 samples per period, so its true peak falls between
   two samples and reads ~0.85, while the peak at twice the lag lands almost
   exactly on a sample and reads ~1.0 — and the real note fails the threshold
   against its own harmonic.
6. `f0 = 11025.0 / interpolated_lag`; `confidence` = the NSDF value at that peak.
7. **Convert:** `midi = 69.0 + 12.0 * log(f0 / 440.0) / log(2.0)`,
   `cents_off = (midi - round(midi)) * 100.0`.
8. **Stabilise:** median-of-3 across hops. There is deliberately **no separate
   octave-correction pass** — see the measured result below.
9. **Onset:** emit `note_started` when the same note has been stable for two
   hops, a refractory period (~60 ms) has elapsed, *and* an **attack** is live
   and settled. A changed pitch is **not** on its own sufficient — see the fifth
   fault below, which is the one that cost the most.

**The onset rule was rebuilt after the first real-instrument session, and it is
the part of this pipeline that has been wrong most often.** Everything above it
was validated against synthesised tones in Milestone 1 and has not needed to
change since. The onset rule was validated the same way and that turned out to
mean almost nothing, because the corpus was *isolated plucks separated by
silence* — the one thing a player never does. Against actual playing it lost
four re-strikes in six and fired twice on a single note change. Six separate
faults, each worth recording because each is a trap the next person will fall
into:

| Fault | Why it happened | Fix |
| --- | --- | --- |
| A re-plucked string went unheard | The threshold was set for a note starting from silence (1.8x). A string struck again while ringing *adds* to what is there; the real step is 1.15x–1.6x. | Threshold lowered, with hysteresis to make it safe. |
| The trailing average ate the attack | It is the reference an attack is measured against, and it followed the signal at 0.25 — so it absorbed a quarter of the transient in one hop and the ratio never cleared. | The average is **frozen** for the first few hops of an attack. |
| Loudness was tested at the wrong moment | The transient peaks in about a hop; the decision waited two hops for the pitch to settle, by which time the evidence was gone. | The attack is **latched** when it happens and spent when the note becomes nameable. |
| One pluck read as two notes, the first mislabelled | An analysis window is ~46 ms, about twice a hop, so for a hop or two after any attack the window still holds the *previous* note — and the detector fired on it before the new pitch resolved. | An attack is unusable until the window-straddle has passed (`ONSET_ATTACK_SETTLE_HOPS`). |
| **A changed pitch counted as a new note on its own** | "Different note, so it must be new" is false for a microphone. A real string sheds energy from its fundamental fastest, so partway through a long note the second harmonic is the loudest thing left and the estimator starts naming *that* — a phantom an octave up, on a note still loud enough to pass any noise gate. Room tone drifts the reading a semitone and does the same. | **An onset now always requires an attack.** Only a microphone reaches this code — keyboard and MIDI notes arrive already separated through their own sources — so the rule can be the physical one: you cannot start a note on a string without putting energy in. |
| The trailing average went deaf after every onset | It is frozen through an attack, so at the moment an onset fires it still describes the *silence before* the note. Left to converge it spends ~5 hops climbing, and every one of those reads high enough to look like an ongoing attack — which holds the hysteresis disarmed. A fast run lost its second note this way. | On an onset, snap the average to the accepted note. Once a note is accepted it *is* the background the next attack must beat. |

The attack test itself is two comparisons, because neither alone is enough. A
note from near-silence is obvious against the **trailing average**. A note
re-struck mid-ring barely moves the average at all, but stands clearly above the
**recent trough** — the quietest hop just before it. The trough is a rolling
minimum rather than the previous hop precisely because a transient straddles two
hops: measured on a tremolo at 0.18 s, hop-to-hop comparison peaked at 1.10
while the same attack stood 1.26 above its trough.

Both comparisons are **ratios**, and a ratio is scale-free — which is why a
third test is needed. Noise drifting from 0.02 to 0.03 is the same 1.5x step as
a note starting from nothing, so proportion alone fires continuously on room
tone. The voiced check is not enough either: it compares against a floor
measured during a *quiet* calibration, while a room in use also contains
handling, pick scrape and the tails of notes already struck. So a hop must also
stand clear of the measured floor by `ONSET_NOISE_MARGIN` before it may be an
attack at all. Proportion says *something changed*; the margin says *there is a
note here to change*.

**A legato exception was written, measured and removed.** Hammer-ons start a
note without a fresh strike, so allowing a changed pitch through on the weaker
test of "the level has not sagged" looked necessary. It was not, and it was
actively harmful: a level that has merely held is also what a string sheds into
as its fundamental dies, so the exception readmitted the exact phantoms it was
written beside. A finger landing on a fret is a *quiet attack, not an absent
one*, and the trough test already hears it — measured, from about 1.4x the level
still ringing. A limp hammer-on does not register, which is also true of a real
guitar.

All thresholds were **swept against the whole scenario set, not picked**. The
noise margin is a worked example: at 1.0 and 1.5 a decaying string's tail still
put a phantom semitone neighbour into a six-note phrase, and at 3.0 a genuine
fingerpicked note was swallowed. 2.0 and 2.5 both pass, so the shipping value
sits between them rather than on either edge — the corpus is synthesised, and a
value that only just passes it would be tuned to the model rather than to the
instrument.

**Measured, not assumed.** The detector and its corpus were built first
(Milestone 1) and the numbers below come from running it, not from estimating:

| Result | Measurement |
| --- | --- |
| Note identification | 0 errors across E2–C6, sine/saw/square, 2 phases each |
| Tuning accuracy | ≤1.2 cents E2–E4, ≤6 cents to E5, ≤7 cents to C6 |
| Intonation tracking | ≤2 cents error E2–E4, ≤6 to E5, ≤10 at C6 |
| Confidence on clean input | ≥0.94 |
| Confidence on white noise | 0.0 — noise is never reported as a note |
| Cost | **2.2 ms per window** against a 23.2 ms hop budget — 10%, measured in Godot 4.7.2 |

**Playing techniques** are now measured too, and are permanent regression tests
in their own suite (`tests/playing_techniques_test.gd`, split from the detector
tests once it outgrew them). Every row was a failure before the onset rebuild:

| Technique | Expected | Result |
| --- | --- | --- |
| Six different notes, silence between | 6 onsets, correct notes | ✅ (was 11, alternating mislabels) |
| Same string re-struck every 0.5 s while ringing | 6 | ✅ (was 2) |
| Same string re-struck every 0.25 s | 6 | ✅ (was 1) |
| Tremolo picking at 0.18 s | 6 | ✅ (was 1) |
| Fast melodic line, damped, 0.15 s apart | 6, correct notes | ✅ |
| Fingerpicking at ~1/9 strum level | 6 | ✅ |
| Hammer-on onto a ringing string | 2 | ✅ — sets the quiet limit, ~1.4x the ringing level |
| **One note held for 4 s** | **exactly 1** | ✅ |
| **Fundamental dying before its 2nd harmonic** | **exactly 1** | ✅ (was 2 — the phantom octave) |
| Three notes left overlapping | — | 1: monophonic by design, see below |

Every one of those is then run **again over room tone**, which is the harder
half and the half that was missing entirely:

| In a room | Expected | Result |
| --- | --- | --- |
| Room tone, nothing played | **0 onsets** | ✅ |
| Six notes over room tone | 6, correct notes | ✅ |
| Re-strikes at 0.25 s over room tone | 6 | ✅ |
| A note decaying into room tone | **exactly 1** | ✅ |
| Fingerpicking over room tone | 6 | ✅ — the tightest case in the suite |

Crucially the room is **noisier than the calibration**, because that is how
playing works: you calibrate once, in a quiet moment, before picking the
instrument up. A suite that calibrates and plays at the same noise level is
testing a room nobody plays in, and the gap between those two numbers is exactly
where phantom notes live.

The held-note and octave-drift rows are the load-bearing ones. Catching a
re-strike is trivial if invented notes are free; it is only meaningful next to a
sustained note that must produce exactly one onset, and a decaying string's own
beating is within a few percent of a genuine tremolo attack. Those pairs are what
pin the thresholds — and the suite was verified to *fail* against the previous
detector before being trusted.

The detector is **monophonic** and stays that way for the jam. Three notes left
ringing together resolve to one, which is a property of the algorithm rather
than a bug in the tuning: MPM estimates *a* period, and a chord has several.
Charts are written as single notes, so this is a limit the game never reaches —
but it is measured rather than assumed, so it cannot quietly become a surprise.

Accuracy falls off with pitch because C6 is only ~10.5 samples per period once
decimated. That is well inside the ±50 cents a semitone allows, so it does not
affect matching, but the tuner readout is correspondingly coarser up there.

**An octave-correction pass was written, measured and removed.** The intent was
to catch notes whose fundamental is weak or missing. Against the corpus it
rescued *nothing* — MPM's first-peak rule already handles a missing fundamental
and fundamentals down to 5% strength — while pushing A5 and C6 down an octave,
because a parabola is a poor fit to an NSDF peak only ~11 samples wide. Taking
the **first** peak above the threshold, rather than the strongest, is the whole
octave defence, and it is sufficient.

**Octave-insensitive matching is the default.** Gameplay compares
`pitch_class` (0–11), not absolute MIDI number. Octave errors are the single
most common pitch-detection failure across every instrument and every
algorithm, and the game does not need octaves to be fun. A strict-octave
toggle lives in Soundcheck for players who want it.

### 4.5 Keyboard source (dev, headless, accessibility)

A computer-keyboard piano layout (`A S D F G H J` → C D E F G A B, with the
black-key row above). It exists for three real reasons, not as a convenience:

1. `tests/game_shell_test.gd` must be able to drive a full round headlessly.
2. `tools/tutorial_capture.tscn` records the instructions video with a scripted
   demo player — which cannot hold a guitar. Without this source there is no
   tutorial clip.
3. A player whose gear is not working can still finish the round.

It is not hidden. It is a listed input option, marked "practice".

**What ships today.** `KeyboardNoteSource`, with the layout every tracker and
DAW already uses — `A S D F G H J K` for the white keys under `W E T Y U` for
the black ones, `Z` and `X` to shift the octave. Two notes on it:

- **The self-test tone moved from `T` to `F2`.** `T` is F♯ once a piano is on
  the keyboard, and a diagnostic that silently steals a note is worse than a
  diagnostic on a duller key. Every letter in both home rows is now a note, so
  anything the game binds has to live on a function key.
- **Held keys are released before an octave shift.** Otherwise a note started
  before the shift would be ended with the number it *would* have had after it,
  and the note would never stop. The test asserts the note ends with the number
  it started with.

A phone has no keyboard, so mobile gets the same idea in a different shape: a
**touch onset source** — tap anywhere on the playfield to fire an onset-only
`NoteEvent`, which is exactly what Rhythm mode already consumes. It is a fourth
`NoteSource` and nothing else, so it costs the rest of the game nothing. Post-
jam (§4.7).

### 4.6 Latency and calibration

| Stage | Typical | Notes |
| --- | --- | --- |
| Acoustic → mic → OS buffer | 5–20 ms | Driver dependent; ASIO/JACK far better than default WASAPI/PulseAudio. |
| `AudioEffectCapture` buffer | ~10 ms | `buffer_length = 0.1`, drained every frame. |
| Detection window fill | ~46 ms | Dominates the mic path. Unavoidable at this window size. |
| Frame quantisation | ~16 ms | Both paths. |
| **Mic total** | **~80–90 ms** | |
| **MIDI total** | **~16–20 ms** | |

Two consequences, both designed for rather than papered over:

- **A calibration step in Soundcheck.** The metronome ticks; the player plays
  along for eight scored beats (twelve, less a two-beat count-in and a tail);
  the median signed offset is stored as `input_latency_ms` and subtracted from
  every subsequent `timestamp_us`. This is what makes the mic path competitive
  with MIDI on timing. Built — see "What ships today" below for why the figure
  is a median and where it is persisted.
- **Timing windows are generous by genre standards** (§6). A rail shooter is
  not a rhythm game with 20 ms judgements, and the mic path could not honour
  those windows anyway.

Mobile web is the worst case on this table — a browser audio path on a phone —
and it is the last target, not the first, for exactly that reason (§4.7).

**What ships today.** `input/mic_capture.gd` (`MicCapture`) owns the bus, the
device, calibration and the self-test; both the standalone tuner and the round
scene use it, so there is one implementation of the audio plumbing rather than
two that drift. Two decisions came out of building it:

- **A self-test tone.** `MicCapture.toggle_test_tone()` injects a 220 Hz sine
  straight into the capture bus, reachable with `T` in both the tuner and the
  round. A silent microphone and a broken analyser look identical from the
  player's side of the screen, and this is what tells them apart — it is also
  the only way the pitch path can be verified on a machine with no working
  input device, which is the situation this game was developed on.
- **The countdown waits for the soundcheck, not the other way round.** The
  round starts on the framework's schedule so the shell's round bookkeeping
  stays intact, and `_update_round()` holds `%RoundTimer` paused until the room
  has been measured. Deferring the round start itself was tried first and
  broke the shared contract in `game_shell_test.gd`, which requires
  `_begin_first_round()` to actually begin one.
- **The latency screen is built** — `ui/calibration.tscn`, backed by
  `input/latency_calibration.gd`, `input/metronome_click.gd` and
  `dmj_profile.gd`. Four decisions came out of building it, three of which
  contradict what the rest of this section originally said:

  - **The click is broadband noise, not a tone.** A tonal click is a note, and
    the analyser cannot tell the game's own metronome from the player. Even a
    3 kHz sine has NSDF peaks at short lags inside the search range. Noise has
    no period, so it reads as unvoiced and is invisible to the detector;
    `latency_calibration_test.gd` asserts the metronome fires **zero** onsets
    while a G3 played over it still fires exactly one.
  - **Notes are dated on the audio clock, not the frame clock.** A drained
    block is up to a frame long, so stamping every sample in it with "now"
    smears a note across tens of milliseconds — against a ±60 ms window that
    is most of the budget. `PitchAnalysis.sample_index` counts samples on the
    stream itself, and wall time is recovered by counting backwards from the
    newest sample: `wall(S) = now - (pushed - S) / rate`.
  - **The stored figure is the median, not the mean.** Eight scored beats is a
    small sample and one fumbled note drags a mean straight past the tolerance
    the exercise exists to establish. Spread is reported as the mean absolute
    deviation about that median, and a run whose spread exceeds 45 ms is
    rejected rather than stored — an inconsistent player has measured nothing.
  - **The detector's own delay is a measured constant, not a formula.** A
    window turns voiced once the note fills roughly a third of it, not half and
    not all, so anything derived from `WINDOW_SIZE` overstates it by 15 ms and
    up. `TYPICAL_ONSET_DELAY_SECONDS = 0.042` is what the analyser was actually
    observed to do (34.6–49.6 ms at 48 kHz), and a test fails if reality drifts
    more than one hop from it. **Constancy matters more than the value**: a
    fixed delay is subtracted once and disappears, while a wandering one puts a
    floor under accuracy that no calibration can lift. Measured jitter is
    14.9 ms, inside a single 21.3 ms hop.

  The screen has been verified end to end against an injected offset — an
  80 ms simulated delay was measured as 81.9 ms — but **not yet against a real
  microphone**, so the 80–90 ms row in the table above is still an estimate
  rather than an observation.

### 4.7 Platform ladder

All three platforms are in scope. They ship in the order of how much new work
they need, and **desktop is first because the jam deadline is real**: the PoC
has to prove that playing a note kills a robot, and it should prove that on the
platform where the input stack is already native.

| Platform | MIDI | Microphone | Practice input | Status |
| --- | --- | --- | --- | --- |
| **Desktop** (Linux / Windows / macOS) | Native `OS.open_midi_inputs()` | Native | Keyboard | **Jam build.** |
| **Mobile** (Android / iOS) | Native — USB-OTG or Bluetooth controllers appear as normal devices | Native, after a runtime permission | Touch onset (§4.5) | **Next.** Needs permissions, touch UI and a latency pass. |
| **Web** | **Not in core** — needs a `JavaScriptBridge` shim over Web MIDI (§4.2) | Native, behind HTTPS + a permission prompt + a user gesture | Keyboard, or touch on a phone browser | **Last.** The most new code and the worst latency, but the widest reach — and a jam entry people can click is worth having. |

**What each one actually costs**

- **Mobile:** record permission in the export preset; the touch onset source;
  a portrait-friendly pass over the note readout (§5.1) and the Soundcheck
  overlay. The base already carries the rest — `Settings._update_content_scale()`
  scales the UI on small screens, the HUD's on-screen **PAUSE** button appears
  when `DisplayServer.is_touchscreen_available()` is true, and
  `GameSession.multiplayer_available()` already forces single player, which
  this game declares anyway.
- **Web:** `input/web_midi_bridge.gd`; the gesture-gated audio unlock inside
  Soundcheck; and a detector budget that survives without a worker `Thread`
  (§4.3). `ShareManager` already downloads the score card in a browser instead
  of writing a file, so sharing needs nothing.

**Two rules keep this honest while the jam build is being written**

1. **No platform checks in gameplay.** Platform differences are resolved once,
   where sources are constructed, and never again. If `dead_metal_jam.gd` ever
   asks `OS.has_feature("web")`, the abstraction has failed.
2. **Nothing desktop-only becomes load-bearing.** Anything the design leans on
   must have a stated fallback that works with mic-or-touch input alone —
   which is precisely what Rhythm mode already is (§3). The game must stay
   winnable when the only thing available is "the player made a sound".

**Not promised:** simultaneous release. Web and mobile are in scope and
unblocked by this design; they are not jam deliverables, and they will be
judged on whether the latency they actually measure keeps the game fun.

---

## 5. UI and feedback

### 5.1 Note readout — the most important widget in the game

The player must *always* know what the game just heard. Ambiguity here reads
as the game being broken. Permanently visible, bottom-centre, game-owned:

```
   ┌────────────────────────────────────────────────┐
   │   ▁▃▅█▅▃▁   ◄ input level                      │
   │                                                │
   │        ┌──────┐                                │
   │        │  E   │   E3 · +6¢   ● MIDI            │
   │        └──────┘   ◄──┼──►    conf 0.94         │
   │         detected      tuner strip              │
   └────────────────────────────────────────────────┘
```

- **Note letter, large.** Text, not colour — the base project's accessibility
  rule forbids encoding meaning in colour alone, and `README.md`'s per-note
  colour map is a garnish on top of the letter, never a substitute.
- **Octave and cents deviation**, so a player can tell "you're flat" from
  "you played the wrong note".
- **Tuner strip** — a centre-marked bar showing cents off. Doubles as a real
  tuner during Soundcheck.
- **Source badge** — MIDI / MIC / KEYS. Removes all doubt about which path is
  live.
- **Confidence** as a small bar on the mic path. A confident wrong answer and
  an unsure guess must not look the same.
- **Input level meter**, always live. A flat meter is the first thing to check
  when nothing is happening.

### 5.2 In-world feedback

- Each bot displays its required note as a large glyph on its chassis, sized so
  it stays legible at spawn distance.
- The front-most valid target is outlined — the shell's existing "one bright
  target" convention from Target Rush, carried over.
- Correct note: the bot shatters into procedural fragments, note glyph bursts
  outward, brief screen shake via `GameShell._add_screen_shake()`.
- Wrong note: a short dissonant sting, combo meter cracks, no world change.
  Wrong notes must feel *inert*, not punishing-loud, or players stop
  experimenting.
- Wind-up telegraph: an arc fills around the bot over its wind-up beats, with
  an audible tick. Both channels, always.
- Damage: the shell reacts first — `_lose_life()` already flashes its danger
  colour, shakes the screen, announces `LAST LIFE!` / `OUT!` and captions it,
  honouring the intense-visual-effects and reduced-motion settings. The game
  adds only what the shell cannot know about: the bot's muzzle flash and a
  ~120 ms hit-stop.

### 5.3 HUD additions

`GameShell`'s HUD already provides score, streak, callout, hint, announcement
labels and the TimerCard — which reads `SECONDS LEFT` or `LIVES LEFT` depending
on the round mode (§7) — all reused as-is. The game adds one `CanvasLayer` of
its own inside its inherited scene — no framework scene is modified:

- **Note readout** (§5.1), bottom-centre.
- **Section banner** — "CHORUS", "BRIDGE" — using the chart's own section
  names, on each rail advance.
- **Combo multiplier**, next to the score.

There is deliberately **no game-owned lives widget**. The shell already renders
the pool, reddens it on the last life, and keeps it legible under player
labels, colour-blind palettes and reduced motion. A second lives display would
only be one more thing to keep in sync.

---

## 6. Scoring

Reuses `GameShell`'s score and streak state (`_scores`, `_streaks`,
`_best_streaks`) so the HUD, results panel, stats panel and share card all work
with no extra wiring.

### Timing tiers

Measured against the enemy's scheduled beat, after latency compensation:

| Tier | Window | Base points |
| --- | --- | --- |
| Perfect | ±60 ms | 100 |
| Good | ±140 ms | 60 |
| Late / Early | ±260 ms | 25 |
| Outside | — | miss |

Windows widen by the `Settings.target_size_scale()` handicap (up to 140%), the
same assist the other two games use for target size. Reusing that setting
rather than adding a new one keeps one honest "make it easier" dial.

### Modifiers

- **Combo multiplier** — ×1 / ×2 / ×4 / ×8 at 5 / 15 / 30 consecutive kills.
  Any miss, any damage taken, or sustained noise drops it to ×1.
- **Pitch bonus** — +15% when `abs(cents_off) <= 25`. Always granted on the
  MIDI path (it is exact by construction); earned on the mic path. This is the
  one place intonation is rewarded, and it is a bonus, never a gate.
- **Section clear** — +250 for clearing a wave with zero damage taken.
- **Noise penalty** — notes played with no valid target decay the combo meter
  (not the score). This is what stops "play every note fast" from being a
  strategy, without punishing a player who is warming up between waves.
- **Wrong note** — −25 and combo reset. Never reports a mistake to the shell,
  so it never costs a life in any round mode (§7.3).

#### Which of those two a note gets — decided in the build

The two penalties above look like one rule until you implement them, because a
played note can miss in three different ways, and only one of them deserves the
score hit:

| Situation | Judgement | Why |
| --- | --- | --- |
| No drone is on screen at all | **Noise** — combo only | Between waves. Warming up, tuning and noodling have to be free, or the game punishes practising. |
| Drones are up, the pitch matches none of them | **Wrong note** — −25, combo reset | The player aimed and picked the wrong target. This is the mistake the penalty exists for. |
| Drones are up, the pitch matches one, but it is not inside a timing window yet | **Noise** — combo only | The player identified the right target and was merely early. Charging points for that teaches hesitation, which is the opposite of what a rhythm game wants. |

The third row is the non-obvious one and it is deliberate. Being early on the
correct note is a *timing* error, and timing errors are already paid for by the
tier ladder — charging twice makes the game feel like it is looking for reasons
to say no.

### Stats fed to the framework

`_round_totals()` and `_player_stats(0)` are overridden to report hits, misses,
accuracy, best combo and best streak — filling the existing results and stats
panels, and the share card, with no new UI.

---

## 7. Lives and health

**The base project owns lives.** Since the round-mode work landed in
`dcs_games`, `GameShell` and `Settings` ship a shared round mode that every
game inherits, chosen by the player under *Settings → Game → Round mode*:

| Round mode | What ends the round | What a mistake costs |
| --- | --- | --- |
| **Timer** (default) | The countdown reaches zero. | Points and combo only. |
| **Lives** | Every player's pool is empty. There is no countdown at all. | One life, plus points and combo. |

It is stored as `game/round_mode` + `game/starting_lives` (1–9, default 3) and
read once per round in `_load_round_settings()`, so switching modes shapes the
*next* round rather than the live one. Dead Metal Jam therefore ships **no
lives system of its own** — the earlier draft of this document specified one,
and it is now deleted rather than duplicated.

### 7.1 What Dead Metal Jam does

Four calls, and that is the whole integration.

| Call | When |
| --- | --- |
| `_lose_life(0)` | A bot completes its wind-up un-killed and fires. |
| `_player_is_out(0)` | Checked before a note is routed to a target, so an eliminated player stops scoring. |
| `_lives_rule_note()` | Appended to the HUD hint — "Each mistake costs 1 of 3 lives". |
| `_round_length_phrase()` | Used in results copy instead of naming the chart length. |

A bot that fires also resets the combo and leaves the field — it does not
linger and chain-hit. Both of those are game rules, and they stay game-owned.

**The game must never branch on the round mode.** `_lose_life()` and
`_player_is_out()` no-op under the countdown and `_lives_rule_note()` returns
an empty string, so all four calls above are unconditional. Under *Timer*, a
bot that fires costs points and the combo and the run is bounded by the chart:
Dead Metal Jam is a score-attack track run. Under *Lives*, the same bot costs a
life and the track can end early. One code path, two shapes — the same
arrangement Target Rush (a wrong key) and Desk-Can-Saw (an escaped can) already
use.

### 7.2 What the shell already provides

Free, and not to be re-implemented:

- The TimerCard becomes a `LIVES LEFT` readout — `3` solo, `3-2` in two-player
  — and the progress bar empties towards zero lives instead of zero seconds.
- The last life reddens and pulses on the same danger scale the final seconds
  use (`_lives_urgency_seconds()`), so the fail state reads identically in both
  modes.
- `_lose_life()` flashes the danger colour, adds screen shake, announces
  `LAST LIFE!` / `OUT!` and emits the matching audio caption — each one already
  gated by the intense-visual-effects, reduced-motion and caption settings.
- Zero lives calls `_end_round()`, the same settle-and-present path the
  countdown uses: results, stats, achievements, share payload.
- `_round_mode_summary()` labels the share card `Single Player - 3 Lives`, and
  `_round_length_phrase()` words results as "94 seconds on 3 lives".

### 7.3 Game-specific rules on top

- **Demo mode never spends a life.** It simply does not call `_lose_life()` —
  a flag on a mode the game already owns, not a round-mode branch. Nobody can
  die in Demo under *either* round mode, which is what makes it the on-ramp.
- **Wrong notes never cost a life,** in any mode. They cost points and the
  combo (§6). Only a bot that actually fires is a mistake worth a life —
  otherwise experimenting with the instrument is punished, in a game whose
  whole subject is playing an instrument.
- **No regeneration in MVP.** "Three consecutive clean sections → +1 life,
  capped at the starting pool" is designed but flagged stretch: it needs tuning
  data MVP will not have, and it would need a matching generic `_gain_life()`
  in the shell, which is a good reason to wait until the rule is proven.

### 7.4 The one remaining early-end case

Losing is solved: `_lose_life()` ends the round on the last life. **Winning is
not.** The chart running out before the countdown does — `TRACK CLEARED` — is
still an early end the shell has no public verb for, and since *Timer* is the
default mode it is the common case, not the edge case.

1. **No framework change:** call the inherited `_end_round()`. It is already
   the single settle path for both round modes and it stops the timer itself,
   so this is correct today — it just reaches into a `_`-prefixed method the
   shell treats as internal.
2. **Recommended:** add a public `finish_round_early()` to
   `scripts/game_shell.gd` that does nothing but call `_end_round()`. This is
   *not* the forbidden kind of framework change: it names no game, adds no
   `if game_id == …`, and any game with a completable objective needs it.

Ship option 1 in the spike; migrate when the framework addition can be reviewed
on its own.

---

## 8. Enemies and encounter design

### 8.1 Staging

Three lanes across, fake depth toward the camera. A bot spawns at the horizon
on a lane, walks toward the camera over its **approach beats**, then enters
**wind-up** and fires. Depth is `scale` plus `y` offset plus draw order — no
3D, no perspective camera.

Rail-shooter pacing means the camera is only stationary during encounters. On
rail advances the player cannot be hurt, which gives the breathing room a
music game genuinely needs — nobody can sight-read continuously for four
minutes.

### 8.2 Roster

| Enemy | Demand | Teaches | MVP |
| --- | --- | --- | --- |
| **Rust Drone** | One note, one hit. | The core verb. | ✅ Built |
| **Feedback Wasp** | One note, very short window, fast approach. | Reaction speed; punishes hesitation. | Yes |
| **Plated Hulk** | A 2–3 note sequence, in order, one plate per note. | Phrasing; reading ahead. | Yes |
| **Amp Golem** | Hold the note for N beats — released early, it re-armours. | Sustain and breath/bow control. Uses `note_ended`. | Yes |
| **Mirror Unit** | *Plays a note at the player*; the player answers with the same note. Its glyph stays blank. | Ear training. The purest expression of the concept, and the reason the game isn't just a note-reading test. | Yes |
| **Silence Sentry** | Fires if *any* note is played while it crosses. Killed by waiting it out. | Restraint; makes the noise penalty legible as a rule. | Stretch |
| **Detonator** | A wrong note anywhere on screen while it lives counts as a hit. | Precision under pressure. | Stretch |
| **The Conductor** (boss) | Phases, each demanding a riff drawn from the chart. | Payoff. | Stretch — MVP ends on a heavy wave, not a boss. |

### 8.3 Note-to-shooting mapping

- A played pitch class resolves against **the front-most bot whose required
  note matches**. Front-most, not nearest-to-cursor — there is no cursor, and
  front-most is also the most urgent, so the intuitive read and the optimal
  read agree.
- Ambiguity is a design tool: two bots on the same note in one wave means one
  note kills both in sequence, front to back. This is a feature, and charts
  should use it for tremolo-picked runs.
- In **Rhythm mode** every bot accepts any note; the front-most valid target is
  simply the front-most bot.
- Multi-note enemies (Hulk) hold an internal cursor and reset it on a wrong
  note in the sequence.

**As built:** front-most and in-window are two separate decisions, made in that
order. The live drones are sorted by approach progress, and the first one in
that order that both matches the pitch *and* is inside a timing window is the
one that dies — **front-most decides *which*, the window decides *whether*.**
Collapsing those into one filter looks equivalent and is not: it would let a
note skip past a matching front drone that was fractionally early and kill the
one behind it, which reads on screen as the shot going through the target.

### 8.4 Art

The MVP ships **flat placeholder rectangles** with the required note letter
drawn on them — body, lane tint, a wind-up bar and a target outline, nothing
more. This is on purpose for the jam: the rules above are the risky part, and
they are legible without art. Depth is faked with position, `scale` and
`z_index`, and the walk toward the camera is **linear** rather than eased, so
the arrival beat is predictable enough to play to. Everything an artist would
replace is confined to `RustDrone._draw()`.

### 8.5 Wave authoring

Waves come from the chart (§10). A section names its wave archetype and the
generator places bots on lanes at chart beats. Handwritten per-bot placement is
supported but expected to be rare — the point is that a chart is a *song*, and
the enemies fall out of it.

---

## 9. Integration with `dcs_games`

### 9.1 File layout

Everything lives under one self-contained folder. `GameCatalog` discovers it at
startup by globbing `games/*/game.gd`.

```
godot-base/games/dead_metal_jam/
  game.gd                      # ✅ static manifest() -> GameManifest
  game.cfg                     # colours, assets, music — the only base customisation (see 9.9)
  dead_metal_jam_options.gd    # class_name, CONSTANTS ONLY (see 9.4)
  gameplay.tscn                # ✅ inherited scene of scenes/game/game_shell.tscn
  gameplay.gd                  # ✅ extends GameShell
  input/
    note_event.gd              # class_name NoteEvent
    note_source.gd             # ✅ class_name NoteSource (abstract base)
    note_event.gd              # ✅ class_name NoteEvent — the only thing gameplay sees
    midi_note_source.gd        # ✅ class_name MidiNoteSource
    mic_capture.gd             # ✅ class_name MicCapture — bus, device, calibration, self-test
    mic_note_source.gd         # ✅ class_name MicNoteSource — MicCapture + PitchDetector
    keyboard_note_source.gd    # ✅ class_name KeyboardNoteSource
    touch_note_source.gd       # post-jam, mobile (see 4.5 / 4.7)
    web_midi_bridge.gd         # post-jam, web only (see 4.2 / 4.7)
    pitch_detector.gd          # ✅ class_name PitchDetector — pure DSP, no autoloads
    pitch_analysis.gd          # ✅ class_name PitchAnalysis — one hop's result
    latency_calibration.gd     # ✅ class_name LatencyCalibration — pure math, no nodes
    metronome_click.gd         # ✅ class_name MetronomeClick — pre-rendered noise clicks
    onset_log.gd               # ✅ class_name OnsetLog — opt-in CSV, retunes the onset rule
    note_router.gd             # ✅ class_name NoteRouter — merge, dedupe, latency
  chart/
    jam_chart.gd               # class_name JamChart extends Resource
    jam_section.gd
    jam_beat.gd
    charts/track_01.tres
  encounter/
    encounter_director.gd      # ✅ class_name EncounterDirector — lanes, waves, matching, tiers
    track_builder.gd           # ✅ class_name DmjTrackBuilder — practice waves; the chart's seam
  enemies/
    rust_drone.gd              # ✅ class_name RustDrone — approach, wind-up, fire
    feedback_wasp.gd           # see 8.2
    plated_hulk.gd
  ui/
    tuner.tscn + .gd           # ✅ standalone soundcheck / tuner, runnable on its own
    calibration.tscn + .gd     # ✅ standalone latency calibration, runnable on its own
    input_check.tscn + .gd     # ✅ standalone: every source at once, what the router emits
    note_readout.tscn + .gd
    soundcheck.tscn + .gd
    share_art.tscn + .gd       # game-owned share card art
  assets/
    audio/                     # track audio and game SFX referenced by game.cfg
    images/
  tests/
    pitch_detector_test.gd     # ✅ DSP: which note is this window?
    playing_techniques_test.gd # ✅ the onset rule against real playing, in a real room
    latency_calibration_test.gd  # ✅ hardware-free: matching, timestamps, click silence
    note_router_test.gd        # ✅ hardware-free: dedupe, offset, keyboard layout, MIDI
    encounter_test.gd          # ✅ the rules: matching, tiers, wind-up, waves, track end
    jam_chart_test.gd
```

**Why `encounter/` is not in `gameplay.gd`.** `gameplay.gd` extends
[`GameShell`], which uses autoload instances, so a headless `--script` test can
never name it (§9.8). Every rule that needs testing therefore lives in
`encounter/` and `enemies/`, which touch no autoload at all — `gameplay.gd` is
left holding only the wiring between the shell, the router and the director.
That is why `encounter_test.gd` can drive the real rules rather than a copy.

✅ marks what exists today. `gameplay.gd` / `gameplay.tscn` follow
`target_rush`; the folder name matches the manifest id, as in the other two
games, so nothing has to reconcile the two. The id is also a `project.godot`
key (`share/stats_urls/<id>`), which is the reason it stays snake_case.
`dmj_profile.gd` sits beside `game.gd` at the folder root: it is the game's own
`user://` file, not part of the input stack.

**Trying it without the menu.** The tuner and calibration scenes run on their
own, which is the fastest way to check a microphone or a new instrument:

```
godot --path godot-base res://games/dead_metal_jam/ui/tuner.tscn
godot --path godot-base res://games/dead_metal_jam/ui/tuner.tscn -- --selftest
godot --path godot-base res://games/dead_metal_jam/ui/calibration.tscn
godot --path godot-base res://games/dead_metal_jam/ui/calibration.tscn -- --selftest
godot --path godot-base res://games/dead_metal_jam/ui/input_check.tscn
```

`F2` toggles the microphone self-test tone in any of them, `Esc` leaves.
`--selftest` on
the calibration scene plays synthetic plucks in place of a player, so the
screen can be exercised on a machine with no microphone — which is the machine
it was written on.

**Checking the gear before a set.** `input_check.tscn` attaches every source to
a real `NoteRouter` and shows what comes out: which sources are listening, the
last note and where it came from, the MIDI device ids actually observed, and
how many duplicates the router merged. It prints each routed note to stdout as
well, so a session can be captured to a file and read back — which is how the
`InputEvent.device` question in §4.2 was finally answered.

**Capturing a real decay envelope.** `-- --log` on the tuner writes one CSV row
per hop to `user://dmj_onset_log.csv` (the absolute path is printed on start
and on quit):

```
godot --path godot-base res://games/dead_metal_jam/ui/tuner.tscn -- --log
```

Each row carries `rms`, the `trailing_rms` it was compared against, their
ratio, and the stable-hop count — the two quantities [constant
`ONSET_RMS_RATIO`] and [constant `ONSET_STABLE_HOPS`] actually gate on, next to
what the detector concluded. Play, quit, plot. This is what closes the standing
"tuned on synthetic attacks" risk in §13, and it is deliberately off by default
and absent from the round scene: a game should not be writing 43 rows a second
while somebody is playing it.

### 9.2 Manifest

```gdscript
game.id = "dead_metal_jam"
game.title = "Dead Metal Jam"
game.tagline = "Play the note. Kill the robot."
game.gameplay_scene_path = "res://games/dead_metal_jam/gameplay.tscn"
game.menu_order = 2
game.supports_multiplayer = false          # one instrument, one player
game.supports_cpu_opponent = false
game.control_style = GameManifest.CONTROL_STYLE_TARGETS
game.share_art_scene_path = "res://games/dead_metal_jam/ui/share_art.tscn"
game.tunables = DeadMetalJamOptions.TUNABLES
game.copy = { ... }                        # mode-select and instructions wording
game.achievements = { ... }                # see 9.6
```

`supports_multiplayer = false` collapses the framework's `mode_select` to the
single-player path automatically — no framework edit, and it removes the
collision with Demo/Rhythm/Jam entirely. The lives pool is per-player, so
declaring single-player also means the pool is simply "the player's".

### 9.3 `GameShell` hook map

| Hook | What Dead Metal Jam does |
| --- | --- |
| `game_id()` | Returns `"dead_metal_jam"`. |
| `_prepare_session()` | Build `NoteRouter`, probe for MIDI devices and audio input, load the chart. |
| `_build_playfield()` | Spawn the rail stage, lane markers and bot pool under `%Playfield`. |
| `_begin_first_round()` | **Show the Soundcheck overlay**; call `_start_round()` only when it is dismissed. This is the documented hook for custom opening timing, so mode selection and calibration need no framework screen. |
| `_load_round_settings()` | `super()` — which reads the round mode, the lives pool and the handicaps — then the chart, hit-window and latency tunables. |
| `_reset_round_state()` | Reset combo, chart cursor and rail position; clear the bot pool. **Not lives** — the shell rearms the pool itself. |
| `_activate_round()` | Start the chart clock and the rail. |
| `_update_round(delta, time_left)` | Advance the chart cursor, tick the rail, update bots, drain the mic buffer, poll the detector thread's result. |
| `_handle_gameplay_input(event)` | MIDI and keyboard events. `pause` is already consumed by the shell; skip routing when `_player_is_out(0)`. |
| `_finish_round()` | Stop the chart, stop the rail, close MIDI ports. |
| `_round_totals()` / `_player_stats(0)` | Score, hits, misses, accuracy, best combo. |
| `_describe_round_outcome()` | `TRACK CLEARED` / `WIPED OUT` / `SET FINISHED`. |
| `_round_highlight_summary()` | "Best combo ×8 · 94% pitch accuracy". |
| `_award_round_achievements()` | §9.6. |
| `_playfield_bounds()` | The rail viewport minus the readout strip. |
| `_on_game_setting_changed(key)` | React to hit-window / latency changes live. Round mode and the lives pool are the shell's, and only apply from the next round. |

### 9.4 Tunables and the `settings_menu` coupling

`AGENTS.md` documents that `settings_menu.tscn` hand-authors its tunable rows
and `_configure_game_tunables()` maps them to manifest keys — so a new game's
tunables need new rows. That is a real framework edit, and the way to keep it
small is to keep the tunable list small.

**One tunable goes to Settings → Game** (the thing a player changes between
sessions and expects to persist):

| Key | Range | Default |
| --- | --- | --- |
| `game/jam_hit_window` | 0.5 – 2.0 | 1.0 |

**Latency is not a settings row, and that is a deliberate reversal.** An
earlier draft listed `game/jam_input_latency_ms` here. It has shipped instead
in `dmj_profile.gd`, which writes `user://dead_metal_jam.cfg`. Latency is a
property of one machine's sound card and one player's instrument, not a
preference: it is measured rather than chosen, a wrong value is a bug rather
than a taste, and it must not travel with a settings profile that gets copied
to another computer. Putting it in a menu invites players to "tune" a number
they cannot perceive directly. Keeping it in a game-owned file also means the
framework's settings menu needs one new row for this game instead of two.

There is **no `game/jam_lives` tunable.** The earlier draft specified one; the
base now ships `game/starting_lives` (1–9) beside *Round mode*, shared by every
game, so a per-game duplicate would be a second dial for the same number. That
also drops this game's settings-menu footprint from three rows to one.

**Everything else lives in Soundcheck** — input source, MIDI device, audio
input device, noise floor, strict-octave toggle, mode. These are per-session
setup choices, they belong next to the live readout that proves they work, and
routing them through the settings menu would triple the framework edit for no
player benefit.

`dead_metal_jam_options.gd` is **constants-only** and must never reference an
autoload instance — headless `--script` runs compile `class_name` dependencies
before autoloads exist. `games/target_rush/target_rush_options.gd` is the
precedent to copy verbatim. The same rule binds `pitch_detector.gd`, which the
unit tests import directly: pure DSP, no `Settings`, no `AudioServer`.

### 9.5 Framework touchpoints — the honest list

The base is shared with every other DCS game, so each row here is a cost, and
the goal is to keep the list shrinking. Two entries the earlier draft carried
are already gone: the lives system, which the base now owns outright (§7), and
the third settings row that came with it.

| # | Touchpoint | Status |
| --- | --- | --- |
| 1 | `settings_menu.tscn` + `_configure_game_tunables()` — two new rows | **Required.** Documented existing coupling; down from three now that lives are shared. |
| 2 | `project.godot` — `audio/driver/enable_input=true` | **Done.** Data, not a code branch, and correct on every platform: it only asks the audio driver to open an input, which desktop, mobile and web all support. |
| 3 | Export presets — desktop for the jam; web, Android and iOS added later, with the platform record permission | **Required, later** (§4.7). Data. The base already exports to all three unchanged, so this adds presets rather than changing the project. |
| 4 | `project.godot` — `share/stats_urls/dead_metal_jam` | **Required.** Data. Keep the URL ≤ 42 UTF-8 bytes or the QR stops scanning. |
| 5 | `game_manifest.gd` + `game_catalog.gd` — read `games/<folder>/game.cfg` | **Recommended** (§9.9). ~35 lines total, game-agnostic, optional per game. This is the customisation surface for every future game, not a Dead Metal Jam feature. |
| 6 | `game_shell.gd` — public `finish_round_early()` | **Recommended** (§7.4). One-line wrapper over the existing `_end_round()`; names no game. |
| 7 | `game_shell.gd` — lives, round mode, damage feedback | **Already done.** Shipped in the base; consumed through `_lose_life()` / `_player_is_out()` / `_lives_rule_note()`. |
| 8 | `share_card_art.gd` | **Avoided** — using `share_art_scene_path` with a game-owned scene instead of adding a third hardcoded style. |
| 9 | `audio_manager.gd` | **Avoided** — the game synthesises its own SFX locally and plays them through the existing `play_sfx()` pool, rather than adding game-specific synthesis to the autoload the way Desk-Can-Saw did. |
| 10 | `default_bus_layout.tres` | **Avoided** — the Instrument bus is created at runtime (§4.3). |
| 11 | Web MIDI shim, touch onset source | **Avoided as a framework change** — both are `NoteSource` files inside `games/dead_metal_jam/input/` (§4.7). Reaching a new platform costs the base nothing. |
| 12 | `instructions_video_test.gd` — allow a game with no walkthrough clip | **Done.** The screen already supports this (`_setup_video()` hides the card and falls back to the single-column layout); only the test insisted every catalogued game ship footage, which made "add a game" mean "record a video first". The assertion now follows the code: declare a clip and it must be your own clip and poster, declare none and the card must give way to the text. Coverage went up, not down — two games must still ship clips. |
| 13 | `instructions.gd` — an `instructions_player_one_controls` copy key | **Done.** The solo control card hardcoded `"Mouse or arrow keys"`, so this game's instructions screen described controls it does not have. The key is optional and the old string is still the fallback, so the other two games render identically. A game that supplies its own line also suppresses the auto-appended controller line: the framework cannot know whether a pad does anything in a game it knows nothing about, and offering a gamepad to someone holding a guitar is worse than saying nothing. |
| 14 | `router.gd`, `game_shell.tscn`, `menu_screen.gd`, theme | **Untouched.** |

### 9.6 Achievements

Registered from the manifest; persistence, toasts and audio are automatic.

| ID | Title | Condition |
| --- | --- | --- |
| `jam_first_track` | Soundcheck | Finish any track in any mode. |
| `jam_perfect_section` | Tight | Clear a section with every kill at Perfect. |
| `jam_no_damage` | Untouched | Finish a track in Jam mode without letting a single bot fire. |
| `jam_mic_run` | Unplugged | Finish a Jam track on the microphone path. |
| `jam_combo_eight` | Shredder | Reach ×8 combo. |

No `GameUnlockRule` in MVP — Dead Metal Jam is available from the start.
Gating it behind Target Rush would be trivial to add later and needs no
framework change.

### 9.7 Accessibility (non-negotiable in this codebase)

- **Reduced motion** — rail movement and bot approach are *essential* movement
  and stay. Ambient parallax, background drift, particle trails, screen shake
  and the readout's idle pulse all freeze. Fades become opacity-only.
- **Intense visual effects off** — no damage vignette flash, no shake; damage
  is then signalled by the shell's `LIVES LEFT` readout, the hit-stop and an
  audio caption. All three come from the shell, so the game cannot get this
  wrong by forgetting to check the setting.
- **Audio captions** via `AudioManager.request_caption()` for: note detected,
  wrong note, life lost, wind-up warning, section cleared. The wind-up tick is
  a sound-only event and *must* be captioned.
- **Never colour alone** — every note is a letter first; the chart's per-note
  colours from `README.md` are decoration layered on the glyph.
- **Handicaps** — `Settings.gameplay_speed_scale()` (0.6–1.0) slows the rail
  and enemy approach; `Settings.target_size_scale()` (up to 1.4) widens timing
  windows; `Settings.extra_round_time()` is not meaningful here (round length
  is the chart) and is ignored, which is a legitimate per-game choice.
- The game is playable **fully deaf** on the MIDI path: every prompt is visual
  and MIDI needs no listening. Worth stating in the instructions copy.
- **Touch is a first-class input, not a port artefact.** Once mobile ships
  (§4.7), the note readout and Soundcheck must be usable at phone size and in
  portrait, and the touch onset source doubles as a motor-accessibility path on
  every platform: it needs one tap, not an instrument.

### 9.8 Testing

- `tests/game_shell_test.gd` picks the game up from the catalog automatically
  and drives a full round headlessly. **No per-game copy.** The input layer
  must survive zero devices (§4.1).
- `tests/lives_mode_test.gd` does the same for the lives round mode: it forces
  *Round mode → Lives*, then drives every catalogued game through a lives
  round. Dead Metal Jam inherits that coverage the moment it declares a
  manifest, and it fails if the game blocks headlessly, so the two constraints
  are the same constraint.
- `tests/pitch_detector_test.gd` — feed synthesised sine, sawtooth and
  square buffers at known frequencies across E2–C6 and assert the detected
  MIDI number, including deliberately detuned inputs to check `cents_off`.
  This is the test that matters most, and it is fully deterministic because
  the detector is pure. It also covers the streaming path — chunked, ragged,
  stereo and 48 kHz input all have to agree with one contiguous buffer — the
  noise floor and silence gates, onset counting, and it prints the measured
  cost per window so a regression in speed is visible even though speed is not
  asserted.
- `tests/playing_techniques_test.gd` — the onset rule against playing rather
  than tones: re-strikes on a ringing string, tremolo, damped runs,
  fingerpicking, hammer-ons, a note held for four seconds, and a string whose
  fundamental dies before its second harmonic. Then every one of them again
  over room tone that is **louder than the calibration**, which is the case
  that matters and the one a silent corpus cannot express. Split out of
  `pitch_detector_test.gd` because they answer different questions — that one
  asks "which note is this window?", this one asks "did a note just start?" —
  and because the two together exceeded the 1000-line lint limit.
- `tests/note_router_test.gd` — source merging, dedupe, latency offset,
  and the zero-source case.
- `tests/encounter_test.gd` — the game's rules, with no scene and no autoload:
  timing tiers and their widening under the accessibility handicap, the combo
  ladder, front-most matching, the noise / wrong-note split, wind-up to fire,
  clean versus dirty waves, track end, Rhythm mode's flag, and the practice
  track builder. Drones are stepped by hand at a fixed 1/60 timestep, so every
  timing assertion is deterministic rather than frame-rate dependent.
  **Verified to have teeth** by mutation: bypassing the timing window, sorting
  targets back-most first, and suppressing the fire transition each fail it
  loudly (3, 2 and 3 checks respectively).
- `tests/jam_chart_test.gd` — chart resources load, sections are ordered, beat
  times are monotonic.
- Run `godot --headless --path . --import` after adding the `class_name`
  scripts, or the global class cache will not know them.
- The tutorial clip is recorded through `tools/record_tutorials.ps1` with the
  keyboard note source driving the scripted demo player (§4.5).

### 9.9 Customising the base — `game.cfg`

The base project is shared, and more games are planned on it. The rule that
keeps it reusable is that **a game customises the base with data, never with
code**: `GameManifest` already carries identity, copy, achievements, tunables
and share media. What it does not carry is *look and sound* — the palette lives
in `scripts/studio_info.gd` as constants, and music is an `@export` per scene.

One small, deliberately narrow addition closes that gap.

**One optional file per game, three sections, nothing else.**

```ini
; games/dead_metal_jam/game.cfg
[colors]
ink    = "0b1013"   ; darkest background          (base: 0e1519)
deep   = "131c21"   ; panels                      (base: 162128)
slate  = "42525c"   ; secondary strokes           (base: 4a5a66)
sky    = "afddea"   ; friendly highlight          (base: afddea)
cream  = "f2f7f9"   ; primary text                (base: f2f7f9)
muted  = "93a6b0"   ; secondary text              (base: 93a6b0)
danger = "ff3b30"   ; enemies and damage only     (base: ff4964)

[assets]
icon       = "res://games/dead_metal_jam/assets/images/icon.svg"
background = "res://games/dead_metal_jam/assets/images/rail_backdrop.png"
share_art  = "res://games/dead_metal_jam/ui/share_art.tscn"

[music]
menu     = "res://games/dead_metal_jam/assets/audio/menu_loop.ogg"
gameplay = "res://games/dead_metal_jam/assets/audio/track_01.ogg"
results  = "res://games/dead_metal_jam/assets/audio/results.ogg"
```

**The contract**

- **Colours, assets and music. That is the whole surface.** No rules, no
  numbers, no layout, no copy — gameplay stays in GDScript, player-facing
  wording stays in `GameManifest.copy`, and numeric options stay in `tunables`.
  Anything a game wants beyond these three sections belongs in its own folder.
- **The colour keys mirror `StudioInfo` one-for-one**, plus `danger`, which is
  `GameShell.DANGER_COLOR`. No new vocabulary to learn, and the base file stays
  the documentation of what each colour means.
- **Every key is optional and every file is optional.** A missing key falls
  back to the base constant; a game with no `game.cfg` looks and sounds exactly
  like the base does today. That is what makes this safe to add — the two
  existing games are unaffected and untouched.
- **Read once, by the framework.** `GameCatalog` already loads
  `games/<folder>/game.gd`; it reads the sibling `game.cfg` with `ConfigFile`
  in the same pass and stores it on the manifest. `game.gd` never parses it.
- **Invalid values degrade, never crash.** An unparseable colour or a path that
  fails `ResourceLoader.exists()` is dropped with a `push_warning()` and the
  base value is used, so a typo costs a log line and the default look.

**The API**

```gdscript
# scripts/game_manifest.gd
var presentation := {}                       # filled by GameCatalog

func color(key: String, fallback: Color) -> Color
func asset(key: String, fallback := "") -> String
func music(key: String) -> String            # "" when unset
```

Screens already resolve `GameCatalog.current()`, so they ask
`manifest.color("danger", GameShell.DANGER_COLOR)` where they previously read
the constant directly. No screen learns a game name, and the `if game_id == …`
rule is untouched.

**Why this shape**

- *Why a `.cfg` and not more manifest fields?* Colours and music are what get
  changed and re-changed while a game is being tuned, often by whoever is not
  writing the GDScript. `ConfigFile` is already how this project persists
  `user://settings.cfg` and `user://achievements.cfg`, so it adds no new
  dependency and no new format.
- *Why not a per-game `Theme` resource?* `dcs_theme.tres` is shared and its
  overrides multiply per control type. A palette override is seven colours.
- *Why not allow more keys?* Because then the base has no shape, every new game
  re-litigates the menus, and "keep the base intact" stops meaning anything.

**When.** Not needed for the MVP spike — Dead Metal Jam can ship on the base
palette with its own scene-local colours. It becomes worth building the moment
a second game wants the same thing, which is the point at which it stops being
a feature for one game and starts being the framework's answer.

---

## 10. Chart data

`README.md` specifies a `.jam` package: a JSON chart, `.wav`/`.raw` audio, and
XML metadata. **Importing `.jam` files is stretch** (§11). MVP ships charts as
Godot `Resource` files whose shape mirrors the JSON one-to-one, so the stretch
importer is a straight field translation and not a redesign.

```gdscript
class_name JamChart extends Resource
    var title: String
    var artist: String
    var bpm: float
    var audio: AudioStream                 # the track
    var sections: Array[JamSection]

class_name JamSection extends Resource
    var name: String                       # "intro" / "chorus" / "bridge" — free text
    var wave_archetype: String             # which enemy mix to place
    var beats: Array[JamBeat]

class_name JamBeat extends Resource
    var time: float                        # seconds from track start
    var note: int                          # MIDI note number
    var duration: float                    # hit-window width, seconds
    var lane: int                          # 0-2, -1 = auto
    var enemy: String                      # roster key
```

Mapping from the `README.md` JSON:

| README JSON | MVP resource |
| --- | --- |
| `section.<name>.beats[].time` (`"0:10"`) | `JamBeat.time`, parsed to seconds |
| `beats[].duration` (window centred on `time`) | `JamBeat.duration`, same semantics |
| `beats[].chord.root` + `semitone` | `JamBeat.note` — the root only; chords are stretch |
| `beats[].chord.note` (¼ note etc.) | Folded into `duration` |
| `beats[].chord.position` (`'III'`, scale-relative) | **Stretch** — needs `scale.root`/`type` resolution |
| `scale.root` / `type` / `semitone` | **Stretch** — MVP charts use absolute notes |
| `notes.color`, `notes.text`, `borderRadius` | **Cut** — one fixed palette per game, declared in `game.cfg` (§9.9), not per note |
| `author.*`, XML metadata | **Cut** — MVP charts are built in |

**MVP content:** three hand-authored tracks, using audio generated the way the
base project already generates all of its own audio — procedurally at runtime,
or as small committed `.ogg` files. Three is enough to prove pacing and to give
the achievements something to bite on.

---

## 11. Cut or simplified for MVP

Explicitly out of scope **for the jam build**. Each line is a decision, not an
omission — and the *Simplified* and *Stretch* lists are deferrals, while *Cut*
means "not in this game".

### Cut

| Feature | Why |
| --- | --- |
| **`.jam` file import** (JSON + WAV + XML packaging) | The scope guidance flags custom files as optional, and it is the single largest source of complexity in the 2018 pitch: a JSON parser, a scale/chord resolver, an XML metadata reader, arbitrary audio loading, plus a file browser and validation UI. MVP uses `.tres` charts shaped to match (§10) so this becomes a translation layer later, not a rewrite. |
| **Player-imported songs / custom charts** | Follows from the above. Also implies chart validation, error reporting and a content-safety story that MVP should not carry. |
| **Polyphonic chord detection over a microphone** | Genuinely a research problem, not an engineering task. Chords stay MIDI-only, and even there they are stretch. |
| **Scale-relative chord notation** (`position: 'III'`) | Needs `scale.root`/`type`/`semitone` resolution. MVP charts write absolute notes. |
| **Per-note colour theming from the chart** | `README.md`'s `notes.color` map. One palette per game instead, declared in `game.cfg` (§9.9) — and the accessibility rule means colour was never carrying the meaning anyway. |
| **A game-owned lives system** | The base now ships lives as a shared round mode (§7). Rebuilding one here would mean two pools, two HUD readouts and a settings dial that fights *Settings → Game → Round mode*. Deleted from this design, not deferred. |
| **Author metadata, avatars, MusicBrainz XML** | Only meaningful once charts are shareable. |
| **Local multiplayer and CPU opponent** | One instrument, one player. `supports_multiplayer = false`. |
| **Real 3D rail** | 2.5D in the existing 2D playfield keeps `gl_compatibility`, the `%Playfield` contract and the procedural-art approach the repo already uses — and it is what keeps the web and mobile targets cheap. |
| **GDExtension / native pitch detector** | Pure GDScript first. Revisit only if profiling on the target machines actually fails. |
| **Boss fight (The Conductor)** | MVP ends on a heavy final wave. A multi-phase boss needs a tuned move set the MVP will not have data for. |
| **Silence Sentry, Detonator** | Two enemies whose rules are inversions of the core verb. Worth building, but only after the core verb is proven fun. |
| **Life regeneration** | Needs difficulty data that does not exist yet, and a matching generic `_gain_life()` in the shell. |

### Simplified

| Feature | Simplification |
| --- | --- |
| **Octave matching** | Pitch class only by default; strict-octave is an opt-in toggle. Sidesteps the most common detection failure. |
| **Demo mode's "stop time"** | Freezes the rail, wind-up timers and chart cursor only — not a global `Engine.time_scale` change, which would fight the shell's round timer and tweens. |
| **Lanes** | Fixed at three. |
| **Sections** | Free-text names with a wave archetype; no musical semantics attached. |
| **Chord support (MIDI)** | Deferred to stretch even on the exact path, so gameplay only ever reasons about one note at a time. |
| **MIDI device selection** | Degrades to "all connected devices" if `InputEvent.device` proves unreliable on 4.7. |
| **Wave authoring** | Archetype-driven generation from chart beats; per-bot hand placement supported but not the expected workflow. |
| **Content** | Three tracks. |
| **Platforms** | Desktop for the jam build. Web and mobile stay **in scope** and unblocked, but they are deferred rather than cut, and each is a source swap behind `NoteRouter` (§4.7). |

### Stretch, in priority order

1. Mobile build: touch onset source, record permission, portrait pass.
2. Web build: Web MIDI shim, gesture-gated audio unlock, thread-free detector
   budget.
3. Chords on the MIDI path (Plated Hulk becomes a chord enemy).
4. The Conductor boss.
5. Silence Sentry and Detonator.
6. `.jam` importer mapping the `README.md` JSON onto `JamChart`.
7. Scale-relative chord notation.
8. Life regeneration.
9. A `GameUnlockRule` gating Dead Metal Jam behind Target Rush.

The two platform items lead because they change *who can play the thing*, and
because a jam entry that is only a desktop download reaches a fraction of the
people a browser build does.

---

## 12. Build order

Each milestone is independently demonstrable, and the riskiest work is first.
**Milestones 1–8 are the jam build, on desktop.** 9 and 10 are the platform
ladder (§4.7) and start only once the game is proven fun on one platform —
porting something that is not yet fun is the classic way to lose a jam.

| # | Milestone | Proves |
| --- | --- | --- |
| 1 | ✅ **Done.** `PitchDetector` + its unit test, standalone. Synthesised buffers in, MIDI numbers out, across E2–C6. | **The entire concept.** If this is not reliable, everything downstream is worthless. Do not proceed past it. **Result: 0 note errors, ≤7 cents, 2.2 ms against a 23.2 ms budget — go.** |
| 2 | ✅ **Done.** All three sources and the `NoteRouter` that fronts them; `gameplay.gd` consumes `NoteEvent` and cannot tell them apart. Verified against real hardware: an Akai MPK mini Play mk3 played correct notes with real velocity (0.06–0.53) and reported `device = 0`, and the computer-keyboard piano played every key. `note_router_test.gd` covers the rest headlessly in 66 checks. | The input stack end to end, and it is already a usable tuner. |
| 3 | 🟡 **Built and self-verified, not yet met a microphone.** Noise-floor calibration ships as the soundcheck; `ui/calibration.tscn` measures the round trip against a noise metronome and stores the median in `user://dead_metal_jam.cfg`. An injected 80 ms offset was measured as 81.9 ms, and the analyser's own delay was measured at 34.6–49.6 ms with 14.9 ms of jitter — inside one hop. **What is still owed is one run with a real instrument.** | That the mic path can hit a ±60 ms window at all. |
| 4 | ✅ **Done.** Three lanes, the Rust Drone, front-most matching, timing tiers, the combo ladder and the practice track builder. The round length now comes from the track (§2) rather than a hardcoded 30 s. Autoplayed headlessly through the real scene on the keyboard source: **4 waves, 14 of 14 drones killed, 0 misses, TRACK CLEARED, 3645 points** — which is exactly 14 kills at ×1/×2 combo with the exact-source bonus plus four clean-wave bonuses, so the scoring arithmetic is confirmed end to end and not just unit-tested. | The framework integration, and that `game_shell_test.gd` still passes. |
| 5 | ✅ **Done.** Wind-up telegraph, `_lose_life()` on a drone that fires, `_player_is_out()` gating the router, and `TRACK CLEARED` via the inherited `_end_round()` (option 1 of §7.4). Verified in the real scene by a **pacifist run**: nobody plays, three drones fire, `lives` goes `3 → 0` and the round settles at 18.4 s against a 48 s timer. The win path and the loss path are therefore both exercised against the shipping scene. | The fail state — and that the game never branches on the round mode. |
| 6 | Rail advance, sections, three lanes, the full MVP roster. | Pacing. |
| 7 | Demo and Rhythm modes. | That the mode flags really are flags. |
| 8 | Three charts, achievements, share art, tutorial capture. | **Jam submission.** |
| 9 | Mobile: touch onset source, record permission, portrait pass over the readout and Soundcheck. | That a platform is a source swap, and that the game survives without a keyboard. |
| 10 | Web: Web MIDI shim, gesture-gated audio unlock, thread-free detector budget. | The widest reach, and that the abstraction held. |

---

## 13. Open risks

| Risk | Mitigation |
| --- | --- |
| ~~GDScript NSDF is too slow at 43 hops/sec~~ | **Retired in milestone 1.** Measured in Godot at 2.2 ms per window against a 23.2 ms budget — ~10× headroom, before any of the planned fallbacks. The 1024-sample fallback and the worker thread are both still available if a phone disagrees. |
| Mic latency makes the ±60 ms Perfect window unreachable | **Calibration ships (§4.6) and measures correctly against an injected offset**, so the mechanism is no longer the risk — the remaining unknown is what a real sound card reports. The detector's own contribution is measured and, more importantly, *constant* (14.9 ms of jitter, inside one hop), so it subtracts cleanly. If real hardware says otherwise, widen the tiers — they are tuning constants, not architecture. |
| Acoustic feedback (speakers → mic) triggers phantom notes | Capture bus is muted and never routed to Master (§4.3); Soundcheck measures the noise floor with the game's own music playing. |
| ~~`InputEvent.device` not populated for MIDI on 4.7~~ | **Retired in milestone 2.** Verified on Windows with Godot 4.7.2 and an Akai MPK mini Play mk3: `device = 0`, matching the index in `OS.get_connected_midi_inputs()`. A per-device picker is therefore possible. `MidiNoteSource.observed_devices()` keeps the check available on platforms that have not been tried, and the degrade-to-all-devices path is still there if one of them disagrees. |
| Distorted electric guitar defeats the detector | Harmonic-rich waveforms and fundamentals down to 5% strength are in the milestone-1 corpus and pass, but synthesis is not a real amp — this only clears once milestone 2 runs a live signal through it. Rhythm mode is the honest fallback and ships in MVP for exactly this reason. |
| ~~**Onsets were tuned on synthetic attacks**~~ | **This risk fired, twice.** It was on the register from milestone 1, phrased as "the thresholds have never been measured against a real decay envelope", and it cost two rounds of real bugs. First: notes went unheard, because the corpus was isolated plucks separated by silence and nothing tested a string struck again while ringing. Second, immediately after: the corpus was still *silent*, so nothing tested a room — and a rule built only from ratios invented notes on room tone and on decaying strings. Six faults are recorded in §4.4. **What replaces it**: ten playing-technique scenarios, each run again over room tone that is deliberately louder than the calibration, all in `playing_techniques_test.gd`; thresholds swept rather than picked; and the suite verified to *fail* against the previous detector before being trusted. Residual: the corpus is still synthesised. `OnsetLog` (`-- --log` on the tuner, §9.1) captures the real thing, and one recorded guitar decay should be checked against these scenarios. |
| **A silent test corpus is not a quiet one** | The second round of onset bugs existed because every scenario ran on digital zero. Silence is not a quiet room; it is a different problem, and an easier one. Both attack tests are ratios, and a ratio is scale-free, so noise drifting inside its own band clears any threshold a real note clears. The absolute floor is what separates them, and nothing on a silent background can measure whether it is set right. Any future signal-processing test must be run over noise, and over noise *louder than whatever was calibrated*, because that gap is where the failures live. |
| **The tuner is not the game, and it hid a bug for weeks** | A tuner draws every *voiced hop*; gameplay reacts only to *onsets*. Those are wildly different bars, and the tuner passes the easier one — a real guitar looked perfect in `ui/tuner.tscn` the whole time the onset rule was losing two thirds of re-strikes. Anything verified only in the tuner is unverified for gameplay. `ui/input_check.tscn` exists for this reason: it shows what the router actually emits, which is what the game sees. |
| **No export templates on the build machine** | Discovered deliberately early: `--export-release` fails with *no export template found* for 4.7.2, so **this project cannot currently produce a build at all**. It is a one-time ~1.4 GB download, not a code problem — but it is exactly the kind of thing that is fatal on deadline night and trivial a month before. Install and do one throwaway export before it matters. |
| Players cannot read notation | The game never shows notation — letters only. Demo mode exists as the on-ramp, and Mirror Units teach by ear. |
| **Jam deadline eats the game** | Milestone 1 is a hard gate and milestones 9–10 are outside the jam. If the schedule slips, the roster shrinks (§8.2 already marks three enemies stretch) and the chart count drops to one — the platform ladder is never the thing that gets rushed. |
| **No native Web MIDI in Godot** | Known and confirmed, not a surprise to be discovered late (§4.2). Web still has the mic and keyboard paths, so a browser build is playable *before* the shim exists; the shim only restores the exact path. |
| **Web audio needs a gesture and a secure context** | Soundcheck is already a mandatory press-through overlay, so the unlock has a natural home (§4.3). The failure mode to design against is a silent one: if the context never starts, the readout must say so rather than showing a flat meter. |
| **Mobile audio latency is far worse than desktop** | Calibration (§4.6) absorbs a constant offset, and the timing tiers are tuning constants. If a phone still cannot hold the Good window, that platform ships Rhythm mode first — which needs onsets, not pitch. |
| **Designing for three platforms slows the jam build** | It does not, as long as the two rules in §4.7 hold: no platform checks in gameplay, and nothing desktop-only becomes load-bearing. Both are cheap to obey now and expensive to retrofit. |

---

## 14. Document revisions

| Revision | Change |
| --- | --- |
| 11 | **It became a game** (§6, §8.3–8.5, §9.1, §9.8, §12 milestones 4 and 5). Milestones 4 and 5 are done: three lanes, the Rust Drone, front-most matching, timing tiers, the combo ladder, the wind-up telegraph, damage through `_lose_life()` and `TRACK CLEARED`. Four decisions are recorded. **Being early on the correct note is noise, not a wrong note** (§6) — the previous draft had two penalties and no rule for choosing between them, and the case that decides it is the player who identifies the right target and is fractionally ahead of the window; timing errors are already paid for by the tier ladder, and charging twice teaches hesitation. **Front-most and in-window are separate decisions in that order** (§8.3), because collapsing them lets a shot pass through a matching front drone that is fractionally early and kill the one behind it. **The round length comes from the track** (§2, as stated but not implemented) — a four-wave track runs 48 s against the shell's default 30 s timer, so `TRACK CLEARED` would almost never have fired; the track is now built in `_load_round_settings()`, which runs before the shell reads `round_duration`. And **the rules live outside `gameplay.gd`** (§9.1): `GameShell` uses autoload instances and so can never be named by a headless test, so `EncounterDirector`, `RustDrone` and `DmjTrackBuilder` touch no autoload and `encounter_test.gd` drives the shipping rules rather than a copy. Enemy art is deliberately **flat placeholder rectangles** (§8.4). One real bug is recorded because the tests caught it: `is_finished()` asked whether any drone existed rather than any *targetable* drone, so a corpse still fading out claimed the track was still running. Both round-end paths were then verified against the real scene rather than only unit-tested — an autoplay run clears 14 of 14 drones for 3645 points, and a pacifist run that never plays a note takes exactly three hits and ends at `lives 0`. |
| 10 | **Phantom notes fixed; the onset rule now requires an attack** (§4.4, §9.1, §9.8, §13). Reported symptom: with a real acoustic guitar the game emitted a stream of notes nobody played — high, quiet, low-confidence, arriving after the player stopped. Two further faults behind it. First, a *changed pitch* was on its own enough to fire an onset; that is false for a microphone, because a string sheds energy from its fundamental fastest and the estimator eventually starts naming the second harmonic instead. Second, the trailing average was left to converge after an onset and spent five hops reading like an ongoing attack, which held the hysteresis disarmed and made a fast run lose its second note. An absolute noise margin was added on top of the two ratio tests. A legato exception was written, measured, found to readmit the phantoms it was written beside, and removed — a hammer-on is a quiet attack, not an absent one. Playing-technique scenarios moved to `tests/playing_techniques_test.gd` and every one is now run a second time over room tone *louder than the calibration*. |
| 9 | **The onset rule was rebuilt against real playing** (§4.4, §13). Reported symptom: a live acoustic guitar that had worked in the tuner stopped registering notes in the game. It was not the new input stack — the router forwards faithfully — it was the onset rule, which had been tuned on isolated plucks separated by silence and had never been asked to handle the two things a player does constantly: striking a ringing string again, and changing note before the last one dies. Four faults, each now recorded with its cause: the threshold was set for notes starting from silence; the trailing average followed the signal fast enough to absorb the very transient it was the reference for; loudness was tested two hops late, after the transient had passed; and an attack fired before the ~46 ms analysis window had moved past the *previous* note, so one pluck became two onsets and the first carried the wrong note name. The rule now tests loudness against both the trailing average **and** a rolling trough, latches the verdict across the hops the pitch needs to settle, freezes the average during a transient, and refuses to fire until the window-straddle has passed. Thresholds were **swept against the whole scenario set**, not chosen. Eight playing techniques are now permanent tests, and the one that pins everything is the held note that must fire exactly once — a decaying string's own beating comes within a few percent of a genuine tremolo attack, so sensitivity and false-positive resistance had to be solved together. Two risk-register changes: the milestone-1 risk "onsets were tuned on synthetic attacks" is marked **fired**, since it predicted this failure precisely, and a new one replaces it — **the tuner is not the game**: it draws voiced hops, gameplay reacts to onsets, and a real instrument looked perfect in the tuner for weeks while two thirds of re-strikes were being dropped. |
| 8 | **The input stack is finished** (§4.1, §4.2, §4.5, §12 milestone 2). `NoteEvent`, `NoteSource`, all three sources and `NoteRouter` shipped; `gameplay.gd` now talks only to the router and cannot tell a guitar from a MIDI keyboard from the `A` key. Four decisions are recorded in §4.1: a failed source **stays attached** so it can say why, and losing the microphone no longer stalls a round because the other sources are independent; **latency compensation belongs to the source**, since the measured round trip is a fact about the microphone and applying it to MIDI would push those notes early by the width of the window they are judged against; **duplicates merge across sources but never within one**, because a re-struck string is the thing the game is listening for; and the router gained a **gate**, because before it only the microphone was quiet during the soundcheck and a MIDI note would have scored during a countdown the player could not see. Two risks retired against real hardware: `InputEvent.device` **is** populated (§4.2, §13 — an MPK mini reported `device = 0`), and MIDI velocity is usable data (0.06–0.53 in ordinary playing). The self-test tone moved from `T` to **`F2`**, because `T` is F♯ once a piano is on the keyboard (§4.5). Added `input_check.tscn` (§9.1), which is how the device question was answered and how a player checks their gear before a set. No new framework touchpoints: every file is game-owned. |
| 7 | **Latency calibration ships** (§4.6, §9.1, §12 milestone 3): `ui/calibration.tscn` plays a metronome, matches what the player plays against it, and stores the result in `user://dead_metal_jam.cfg`. Four decisions are recorded because three of them contradict what this document previously said. The metronome click is **broadband noise, not a tone** — a tonal click is a note, and the game would confidently measure its own audio. Notes are dated on the **audio clock, not the frame clock**, because a frame's worth of smear is most of a ±60 ms budget. The stored figure is the **median, not the mean** (§4.6 said mean), because eight beats is a small sample and one fumble moves a mean past the tolerance being established. And the detector's own delay is a **measured constant, not a formula**, because a window turns voiced at roughly a third full — two formula-derived versions were written and both failed the test against reality. Latency also **left the settings menu** (§9.4): it is measured, not preferred, and must not travel with a settings profile to a machine with a different sound card. One framework touchpoint was added (§9.5, row 13) — an `instructions_player_one_controls` key, because the solo control card hardcoded "Mouse or arrow keys" and this game's instructions screen was describing controls that do not exist. New risk (§13): **no export templates are installed**, so no build can currently be produced — found on purpose now rather than on deadline night. Also added `OnsetLog` (§9.1): `-- --log` on the tuner dumps per-hop RMS, the trailing average it was judged against and the stable-hop count, which is the measurement the "tuned on synthetic attacks" risk has been waiting for since milestone 1. |
| 6 | **The game is in the menu.** `game.gd`, `gameplay.gd` and the inherited `gameplay.tscn` landed, so Dead Metal Jam is a real catalogued game: it calls a note, listens, and scores hits and misses by pitch class (any octave counts). Audio plumbing was extracted to `MicCapture` and is now shared with a standalone tuner scene (§9.1), and a **self-test tone** was added because the machine this was built on has no working microphone — §4.3 gained the reason the obvious dead-mic guard does not work. Integration cost two framework findings: `_begin_first_round()` **must** start a round, so the soundcheck now holds the countdown instead of delaying the round (§4.6); and `instructions_video_test.gd` demanded a walkthrough clip from every game even though the screen already supports going without one, which made adding any game require recording a video first (§9.5, row 12). Milestones 2 and 4 are part-done (§12) — the framework half is finished, the content half is not. |
| 5 | Folder renamed `dead-metal-jam` → **`dead_metal_jam`** to match `slice_and_slash` and `target_rush`, and so the folder name matches the manifest id. All `res://` paths updated. Milestone 1 was then **executed in Godot 4.7.2 for the first time** rather than only in the Python reference port: the suite passes and the real cost is **2.2 ms per window, 10% of the hop budget** — better than the 4 ms the port predicted, so the accuracy and cost figures in §4.4 are now measurements of the shipping code. |
| 4 | **Milestone 1 built and measured**, and §4.4 rewritten to match what the code actually does rather than what was guessed. Three changes were forced by measurement: the lag range gained a semitone of headroom at each end (a guitar 30 cents flat was falling off the bottom), the peak threshold now compares *interpolated* peaks (raw comparison loses the top octave to its own harmonic), and **the octave-correction pass was removed** — it rescued nothing and broke A5/C6. DC removal became window-mean subtraction so the per-window entry point stays pure. Added the measured accuracy and cost table, marked the milestone done in §12, and retired the "too slow" risk in favour of a new one: onset thresholds are still synthetic. |
| 3 | Platform scope widened: **web and mobile are in scope, desktop ships first.** The first build is a proof of concept for a game jam, so "MVP" now means *the jam build*. Added §4.7, the platform ladder, with the per-platform input matrix and the two rules that keep the jam build from foreclosing the other targets; added the web Web-MIDI-shim and mobile touch-onset sources (§4.2, §4.5); documented the web and mobile microphone constraints (§4.3). "Web and mobile export" moved out of *Cut* and to the top of *Stretch*, with matching build-order milestones (9–10) and risk rows. |
| 2 | Rewritten against the base project as it now stands. **Lives are no longer game-owned** — `dcs_games` ships them as a shared round mode, so §7 became an integration spec (four calls) instead of a system spec, the `game/jam_lives` tunable and the game-owned lives strip were deleted, and the "no way to end a round early" friction point shrank to the `TRACK CLEARED` case (§7.4). Paths updated for the move to `godot-base/games/dead_metal_jam/`. Added §9.9, the `game.cfg` presentation config — the one sanctioned way to customise the base's colours, assets and music as more games arrive. |
| 1 | Initial design draft. |
