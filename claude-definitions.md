# Definitions

Shared vocabulary for a seeded, theory-aware MIDI generator (chords / arpeggios / melody / bass). These definitions are output-format agnostic — they describe the *musical model*, not how notes get rendered (MIDI file, plugin event queue, OSC, etc.).

## Pitch & Note Conventions

- **Note name list**: 12-tone equal temperament, sharps spelling — `C, C#, D, D#, E, F, F#, G, G#, A, A#, B`. Pitch-class (pc) = note index mod 12.
- **MIDI pitch**: `(octave + 1) * 12 + note_index`. Middle C = MIDI 60 = `C4` in this convention.
- **Pitch-class set**: a `{[pc]=true}` table. Used everywhere for "is this note in the scale / in the chord."
- **Range / window**: a `[lo, hi]` MIDI pair, clamped to 0..127. Always sort/dedupe before use.

## Modes & Scales

A **mode** is a name plus a sorted list of 7 semitone offsets from the tonic (`SCALE_INTERVALS`). The canonical set:

| Mode             | Intervals (semis from root) |
|------------------|-----------------------------|
| `major`          | 0 2 4 5 7 9 11             |
| `lydian`         | 0 2 4 6 7 9 11             |
| `lydian_dom`     | 0 2 4 6 7 9 10             |
| `mixolydian`     | 0 2 4 5 7 9 10             |
| `minor` (natural)| 0 2 3 5 7 8 10             |
| `dorian`         | 0 2 3 5 7 9 10             |
| `phrygian`       | 0 1 3 5 7 8 10             |
| `locrian`        | 0 1 3 5 6 8 10             |
| `harmonic_minor` | 0 2 3 5 7 8 11             |

Each mode also has a **diatonic triad quality per degree** (`MODE_CHORDS`) — e.g. major = `maj min min maj maj min dim`. This is the "default quality" for a scale-degree in that mode.

## Chords

A **chord quality** is a name → ordered semitone-offsets-from-root list (`CHORD_INTERVALS`). Core set:

- Triads: `maj` (0,4,7), `min` (0,3,7), `dim` (0,3,6), `aug` (0,4,8)
- Power: `5` (0,7,12)
- Suspended: `sus2` (0,2,7), `sus4` (0,5,7)
- Sevenths: `maj7`, `min7`, `dom7`, `dim7`, `m7b5` (half-diminished)
- Sixths: `6` (0,4,7,9), `min6` (0,3,7,9)
- Extended: `add9`, `maj9`, `min9`, `dom9`, `7b9`

A chord is built as `root_midi + interval` for each interval; **inversions** rotate the lowest note up an octave N times.

### Voicing & Bass

- **Inversion (rotation)**: integer N, 0 = root position; N rotates the bottom N notes up an octave.
- **Slash bass**: an *added* low note specified as a key scale-degree string with optional accidental — e.g. `"3"`, `"b7"`, `"#4"`, `"5"`. Independent of inversion. This is how non-chord-tone bass notes (pedal points, F/G sus13, IV/1) are spelled.
- **Smart voicing**: when no explicit inversion/slash is set, pick the rotation that minimises total semitone motion from the previous chord, with extra weight on the soprano (top) voice and a soft penalty against drifting too far up the keyboard.

## Progressions

A **progression preset** is a flat record:

```
{ cat, name, degrees, qualities, mode, inversions? }
```

- `cat` — UI grouping label (e.g. `"Diatonic"`, `"Jazz"`, `"Modal"`).
- `name` — display string. May reference altered degrees with flat/sharp labels: `bVII`, `bII`, `#IV`, etc.
- `degrees` — array of scale-degree integers 1..7.
- `qualities` — parallel array; each entry either a chord-quality string (overrides) or nil (= follow mode default for that degree).
- `mode` — mode key from the mode list above.
- `inversions` — optional parallel array. Each entry:
  - `nil` → root position
  - integer N → Nth inversion
  - string → slash-bass spec (see above)

### Mode / Borrowed-Chord Invariant

