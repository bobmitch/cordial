# VST Migration Plan

Turning `cordial.lua` into a cross-DAW VST/AU plugin while keeping the existing
REAPER script alive from the same codebase.

## Approach: embed Lua inside a JUCE plugin

The REAPER-specific surface area in `cordial.lua` is small and well-isolated.
Everything that matters musically — `PROGRESSIONS`, `build_progression`,
`build_chord`, the arp pipeline, the eight melody generators in `MEL_GEN_FNS`,
the phrase arc / metric weight / voice leading helpers — is pure data
manipulation. It ports cleanly without rewriting.

Rather than rewriting ~3000 lines of musical logic in C++, we keep the
generator core in Lua and wrap it in a thin JUCE shim. One codebase ships as
**both** a REAPER script and a VST/AU plugin.

### Why this is workable (and not exotic)

The usual objection to Lua in audio plugins is GC pauses or JIT hitches inside
`processBlock` at sub-millisecond budgets. That concern **does not apply here**:

- Cordial is a MIDI generator. No DSP runs in the audio thread.
- Generation cadence is per-bar / on parameter change, not per-buffer.
- Standard architecture: worker thread runs Lua, pushes timestamped events to a
  lock-free queue, audio thread is a dumb pump that emits events whose
  timestamp falls in the current buffer. No Lua, no allocation, no locks in
  `processBlock`.

Precedents for embedded Lua in audio products: Renoise (entire scripting
layer, commercial since ~2009), Reaper itself (host-side), Wwise and FMOD
(game audio middleware), Protoplug (open-source JUCE + LuaJIT), several VCV
Rack modules.

### What is REAPER-bound and must be replaced

| REAPER concept | VST equivalent |
|---|---|
| `reaper.StuffMIDIMessage` live preview | Plugin's normal MIDI-out during host playback |
| MIDI item creation at edit cursor | Realtime emission + drag-out MIDI file |
| `reaper.SetProjExtState` persistence | VST state chunk |
| Time signature at cursor | `juce::AudioPlayHead::getPosition()` |
| ReaImGui UI | ImGui-in-JUCE (mirrors current layout) |

The conceptual shift: a VST is realtime, so "edit cursor + write items" becomes
"plugin continuously emits notes from current transport position." The live
preview tick state machines in `cordial.lua` are already 90% of this; live and
"render" paths unify into a single playback engine, which is a net code
reduction.

## Stack

| Concern | Pick | Rationale |
|---|---|---|
| Plugin framework | **JUCE 8** via CMake (not Projucer) | Dominant ecosystem, huge AI training corpus, first-class VST3/AUv3, modern CMake API |
| Lua runtime | **Lua 5.4** (vendored, ~250KB) | Simpler than LuaJIT, no Apple Silicon caveats, generator workload nowhere near JIT-relevant |
| Lua/C++ bridge | **sol2** (header-only) | Modern C++, by far the best docs, AI handles it fluently |
| UI | **ImGui-in-JUCE** (`melatonin_imgui` or similar) for v1 | Mirrors ReaImGui layout 1:1; can rewrite as native `juce::Component` later for polish |
| Build | **CMake + CPM.cmake** | Reproducible, CI-friendly, one-line dependency fetches |
| Formats | **VST3 + AUv3** | Covers every DAW that matters; AAX skipped unless Pro Tools is a target |
| CI | GitHub Actions (macOS + Windows), `pluginval`, `auval` | Catches host-compat issues before users do |

## Phases

### 1. Scaffold *(scaffolded — see [`plugin/`](plugin/))*
CMake JUCE project, sol2 + Lua 5.4 vendored via CPM, "Hello plugin" that emits
a hardcoded C-major chord on bar 1. Verify it loads in Reaper, Ableton, Logic.

