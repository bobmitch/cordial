#include "PluginProcessor.h"
#include "PluginEditor.h"

namespace
{
    constexpr int kChannel = 1;
}

CordialAudioProcessor::CordialAudioProcessor()
    : AudioProcessor(BusesProperties())   // MIDI effect: no audio buses
{
    if (auto chord = luaHost.getPhase1Chord())
    {
        chordNotes       = chord->notes;
        chordVelocity    = chord->velocity;
        chordLengthBeats = chord->lengthBeats;
        luaDiagnostic    = "Lua OK: " + luaHost.ping();
    }
    else
    {
        // Fallback so the plugin still loads (and is audibly broken) if the
        // Lua side fails — easier to diagnose than silent failure.
        chordNotes    = { 60, 64, 67 };
        luaDiagnostic = "Lua FAILED — using C++ fallback chord";
    }
}

void CordialAudioProcessor::prepareToPlay (double, int)
{
    wasPlaying = false;
    armed      = true;
    chordOn    = false;
}

void CordialAudioProcessor::processBlock (juce::AudioBuffer<float>& audio,
                                          juce::MidiBuffer& midi)
{
    audio.clear();
    midi.clear();   // generator: we don't pass through input

    auto* ph = getPlayHead();
    juce::AudioPlayHead::PositionInfo pos;
    bool gotPos = false;
    if (ph != nullptr)
    {
        if (auto p = ph->getPosition())
        {
            pos    = *p;
            gotPos = true;
        }
    }

    const bool playing = gotPos && pos.getIsPlaying();
    const double bpm   = gotPos ? pos.getBpm().orFallback (120.0) : 120.0;
    const double sr    = getSampleRate() > 0.0 ? getSampleRate() : 44100.0;
    const int   numSamples = audio.getNumSamples();

    const bool justStarted = playing && ! wasPlaying;
    const bool justStopped = ! playing && wasPlaying;
    wasPlaying = playing;

    if (justStopped && chordOn)
    {
        for (int n : chordNotes)
            midi.addEvent (juce::MidiMessage::noteOff (kChannel, n), 0);
        chordOn = false;
        armed   = true;
        return;
    }

    if (justStarted && armed && ! chordNotes.empty())
    {
        for (int n : chordNotes)
            midi.addEvent (juce::MidiMessage::noteOn (kChannel, n,
                                                     (juce::uint8) chordVelocity), 0);
        chordOn = true;
        armed   = false;

        // Length in samples. Re-evaluated each play so tempo edits between
        // takes work without restarting the plugin.
        const double secs    = (60.0 / juce::jmax (1.0, bpm)) * chordLengthBeats;
        // Stash remaining samples in chordLengthBeats's sibling field via a
        // local static would be ugly — we instead reuse `samplesUntilOff`
        // tracked through `chordOn`. Compute and store on the processor.
        samplesUntilOff = juce::roundToInt (secs * sr);
    }

    if (chordOn)
    {
        if (samplesUntilOff <= numSamples)
        {
            const int offset = juce::jmax (0, samplesUntilOff);
            for (int n : chordNotes)
                midi.addEvent (juce::MidiMessage::noteOff (kChannel, n), offset);
            chordOn         = false;
            samplesUntilOff = 0;
        }
        else
        {
            samplesUntilOff -= numSamples;
        }
    }
}

juce::AudioProcessorEditor* CordialAudioProcessor::createEditor()
{
    return new CordialAudioProcessorEditor (*this);
}

// JUCE plugin factory entry point.
juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new CordialAudioProcessor();
}