**Critical:** chord roots resolve via `SCALE_INTERVALS[mode][degree]`. A preset label like `bVII` only renders at the actual flat-seventh root when `mode` is a mode whose 7th degree is +10 semitones (minor, dorian, phrygian, mixolydian, lydian_dom, locrian). The same applies to `bII`, `bIII`, `bVI`. The preset author chooses `mode` so the borrowed labels in the `name` come out at the right pitch; "simplifying" a preset by collapsing its mode to major will silently retune those chords.

### Recommended Preset Categories

Diatonic, Pop/Folk, Ambient, Neo-Soul, Jazz, Fusion, Gospel, Blues, Funk, Disco, Rock, Metal, EDM/Synth, Latin, Reggae, Cinematic, Game/JRPG, Modal, Classical, Custom. A `Custom` slot with empty `degrees`/`qualities` allows user-editable progressions.

## Time, Beats & Grid

- **Beats are the canonical time unit.** Quarter note = 1 beat. All internal durations, onsets, and arithmetic flow in beats. Conversion to the output format's native time unit (PPQ ticks, sample frames, seconds) happens only at emit time.
- **Time signature is read live** at the playhead / cursor each frame; do not cache across a generation pass. `num` = numerator (beats per bar), `denom` = denominator.
- **Bars → beats**: `bars * num`.

### Rate / Duration Tables

Rate options for the arpeggiator and onset grids (sorted longest → shortest, triplets interleaved at their natural pulse):

| Label   | Beats |
|---------|-------|
| `1/4`   | 1.0   |
| `1/4T`  | 2/3   |
| `1/8`   | 0.5   |
| `1/8T`  | 1/3   |
| `1/16`  | 0.25  |
| `1/16T` | 1/6   |
| `1/32`  | 0.125 |

Melody duration grid extends to longer values:

| Label  | Beats |
|--------|-------|
| `1/32` | 0.125 |
| `1/16` | 0.25  |
| `1/8`  | 0.5   |
| `1/4`  | 1.0   |
| `3/8`  | 1.5 (dotted 1/4) |
| `1/2`  | 2.0   |
| `3/4`  | 3.0 (dotted 1/2) |
| `1/1`  | 4.0   |

## Layers

The generator runs three (or four) independent layers in parallel, each on its own output channel/track, sharing the same seed, key, mode, and progression:

### Chord layer
Writes block chords at progression rate. Honours the chord's full voicing (notes + optional slash bass).

### Arp layer
Stepped chord-tone playback.
- **Chord-tone pool** drawn across `[arp_oct_low, arp_oct_high]`.
- **Pattern**: `Up`, `Down`, `Up-Down`, `Down-Up`, `Random`, `Chord` (all tones together), `Weave`, `Pedal`, `Skip`, `Down-Weave`, `Top Pedal`, `Converge`, `Skip-Reverse`, `Diverge`, `Alberti`, `Random Walk`.
- **Rate**: from the rate table above.
- **Gate**: 0..100, percentage of step length the note sustains.
- **Note probability**: per-step skip chance.
- **Beat-1 / beat-N probability** with a separate accent grid: lets the user thin out off-beats or downbeats independently.
- **Rigidity**: 0..100, snap played pitches toward chord tones when departing from them.

### Melody layer
Higher-level generator with multiple strategies plus phrase-level shaping.

**Strategy presets** (mutually exclusive):
- `Free` — wandering line within constraints.
- `Motif` — generate, develop, restate a short motivic cell.
- `Mechanical` — even subdivisions, low rhythmic variance.
- `Pedal Point` — repeated pitch with embellishment around it.
- `Call & Response` — phrase / answer pair, often contour-inverted.

**Phrasing** (layered on top of any strategy):
- `None` — strictly diatonic.
- `Bluesy` — b3, b5, b7 added to the pool; bend-like resolutions (b3→3, b5→5, b7→1).
- `Pentatonic` — pool restricted to major/minor pentatonic plus the current chord's tones. Mode-of-the-key determines which pentatonic.

**Pitch window** — `[anchor - range_down, anchor + range_up]` semitones. Anchor mode:
1. `Fixed` — tonic at a fixed octave (register independent of harmony).
2. `Chord root` — window travels with the current chord.
3. `Scale root` — tonic at the global key octave.

Asymmetric defaults (e.g. up 14 / down 7) match real lead playing: ride above the chord, dip a fifth below.

