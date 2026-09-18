#!/usr/bin/env python3
"""Authors the two generated note charts, with optional archival audio rendering.

`assets/demo.ogg` is a recording the author holds the rights to. Tracks 02 and
03 are not recordings: they are synthesised here, and this file is the only
place they exist as anything but bytes. Re-running it reproduces both.

**The song and the chart come out of the same data.** A chart is a promise
about when the player must play, and the one way to be sure the promise lands
on the music is to never write the two down twice. `SONGS` below is the single
source of truth: `render()` turns a section's beats into an audible lead line,
and `write_chart()` turns the very same beats into `JamBeat.time`. They cannot
drift, because there is nothing to drift from.

Beat positions are written in *beats*, not seconds, for the same reason: the
grid is the tempo, so a chart authored this way is on the bar by construction
rather than by measurement. `DESIGN.md` §10 records what the alternative cost.

Gameplay has no backing music. Charts never reference the optional audio files.

Usage:
    python tools/make_tracks.py            # writes chart/charts/ only
    python tools/make_tracks.py --audio    # also renders archival audio
    python tools/make_tracks.py --verify   # checks committed charts
    python tools/make_tracks.py --audio --verify  # also checks archival audio

Needs NumPy; ffmpeg is used only with --audio. Nothing in the game runs this
authoring tool.
"""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
import wave
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

SAMPLE_RATE = 44100
GAME_DIR = Path(__file__).resolve().parent.parent
ASSETS = GAME_DIR / "assets"
CHARTS = GAME_DIR / "chart" / "charts"
RES_PREFIX = "res://games/dead_metal_jam"

# Ogg Vorbis, mono, VBR. The bed is a wall of guitar and drums; stereo and a
# higher rate would double the committed bytes for something nobody is going to
# hear over their own instrument.
OGG_BITRATE = "80k"


# --------------------------------------------------------------------------
# Song description
# --------------------------------------------------------------------------


@dataclass
class Beat:
    """One charted demand, positioned on the grid in beats from bar one."""

    beat: float
    note: int
    notes: list[int] = field(default_factory=list)
    lane: int = -1
    enemy: str = "rusty_clanky"

    def phrase(self) -> list[int]:
        return self.notes if self.notes else [self.note]


@dataclass
class Section:
    name: str
    archetype: str
    beats: list[Beat]


@dataclass
class Part:
    """One stretch of the *arrangement*: how the band plays, and for how long.

    Sections are what the game stages from; parts are what the song does. They
    overlap for the charted half of a track and then the song carries on alone,
    because a bed has to outlast the chart written over it by a wide margin
    (`jam_chart_test.gd` insists on thirty seconds).
    """

    bars: int
    chords: list[int]
    intensity: str  # "sparse" | "drive" | "heavy" | "halftime" | "outro"


@dataclass
class Song:
    stem: str
    title: str
    artist: str
    bpm: float
    sections: list[Section]
    arrangement: list[Part]
    lead_octave: int = 12
    seed: int = 7


# Both tracks stay inside a guitar's open position: every charted note is
# reachable in first position on a standard-tuned guitar, and matching is by
# pitch class anyway, so a bass or a keyboard can take any of them where it
# sits best (§4.4, §8.3).

# A minor. The slow one: a heavy stomp with a real bridge in the middle of it.
A2, C3, D3, E3, G3, A3 = 45, 48, 50, 52, 55, 57
AM, F2, G2 = 45, 41, 43

