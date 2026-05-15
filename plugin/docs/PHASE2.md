# Phase 2 — Carve the boundary

> Mapped to the "Phases" section of `../../vst-migration-plan.md`. Phase 3
> picks up at [`ARCHITECTURE.md`](ARCHITECTURE.md#where-phase-n-adds-code)
> once the entire core surface is host-agnostic.

## Goal

Split the original `cordial.lua` into:

- **`plugin/lua/core/`** — host-agnostic music engine (data tables,
  progressions, RNG, chord/arp/bass/melody generation). No `reaper.*`
  calls, no UI references. Consumed by *both* the REAPER product and the
  VST plugin.
- **`plugin/lua/host_reaper.lua`** — REAPER-specific glue: `state` table,
  ReaImGui UI, live preview via `reaper.StuffMIDIMessage`, MIDI item
  writer, project persistence.
- **`plugin/lua/host_vst.lua`** — thin adapter that the C++ shim talks to.
  Will pull `core/` modules via `package.preload` populated from JUCE
  `BinaryData`.

`cordial.lua` at the repo root becomes a **generated artifact** assembled
by `plugin/scripts/bundle-cordial.lua` from `core/*.lua` + `host_reaper.lua`.
Existing REAPER users keep loading a single file; the bundler header
flags it as auto-generated so nobody edits it by hand.

## Bundler mechanics

Each core module is a normal Lua module that ends with `return M`. The
bundler wraps each module body in an IIFE so its return value lands in
a top-level local:

```lua
local theory = (function()
  -- contents of plugin/lua/core/theory.lua
  local M = {}
  M.NOTE_NAMES = { ... }
  return M
end)()
```

`host_reaper.lua` then has a short import block at the top that aliases
the module exports back to bare locals, so the rest of the REAPER code
reads identically to the pre-phase-2 file:

```lua
local NOTE_NAMES       = theory.NOTE_NAMES
local CHORD_INTERVALS  = theory.CHORD_INTERVALS
-- ... etc ...
```

This keeps the diff at each sub-commit tight — only the extracted
section moves, the rest stays put.

## Sub-commit plan

One module per commit. Each commit produces a bundled `cordial.lua` that
must still load cleanly in REAPER and produce **byte-identical** MIDI
output for a fixed seed + parameter set against the previous build.

| Sub | Module | Status | Notes |
|---|---|---|---|
| 2a | `core/theory.lua` | ✅ shipped | `NOTE_NAMES`, `CHORD_INTERVALS`, `MODE_*`, `SCALE_INTERVALS`, `mode_idx_by_name` |
| 2b | `core/progressions.lua` | ⏳ next | The `PROGRESSIONS` catalog |
| 2c | `core/rng.lua` | ⏳ | `rng_seed` and any seeded helpers |
| 2d | `core/chord.lua` | ⏳ | `build_chord`, `build_progression`, voicing helpers |
| 2e | `core/arp.lua` | ⏳ | `build_arp_pool`, `apply_arp_pattern`, `build_arp_events` |
| 2f | `core/bass.lua` | ⏳ | Bass generator (lines ~3042-3192 in old `cordial.lua`) |
| 2g | `core/melody.lua` | ⏳ | Phrase arc, metric weight, voice leading, all `mel_*` generators, `MEL_GEN_FNS`. Biggest piece. |
| 2h | `core/init.lua` + `host_vst.lua` wiring | ⏳ | Public surface; plugin embeds modules via JUCE `BinaryData` and `package.preload` |

## Verification per sub-commit

1. `lua plugin/scripts/bundle-cordial.lua` — bundle succeeds.
2. `luac -p cordial.lua` — bundled file parses.
3. Load `cordial.lua` in REAPER, set a fixed seed, render chord/arp/melody
   at a known progression — output should be identical to the pre-extraction
   build.
4. Commit + push; mark the row above as shipped.

## Files involved

- `plugin/scripts/bundle-cordial.lua` — the bundler
- `plugin/lua/core/*.lua` — source modules (grows each sub-commit)
- `plugin/lua/host_reaper.lua` — REAPER glue (shrinks each sub-commit)
- `cordial.lua` (repo root) — **generated**, do not hand-edit

## What does NOT change in Phase 2

- The VST plugin's behaviour. It still emits a hardcoded C-major chord
  from the existing `host_vst.lua` until sub 2h wires the core in.
- The REAPER UI. ReaImGui layout, presets, and parameter ranges all
  stay where they are.
- The seed contract. Determinism must hold — same seed + same params →
  identical output before and after each extraction.
