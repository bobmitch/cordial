#pragma once

#include <sol/sol.hpp>
#include <juce_core/juce_core.h>

#include <optional>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// LuaHost — owns the embedded sol::state and exposes typed helpers that the
// AudioProcessor can call. All Lua interaction must go through this class so
// that the C++ surface stays narrow and the audio thread never touches Lua.
//
// Phase 3: generate(Params) calls host_vst.lua's generate() function and
//          returns a flat list of MidiEvent records (beats, not samples).
//          The processor converts beats→samples using the live BPM.
// ---------------------------------------------------------------------------
class LuaHost
{
public:
    // -----------------------------------------------------------------------
    // Parameter struct — passed into generate(). Mirrors the flat table that
    // core.chord.build_progression accepts. Phase 5 will populate this from
    // AudioProcessorValueTreeState; for now it holds hardcoded defaults.
    // -----------------------------------------------------------------------
    struct Params
    {
        std::string      mode         { "major" };
        int              rootIdx      { 1 };          // 1 = C, 2 = C#/Db, ...
        int              octave       { 4 };
        int              timesigNum   { 4 };
        std::vector<int> degrees      { 1, 4, 5, 1 }; // I-IV-V-I
        bool             smartVoicing { true };
    };

    // -----------------------------------------------------------------------
    // One scheduled MIDI event. Positions and durations are in beats so the
    // audio thread can convert to samples using the live BPM each block.
    // -----------------------------------------------------------------------
    struct MidiEvent
    {
        double posBeats  { 0.0 };
        int    note      { 60 };
        int    velocity  { 100 };
        double durBeats  { 4.0 };
        int    channel   { 1 };
    };

    LuaHost();

    // Build a flat event list from core.chord (and eventually arp/melody).
    // Safe to call from any non-audio thread. Returns an empty vector on error.
    std::vector<MidiEvent> generate(const Params& params);

    // Diagnostic — round-trips a string through Lua. Useful in CI smoke tests.
    juce::String ping();

private:
    sol::state lua;
    sol::table hostModule;
    bool loaded { false };
};