TRACK_02 = Song(
    stem="track_02",
    title="Scrapyard Stomp",
    artist="DeskCanSaw",
    bpm=100.0,
    sections=[
        Section(
            "INTRO",
            "walk_in",
            [
                Beat(0, A2),
                Beat(6, E3),
                Beat(12, C3),
                Beat(18, G3),
            ],
        ),
        Section(
            "VERSE",
            "march",
            [
                Beat(24, A2),
                Beat(28, C3),
                Beat(32, D3, enemy="silencer_sentry"),
                Beat(36, E3),
                Beat(40, D3),
            ],
        ),
        Section(
            "CHORUS",
            "press",
            [
                Beat(44, A3),
                Beat(47, G3),
                Beat(50, E3, notes=[E3, C3], lane=1, enemy="plated_knuckle"),
                Beat(53, D3),
                Beat(56, C3),
                Beat(59, A2),
            ],
        ),
        Section(
            "BRIDGE",
            "hold",
            [
                Beat(64, A2, notes=[A2, C3, E3], lane=1, enemy="plated_knuckle"),
                Beat(72, D3),
                Beat(80, G3, notes=[G3, E3], lane=1, enemy="plated_knuckle"),
            ],
        ),
        Section(
            "OUTRO",
            "press",
            [
                Beat(88, A2),
                Beat(91, C3),
                Beat(94, D3),
                Beat(97, E3),
                Beat(100, G3),
                Beat(103, A3, notes=[A3, G3, E3, A2], enemy="conductor"),
            ],
        ),
    ],
    arrangement=[
        Part(6, [AM, AM, F2, G2], "sparse"),
        Part(5, [AM, AM, F2, G2], "drive"),
        Part(5, [AM, F2, G2, AM], "heavy"),
        Part(6, [AM, AM, F2, F2], "halftime"),
        Part(5, [AM, F2, G2, AM], "heavy"),
        Part(8, [AM, AM, F2, G2], "drive"),
        Part(8, [AM, F2, G2, AM], "heavy"),
        Part(8, [AM, AM, F2, G2], "drive"),
        Part(12, [AM, F2, G2, AM], "outro"),
    ],
)

# E minor. The fast one: the same shape at two thirds of the time, and one more
# section, so the ladder from track to track is pace rather than trickery.
E2, G2b, A2b, B2, D3b, E3b = 40, 43, 45, 47, 50, 52
EM, C2, D2 = 40, 36, 38

TRACK_03 = Song(
    stem="track_03",
    title="Overdrive",
    artist="DeskCanSaw",
    bpm=168.0,
    sections=[
        Section(
            "INTRO",
            "walk_in",
            [
                Beat(0, E2),
                Beat(6, B2),
                Beat(12, G2b),
                Beat(18, D3b),
            ],
        ),
        Section(
            "VERSE",
            "march",
            [
                Beat(24, E2),
                Beat(28, G2b),
                Beat(32, A2b, enemy="silencer_sentry"),
                Beat(36, B2),
                Beat(40, A2b),
                Beat(44, G2b),
            ],
        ),
        Section(
            "CHORUS",
            "press",
            [
                Beat(48, E3b),
                Beat(51, D3b),
                Beat(54, B2, notes=[B2, G2b], lane=1, enemy="plated_knuckle"),
                Beat(57, A2b),
                Beat(60, G2b),
                Beat(63, E2),
            ],
        ),
        Section(
            "BRIDGE",
            "hold",
            [
                Beat(72, E2, notes=[E2, G2b, B2], lane=1, enemy="plated_knuckle"),
                Beat(80, A2b),
                Beat(88, E3b, notes=[E3b, B2], lane=1, enemy="plated_knuckle"),
            ],
        ),
        Section(
            "SOLO",
            "march",
            [
                Beat(96, B2),
                Beat(100, D3b),
                Beat(104, E3b, enemy="silencer_sentry"),
                Beat(108, D3b),
                Beat(112, B2),
                Beat(116, A2b),
            ],
        ),
        Section(
            "OUTRO",
            "press",
            [
                Beat(120, E2),
                Beat(123, G2b),
                Beat(126, A2b),
                Beat(129, B2),
                Beat(132, D3b),
                Beat(135, E3b),
                Beat(138, B2),
                Beat(141, E2, notes=[E2, G2b, B2, E2], enemy="conductor"),
            ],
        ),
    ],
    arrangement=[
        Part(6, [EM, EM, C2, D2], "sparse"),
        Part(6, [EM, EM, C2, D2], "drive"),
        Part(6, [EM, C2, D2, EM], "heavy"),
        Part(6, [EM, EM, C2, C2], "halftime"),
        Part(6, [EM, C2, D2, EM], "drive"),
        Part(8, [EM, EM, C2, D2], "heavy"),
        Part(12, [EM, EM, C2, D2], "drive"),
        Part(12, [EM, C2, D2, EM], "heavy"),
        Part(12, [EM, EM, C2, D2], "drive"),
        Part(16, [EM, C2, D2, EM], "heavy"),
        Part(16, [EM, EM, C2, D2], "outro"),
    ],
    seed=19,
)

