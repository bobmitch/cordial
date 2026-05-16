#include "PluginProcessor.h"
#include "PluginEditor.h"

// ---------------------------------------------------------------------------
// Parameter layout — called once during APVTS construction.
// ---------------------------------------------------------------------------
juce::AudioProcessorValueTreeState::ParameterLayout
CordialAudioProcessor::buildParameterLayout (const std::vector<LuaHost::PresetInfo>& presets)
{
    juce::AudioProcessorValueTreeState::ParameterLayout layout;

    // Root note (C … B)
    juce::StringArray rootChoices;
    for (const auto* name : Params::NOTE_NAMES)
        rootChoices.add (name);
    layout.add (std::make_unique<juce::AudioParameterChoice> (
        juce::ParameterID { Params::Root, 1 },
        "Root", rootChoices, 0));  // default = C

    // Progression preset
    juce::StringArray presetChoices;
    for (const auto& pi : presets)
        presetChoices.add (pi.name.isEmpty() ? "Preset" : pi.name);
    if (presetChoices.isEmpty())
        presetChoices.add ("Default");
    layout.add (std::make_unique<juce::AudioParameterChoice> (
        juce::ParameterID { Params::Preset, 1 },
        "Preset", presetChoices, 0));  // default = first preset

    // Octave
    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { Params::Octave, 1 },
        "Octave",
        Params::OCTAVE_MIN, Params::OCTAVE_MAX, Params::OCTAVE_DEFAULT));

    // Seed
    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { Params::Seed, 1 },
        "Seed",
        Params::SEED_MIN, Params::SEED_MAX, Params::SEED_DEFAULT));

    // Smart voicing
    layout.add (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { Params::SmartVoicing, 1 },
        "Smart Voicing", true));

    return layout;
}

// ---------------------------------------------------------------------------
// makeParams — translates APVTS values into a Lua params snapshot.
// All reads are from atomic<float>* so this is thread-safe.
// ---------------------------------------------------------------------------
LuaHost::Params CordialAudioProcessor::makeParams() const
{
    LuaHost::Params p;

    const int rootChoice   = static_cast<int> (
        apvts.getRawParameterValue (Params::Root)->load (std::memory_order_relaxed));
    const int presetChoice = static_cast<int> (
        apvts.getRawParameterValue (Params::Preset)->load (std::memory_order_relaxed));

    p.rootIdx        = rootChoice + 1;          // APVTS 0-based → Lua 1-based
    p.progressionIdx = presetChoice + 1;        // APVTS 0-based → Lua 1-based
    p.octave         = static_cast<int> (
        apvts.getRawParameterValue (Params::Octave)->load (std::memory_order_relaxed));
    p.seed           = static_cast<int> (
        apvts.getRawParameterValue (Params::Seed)->load (std::memory_order_relaxed));
    p.smartVoicing   =
        apvts.getRawParameterValue (Params::SmartVoicing)->load (std::memory_order_relaxed) > 0.5f;

    return p;
}

// ---------------------------------------------------------------------------
// GeneratorWorker
// ---------------------------------------------------------------------------
CordialAudioProcessor::GeneratorWorker::GeneratorWorker (
    LuaHost&                        host,
    EventQueue&                     q,
    std::atomic<int>&               countOut,
    std::function<LuaHost::Params()> provider)
    : juce::Thread ("CordialGenerator"),
      luaHost (host), queue (q),
      lastEventCount (countOut),
      paramProvider (std::move (provider))
{
}

void CordialAudioProcessor::GeneratorWorker::run()
{
    regenerate();   // initial generation

    while (! threadShouldExit())
    {
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
    auto params = paramProvider();
    auto events = luaHost.generate (params);

    queue.beginGeneration();
    if (! events.empty())
        queue.pushEvents (events.data(), static_cast<int> (events.size()));

    lastEventCount.store (static_cast<int> (events.size()), std::memory_order_release);
}

// ---------------------------------------------------------------------------
// CordialAudioProcessor
// ---------------------------------------------------------------------------
CordialAudioProcessor::CordialAudioProcessor()
    : AudioProcessor (BusesProperties()
                        .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                        .withOutput ("Output", juce::AudioChannelSet::stereo(), true)),
      presetInfos (luaHost.getPresets()),          // Lua call before worker starts
      apvts (*this, nullptr, "CordialState",
             buildParameterLayout (presetInfos)),
      worker (luaHost, eventQueue, lastEventCount, [this] { return makeParams(); })
{
    cachedPing = luaHost.ping();  // one-time Lua call on main thread

    // Pre-reserve so processBlock never heap-allocates.
    currentGeneration.reserve (EventQueue::kCapacity);
    activeNotes.reserve (256);

    // Listen for parameter changes → trigger regeneration.
    for (const auto* id : { Params::Root, Params::Preset,
                             Params::Octave, Params::Seed, Params::SmartVoicing })
        apvts.addParameterListener (id, this);

    worker.startThread (juce::Thread::Priority::normal);
}

CordialAudioProcessor::~CordialAudioProcessor()
{
    for (const auto* id : { Params::Root, Params::Preset,
                             Params::Octave, Params::Seed, Params::SmartVoicing })
        apvts.removeParameterListener (id, this);

    worker.stopThread (2000);
}

void CordialAudioProcessor::parameterChanged (const juce::String& /*paramID*/, float /*newValue*/)
{
    worker.requestRegeneration();
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

void CordialAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    auto state = apvts.copyState();
    std::unique_ptr<juce::XmlElement> xml (state.createXml());
    copyXmlToBinary (*xml, destData);
}

void CordialAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> xml (getXmlFromBinary (data, sizeInBytes));
    if (xml != nullptr && xml->hasTagName (apvts.state.getType()))
        apvts.replaceState (juce::ValueTree::fromXml (*xml));
}

juce::String CordialAudioProcessor::getLuaDiagnostic() const
{
    const int n = lastEventCount.load (std::memory_order_acquire);
    if (n <= 0)
        return "Generating\xe2\x80\xa6";   // "Generating…" UTF-8
    return "Lua OK (" + juce::String (n) + " events): " + cachedPing;
}

void CordialAudioProcessor::processBlock (juce::AudioBuffer<float>& audio,
                                          juce::MidiBuffer& midi)
{
    juce::ignoreUnused (audio);

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

    for (auto it = activeNotes.begin(); it != activeNotes.end();)
    {
        if (it->noteOffSample < bufEnd)
        {
            const int offset = static_cast<int> (
                juce::jmax (int64_t {0}, it->noteOffSample - bufStart));
            midi.addEvent (juce::MidiMessage::noteOff (it->channel, it->note), offset);
            it = activeNotes.erase (it);
        }
        else { ++it; }
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
