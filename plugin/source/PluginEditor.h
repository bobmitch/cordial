#pragma once

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include "PluginProcessor.h"

// ---------------------------------------------------------------------------
// CordialAudioProcessorEditor — Phase 7
//
// Layout: four GroupComponent sections (Global, Chord, Arp, Melody) laid out
// top-to-bottom. All controls are wired via APVTS attachments for DAW
// automation and preset recall. A drag handle in the top bar lets the user
// drag a .mid file of the current generation directly to the DAW timeline.
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

    // Writes the current generation to a temp .mid file and returns its path.
    // Returns an empty string on failure (e.g. no events yet).
    juce::String writeTempMidi();

    // Component that initiates an external file drag when the user drags it.
    struct DragHandle : juce::Component
    {
        std::function<juce::String()> getMidiFilePath;

        void paint (juce::Graphics& g) override
        {
            const auto bounds = getLocalBounds().toFloat().reduced (1.0f);
            g.setColour (isHovered ? juce::Colour (0xff5a8fa8) : juce::Colour (0xff3e6a80));
            g.fillRoundedRectangle (bounds, 4.0f);
            g.setColour (juce::Colours::white.withAlpha (0.6f));
            g.drawRoundedRectangle (bounds, 4.0f, 1.0f);
            g.setColour (juce::Colours::white);
            g.setFont (juce::Font (juce::FontOptions (11.0f)));
            g.drawText ("\xe2\x87\xa7 MIDI", getLocalBounds(), juce::Justification::centred);
        }

        void mouseEnter (const juce::MouseEvent&) override { isHovered = true;  repaint(); }
        void mouseExit  (const juce::MouseEvent&) override { isHovered = false; repaint(); }
        void mouseUp    (const juce::MouseEvent&) override { dragStarted = false; }

        void mouseDrag (const juce::MouseEvent& e) override
        {
            if (dragStarted || e.getDistanceFromDragStart() < 5) return;
            dragStarted = true;
            const auto path = getMidiFilePath ? getMidiFilePath() : juce::String{};
            if (path.isNotEmpty())
                juce::DragAndDropContainer::performExternalDragDropOfFiles (
                    { path }, false, this, [this] { dragStarted = false; });
            else
                dragStarted = false;
        }

    private:
        bool isHovered   = false;
        bool dragStarted = false;
    };

    CordialAudioProcessor& processor;
    juce::AudioProcessorValueTreeState& apvts;

    // --- Top bar -------------------------------------------------------------
    juce::Label heading;
    DragHandle  dragHandle;
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
    juce::Label arpPatternLabel  { {}, "Pattern" };
    juce::Label arpRateLabel     { {}, "Rate" };
    juce::Label arpOctLowLabel   { {}, "Oct Low" };
    juce::Label arpOctHighLabel  { {}, "Oct High" };
    juce::Label arpRigidityLabel { {}, "Rigidity" };

    // --- Arp section controls ------------------------------------------------
    juce::ToggleButton arpEnabledBtn;
    juce::ComboBox     arpPatternCombo;
    juce::ComboBox     arpRateCombo;
    juce::Slider       arpOctLowSlider   { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };
    juce::Slider       arpOctHighSlider  { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };
    juce::Slider       arpRigiditySlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };

    // --- Melody section ------------------------------------------------------
    juce::ToggleButton melEnabledBtn;

    juce::Label    melPresetLabel   { {}, "Preset" };
    juce::ComboBox melPresetCombo;

    juce::Label  melOctaveLabel  { {}, "Octave" };
    juce::Slider melOctaveSlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };

    juce::Label  melBusynessLabel  { {}, "Busyness" };
    juce::Slider melBusynessSlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };

    juce::Label  melCadenceLabel  { {}, "Cadence" };
    juce::Slider melCadenceSlider { juce::Slider::LinearHorizontal, juce::Slider::TextBoxRight };

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
    std::unique_ptr<SliderAttachment> arpOctLowAttachment;
    std::unique_ptr<SliderAttachment> arpOctHighAttachment;
    std::unique_ptr<SliderAttachment> arpRigidityAttachment;

    // Melody
    std::unique_ptr<ButtonAttachment> melEnabledAttachment;
    std::unique_ptr<ComboAttachment>  melPresetAttachment;
    std::unique_ptr<SliderAttachment> melOctaveAttachment;
    std::unique_ptr<SliderAttachment> melBusynessAttachment;
    std::unique_ptr<SliderAttachment> melCadenceAttachment;
};
