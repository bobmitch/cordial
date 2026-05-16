#include "PluginEditor.h"

CordialAudioProcessorEditor::CordialAudioProcessorEditor (CordialAudioProcessor& p)
    : AudioProcessorEditor (&p), processor (p)
{
    heading.setText ("Cordial", juce::dontSendNotification);
    heading.setFont (juce::Font (juce::FontOptions (20.0f, juce::Font::bold)));
    heading.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (heading);

    diagnostic.setText (processor.getLuaDiagnostic(), juce::dontSendNotification);
    diagnostic.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (diagnostic);

    // 4 Hz is plenty for a "Generating…" → "Lua OK" swap-once readout.
    startTimerHz (4);

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

void CordialAudioProcessorEditor::timerCallback()
{
    const auto next = processor.getLuaDiagnostic();
    if (diagnostic.getText() != next)
        diagnostic.setText (next, juce::dontSendNotification);
}