SONGS = [TRACK_02, TRACK_03]


# --------------------------------------------------------------------------
# Synthesis
# --------------------------------------------------------------------------


def hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def add(buffer: np.ndarray, start: float, chunk: np.ndarray) -> None:
    """Mixes `chunk` into `buffer` at `start` seconds, clipped to the end."""
    begin = int(start * SAMPLE_RATE)
    if begin < 0:
        chunk = chunk[-begin:]
        begin = 0
    end = min(begin + chunk.size, buffer.size)
    if end <= begin:
        return
    buffer[begin:end] += chunk[: end - begin]


def decay(length: int, tau: float, attack: float = 0.004) -> np.ndarray:
    t = np.arange(length) / SAMPLE_RATE
    envelope = np.exp(-t / tau)
    rise = int(attack * SAMPLE_RATE)
    if rise > 1:
        envelope[:rise] *= np.linspace(0.0, 1.0, rise)
    return envelope


def saw(freq: float, length: int, partials: int = 12) -> np.ndarray:
    """Band-limited sawtooth. Additive, so nothing needs a filter to be tame."""
    t = np.arange(length) / SAMPLE_RATE
    wave_out = np.zeros(length)
    for harmonic in range(1, partials + 1):
        if freq * harmonic >= SAMPLE_RATE * 0.45:
            break
        wave_out += np.sin(2.0 * np.pi * freq * harmonic * t) / harmonic
    return wave_out * (2.0 / np.pi)


def power_chord(root: float, length: int, gain: float) -> np.ndarray:
    """Root, fifth and octave through a soft clipper — a rhythm guitar.

    Distortion is what makes this sound like an instrument rather than a test
    tone, and it is also the reason the detector corpus has harmonic-rich
    waveforms in it (§4.4): the bed is exactly the kind of signal the game has
    to hear a player *through*.
    """
    voices = saw(root, length) + saw(root * 1.4983, length) * 0.8
    voices += saw(root * 2.0, length) * 0.5
    return np.tanh(voices * gain) * 0.5


def lead_note(midi: int, duration: float, amp: float) -> np.ndarray:
    """The charted note, played so the player can hear what they are being
    asked for. Slightly detuned pair plus a vibrato, so it reads as played
    rather than as a beep."""
    length = int(duration * SAMPLE_RATE)
    t = np.arange(length) / SAMPLE_RATE
    freq = hz(midi)
    vibrato = 1.0 + 0.004 * np.sin(2.0 * np.pi * 5.2 * t) * np.clip(t * 3.0, 0.0, 1.0)
    tone = np.zeros(length)
    for harmonic, weight in ((1, 1.0), (2, 0.5), (3, 0.28), (4, 0.14), (5, 0.07)):
        tone += weight * np.sin(2.0 * np.pi * freq * harmonic * t * vibrato)
    tone = np.tanh(tone * 1.6)
    return tone * decay(length, duration * 0.42, attack=0.006) * amp


def kick(amp: float) -> np.ndarray:
    length = int(0.28 * SAMPLE_RATE)
    t = np.arange(length) / SAMPLE_RATE
    sweep = 48.0 + 90.0 * np.exp(-t / 0.022)
    phase = 2.0 * np.pi * np.cumsum(sweep) / SAMPLE_RATE
    body = np.sin(phase) * decay(length, 0.09, attack=0.001)
    click = np.sin(2.0 * np.pi * 1800.0 * t) * decay(length, 0.003, attack=0.0002)
    return (body + click * 0.25) * amp


def snare(rng: np.random.Generator, amp: float) -> np.ndarray:
    length = int(0.22 * SAMPLE_RATE)
    t = np.arange(length) / SAMPLE_RATE
    noise = rng.standard_normal(length)
    # A difference is a one-line high-pass: enough to take the mud out of a
    # noise burst without pulling scipy in for one filter.
    noise = np.diff(noise, prepend=0.0)
    tone = np.sin(2.0 * np.pi * 186.0 * t) + 0.6 * np.sin(2.0 * np.pi * 331.0 * t)
    return (noise * 0.7 + tone * 0.5) * decay(length, 0.075, attack=0.001) * amp


