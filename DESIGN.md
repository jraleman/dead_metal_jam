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
> beside `triangle_rush` and `desk_can_saw`, discovered by `GameCatalog` at
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

The player moves automatically between combat rooms in a derelict industrial
world. Scrap robots deploy to firing positions and aim at the player. Each one
is branded with a **note**. Playing that note on a real instrument — a MIDI
controller, or any monophonic instrument through a microphone — fires an energy
shot at it. A robot left alive until its attack bar fills fires back.

There is no trigger button. The instrument *is* the gun.

### Locked pillars

| Pillar | Decision |
| --- | --- |
| Genre | On-rails shooter. Movement is automatic; the player only aims-by-pitch and times. |
| Reference points | *Time Crisis* / *House of the Dead* for pacing and staging; *SUPERHOT* for the look. |
| Weapon | A real instrument. Note identity matters — a C must be told apart from an E. |
| Presentation | **2.5D fake depth inside the existing 2D playfield.** Fixed firing bays supply scale and depth; no `Node3D`. Keeps `gl_compatibility` and the `%Playfield` contract intact. |
| Instrument target | **Any monophonic instrument, one note at a time** — guitar, bass, voice, wind, or one key at a time. Chords are stretch. |
| Platform | **Desktop first; web and mobile in scope.** The jam build ships Linux / Windows / macOS. Web and mobile follow, and the input layer is designed so reaching them is a source swap, not a rewrite (§4.7). The base's `gl_compatibility` renderer already exports to all three unchanged. |
| Modes | **All three from `README.md` ship in MVP:** Demo, Rhythm, Jam. |

### Look and tone

An industrial concert stage: blue-black steel, warm amber lamps, pale lettering
and a cool teal input signal. `ui/palette.gd` defines the shared accents; the manifest
carries them into the shared menus. Saturated hostile red remains reserved for
enemies, damage and mistakes. Gameplay artwork is drawn procedurally.

Standalone menus extend that palette with game-owned beveled steel plates,
condensed headings, a brushed-metal plaque and a subtle amplifier-grille backdrop.
Four short, non-repeating focus ticks and separate confirm/back cues share the
existing SFX controls. The optional skin, material, motion and sound-bank hooks
leave collection builds unchanged; the normal body font and semantic note/player
colors are retained. Reduced motion also stops menu decoration when changed live.

Three combat rooms have distinct machinery, cover props and firing bays,
without scrolling floor guides or a strike line. The opening and share card
reuse that scenery rather than drawing separate approximations. A responsive instrument
console shows the called note, real input level, the last heard note and scored
judgements; the upper HUD shows the track, completed waves and charge toward
the next combo multiplier. Its measured bounds keep the playfield clear even
when the console stacks, with stable space reserved for audio captions so they
never move the battlefield as they fade. Reduced motion suppresses
entry slides, camera motion and traveling orbs while retaining shot paths,
outcome markers and firing times. Effects switches also apply mid-round.
The concept-based drone artwork is described in section 8.4; encounter rules
remain unchanged by those earlier presentation passes. The subsequent arcade
revision below intentionally changes Jam's timing gate and enemy movement.

The dimensional effects pass adds beveled surfaces, feathered stage lighting,
bounded drifting dust, foreground parallax and animated turbine/reactor detail.
Kills combine a fast-growing, sustained bright fireball and additive glow with
a 0.9-second articulated breakup: heads, limbs and armor plates travel and spin
independently before fading. Perspective-scaled debris and smoke linger behind
them; floor shockwaves use a captured foot position and render underneath the
actors. Wreckage does not delay waves or reserve firing bays beyond the original
short exit interval. Results leave time for the final breakup, while reduced
motion keeps a short static fade. Impact labels stay above the debris. This is
still procedural 2D
drawing, not a `Node3D` scene or a renderer-dependent post-process. Decorative
motion follows the encounter clock and accessibility switches; shot feedback
retains its separate presentation clock without changing judgement or damage.

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
        │  │   → matches the most urgent valid bot?        │  │
        │  │        yes → visible hit, timing bonus, combo │  │
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
diagram above shows this game's default *Lives* round mode; under optional *Timer*
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

All three ship in MVP. They use one code path with mode flags, not three
games.

| Mode | Pitch matters | Timing matters | Damage | Purpose |
| --- | --- | --- | --- | --- |
| **Demo** | Yes | Yes, but forgiving | **No** | Tutorial and metronome practice. **Time stops until the player hits the beat.** The rail, enemy wind-ups and the chart clock all pause at each beat mark and resume the instant a correct note lands. Nobody can die; the run always finishes. |
| **Rhythm** | **No** — any note counts | Yes, strict | Yes | Onset-only. Kills the pitch-detection dependency entirely, so it is the honest fallback for a noisy room, an unusual instrument, or a player who just wants to hit things. Also the drummer's mode. |
| **Jam** | Yes | Bonuses, not a hit gate | Yes | Arcade firefights. Correct notes hit any time before a robot fires; shots close to the beat earn more points. |

**Implementation note.** Demo's "stop time" is scoped deliberately: it freezes
the rail transform, enemy wind-up timers and the chart cursor. It is *not* a
global `Engine.time_scale` change — that would fight `GameShell`'s round timer,
its tweens and the pause overlay.

As built it is narrower still, and better for it: `advance()` computes one
local `step`, which is `0.0` while the world is held and `delta` otherwise, and
*everything* downstream reads that one variable. The room, entry poses, the
wind-up fuses and the chart cursor therefore stop and start together and cannot
drift apart — which a per-system freeze flag would not have guaranteed.

Confirmed-shot feedback has its own short presentation clock so a hit remains
visible even if Demo immediately holds the next beat. `DmjShotFx` inherits
normal scene pause, retains no enemy references, and never changes scoring
or damage.

The one thing that does reach out of the director is the **round timer, which
`gameplay.gd` pauses while the world is held**. That is not a contradiction of
the paragraph above: the timer is paused through its own `paused` property, not
by scaling time globally. It is necessary because "the run always finishes"
would otherwise be false for exactly the player Demo exists for — a learner who
takes ten seconds over a note would watch the clock eat the song they are
trying to learn. Measured over a full track (§12), the world held for 35.1 s
and the round clock lost none of it.

**Damage** in the table above means "this mode reports mistakes to the shell".
What a mistake actually costs is the player's *round mode*, not the game's
choice (§7). Demo is the exception that stays game-owned: it never reports a
mistake at all, so nobody can die in Demo under either round mode.

**Mode selection**, as designed, happened in the game-owned **Soundcheck**
overlay, not the framework's `mode_select` screen. `mode_select` in `dcs_games`
means *player count*, which is a different axis; overloading it would require
framework edits. See §9.

**As built, mode is a Settings → Game choice row** (`game/dmj_mode`, §9.4), and
the Soundcheck overlay does not exist. It was dropped in revision 6, when
`_begin_first_round()` turned out to be obliged to *start a round* — leaving no
pre-round moment for an overlay to occupy. Soundcheck survives as an in-round
hold instead, which is the right shape for tuning up but the wrong shape for
picking a mode. The other setting §9.4 originally assigned to Soundcheck, the
input source, had already shipped the same way as `game/dmj_note_source`, so
mode follows shipped precedent rather than inventing a second pattern.

The cost of that move is honest and worth writing down: mode is now a decision
made *before* the round rather than during it, so a player who wants to try
Demo mid-song has to leave and come back. That is the trade for not building a
pre-round screen the shell has no room for.

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
  every note look sustained to any rule that measures how long a note was held.
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
- The most urgent matching target is selected in Jam: the smallest remaining
  firing time, not distance walked. The main readout follows that threat.
- Correct note: a pitch-colored energy tracer and orb connect the player's amplifier
  emitter to the actual struck plate. Sparks and `DOWN` / `PLATE HIT` distinguish
  a kill from damage to armor.
- Wrong note: a muted tracer hits the side scenery and reads `MISS`, with the
  existing dissonant sting and combo reset.
  Wrong notes must feel *inert*, not punishing-loud, or players stop
  experimenting.
- Attack telegraph: a segmented filling bar shows the complete attack,
  including the musical lead-in. There is no numeric FIRE countdown.
  The target ring closes around the bonus beat and the HUD flashes `ON BEAT`.
  Demo suppresses attack bars
  and labels the circuit protected.
- Damage: the shell reacts first — `_lose_life()` already flashes its danger
  colour, shakes the screen, announces `LAST LIFE!` / `OUT!` and captions it,
  honouring the intense-visual-effects and reduced-motion settings. The game
  adds the arm-cannon muzzle flash, a red shot to the player's emitter, and a
  ~120 ms hit-stop.
- Every played note flares the light pool at the camera's feet (§8.1) — hard on
  a hit, faint on a miss, scaled by how hard the note was struck. It is the
  game's muzzle flash, and it is drawn *behind* the bots on purpose so that
  lighting up never costs the player the thing they are aiming at.

Shots use **hitscan resolution**: the note judgement or enemy fire event is
authoritative immediately. The full tracer and impact marker appear at once;
a short traveling energy head reinforces its direction. There is no second
collision/damage system, delayed hit callback, or chance of a missed visual
projectile scoring. Static paths and markers remain under reduced motion or
disabled effects. A round with a final tracer settles for 0.32 seconds before
results cover the field; input is disabled during this interval, replay clears
all effects, and a lethal shot cannot become a track-clear victory.

Hit reactions pivot around planted feet, and auto-aim uses the resulting art
transform. Confirmed reactions finish on a presentation clock even when Demo
holds the next beat. Kills collapse the chassis with an energy burst, metal
debris and smoke; plate hits shed sparks and fragments. The weapon recoils and
ejects casings. `DmjShotFx` caps both shot records and particles (48 and 256);
neither can change scoring or damage. Disabling effects or enabling reduced
motion clears particles and suppresses recoil/flash while retaining outcomes.

`DmjPalette.NOTE_COLORS` is the shared twelve-pitch palette. It colors plates,
targeting brackets, HUD notes, the input meter and shots consistently across
octaves. The HUD includes a color key; note letters and plate-order numbers
remain visible, with contrasting ink rather than color-only prompts.

### 5.3 HUD additions

`GameShell`'s HUD already provides score, streak, callout, hint, announcement
labels and the TimerCard — which reads `SECONDS LEFT` or `LIVES LEFT` depending
on the round mode (§7) — all reused as-is. The game adds its widgets **into the
shell's own HUD column** inside its inherited scene — no framework scene is
modified:

- **Note readout** (§5.1), the last child of the HUD's `Layout` VBox, so it
  sits at the foot of the column.
- **Progress banner** — `WAVE 3 / 5` — left-aligned over the shell's `Callout`
  row.
- **Combo multiplier**, right-aligned over the same row.

