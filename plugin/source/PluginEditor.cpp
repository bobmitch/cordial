#include "PluginEditor.h"

CordialAudioProcessorEditor::CordialAudioProcessorEditor (CordialAudioProcessor& p)
    : AudioProcessorEditor (&p), processor (p)
{
    heading.setText ("Cordial — Phase 1 scaffold", juce::dontSendNotification);
    heading.setFont (juce::Font (juce::FontOptions (20.0f, juce::Font::bold)));
    heading.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (heading);

    diagnostic.setText (processor.getLuaDiagnostic(), juce::dontSendNotification);
    diagnostic.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (diagnostic);

    setSize (720, 180);
}

void CordialAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void CordialAudioProcessorEditor::resized()
{
    auto r = getLocalBounds().reduced (16);
    heading.setBounds    (r.removeFromTop (40));
    diagnostic.setBounds (r.removeFromTop (40));
}
