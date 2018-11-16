# DeadMetalJam

## About

Inspired by [Typing of the Dead](https://youtu.be/Zs3M6oDcPlU?t=174),
but instead of a keyboard you use your musical instrument,
and instead of zombies, you kill some mean robots :)

### Modes

There are three modes available:


- Demo     (use metronome, stop time 'til user hits the beat)
- Rythm    (notes pitch are irrelevant)
- Jam      (standard)


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