**The banner does not name the section, and that is deliberate.** It used to
read `CHORUS · 3/5`, taken from the chart's own section names. Those were cut
from every player-facing surface: CHORUS and BRIDGE are *authoring*
vocabulary — how the person writing the chart talks about the song — and they
tell somebody holding a guitar nothing they can act on. The names stay in the
chart (§10), where they are still worth having; they simply stop being shown.

What the advance says instead is encouragement — "Keep on going!", "Nice! Keep
it up!" — with "Last stretch!" reserved for the final advance, where "keep
going" is the wrong thing to say to somebody one wave from the end. The line is
chosen by how far through the track the player is rather than at random, so it
always suits the moment and two runs of the same track read the same way.

It lands on three surfaces at once, because they answer different questions:
the banner holds **where you are** (`WAVE 3 / 5`), the centre-screen flash and
the status line carry **the encouragement**, and the screen-reader caption
carries both. The flash is skipped on the opening advance, where the shell has
just said `GO!` and two banners in the same frame read as a glitch rather than
a cue.

**The status line has to be held, not set once.** `_update_target_readout()`
rewrites it every frame, so an advance line written once at the start of the
advance is overwritten before it is ever drawn — which is exactly what happened
to the first version of this, and what a real-run capture caught. The line is
kept in `_advance_line_now` for as long as the advance lasts and cleared when
the next wave starts.

The banner now reads the same whether the track is a charted song or the
practice ramp, so the HUD does not change shape when the player switches
tracks. An earlier pass had the practice builder name each wave `"WAVE 3"`,
which rendered as `WAVE 3 · 3/5` — the same number twice, once as a name the
ramp had invented for itself. The name is a property of the *chart*, and a
generated ramp does not have one.

**They are laid out by containers, never pinned to the viewport.** An earlier
draft anchored the readout to the bottom of the screen with a hardcoded height,
and it collided with two things the shell draws in the same place: the audio
caption (§9.7), which is two lines tall for a long caption, and the hint panel.
Absolute coordinates cannot be made safe against a widget whose height depends
on its text. Being a container child makes the overlap structurally impossible
instead. The progress and combo labels are full-rect children of `Callout` for
the same reason: they track that row rather than guessing its Y.

The shell's hint panel is hidden here (`_build_playfield()`) rather than
written to. The readout already carries the current instruction, and two
permanent instruction strips is one too many.
`READOUT_CLEARANCE` is then derived from the readout's own height rather than
measured against the screen, so `_playfield_bounds()` (§9.3) stops the rail
half a drone body short of the panel at any viewport size.

The central card becomes an **amplifier tube bank** in Lives rounds. One lit
filament means one life; spent tubes have broken wires, cracked glass, and an
X, so the count does not depend on colour. A numeric `3 / 3 LIVES` readout sits
above the rack. The last tube gets a slow glow and `LAST TUBE` warning; zero
reads `POWER CUT`. Demo instead labels the circuit protected. Reduced motion
or disabled effects makes the rack static.

This replaces the visible countdown card and progress bar rather than adding
a second health meter. `DmjLifeRack` only renders the shell's authoritative
pool, updated through `_update_lives()`; it never charges or restores lives.
Timer rounds retain the original countdown. The rack fits the existing top
bar, including the full configurable nine-tube pool.

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
| Outside the beat window | — | 25-point snap hit in Jam; miss in Rhythm/Demo |

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
- **Score floor** — the running score is clamped at **0**. The wrong-note
  penalty exists to make aiming carelessly cost something, not to open a hole a
  beginner has to climb out of before their first kill counts. A player who
  opens a round by fumbling five notes should read `0`, not `-125`, and be able
  to score from the next note onward.

#### Which of those two a note gets — decided in the build

The two penalties above look like one rule until you implement them, because a
played note can miss in three different ways, and only one of them deserves the
score hit:

| Situation | Judgement | Why |
| --- | --- | --- |
| No drone is on screen at all | **Noise** — combo only | Between waves. Warming up, tuning and noodling have to be free, or the game punishes practising. |
| Drones are up, the pitch matches none of them | **Wrong note** — −25, combo reset | The player aimed and picked the wrong target. This is the mistake the penalty exists for. |
| Drones are up, the pitch matches one, but it is not inside a timing window yet | **Noise** — combo only | The player identified the right target and was merely early. Charging points for that teaches hesitation, which is the opposite of what a rhythm game wants. |

The third row describes the strict practice modes. In arcade Jam, any matching
target that has not fired takes the shot: an out-of-window note earns the snap
tier rather than becoming noise. The tier ladder still rewards timing without
making a player watch an unavoidable shot after narrowly missing a beat.

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
| **Timer** | The countdown reaches zero. | Points and combo only. |
| **Lives** (Dead Metal Jam default) | Every player's pool is empty. There is no countdown at all. | One life, plus points and combo. |

It is stored as `game/round_mode` + `game/starting_lives` (1–9, default 3) and
read once per round in `_load_round_settings()`, so switching modes shapes the
*next* round rather than the live one. Dead Metal Jam therefore ships **no
lives system of its own** — the earlier draft of this document specified one,
and it is now deleted rather than duplicated.

The manifest opts into `default_lives_mode`, which the shared settings and
shell resolve for this game only. Other manifests keep Timer by default.
A saved round-mode choice wins, including existing Timer preferences.
An unset preference stays unset when saving unrelated options; resetting
settings restores each game's default rather than writing a shared Timer
override.

### 7.1 What Dead Metal Jam does

Four rules calls, plus a presentation hook for the amplifier rack.

| Call | When |
| --- | --- |
| `_lose_life(0)` | A bot completes its wind-up un-killed and fires. |
| `_player_is_out(0)` | Checked before a note is routed to a target, so an eliminated player stops scoring. |
| `_lives_rule_note()` | Appended to the HUD hint: each firing robot burns one tube (1 life). |
| `_round_length_phrase()` | Used in results copy instead of naming the chart length. |
| `_update_lives()` | Calls the shell first, then presents its pool as amplifier tubes. |

A bot that fires also resets the combo and leaves the field — it does not
linger and chain-hit. Both of those are game rules, and they stay game-owned.

**Damage rules never branch on the round mode.** `_lose_life()` and
`_player_is_out()` no-op under the countdown and `_lives_rule_note()` returns
an empty string, so all four calls above are unconditional. Under *Timer*, a
bot that fires costs points and the combo and the run is bounded by the chart:
Dead Metal Jam is a score-attack track run. Under *Lives*, the same bot costs a
life and the track can end early. One code path, two shapes — the same
arrangement Triangle Rush (a wrong key) and Desk-Can-Saw (an escaped can) already
use.

### 7.2 What the shell already provides

Free, and not to be re-implemented:

- The TimerCard's shared values track the pool. Dead Metal Jam presents those
  values through its tube bank and hides the generic number/progress widgets;
  other games retain the shared display.
- The shell's danger scale remains available through
  `_lives_urgency_seconds()`. The rack adds a restrained last-tube glow and
  static warning text without changing the life count or the danger rules.
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
still an early end the shell has no public verb for. It must settle the round
in either mode, without waiting for the timer or exhausting the lives pool.

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

Three firing columns, with additional back-row slots when a chart overlaps
enemies in one column. `DmjArenaLayout` is the single placement definition
used by actors, scenery, and share artwork. Drones make a short lateral entry,
then hold their position and apparent size through aiming and firing. Reduced
motion skips the lateral movement.

The chart's existing `approach` field now means **lead-in to the bonus beat**,
not physical travel. `approach + windup` is the attack deadline. Crossing a
phase boundary consumes frame overshoot, so the attack bar and the
fire event agree even at a low frame rate. Breaking a plate moves its bonus
beat, not the firing deadline.

`DmjRail` retains its integration API but now renders industrial combat rooms:
Loading Bay, Turbine Hall, and Reactor Deck. Machinery, fixed floor geometry,
doors, cables and cargo replace scrolling rails, repeating cross-ties and the
yellow strike line. Inter-wave transitions change the room; nothing scrolls
under a stationary firefight.

The shared floor inset still leaves architectural headroom. Camera breathing
is small and uses the encounter clock, so Demo freezes it; reduced motion
removes it. The same room renderer is used by the opening and share artwork.
A compact amplifier emitter occupies the now-clear foreground and gives
player shots a visible origin without covering the enemies' note plates.

### 8.2 Roster

| Enemy | Demand | Teaches | MVP |
| --- | --- | --- | --- |
| **Rusty Clanky** | One note, one hit. | The core verb. | ✅ Built |
| **Plated Knuckle** | Exactly three notes in order, one plate per hit. Wrong notes reset the armor. | Phrasing; reading ahead. | ✅ Built |
| **Silencer Sentry** | Fires if *any* note is played while it crosses. Killed by waiting it out. | Restraint; makes the noise penalty legible as a rule. | Stretch |
| **The Conductor** (boss) | Phases, each demanding a riff drawn from the chart. | Payoff. | Stretch — MVP ends on a heavy wave, not a boss. |

Four enemies, and each one asks for something the others do not: one note,
several notes in order, *no* notes, and a whole riff. That is the whole span of
what an instrument can be asked for, which is why the list is this short — an
enemy that does not add a new demand only adds art.

**As built:** the two shipped enemies share a base, `JamBot`, which owns
everything that is true of *any* bot — lane, approach, wind-up, firing, death,
the note glyph, the depth fake. A subclass supplies only three things: what it
demands (`demand_size`), what a correct note does to it (`strike`), and how it
is drawn. Character drawings now live separately under `enemies/art/`, so the
same art can be shown without constructing a combat actor.

That split is what let the roster grow without the matching rule learning a
second shape. `EncounterDirector.resolve_note()` calls `strike()` and asks
afterwards whether the bot is still targetable; it never checks what kind of
bot it hit. A Silencer Sentry — whose correct answer is *no note* — is a third
subclass and no change at all to the rules, which is the test this refactor
was actually for.

### 8.3 Note-to-shooting mapping

- In Jam, a played pitch class resolves against **the matching bot that will
  shoot soonest**. There is no mouse aiming requirement.
- Ambiguity is a design tool: two bots on the same note in one wave means repeated
  notes kill them in firing order. This is a feature, and charts
  should use it for tremolo-picked runs.
- In **Rhythm mode** every bot accepts any note; the front-most valid target is
  simply the front-most bot.
- Multi-note enemies (Plated Knuckle) hold an internal cursor and reset it on a
  wrong note in the sequence.

**As built:** `arcade_shots` is enabled for Jam only. A matching live target is
selected by firing urgency and always takes a hit; timing determines its
score. Rhythm and Demo retain the existing ordered, in-window selection so
their practice behavior and held-beat targeting remain intact. The hit's
position is captured before `strike()` changes a plate cursor, so the tracer
lands on the plate that actually took the note.

**As built, phrases:** a Plated Knuckle's plates are each their own beat.
Breaking one pushes the next bonus beat out by one plate interval. Jam permits
a fast sequence of correct shots, but playing the intended rhythm scores more;
Rhythm and Demo still gate each plate to its timing window.

