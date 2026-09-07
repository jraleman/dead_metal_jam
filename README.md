# DeadMetalJam

## About

Inspired by [Typing of the Dead](https://youtu.be/Zs3M6oDcPlU?t=174),
but instead of a keyboard you use your musical instrument,
and instead of zombies, you kill some mean robots :)

Or maybe based similar to [SUPERHOT](https://www.youtube.com/watch?v=vrS86l_CtAY),
aesthetics wise.

### Standalone menu style

Running the base project with `--game=dead_metal_jam` adds an amplifier-rack
presentation: beveled steel buttons, amber focus outlines and power indicators,
condensed bold headings, a brushed-metal logo plaque, and a restrained
speaker-grille/stage-truss backdrop. Body text stays in the normal readable font.
Reduced motion keeps focus visible while stopping decorative movement.

Menu focus uses four short, non-repeating mechanical ticks with a 60 ms
cooldown. Confirmation has a footswitch clunk and muted guitar chug; Back and
Resume use a darker latch sound. These cues are generated once in
`ui/menu_sound.gd`, use the existing SFX volume/mute controls, and leave gameplay
note sounds alone. Mouse, keyboard and controller navigation share one focus cue.

The partial widget skin lives in `ui/menu_skin.gd`, with vector artwork in
`assets/ui/` and the backdrop/material resources alongside the skin. `game.gd`
declares them through optional `GameTheme` resources; collection builds and
other games keep the framework's original presentation.

### Modes

There are three modes available:


- Demo: guided beat practice; time waits for the correct note, with no damage.
- Rhythm: any note can hit, but timing is required.
- Jam: arcade shooting; correct notes connect before the enemy fires, and beat timing earns bonuses.


### Arcade firefights

Your instrument fires note-colored energy shots, automatically aimed at the matching drone
with the soonest attack deadline. Impacts distinguish **DOWN**, **PLATE HIT**,
and **MISS**; missed shots hit scenery instead of pretending to damage robots.
Enemy arm cannons return red shots toward your amplifier.

Drones quickly deploy to firing positions rather than walking toward the
camera. Filling **attack bars** show when they will shoot, without numeric
countdowns. The closing target ring and the HUD's **ON BEAT** cue show the bonus window.
Loading Bay, Turbine Hall, and Reactor Deck give each encounter a distinct
industrial setting, with room transitions instead of a scrolling treadmill.
Hits rock the armor and throw sparks; kills collapse the chassis into a burst
of debris, smoke and energy. The amplifier recoils and ejects casings, while
turbines, vent steam and electrical sparks animate the rooms. Effects are
bounded even during rapid MIDI input. Reduced motion or disabled effects keeps
static shot paths, colors and outcome markers without recoil, flashes or particles.

### Notes and armor

Every octave uses the same pitch-color mapping, shown in the HUD's color key:
**C coral, D amber, E lime, F green, G cyan, A periwinkle, B pink**. Sharps have
their own intermediate colors. Plates, targeting brackets, the called/heard
notes, input signal and successful shots share `ui/palette.gd`; letters remain
visible so recognizing a color is never required.

**Plated Knuckle always has three plates and takes three correct notes in
order.** A wrong note resets all three, as before. Older short phrases cycle
to three notes (C-E becomes C-E-C); longer phrases use their first three notes.


### Lives and the amplifier

New players start in **Lives** rounds with **3 lives**. Each robot that fires
burns out one of the HUD's amplifier tubes; cracked, crossed-out tubes are
spent, and the last powered tube is marked **LAST TUBE**. A numeric count
keeps the display readable without relying on color. Losing every tube ends
the round; clearing the track wins it.

Wrong notes never cost a life, and Demo protects the tubes. Replay restores
the full rack. **Settings > Game** still offers Timer rounds and 1-9 starting
lives, and saved choices take priority over this game's default. Other games
keep their existing default. Reduced motion disables tube animation.


## Drone artwork

The concept-based drones are drawn procedurally, with dynamic note plates.
Rusty Clanky and Plated Knuckle use the new artwork in gameplay.
Silencer Sentry and The Conductor are art previews only; their mechanics
are not enabled.

In the base Godot project, open `ui/drone_gallery.tscn` from this game folder
and run the scene with **F6** to inspect all four. The gallery can cycle
notes and plates, show charge poses, and pause animation. It also respects
the game's reduced-motion setting.

## .JAM files

Located inside the package (.jam), you will find:

- JSON (.js)
- Audio (.wav, .raw)
- Metadata (.xml)

### JSON

Define states, props, and other settings from the track.
This is the main file.

Some examples can be:

```js
{
  author: {
    name: 'John Doe',                   // Your name
    site: 'https://johndoe.github.io/', // Your website
    avatar: './assets/author.png'       // Your avatar || picture || photo || image
  }
  scale: {
    root: 'C',                          // root of the scale
    type: 'minor',                      // type of scale
    semitone: 'sharp'                   // can be either; 'sharp', 'flat' or 'none'
      ...
  }
  notes: {
    color: {
      A: '#xxxxxx',                     // La
      B: '#xxxxxx',                     // Si
      C: '#xxxxxx',                     // Do
      D: '#xxxxxx',                     // Re
      E: '#xxxxxx',                     // Mi
      F: '#xxxxxx',                     // Fa
      G: '#xxxxxx'                      // Sol
    },
    text: {
      size: 24,                         // font size
      color: '#xxxxxx'                  // text color
    },
    borderRadius: 0.5,                  // floating point, scale is:  0.1 -> 10%; 1.0 -> 100%
    ...
  },
  section: {                            // main object (defines the beats of the track)
    // here you define all the beats...
    intro: {                            // can be 'intro', 'chorus', 'bridge', 'outro', etc...
      beats: [                          // beats, notes that the player has to hit
        {                               
            time: '0:10': {             // when to start the peak of the beat
              chord: {                  // defines the chord
                position: 'III'         // So this chord is E major, relative to C# minor scale
                note: 0.25              // 1/4th note, (negra)
              },
              duration: 2.5             // duration of the beat, since 0:10 is defined as the main
                                        // time, the range starts from -1.25 to +1.25
                                        // in this example, starts from 0:08.75 -> 0:11.25
        },
          time: '0:17': {
            chord: {
              root: 'G',
              semitone: 'flat',
              type: 'minor'
            },
            duration: 2.5
        }
      }
    }
  }
  ...
}

```


### Audio

Must be a valid `.wav` or `.raw`.

### Metadata

Defined by XML, including tags and labels, such as:

```xml

<Artist>
  <Name> { ... } </Name>
  <Site> { ... } </Site>
  <Logo> { ... } </Logo>
</Artist>
<Cover imgSrc="{ ... }" />
<Year> { ... } </Year>
<Title> { ... } </Title>
<Genre> { ... } </Genre>
...

```

For references, check out 
[MusicBrainz - XML MetaData](https://musicbrainz.org/doc/MusicBrainz_XML_Meta_Data)
