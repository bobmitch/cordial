# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`cordial` is a single-file REAPER script (`cordial.lua`, ~3000 lines of Lua) that generates chord progressions, arpeggios, and melodies as MIDI items, with a ReaImGui UI and live MIDI preview while editing parameters. It depends on REAPER and the ReaImGui extension (installed via ReaPack); there is no build, package manager, or test runner.

## Running / Iterating

- Load the script in REAPER: **Actions → Show action list → Load…** and select `cordial.lua`. Re-running the action reloads the file.
- There is no CLI, no test suite, no linter configured. "Testing" a change means running it inside REAPER and listening — UI feedback (Live Preview toggles for Chords / Arp / Melody) is the primary verification loop.
- Syntax-check without REAPER: `luac -p cordial.lua` (catches parse errors only; nothing in the script can be exercised outside REAPER because everything calls `reaper.*` or `reaper.ImGui_*`).

## Architecture

Everything lives in `cordial.lua`. The file is organized top-to-bottom as a pipeline; section banners (`-- ====` and `-- ----`) mark each stage. Read in this order:

1. **Music theory tables** (top): `NOTE_NAMES`, `CHORD_INTERVALS`, `MODE_CHORDS`, `MODE_NAMES`/`MODE_DISPLAY`, `SCALE_INTERVALS`. These are the source of truth — chord roots resolve via `SCALE_INTERVALS[mode][degree]`, so adding a borrowed-chord progression only renders correctly if the preset's `mode` field actually flats that degree (see the comment block above `PROGRESSIONS`).
2. **`PROGRESSIONS` catalog**: a flat array of presets, each `{cat, name, degrees, qualities, mode}`. `qualities[i] = nil` means "follow mode default"; a string overrides for that slot. `cat` drives the grouped UI dropdown.
3. **`state` table** (~line 335): single global mutable struct holding every UI value, RNG seed, live-preview bookkeeping, and per-slot chord overrides. Almost every function reads/writes `state` directly — it is the de facto API between the UI and the generators.
4. **Generation pipeline**: `build_progression` → per-chord `build_chord` → optional layers:
   - **Chord layer**: writes block chords directly.
   - **Arp layer** (`build_arp_pool` → `apply_arp_pattern` → `build_arp_events`): pool of chord tones across `arp_octaves`, pattern (Up/Down/UpDown/Random/Chord) applied, then stepped at `arp_rate`.
   - **Melody layer**: dispatch table `MEL_GEN_FNS` (~line 1779) maps preset index → one of `mel_free`, `mel_flowing`, `mel_structured`, `mel_conversational`, `mel_mechanical`, `mel_phrase_answer`, `mel_fractal`, `mel_motif`. All of them ultimately fill blocks via the shared `mel_fill_block` and the helpers in the **Phrase Arc** (tension/density envelope), **Metric Weight** (beat-strength scoring), and **Voice Leading / Diatonic Step** sections. Chromatic passing tones flow through `maybe_insert_colour`; `apply_rigidity` snaps notes back toward chord tones.
5. **Live preview**: three parallel state machines (`live_preview_tick` for chords, `arp_live_tick`, `mel_live_tick`) driven each frame from `loop()`. They send raw MIDI via `reaper.StuffMIDIMessage`; `reset_live` and the `*_notes_off` helpers must be called whenever a parameter that invalidates the cached event stream changes — forgetting this leaves hung notes.
6. **MIDI write** (`write_all` ~line 2265): finds/creates dedicated tracks (`get_or_create_track`) and emits MIDI items at the edit cursor honouring the project time signature (`get_timesig_at_cursor`).
7. **UI** (`draw_ui` ~line 2538): one big ImGui function. Helper widgets: `combo`, `combo_grouped` (used with the `*_ITEMS` arrays just above `draw_ui`), `sslider`. The main loop is `reaper.defer(loop)` at the bottom.

Key cross-cutting invariants:

- **Determinism**: every generator reseeds via `rng_seed(state.seed)` so the same seed + same parameters produces identical output. Don't introduce `math.random()` calls that bypass this.
- **Beats, not seconds**: durations flow as beats throughout; PPQ conversion happens only at MIDI write time using `state.ppq_per_beat`.
- **Time signature is read live** at the cursor/playhead each frame — don't cache it across the generation pipeline.
- **Per-project persistence** (`PROJECT STATE PERSISTENCE` section, ~line 477): scalar `state` fields are saved/loaded via `reaper.SetProjExtState` using the `PERSIST_KEYS` list as the single source of truth. When adding a new scalar field that should persist, append its key to `PERSIST_KEYS`. Array fields need explicit serialization/deserialization added to `save_proj_state` / `load_proj_state`. Do not add live-preview or runtime bookkeeping fields to either — only user-facing parameters belong there.

## House style — musicality first

This project exists to produce music that a real player would want to hear. When in doubt, optimise for the sound, not the code.

- **Be the smartest, most musical voice in the room.** Bring real theory: voice leading, tensions and resolutions, idiomatic register, rhythmic phrasing. If a "correct" change would produce stiff or generic output, push back and propose the musical alternative.
- **Listen before shipping.** Algorithmic changes to the melody/arp/chord generators must be auditioned in REAPER. Numbers that look right on paper routinely sound wrong; if you can't audition a change yourself, say so explicitly rather than claiming success.
- **Preserve the seed contract.** Reproducibility is a feature — same seed, same notes. Any new randomness threads through the seeded RNG helpers.
- **Respect existing musical idioms in `PROGRESSIONS`.** Each preset's `mode` was chosen so borrowed-chord labels (bVII, bII, etc.) actually render at the right pitch. Don't "simplify" by collapsing modes.
- **Clean code, but not at music's expense.** Prefer editing the existing pipeline over adding parallel abstractions. The file is long but linear; keep new helpers near the section they belong to and follow the existing banner style. No speculative interfaces, no scaffolding for features nobody asked for.