A wrong note resets the sequence, with two corrections the first draft did not
have. **It re-bases the beat rather than only the cursor.** Resetting a cursor
alone leaves the bot's next beat already in the past, losing its bonus and
making it permanently unhittable in the strict practice modes;
the phrase now restarts one plate interval from *now*, so what a mistake costs
is the wind-up time it burned. And **only a phrase actually in progress can be
broken** — a bot still on its first plate has nothing to lose, and charging it
anyway would make every stray note on the field a penalty against enemies the
player has not engaged yet.

### 8.4 Art

All four sketches in `assets/drones/` have procedural 2D character drawings
under `enemies/art/`. They keep the concepts' distinctive silhouettes: Rusty
Clanky's antennae, crooked grin and rattling limbs; Plated Knuckle's crest,
heavy shoulders and diamond plates; Silencer Sentry's rotor and stitched
grille; and The Conductor's top hat, amplifier body, wheels and baton.

`DmjDroneArt` owns the shared drawing helpers, readable note plates, targeting
brackets and charge bar. `JamBot` supplies the current notes, phrase cursor,
charge and pose time; no drawing owns a gameplay clock. Gaits, rotor motion
and conducting gestures therefore freeze under reduced motion, and live
actors also hold their poses during Demo's stop-time. Feet and ground shadows
are anchored to their firing bays. The larger
silhouettes scale down in short playfields, with shadow/bracket clearance
reserved above the HUD. Live Rusty/Plated poses raise an arm-mounted emitter;
their attack bars and bonus rings reuse the same art layer.

Plated Knuckle lights only its current note plate. Future plates are muted
and numbered, while completed plates are visibly cracked. All three plates
are used: shorter authored phrases cycle, and longer phrases use their first
three notes. The displayed notes come
from the same sequence cursor that scoring uses, not letters baked into art.

**This is an art-only roster expansion.** Rusty Clanky and Plated Knuckle
use their new drawings in encounters and the opening/share artwork.
Silencer Sentry and The Conductor remain visual previews: no new roster keys,
chart changes, silence rules or boss phases are enabled. Run
`ui/drone_gallery.tscn` to inspect all four, cycle notes/plates, toggle charge
poses and pause motion. The gallery contains drawing nodes, not enemies.

**Distance also costs contrast.** `_place()` tints a bot toward the corridor's
dust colour by how far away it is, which is what makes the walls and the floor
look like they contain air. The tint is deliberately partial: a bot's glyph is
the note the player is being asked for, so fogging it all the way into the dust
would be asking the question in a colour nobody can read. It stays subtle at
the fixed firing depths and never touches alpha — transparency is reserved
for the death and muzzle fades, which mean
something else.

Enemy apparent size now comes from the firing position rather than elapsed
lead-in time. Notes are timed against the target ring and HUD, not a body
walking toward a line.

### 8.5 Wave authoring

Waves come from the chart (§10). A section names its wave archetype and the
generator places bots on lanes at chart beats. Handwritten per-bot placement is
supported but expected to be rare — the point is that a chart is a *song*, and
the enemies fall out of it.

**As built:** an archetype is *pacing*, and only pacing — the bonus-beat lead-in,
how long a bot charges before it fires, and how much repositioning time precedes
the section. Four ship: `walk_in` (the opener, the longest read in the game),
`march` (the default), `press` (a shorter read arrived at through a shorter
rail, so it lands as a step up in tempo) and `hold` (slow and heavy, preceded
by real rail — the bridge is where the player gets their breath back).

It is deliberately a small closed set. Per-beat tuning is how a chart format
turns into a scripting language, and an unknown archetype falls back to the
default rather than failing: a typo in one section name should not be a track
that refuses to load on jam night.

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
    jam_chart.gd               # ✅ class_name JamChart — the section list, and the compiler
    jam_section.gd             # ✅ class_name JamSection — a named stretch, one wave
    jam_beat.gd                # ✅ class_name JamBeat — one demand
    charts/track_01.tres       # ✅ "Demo", 140 BPM, five sections
    charts/track_02.tres       # ✅ "Scrapyard Stomp", 100 BPM, five sections
    charts/track_03.tres       # ✅ "Overdrive", 168 BPM, six sections
  encounter/
    encounter_director.gd      # ✅ class_name EncounterDirector — lanes, waves, matching, tiers
    track_builder.gd           # ✅ class_name DmjTrackBuilder — practice waves; the chart's seam
    rail.gd                    # ✅ class_name DmjRail — the visible lanes and the advance
    track_bed.gd               # ✅ class_name DmjTrackBed — the round's song, owned by the round
  enemies/
    jam_bot.gd                 # ✅ class_name JamBot — everything true of any bot
    rusty_clanky.gd            # ✅ class_name RustyClanky — one note, one hit
    plated_knuckle.gd          # ✅ class_name PlatedKnuckle — a phrase, one plate per note
  ui/
    tuner.tscn + .gd           # ✅ standalone soundcheck / tuner, runnable on its own
    calibration.tscn + .gd     # ✅ standalone latency calibration, runnable on its own
    input_check.tscn + .gd     # ✅ standalone: every source at once, what the router emits
    note_readout.tscn + .gd
    soundcheck.tscn + .gd
    share_art.tscn + .gd       # ✅ game-owned share card art
  assets/
    demo.ogg                   # ✅ the round's music — the author's own song, trimmed to 3:05
    track_02.ogg               # ✅ "Scrapyard Stomp" — generated, see §10
    track_03.ogg               # ✅ "Overdrive" — generated, see §10
    intro-bg.ogg               # ✅ the intro slideshow's bed, trimmed to 0:20
    images/
  tools/
    make_tracks.py             # ✅ writes track_02/03: both the .ogg and the .tres
  tests/
    pitch_detector_test.gd     # ✅ DSP: which note is this window?
    playing_techniques_test.gd # ✅ the onset rule against real playing, in a real room
    latency_calibration_test.gd  # ✅ hardware-free: matching, timestamps, click silence
    note_router_test.gd        # ✅ hardware-free: dedupe, offset, keyboard layout, MIDI
    encounter_test.gd          # ✅ the rules: matching, tiers, wind-up, phrases, sections
    mode_test.gd               # ✅ the three modes, and only them
    staging_test.gd            # ✅ the picture: the corridor, depth cues and the camera
    jam_chart_test.gd          # ✅ the compiler: arrivals, lanes, archetypes, all three songs
    intro_test.gd              # ✅ the slideshow: slides, skipping, captions, the bed
    round_music_test.gd        # ✅ the song stops when the world stops, and leaves when the scene does
```

**Why `encounter/` is not in `gameplay.gd`.** `gameplay.gd` extends
[`GameShell`], which uses autoload instances, so a headless `--script` test can
never name it (§9.8). Every rule that needs testing therefore lives in
`encounter/`, `enemies/` and `chart/`, which touch no autoload at all —
`gameplay.gd` is left holding only the wiring between the shell, the router and
the director. That is why `encounter_test.gd` and `jam_chart_test.gd` can drive
the real rules and the real shipped charts rather than a copy.

✅ marks what exists today. `gameplay.gd` / `gameplay.tscn` follow
`triangle_rush`; the folder name matches the manifest id, as in the other two
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
game.tutorial_video_path = "res://assets/video/tutorial_dead_metal_jam.ogv"
game.tutorial_poster_path = "res://assets/video/tutorial_dead_metal_jam_poster.webp"
game.tunables = DeadMetalJamOptions.TUNABLES
game.copy = { ... }                        # mode-select and instructions wording
game.achievements = { ... }                # see 9.6
```

The instructions clip is recorded from the actual arcade round in
`tools/tutorial_capture.gd`, with non-persistent three-life settings. It shows
early correct-note shots, beat-timed bonuses and one incoming shot burning a
life tube. The video and poster are regenerated alongside the gameplay art,
so the tutorial never teaches the retired walking/strike-line mechanic.

`supports_multiplayer = false` collapses the framework's `mode_select` to the
single-player path, and it removes the collision with Demo/Rhythm/Jam entirely.
The lives pool is per-player, so declaring single-player also means the pool is
simply "the player's".

This was originally written as "no framework edit", which was wrong: the
manifest flag existed but nothing read it, so the Multiplayer card was still
offered. The framework now honours it via `GameSession.multiplayer_offered()`,
and `main_menu.gd` skips `mode_select` outright for a solo-only game rather
than showing a screen with one card on it — Play goes straight to the
instructions, which is where confirming solo would have led anyway. Back from
the instructions returns to the main menu for these games, since there is no
mode screen to return to.

### 9.3 `GameShell` hook map

| Hook | What Dead Metal Jam does |
| --- | --- |
| `game_id()` | Returns `"dead_metal_jam"`. |
| `_prepare_session()` | Build `NoteRouter`, probe for MIDI devices and audio input, load the chart. |
| `_build_playfield()` | Build the encounter's combat room, firing bays and shot-feedback layer under `%Playfield`. |
| `_begin_first_round()` | Start the round — and hold it. This hook **must** call `_start_round()` (revision 6), so the Soundcheck overlay this table originally described is an *in-round* hold rather than a screen in front of one. Mode selection and the input source therefore ship as Settings rows instead (§3, §9.4), and neither needs a framework screen either way. |
| `_load_round_settings()` | `super()` — which reads the round mode, the lives pool and the handicaps — then the mode, chart, hit-window and latency tunables. `_director.apply_mode()` is called here, so a mode change takes effect on the next round and never mid-round. |
| `_reset_round_state()` | Reset combo, chart cursor and room position; clear drones, tracers and pending round endings. **Not lives** — the shell rearms the pool itself. |
| `_activate_round()` | Start the chart clock, the rail and the round's song — the song on the game's own [`DmjTrackBed`], not through `AudioManager` (§9.5 row 9). |
| `_update_round(delta, time_left)` | Advance the chart cursor, tick the rail, update bots, drain the mic buffer, poll the detector thread's result. |
| `_handle_gameplay_input(event)` | MIDI and keyboard events. `pause` is already consumed by the shell; skip routing when `_player_is_out(0)`. |
| `_end_round()` | Let a confirmed final impact remain visible for 0.32 s before the normal results path; stop the timer and further input during that interval. |
| `_finish_round()` | Stop the chart, stop the rail, close MIDI ports, and fade the song out over 0.6 s — long enough that the results panel does not read as a crash. Stopping the song on a *pause* or an *exit* is not a hook at all: [`DmjTrackBed`] answers the engine's own `NOTIFICATION_PAUSED` / `NOTIFICATION_EXIT_TREE` itself, because the overlay's own *Exit to main menu* hands the scene to `Router` without the round ever being told it is over (§9.5 row 9). |
| `_on_pause_closed()` | `super()`, then resume the song from the position the pause held it at, while a round is still running. The one part of the song's life the bed cannot handle for itself, and the reason it is safe: the overlay emits `closed` from `resume()` and from nowhere else, so exiting cannot reach it. |
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

