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
    inline constexpr const char* Seed         = "seed";
    inline constexpr const char* SmartVoicing = "smart_voicing";

    // Chord layer
    inline constexpr const char* ChordEnabled = "chord_enabled";
    inline constexpr const char* ChordOctave  = "chord_octave";

    // Arp layer
    inline constexpr const char* ArpEnabled    = "arp_enabled";
    inline constexpr const char* ArpPattern    = "arp_pattern";
    inline constexpr const char* ArpRate       = "arp_rate";
    inline constexpr const char* ArpOctaveLow  = "arp_oct_low";
    inline constexpr const char* ArpOctaveHigh = "arp_oct_high";
    inline constexpr const char* ArpRigidity   = "arp_rigidity";

    // Melody layer
    inline constexpr const char* MelEnabled   = "mel_enabled";
    inline constexpr const char* MelPreset    = "mel_preset";
    inline constexpr const char* MelOctave    = "mel_octave";
    inline constexpr const char* MelBusyness  = "mel_busyness";
    inline constexpr const char* MelCadence   = "mel_cadence";

    // Mirrored from core/theory.lua so C++ can map int indices to names
    // without calling Lua after the worker has started. Must be kept in
    // sync with theory.MODE_NAMES and theory.NOTE_NAMES.
    inline constexpr std::array<const char*, 12> NOTE_NAMES {
        "C","C#","D","D#","E","F","F#","G","G#","A","A#","B"
    };

    // rootIdx (Lua, 1-based) = paramValue (APVTS, 0-based) + 1
    // So: Root choice index 0 → C → root_idx = 1 in Lua.
    inline constexpr int NOTE_COUNT = 12;

    inline constexpr int OCTAVE_MIN     = 3;
    inline constexpr int OCTAVE_MAX     = 6;
    inline constexpr int OCTAVE_DEFAULT = 4;

    inline constexpr int SEED_MIN     = 1;
    inline constexpr int SEED_MAX     = 9999;
    inline constexpr int SEED_DEFAULT = 1;

    // Arp pattern names — parallel with AudioParameterChoice indices 0..8.
    inline constexpr std::array<const char*, 9> ARP_PATTERNS {
        "Up","Down","Up-Down","Down-Up","Chord","Random","Weave","Pedal","Alberti"
    };

    // Arp rate display labels and corresponding beat values.
    // Triplet values: 1/4T = 2/3 beat, 1/8T = 1/3, 1/16T = 1/6, 1/32T = 1/12.
    inline constexpr std::array<const char*, 8> ARP_RATES {
        "1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T"
    };
    inline constexpr std::array<double, 8> ARP_RATE_BEATS {
        1.0, 2.0/3.0, 0.5, 1.0/3.0, 0.25, 1.0/6.0, 0.125, 1.0/12.0
    };

    inline constexpr int ARP_OCT_MIN     = 2;
    inline constexpr int ARP_OCT_MAX     = 7;
    inline constexpr int ARP_OCT_LOW_DEF = 4;
    inline constexpr int ARP_OCT_HIGH_DEF= 5;

    // Melody strategy presets — parallel with mel_preset AudioParameterChoice.
    // Indices 1-based in Lua; APVTS stores 0-based.
    inline constexpr std::array<const char*, 5> MEL_PRESETS {
        "Free", "Motif", "Mechanical", "Pedal Point", "Call & Response"
    };
}
