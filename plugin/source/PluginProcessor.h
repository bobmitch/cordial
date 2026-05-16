#pragma once

#include <juce_audio_processors/juce_audio_processors.h>

#include <atomic>
#include <vector>

#include "EventQueue.h"
#include "LuaHost.h"

// ---------------------------------------------------------------------------
// CordialAudioProcessor — phase 4: threaded generation.
//
// Architecture:
//   - LuaHost lives on the worker thread (Lua is single-threaded, so only
//     the worker calls it after construction).
//   - Generator worker (juce::Thread) regenerates the event list on signal
//     and publishes through EventQueue (juce::AbstractFifo).
//   - processBlock drains the queue lock-free at the top of each buffer
//     into a pre-reserved local vector, then emits events sample-accurately
//     using the BPM captured at transport start.
//
// processBlock realtime contract:
//   - No heap allocation (queue drain, activeNotes, midi events all reserved)
//   - No Lua calls
//   - No locks (SPSC fifo, atomic gen counter)
// ---------------------------------------------------------------------------
class CordialAudioProcessor : public juce::AudioProcessor
{
public:
    CordialAudioProcessor();
    ~CordialAudioProcessor() override;

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

    // Editor reads this on a Timer; built fresh each call from the atomic
    // event-count and the ping string cached at construction.
    juce::String getLuaDiagnostic() const;

private:
    // -----------------------------------------------------------------------
    // GeneratorWorker — owns the LuaHost and produces into the EventQueue.
    // Wakes on notify(); regenerates and publishes; sleeps again. Stopped
    // and joined by the processor's destructor.
    // -----------------------------------------------------------------------
    class GeneratorWorker : public juce::Thread
    {
    public:
        GeneratorWorker (LuaHost& host, EventQueue& queue,
                         std::atomic<int>& eventCountOut);

        void run() override;

        // Ask the worker to regenerate. Thread-safe; just sets a flag and
        // wakes the thread.
        void requestRegeneration();

    private:
        void regenerate();

        LuaHost&          luaHost;
        EventQueue&       queue;
        std::atomic<int>& lastEventCount;   // published for the editor
    };

    LuaHost          luaHost;
    EventQueue       eventQueue;
    GeneratorWorker  worker;

    // Cached at construction so the editor's diagnostic getter never
    // touches Lua (and never races the worker on the sol::state).
    juce::String     cachedPing;
    std::atomic<int> lastEventCount { 0 };

    // Audio-thread-only state.
    std::vector<LuaHost::MidiEvent> currentGeneration;  // refilled from queue
    int     eventCursor       { 0 };
    int64_t samplesSinceStart { 0 };
    double  cachedBpm         { 120.0 };

    struct ActiveNote { int note, channel; int64_t noteOffSample; };
    std::vector<ActiveNote> activeNotes;

    bool wasPlaying { false };
    bool armed      { true };
};
