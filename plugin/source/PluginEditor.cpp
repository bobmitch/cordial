#include "PluginEditor.h"
#include "Parameters.h"

namespace
{
    constexpr int kMargin     = 12;
    constexpr int kRowH       = 28;
    constexpr int kGap        = 6;
    constexpr int kLabelW     = 90;
    constexpr int kComboW     = 200;
    constexpr int kSliderW    = 180;
}

CordialAudioProcessorEditor::CordialAudioProcessorEditor (CordialAudioProcessor& p)
    : AudioProcessorEditor (&p),
      processor (p),
      apvts (p.getAPVTS())
{
    // --- Heading + diagnostic ------------------------------------------------
    heading.setText ("Cordial", juce::dontSendNotification);
    heading.setFont (juce::Font (juce::FontOptions (20.0f, juce::Font::bold)));
    heading.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (heading);

    diagnostic.setText (processor.getLuaDiagnostic(), juce::dontSendNotification);
    diagnostic.setFont (juce::Font (juce::FontOptions (11.0f)));
    diagnostic.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (diagnostic);

    // --- Root combo ----------------------------------------------------------
    rootLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (rootLabel);
    addAndMakeVisible (rootCombo);
    rootAttachment = std::make_unique<ComboAttachment> (apvts, Params::Root, rootCombo);

    // --- Preset combo --------------------------------------------------------
    presetLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (presetLabel);
    addAndMakeVisible (presetCombo);
    presetAttachment = std::make_unique<ComboAttachment> (apvts, Params::Preset, presetCombo);

    // --- Octave slider -------------------------------------------------------
    octaveLabel.setJustificationType (juce::Justification::centredRight);
    octaveSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 36, kRowH);
    addAndMakeVisible (octaveLabel);
    addAndMakeVisible (octaveSlider);
    octaveAttachment = std::make_unique<SliderAttachment> (apvts, Params::Octave, octaveSlider);

    // --- Seed slider ---------------------------------------------------------
    seedLabel.setJustificationType (juce::Justification::centredRight);
    seedSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 52, kRowH);
    addAndMakeVisible (seedLabel);
    addAndMakeVisible (seedSlider);
    seedAttachment = std::make_unique<SliderAttachment> (apvts, Params::Seed, seedSlider);

    // --- Smart voicing toggle ------------------------------------------------
    svLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (svLabel);
    addAndMakeVisible (svButton);
    svAttachment = std::make_unique<ButtonAttachment> (apvts, Params::SmartVoicing, svButton);

    startTimerHz (4);

    // Width: label + combo (root) + gap + label + combo (octave) + margins
    setSize (660, 290);
}

void CordialAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void CordialAudioProcessorEditor::resized()
{
    auto r = getLocalBounds().reduced (kMargin);

    heading.setBounds    (r.removeFromTop (30));
    r.removeFromTop (kGap);
    diagnostic.setBounds (r.removeFromTop (18));
    r.removeFromTop (kGap + 4);

    // Row: Root [combo]         Octave [slider]
    {
        auto row = r.removeFromTop (kRowH);
        rootLabel.setBounds  (row.removeFromLeft (kLabelW));
        rootCombo.setBounds  (row.removeFromLeft (kComboW));
        row.removeFromLeft   (kGap * 3);
        octaveLabel.setBounds (row.removeFromLeft (kLabelW));
        octaveSlider.setBounds (row.removeFromLeft (kSliderW + 36));
    }
    r.removeFromTop (kGap);

    // Row: Preset [combo, wider]
    {
        auto row = r.removeFromTop (kRowH);
        presetLabel.setBounds (row.removeFromLeft (kLabelW));
        presetCombo.setBounds (row);
    }
    r.removeFromTop (kGap);

    // Row: Seed [slider]        Smart Voicing [toggle]
    {
        auto row = r.removeFromTop (kRowH);
        seedLabel.setBounds  (row.removeFromLeft (kLabelW));
        seedSlider.setBounds (row.removeFromLeft (kSliderW + 52));
        row.removeFromLeft   (kGap * 3);
        svLabel.setBounds    (row.removeFromLeft (kLabelW));
        svButton.setBounds   (row.removeFromLeft (kRowH));
    }
}

void CordialAudioProcessorEditor::timerCallback()
{
    const auto next = processor.getLuaDiagnostic();
    if (diagnostic.getText() != next)
        diagnostic.setText (next, juce::dontSendNotification);
}
