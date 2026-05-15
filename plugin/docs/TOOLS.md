# Tooling — Windows install guide

Phase 1 prefers OSS where it doesn't impose obvious pain. The notes below
flag which choices are free-and-open-source vs. free-as-in-beer-but-proprietary,
so you can make a deliberate call.

## TL;DR — minimum to build

| Tool | Version | License | Notes |
|---|---|---|---|
| **Git for Windows** | latest | GPLv2 (OSS) | https://git-scm.com/download/win — or `winget install Git.Git` |
| **CMake** | ≥ 3.22 | BSD-3 (OSS) | https://cmake.org/download/ — or `winget install Kitware.CMake` |
| **Ninja** | latest | Apache-2 (OSS) | `winget install Ninja-build.Ninja` — much faster than the VS generator |
| **C++ compiler** | see below | mixed | Three options, ranked by friction |

Pull-in-at-configure-time (you don't install these — CPM fetches them):

| Library | Version | License |
|---|---|---|
| JUCE | 8.0.4 | **GPLv3 / commercial** (dual) |
| Lua | 5.4.5 | MIT |
| sol2 | 3.3.1 | MIT |
| CPM.cmake | 0.40.2 | MIT |

## C++ compiler — pick one

### Option A (recommended path of least resistance): MSVC Build Tools 2022

Free as in beer, **not** OSS (proprietary EULA, no source). This is the
toolchain JUCE is best-tested against on Windows and the path with the
fewest surprises.

Install just the build tools (no IDE, ~5–7 GB):

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools `
  --override "--passive --add Microsoft.VisualStudio.Workload.VCTools `
              --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
              --add Microsoft.VisualStudio.Component.Windows11SDK.22621"
```

After install, **open the "x64 Native Tools Command Prompt for VS 2022"**
(or run `Launch-VsDevShell.ps1` from PowerShell) before invoking `cmake`,
otherwise `cl.exe` and the Windows SDK won't be on the PATH.

### Option B (fully OSS): LLVM Clang + Windows SDK

`winget install LLVM.LLVM` gets you `clang-cl` and `clang++`. You still need
the **Windows SDK** (proprietary headers/libs from Microsoft, free download)
either from the Microsoft Store or as a standalone installer. There is no
fully-OSS alternative to the Windows SDK on Windows — every cross-platform
plugin framework on this OS depends on it.

This works with JUCE but expect occasional pthread/COM/UTF-16 paper cuts you
won't hit with MSVC. Worth it if you want the toolchain itself to be OSS,
otherwise stick with Option A.

To use Clang with the CMake build:

```powershell
cmake -S . -B build -G Ninja `
  -DCMAKE_C_COMPILER=clang-cl `
  -DCMAKE_CXX_COMPILER=clang-cl `
  -DCMAKE_BUILD_TYPE=Release
```

### Option C (not recommended): MinGW-w64

GCC for Windows, fully OSS. JUCE's Windows build assumes MSVC ABI in
several places; community patches exist but expect to babysit the
configuration. Avoid unless you have a strong reason.

## JUCE licensing — heads up

JUCE 8 is dual-licensed **GPLv3 OR commercial**. Under the GPL path:

- You **may** distribute the compiled plugin freely.
- If you distribute the plugin (source or binary) you **must** make its
  full source available under GPL terms.
- The plugin shows a small "Made with JUCE" splash unless you have a
  commercial license. We disable the splash in `CMakeLists.txt` via
  `JUCE_DISPLAY_SPLASH_SCREEN=0`, which is **only legal under the GPL
  path**. If you ever go commercial-source-closed, that define must come
  out.

Cordial today is MIT. Combining MIT music logic with GPL JUCE in a single
binary produces a GPL binary — the MIT-licensed pieces in `cordial.lua` /
`lua/` remain MIT in their source form, which is what we want.

## Optional but useful

| Tool | Purpose | License |
|---|---|---|
| **pluginval** | Validates plugin against host expectations. `winget install Tracktion.pluginval` or build from https://github.com/Tracktion/pluginval | GPLv3 (OSS) |
| **REAPER** | Free 60-day eval (effectively unlimited), great for plugin debugging | proprietary, free eval |
| **Carla** | OSS plugin host — useful for headless smoke tests | GPLv2 (OSS) |
| **Steinberg VST3 SDK validator** (`validator.exe`) | Comes bundled with VST3 SDK; JUCE pulls this in automatically | proprietary (Steinberg) |

## CI

Phase 1 has no CI configured; planned for Phase 8. The build is fully
reproducible from a clean checkout because every dependency is fetched
by CPM with a pinned tag, so a GitHub Actions matrix is mostly a matter
of installing the tools above on a `windows-latest` / `macos-latest` runner.

## Sanity check

After installing the tools above, from `plugin/`:

```powershell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

First configure takes 1–3 minutes (downloads JUCE source). Subsequent
builds are incremental. Output ends up at:

```
plugin/build/CordialVST_artefacts/Release/VST3/Cordial.vst3
plugin/build/CordialVST_artefacts/Release/Standalone/Cordial.exe
```

The standalone build is the fastest way to verify the plugin works without
involving a DAW.
