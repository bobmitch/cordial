#include "PluginProcessor.h"
#include "PluginEditor.h"

CordialAudioProcessor::CordialAudioProcessor()
    : AudioProcessor(BusesProperties()
                       .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                       .withOutput ("Output", juce::AudioChannelSet::stereo(), true))
{
    // Generate the default I-IV-V-I progression in C major at construction.
    // Phase 5 will regenerate when the user changes parameters via the UI.
    LuaHost::Params p;
    midiEvents = luaHost.generate(p);

    luaDiagnostic = midiEvents.empty()
        ? "Lua FAILED — no events generated"
        : "Lua OK (" + juce::String ((int) midiEvents.size())
          + " events): " + luaHost.ping();
}

void CordialAudioProcessor::prepareToPlay (double, int)
{
    wasPlaying    = false;
    armed         = true;
    eventCursor   = 0;
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

void CordialAudioProcessor::processBlock (juce::AudioBuffer<float>& audio,
                                          juce::MidiBuffer& midi)
{
    // Audio passthrough — leave `audio` untouched.
    juce::ignoreUnused (audio);

    auto* ph = getPlayHead();
    juce::AudioPlayHead::PositionInfo pos;
    bool gotPos = false;
    if (ph != nullptr)
        if (auto p = ph->getPosition())
        { pos = *p; gotPos = true; }

    const bool playing    = gotPos && pos.getIsPlaying();
    const double bpm      = gotPos ? pos.getBpm().orFallback (120.0) : 120.0;
    const double sr       = getSampleRate() > 0.0 ? getSampleRate() : 44100.0;
    const int numSamples  = audio.getNumSamples();

    const bool justStarted = playing && ! wasPlaying;
    const bool justStopped = ! playing && wasPlaying;
    wasPlaying = playing;

    // --- Transport stop: flush all sounding notes and re-arm. ---------------
    if (justStopped)
    {
        for (const auto& an : activeNotes)
            midi.addEvent (juce::MidiMessage::noteOff (an.channel, an.note), 0);
        activeNotes.clear();
        armed         = true;
        eventCursor   = 0;
        samplesSinceStart = 0;
        return;
    }

    // --- Transport start: reset playback head. --------------------------------
    if (justStarted && armed)
    {
        eventCursor       = 0;
        samplesSinceStart = 0;
        cachedBpm         = juce::jmax (1.0, bpm);
        armed             = false;
    }

    if (! playing)
        return;

    // --- Drain events that fall inside this buffer. --------------------------
    //
    // Timing is anchored to the moment transport started (samplesSinceStart).
    // We use the BPM captured at that moment (cachedBpm) for consistency; a
    // real-time tempo change will drift but is corrected at the next transport
    // start. Phase 4+ will re-generate on tempo change via the worker thread.
    const double samplesPerBeat = (sr * 60.0) / cachedBpm;
    const int64_t bufStart      = samplesSinceStart;
    const int64_t bufEnd        = bufStart + numSamples;

    // Note-offs first (MIDI convention: off before on if same pitch, same buffer).
    for (auto it = activeNotes.begin(); it != activeNotes.end();)
    {
        if (it->noteOffSample < bufEnd)
        {
            const int offset = static_cast<int> (
                juce::jmax (int64_t{0}, it->noteOffSample - bufStart));
            midi.addEvent (juce::MidiMessage::noteOff (it->channel, it->note), offset);
            it = activeNotes.erase (it);
        }
        else
        {
            ++it;
        }
    }

    // Note-ons for events whose start falls in this buffer.
    while (eventCursor < static_cast<int> (midiEvents.size()))
    {
        const auto& ev = midiEvents[static_cast<std::size_t> (eventCursor)];
        const int64_t evSample = static_cast<int64_t> (ev.posBeats * samplesPerBeat);
        if (evSample >= bufEnd) break;

        const int offset = static_cast<int> (
            juce::jmax (int64_t{0}, evSample - bufStart));
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
