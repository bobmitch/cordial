#pragma once

#include <sol/sol.hpp>
#include <juce_core/juce_core.h>

#include <optional>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// LuaHost — owns the embedded sol::state and exposes typed helpers that the
// AudioProcessor can call. All Lua interaction must go through this class.
// Post-construction the worker thread is the only caller; the audio thread
// never touches Lua.
//
// Phase 5 adds: getPresets() (called once at construction to populate the
// APVTS choice list) and updates Params to carry progressionIdx + seed.
// ---------------------------------------------------------------------------
class LuaHost
{
public:
    // -----------------------------------------------------------------------
    // Parameter struct — one snapshot per generation. Fields mirror the flat
    // table expected by host_vst.lua / core.chord.build_progression.
    // -----------------------------------------------------------------------
    struct Params
    {
        std::string      mode          { "major" };   // fallback when progressionIdx == 0
        int              rootIdx       { 1 };          // 1=C … 12=B
        int              timesigNum    { 4 };
        std::vector<int> degrees       { 1, 4, 5, 1 }; // used when progressionIdx == 0
        bool             smartVoicing  { true };
        int              progressionIdx { 1 };          // 1-based into PROGRESSIONS; 0 = manual
        int              seed          { 1 };           // RNG seed

        // Chord layer
        bool        chordEnabled  { true };
        int         chordOctave   { 4 };

        // Arp layer
        bool        arpEnabled     { false };
        std::string arpPattern     { "Up" };
        double      arpRateBeats   { 0.25 };  // 1/16 note
        int         arpOctaveLow   { 4 };
        int         arpOctaveHigh  { 5 };
        int         arpRigidity    { 0 };     // 0 = chord tones only (passed as-is to Lua)

        // Melody layer
        bool        melEnabled    { false };
        int         melPreset     { 1 };    // 1-based index into MEL_PRESETS (Lua preset_idx)
        int         melOctave     { 4 };
        int         melBusyness   { 50 };   // 0–100
        int         melCadence    { 60 };   // 0–100
    };

    // -----------------------------------------------------------------------
    // Progression preset metadata — cached at construction from the Lua
    // PROGRESSIONS catalog so the editor never needs to call Lua directly.
    // -----------------------------------------------------------------------
    struct PresetInfo
    {
        juce::String name;
        juce::String category;
    };

    // -----------------------------------------------------------------------
    // One scheduled MIDI event returned by generate(). Positions and
    // durations are in beats; the audio thread converts to samples using
    // the live BPM captured at transport start.
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

    // -----------------------------------------------------------------------
    // Called once at construction (before the worker thread starts) to
    // populate the APVTS AudioParameterChoice list.
    // -----------------------------------------------------------------------
    std::vector<PresetInfo> getPresets();

    // -----------------------------------------------------------------------
    // Called by the worker thread to build the event list for the current
    // parameter snapshot. Returns empty on Lua error.
    // -----------------------------------------------------------------------
    std::vector<MidiEvent> generate (const Params& params);

    // Diagnostic — round-trips a string through Lua. Safe to call from the
    // main thread before the worker has started.
    juce::String ping();

private:
    sol::state lua;
    sol::table hostModule;
    bool loaded { false };
};