def hat(rng: np.random.Generator, amp: float, tau: float = 0.03) -> np.ndarray:
    length = int(0.12 * SAMPLE_RATE)
    noise = rng.standard_normal(length)
    noise = np.diff(noise, prepend=0.0)
    noise = np.diff(noise, prepend=0.0)
    return noise * decay(length, tau, attack=0.0005) * amp


# How each intensity plays one bar: guitar hits on these sixteenth positions,
# and the kit follows its own row. Written out rather than derived, because a
# groove is the one thing in this file that should be legible at a glance.
PATTERNS = {
    "sparse": {
        "guitar": [0, 8],
        "guitar_gain": 2.0,
        "guitar_amp": 0.20,
        "kick": [0, 8],
        "snare": [],
        "hat": [0, 4, 8, 12],
        "bass": [0, 8],
    },
    "drive": {
        "guitar": [0, 2, 4, 6, 8, 10, 12, 14],
        "guitar_gain": 3.4,
        "guitar_amp": 0.26,
        "kick": [0, 6, 8, 14],
        "snare": [4, 12],
        "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        "bass": [0, 4, 8, 12],
    },
    "heavy": {
        "guitar": [0, 1, 2, 4, 6, 7, 8, 10, 11, 12, 14],
        "guitar_gain": 4.4,
        "guitar_amp": 0.29,
        "kick": [0, 2, 6, 8, 10, 14],
        "snare": [4, 12],
        "hat": [0, 2, 4, 6, 8, 10, 12, 14],
        "bass": [0, 2, 6, 8, 10, 14],
    },
    "halftime": {
        "guitar": [0, 6, 8],
        "guitar_gain": 4.8,
        "guitar_amp": 0.31,
        "kick": [0, 6],
        "snare": [8],
        "hat": [0, 8],
        "bass": [0, 6, 8],
    },
    "outro": {
        "guitar": [0, 2, 4, 6, 8, 10, 12, 14],
        "guitar_gain": 3.0,
        "guitar_amp": 0.24,
        "kick": [0, 8],
        "snare": [4, 12],
        "hat": [0, 4, 8, 12],
        "bass": [0, 8],
    },
}


def render(song: Song) -> np.ndarray:
    rng = np.random.default_rng(song.seed)
    seconds_per_beat = 60.0 / song.bpm
    sixteenth = seconds_per_beat / 4.0
    total_bars = sum(part.bars for part in song.arrangement)
    length = int((total_bars * 4 * seconds_per_beat + 2.0) * SAMPLE_RATE)
    buffer = np.zeros(length)

    bar = 0
    for part in song.arrangement:
        pattern = PATTERNS[part.intensity]
        for index in range(part.bars):
            bar_start = bar * 4 * seconds_per_beat
            root = part.chords[index % len(part.chords)]

            for step in pattern["guitar"]:
                at = bar_start + step * sixteenth
                held = sixteenth * (2 if step % 2 == 0 else 1)
                chunk = power_chord(
                    hz(root + 12), int(held * 1.6 * SAMPLE_RATE), pattern["guitar_gain"]
                )
                chunk *= decay(chunk.size, held * 0.6, attack=0.002)
                add(buffer, at, chunk * pattern["guitar_amp"])

            for step in pattern["bass"]:
                at = bar_start + step * sixteenth
                held = sixteenth * 2.0
                size = int(held * 1.4 * SAMPLE_RATE)
                tone = saw(hz(root - 12), size, partials=6) * 0.6
                tone += np.sin(
                    2.0 * np.pi * hz(root - 12) * np.arange(size) / SAMPLE_RATE
                )
                add(buffer, at, tone * decay(size, held * 0.7) * 0.22)

            for step in pattern["kick"]:
                add(buffer, bar_start + step * sixteenth, kick(0.85))
            for step in pattern["snare"]:
                add(buffer, bar_start + step * sixteenth, snare(rng, 0.5))
            for step in pattern["hat"]:
                add(buffer, bar_start + step * sixteenth, hat(rng, 0.12))

            bar += 1

    # The charted notes, played by the song at the instant the game asks for
    # them. This is the whole reason the chart and the bed are generated
    # together: the player is being asked to double the lead, so the lead has
    # to be there.
    for section in song.sections:
        for beat in section.beats:
            phrase = beat.phrase()
            for offset, note in enumerate(phrase):
                at = (beat.beat + offset * 0.5) * seconds_per_beat
                add(
                    buffer,
                    at,
                    lead_note(note + song.lead_octave, seconds_per_beat * 1.4, 0.30),
                )

    fade = int(3.0 * SAMPLE_RATE)
    buffer[-fade:] *= np.linspace(1.0, 0.0, fade)
    peak = float(np.max(np.abs(buffer)))
    if peak > 0.0:
        buffer *= 0.89 / peak
    return buffer


