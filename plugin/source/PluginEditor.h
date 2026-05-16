#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include "PluginProcessor.h"

// ---------------------------------------------------------------------------
// CordialAudioProcessorEditor — Phase 6
//
// Layout: four GroupComponent sections (Global, Chord, Arp, Melody) laid out
// top-to-bottom. All controls are wired via APVTS attachments for DAW
// automation and preset recall.
// ---------------------------------------------------------------------------
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

    // --- Top bar -------------------------------------------------------------
    juce::Label heading;
    juce::Label diagnostic;

    // --- Section group borders -----------------------------------------------
    juce::GroupComponent globalGroup;
    juce::GroupComponent chordGroup;
    juce::GroupComponent arpGroup;
    juce::GroupComponent melGroup;

    // --- Global section labels -----------------------------------------------
    juce::Label rootLabel    { {}, "Root" };
    juce::Label octaveLabel  { {}, "Octave" };
    juce::Label presetLabel  { {}, "Preset" };
    juce::Label seedLabel    { {}, "Seed" };

    // --- Global section controls ---------------------------------------------
    juce::ComboBox rootCombo;
    juce::Slider   octaveSlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };
    juce::ComboBox presetCombo;
    juce::Slider   seedSlider   { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };

    // --- Chord section -------------------------------------------------------
    juce::ToggleButton chordEnabledBtn;
    juce::ToggleButton svButton;

    // --- Arp section labels --------------------------------------------------
    juce::Label arpPatternLabel { {}, "Pattern" };
    juce::Label arpRateLabel    { {}, "Rate" };
    juce::Label arpOctavesLabel { {}, "Octaves" };
    juce::Label arpRigidityLabel{ {}, "Rigidity" };

    // --- Arp section controls ------------------------------------------------
    juce::ToggleButton arpEnabledBtn;
    juce::ComboBox     arpPatternCombo;
    juce::ComboBox     arpRateCombo;
    juce::Slider       arpOctavesSlider  { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };
    juce::Slider       arpRigiditySlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };

    // --- Melody section ------------------------------------------------------
    juce::ToggleButton melEnabledBtn;
    juce::Label        melComingLabel;

    // --- APVTS attachments ---------------------------------------------------
    using ComboAttachment  = juce::AudioProcessorValueTreeState::ComboBoxAttachment;
    using SliderAttachment = juce::AudioProcessorValueTreeState::SliderAttachment;
    using ButtonAttachment = juce::AudioProcessorValueTreeState::ButtonAttachment;

    // Global
    std::unique_ptr<ComboAttachment>  rootAttachment;
    std::unique_ptr<SliderAttachment> octaveAttachment;
    std::unique_ptr<ComboAttachment>  presetAttachment;
    std::unique_ptr<SliderAttachment> seedAttachment;

    // Chord
    std::unique_ptr<ButtonAttachment> chordEnabledAttachment;
    std::unique_ptr<ButtonAttachment> svAttachment;

    // Arp
    std::unique_ptr<ButtonAttachment> arpEnabledAttachment;
    std::unique_ptr<ComboAttachment>  arpPatternAttachment;
    std::unique_ptr<ComboAttachment>  arpRateAttachment;
    std::unique_ptr<SliderAttachment> arpOctavesAttachment;
    std::unique_ptr<SliderAttachment> arpRigidityAttachment;

    // Melody
    std::unique_ptr<ButtonAttachment> melEnabledAttachment;
};
