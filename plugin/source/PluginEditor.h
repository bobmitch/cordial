#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include "PluginProcessor.h"

// Minimal editor — a heading and a diagnostic label. The diagnostic is
// polled on a timer so the "Generating…" → "Lua OK (N events): …" swap
// shows up once the worker has published its first generation. ImGui-in-JUCE
// replaces this in phase 6.
class CordialAudioProcessorEditor : public juce::AudioProcessorEditor,
                                    private juce::Timer
{
public:
    explicit CordialAudioProcessorEditor (CordialAudioProcessor&);
    ~CordialAudioProcessorEditor() override = default;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    void timerCallback() override;

    CordialAudioProcessor& processor;
    juce::Label            heading;
    juce::Label            diagnostic;
};
