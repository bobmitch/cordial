# Cordial VST

Cross-DAW port of `cordial.lua`. Embeds Lua 5.4 inside a JUCE 8 MIDI-effect
plugin so the existing REAPER script and the new VST/AU share one music
engine.

This directory is everything related to the plugin build. The REAPER script
(`../cordial.lua`) stays where it is and is unaffected by anything in here.

## Status

**Phase 1 — Scaffold.** Builds a "hello plugin" that loads in any VST3/AU
host and emits a hardcoded C-major chord (sourced from
[`lua/host_vst.lua`](lua/host_vst.lua) via sol2) when transport starts.

See [`docs/PHASE1.md`](docs/PHASE1.md) for what's done and how to verify.
See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the directory layout
and where future phases plug in.

## Quick start (Windows)

Install the tools listed in [`docs/TOOLS.md`](docs/TOOLS.md). Then from a
**x64 Native Tools Command Prompt for VS 2022** (or any shell where
`cl.exe` and `cmake` are on the PATH):

```powershell
cd plugin
pwsh -File scripts/build-windows.ps1
```

That fetches JUCE, Lua, and sol2 via CPM into `build/`, then compiles a
`Cordial.vst3` under `build/CordialVST_artefacts/Release/VST3/`. Copy it
to `%CommonProgramW6432%\VST3\` (typically `C:\Program Files\Common Files\VST3\`)
or point your DAW at the build output directly.

## Quick start (macOS / Linux)

```bash
cd plugin
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Repo layout

```
plugin/
├── CMakeLists.txt          top-level build
├── cmake/CPM.cmake         dependency fetcher bootstrap
├── source/                 C++ shim (AudioProcessor, Editor, LuaHost)
├── lua/                    Lua scripts embedded into the plugin binary
│   └── host_vst.lua        phase-1 stub; phase 2 grows this + adds core/
├── docs/                   migration notes (read these first)
│   ├── TOOLS.md            install guide — Windows + OSS preferences
│   ├── PHASE1.md           what shipped in phase 1
│   └── ARCHITECTURE.md     directory map for future phases
└── scripts/                build helpers
```
