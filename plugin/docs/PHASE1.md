# Phase 1 — Scaffold

> Mapped to the "Phases" section of `../../vst-migration-plan.md`. Phase 2
> picks up at [`ARCHITECTURE.md`](ARCHITECTURE.md#phase-2-carve-the-boundary).

> **Status: shipped.** First successful end-to-end run in REAPER on
> Windows confirmed C-E-G playback through a downstream VSTi with the
> Lua bridge active.

## What ships

A minimal JUCE 8 stereo-Fx plugin (VST3 + AU + Standalone) that:

1. Loads Lua 5.4 in-process via sol2.
2. Reads a hardcoded C-major chord (notes, velocity, length-in-beats) from
   [`lua/host_vst.lua`](../lua/host_vst.lua).
3. Passes audio and MIDI through unchanged, and on top of that emits the
   chord on the first transport-start (re-arms on stop).
4. Shows a tiny editor window with a Lua diagnostic that includes the
   parsed note count, e.g. `Lua OK (3 notes): pong from Lua Lua 5.4`.

That's it. No parameters, no UI, no presets, no Cordial music logic — those
land in phases 2–6. The goal of phase 1 is purely to prove that the build
graph and the Lua bridge work in every DAW we care about.

## Acceptance criteria

- [x] `cmake --build` succeeds on Windows (MSVC 2022 + Ninja, CMake 4.x).
- [x] `Cordial.vst3` recognised by **REAPER** and emits audible chord through
      a downstream VSTi on the same track.
- [x] Editor shows `Lua OK (3 notes): pong from Lua Lua 5.4`.
- [ ] Recognised by at least one other host (Ableton / FL / Cubase / Bitwig).
- [ ] On macOS, `Cordial.component` (AU) is recognised by **Logic Pro**.
- [ ] `pluginval --strictness 5` passes against the VST3 build.

## Quick verification (Windows)

```powershell
cd plugin
pwsh -File scripts/build-windows.ps1
```

Then in REAPER:

1. New track → insert **Cordial** in the FX chain.
2. Insert **ReaSynth** (or any VSTi) **after** Cordial in the same chain.
3. Press play.

Expected: C-E-G held for one bar through ReaSynth. The standalone build
(`Cordial.exe`) is also produced but its transport semantics are
JUCE-specific and not a substitute for a DAW smoke test.

## Files touched

```
plugin/
├── CMakeLists.txt           dependency graph, plugin target
├── cmake/CPM.cmake          dependency fetcher
├── source/
│   ├── PluginProcessor.{h,cpp}   transport detection + MIDI emission
│   ├── PluginEditor.{h,cpp}      placeholder window
│   └── LuaHost.{h,cpp}           sol2 wrapper, the only file that touches Lua
└── lua/host_vst.lua         phase-1 stub returning the chord
```

## Gotchas resolved during Phase 1

Everything below was hit on the first real Windows build — captured so
future phases (and future agents) don't rediscover the same potholes.

### 1. CMake 4.x removes legacy `cmake_minimum_required` floors

**Symptom:** Configure fails with
`Compatibility with CMake < 3.5 has been removed from CMake. ... Update the
VERSION argument <min> value.`, fingering `build/_deps/lua-src/CMakeLists.txt`.

**Cause:** The `walterschell/Lua` CMake wrapper still declares an old
`cmake_minimum_required`. CMake 4.x rejects this outright instead of
warning. Affects any transitive dependency that hasn't bumped its floor.

**Fix:** [`CMakeLists.txt`](../CMakeLists.txt) sets
`CMAKE_POLICY_VERSION_MINIMUM 3.5` near the top, which is the
shim CMake itself recommends. Harmless on older CMake (the variable
is simply unread).

### 2. sol2 range-based-for on a Lua sequence yields nothing

**Symptom:** Editor reads `Lua OK: pong from Lua Lua 5.4`, plugin loads,
but no MIDI is ever generated.

**Cause:** Range-based `for (auto& kv : sol::table)` uses `pairs()`
semantics. For a Lua *sequence* (`{60, 64, 67}`) sol2 v3's iterator
isn't guaranteed to enumerate the array part, so the parse silently
produces an empty `std::vector<int>`. The "Lua OK" string was gated only
on the optional being non-empty, not on the inner vector having entries.

**Fix:** Use the canonical `ipairs`-style idiom in
[`LuaHost.cpp`](../source/LuaHost.cpp): walk integer indices through
`sol::optional<int>` until the first invalid slot. Additionally surfaced
the parsed note count in the editor diagnostic (`Lua OK (3 notes): ...`)
and added a fallback that flags `[empty notes → using C++ fallback]` if
the vector ever comes back empty again — so this class of failure is
visible at a glance instead of silent.

### 3. `IS_MIDI_EFFECT TRUE` breaks audio chains in REAPER

**Symptom:** Cordial loads and Lua diagnostic is green, but inserting it
into a track's FX chain silences both audio and MIDI for every plugin
after it. With Cordial bypassed, the chain works normally.

**Cause:** `IS_MIDI_EFFECT TRUE` in JUCE declares **zero audio buses**.
REAPER can't route audio through a 0-in/0-out plugin, so everything
downstream goes silent. Several other hosts have related quirks.

**Fix:** Ship as a normal stereo Fx that *also* produces MIDI — the
universal pattern Scaler / Cthulhu / RapidComposer etc. use. Concretely:

- [`CMakeLists.txt`](../CMakeLists.txt): drop `IS_MIDI_EFFECT TRUE`,
  keep `NEEDS_MIDI_INPUT/OUTPUT TRUE`.
- [`PluginProcessor.h`](../source/PluginProcessor.h):
  `isMidiEffect() -> false`; add `isBusesLayoutSupported`.
- [`PluginProcessor.cpp`](../source/PluginProcessor.cpp): constructor
  declares stereo in/out buses; `processBlock` no longer clears audio
  or MIDI — both pass through and our chord is added on top.

The "right" REAPER workflow for Cordial is therefore **same-track,
in front of a synth** (Cordial → ReaSynth on the same FX chain), not
a MIDI track-send to a separate VSTi track. Cross-track sends still
work but require extra send configuration that's easy to get wrong.

### 4. REAPER caches plugin descriptors aggressively

**Symptom:** After rebuilding, the editor still shows the old
diagnostic string format. New code clearly compiled, but REAPER
loads stale behaviour.

**Cause:** REAPER caches scanned plugins per session. Just rebuilding
the `.vst3` and reopening a project doesn't pick up changes to the
plugin's bus layout / `isMidiEffect` reporting; only the binary
contents change, while the descriptor stays cached.

**Fix:** After a rebuild that changes plugin metadata, in REAPER:
**remove the FX instance from the chain**, then
**Options → Preferences → Plug-ins → VST → Re-scan**, then re-add.
Behaviour changes that only touch `processBlock` are picked up
automatically on the next play.

## Threading notes for future phases

`processBlock` already follows the realtime contract that phase 4 will
formalise:

- No allocations.
- No Lua calls.
- All chord data is cached in plain `std::vector<int>` populated once during
  construction.

Phase 4 (`AbstractFifo` of MIDI events between a worker thread and
`processBlock`) is the natural next step — the worker thread re-runs Lua
on parameter changes and pushes timestamped events into the FIFO. Phase 1
leaves the worker out because there's nothing to schedule yet beyond a
single chord, but the boundary is already in the right place.

## Known gaps (intentional, deferred)

| Gap | Picked up in |
|---|---|
| No parameters, no automation | Phase 5 |
| No state persistence (VST chunk) | Phase 5 |
| No real Cordial generation | Phase 2 (carve `core/`) + Phase 3 (sol2 binding) |
| No drag-out MIDI | Phase 7 |
| No CI | Phase 8 |
| No ImGui UI — just a JUCE label | Phase 6 |
| Trigger fires only once per transport start (no bar-by-bar generation) | Phase 4 |

## Sanity checklist before declaring phase 1 fully done

1. [x] Delete `plugin/build/`, rebuild from scratch, plugin still loads.
2. [x] Open in REAPER on Windows, same-track FX chain → chord audible.
3. [ ] Open in one of Ableton / FL / Cubase / Bitwig on Windows → chord audible.
4. [ ] Open in Logic Pro on macOS via AU → chord audible.
5. [x] Editor diagnostic shows `Lua OK (3 notes): pong from Lua Lua 5.4`.
6. [ ] `pluginval --strictness 5 plugin\build\...\Cordial.vst3` passes.
7. [ ] Tag the commit (`phase1-scaffold`) so phase 2 has a clean rollback point.
