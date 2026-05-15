#pragma once

#include <sol/sol.hpp>
#include <juce_core/juce_core.h>

#include <optional>
#include <vector>

// ---------------------------------------------------------------------------
// LuaHost — owns the embedded sol::state and exposes typed helpers that the
// AudioProcessor can call. All Lua interaction must go through this class so
// that the C++ surface stays narrow and the audio thread never touches Lua.
//
// Phase 1: loads `host_vst.lua` from the embedded JUCE BinaryData and
//          exposes `getPhase1Chord()` and `ping()`. Real generation comes in
//          phase 2 once `core/` is carved out of `cordial.lua`.
// ---------------------------------------------------------------------------
class LuaHost
{
public:
    struct Chord
    {
        std::vector<int> notes;
        int velocity { 100 };
        double lengthBeats { 4.0 };
    };

    LuaHost();

    // Returns nullopt if the Lua side errored.
    std::optional<Chord> getPhase1Chord();

    // Diagnostic — round-trips a string through Lua. Useful in CI smoke tests.
    juce::String ping();

private:
    sol::state lua;
    sol::table hostModule;
    bool loaded { false };
};
