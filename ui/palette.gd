class_name DmjPalette
extends RefCounted

## Cold steel, warm stage lights, and a separate colour for the input signal.
const INK := Color("080e12")
const PANEL := Color("111c22")
const STEEL := Color("1d3038")
const LINE := Color("35505a")
const TEXT := Color("f4eddd")
const MUTED := Color("a5b9bc")
const AMBER := Color("ffc86a")
const SIGNAL := Color("70d6cb")
const DANGER := Color("ff4964")

## Pitch classes C through B. Octaves share colors; letters remain authoritative.
const NOTE_COLORS: Array[Color] = [
	Color("ff8d84"), Color("ffa778"), Color("ffc66a"), Color("e7d976"),
	Color("d9ef7b"), Color("86e0a4"), Color("69dfca"), Color("77d6ff"),
	Color("88b5ff"), Color("aeabff"), Color("d9a0fa"), Color("f39ecb"),
]


static func note_color(note: int) -> Color:
	return NOTE_COLORS[posmod(note, 12)] if note >= 0 else MUTED
