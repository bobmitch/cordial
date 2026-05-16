#include "PluginProcessor.h"
#include "PluginEditor.h"

// ---------------------------------------------------------------------------
// GeneratorWorker
// ---------------------------------------------------------------------------
CordialAudioProcessor::GeneratorWorker::GeneratorWorker (LuaHost& host,
                                                         EventQueue& q,
                                                         std::atomic<int>& countOut)
    : juce::Thread ("CordialGenerator"),
      luaHost (host),
      queue (q),
      lastEventCount (countOut)
{
}

void CordialAudioProcessor::GeneratorWorker::run()
{
    // Initial generation so the queue is populated before the user hits play.
    regenerate();

    while (! threadShouldExit())
    {
        // wait() blocks until notify() or the timeout. The 1-second cap is a
        // safety net — nothing actually depends on the periodic wake.
        wait (1000);
        if (threadShouldExit()) break;
        regenerate();
    }
}

void CordialAudioProcessor::GeneratorWorker::requestRegeneration()
{
    notify();
}

void CordialAudioProcessor::GeneratorWorker::regenerate()
{
    // Phase 4 uses the default params. Phase 5 will read live UI params
    // through a thread-safe snapshot here.
    LuaHost::Params p;
    auto events = luaHost.generate (p);

    queue.beginGeneration();
    if (! events.empty())
        queue.pushEvents (events.data(), static_cast<int> (events.size()));

    lastEventCount.store (static_cast<int> (events.size()),
                          std::memory_order_release);
}

// ---------------------------------------------------------------------------
// CordialAudioProcessor
// ---------------------------------------------------------------------------
CordialAudioProcessor::CordialAudioProcessor()
    : AudioProcessor (BusesProperties()
                        .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                        .withOutput ("Output", juce::AudioChannelSet::stereo(), true)),
      worker (luaHost, eventQueue, lastEventCount)
{
    // One-time synchronous Lua call from the main thread, before the
    // worker starts. After this point, the worker is the only thread that
    // touches Lua.
    cachedPing = luaHost.ping();

    // Pre-reserve so processBlock never allocates while draining or
    // tracking notes.
    currentGeneration.reserve (EventQueue::kCapacity);
    activeNotes.reserve (256);

    worker.startThread (juce::Thread::Priority::normal);
}

CordialAudioProcessor::~CordialAudioProcessor()
{
    // 2-second join window; the worker has nothing blocking other than
    // wait(), so it exits promptly.
    worker.stopThread (2000);
}

void CordialAudioProcessor::prepareToPlay (double, int)
{
    wasPlaying        = false;
    armed             = true;
    eventCursor       = 0;
    samplesSinceStart = 0;
    activeNotes.clear();
}

bool CordialAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    const auto& mainOut = layouts.getMainOutputChannelSet();
    if (mainOut != juce::AudioChannelSet::mono()
     && mainOut != juce::AudioChannelSet::stereo())
        return false;
    return mainOut == layouts.getMainInputChannelSet();
}

juce::String CordialAudioProcessor::getLuaDiagnostic() const
{
    const int n = lastEventCount.load (std::memory_order_acquire);
    if (n <= 0)
        return "Generating…";
    return "Lua OK (" + juce::String (n) + " events): " + cachedPing;
}

void CordialAudioProcessor::processBlock (juce::AudioBuffer<float>& audio,
                                          juce::MidiBuffer& midi)
{
    juce::ignoreUnused (audio);  // audio passthrough

    // Pick up any new generation the worker has published. If true, the
    // event list was replaced and we restart playback from event 0. Any
    // notes still sounding from the previous generation are flushed —
    // their scheduled noteOffSample values were anchored to the old
    // samplesSinceStart and would otherwise get stuck.
    if (eventQueue.drainTo (currentGeneration))
    {
        for (const auto& an : activeNotes)
            midi.addEvent (juce::MidiMessage::noteOff (an.channel, an.note), 0);
        activeNotes.clear();
        eventCursor       = 0;
        samplesSinceStart = 0;
    }

    auto* ph = getPlayHead();
    juce::AudioPlayHead::PositionInfo pos;
    bool gotPos = false;
    if (ph != nullptr)
        if (auto p = ph->getPosition())
        { pos = *p; gotPos = true; }

    const bool   playing    = gotPos && pos.getIsPlaying();
    const double bpm        = gotPos ? pos.getBpm().orFallback (120.0) : 120.0;
    const double sr         = getSampleRate() > 0.0 ? getSampleRate() : 44100.0;
    const int    numSamples = audio.getNumSamples();

    const bool justStarted = playing && ! wasPlaying;
    const bool justStopped = ! playing && wasPlaying;
    wasPlaying = playing;

    if (justStopped)
    {
        for (const auto& an : activeNotes)
            midi.addEvent (juce::MidiMessage::noteOff (an.channel, an.note), 0);
        activeNotes.clear();
        armed             = true;
        eventCursor       = 0;
        samplesSinceStart = 0;
        return;
    }

    if (justStarted && armed)
    {
        eventCursor       = 0;
        samplesSinceStart = 0;
        cachedBpm         = juce::jmax (1.0, bpm);
        armed             = false;
    }

    if (! playing)
        return;

    const double  samplesPerBeat = (sr * 60.0) / cachedBpm;
    const int64_t bufStart       = samplesSinceStart;
    const int64_t bufEnd         = bufStart + numSamples;

    // Note-offs first (off-then-on if same pitch lands in same buffer).
    for (auto it = activeNotes.begin(); it != activeNotes.end();)
    {
        if (it->noteOffSample < bufEnd)
        {
            const int offset = static_cast<int> (
                juce::jmax (int64_t {0}, it->noteOffSample - bufStart));
            midi.addEvent (juce::MidiMessage::noteOff (it->channel, it->note), offset);
            it = activeNotes.erase (it);
        }
        else
        {
            ++it;
        }
    }

    while (eventCursor < static_cast<int> (currentGeneration.size()))
    {
        const auto& ev = currentGeneration[static_cast<std::size_t> (eventCursor)];
        const int64_t evSample = static_cast<int64_t> (ev.posBeats * samplesPerBeat);
        if (evSample >= bufEnd) break;

        const int offset = static_cast<int> (
            juce::jmax (int64_t {0}, evSample - bufStart));
        midi.addEvent (juce::MidiMessage::noteOn (ev.channel, ev.note,
                                                  static_cast<juce::uint8> (ev.velocity)),
                       offset);

        const int64_t offSample = static_cast<int64_t> (
            (ev.posBeats + ev.durBeats) * samplesPerBeat);
        activeNotes.push_back ({ ev.note, ev.channel, offSample });

        ++eventCursor;
    }

    samplesSinceStart += numSamples;
}

juce::AudioProcessorEditor* CordialAudioProcessor::createEditor()
{
    return new CordialAudioProcessorEditor (*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new CordialAudioProcessor();
}
