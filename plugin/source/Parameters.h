#pragma once

#include <array>

// ---------------------------------------------------------------------------
// Parameters — IDs and compile-time tables used by both PluginProcessor
// (for APVTS construction and makeParams()) and PluginEditor (for
// SliderAttachment / ComboBoxAttachment wiring).
// ---------------------------------------------------------------------------
namespace Params
{
    // Parameter identifiers — single source of truth; never hardcode strings
    // elsewhere in the C++ codebase.
    inline constexpr const char* Root         = "root";
    inline constexpr const char* Preset       = "preset";
    inline constexpr const char* Octave       = "octave";
    inline constexpr const char* Seed         = "seed";
    inline constexpr const char* SmartVoicing = "smart_voicing";

    // Mirrored from core/theory.lua so C++ can map int indices to names
    // without calling Lua after the worker has started. Must be kept in
    // sync with theory.MODE_NAMES and theory.NOTE_NAMES.
    inline constexpr std::array<const char*, 12> NOTE_NAMES {
        "C","C#","D","D#","E","F","F#","G","G#","A","A#","B"
    };

    // rootIdx (Lua, 1-based) = paramValue (APVTS, 0-based) + 1
    // So: Root choice index 0 → C → root_idx = 1 in Lua.
    inline constexpr int NOTE_COUNT = 12;

    inline constexpr int OCTAVE_MIN = 3;
    inline constexpr int OCTAVE_MAX = 6;
    inline constexpr int OCTAVE_DEFAULT = 4;

    inline constexpr int SEED_MIN     = 1;
    inline constexpr int SEED_MAX     = 9999;
    inline constexpr int SEED_DEFAULT = 1;
}
