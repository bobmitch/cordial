#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include "PluginProcessor.h"

// Functional editor for Phase 5. Controls are attached to the APVTS so they
// participate in DAW automation and preset recall. ImGui replaces this in
// Phase 6, so the layout stays deliberately simple.
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
    juce::AudioProcessorValueTreeState& apvts;

    // --- Labels --------------------------------------------------------------
    juce::Label heading;
    juce::Label diagnostic;

    juce::Label rootLabel   { {}, "Root" };
    juce::Label presetLabel { {}, "Preset" };
    juce::Label octaveLabel { {}, "Octave" };
    juce::Label seedLabel   { {}, "Seed" };
    juce::Label svLabel     { {}, "Smart voicing" };

    // --- Controls ------------------------------------------------------------
    juce::ComboBox rootCombo;
    juce::ComboBox presetCombo;
    juce::Slider   octaveSlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };
    juce::Slider   seedSlider   { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };
    juce::ToggleButton svButton;

    // --- APVTS attachments ---------------------------------------------------
    using ComboAttachment  = juce::AudioProcessorValueTreeState::ComboBoxAttachment;
    using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment;
    using ButtonAttachment = juce::AudioProcessorValueTreeState::ButtonAttachment;

    std::unique_ptr<ComboAttachment>  rootAttachment;
    std::unique_ptr<ComboAttachment>  presetAttachment;
    std::unique_ptr<SliderAttachment> octaveAttachment;
    std::unique_ptr<SliderAttachment> seedAttachment;
    std::unique_ptr<ButtonAttachment> svAttachment;
};