def write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())


def encode_ogg(wav_path: Path, ogg_path: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise SystemExit("ffmpeg is not on PATH; cannot encode the Ogg beds.")
    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(wav_path),
            "-ac",
            "1",
            "-c:a",
            "libvorbis",
            "-b:a",
            OGG_BITRATE,
            str(ogg_path),
        ],
        check=True,
    )


# --------------------------------------------------------------------------
# Chart emission
# --------------------------------------------------------------------------


def _tres_float(value: float) -> str:
    """Godot writes a bare integer without a decimal point; matching that keeps
    a regenerated chart from showing up as a diff of nothing but formatting."""
    rounded = round(value, 3)
    if abs(rounded - round(rounded)) < 1e-9:
        return str(int(round(rounded)))
    return f"{rounded:g}"


def chart_text(song: Song) -> str:
    seconds_per_beat = 60.0 / song.bpm
    lines: list[str] = [
        '[gd_resource type="Resource" script_class="JamChart" format=3]',
        "",
        f'[ext_resource type="Script" path="{RES_PREFIX}/chart/jam_chart.gd" id="2_chart"]',
        f'[ext_resource type="Script" path="{RES_PREFIX}/chart/jam_section.gd" id="3_section"]',
        f'[ext_resource type="Script" path="{RES_PREFIX}/chart/jam_beat.gd" id="4_beat"]',
        "",
    ]

    section_ids: list[str] = []
    for section_index, section in enumerate(song.sections):
        beat_ids: list[str] = []
        for beat_index, beat in enumerate(section.beats):
            beat_id = f"Beat_{section_index}_{beat_index}"
            beat_ids.append(beat_id)
            lines.append(f'[sub_resource type="Resource" id="{beat_id}"]')
            lines.append('script = ExtResource("4_beat")')
            seconds = beat.beat * seconds_per_beat
            if seconds != 0.0:
                lines.append(f"time = {_tres_float(seconds)}")
            lines.append(f"note = {beat.note}")
            if beat.notes:
                lines.append(
                    "notes = Array[int](["
                    + ", ".join(str(value) for value in beat.notes)
                    + "])"
                )
            if beat.lane >= 0:
                lines.append(f"lane = {beat.lane}")
            if beat.enemy != "rusty_clanky":
                lines.append(f'enemy = "{beat.enemy}"')
            lines.append("")

        section_id = f"Section_{section_index}"
        section_ids.append(section_id)
        lines.append(f'[sub_resource type="Resource" id="{section_id}"]')
        lines.append('script = ExtResource("3_section")')
        lines.append(f'name = "{section.name}"')
        if section.archetype != "march":
            lines.append(f'wave_archetype = "{section.archetype}"')
        lines.append(
            'beats = Array[ExtResource("4_beat")](['
            + ", ".join(f'SubResource("{beat_id}")' for beat_id in beat_ids)
            + "])"
        )
        lines.append("")

    lines.append("[resource]")
    lines.append('script = ExtResource("2_chart")')
    lines.append(f'title = "{song.title}"')
    lines.append(f'artist = "{song.artist}"')
    lines.append(f"bpm = {_tres_float(song.bpm)}")
    lines.append(
        'sections = Array[ExtResource("3_section")](['
        + ", ".join(f'SubResource("{section_id}")' for section_id in section_ids)
        + "])"
    )
    lines.append("")
    return "\n".join(lines)


def write_chart(song: Song) -> Path:
    path = CHARTS / f"{song.stem}.tres"
    path.write_text(chart_text(song), encoding="utf-8")
    return path


