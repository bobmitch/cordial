#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include <atomic>
#include <functional>
#include <vector>

#include "EventQueue.h"
#include "LuaHost.h"
#include "Parameters.h"

// ---------------------------------------------------------------------------
// CordialAudioProcessor — phase 5: APVTS parameters + state persistence.
//
// Parameter → generation data flow:
//   DAW automation / UI control
//     → APVTS parameter change
//       → parameterChanged() listener
//         → worker.requestRegeneration()
//           → GeneratorWorker::regenerate() reads makeParams()
//             → LuaHost::generate() → EventQueue
//               → processBlock emits sample-accurate MIDI
//
// State save/recall: APVTS handles XML round-trip for all registered
// parameters via getStateInformation / setStateInformation.
// ---------------------------------------------------------------------------
class CordialAudioProcessor : public juce::AudioProcessor,
                              private juce::AudioProcessorValueTreeState::Listener
{
public:
    CordialAudioProcessor();
    ~CordialAudioProcessor() override;

    void prepareToPlay  (double sampleRate, int samplesPerBlock) override;
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

    // APVTS handles the XML round-trip for all registered parameters.
    void getStateInformation (juce::MemoryBlock& destData) override;
    void setStateInformation (const void* data, int sizeInBytes) override;

    juce::String getLuaDiagnostic() const;
    juce::AudioProcessorValueTreeState& getAPVTS() { return apvts; }

    // Preset name cache — built at construction from Lua; read-only after
    // that so the editor can access it safely on the message thread.
    const std::vector<LuaHost::PresetInfo>& getPresetInfos() const { return presetInfos; }

private:
    // --- APVTS parameter layout (built before worker starts) ----------------
    static juce::AudioProcessorValueTreeState::ParameterLayout
    buildParameterLayout (const std::vector<LuaHost::PresetInfo>& presets);

    // Translates current APVTS values into a Lua-ready Params snapshot.
    // Thread-safe: reads only atomics.
    LuaHost::Params makeParams() const;

    // AudioProcessorValueTreeState::Listener
    void parameterChanged (const juce::String& parameterID, float newValue) override;

    // -----------------------------------------------------------------------
    // GeneratorWorker — runs Lua generation off the audio thread.
    // -----------------------------------------------------------------------
    class GeneratorWorker : public juce::Thread
    {
    public:
        GeneratorWorker (LuaHost& host,
                         EventQueue& queue,
                         std::atomic<int>& eventCountOut,
                         std::function<LuaHost::Params()> paramProvider);

        void run() override;
        void requestRegeneration();

    private:
        void regenerate();

        LuaHost&                       luaHost;
        EventQueue&                    queue;
        std::atomic<int>&              lastEventCount;
        std::function<LuaHost::Params()> paramProvider;
    };

    // Member declaration order matters — luaHost must be first so the APVTS
    // initialiser (which calls luaHost.getPresets()) can use it.
    LuaHost                              luaHost;
    std::vector<LuaHost::PresetInfo>     presetInfos;   // cached before worker starts
    juce::AudioProcessorValueTreeState   apvts;
    EventQueue                           eventQueue;
    GeneratorWorker                      worker;

    juce::String     cachedPing;
    std::atomic<int> lastEventCount { 0 };

    // Audio-thread-only state.
    std::vector<LuaHost::MidiEvent> currentGeneration;
    int     eventCursor       { 0 };
    int64_t samplesSinceStart { 0 };
    double  cachedBpm         { 120.0 };

    struct ActiveNote { int note, channel; int64_t noteOffSample; };
    std::vector<ActiveNote> activeNotes;

    bool wasPlaying { false };
    bool armed      { true };
};