**Density / timing parameters** (all 0..100):
- `busyness` — 0 = sparse and long-held, 100 = dense clustered bursts around bar / half-bar landmarks.
- `space` — 0 = fill the bar, 100 = lots of rests, onsets pinned to quarters.
- `cadence` — 0 = free wander, 100 = textbook cadences with strong block-start / downbeat chord-tone landings.
- `metre` — 0 = any grid slot eligible for onsets, 100 = strongest beats only.
- `rhythm_rigidity` — bias each note's duration to match the onset's grid alignment (a 1/4 only starts on a 1/4 boundary, etc.).
- `colour` — chromatic passing-tone probability.

### Bass layer (optional)
Style-driven:
- `Root` — root on every chord change.
- `Root-Fifth` — alternating root/fifth.
- `Walking` — diatonic walk with chromatic-approach probability on the last beat before each chord change.
- `Boogie` — repeating pattern figure.
- `Pattern` — user-defined N-step pattern over a chosen grid; each step is one of: rest, root, fifth, octave-up.

Bass should use its own RNG stream derived from the master seed so the bass is reproducible without coupling to arp/melody random draws.

## Generation Pipeline

```
build_progression       → array of chord blocks (notes, voicing, root, duration in beats, label)
  ├─ Chord layer        → write block chords
  ├─ Arp layer          → build pool, apply pattern, step at rate, emit events
  ├─ Melody layer       → strategy-specific event stream over phrase-arc envelope
  └─ Bass layer         → style-specific event stream
                        → at emit time, convert beats → output time unit
```

Each chord block carries: `notes` (chord tones, rotated by inversion — feeds arp/melody), `voicing` (full strum including slash bass — feeds chord layer), `quality`, `degree`, `duration` (beats), `inversion`, `slash_bass`, `root_midi`, `bass_midi`, and a display `label` like `"C maj7/G"`.

## Shared Musical Helpers

These are generator-agnostic; the chord / arp / melody / bass layers all reuse them.

