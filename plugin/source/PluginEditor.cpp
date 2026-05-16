#include "PluginEditor.h"
#include "Parameters.h"

namespace
{
    constexpr int kMargin    = 10;
    constexpr int kRowH      = 26;
    constexpr int kGap       = 5;
    constexpr int kGroupPad  = 18;  // extra top indent inside a GroupComponent (for border+title)
    constexpr int kInnerPad  = 6;   // left/right/bottom padding inside a group
    constexpr int kLabelW    = 80;
    constexpr int kComboW    = 190;
    constexpr int kSliderW   = 170;
    constexpr int kTbW       = 100; // ToggleButton width
}

CordialAudioProcessorEditor::CordialAudioProcessorEditor (CordialAudioProcessor& p)
    : AudioProcessorEditor (&p),
      processor (p),
      apvts (p.getAPVTS())
{
    // --- Top bar -------------------------------------------------------------
    heading.setText ("Cordial", juce::dontSendNotification);
    heading.setFont (juce::Font (juce::FontOptions (20.0f, juce::Font::bold)));
    heading.setJustificationType (juce::Justification::centredLeft);
    addAndMakeVisible (heading);

    diagnostic.setText (processor.getLuaDiagnostic(), juce::dontSendNotification);
    diagnostic.setFont (juce::Font (juce::FontOptions (11.0f)));
    diagnostic.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (diagnostic);

    dragHandle.getMidiFilePath = [this]() -> juce::String { return writeTempMidi(); };
    dragHandle.setMouseCursor (juce::MouseCursor::DraggingHandCursor);
    addAndMakeVisible (dragHandle);

    // --- Global section ------------------------------------------------------
    globalGroup.setText ("Global");
    addAndMakeVisible (globalGroup);

    rootLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (rootLabel);
    addAndMakeVisible (rootCombo);
    rootAttachment = std::make_unique<ComboAttachment> (apvts, Params::Root, rootCombo);

    octaveLabel.setJustificationType (juce::Justification::centredRight);
    octaveSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 34, kRowH);
    addAndMakeVisible (octaveLabel);
    addAndMakeVisible (octaveSlider);
    octaveAttachment = std::make_unique<SliderAttachment> (apvts, Params::Octave, octaveSlider);

    presetLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (presetLabel);
    addAndMakeVisible (presetCombo);
    presetAttachment = std::make_unique<ComboAttachment> (apvts, Params::Preset, presetCombo);

    seedLabel.setJustificationType (juce::Justification::centredRight);
    seedSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 50, kRowH);
    addAndMakeVisible (seedLabel);
    addAndMakeVisible (seedSlider);
    seedAttachment = std::make_unique<SliderAttachment> (apvts, Params::Seed, seedSlider);

    // --- Chord section -------------------------------------------------------
    chordGroup.setText ("Chord");
    addAndMakeVisible (chordGroup);

    chordEnabledBtn.setButtonText ("Enabled");
    addAndMakeVisible (chordEnabledBtn);
    chordEnabledAttachment = std::make_unique<ButtonAttachment> (
        apvts, Params::ChordEnabled, chordEnabledBtn);

    svButton.setButtonText ("Smart voicing");
    addAndMakeVisible (svButton);
    svAttachment = std::make_unique<ButtonAttachment> (apvts, Params::SmartVoicing, svButton);

    // --- Arp section ---------------------------------------------------------
    arpGroup.setText ("Arp");
    addAndMakeVisible (arpGroup);

    arpEnabledBtn.setButtonText ("Enabled");
    addAndMakeVisible (arpEnabledBtn);
    arpEnabledAttachment = std::make_unique<ButtonAttachment> (
        apvts, Params::ArpEnabled, arpEnabledBtn);

    arpPatternLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (arpPatternLabel);
    addAndMakeVisible (arpPatternCombo);
    arpPatternAttachment = std::make_unique<ComboAttachment> (
        apvts, Params::ArpPattern, arpPatternCombo);

    arpRateLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (arpRateLabel);
    addAndMakeVisible (arpRateCombo);
    arpRateAttachment = std::make_unique<ComboAttachment> (
        apvts, Params::ArpRate, arpRateCombo);

    arpOctavesLabel.setJustificationType (juce::Justification::centredRight);
    arpOctavesSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 28, kRowH);
    addAndMakeVisible (arpOctavesLabel);
    addAndMakeVisible (arpOctavesSlider);
    arpOctavesAttachment = std::make_unique<SliderAttachment> (
        apvts, Params::ArpOctaves, arpOctavesSlider);

    arpRigidityLabel.setJustificationType (juce::Justification::centredRight);
    arpRigiditySlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 34, kRowH);
    addAndMakeVisible (arpRigidityLabel);
    addAndMakeVisible (arpRigiditySlider);
    arpRigidityAttachment = std::make_unique<SliderAttachment> (
        apvts, Params::ArpRigidity, arpRigiditySlider);

    // --- Melody section ------------------------------------------------------
    melGroup.setText ("Melody");
    addAndMakeVisible (melGroup);

    melEnabledBtn.setButtonText ("Enabled");
    addAndMakeVisible (melEnabledBtn);
    melEnabledAttachment = std::make_unique<ButtonAttachment> (
        apvts, Params::MelEnabled, melEnabledBtn);

    melPresetLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (melPresetLabel);
    addAndMakeVisible (melPresetCombo);
    melPresetAttachment = std::make_unique<ComboAttachment> (
        apvts, Params::MelPreset, melPresetCombo);

    melBusynessLabel.setJustificationType (juce::Justification::centredRight);
    melBusynessSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 34, kRowH);
    addAndMakeVisible (melBusynessLabel);
    addAndMakeVisible (melBusynessSlider);
    melBusynessAttachment = std::make_unique<SliderAttachment> (
        apvts, Params::MelBusyness, melBusynessSlider);

    melCadenceLabel.setJustificationType (juce::Justification::centredRight);
    melCadenceSlider.setTextBoxStyle (juce::Slider::TextBoxRight, false, 34, kRowH);
    addAndMakeVisible (melCadenceLabel);
    addAndMakeVisible (melCadenceSlider);
    melCadenceAttachment = std::make_unique<SliderAttachment> (
        apvts, Params::MelCadence, melCadenceSlider);

    startTimerHz (4);

    setSize (720, 500);
}

void CordialAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void CordialAudioProcessorEditor::resized()
{
    auto r = getLocalBounds().reduced (kMargin);

    // --- Top bar: heading (left) + drag handle + diagnostic (right) ---------
    {
        auto bar = r.removeFromTop (30);
        heading.setBounds    (bar.removeFromLeft (120));
        bar.removeFromLeft   (kGap);
        dragHandle.setBounds (bar.removeFromLeft (80));
        diagnostic.setBounds (bar);
    }
    r.removeFromTop (kGap);

    // =========================================================================
    // Global section  (3 rows × kRowH + gaps + top/bottom padding)
    // 3 rows + 2 gaps + kGroupPad (title) + kInnerPad (bottom) = ~110px
    // =========================================================================
    {
        const int groupH = kGroupPad + kRowH + kGap + kRowH + kGap + kRowH + kInnerPad;
        auto outer = r.removeFromTop (groupH);
        globalGroup.setBounds (outer);

        // Inner area sits below the group title bar and inset from borders.
        auto inner = outer.reduced (kInnerPad).withTrimmedTop (kGroupPad - kInnerPad);

        // Row 1: Root [combo]   Octave [slider]
        {
            auto row = inner.removeFromTop (kRowH);
            rootLabel.setBounds  (row.removeFromLeft (kLabelW));
            rootCombo.setBounds  (row.removeFromLeft (kComboW));
            row.removeFromLeft   (kGap * 4);
            octaveLabel.setBounds  (row.removeFromLeft (kLabelW));
            octaveSlider.setBounds (row);
        }
        inner.removeFromTop (kGap);

        // Row 2: Preset [combo, full width]
        {
            auto row = inner.removeFromTop (kRowH);
            presetLabel.setBounds (row.removeFromLeft (kLabelW));
            presetCombo.setBounds (row);
        }
        inner.removeFromTop (kGap);

        // Row 3: Seed [slider]
        {
            auto row = inner.removeFromTop (kRowH);
            seedLabel.setBounds  (row.removeFromLeft (kLabelW));
            seedSlider.setBounds (row);
        }
    }
    r.removeFromTop (kGap);

    // =========================================================================
    // Chord section  (1 row: Chord Enabled toggle + Smart Voicing toggle)
    // =========================================================================
    {
        const int groupH = kGroupPad + kRowH + kInnerPad;
        auto outer = r.removeFromTop (groupH);
        chordGroup.setBounds (outer);

        auto inner = outer.reduced (kInnerPad).withTrimmedTop (kGroupPad - kInnerPad);
        auto row   = inner.removeFromTop (kRowH);

        chordEnabledBtn.setBounds (row.removeFromLeft (kTbW));
        row.removeFromLeft (kGap * 4);
        svButton.setBounds (row.removeFromLeft (kTbW + 30));
    }
    r.removeFromTop (kGap);

    // =========================================================================
    // Arp section  (3 rows: enabled; pattern + rate; octaves + rigidity)
    // =========================================================================
    {
        const int groupH = kGroupPad + kRowH + kGap + kRowH + kGap + kRowH + kInnerPad;
        auto outer = r.removeFromTop (groupH);
        arpGroup.setBounds (outer);

        auto inner = outer.reduced (kInnerPad).withTrimmedTop (kGroupPad - kInnerPad);

        // Row 1: Arp Enabled toggle
        {
            auto row = inner.removeFromTop (kRowH);
            arpEnabledBtn.setBounds (row.removeFromLeft (kTbW));
        }
        inner.removeFromTop (kGap);

        // Row 2: Pattern [combo]   Rate [combo]
        {
            auto row = inner.removeFromTop (kRowH);
            arpPatternLabel.setBounds (row.removeFromLeft (kLabelW));
            arpPatternCombo.setBounds (row.removeFromLeft (kComboW));
            row.removeFromLeft (kGap * 4);
            arpRateLabel.setBounds (row.removeFromLeft (kLabelW));
            arpRateCombo.setBounds (row.removeFromLeft (kComboW));
        }
        inner.removeFromTop (kGap);

        // Row 3: Octaves [slider]   Rigidity [slider]
        {
            auto row = inner.removeFromTop (kRowH);
            arpOctavesLabel.setBounds  (row.removeFromLeft (kLabelW));
            arpOctavesSlider.setBounds (row.removeFromLeft (kSliderW));
            row.removeFromLeft (kGap * 4);
            arpRigidityLabel.setBounds  (row.removeFromLeft (kLabelW));
            arpRigiditySlider.setBounds (row);
        }
    }
    r.removeFromTop (kGap);

    // =========================================================================
    // Melody section  (3 rows: enabled; preset; busyness + cadence)
    // =========================================================================
    {
        const int groupH = kGroupPad + kRowH + kGap + kRowH + kGap + kRowH + kInnerPad;
        auto outer = r.removeFromTop (groupH);
        melGroup.setBounds (outer);

        auto inner = outer.reduced (kInnerPad).withTrimmedTop (kGroupPad - kInnerPad);

        // Row 1: Melody Enabled toggle
        {
            auto row = inner.removeFromTop (kRowH);
            melEnabledBtn.setBounds (row.removeFromLeft (kTbW));
        }
        inner.removeFromTop (kGap);

        // Row 2: Preset [combo, full width]
        {
            auto row = inner.removeFromTop (kRowH);
            melPresetLabel.setBounds (row.removeFromLeft (kLabelW));
            melPresetCombo.setBounds (row);
        }
        inner.removeFromTop (kGap);

        // Row 3: Busyness [slider]   Cadence [slider]
        {
            auto row = inner.removeFromTop (kRowH);
            melBusynessLabel.setBounds  (row.removeFromLeft (kLabelW));
            melBusynessSlider.setBounds (row.removeFromLeft (kSliderW));
            row.removeFromLeft (kGap * 4);
            melCadenceLabel.setBounds   (row.removeFromLeft (kLabelW));
            melCadenceSlider.setBounds  (row);
        }
    }
}