# --------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------
#
# The first version of this measured tempo by autocorrelating the onset
# envelope, the way §10 records track 01 being measured, and it was the wrong
# tool for this job twice over. It reported 82.75 BPM for a track written at
# 168 — the half-tempo an autocorrelation always has to choose between — and
# 98.5 for one written at 100, because quantising the lag to whole envelope
# frames puts the tempo resolution at nearly two BPM up there. Neither number
# was evidence of anything.
#
# It was also answering a question this file cannot get wrong. Tempo is an
# *input* here, not something to be recovered: the audio is rendered off the
# same grid the chart is written on. What is worth checking is the thing that
# would actually hurt — that the rendered audio really does put a note where
# the chart says one is. So the two checks below are both about *arrivals*.


def onset_envelope(samples: np.ndarray, hop: int = 64) -> tuple[np.ndarray, float]:
    """Rectified energy rise per frame, plus the frame rate it was taken at."""
    window = 256
    frames = (samples.size - window) // hop
    energy = np.empty(frames)
    for index in range(frames):
        chunk = samples[index * hop : index * hop + window]
        energy[index] = float(np.sqrt(np.mean(chunk * chunk)))
    flux = np.maximum(np.diff(energy, prepend=energy[0]), 0.0)
    return flux, SAMPLE_RATE / hop


def grid_alignment(samples: np.ndarray, bpm: float) -> tuple[float, float]:
    """Finds the phase of the sixteenth grid the track's attacks actually sit
    on, and how strongly they sit on it.

    The question worth asking is not "how much energy is within a few
    milliseconds of a grid line" — the answer to that is dominated by how wide
    the analysis window is, which is why the first attempt at this reported 16%
    for a track that is on the grid by construction. The question is whether
    the grid the *chart* is written on is the grid the *music* is on. So the
    phase is swept across one sixteenth and the winner is reported: a track
    whose attacks agree with its chart peaks at a phase of zero.

    Returns the winning phase in milliseconds and how many times more attack
    energy falls on that phase than on an average one.
    """
    flux, rate = onset_envelope(samples)
    sixteenth = 60.0 / bpm / 4.0
    times = np.arange(flux.size) / rate
    tolerance = sixteenth * 0.06

    steps = 96
    scores = np.empty(steps)
    for index in range(steps):
        phase = sixteenth * index / steps
        offset = np.abs(
            ((times - phase + sixteenth * 0.5) % sixteenth) - sixteenth * 0.5
        )
        scores[index] = float(flux[offset <= tolerance].sum())

    best = int(np.argmax(scores))
    phase_ms = sixteenth * best / steps * 1000.0
    # Report the phase as a signed distance from the grid line, so a track that
    # lands a hair *before* the beat does not read as almost a full sixteenth
    # late.
    if phase_ms > sixteenth * 500.0:
        phase_ms -= sixteenth * 1000.0
    concentration = float(scores[best] / scores.mean()) if scores.mean() > 0.0 else 0.0
    return phase_ms, concentration


def lead_is_audible(samples: np.ndarray, song: Song) -> tuple[int, int]:
    """Counts the charted arrivals where the charted pitch is actually playing.

    A Goertzel at the lead's own fundamental, taken across the beat and
    compared with the same bin one beat earlier. The lead line is the only
    voice in the mix at that frequency and it only sounds at charted times, so
    a beat the song does not play shows up as no rise at all.
    """
    seconds_per_beat = 60.0 / song.bpm
    window = int(seconds_per_beat * 0.5 * SAMPLE_RATE)
    heard = 0
    total = 0

    for section in song.sections:
        for beat in section.beats:
            for offset, note in enumerate(beat.phrase()):
                total += 1
                at = (beat.beat + offset * 0.5) * seconds_per_beat
                frequency = hz(note + song.lead_octave)
                during = _goertzel(samples, at, window, frequency)
                before = _goertzel(samples, at - seconds_per_beat, window, frequency)
                if during > before * 1.8:
                    heard += 1
    return heard, total


def _goertzel(samples: np.ndarray, at: float, window: int, frequency: float) -> float:
    start = int(at * SAMPLE_RATE)
    if start < 0 or start + window > samples.size:
        return 0.0
    chunk = samples[start : start + window]
    t = np.arange(window) / SAMPLE_RATE
    taper = np.hanning(window)
    real = float(np.dot(chunk * taper, np.cos(2.0 * np.pi * frequency * t)))
    imaginary = float(np.dot(chunk * taper, np.sin(2.0 * np.pi * frequency * t)))
    return math.hypot(real, imaginary) / window