**As built, the list is six**, and every one of them is either a handicap or a
choice about what to play — never a second copy of something the base already
owns:

| Key | Kind | Default | What it decides |
| --- | --- | --- | --- |
| `game/dmj_mode` | choice | Jam | Jam, Rhythm or Demo (§3). |
| `game/dmj_track` | choice | Demo song | One of the three charted songs, or the generated practice ramp. |
| `game/dmj_waves` | 1 – 12 | 4 | How long the practice ramp runs. The song ignores it — it brings its own sections. |
| `game/dmj_timing_window` | 0.6 – 2.0 | 1.0 | The hit window the table above meant. Multiplies into the base handicap rather than competing with it. |
| `game/dmj_wrong_note_penalty` | 0 – 100 | 25 | Points lost for naming a robot that is not there. Zero is a valid setting. |
| `game/dmj_note_source` | choice | Automatic | Which inputs are attached (§4.1). |

**Mode is the first row**, because it changes more about a round than the five
below it put together, and a player scanning the page should meet it first.

**`dmj_options.gd` repeats the mode numbers rather than importing
`EncounterDirector.Mode`.** That looks like duplication and is deliberate: the
options file has a no-dependency rule so headless tests can parse it without
pulling in a scene tree. `mode_test.gd` asserts the two agree, so the copy
cannot drift silently — which is a cheaper guarantee than the coupling would
have been.

**Track is a player-facing option and not a debug flag**, which is the decision
worth recording. The practice ramp was going to be deleted once the chart
landed. It survives because the two stage the *same rules* to different ends: a
song has an arc and stops, and a ramp does not, and somebody learning where E2
is on their instrument wants the one that does not stop. Both compile to the
same plain data, so keeping it costs one branch in `_build_track()` and nothing
downstream can tell them apart.

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
before autoloads exist. `games/triangle_rush/triangle_rush_options.gd` is the
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
| 8 | `share_card.gd` — honour `share_art_scene_path` | **Done.** The manifest field existed and *nothing read it*, so "use a game-owned art scene instead of adding a third hardcoded style" was not actually a way out — it was a field that did nothing. `_install_game_art()` now swaps `%ActionArt` for the manifest's scene, and swaps it back when the card is reconfigured for a game that has none. ~30 lines, names no game, and it is the difference between the field being a plan and being a feature. The swap must set `owner` before `unique_name_in_owner` or `%ActionArt` stops resolving; `share_card_test.gd` covers both the install and the revert. |
| 9 | `audio_manager.gd` | **Avoided** — the game synthesises its own SFX locally and plays them through the existing `play_sfx()` pool, rather than adding game-specific synthesis to the autoload the way Desk-Can-Saw did. Since revision 20 the *music* is game-owned too, for a different reason: the manager's players run with `PROCESS_MODE_ALWAYS` and outlive the scene that started them, which is right for a menu bed and wrong for a round's song, and `stop_music()` no-ops while a crossfade is in flight. Fixing that in the autoload would change what every other game's music does; a node in this game's scene ([`DmjTrackBed`]) changes nothing outside it. |
| 10 | `default_bus_layout.tres` | **Avoided** — the Instrument bus is created at runtime (§4.3). |
| 11 | Web MIDI shim, touch onset source | **Avoided as a framework change** — both are `NoteSource` files inside `games/dead_metal_jam/input/` (§4.7). Reaching a new platform costs the base nothing. |
| 12 | `instructions_video_test.gd` — allow a game with no walkthrough clip | **Done.** The screen already supports this (`_setup_video()` hides the card and falls back to the single-column layout); only the test insisted every catalogued game ship footage, which made "add a game" mean "record a video first". The assertion now follows the code: declare a clip and it must be your own clip and poster, declare none and the card must give way to the text. Coverage went up, not down — two games must still ship clips. |
| 13 | `instructions.gd` — an `instructions_player_one_controls` copy key | **Done.** The solo control card hardcoded `"Mouse or arrow keys"`, so this game's instructions screen described controls it does not have. The key is optional and the old string is still the fallback, so the other two games render identically. A game that supplies its own line also suppresses the auto-appended controller line: the framework cannot know whether a pad does anything in a game it knows nothing about, and offering a gamepad to someone holding a guitar is worse than saying nothing. |
| 14 | `tools/tutorial_capture.gd` + `tools/record_tutorials.ps1` — a `dead_metal_jam` branch | **Done, dev-only.** Neither file ships in a build; they exist to record the instructions clip. The branch adds setting overrides, five caption steps and a scripted keyboard player, because a tutorial for this game cannot be driven by moving a mouse. |
| 15 | `tutorial_capture.gd` — `GameSession.game_title()` no longer exists | **Bug fix.** `_build_overlay()` called a method that had been removed, and the error aborted the function before it created the title, body, keycap and fade — so *every* clip this tool had ever produced was a bare step-number badge over silent gameplay, for all three games. Now read from `GameCatalog`. Found by recording a clip and looking at it. |
| 16 | `router.gd`, `game_shell.tscn`, `menu_screen.gd`, theme | **Untouched.** |

### 9.6 Achievements

Registered from the manifest; persistence, toasts and audio are automatic.

| ID | Title | Condition |
| --- | --- | --- |
| `jam_first_track` | Soundcheck | Finish any track in any mode. |
| `jam_perfect_section` | Tight | Clear a section with every kill at Perfect. |
| `jam_no_damage` | Untouched | Finish a track in Jam mode without letting a single bot fire. |
| `jam_mic_run` | Unplugged | Finish a Jam track on the microphone path. |
| `jam_combo_eight` | Shredder | Reach ×8 combo. |

**Two of them are suppressed in Demo mode**, which is a deviation from the
table as first written and worth the paragraph. Demo stops the clock until the
right note arrives (§3), so a Perfect tier and a long streak are not
achievements there — they are what the mode *is*. Awarding `jam_perfect_section`
and `jam_combo_eight` in Demo would mean the two hardest badges are the two
easiest to get, which devalues them for the players who earned them properly.
`jam_first_track` still unlocks in any mode: finishing a track is a real thing
to have done however you got through it, and it is the badge that tells a new
player the system exists.

**`jam_no_damage` and `jam_mic_run` are Jam-only** for the same reason from the
other direction. Rhythm mode does not let bots fire, so "no damage" would be
automatic, and Demo's frozen clock makes it nearly so.

**The round-end badges read `EncounterDirector.mode()`, not the setting.** The
setting can be changed from the pause menu mid-round; the director's mode is
the one the round was actually played under. `halt()` deliberately leaves it
intact so it can still be read when the round is being scored.

No `GameUnlockRule` in MVP — Dead Metal Jam is available from the start.
Gating it behind Triangle Rush would be trivial to add later and needs no
framework change.

### 9.7 Accessibility (non-negotiable in this codebase)

- **Reduced motion** — camera movement, deployment slides, sweeping room
  transitions, traveling orbs and idle animation stop. Static shot paths,
  hit/miss labels, attack bars and room changes retain the essential cues.
- **Intense visual effects off** — no damage vignette flash, no shake; damage
  is then signalled by the shell's `LIVES LEFT` readout, the hit-stop and an
  audio caption. All three come from the shell, so the game cannot get this
  wrong by forgetting to check the setting.
- **Audio captions** via `AudioManager.request_caption()` for: note detected,
  wrong note, life lost, wind-up warning, section cleared. The wind-up tick is
  a sound-only event and *must* be captioned.
- **Never colour alone** — every note is a letter first; the chart's per-note
  colours from `README.md` are decoration layered on the glyph.
- **Handicaps** — `Settings.gameplay_speed_scale()` (0.6–1.0) scales the single
  delta the director is advanced by, which slows repositioning, deployment, the
  wind-up fuse and the beat *together* because all four are derived from that
  one clock. The round timer is divided by the same scale, or asking for an
  easier game would quietly mean "the same timer, less of the song" and push
  `TRACK CLEARED` further away. `Settings.target_size_scale()` (up to 1.4)
  widens timing windows; `Settings.extra_round_time()` is not meaningful here
  (round length is the chart) and is ignored, which is a legitimate per-game
  choice.
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
  clean versus dirty waves, track end, Rhythm mode's flag, and — since
  milestone 6 — the phrase enemy, per-wave rail advances, section
  announcements and roster staging. Drones are stepped by hand at a fixed 1/60
  timestep, so every timing assertion is deterministic rather than frame-rate
  dependent.
  **Verified to have teeth** by mutation: bypassing the timing window, sorting
  targets back-most first, and suppressing the fire transition each fail it
  loudly (3, 2 and 3 checks respectively). The milestone-6 additions were
  mutation-checked the same way — dropping the phrase beat re-base, dropping
  the "only a started phrase can be broken" guard, and ignoring a wave's own
  advance each fail 2, 2 and 5 checks. The guard mutation initially passed,
  which was the test's fault and not the guard's: it asserted the cursor and
  the readout, which are unchanged when the cursor is already zero, and not the
  thing that actually breaks — the bot's beat being pushed out from under a
  player who was already lining the note up.
- `tests/mode_test.gd` — the three modes (§3), and only them. Split out of
  `encounter_test.gd` in milestone 7 because it asks a different question:
  that file asks what the rules are, this one asks whether the modes are
  really *just flags* on those rules. It asserts each mode's four flag values
  and that switching is reversible, that `dmj_options.gd`'s copied mode
  numbers still match the director's enum, that Rhythm takes any note but no
  worse timing, and that Demo holds the world, holds it only for the bot the
  reticle is on, releases it on the answer, never lets a bot fire, keeps the
  rail moving between waves, and paces a phrase plate by plate.
  **Verified to have teeth** by mutation, which is the whole point of the file:
  forcing `stop_time` off, `reports_damage` on, `pitch_matters` on, the mode
  window scale to 1.0, and removing the frozen-`step` gate fail 13, 1, 5, 3 and
  8 checks respectively. Two mutations survived the first pass and both were
  real gaps, now closed: switching *out* of Demo mid-freeze was untested, and
  freezing for any waiting bot rather than the front-most was invisible because
  the arranged moment landed on `time_to_beat() == 0.000` exactly, where the
  two behaviours agree to the microsecond.
- `tests/arcade_shooting_test.gd` — correct-note shots before the firing deadline,
  timing bonuses, firing urgency, separate bays, per-plate impact positions,
  frame-independent attack clocks, long-frame Demo safety, bounded cosmetic
  effects and real gameplay input/damage/replay integration.
