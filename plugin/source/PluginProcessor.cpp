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
        juce::ParameterID { Params::Root, 1 }, "Root", rootChoices, 0));

    // Progression preset
    juce::StringArray presetChoices;
    for (const auto& pi : presets)
        presetChoices.add (pi.name.isEmpty() ? "Preset" : pi.name);
    if (presetChoices.isEmpty()) presetChoices.add ("Default");
    layout.add (std::make_unique<juce::AudioParameterChoice> (
        juce::ParameterID { Params::Preset, 1 }, "Preset", presetChoices, 0));

    // Octave
    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { Params::Octave, 1 }, "Octave",
        Params::OCTAVE_MIN, Params::OCTAVE_MAX, Params::OCTAVE_DEFAULT));

    // Seed
    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { Params::Seed, 1 }, "Seed",
        Params::SEED_MIN, Params::SEED_MAX, Params::SEED_DEFAULT));

    // --- Chord layer ---------------------------------------------------------
    layout.add (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { Params::SmartVoicing, 1 }, "Smart Voicing", true));
    layout.add (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { Params::ChordEnabled, 1 }, "Chord", true));

    // --- Arp layer -----------------------------------------------------------
    layout.add (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { Params::ArpEnabled, 1 }, "Arp", false));

    juce::StringArray arpPatternChoices;
    for (const auto* p : Params::ARP_PATTERNS) arpPatternChoices.add (p);
    layout.add (std::make_unique<juce::AudioParameterChoice> (
        juce::ParameterID { Params::ArpPattern, 1 }, "Arp Pattern",
        arpPatternChoices, 0));

    juce::StringArray arpRateChoices;
    for (const auto* r : Params::ARP_RATES) arpRateChoices.add (r);
    layout.add (std::make_unique<juce::AudioParameterChoice> (
        juce::ParameterID { Params::ArpRate, 1 }, "Arp Rate",
        arpRateChoices, 2));  // default 1/16

    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { Params::ArpOctaves, 1 }, "Arp Octaves", 1, 3, 1));
    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { Params::ArpRigidity, 1 }, "Arp Rigidity", 0, 100, 100));

    // --- Melody layer --------------------------------------------------------
    layout.add (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { Params::MelEnabled, 1 }, "Melody", false));

    return layout;
}

// ---------------------------------------------------------------------------
// makeParams — translates APVTS values into a Lua params snapshot.
// All reads are from atomic<float>* so this is thread-safe.
// ---------------------------------------------------------------------------
LuaHost::Params CordialAudioProcessor::makeParams() const
{
    auto load = [this](const char* id)
    {
        return apvts.getRawParameterValue (id)->load (std::memory_order_relaxed);
    };

    LuaHost::Params p;

    p.rootIdx        = static_cast<int> (load (Params::Root))   + 1;
    p.progressionIdx = static_cast<int> (load (Params::Preset)) + 1;
    p.octave         = static_cast<int> (load (Params::Octave));
    p.seed           = static_cast<int> (load (Params::Seed));
    p.smartVoicing   = load (Params::SmartVoicing) > 0.5f;
    p.chordEnabled   = load (Params::ChordEnabled)  > 0.5f;

    p.arpEnabled     = load (Params::ArpEnabled)    > 0.5f;
    const int arpPatIdx  = std::clamp (static_cast<int> (load (Params::ArpPattern)), 0, 8);
    p.arpPattern     = Params::ARP_PATTERNS[static_cast<std::size_t> (arpPatIdx)];
    const int arpRateIdx = std::clamp (static_cast<int> (load (Params::ArpRate)), 0, 3);
    p.arpRateBeats   = Params::ARP_RATE_BEATS[static_cast<std::size_t> (arpRateIdx)];
    p.arpOctaves     = static_cast<int> (load (Params::ArpOctaves));
    p.arpRigidity    = static_cast<int> (load (Params::ArpRigidity));

    p.melEnabled     = load (Params::MelEnabled)    > 0.5f;

    return p;
}

// ---------------------------------------------------------------------------
// GeneratorWorker
// ---------------------------------------------------------------------------
CordialAudioProcessor::GeneratorWorker::GeneratorWorker (
    LuaHost&                         host,
    EventQueue&                      q,
    std::atomic<int>&                countOut,
    std::function<LuaHost::Params()> provider)
    : juce::Thread ("CordialGenerator"),
      luaHost (host), queue (q),
      lastEventCount (countOut),
      paramProvider (std::move (provider))
{
}

void CordialAudioProcessor::GeneratorWorker::run()
{
    regenerate();
    while (! threadShouldExit())
    {
        wait (1000);
        if (threadShouldExit()) break;
        regenerate();
    }
}

void CordialAudioProcessor::GeneratorWorker::requestRegeneration() { notify(); }

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
namespace
{
    constexpr const char* kListenedParams[] = {
        Params::Root,        Params::Preset,
        Params::Octave,      Params::Seed,
        Params::SmartVoicing,Params::ChordEnabled,
        Params::ArpEnabled,  Params::ArpPattern,
        Params::ArpRate,     Params::ArpOctaves,
        Params::ArpRigidity, Params::MelEnabled,
    };
}

CordialAudioProcessor::CordialAudioProcessor()
    : AudioProcessor (BusesProperties()
                        .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                        .withOutput ("Output", juce::AudioChannelSet::stereo(), true)),
      presetInfos (luaHost.getPresets()),
      apvts (*this, nullptr, "CordialState", buildParameterLayout (presetInfos)),
      worker (luaHost, eventQueue, lastEventCount, [this] { return makeParams(); })
{
    cachedPing = luaHost.ping();
    currentGeneration.reserve (EventQueue::kCapacity);
    activeNotes.reserve (256);

    for (const auto* id : kListenedParams)
        apvts.addParameterListener (id, this);

    worker.startThread (juce::Thread::Priority::normal);
}

CordialAudioProcessor::~CordialAudioProcessor()
{
    for (const auto* id : kListenedParams)
        apvts.removeParameterListener (id, this);
    worker.stopThread (2000);
}

void CordialAudioProcessor::parameterChanged (const juce::String&, float)
{
    worker.requestRegeneration();
}

void CordialAudioProcessor::prepareToPlay (double, int)
{
    wasPlaying = false; armed = true;
    eventCursor = 0; samplesSinceStart = 0;
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
    if (n <= 0) return "Generating\xe2\x80\xa6";
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
        eventCursor = 0; samplesSinceStart = 0;
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
        armed = true; eventCursor = 0; samplesSinceStart = 0;
        return;
    }

    if (justStarted && armed)
    {
        eventCursor = 0; samplesSinceStart = 0;
        cachedBpm = juce::jmax (1.0, bpm);
        armed = false;
    }

    if (! playing) return;

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
