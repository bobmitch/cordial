# Phase 1 — Scaffold

> Mapped to the "Phases" section of `../../vst-migration-plan.md`. Phase 2
> picks up at [`ARCHITECTURE.md`](ARCHITECTURE.md#phase-2-carve-the-boundary).

## What ships

A minimal JUCE 8 MIDI-effect plugin (VST3 + AU + Standalone) that:

1. Loads Lua 5.4 in-process via sol2.
2. Reads a hardcoded C-major chord (notes, velocity, length-in-beats) from
   [`lua/host_vst.lua`](../lua/host_vst.lua).
3. Emits that chord through the plugin's MIDI-out the first time host
   transport starts (re-arms on stop).
4. Shows a tiny editor window with a one-line Lua diagnostic string.

That's it. No parameters, no UI, no presets, no Cordial music logic — those
land in phases 2–6. The goal of phase 1 is purely to prove that the build
graph and the Lua bridge work in every DAW we care about.

## Acceptance criteria

- [ ] `cmake --build` succeeds from a clean checkout on Windows (MSVC) and
      ideally macOS (Clang).
- [ ] `Cordial.vst3` is recognised by **REAPER**, **Ableton Live**, and at
      least one other host (Cubase / FL Studio / Bitwig).
- [ ] On macOS, `Cordial.component` (AU) is recognised by **Logic Pro**.
- [ ] Loading the plugin in any of the above and pressing play produces an
      audible C-E-G when routed into a synth.
- [ ] Editor window opens and shows `Lua OK: pong from Lua Lua 5.4`.
- [ ] `pluginval --strictness 5` passes against the VST3 build.

## Quick verification (Windows)

```powershell
cd plugin
pwsh -File scripts/build-windows.ps1
# Open the standalone:
build\CordialVST_artefacts\Release\Standalone\Cordial.exe
```

In the standalone, route the plugin's MIDI-out to a soft-synth (the
standalone exposes MIDI-out as a virtual port, or you can load a VSTi
inside REAPER on the same track) and hit play.

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

## Sanity checklist before declaring phase 1 done

1. Delete `plugin/build/`, rebuild from scratch, plugin still loads.
2. Open in REAPER on Windows — chord audible.
3. Open in Ableton Live on Windows — chord audible.
4. Editor diagnostic string reads `Lua OK: pong from Lua Lua 5.4`.
5. Tag the commit (`phase1-scaffold`) so phase 2 has a clean rollback point.