- `tests/staging_test.gd` — the picture rather than the rules (§8.1). Split out
  of `encounter_test.gd` when the corridor pushed it past the 1000-line limit,
  on a line that was already there: a failure in this file means the game
  *looks* wrong, a failure next door means it *plays* wrong. It asserts that
  the corridor reserves headroom without swallowing the run-up and survives a
  degenerate field, that firing depth sets scale and draw order, that
  distance fogs a bot without making its glyph unreadable or touching alpha,
  that bots hold their firing positions rather than growing toward the camera,
  and that the head bob moves, stays small, only ever dips, stops dead under
  reduced motion and freezes with Demo's stop-time.
  Nothing here renders: the corridor is geometry before it is pixels, and the
  numbers are the part a screenshot could not pin down anyway. The visual half
  was checked separately by capturing real frames of the shipping scene and
  measuring per-frame pixel change on a wall row and a ceiling row — 30–62% and
  35–45% during an advance, against a reduced-motion control that drops to
  17–24% with the bob at exactly zero on both axes.
  **Verified to have teeth** by mutation: zeroing `HORIZON_HEADROOM`, zeroing
  `FOG_STRENGTH`, removing the corridor inset, disabling the reduced-motion
  early return, running the bob on `delta` instead of the stop-time-gated
  `step`, leaking a section name into the advance copy, moving the last-stretch
  boundary by one, and counting waves from zero each fail it.
  It also covers the HUD's words, which is the one thing here that is not
  geometry: that the banner counts waves the way a person does, that the
  advance copy never quotes a section name, and that only the final advance
  gets the last-stretch line. The section names are read out of the *shipped
  chart* rather than hardcoded, so renaming a section cannot slip a new word
  past the check. Reaching them at all takes a trick worth knowing: `gameplay.gd`
  can never be instantiated headlessly, but its copy functions are `static`, so
  a runtime `load()` can call them. It must stay `load()` and never become
  `preload` — a preload resolves while the test script itself compiles, which
  drags `GameShell`'s `Settings` reference in before the autoloads exist and
  fails the whole file.
- `tests/jam_chart_test.gd` — the two things that produce a track. The chart
  compiler and the shipped song: beats sort, empty sections are skipped rather
  than compiled into a wave that ends on the frame it starts, an unknown
  archetype falls back instead of failing, auto lanes spread across all three,
  `beats[].duration` becomes the wind-up, arrivals survive the section offset
  exactly, a phrase compiles with a wind-up it can physically be played in,
  and a chart is priced by the same rule as a practice ramp. It then loads
  `charts/track_01.tres` itself and asserts it is playable, so a hand-edited
  chart cannot ship broken. Since milestone 7 it also holds the
  `DmjTrackBuilder` tests, moved here from `encounter_test.gd`: a song someone
  wrote down and a ramp nobody wrote are the same question from opposite ends,
  they must produce the identical plain data, and
  `_test_duration_matches_the_builder()` is the seam where that is checked.
- `tests/round_music_test.gd` — the song's lifetime, which is the one thing
  about the music a player notices when it is wrong. Four unit tests on
  [`DmjTrackBed`] — that it is pausable and on the Music bus, that a null
  stream is silence rather than an error, that holding keeps its place and
  resuming returns to it, that a bed with nothing held stays quiet, and that
  finishing clears the held position so a later resume cannot start a song
  under a player who is no longer in a round. Then one scene-level test that
  instantiates the *real* `gameplay.tscn` in a `SubViewport` and pauses,
  resumes, closes the overlay and frees the scene, asserting silence after the
  pause and after the exit. It deliberately lets the song run for 400 ms
  before pausing: a round paused on its first millisecond cannot tell "came
  back where it was" apart from "started the track over", and the assertion
  would pass either way.
  It also checks that no `AudioManager` player is holding the round's stream,
  which is the exit bug stated directly rather than by proxy.
  **Verified to have teeth** by mutation: dropping the `hold()` on pause,
  dropping the `finish()` on exit-tree, dropping the resume, resuming with
  `play(0.0)` instead of `play(from)`, and holding without recording the
  position each fail it with the matching message. The distinction the scene
  test rests on is an engine behaviour that was measured rather than assumed —
  a pausable `AudioStreamPlayer` frozen by the tree reports `playing == false`
  with `get_playback_position()` *intact*, whereas a real `stop()` returns it
  to zero, so asserting zero is what separates "the round stopped it" from
  "the engine merely muted it".
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

**As built, three tracks ship.**

| Chart | Title | BPM | Key | Sections | Bots | Plated | Audio |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `track_01.tres` | Demo | 140 | E minor | 5 | 24 | 3 | `demo.ogg` (3:05) |
| `track_02.tres` | Scrapyard Stomp | 100 | A minor | 5 | 24 | 3 | `track_02.ogg` (2:33) |
| `track_03.tres` | Overdrive | 168 | E minor | 6 | 33 | 3 | `track_03.ogg` (2:33) |

Track 01's audio is a recording the author holds the rights to, trimmed to
3:05. **Tracks 02 and 03 are generated**, by `tools/make_tracks.py`, which writes the `.ogg`
*and* emits the `.tres` from one shared description of the song. That is the
point of the tool: a chart and the music it is charted against are the same
data seen twice, and the only reliable way to keep them in agreement is to stop
maintaining them separately. Re-run it with `python tools/make_tracks.py`.

**They are slow, medium and fast on purpose.** 100 / 140 / 168 BPM is the
readable spread — the menu lists them by tempo and shows the number, because a
player choosing a track on an instrument is choosing how fast they have to
move. Scrapyard Stomp being the slowest is also why the tutorial is recorded
against it (§9.5 row 14).

**How the tempo was verified, and the two ways that failed.** A generated bed
still has to be *checked*, because a bug in the synthesiser would produce a
chart that agrees with a song nobody can hear the beat of. The first attempt
autocorrelated the onset envelope, the same method used on track 01 — it locked
onto half- and double-tempo and reported 200 BPM for the 100 BPM bed.
Autocorrelation cannot distinguish a period from its harmonics, and on a bed
with a strong backbeat the wrong one often wins. The second attempt measured
what share of the onset energy fell on the beat grid, which passed for
*everything*, including deliberately detuned control input — a grid coarse
enough to catch real playing is coarse enough to catch noise. What works is a
phase sweep: slide the grid across a full beat, confirm the energy peaks at one
offset rather than being flat, then confirm with a Goertzel filter that the
expected tempo bin actually leads its neighbours. `make_tracks.py --verify`
runs it, and it fails if the tempo is wrong.

The lesson is the one this document keeps relearning: a measurement that
returns a plausible number is not a verification. Both failed methods produced
confident answers, and both would have shipped a chart that fought the music.

**The songs play through once and are never looped.** An earlier build shipped a
sixty-second cut of track 01's master with the loop flag set, so a long round heard
the same minute twice. Looping is controlled
entirely by the `.import` `loop=` flag and by nothing in code, which is exactly
why `jam_chart_test.gd` asserts it: no other line in the project reads it, so
nothing else would notice if it changed.

**Every track is trimmed to slightly more than the longest round that can
reach it.** `gameplay.gd` clamps `round_duration` to `MAX_ROUND_SECONDS = 180`,
so three minutes is the hard ceiling on how much music a round can consume no
matter how badly it is played or how far the speed handicap is turned down.
Track 01 ships at 3:05 and the generated beds at 2:33, each with a three-second
fade on the tail so reaching the end of the file sounds like an ending rather
than a cut. The audio a player can actually hear is therefore unchanged; what
went away is 5 MB of tail nothing can reach.

This is *not* a reversal of the loop fix above, and the difference is worth
being precise about. The thing that was wrong before was a **sixty-second cut
that looped** — the player heard the same minute twice inside one round. A
trim longer than the round ceiling cannot repeat, because the round ends first.
The honest cost is that the master is no longer shipped whole: the file in
`assets/` is now a derived cut, and re-making it needs the master, which lives
outside the repository. `jam_chart_test.gd` asserts every track still outlasts
its own chart by at least thirty seconds, so a trim that went too far fails
rather than silently fading a round out on silence.

Beat times are laid out on the track's **measured** tempo — for track 01, 140
BPM taken by autocorrelating the onset envelope of the cut, not assumed. An
earlier draft of this chart was written at 100 BPM and every demand in it
landed slightly beside the music, which is the one thing a rhythm game cannot
afford to get wrong by a little.

Three compiler decisions are worth recording.

**A beat's `time` is an arrival, not a spawn.** The bot has to appear one
approach earlier, and the obvious implementation — clamp the first spawn to
zero — drags that first arrival late and shears every interval in the section
behind it. The whole section is offset by one approach instead, so the
intervals inside it survive exactly. That is what a chart actually promises.

**`beats[].duration` buys the late half of the window only.** The early half is
already the approach, which the timing tiers judge; what the chart is really
setting is the bot's wind-up. Zero means "use the section archetype", which is
how nearly every beat should be written.

**A phrase's wind-up is written into the plan, not widened at spawn.** The
round length is derived from the plan (§2), so a Plated Knuckle that quietly
gave itself more time at runtime would make the round timer lie. Both the chart
compiler and `DmjTrackBuilder` call the same `PlatedKnuckle.windup_for()` and
write the result down.

