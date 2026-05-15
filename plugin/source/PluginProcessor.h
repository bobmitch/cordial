#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include "LuaHost.h"

// ---------------------------------------------------------------------------
// CordialAudioProcessor — phase 1 scaffold.
//
// MIDI-effect plugin. The audio thread runs no Lua and allocates nothing in
// `processBlock`; the cached chord notes are fetched from Lua during
// construction (and on resume) and copied into a small POD vector that
// `processBlock` reads.
//
// Behaviour: when the host transport starts, the next time playback crosses
// the bar-1 boundary (ppq 0) we emit C-E-G (sourced from host_vst.lua). On
// the bar-2 boundary we emit the matching note-offs. Stop + restart re-arms.
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
    // Reported as a normal Fx (not a pure MIDI effect) so REAPER's audio
    // chain isn't broken when Cordial is inserted before a synth.
    bool isMidiEffect() const override                  { return false; }
    double getTailLengthSeconds() const override        { return 0.0; }

    int  getNumPrograms() override                      { return 1; }
    int  getCurrentProgram() override                   { return 0; }
    void setCurrentProgram (int) override               {}
    const juce::String getProgramName (int) override    { return {}; }
    void changeProgramName (int, const juce::String&) override {}

    void getStateInformation (juce::MemoryBlock&) override {}
    void setStateInformation (const void*, int) override   {}

    // Exposed for the editor's diagnostic readout.
    juce::String getLuaDiagnostic() const { return luaDiagnostic; }

private:
    LuaHost luaHost;
    std::vector<int> chordNotes;     // populated once from Lua, then read-only
    int              chordVelocity { 100 };
    double           chordLengthBeats { 4.0 };

    bool wasPlaying     { false };
    bool armed          { true };    // re-armed on transport stop
    bool chordOn        { false };
    int  samplesUntilOff { 0 };      // > 0 while the chord is sounding

    juce::String luaDiagnostic;
};