void CordialAudioProcessorEditor::timerCallback()
{
    const auto next = processor.getLuaDiagnostic();
    if (diagnostic.getText() != next)
        diagnostic.setText (next, juce::dontSendNotification);
}

juce::String CordialAudioProcessorEditor::writeTempMidi()
{
    const auto events = processor.getDragSnapshot();
    if (events.empty()) return {};

    constexpr int kPPQ = 480;

    juce::MidiFile midiFile;
    midiFile.setTicksPerQuarterNote (kPPQ);

    juce::MidiMessageSequence seq;
    // 120 BPM tempo marker (500 000 µs / beat) so the file plays back sensibly
    // when opened standalone; the DAW re-tempo's it to the project on import.
    seq.addEvent (juce::MidiMessage::tempoMetaEvent (500000), 0);

    for (const auto& ev : events)
    {
        const auto onTick  = static_cast<int> (std::round (ev.posBeats * kPPQ));
        const auto offTick = static_cast<int> (std::round ((ev.posBeats + ev.durBeats) * kPPQ));
        seq.addEvent (juce::MidiMessage::noteOn  (ev.channel, ev.note,
                                                  static_cast<juce::uint8> (ev.velocity)), onTick);
        seq.addEvent (juce::MidiMessage::noteOff (ev.channel, ev.note,
                                                  static_cast<juce::uint8> (0)), offTick);
    }
    seq.updateMatchedPairs();
    midiFile.addTrack (seq);

    const auto tempFile = juce::File::getSpecialLocation (juce::File::tempDirectory)
                              .getChildFile ("cordial_drag.mid");
    juce::FileOutputStream fos (tempFile);
    if (! fos.openedOk()) return {};
    if (! midiFile.writeTo (fos)) return {};

    return tempFile.getFullPathName();
}