**Sections are not glued to the audio clock, and that is a deferral, not an
oversight.** A wave ends when it is cleared and the rail advance in front of
the next one is a fixed length, so real time drifts from track time as the
player plays well — the audio is a *bed*, not a conductor. Syncing them needs
the chart cursor to drive the spawner from `AudioStreamPlayer.get_playback_position()`,
which is a different game to build and test than the one milestone 6 was for.
The consequence is honest and small: intervals hold inside a section, and a
section boundary may land off the bar. Every track is written long enough that
a strong player reaches the end of the chart well before the end of the music.

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
| **Silencer Sentry** | An enemy whose rule is an inversion of the core verb. Worth building, but only after the core verb is proven fun. |
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
3. Chords on the MIDI path (Plated Knuckle becomes a chord enemy).
4. The Conductor boss.
5. Silencer Sentry.
6. `.jam` importer mapping the `README.md` JSON onto `JamChart`.
7. Scale-relative chord notation.
8. Life regeneration.
9. A `GameUnlockRule` gating Dead Metal Jam behind Triangle Rush.

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
| 4 | ✅ **Done.** Three lanes, Rusty Clanky, front-most matching, timing tiers, the combo ladder and the practice track builder. The round length now comes from the track (§2) rather than a hardcoded 30 s. Autoplayed headlessly through the real scene on the keyboard source: **4 waves, 14 of 14 drones killed, 0 misses, TRACK CLEARED, 3645 points** — which is exactly 14 kills at ×1/×2 combo with the exact-source bonus plus four clean-wave bonuses, so the scoring arithmetic is confirmed end to end and not just unit-tested. | The framework integration, and that `game_shell_test.gd` still passes. |
| 5 | ✅ **Done.** Wind-up telegraph, `_lose_life()` on a drone that fires, `_player_is_out()` gating the router, and `TRACK CLEARED` via the inherited `_end_round()` (option 1 of §7.4). Verified in the real scene by a **pacifist run**: nobody plays, three drones fire, `lives` goes `3 → 0` and the round settles at 18.4 s against a 48 s timer. The win path and the loss path are therefore both exercised against the shipping scene. | The fail state — and that the game never branches on the round mode. |
| 6 | ✅ **Done.** The visible rail, named sections with staging archetypes, the `JamChart` compiler and the second enemy. One song ships — five sections, 24 bots, three Plated Knuckles — charted against `demo.mp3`, and the practice ramp survives as a player-facing option rather than being deleted. Autoplayed headlessly through the real scene: **5 sections in order, all cleared clean, 24 robots down, 4 plate hits, 0 misses, TRACK CLEARED at 62.3 s** against a 73.2 s backstop, with the music still playing under it. `encounter_test.gd` is now 242 checks and `jam_chart_test.gd` adds 170. | Pacing. |
| 7 | ✅ **Done.** Demo and Rhythm ship as a Settings → Game choice (`game/dmj_mode`), and `apply_mode()` is the entire difference between them: four flags, one code path. Proved in the real scene by autoplaying the same song five ways. Played correctly and on time, **Jam scores 10105 with 28 hits and 24 kills** — and *Rhythm playing deliberately wrong notes* and *Demo answering every beat 1.25 s late* both score **exactly 10105, 28 hits, 24 kills**. The two negative controls are what make that mean something: the same wrong notes in **Jam score 0** (90 wrong notes, 0 hits) and the same late notes in **Jam score 0**. Demo held the world 28 times and paused the round clock for 35.1 s with no drift. | That the mode flags really are flags. |
| 8 | ✅ **Done.** Two more charts, the five achievements, a game-owned share card and the instructions clip. `tools/make_tracks.py` writes each new song's `.ogg` and its `.tres` from one description, so the chart and the music cannot disagree; tempo is verified by a phase sweep plus a Goertzel lead check after autocorrelation and energy-share both returned confident wrong answers (§10). **Three tracks now ship — 100, 140 and 168 BPM; 81 bots and 9 Plated Knuckles between them** — and `jam_chart_test.gd` loads every entry in `DmjOptions.CHART_PATHS` rather than a chart it was told about, going **276 → 563 checks**. The share card draws the game's own corridor, which meant making `share_art_scene_path` do something: it was a manifest field nothing read. Two real bugs in that art were found by rendering the card to a PNG and looking at it, and a third — a framework bug that had silently reduced *every* tutorial clip for *all three games* to a bare step badge — was found by recording the clip and looking at that. The clip is 30.0 s of Scrapyard Stomp autoplayed through the shipping scene, five captions, **1055 points and two waves by the end**, including a robot reaching the front and firing under the caption that describes it. **All 17 suites green.** | **Jam submission.** |
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
| Players cannot read notation | The game never shows notation — letters only. Demo mode exists as the on-ramp. |
| **Jam deadline eats the game** | Milestone 1 is a hard gate and milestones 9–10 are outside the jam. If the schedule slips, the roster shrinks (§8.2 already marks three enemies stretch) and the chart count drops to one — the platform ladder is never the thing that gets rushed. |
| **No native Web MIDI in Godot** | Known and confirmed, not a surprise to be discovered late (§4.2). Web still has the mic and keyboard paths, so a browser build is playable *before* the shim exists; the shim only restores the exact path. |
| **Web audio needs a gesture and a secure context** | Soundcheck is already a mandatory press-through overlay, so the unlock has a natural home (§4.3). The failure mode to design against is a silent one: if the context never starts, the readout must say so rather than showing a flat meter. |
| **Mobile audio latency is far worse than desktop** | Calibration (§4.6) absorbs a constant offset, and the timing tiers are tuning constants. If a phone still cannot hold the Good window, that platform ships Rhythm mode first — which needs onsets, not pitch. |
| **Designing for three platforms slows the jam build** | It does not, as long as the two rules in §4.7 hold: no platform checks in gameplay, and nothing desktop-only becomes load-bearing. Both are cheap to obey now and expensive to retrofit. |

---

## 14. Document revisions