def verify(song: Song) -> list[str]:
    problems: list[str] = []
    ogg = ASSETS / f"{song.stem}.ogg"
    chart = CHARTS / f"{song.stem}.tres"
    if not ogg.exists():
        return [f"{ogg.name} is missing."]
    if not chart.exists():
        return [f"{chart.name} is missing."]

    ffmpeg = shutil.which("ffmpeg")
    with tempfile.TemporaryDirectory() as work:
        decoded = Path(work) / "decoded.wav"
        subprocess.run(
            [ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", str(ogg),
             "-ac", "1", "-ar", str(SAMPLE_RATE), str(decoded)],
            check=True,
        )
        with wave.open(str(decoded), "rb") as handle:
            frames = handle.getnframes()
            raw = handle.readframes(frames)
        samples = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0

    seconds = samples.size / SAMPLE_RATE
    last_beat = max(beat.beat for section in song.sections for beat in section.beats)
    charted = last_beat * 60.0 / song.bpm
    print(f"\n  {song.stem} - {song.title}, {song.bpm:g} BPM")
    print(f"    {seconds:.1f} s of audio; last arrival at {charted:.1f} s")

    phase_ms, concentration = grid_alignment(samples, song.bpm)
    print(f"    grid phase {phase_ms:+.1f} ms, {concentration:.1f}x attack "
          f"energy on it")
    if abs(phase_ms) > 8.0:
        problems.append(
            f"{song.stem}: attacks sit {phase_ms:+.1f} ms off the chart's own grid."
        )
    if concentration < 2.0:
        problems.append(
            f"{song.stem}: attacks are only {concentration:.1f}x concentrated on the grid."
        )

    heard, total = lead_is_audible(samples, song)
    print(f"    {heard}/{total} charted notes audible in the bed")
    if heard < total:
        problems.append(
            f"{song.stem}: {total - heard} charted note(s) are not played by the song."
        )

    if seconds < charted + 45.0:
        problems.append(
            f"{song.stem}: {seconds:.1f} s of audio is too short for {charted:.1f} s of chart."
        )
    peak = float(np.max(np.abs(samples)))
    print(f"    peak {peak:.3f}")
    if peak < 0.5 or peak > 0.999:
        problems.append(f"{song.stem}: peak level {peak:.3f} is out of range.")
    return problems


# --------------------------------------------------------------------------


def build(song: Song) -> None:
    print(f"Rendering {song.title} ({song.bpm:g} BPM) ...")
    samples = render(song)
    ogg = ASSETS / f"{song.stem}.ogg"
    with tempfile.TemporaryDirectory() as work:
        wav = Path(work) / f"{song.stem}.wav"
        write_wav(wav, samples)
        encode_ogg(wav, ogg)
    size_mb = ogg.stat().st_size / (1024 * 1024)
    print(f"  -> {ogg.relative_to(GAME_DIR)} ({size_mb:.2f} MB)")

    chart = write_chart(song)
    beats = sum(len(section.beats) for section in song.sections)
    print(
        f"  -> {chart.relative_to(GAME_DIR)} "
        f"({len(song.sections)} sections, {beats} beats)"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Check committed charts; combine with --audio to measure archival recordings too.",
    )
    parser.add_argument(
        "--audio", action="store_true",
        help="Also rebuild archival audio. The game does not play these recordings.",
    )
    arguments = parser.parse_args()

    if arguments.verify:
        problems: list[str] = []
        for song in SONGS:
            chart = CHARTS / f"{song.stem}.tres"
            if not chart.is_file():
                problems.append(f"{song.stem}: chart is missing.")
            elif chart.read_text(encoding="utf-8") != chart_text(song):
                problems.append(f"{song.stem}: chart does not match its authored note grid.")
            if arguments.audio:
                problems.extend(verify(song))
        if problems:
            for problem in problems:
                print(f"FAIL: {problem}", file=sys.stderr)
            return 1
        print("Both generated charts check out." if not arguments.audio else "Charts and archival audio check out.")
        return 0

    CHARTS.mkdir(parents=True, exist_ok=True)
    for song in SONGS:
        if arguments.audio:
            ASSETS.mkdir(parents=True, exist_ok=True)
            build(song)
        else:
            print(f"Wrote {write_chart(song).relative_to(GAME_DIR)} (no backing audio).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