> Code: [`plugin/source/`](plugin/source/) · Build: [`plugin/CMakeLists.txt`](plugin/CMakeLists.txt) ·
> Phase notes: [`plugin/docs/PHASE1.md`](plugin/docs/PHASE1.md) ·
> Tooling: [`plugin/docs/TOOLS.md`](plugin/docs/TOOLS.md) ·
> Layout & invariants: [`plugin/docs/ARCHITECTURE.md`](plugin/docs/ARCHITECTURE.md)

### 2. Carve the boundary
Split `cordial.lua` into:

- `core/` — music theory tables, `build_progression`, `build_chord`,
  arp/melody generators, RNG. Host-agnostic, no `reaper.*` calls.
- `host_reaper.lua` — current REAPER glue (keeps the script working for
  existing users).
- `host_vst.lua` — thin module that wraps `core/` for the C++ shim.

Highest-leverage step: once `core/` is host-agnostic, both products consume it
and bug fixes / new presets land in both simultaneously.

### 3. C++ ↔ Lua shim
sol2 binds parameter struct → Lua. Lua returns array of
`{tick, note, vel, len, channel}` events. One generation call per bar, off
the audio thread.

### 4. Threading
`juce::AbstractFifo` of MIDI events between worker thread and `processBlock`.
Audio thread allocates nothing, calls no Lua. Worker re-runs generators when
parameters change or transport approaches the next bar boundary.

### 5. Parameters & state
- Core scalars (key, mode, tempo, density, rigidity, seed, etc.) →
  `juce::AudioProcessorValueTreeState` so DAWs see them as automatable.
- Full state table (slot overrides, etc.) → serialized to VST chunk via
  Lua → JSON → `juce::MemoryBlock`.

### 6. UI port
ImGui inside a JUCE editor component. Lift `draw_ui` into C++ widget calls;
reuse the same parameter names. The three live-preview state machines
(`live_preview_tick`, `arp_live_tick`, `mel_live_tick`) disappear — the
plugin's normal MIDI-out replaces them.

### 7. Drag-out MIDI
`juce::DragAndDropContainer` so users can still "commit a phrase to my
timeline" — preserves the REAPER workflow for non-realtime use.

### 8. Validation
`pluginval --strictness 10`, `auval -v`, then manual smoke test in Reaper,
Ableton, Logic, Cubase, FL Studio.

## Invariants to preserve across the port

These are non-negotiable and already documented in `CLAUDE.md`:

- **Determinism.** Same seed + same parameters → identical output. All
  randomness threads through the seeded RNG. Lua-side helpers stay; the
  C++ shim must not introduce its own `rand()` calls.
- **Beats, not seconds.** Durations remain in beats inside `core/`; PPQ /
  sample conversion happens only at the C++ boundary.
- **Time signature read live** from the host playhead each generation cycle,
  not cached.
- **Mode integrity.** Each preset's `mode` was chosen so borrowed-chord
  labels resolve to the right pitch via `SCALE_INTERVALS[mode][degree]`. The
  port must not collapse modes for "simplicity."

## Where AI assistance is strong vs. weak

**Strong (lean on it):** CMake config, JUCE boilerplate, sol2 bindings,
parameter wiring, ImGui layouts, MIDI event arithmetic, format-specific
quirks (e.g., AUv3 MIDI processor entitlements).

**Weak (must be owned by a human):** realtime correctness (no allocation
or locks in `processBlock`), musical regression testing (does the new path
*sound* the same?), per-DAW behavioural quirks that only show up when the
plugin is loaded in that host.

## Effort estimate

Focused, AI-assisted developer who already knows the codebase:

- **~2–4 weeks of evenings** to a first usable build (phases 1–5).
- **~2–4 weeks more** for UI polish, drag-out MIDI, and DAW-specific fixups.

## Open questions before kickoff

1. Do we ship the drag-out MIDI workflow in v1, or rely purely on realtime
   emission and let users record the plugin's output?
2. AUv3 on iPad — included in scope or desktop-only first?
3. Native JUCE UI vs ImGui-in-JUCE long-term — decide before phase 6 or
   defer until after v1 ships?