| Revision | Change |
| --- | --- |
| 20 | **The song stops when the game does** (§9.1, §9.3, §9.5 row 9, §9.8). Reported symptom: pausing left the track playing over a frozen game, and leaving for the main menu took the track with it. Two faults, one cause. The music was played through `AudioManager`, whose players are deliberately `PROCESS_MODE_ALWAYS` so a menu bed can survive the scene change it is playing under — correct for a menu, and exactly backwards for a song that belongs to one round. The second fault is worse because nothing in this game was even reachable: the pause overlay's own *Exit to main menu* unpauses the tree and calls `Router.goto()` itself, so `_finish_round()` — the only place that stopped the music — never ran, and the main menu has no track of its own to talk over the one that followed the player in. **The fix is a node, not a call.** `encounter/track_bed.gd` is an `AudioStreamPlayer` living in the gameplay scene: it is `PROCESS_MODE_PAUSABLE`, so the world stopping arrives *at the bed* as `NOTIFICATION_PAUSED`, and it dies with the scene, so `NOTIFICATION_EXIT_TREE` covers **every** way out — including routes this game has never heard of. Both are answered inside the bed rather than in `gameplay.gd`, so no future exit can leave the song playing by forgetting to call something; the only piece wired up on the game's side is the way *back* into a round. **A pause holds its place rather than restarting the track**, because a player who paused four minutes into a song did not ask to hear it again; that is the one behaviour here that is a choice rather than a consequence, and it is why the bed keeps a position at all. Resume hangs off `_on_pause_closed()` and not `NOTIFICATION_UNPAUSED` — the overlay unpauses the tree *before* routing away, so unpause would blip the song back on for the length of the router's fade; `closed` is emitted by the pause menu's `resume()` and by nothing else. **`AudioManager` is still untouched** (§9.5 row 9): its behaviour is right for the menus, and changing it would change what the other two games' music does. The duplicate-stream workaround from revision 14 was **deleted with the problem it worked around** — it existed because `play_music()` no-ops on the stream object already playing while `stop_music()` calls `stop()` from a tween callback at the end of its fade, and a player this scene owns has no such handshake. That same no-op has a sharper edge that owning the bed also sidesteps: `stop_music()` early-returns while `_music.playing` is false, so a stop issued *during* a crossfade does nothing and can leave the incoming player running with nobody holding a reference to stop it. `round_music_test.gd` is new (34 checks) and drives the real scene rather than a stand-in; five mutations were run against it and all five were caught. **Where the code sits was decided by the lint limit, and the limit gave the right answer.** `gameplay.gd` was 23 lines from the 1000-line ceiling, and a first draft that narrated the whole fix from the subclass — the fade lengths, the notifications, the prose — landed at 1027 and failed `gdlint`. Moving the music policy into the file that owns the music, which is what the limit forced, is also what makes the bed self-defending rather than something `gameplay.gd` has to remember to drive; the subclass keeps the 992-line file and the one hook the bed genuinely cannot serve itself. The engine behaviour the scene test depends on was measured first with a throwaway probe rather than assumed — playback positions do advance under the headless dummy driver, and a pausable player frozen by the tree keeps its position while a real `stop()` zeroes it, which is the difference the test asserts. All 18 suites green; `gdlint` clean on every file this change touches. |
| 19 | **The two recorded tracks ship as trimmed OGG** (§9.1, §10). `assets/demo.mp3` (4.46 MB, 4:35) and `assets/intro-bg.mp3` (3.98 MB, 4:03) became `demo.ogg` (3.05 MB, 3:05) and `intro-bg.ogg` (0.36 MB, 0:20) — **8.44 MB down to 3.41 MB**, with nothing a player can hear removed from either. The trim lengths are measured rather than chosen: `gameplay.gd` clamps `round_duration` to `MAX_ROUND_SECONDS = 180`, so three minutes is the hard ceiling on how much of track 01 any round can consume, and the intro is `TOTAL_SECONDS = 9.0`, so twenty seconds of bed is already double what the scene can reach. Both were checked for leading and trailing silence first — there was none, so this is a length cut and not a clean-up, which is the sort of thing worth establishing before deleting four megabytes. **This is deliberately not a reversal of revision 16.** What was wrong then was a sixty-second cut *with the loop flag set*, so a single round heard the same minute twice; a trim longer than the round ceiling cannot repeat, because the round ends first. The honest cost is the other half of that revision: `assets/` now holds a derived cut rather than the master, and the master lives outside the repository, so re-making the trim is no longer something the checkout can do by itself. Each file gets a three-second fade on the tail, because a trimmed song that reaches the end of its file otherwise stops mid-note — the game's own fade only runs when the *game* decides to stop the music, which is a different path from the stream simply running out. The fade was verified by decoding the tails and measuring RMS in half-second windows (demo: ~6000 through 182 s, falling to 591 by 184.5 s), which was worth doing: `volumedetect` with an input seek had reported identical loudness at two points three minutes apart, a plausible-looking answer that was purely an artefact of imprecise Vorbis seeking. All four audio assets are now `oggvorbisstr` with `loop=false`, which `jam_chart_test.gd` still asserts along with each track outlasting its own chart by thirty seconds. All 17 suites green. |
| 18 | **Milestone 8: three tracks, five achievements, a game-owned card and the instructions clip** (§9.1, §9.2, §9.4–9.6, §10, §12). The theme of this one is that four separate things looked finished and were not, and each was caught the same way — by producing the artefact and *looking at it*. **The two new songs are generated by `tools/make_tracks.py`**, which emits the `.ogg` and the `.tres` from one description, because a chart and the music it is charted against are the same data seen twice and the only way to keep them in agreement is to stop maintaining them separately. **Verifying the tempo took three attempts and the first two failed by succeeding.** Autocorrelating the onset envelope — the method that measured track 01 — locked onto a harmonic and reported 200 BPM for the 100 BPM bed; a rewrite measuring the share of onset energy landing on the beat grid then passed *everything*, including deliberately detuned control input, because a grid coarse enough to catch real playing is coarse enough to catch noise. What works is a phase sweep that confirms the energy peaks at one grid offset rather than being flat, plus a Goertzel filter confirming the expected tempo bin leads its neighbours. Both failed methods returned confident numbers, which is the point worth keeping. **Track option values are appended, never renumbered** (§9.4): the value is what lands in `user://settings.cfg`, so re-sorting the list to read tidily would silently move every player who chose the practice ramp onto a song. **Two of the five achievements are suppressed in Demo** (§9.6) — Demo stops the clock until the right note arrives, so a Perfect tier and a long streak are what the mode *is*, and awarding them there would make the two hardest badges the two easiest to get; the round-end badges also read `EncounterDirector.mode()` rather than the setting, which can be changed from the pause menu mid-round. **`share_art_scene_path` had to be made real** (§9.5 row 8): this document recorded a third hardcoded card style as "avoided" by using that manifest field, but nothing in the framework read it, so the avoidance was a field that did nothing. `share_card.gd` now installs the game's scene and — the half that matters — swaps it back, since one card is reconfigured for every result shared. Rendering the card to a PNG and looking at it found two bugs no test had: `%ActionArt` stopped resolving after the swap because a node added at runtime has no `owner` to register a unique name against, and the near robot was clipped by the card frame. **The tutorial found a framework bug that had been silently corrupting every clip for all three games**: `_build_overlay()` called `GameSession.game_title()`, which no longer exists, and the error aborted the function before it created the title, body, keycap and fade — so every walkthrough ever recorded by this tool was a bare step-number badge over silent gameplay. Nothing failed; the tool exited zero and wrote a video. It was found by watching the video. **The clip is recorded against a shipped chart, not the practice ramp**, because the ramp is seeded from the clock and a caption timed against one take would be describing another; and the caption teaching the armoured robot was **cut rather than faked** once measurement showed all three charts hold their first Plated Knuckle past the half-minute mark — which is deliberate (§8.2) and correct, so the tutorial stops before it rather than lying about it. `jam_chart_test.gd` now loads every entry in `DmjOptions.CHART_PATHS` rather than a path it was told about, and asserts the menu and the chart map describe the same set of songs: **276 → 563 checks**. The new share-card test was proved load-bearing by disabling the feature and confirming it went red. All 17 suites green. |
| 17 | **Section names stop being player-facing** (§5.3, §9.8). CHORUS, BRIDGE and the rest were removed from every surface the player sees: the HUD banner, the centre-screen flash on each rail advance, the status line and the screen-reader caption. The reason is that a section name is *authoring* vocabulary — it is how whoever wrote the chart talks about the song — and it tells somebody holding a guitar nothing they can act on. The names stay in the chart, where an author still wants them (§10); `JamSection.name` and `EncounterDirector.section_name()` keep working and are now documented as authoring and diagnostics only. The banner keeps the half of its old content that *was* useful, `WAVE 3 / 5`, which is also what the practice ramp already read — so the HUD no longer changes shape between a charted song and a generated ramp. The advance spends its words on encouragement instead, chosen by position in the track rather than at random so two runs read the same way, with **"Last stretch!" reserved for the final advance** because "keep going" is the wrong thing to say to somebody one wave from the end. One bug was found by verifying against a real run rather than trusting the code: the advance's status line was written once in `_on_section_started()` and silently overwritten one frame later by `_update_target_readout()`, which rewrites that label every frame — true of the old section-name copy too, so it had been dead the whole time. The line is now held in `_advance_line_now` for the length of the advance. Proved by capturing every word the HUD showed during a full autoplay: banner `WAVE 1 / 5` through `WAVE 5 / 5` then `TRACK CLEARED`, status `Breathe. Keep on going!` → `Nice! Keep it up!` → `Still standing!` → `You've got this!` → `Last stretch!`, with the run itself unchanged at 24 kills and TRACK CLEARED at 63.5 s. The copy functions were made `static` so a headless test can reach them without instantiating `GameShell`, and `staging_test.gd` grew from 25 to 77 checks; three mutations — leaking a section name, moving the last-stretch boundary by one, and counting waves from zero — were each caught. The HUD node `DmjSection` was renamed `DmjProgress` so the scene stops using the vocabulary the game no longer shows. |
| 16 | **The corridor, and the song plays through** (§8.1, §8.4, §9.8, §10). Three requests, and the interesting one is the request that was refused. **The music no longer loops.** The shipped chart pointed at a sixty-second cut of the master with the loop flag set, so a long round heard the same minute twice; it now plays `assets/demo.mp3` whole, which outlasts the slowest possible run of the chart by minutes, and the derived cut was deleted rather than left to rot beside a source it can be re-made from. Re-pointing the chart was checked rather than assumed: the 140 BPM grid was measured against the full master by cross-correlating onset envelopes, and the cut sits at lag 0 with r = 0.966, so every beat time in the chart still lands where it did. **The intro slideshow has a bed** (`assets/intro-bg.mp3`), and it clears it on the way out — `main_menu.gd` guards `if music:`, so a menu with no track of its own would otherwise have inherited the intro's. **The rail became a corridor** (§8.1): backdrop, ceiling beams, trapezoid floor, panelled walls, haze and a light pool at the camera's feet, plus depth fog on the bots and a head bob on the camera. Four decisions are recorded there, and the one worth reading twice is that **wall height must not reuse the lane spread** — the obvious reuse makes wall tops and bases converge together, which collapses the ceiling to a sliver and reads as a striped floor. The **first-person guitar viewmodel was designed and then cut**: a viewmodel lives at the bottom of the frame and in this game the bottom of the frame *is* the strike line, so it would cover bots at the exact instant their arrival has to be judged. The light pool replaces it — same muzzle-flash job, drawn behind every bot instead of in front of them. Nothing was allowed to change **apparent speed**; the linear walk is what makes an arrival playable to a beat, so every new cue was chosen to be a depth cue and not a motion cue. Verified by capturing real frames of the shipping scene and measuring per-frame pixel change (30–62% on a wall row during an advance, against a reduced-motion control at 17–24% with the bob pinned to exactly zero), which also caught two bugs a unit test could not have: a triangulation failure from a guard written in unit space for a quad drawn in progress space, and a ceiling too shallow to see. `staging_test.gd` is new (25 checks), split out of `encounter_test.gd` on the line between how the game plays and how it looks; six mutations were run against the new guards and all six were caught. |
| 15 | **Milestone 7: Demo and Rhythm ship** (§3, §9.4, §9.8, §12). The milestone's obligation was to prove the modes are *flags*, so the implementation is one function — `apply_mode()` sets four booleans and nothing else — and the tests are built to falsify exactly that. Four decisions are recorded. **Mode ships as a Settings row, not the Soundcheck overlay this document promised** (§3): that overlay was dropped in revision 6 when `_begin_first_round()` turned out to be obliged to start a round, leaving nowhere for it to live, and the input source — the other setting §9.4 assigned to Soundcheck — had already shipped as a tunable. Following the shipped precedent beat inventing a second pattern; the honest cost is that mode is now chosen before a round rather than during one. **Stop-time is one `step` variable, not a per-system flag** (§3): the rail, the walk, the wind-up fuses and the chart cursor all read it, so they cannot drift apart while the world is held — and `Engine.time_scale` was rejected because it would fight the shell's timer, tweens and pause overlay. **The round timer is paused too**, because "the run always finishes" would otherwise be false for exactly the player Demo exists for. **Demo waits only for the front-most bot**, and the reason recorded in the code was found to be wrong while testing it: the first draft claimed a bot further back is unhittable, but `_front_most_in_window()` skips out-of-window matches, so it is perfectly hittable. The real reason is that the reticle and the HUD readout both follow the front-most bot, so a freeze held for anything else is a freeze the player is never told how to end. Proved in the real scene rather than only unit-tested, with negative controls: the same song scores **10105 in Jam played correctly, 10105 in Rhythm played with deliberately wrong notes, and 10105 in Demo answering every beat 1.25 s late** — while those same wrong notes score **0 in Jam**, and those same late notes score **0 in Jam**. `mode_test.gd` is new (63 checks) and mutation-checked; two mutations survived its first pass and both were real gaps, now closed. Test files were also rebalanced to the 1000-line limit: modes left `encounter_test.gd`, and the `DmjTrackBuilder` tests joined the chart compiler in `jam_chart_test.gd`, which is where the other half of "things that produce a track" already lived. |
| 14 | **Review fixes** (§9.4 handicaps, §10). Two defects found by review of the milestone 6 change set, both in the seams rather than the rules. **The song is started from a fresh `AudioStream` instance each round.** `AudioManager.play_music()` no-ops when the same stream object is already playing, and `stop_music()` fades out and calls `stop()` from a tween callback at the *end* of the fade — so pressing Play Again inside the 0.6 s fade hit the no-op and was then silenced by the callback already in flight, and the round opened in silence. Demonstrated against the real autoload before fixing, and the fix demonstrated against it after; the copy is a handle, not a second megabyte, because the MP3 bytes are copy-on-write. **The speed handicap was a no-op.** `GameShell` computes `_round_gameplay_speed` but nothing reads it, so this document promised an accessibility setting the game did not implement. The director is now advanced by a scaled delta — one multiplication, in one place, because the rail, the walk, the wind-up and the beat are all derived from that clock and would otherwise drift apart — and the round timer is divided by the same scale, since a slower game on an unchanged timer is not an easier game. Also corrected: the practice ramp was naming each wave `"WAVE 3"`, which the banner rendered as `WAVE 3 · 3/5`; a name belongs to a chart, and a generated ramp does not have one. |
| 13 | **Milestone 6: the rail moves, the song has sections, and the roster is two** (§8.1–8.5, §9.1, §9.4, §10, §12). Six decisions are recorded. **A shared `JamBot` base was extracted before the second enemy was written**, not after: Rusty Clanky was the only bot, so every rule in the director was implicitly a rule about *it*, and adding a second enemy on top of that would have meant the matching rule learning what kind of thing it hit. The director now calls `strike()` and asks afterwards whether the bot is still targetable — **`strike()` rather than `kill()`** is the whole of what made a multi-note enemy possible without a branch. **A broken phrase re-bases its beat**, because resetting only the cursor leaves the next beat in the past and turns one wrong note into a guaranteed hit taken; and **only a phrase in progress can be broken**, or every stray note is a penalty against bots the player never engaged. **A phrase's wind-up is written into the plan** rather than widened by the bot at spawn, since the round timer is derived from the plan (§2) and would otherwise lie. **The rail is drawn** (`encounter/rail.gd`) because pacing is the one thing here that cannot be unit tested — a test can prove 2.2 seconds pass between waves, but only a moving floor tells the player those seconds are travel rather than a stall. And **the music is a bed, not a conductor** (§10): waves end early on good play, so track time drifts from real time, and audio-position-driven spawning is deferred rather than faked. Two smaller corrections: the chart was re-authored at the track's **measured** 140 BPM after a first pass at an assumed 100 put every demand slightly beside the music, and the practice ramp was kept as a player-facing Track option instead of being deleted, because a ramp that never stops is what somebody learning their instrument wants. Verified against the shipping scene, not just unit-tested: 5 sections, 24 robots down, 4 plate hits, 0 misses, TRACK CLEARED at 62.3 s. New tests: `jam_chart_test.gd` (170 checks) and 74 more in `encounter_test.gd`, each mutation-checked against a deliberately broken build before being trusted. |
| 12 | **The roster is four enemies** (§8.2). Feedback Wasp, Amp Golem, Mirror Unit and Detonator are cut, and the survivors renamed: Rust Drone → **Rusty Clanky**, Plated Hulk → **Plated Knuckle**, Silence Sentry → **Silencer Sentry**. The cut is by *demand*, not by taste — what remains asks for one note, several notes in order, no notes, and a riff, which is the whole span an instrument can be asked for. Feedback Wasp was Rusty Clanky with a shorter window, which is a chart tuning value rather than an enemy; Detonator restated the wrong-note penalty as a hazard; and Amp Golem and Mirror Unit each needed a whole subsystem the MVP does not have (sustain tracking via `note_ended`, and the game playing notes *at* the player), so both were carrying stretch risk while sitting in the MVP column. Only Rust Drone existed in code, so this was a rename rather than a deletion: `class_name RustDrone` → `RustyClanky` and `enemies/rust_drone.gd` → `enemies/rusty_clanky.gd`. **The encounter system's generic vocabulary is deliberately untouched** — `drone_spawned`, `_drones`, `live_drones()` and the chart's `{"drones": [...]}` key all still say "drone", because they name *any* enemy actor rather than this one, and the chart key is a data contract that outlives the roster. |
| 11 | **It became a game** (§6, §8.3–8.5, §9.1, §9.8, §12 milestones 4 and 5). Milestones 4 and 5 are done: three lanes, Rusty Clanky, front-most matching, timing tiers, the combo ladder, the wind-up telegraph, damage through `_lose_life()` and `TRACK CLEARED`. Four decisions are recorded. **Being early on the correct note is noise, not a wrong note** (§6) — the previous draft had two penalties and no rule for choosing between them, and the case that decides it is the player who identifies the right target and is fractionally ahead of the window; timing errors are already paid for by the tier ladder, and charging twice teaches hesitation. **Front-most and in-window are separate decisions in that order** (§8.3), because collapsing them lets a shot pass through a matching front drone that is fractionally early and kill the one behind it. **The round length comes from the track** (§2, as stated but not implemented) — a four-wave track runs 48 s against the shell's default 30 s timer, so `TRACK CLEARED` would almost never have fired; the track is now built in `_load_round_settings()`, which runs before the shell reads `round_duration`. And **the rules live outside `gameplay.gd`** (§9.1): `GameShell` uses autoload instances and so can never be named by a headless test, so `EncounterDirector`, `RustyClanky` and `DmjTrackBuilder` touch no autoload and `encounter_test.gd` drives the shipping rules rather than a copy. Enemy art is deliberately **flat placeholder rectangles** (§8.4). One real bug is recorded because the tests caught it: `is_finished()` asked whether any drone existed rather than any *targetable* drone, so a corpse still fading out claimed the track was still running. Both round-end paths were then verified against the real scene rather than only unit-tested — an autoplay run clears 14 of 14 drones for 3645 points, and a pacifist run that never plays a note takes exactly three hits and ends at `lives 0`. |
| 10 | **Phantom notes fixed; the onset rule now requires an attack** (§4.4, §9.1, §9.8, §13). Reported symptom: with a real acoustic guitar the game emitted a stream of notes nobody played — high, quiet, low-confidence, arriving after the player stopped. Two further faults behind it. First, a *changed pitch* was on its own enough to fire an onset; that is false for a microphone, because a string sheds energy from its fundamental fastest and the estimator eventually starts naming the second harmonic instead. Second, the trailing average was left to converge after an onset and spent five hops reading like an ongoing attack, which held the hysteresis disarmed and made a fast run lose its second note. An absolute noise margin was added on top of the two ratio tests. A legato exception was written, measured, found to readmit the phantoms it was written beside, and removed — a hammer-on is a quiet attack, not an absent one. Playing-technique scenarios moved to `tests/playing_techniques_test.gd` and every one is now run a second time over room tone *louder than the calibration*. |
| 9 | **The onset rule was rebuilt against real playing** (§4.4, §13). Reported symptom: a live acoustic guitar that had worked in the tuner stopped registering notes in the game. It was not the new input stack — the router forwards faithfully — it was the onset rule, which had been tuned on isolated plucks separated by silence and had never been asked to handle the two things a player does constantly: striking a ringing string again, and changing note before the last one dies. Four faults, each now recorded with its cause: the threshold was set for notes starting from silence; the trailing average followed the signal fast enough to absorb the very transient it was the reference for; loudness was tested two hops late, after the transient had passed; and an attack fired before the ~46 ms analysis window had moved past the *previous* note, so one pluck became two onsets and the first carried the wrong note name. The rule now tests loudness against both the trailing average **and** a rolling trough, latches the verdict across the hops the pitch needs to settle, freezes the average during a transient, and refuses to fire until the window-straddle has passed. Thresholds were **swept against the whole scenario set**, not chosen. Eight playing techniques are now permanent tests, and the one that pins everything is the held note that must fire exactly once — a decaying string's own beating comes within a few percent of a genuine tremolo attack, so sensitivity and false-positive resistance had to be solved together. Two risk-register changes: the milestone-1 risk "onsets were tuned on synthetic attacks" is marked **fired**, since it predicted this failure precisely, and a new one replaces it — **the tuner is not the game**: it draws voiced hops, gameplay reacts to onsets, and a real instrument looked perfect in the tuner for weeks while two thirds of re-strikes were being dropped. |
| 8 | **The input stack is finished** (§4.1, §4.2, §4.5, §12 milestone 2). `NoteEvent`, `NoteSource`, all three sources and `NoteRouter` shipped; `gameplay.gd` now talks only to the router and cannot tell a guitar from a MIDI keyboard from the `A` key. Four decisions are recorded in §4.1: a failed source **stays attached** so it can say why, and losing the microphone no longer stalls a round because the other sources are independent; **latency compensation belongs to the source**, since the measured round trip is a fact about the microphone and applying it to MIDI would push those notes early by the width of the window they are judged against; **duplicates merge across sources but never within one**, because a re-struck string is the thing the game is listening for; and the router gained a **gate**, because before it only the microphone was quiet during the soundcheck and a MIDI note would have scored during a countdown the player could not see. Two risks retired against real hardware: `InputEvent.device` **is** populated (§4.2, §13 — an MPK mini reported `device = 0`), and MIDI velocity is usable data (0.06–0.53 in ordinary playing). The self-test tone moved from `T` to **`F2`**, because `T` is F♯ once a piano is on the keyboard (§4.5). Added `input_check.tscn` (§9.1), which is how the device question was answered and how a player checks their gear before a set. No new framework touchpoints: every file is game-owned. |
| 7 | **Latency calibration ships** (§4.6, §9.1, §12 milestone 3): `ui/calibration.tscn` plays a metronome, matches what the player plays against it, and stores the result in `user://dead_metal_jam.cfg`. Four decisions are recorded because three of them contradict what this document previously said. The metronome click is **broadband noise, not a tone** — a tonal click is a note, and the game would confidently measure its own audio. Notes are dated on the **audio clock, not the frame clock**, because a frame's worth of smear is most of a ±60 ms budget. The stored figure is the **median, not the mean** (§4.6 said mean), because eight beats is a small sample and one fumble moves a mean past the tolerance being established. And the detector's own delay is a **measured constant, not a formula**, because a window turns voiced at roughly a third full — two formula-derived versions were written and both failed the test against reality. Latency also **left the settings menu** (§9.4): it is measured, not preferred, and must not travel with a settings profile to a machine with a different sound card. One framework touchpoint was added (§9.5, row 13) — an `instructions_player_one_controls` key, because the solo control card hardcoded "Mouse or arrow keys" and this game's instructions screen was describing controls that do not exist. New risk (§13): **no export templates are installed**, so no build can currently be produced — found on purpose now rather than on deadline night. Also added `OnsetLog` (§9.1): `-- --log` on the tuner dumps per-hop RMS, the trailing average it was judged against and the stable-hop count, which is the measurement the "tuned on synthetic attacks" risk has been waiting for since milestone 1. |
| 6 | **The game is in the menu.** `game.gd`, `gameplay.gd` and the inherited `gameplay.tscn` landed, so Dead Metal Jam is a real catalogued game: it calls a note, listens, and scores hits and misses by pitch class (any octave counts). Audio plumbing was extracted to `MicCapture` and is now shared with a standalone tuner scene (§9.1), and a **self-test tone** was added because the machine this was built on has no working microphone — §4.3 gained the reason the obvious dead-mic guard does not work. Integration cost two framework findings: `_begin_first_round()` **must** start a round, so the soundcheck now holds the countdown instead of delaying the round (§4.6); and `instructions_video_test.gd` demanded a walkthrough clip from every game even though the screen already supports going without one, which made adding any game require recording a video first (§9.5, row 12). Milestones 2 and 4 are part-done (§12) — the framework half is finished, the content half is not. |
| 5 | Folder renamed `dead-metal-jam` → **`dead_metal_jam`** to match `desk_can_saw` and `triangle_rush`, and so the folder name matches the manifest id. All `res://` paths updated. Milestone 1 was then **executed in Godot 4.7.2 for the first time** rather than only in the Python reference port: the suite passes and the real cost is **2.2 ms per window, 10% of the hop budget** — better than the 4 ms the port predicted, so the accuracy and cost figures in §4.4 are now measurements of the shipping code. |
| 4 | **Milestone 1 built and measured**, and §4.4 rewritten to match what the code actually does rather than what was guessed. Three changes were forced by measurement: the lag range gained a semitone of headroom at each end (a guitar 30 cents flat was falling off the bottom), the peak threshold now compares *interpolated* peaks (raw comparison loses the top octave to its own harmonic), and **the octave-correction pass was removed** — it rescued nothing and broke A5/C6. DC removal became window-mean subtraction so the per-window entry point stays pure. Added the measured accuracy and cost table, marked the milestone done in §12, and retired the "too slow" risk in favour of a new one: onset thresholds are still synthetic. |
| 3 | Platform scope widened: **web and mobile are in scope, desktop ships first.** The first build is a proof of concept for a game jam, so "MVP" now means *the jam build*. Added §4.7, the platform ladder, with the per-platform input matrix and the two rules that keep the jam build from foreclosing the other targets; added the web Web-MIDI-shim and mobile touch-onset sources (§4.2, §4.5); documented the web and mobile microphone constraints (§4.3). "Web and mobile export" moved out of *Cut* and to the top of *Stretch*, with matching build-order milestones (9–10) and risk rows. |
| 2 | Rewritten against the base project as it now stands. **Lives are no longer game-owned** — `dcs_games` ships them as a shared round mode, so §7 became an integration spec (four calls) instead of a system spec, the `game/jam_lives` tunable and the game-owned lives strip were deleted, and the "no way to end a round early" friction point shrank to the `TRACK CLEARED` case (§7.4). Paths updated for the move to `godot-base/games/dead_metal_jam/`. Added §9.9, the `game.cfg` presentation config — the one sanctioned way to customise the base's colours, assets and music as more games arrive. |
| 1 | Initial design draft. |
