# cordial

A REAPER script (Lua) for generating chord progressions, arpeggios, and melodies directly into your project. Provides a ReaImGui UI with live MIDI preview and configurable theory, rhythm, and humanization controls.

## Features

- **Chord progressions** across 9 modes (Major, Minor, Dorian, Phrygian, Lydian, Lydian Dom, Mixolydian, Locrian, Harmonic Minor) with built-in presets grouped by style: Diatonic, Ambient, Neo-Soul, Jazz, Gospel, Cinematic, Modal, plus Custom.
- **Chord qualities**: maj, min, maj7, min7, dom7, dim, dim7, aug, sus2, sus4, maj9, min9, add9, with per-slot quality overrides and inversions.
- **Arpeggiator** with patterns (Up, Down, Up-Down, Down-Up, Random, Chord), selectable rates (1/4 – 1/32, including 1/16T), octave range, step probability, and rigidity.
- **Melody generator** with 8 generation presets:
  - Free, Flowing, Structured, Conversational, Mechanical, Phrase & Answer, Fractal, Motif
  - Controls for rigidity, chromatic colour (passing tones), min/max note duration, metric beat-placement weighting, and a busyness slider that drives note density along an arc — high values cluster shorter notes around bar/half-bar landmarks.
- **Live preview** of chords, arpeggios, and melody while editing parameters.
- **Deterministic seeds** for reproducible generation, plus a randomise button.
- Writes results as MIDI items on dedicated tracks, respecting the project's time signature at the cursor.

## Requirements

- [REAPER](https://www.reaper.fm/)
- ReaImGui extension (install via [ReaPack](https://reapack.com/))

## Installation

1. Install ReaImGui through ReaPack.
2. Copy `cordial.lua` into your REAPER scripts folder (or any location).
3. In REAPER: **Actions → Show action list → Load…** and select `cordial.lua`.
4. Optionally bind it to a shortcut or toolbar button.

## Usage

Run the action to open the Chord Generator window. Choose a key, mode, and progression preset (or build a custom one), then enable/configure the chord, arpeggio, and melody layers. Use **Live Preview** to audition changes; write the result to commit MIDI items at the edit cursor.

## License

[MIT](LICENSE) © 2026 bobmitch
