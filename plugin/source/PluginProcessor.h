#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include "LuaHost.h"

// ---------------------------------------------------------------------------
// CordialAudioProcessor — phase 3: full chord-progression generation.
//
// The LuaHost calls host_vst.lua's generate() once at construction (and
// will be called again in Phase 5 when parameters change). The resulting
// MidiEvent list is stored in beats; processBlock converts to sample offsets
// using the live BPM from the host playhead.
//
// processBlock realtime contract:
//   - Allocates nothing on the heap (note: activeNotes can grow; fixed in Phase 4)
//   - Calls no Lua
//   - Takes no locks
//   - Never blocks
// ---------------------------------------------------------------------------
class CordialAudioProcessor : public juce::AudioProcessor
{
public:
    CordialAudioProcessor();
    ~CordialAudioProcessor() override = default;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override {}
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override         { return "Cordial"; }
    bool acceptsMidi()  const override                  { return true; }
    bool producesMidi() const override                  { return true; }
    bool isMidiEffect() const override                  { return false; }
    double getTailLengthSeconds() const override        { return 0.0; }

    int  getNumPrograms() override                      { return 1; }
    int  getCurrentProgram() override                   { return 0; }
    void setCurrentProgram (int) override               {}
    const juce::String getProgramName (int) override    { return {}; }
    void changeProgramName (int, const juce::String&) override {}

    void getStateInformation (juce::MemoryBlock&) override {}
    void setStateInformation (const void*, int) override   {}

    juce::String getLuaDiagnostic() const { return luaDiagnostic; }

private:
    LuaHost luaHost;

    // Pre-generated event list (beats). Populated at construction from Lua;
    // will be regenerated in Phase 5 when parameters change.
    std::vector<LuaHost::MidiEvent> midiEvents;

    // Per-playback state — reset on every transport start.
    int     eventCursor       { 0 };
    int64_t samplesSinceStart { 0 };
    double  cachedBpm         { 120.0 };

    // Active (sounding) notes waiting for their note-off.
    // Note: std::vector may allocate; a lock-free ring replaces this in Phase 4.
    struct ActiveNote { int note, channel; int64_t noteOffSample; };
    std::vector<ActiveNote> activeNotes;

    bool wasPlaying { false };
    bool armed      { true };

    juce::String luaDiagnostic;
};