- **`is_chord_tone(p, chord_pcs)` / `is_scale_tone(p, scale_pcs)`** — pitch-class membership tests.
- **`chord_scale_pc_set(chord_notes, chord_root)`** — chord-aware scale: starts from the global mode, *drops* any conflicting scale tone the chord overrides (e.g. on `V7/vi` in C major, the diatonic G is dropped in favour of the chord's G#; on `Imaj7` in lydian-dominant the scale's b7 is dropped for the chord's maj7), then adds the chord's pitch-classes. Returns the merged pc set and a `differs_from_global` flag.
- **`nearest_chord_tone(p, chord_range)`** — snap to closest chord tone.
- **`voice_lead_to_chord(prev_pitch, chord_range, max_leap)`** — pick a chord tone that voice-leads from `prev_pitch`. Stepwise (≤ 2 semitones) heavily preferred, small leaps OK, large leaps penalised. Used for chord-change landings and bass landings on roots.
- **`diatonic_step(scale_notes, pitch, n)`** — move n diatonic steps (signed).
- **`diatonic_neighbor(scale_notes, pitch, ±1)`** — upper/lower neighbour.
- **`leading_tone_to(target)`** — semitone below target.

## Phrase Arc (Tension & Density Envelope)

A two-level shape that biases pitch choices and onset density across one progression cycle.

- **Cycle-level arch** — one peak per progression pass:
  - Peak position (`peak_frac`):
    - ≤ 2-chord progressions: 0.50 (symmetric).
    - Cadential (resolves to tonic): 0.55 (pulled earlier, give the descent room).
    - Long non-cadential: 0.618 (golden section).
  - `base_value` = 0.10 (start/end tension), `peak_value` = 0.85.
- **Per-phrase sub-arch** — symmetric sine peak over each ~4-bar phrase. Blended additively (`0.70 * cycle + 0.30 * phrase`) so the long-form shape dominates and you don't get HVAC-style pumping every 4 bars. Suppressed when there's only one phrase.
- **Cadence-aware descent** — when the progression resolves to the tonic, raise the post-peak curve to a power > 1 so the line settles harder into the resolution:
  - Plagal / borrowed → I: `descent_pow = 1.5`
  - V → I, V7 → I, IV → I: `strong_descent_pow = 1.8`
- **Cadence floor** — during the final (resolution) chord, clamp tension to ≤ 0.12 so the chord-tone landing rule dominates the close.

The same arch shape feeds **density**: amplitude grows with `busyness`, and during the cadence block density is multiplied by ~0.70 so the landing breathes.

## Metric Weight

Maps a grid slot to a strong/weak beat score in 0..1:

| Position                    | Weight |
|-----------------------------|--------|
| Bar downbeat                | 1.0    |
| Mid-bar (beat 3 in 4/4)     | 0.6    |
| Other whole beats           | 0.35   |
| Half-beat (off-eighth)      | 0.2    |
| Sub-beat (sixteenth etc.)   | 0.1    |

Used by:
- **Onset gating** — `metre` parameter sets a weight threshold; sub-threshold slots admit probabilistically.
- **Chord-tone landing probability** — strong beats and block starts demand a chord tone; the line is freer on weak beats.
- **Duration biasing** — longer durations are preferred on strong beats.

## Chord-Tone Landing Rule

At chord-block starts and on strong beats, the next pitch should prefer (or require) a chord tone. Probability formula:

```
p = max of:
  is_block_start          → 0.20 + 0.75 * cadence
  metric_weight ≥ 0.95    → 0.10 + 0.75 * cadence     (downbeat)
  metric_weight ≥ 0.55    → 0.05 + 0.50 * cadence     (mid-bar)
  metric_weight ≥ 0.30    →        0.30 * cadence     (whole beat)
then relaxed by tension:  p *= (1 - 0.4 * tension)
```

Cadence parameter (0..1) drives commitment to harmonic landings; tension (from the phrase arc, 0..1) lets the line climb away from the harmony before resolving.

## Grid-Quantised Placement (Drift-Free)

Express every onset and endpoint as an **integer number of grid steps** where the grid step = the minimum note duration. All arithmetic stays integer; floating point only appears when converting to beats at emit. Accumulation drift is impossible.

## Determinism & Seeded RNG

- One master `seed` integer. Same seed + same parameter set = identical output, every time. This is a *contract*, not a nicety — it lets users version-control their compositions as parameter snapshots.
- Every generator calls `rng_seed(seed)` before drawing.
- **Never bypass with raw `math.random()`** or any other unseeded entropy.
- Per-layer streams (e.g. bass) derive a sub-seed from the master via a fixed transform (`seed * 1664525 + 1013904223) mod 99991 + 1`) so that draws in one layer cannot shift another layer's output. Same-seed reproducibility is preserved.

## Live Preview

Each layer that supports live preview runs an independent state machine, ticked every UI frame, that:

1. Quantises start to the next musical boundary (bar / beat) — no mid-beat starts.
2. Emits notes via the host's live-MIDI path.
3. Caches its computed event stream until any parameter that invalidates the cache changes (key, mode, progression, durations, velocity ranges, anchor settings, etc.) — at which point it must:
   - Send all-notes-off for that layer (or hung notes will result).
   - Clear the cached event stream and rebuild on next tick.

This invariant — *every parameter that mutates output must invalidate live caches AND fire notes-off* — is the single most common source of bugs.

## Persistence

- **User-facing parameters persist per-project** (or per-preset / per-plugin-instance in a VST). Save on exit / state-chunk request; load on open / state-chunk restore.
- Maintain a `PERSIST_KEYS` list as the single source of truth for scalar parameters. Adding a new user parameter = appending its key.
- Array fields (chord durations, inversions, quality overrides, slash-bass overrides, custom degrees, bass pattern) need explicit serialise/deserialise.
- **Do not persist** live-preview state, runtime caches, RNG cursors, or UI open/collapse flags that are session-only. Only user-facing parameters belong in saved state.

## House Style — Musicality First

A real player's ear is the final arbiter. Numbers that look right on paper routinely sound wrong; algorithmic changes to the chord / arp / melody / bass generators must be auditioned before they ship. If the "correct" change produces stiff or generic output, push back and propose the musical alternative — voice leading, tensions and resolutions, idiomatic register, rhythmic phrasing. Preserve the seed contract, respect the mode chosen for each progression preset, and prefer extending the existing pipeline over adding parallel abstractions.
