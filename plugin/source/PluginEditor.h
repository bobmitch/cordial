#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include "PluginProcessor.h"

// Phase 1 editor: just a label so we can confirm the plugin loaded and Lua
// is running. ImGui-in-JUCE comes online in phase 6.
class CordialAudioProcessorEditor : public juce::AudioProcessorEditor
{
public:
    explicit CordialAudioProcessorEditor (CordialAudioProcessor&);
    ~CordialAudioProcessorEditor() override = default;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    CordialAudioProcessor& processor;
    juce::Label            heading;
    juce::Label            diagnostic;
};
