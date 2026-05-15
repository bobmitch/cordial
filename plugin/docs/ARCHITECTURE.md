# Architecture — where things live (and where Phase N puts new things)

Cross-reference for anyone (human or AI) opening the `plugin/` directory
mid-migration. Reads alongside `../../vst-migration-plan.md`.

## The two products, one engine

```
  cordial.lua  ──┐                                 ┌──>  REAPER script (today)
                 ├──>  core/ (host-agnostic Lua) ──┤
  plugin/lua  ──┘                                  └──>  VST/AU plugin (this dir)
```

`core/` does not exist yet — Phase 2 creates it by carving the music logic
out of `cordial.lua`. Until then, `plugin/lua/host_vst.lua` is a stub.

## Directory map

```
plugin/
├── CMakeLists.txt        # juce_add_plugin + CPM dependencies
├── cmake/
│   └── CPM.cmake         # dependency fetcher bootstrap
├── source/               # C++ — the JUCE shim, nothing musical lives here
│   ├── PluginProcessor.{h,cpp}
│   │   # AudioProcessor. Owns LuaHost. processBlock is realtime-clean:
│   │   # no allocations, no Lua, no locks. Phase 4 introduces an
│   │   # AbstractFifo between a worker thread and this file.
│   ├── PluginEditor.{h,cpp}
│   │   # GUI. Phase 1: a label. Phase 6: ImGui-in-JUCE mirroring
│   │   # the current ReaImGui layout.
│   └── LuaHost.{h,cpp}
│       # The ONLY file that includes <sol/sol.hpp>. Every Lua call goes
│       # through a typed C++ method here. Keeps the C++ ↔ Lua boundary
│       # in exactly one place, which is what Phase 3 expands.
├── lua/                  # Lua, embedded as binary data into the plugin
│   ├── host_vst.lua      # phase 1 stub. Phase 2 wires it to require core/.
│   ├── host_reaper.lua   # REAPER glue: UI, MIDI item writer, live preview,
│   │                     # project persistence. Source of truth — every edit
│   │                     # to the REAPER product happens here, NOT in the
│   │                     # generated repo-root cordial.lua.
│   └── core/             # host-agnostic music engine, carved out of the
│                         # original cordial.lua during phase 2. Each file
│                         # is a Lua module (`local M = {}; ... return M`).
│       ├── theory.lua    # ✅ extracted (phase 2a)
│       ├── progressions.lua  # 🚧 phase 2b
│       ├── rng.lua       # 🚧 phase 2c
│       ├── chord.lua     # 🚧 phase 2d
│       ├── arp.lua       # 🚧 phase 2e
│       └── melody.lua    # 🚧 phase 2f
├── scripts/
│   ├── build-windows.ps1     # plugin build helper
│   └── bundle-cordial.lua    # regenerates repo-root cordial.lua from
│                             # core/*.lua + host_reaper.lua. Each core
│                             # module is wrapped in an IIFE so its
│                             # `return M` lands in a top-level local;
│                             # host_reaper.lua aliases the exports back
│                             # to bare locals so the REAPER code reads
│                             # unchanged.
└── docs/                 # phase notes — start here when picking work up
    ├── TOOLS.md          # install guide
    ├── PHASE1.md         # what shipped in phase 1
    ├── PHASE2.md         # carve plan + per-module status
    └── ARCHITECTURE.md   # this file
```

The repo-root `cordial.lua` is **auto-generated**. To change REAPER
behaviour, edit `plugin/lua/host_reaper.lua` (or the relevant
`plugin/lua/core/*.lua`) and re-run the bundler:

```bash
lua plugin/scripts/bundle-cordial.lua
```

The bundler stamps a "DO NOT EDIT BY HAND" header on `cordial.lua` so
the constraint is obvious to anyone (human or agent) opening it.

## Where Phase N adds code

| Phase | Concern | Files that change |
|---|---|---|
| 2 | Carve `core/` out of `cordial.lua` | new `plugin/lua/core/*.lua`; `cordial.lua` becomes a thin REAPER host wrapping `core/` (via `package.path` shim or copy-on-build); `plugin/lua/host_vst.lua` `require`s `core` |
| 3 | C++ ↔ Lua shim | `source/LuaHost.{h,cpp}` grows typed bindings: parameter struct → Lua, event list → C++ |
| 4 | Threading | new `source/EventQueue.{h,cpp}` (`juce::AbstractFifo`); worker thread owned by `PluginProcessor` |
| 5 | Parameters & state | `source/Parameters.{h,cpp}` (`AudioProcessorValueTreeState`); `getStateInformation` serializes Lua state via JSON |
| 6 | UI port | replace `PluginEditor` with ImGui-in-JUCE; add `external/melatonin_imgui` (or chosen wrapper) via CPM |
| 7 | Drag-out MIDI | `source/DragSource.{h,cpp}` using `juce::DragAndDropContainer` |
| 8 | Validation / CI | `.github/workflows/build.yml`; invokes `pluginval` and `auval` |

## Invariants the C++ side must respect

Lifted from `../../CLAUDE.md` and `../../vst-migration-plan.md`:

1. **Determinism.** All randomness threads through Cordial's seeded RNG in
   Lua. Do not call `std::rand`, `juce::Random`, or any C++ RNG from a path
   that affects musical output.
2. **Beats, not seconds.** `core/` speaks beats. The C++ side converts to
   samples using the live playhead BPM at the moment of generation.
   `LuaHost::Chord::lengthBeats` is the canonical example.
3. **Live time signature.** Read `juce::AudioPlayHead::PositionInfo` on
   every generation cycle. Never cache the time signature across blocks.
4. **Mode integrity.** Don't collapse a preset's `mode` field "for
   simplicity" when binding presets to C++ — borrowed-chord labels rely
   on `SCALE_INTERVALS[mode][degree]` resolving to the right pitch.

## Realtime contract for `processBlock`

Anything new added to `processBlock` must pass all of:

- Allocates nothing on the heap.
- Calls no Lua.
- Takes no locks.
- Never blocks (no file I/O, no waits).

Generation runs on the worker thread (Phase 4 onwards). The audio thread
only pumps pre-computed events from a `juce::AbstractFifo`.

## Why Lua is embedded as BinaryData, not a sidecar file

Plugin formats (VST3, AU) install as opaque bundles that DAWs may move,
sandbox, or copy. Loading a Lua file from disk at runtime invites the
same path-resolution pain that drove every other plugin to embed its
resources. JUCE's `juce_add_binary_data` does the right thing on every
platform.

The cost is a rebuild every time a Lua source changes. That's a fine
tradeoff for a generator plugin; if iteration speed becomes painful in
Phase 6+, add a developer-only "load Lua from disk" mode behind a
preprocessor flag.
