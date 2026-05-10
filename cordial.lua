-- ============================================================
--  Chord Generator  –  Phase 3
--  Adds: melody layer with 8 generation presets, rigidity,
--        colour (chromatic passing tones), min/max duration,
--        metre (beat placement enforcement),
--        busyness (arc-shaped density / clustering of shorter
--        notes around bar/half-bar landmarks), live preview
--
--  Requires: ReaImGui extension (install via ReaPack)
-- ============================================================

local ctx = reaper.ImGui_CreateContext("Chord Generator")

-- ----------------------------------------------------------------
--  MUSIC THEORY TABLES
-- ----------------------------------------------------------------
local NOTE_NAMES = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }

local CHORD_INTERVALS = {
  ["maj"]  = {0,4,7},    ["min"]  = {0,3,7},
  ["maj7"] = {0,4,7,11}, ["min7"] = {0,3,7,10},
  ["dom7"] = {0,4,7,10}, ["dim"]  = {0,3,6},
  ["dim7"] = {0,3,6,9},  ["aug"]  = {0,4,8},
  ["sus2"] = {0,2,7},    ["sus4"] = {0,5,7},
  ["maj9"] = {0,4,7,11,14}, ["min9"] = {0,3,7,10,14},
  ["add9"] = {0,4,7,14},
  -- Half-diminished (essential for minor jazz ii-V-i)
  ["m7b5"] = {0,3,6,10},
  -- Power chord (root + 5 + octave – essential for rock/metal)
  ["5"]    = {0,7,12},
  -- 6 chords (jazz I, fusion)
  ["6"]    = {0,4,7,9},  ["min6"] = {0,3,7,9},
  -- Dominant 9 (jazz/funk V)
  ["dom9"] = {0,4,7,10,14},
  -- Dominant 7 with flat 9 (V of i in minor / Phrygian-dom flavour)
  ["7b9"]  = {0,4,7,10,13},
}

local MODE_CHORDS = {
  lydian         = {"maj","min","min","maj","maj","min","dim"},
  lydian_dom     = {"maj","min","min","maj","min","dim","maj"},
  mixolydian     = {"maj","min","min","maj","min","min","maj"},
  major          = {"maj","min","min","maj","maj","min","dim"},
  minor          = {"min","dim","maj","min","min","maj","maj"},
  dorian         = {"min","min","maj","maj","min","dim","maj"},
  phrygian       = {"min","maj","maj","min","dim","maj","min"},
  locrian        = {"dim","maj","min","min","maj","maj","min"},
  harmonic_minor = {"min","dim","aug","min","maj","maj","dim"},
}
local MODE_NAMES   = {
  "major","lydian","lydian_dom","mixolydian",
  "minor","dorian","phrygian","locrian","harmonic_minor"
}
local MODE_DISPLAY = {
  "Major","Lydian","Lydian Dom","Mixolydian",
  "Minor (nat.)","Dorian","Phrygian","Locrian","Harmonic Minor"
}
local function mode_idx_by_name(name)
  for i, n in ipairs(MODE_NAMES) do
    if n == name then return i end
  end
  return nil
end
local SCALE_INTERVALS = {
  major          = {0,2,4,5,7,9,11},
  lydian         = {0,2,4,6,7,9,11},
  lydian_dom     = {0,2,4,6,7,9,10},
  mixolydian     = {0,2,4,5,7,9,10},
  minor          = {0,2,3,5,7,8,10},
  dorian         = {0,2,3,5,7,9,10},
  phrygian       = {0,1,3,5,7,8,10},
  locrian        = {0,1,3,5,6,8,10},
  harmonic_minor = {0,2,3,5,7,8,11},
}

-- ----------------------------------------------------------------
--  PROGRESSION / FLAVOUR PRESETS
--  Each entry encodes:
--    name     = display name
--    degrees  = scale degree sequence (1-7)
--    qualities = per-chord quality override (nil = follow mode default)
--    cat      = grouping label
--    mode     = (optional) mode key from MODE_NAMES; auto-applied
--               when the preset is selected so chord roots come out
--               correct for any borrowed/modal labels in `name`.
--
--  nil quality means "use whatever the current mode dictates".
--  A non-nil quality overrides the mode for that chord slot.
--
--  IMPORTANT: chord-root semantics rely on SCALE_INTERVALS[mode][deg].
--  Borrowed-chord labels like "bVII", "bVI", "bII", "bIII" only render
--  as those altered roots when `mode` is set to a mode whose scale has
--  that degree flatted. e.g. true bVII needs minor/dorian/phrygian/
--  mixolydian/lydian_dom/locrian (all give deg7 = +10 semitones).
-- ----------------------------------------------------------------
local PROGRESSIONS = {
  -- ── Diatonic (Major-key staples) ─────────────────────────────
  {cat="Diatonic",  name="I  IV  V  I",                            degrees={1,4,5,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  V  vi  IV (Axis)",                    degrees={1,5,6,4},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  IV  vi  V",                           degrees={1,4,6,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="ii  V  I  I",                            degrees={2,5,1,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  vi  IV  V (50s)",                     degrees={1,6,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="vi  IV  I  V",                           degrees={6,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  iii  IV  V",                          degrees={1,3,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  IV  I  V",                            degrees={1,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  vi  ii  V",                           degrees={1,6,2,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  IV  ii  V",                           degrees={1,4,2,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="vi  ii  V  I (circle)",                  degrees={6,2,5,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  V  vi  iii  IV  I  IV  V (Pachelbel)",degrees={1,5,6,3,4,1,4,5}, qualities={nil,nil,nil,nil,nil,nil,nil,nil},       mode="major"},
  {cat="Diatonic",  name="I  IV  V  vi (deceptive)",               degrees={1,4,5,6},         qualities={nil,nil,nil,nil},                       mode="major"},

  -- ── Pop / Folk / Singer-Songwriter ───────────────────────────
  {cat="Pop/Folk",  name="I  V  IV  V",                            degrees={1,5,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  iii  vi  IV",                         degrees={1,3,6,4},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="vi  V  IV  V (descending)",              degrees={6,5,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  V  vi  iii",                          degrees={1,5,6,3},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  IV  vi  iii",                         degrees={1,4,6,3},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  V/vi  vi  IV",                        degrees={1,3,6,4},         qualities={"maj","dom7","min","maj"},              mode="major"},
  {cat="Pop/Folk",  name="vi  IV  V  I (uplift)",                  degrees={6,4,5,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="vi  iii  IV  I (lo-fi)",                 degrees={6,3,4,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  V  vi  IV  I  V  IV  IV (8-bar)",     degrees={1,5,6,4,1,5,4,4}, qualities={nil,nil,nil,nil,nil,nil,nil,nil},       mode="major"},
  {cat="Pop/Folk",  name="I  IV  I  V (folk)",                     degrees={1,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},

  -- ── Ambient / Sus ────────────────────────────────────────────
  {cat="Ambient",   name="I  Vsus4  I  IVsus2",                    degrees={1,5,1,4},         qualities={"maj","sus4","maj","sus2"},             mode="major"},
  {cat="Ambient",   name="Isus2  IVadd9  V  vi",                   degrees={1,4,5,6},         qualities={"sus2","add9",nil,nil},                 mode="major"},
  {cat="Ambient",   name="I  Isus2  Isus4  I",                     degrees={1,1,1,1},         qualities={"maj","sus2","sus4","maj"},             mode="major"},
  {cat="Ambient",   name="vi  IVadd9  Isus2  V",                   degrees={6,4,1,5},         qualities={nil,"add9","sus2",nil},                 mode="major"},
  {cat="Ambient",   name="IVmaj7  Imaj7  vi  V",                   degrees={4,1,6,5},         qualities={"maj7","maj7",nil,nil},                 mode="major"},
  {cat="Ambient",   name="I  IVsus2  vi  Vsus4",                   degrees={1,4,6,5},         qualities={"maj","sus2","min","sus4"},             mode="major"},
  {cat="Ambient",   name="Imaj9  IVmaj9  iii7  vi9",               degrees={1,4,3,6},         qualities={"maj9","maj9","min7","min9"},           mode="major"},
  {cat="Ambient",   name="Imaj7  IImaj7  Imaj7  IImaj7 (Lyd float)",degrees={1,2,1,2},        qualities={"maj7","maj7","maj7","maj7"},           mode="lydian"},
  {cat="Ambient",   name="Imaj7  bVIImaj7  IVmaj7  Imaj7 (Mixo)",  degrees={1,7,4,1},         qualities={"maj7","maj7","maj7","maj7"},           mode="mixolydian"},

  -- ── Neo-Soul / R&B ───────────────────────────────────────────
  {cat="Neo-Soul",  name="Imaj7  IVmaj7  iii7  vi7",               degrees={1,4,3,6},         qualities={"maj7","maj7","min7","min7"},           mode="major"},
  {cat="Neo-Soul",  name="ii7  V7  Imaj7  VI7 (V/ii)",             degrees={2,5,1,6},         qualities={"min7","dom7","maj7","dom7"},           mode="major"},
  {cat="Neo-Soul",  name="Imaj9  vi7  ii7  Vsus4",                 degrees={1,6,2,5},         qualities={"maj9","min7","min7","sus4"},           mode="major"},
  {cat="Neo-Soul",  name="IVmaj7  iii7  ii7  V7",                  degrees={4,3,2,5},         qualities={"maj7","min7","min7","dom7"},           mode="major"},
  {cat="Neo-Soul",  name="Imaj7  bVIImaj7  IVmaj7  Imaj7",         degrees={1,7,4,1},         qualities={"maj7","maj7","maj7","maj7"},           mode="mixolydian"},
  {cat="Neo-Soul",  name="vi7  IVmaj7  Imaj7  V7",                 degrees={6,4,1,5},         qualities={"min7","maj7","maj7","dom7"},           mode="major"},
  {cat="Neo-Soul",  name="im9  IVdom9 (Dorian vamp)",              degrees={1,4},             qualities={"min9","dom9"},                         mode="dorian"},
  {cat="Neo-Soul",  name="Imaj7  iii7  IVmaj7  iv6 (modal mix)",   degrees={1,3,4,4},         qualities={"maj7","min7","maj7","min6"},           mode="major"},
  {cat="Neo-Soul",  name="iii7  vi7  ii9  V13",                    degrees={3,6,2,5},         qualities={"min7","min7","min9","dom9"},           mode="major"},

  -- ── Jazz ─────────────────────────────────────────────────────
  {cat="Jazz",      name="Imaj7  vi7  ii7  V7 (turnaround)",       degrees={1,6,2,5},         qualities={"maj7","min7","min7","dom7"},           mode="major"},
  {cat="Jazz",      name="ii7  V7  Imaj7  Imaj7",                  degrees={2,5,1,1},         qualities={"min7","dom7","maj7","maj7"},           mode="major"},
  {cat="Jazz",      name="iii7  vi7  ii7  V7",                     degrees={3,6,2,5},         qualities={"min7","min7","min7","dom7"},           mode="major"},
  {cat="Jazz",      name="Imaj7  IV7  iii7  bVII7 (backdoor)",     degrees={1,4,3,7},         qualities={"maj7","dom7","min7","dom7"},           mode="mixolydian"},
  {cat="Jazz",      name="vi7  II7  ii7  V7 (V/V)",                degrees={6,2,2,5},         qualities={"min7","dom7","min7","dom7"},           mode="major"},
  {cat="Jazz",      name="iim7b5  V7b9  i (minor ii-V-i)",         degrees={2,5,1},           qualities={"m7b5","7b9","min7"},                   mode="harmonic_minor"},
  {cat="Jazz",      name="Imaj7  bIIImaj7  bVImaj7  bII7 (Coltrane-ish)", degrees={1,3,6,2},  qualities={"maj7","maj7","maj7","dom7"},           mode="phrygian"},
  {cat="Jazz",      name="I6  vi7  ii7  V7 (rhythm changes A)",    degrees={1,6,2,5},         qualities={"6","min7","min7","dom7"},              mode="major"},
  {cat="Jazz",      name="III7  VI7  II7  V7 (rhythm changes B)",  degrees={3,6,2,5},         qualities={"dom7","dom7","dom7","dom7"},           mode="major"},
  {cat="Jazz",      name="Imaj7  vi7  ii7  V7  iii7  VI7  ii7  V7",degrees={1,6,2,5,3,6,2,5}, qualities={"maj7","min7","min7","dom7","min7","dom7","min7","dom7"}, mode="major"},

  -- ── Fusion ───────────────────────────────────────────────────
  {cat="Fusion",    name="im9  IVdom9 (Dorian vamp)",              degrees={1,4},             qualities={"min9","dom9"},                         mode="dorian"},
  {cat="Fusion",    name="Imaj7  IV7 (Lydian Dom)",                degrees={1,4},             qualities={"maj7","dom7"},                         mode="lydian_dom"},
  {cat="Fusion",    name="im7  bIIImaj7  IVmaj7  bVII7",           degrees={1,3,4,7},         qualities={"min7","maj7","maj7","dom7"},           mode="dorian"},
  {cat="Fusion",    name="Imaj7  bVImaj7  bVIImaj7  Imaj7 (mix)",  degrees={1,6,7,1},         qualities={"maj7","maj7","maj7","maj7"},           mode="minor"},
  {cat="Fusion",    name="im9  bIIImaj9  IVmaj7  V7",              degrees={1,3,4,5},         qualities={"min9","maj9","maj7","dom7"},           mode="dorian"},
  {cat="Fusion",    name="Imaj7  iii7  IVmaj7  bVIImaj7",          degrees={1,3,4,7},         qualities={"maj7","min7","maj7","maj7"},           mode="mixolydian"},
  {cat="Fusion",    name="im6  bIImaj7  im6  V7b9",                degrees={1,2,1,5},         qualities={"min6","maj7","min6","7b9"},            mode="phrygian"},

  -- ── Gospel ───────────────────────────────────────────────────
  {cat="Gospel",    name="I  IV  I  V7",                           degrees={1,4,1,5},         qualities={"maj","maj","maj","dom7"},              mode="major"},
  {cat="Gospel",    name="I  IV  V7  I",                           degrees={1,4,5,1},         qualities={"maj","maj","dom7","maj"},              mode="major"},
  {cat="Gospel",    name="I  bVII  IV  I (Mixo)",                  degrees={1,7,4,1},         qualities={"maj","maj","maj","maj"},               mode="mixolydian"},
  {cat="Gospel",    name="vi  IV  I  V7",                          degrees={6,4,1,5},         qualities={"min","maj","maj","dom7"},              mode="major"},
  {cat="Gospel",    name="I  III7  IV  iv (modal mix)",            degrees={1,3,4,4},         qualities={"maj","dom7","maj","min"},              mode="major"},
  {cat="Gospel",    name="I  IV  ii  V7 (turnaround)",             degrees={1,4,2,5},         qualities={"maj","maj","min","dom7"},              mode="major"},
  {cat="Gospel",    name="I  vi  ii  V7 (gospel circle)",          degrees={1,6,2,5},         qualities={"maj","min","min","dom7"},              mode="major"},
  {cat="Gospel",    name="iii7  vi7  ii7  V7",                     degrees={3,6,2,5},         qualities={"min7","min7","min7","dom7"},           mode="major"},

  -- ── Blues ────────────────────────────────────────────────────
  {cat="Blues",     name="12-bar I7-IV7-I7-V7-IV7-I7-V7",          degrees={1,1,1,1,4,4,1,1,5,4,1,5}, qualities={"dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7"}, mode="mixolydian"},
  {cat="Blues",     name="12-bar quick-change",                    degrees={1,4,1,1,4,4,1,1,5,4,1,5}, qualities={"dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7"}, mode="mixolydian"},
  {cat="Blues",     name="Minor blues 12-bar",                     degrees={1,1,1,1,4,4,1,1,5,4,1,5}, qualities={"min7","min7","min7","min7","min7","min7","min7","min7","dom7","min7","min7","dom7"}, mode="harmonic_minor"},
  {cat="Blues",     name="8-bar I7  V7  IV7  IV7  I7  V7  I7  V7", degrees={1,5,4,4,1,5,1,5}, qualities={"dom7","dom7","dom7","dom7","dom7","dom7","dom7","dom7"},                                       mode="mixolydian"},
  {cat="Blues",     name="Turnaround  I7  IV7  I7  V7",            degrees={1,4,1,5},         qualities={"dom7","dom7","dom7","dom7"},           mode="mixolydian"},

  -- ── Funk ─────────────────────────────────────────────────────
  {cat="Funk",      name="im7  IV7 (Dorian vamp)",                 degrees={1,4},             qualities={"min7","dom7"},                         mode="dorian"},
  {cat="Funk",      name="im9  bVII7  IV7  im9",                   degrees={1,7,4,1},         qualities={"min9","dom7","dom7","min9"},           mode="dorian"},
  {cat="Funk",      name="ii7  V7  ii7  V7 (vamp)",                degrees={2,5,2,5},         qualities={"min7","dom7","min7","dom7"},           mode="major"},
  {cat="Funk",      name="I7 vamp (one-chord)",                    degrees={1,1,1,1},         qualities={"dom7","dom7","dom7","dom7"},           mode="mixolydian"},
  {cat="Funk",      name="im7  bIII7  bVII7  IV7",                 degrees={1,3,7,4},         qualities={"min7","dom7","dom7","dom7"},           mode="dorian"},

  -- ── Rock ─────────────────────────────────────────────────────
  {cat="Rock",      name="I  bVII  IV  I (classic)",               degrees={1,7,4,1},         qualities={"maj","maj","maj","maj"},               mode="mixolydian"},
  {cat="Rock",      name="I  V  IV (3-chord)",                     degrees={1,5,4},           qualities={"maj","maj","maj"},                     mode="major"},
  {cat="Rock",      name="I  IV  V  I (anthem)",                   degrees={1,4,5,1},         qualities={"maj","maj","maj","maj"},               mode="major"},
  {cat="Rock",      name="vi  IV  V  I",                           degrees={6,4,5,1},         qualities={"min","maj","maj","maj"},               mode="major"},
  {cat="Rock",      name="I  IV  bVII  IV (Mixo riff)",            degrees={1,4,7,4},         qualities={"maj","maj","maj","maj"},               mode="mixolydian"},
  {cat="Rock",      name="i  bVI  bIII  bVII (epic)",              degrees={1,6,3,7},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="Rock",      name="I5  IV5  V5 (power chords)",             degrees={1,4,5},           qualities={"5","5","5"},                           mode="major"},
  {cat="Rock",      name="i5  bVII5  bVI5  bVII5",                 degrees={1,7,6,7},         qualities={"5","5","5","5"},                       mode="minor"},
  {cat="Rock",      name="I  V  vi  iii  IV  I  IV  V (rock Pachelbel)", degrees={1,5,6,3,4,1,4,5}, qualities={nil,nil,nil,nil,nil,nil,nil,nil}, mode="major"},

  -- ── Post-Hardcore / Metal ────────────────────────────────────
  {cat="Metal",     name="i5  bII5  i5  bII5 (Phrygian)",          degrees={1,2,1,2},         qualities={"5","5","5","5"},                       mode="phrygian"},
  {cat="Metal",     name="i5  bVI5  bVII5  i5",                    degrees={1,6,7,1},         qualities={"5","5","5","5"},                       mode="minor"},
  {cat="Metal",     name="i  bII  bIII  iv (Phrygian dark)",       degrees={1,2,3,4},         qualities={"min","maj","maj","min"},               mode="phrygian"},
  {cat="Metal",     name="i5  bVII5  bVI5  V5 (lament)",           degrees={1,7,6,5},         qualities={"5","5","5","5"},                       mode="phrygian"},
  {cat="Metal",     name="i  V  bVI  iv (harmonic minor)",         degrees={1,5,6,4},         qualities={"min","maj","maj","min"},               mode="harmonic_minor"},
  {cat="Metal",     name="i  bIII  iv  bVII",                      degrees={1,3,4,7},         qualities={"min","maj","min","maj"},               mode="minor"},
  {cat="Metal",     name="i5  bVI5  bIII5  bVII5 (anthem)",        degrees={1,6,3,7},         qualities={"5","5","5","5"},                       mode="minor"},
  {cat="Metal",     name="i  bII  V7  i (Phrygian-dom cadence)",   degrees={1,2,5,1},         qualities={"min","maj","dom7","min"},              mode="phrygian"},
  {cat="Metal",     name="i  bVII  bVI  V7  i (Andalusian cadence)", degrees={1,7,6,5,1},   qualities={"min","maj","maj","dom7","min"},        mode="phrygian"},

  -- ── EDM / Synthwave / Trap ───────────────────────────────────
  {cat="EDM/Synth", name="vi  IV  I  V (festival)",                degrees={6,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="EDM/Synth", name="I  V  vi  IV (anthem)",                  degrees={1,5,6,4},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="EDM/Synth", name="vi  V  IV  V (build)",                   degrees={6,5,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="EDM/Synth", name="i  bVI  bIII  bVII (Synthwave)",         degrees={1,6,3,7},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="EDM/Synth", name="i  bVII  bVI  V (lament wave)",          degrees={1,7,6,5},         qualities={"min","maj","maj","maj"},               mode="phrygian"},
  {cat="EDM/Synth", name="i  bIII  bVII  IV (Dorian synth)",       degrees={1,3,7,4},         qualities={"min","maj","maj","maj"},               mode="dorian"},
  {cat="EDM/Synth", name="i  bVI  bVII  v (trap loop)",            degrees={1,6,7,5},         qualities={"min","maj","maj","min"},               mode="minor"},
  {cat="EDM/Synth", name="i  iv  bVI  bVII (trap dark)",           degrees={1,4,6,7},         qualities={"min","min","maj","maj"},               mode="minor"},
  {cat="EDM/Synth", name="i  bVII  bVI  bVII (cycle)",             degrees={1,7,6,7},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="EDM/Synth", name="i  bIII  v  iv (drill)",                 degrees={1,3,5,4},         qualities={"min","maj","min","min"},               mode="minor"},

  -- ── Latin / Bossa Nova ───────────────────────────────────────
  {cat="Latin",     name="ii7  V7  Imaj7  Imaj7 (bossa)",          degrees={2,5,1,1},         qualities={"min7","dom7","maj7","maj7"},           mode="major"},
  {cat="Latin",     name="Imaj7  VI7  ii7  V7 (bossa turn)",       degrees={1,6,2,5},         qualities={"maj7","dom7","min7","dom7"},           mode="major"},
  {cat="Latin",     name="ii7  V7  iii7  VI7 (bossa cycle)",       degrees={2,5,3,6},         qualities={"min7","dom7","min7","dom7"},           mode="major"},
  {cat="Latin",     name="Imaj7  VI7  ii7  V7  iii7  VI7  ii7  V7",degrees={1,6,2,5,3,6,2,5}, qualities={"maj7","dom7","min7","dom7","min7","dom7","min7","dom7"}, mode="major"},
  {cat="Latin",     name="i  bVII  bVI  V (Andalusian)",           degrees={1,7,6,5},         qualities={"min","maj","maj","maj"},               mode="phrygian"},
  {cat="Latin",     name="i  iv  V7  i (minor latin)",             degrees={1,4,5,1},         qualities={"min","min","dom7","min"},              mode="harmonic_minor"},
  {cat="Latin",     name="im7  IV7 (Latin Dorian vamp)",           degrees={1,4},             qualities={"min7","dom7"},                         mode="dorian"},

  -- ── Reggae ───────────────────────────────────────────────────
  {cat="Reggae",    name="I  IV  V  V (one-drop)",                 degrees={1,4,5,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Reggae",    name="I  V  vi  IV (skank)",                   degrees={1,5,6,4},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Reggae",    name="vi  IV  V  V",                           degrees={6,4,5,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Reggae",    name="I  IV  I  V",                            degrees={1,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Reggae",    name="i  bVII  i  bVII (rockers)",             degrees={1,7,1,7},         qualities={"min","maj","min","maj"},               mode="minor"},
  {cat="Reggae",    name="ii  V  I  I (rocksteady)",               degrees={2,5,1,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Reggae",    name="i  iv  v  i (minor reggae)",             degrees={1,4,5,1},         qualities={"min","min","min","min"},               mode="minor"},

  -- ── Cinematic ────────────────────────────────────────────────
  {cat="Cinematic", name="i  bVI  bVII  i",                        degrees={1,6,7,1},         qualities={"min","maj","maj","min"},               mode="minor"},
  {cat="Cinematic", name="i  iv  bVI  V (harmonic minor)",         degrees={1,4,6,5},         qualities={"min","min","maj","maj"},               mode="harmonic_minor"},
  {cat="Cinematic", name="Imaj7  bVImaj7  bVIImaj7  Imaj7 (mix)",  degrees={1,6,7,1},         qualities={"maj7","maj7","maj7","maj7"},           mode="minor"},
  {cat="Cinematic", name="i  bVII  bVI  bVII",                     degrees={1,7,6,7},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="Cinematic", name="i  bIII  bVI  bVII",                     degrees={1,3,6,7},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="Cinematic", name="Iaug  bVI  bVII  i (epic)",              degrees={1,6,7,1},         qualities={"aug","maj","maj","min"},               mode="minor"},
  {cat="Cinematic", name="i  bII  i  V7 (Phrygian dom)",           degrees={1,2,1,5},         qualities={"min","maj","min","dom7"},              mode="phrygian"},
  {cat="Cinematic", name="i  bIII  iv  bVI (lament)",              degrees={1,3,4,6},         qualities={"min","maj","min","maj"},               mode="minor"},
  {cat="Cinematic", name="i  V/iv  iv  V (trailer build)",         degrees={1,1,4,5},         qualities={"min","dom7","min","maj"},              mode="harmonic_minor"},

  -- ── Modal Colour ─────────────────────────────────────────────
  {cat="Modal",     name="i  bII  bVII  i (Phrygian)",             degrees={1,2,7,1},         qualities={"min","maj","maj","min"},               mode="phrygian"},
  {cat="Modal",     name="I  II  I  II (Lydian)",                  degrees={1,2,1,2},         qualities={"maj","maj","maj","maj"},               mode="lydian"},
  {cat="Modal",     name="I  bVII  IV  I (Mixolydian)",            degrees={1,7,4,1},         qualities={"maj","maj","maj","maj"},               mode="mixolydian"},
  {cat="Modal",     name="i  IV  i  bVII (Dorian)",                degrees={1,4,1,7},         qualities={"min","maj","min","maj"},               mode="dorian"},
  {cat="Modal",     name="i  VI  bIII  bVII (Dorian)",             degrees={1,6,3,7},         qualities={"min","maj","maj","maj"},               mode="dorian"},
  {cat="Modal",     name="Imaj7  IImaj7  V7  Imaj7 (Lyd)",         degrees={1,2,5,1},         qualities={"maj7","maj7","dom7","maj7"},           mode="lydian"},
  {cat="Modal",     name="Imaj7  bVII7  Imaj7 (Lyd Dom)",          degrees={1,7,1,7},         qualities={"maj7","dom7","maj7","dom7"},           mode="lydian_dom"},
  {cat="Modal",     name="i  bII  iv  V7 (Phryg dom)",             degrees={1,2,4,5},         qualities={"min","maj","min","dom7"},              mode="phrygian"},

  -- ── Classical ────────────────────────────────────────────────
  {cat="Classical", name="I  IV  V  I (perfect cadence)",          degrees={1,4,5,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Classical", name="I  V  vi  iii  IV  I  IV  V (Pachelbel)",degrees={1,5,6,3,4,1,4,5}, qualities={nil,nil,nil,nil,nil,nil,nil,nil},       mode="major"},
  {cat="Classical", name="I  IV  V  vi (deceptive)",               degrees={1,4,5,6},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Classical", name="I  IV  I (plagal/amen)",                 degrees={1,4,1},           qualities={nil,nil,nil},                           mode="major"},
  {cat="Classical", name="i  iv  V7  I (Picardy)",                 degrees={1,4,5,1},         qualities={"min","min","dom7","maj"},              mode="harmonic_minor"},
  {cat="Classical", name="i  bVII  bVI  V (lament bass)",          degrees={1,7,6,5},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="Classical", name="bII  V7  i (Neapolitan)",                degrees={2,5,1},           qualities={"maj","dom7","min"},                    mode="phrygian"},
  {cat="Classical", name="i  iv  V7  i (minor cadence)",           degrees={1,4,5,1},         qualities={"min","min","dom7","min"},              mode="harmonic_minor"},
  {cat="Classical", name="I  vi  IV  V  I (extended cadence)",     degrees={1,6,4,5,1},       qualities={nil,nil,nil,nil,nil},                   mode="major"},
  {cat="Classical", name="I  V/V  V  I (secondary dom)",           degrees={1,2,5,1},         qualities={"maj","dom7","maj","maj"},              mode="major"},

  -- ── Custom ───────────────────────────────────────────────────
  {cat="Custom",    name="Custom",                                 degrees={},                qualities={},                                      mode=nil},
}

-- (PROG_NAMES, QUALITY_LIST, QUALITY_DISPLAY replaced by grouped item tables below)

-- Arp rate options
local ARP_RATES = {
  {label="1/4",   beats=1.0},
  {label="1/8",   beats=0.5},
  {label="1/16",  beats=0.25},
  {label="1/16T", beats=1/6},
  {label="1/32",  beats=0.125},
}
local ARP_RATE_NAMES = {}
for _, r in ipairs(ARP_RATES) do ARP_RATE_NAMES[#ARP_RATE_NAMES+1] = r.label end

-- Accent grid options
local ACCENT_GRID = {
  {label="1/4",   beats=1.0},
  {label="1/8",   beats=0.5},
  {label="1/16",  beats=0.25},
  {label="1/16T", beats=1/6},
  {label="1/32",  beats=0.125},
}
local ACCENT_GRID_NAMES = {}
for _, g in ipairs(ACCENT_GRID) do ACCENT_GRID_NAMES[#ACCENT_GRID_NAMES+1] = g.label end

local ARP_PATTERNS = {"Up","Down","Up-Down","Down-Up","Random","Chord","Weave","Pedal","Skip"}

-- Melody duration grid — all valid note lengths in beats (quarter = 1 beat)
local MEL_DURATIONS = {
  {label="1/32", beats=0.125},
  {label="1/16", beats=0.25},
  {label="1/8",  beats=0.5},
  {label="1/4",  beats=1.0},
  {label="3/8",  beats=1.5},   -- dotted 1/4
  {label="1/2",  beats=2.0},
  {label="3/4",  beats=3.0},   -- dotted 1/2
  {label="1/1",  beats=4.0},
}
local MEL_DUR_NAMES = {}
for _, d in ipairs(MEL_DURATIONS) do MEL_DUR_NAMES[#MEL_DUR_NAMES+1] = d.label end

-- Melody generation presets
local MEL_PRESETS = {
  "Free",           -- 1: weighted random walk, gap fill, chord-tone bias
  "Flowing",        -- 2: smooth noise-driven pitch curve, stepwise
  "Structured",     -- 3: contour following + rhythmic motif repetition
  "Conversational", -- 4: Markov chain + tension/release
  "Mechanical",     -- 5: strict intervallic rules, minimal randomness
  "Phrase & Answer",-- 6: antecedent/consequent call-and-response
  "Fractal",        -- 7: L-system style self-similar motif expansion
  "Motif",          -- 8: seed cell repeated with variation
}

local BASS_STYLES = {"Root", "Root-Fifth", "Walking", "Boogie", "Pattern"}
-- Pattern step note values: 0=rest, 1=root, 2=fifth, 3=oct-up
local BASS_PAT_LABELS = {"·", "R", "5", "8"}

-- ----------------------------------------------------------------
--  STATE
-- ----------------------------------------------------------------
local state = {
  root_idx  = 1,
  mode_idx  = 1,
  octave    = 4,

  prog_idx         = 1,
  custom_degrees   = {1,4,5,1},
  chord_durations  = {},
  chord_inversions = {},
  chord_quality_overrides = {},  -- nil entry = follow mode; string = override quality

  -- Chord layer
  chord_track_name = "Chords",
  chord_channel    = 0,
  chord_enabled    = true,
  chord_velocity   = 80,

  -- Arp layer
  arp_enabled      = true,
  arp_track_name   = "Arp",
  arp_channel      = 1,
  arp_rate_idx     = 3,
  arp_pattern_idx  = 1,
  arp_octaves      = 2,
  arp_gate         = 80,
  arp_velocity     = 90,
  arp_vel_human    = 15,
  arp_note_prob    = 100,
  arp_beat1_prob   = 100,
  arp_beatn_prob   = 100,
  arp_beatn_idx    = 2,
  arp_rigidity     = 0,

  -- Melody layer
  mel_enabled      = true,
  mel_track_name   = "Melody",
  mel_channel      = 2,          -- 0-based (MIDI ch 3)
  mel_preset_idx   = 1,          -- index into MEL_PRESETS
  mel_min_dur_idx  = 2,          -- default min = 1/16
  mel_max_dur_idx  = 6,          -- default max = 1/2
  mel_velocity     = 85,
  mel_vel_human    = 20,
  mel_oct_min      = 4,          -- minimum octave for melody
  mel_oct_max      = 5,          -- maximum octave for melody
  mel_busyness     = 45,         -- 0=sparse/long-held, 100=dense/clustered bursts
  mel_rigidity     = 30,         -- 0=chord tones only, 100=full scale (post-filter)
  mel_colour       = 0,          -- 0=scale only, 100=chromatic passing tones allowed
  mel_metre        = 50,         -- 0=free (no beat awareness), 100=strong beat enforcement
  mel_render_cycles = 4,         -- offline write: number of progression cycles to render

  -- Melody live preview
  mel_live_enabled  = false,
  mel_live_note     = -1,
  mel_live_note_end = -1,
  mel_live_events   = nil,
  mel_live_total_beats = 0,
  mel_live_last_idx = -1,
  mel_wait_boundary = false,

  -- Bass layer
  bass_enabled       = false,
  bass_track_name    = "Bass",
  bass_channel       = 3,          -- 0-based (MIDI ch 4)
  bass_style_idx     = 1,          -- index into BASS_STYLES
  bass_oct           = 2,          -- octave anchor for bass notes
  bass_follow_inv    = false,      -- honour chord inversion for bass note selection
  bass_velocity      = 90,
  bass_vel_human     = 10,
  bass_gate          = 90,
  bass_approach_prob = 70,         -- Walking: prob (0-100) of chromatic approach on last beat
  -- Pattern style
  bass_pattern_steps    = 4,
  bass_pattern_grid_idx = 2,       -- index into ARP_RATES; default 1/8
  bass_pattern_notes    = {1,0,1,2, 0,0,0,0},  -- 0=rest,1=root,2=fifth,3=oct

  -- Bass live preview
  bass_live_enabled   = false,
  bass_live_note      = -1,
  bass_live_note_end  = -1,
  bass_live_events    = nil,
  bass_live_total_beats = 0,
  bass_live_last_idx  = -1,
  bass_wait_boundary  = false,

  -- Seed / keep
  seed        = math.floor(reaper.time_precise() * 1000) % 99999,
  seed_str    = "",
  seed_locked = false,

  -- PPQ
  ppq_per_beat = 960,

  -- Time signature
  timesig_num   = 4,
  timesig_denom = 4,

  -- Live chord preview
  live_enabled        = false,
  last_chord_idx      = -1,
  last_notes_on       = {},
  chord_wait_boundary = false,

  -- Live arp preview
  arp_live_enabled     = false,
  arp_live_notes_on    = {},
  arp_live_note_end    = -1,
  arp_live_last_idx    = -1,
  arp_live_events      = nil,
  arp_live_total_beats = 0,
  arp_wait_boundary    = false,

  status_msg = "Ready.",
}

local function init_chord_arrays(n)
  state.chord_durations       = {}
  state.chord_inversions      = {}
  state.chord_quality_overrides = {}
  for i = 1, n do
    state.chord_durations[i]        = 1
    state.chord_inversions[i]       = 0
    state.chord_quality_overrides[i] = nil  -- auto = follow mode
  end
end

-- Load quality overrides from a preset's qualities array.
-- nil entries in the preset become nil overrides (auto).
local function load_preset_qualities(preset, n)
  state.chord_quality_overrides = {}
  for i = 1, n do
    local q = preset.qualities and preset.qualities[i]
    state.chord_quality_overrides[i] = q  -- nil or quality string
  end
end
init_chord_arrays(4)
load_preset_qualities(PROGRESSIONS[state.prog_idx], 4)
state.seed_str = tostring(state.seed)

-- ----------------------------------------------------------------
--  SEEDED RNG
-- ----------------------------------------------------------------
local function rng_seed(s) math.randomseed(s) end
local function rng_float()  return math.random() end
local function rng_int(a,b) return math.random(a,b) end

-- Isolated RNG stream for bass: derived from state.seed so same seed → same bass,
-- but independent of the arp/melody stream so neither can shift the other.
local function bass_rng_reseed()
  rng_seed((state.seed * 1664525 + 1013904223) % 99991 + 1)
end

-- ----------------------------------------------------------------
--  TIME SIGNATURE HELPERS
-- ----------------------------------------------------------------
local function get_timesig_at(proj_time)
  local num, denom = reaper.TimeMap_GetTimeSigAtTime(0, proj_time)
  if not num or num < 1 then num = 4 end
  if not denom or denom < 1 then denom = 4 end
  return num, denom
end
local function get_timesig_at_cursor()  return get_timesig_at(reaper.GetCursorPosition()) end
local function get_timesig_at_playpos() return get_timesig_at(reaper.GetPlayPosition())   end
local function bars_to_beats(bars, num) return bars * num end

-- ----------------------------------------------------------------
--  MUSIC THEORY HELPERS
-- ----------------------------------------------------------------
local function midi_note(note_idx, octave)
  return (octave + 1) * 12 + (note_idx - 1)
end

local function degree_root_midi(root_idx, mode, deg, octave)
  return midi_note(root_idx, octave) + SCALE_INTERVALS[mode][deg]
end

local function build_chord(root_midi, quality, inversion)
  local ivs = CHORD_INTERVALS[quality] or CHORD_INTERVALS["maj"]
  local notes = {}
  for _, iv in ipairs(ivs) do notes[#notes+1] = root_midi + iv end
  local inv = inversion % #notes
  for _ = 1, inv do
    local lo = table.remove(notes, 1)
    notes[#notes+1] = lo + 12
  end
  return notes
end

local function current_degrees()
  local p = PROGRESSIONS[state.prog_idx]
  return (p.name == "Custom") and state.custom_degrees or p.degrees
end

local function build_progression()
  local degrees   = current_degrees()
  local mode      = MODE_NAMES[state.mode_idx]
  local qualities = MODE_CHORDS[mode]
  local num       = state.timesig_num
  local result    = {}
  for i, deg in ipairs(degrees) do
    -- Quality: use per-chord override if set, else mode default
    local override = state.chord_quality_overrides[i]
    local quality  = override or qualities[deg] or "maj"
    local root_m   = degree_root_midi(state.root_idx, mode, deg, state.octave)
    local inv      = state.chord_inversions[i] or 0
    local dur_bars = state.chord_durations[i]  or 1
    local dur_beats = bars_to_beats(dur_bars, num)
    local notes    = build_chord(root_m, quality, inv)
    local root_name = NOTE_NAMES[(root_m % 12) + 1]
    local override_marker = override and ("*"..override) or ""
    result[#result+1] = {
      notes     = notes,
      quality   = quality,
      degree    = deg,
      duration  = dur_beats,
      dur_bars  = dur_bars,
      inversion = inv,
      root_midi = root_m,                 -- root regardless of inversion
      bass_midi = notes[1],               -- actual bass after inversion
      is_override = override ~= nil,
      label    = root_name.." "..quality..(inv>0 and (" inv"..inv) or "")
                 ..(override and " *" or ""),
    }
  end
  return result
end

-- Return sorted list of scale MIDI pitches across mel_oct_min..mel_oct_max
local function scale_notes_in_range()
  local mode     = MODE_NAMES[state.mode_idx]
  local ivs      = SCALE_INTERVALS[mode]
  local root_pc  = (state.root_idx - 1) % 12
  local notes    = {}
  for oct = state.mel_oct_min - 1, state.mel_oct_max do
    for _, iv in ipairs(ivs) do
      local p = (oct + 1) * 12 + ((root_pc + iv) % 12)
      if p >= (state.mel_oct_min) * 12 and p <= (state.mel_oct_max + 1) * 12 - 1 then
        notes[#notes+1] = p
      end
    end
  end
  table.sort(notes)
  -- Deduplicate
  local deduped = {}
  for i, n in ipairs(notes) do
    if i == 1 or n ~= notes[i-1] then deduped[#deduped+1] = n end
  end
  return deduped
end

-- Return chord tone pitches within the melody range
local function chord_notes_in_range(chord_notes)
  local pcs = {}
  for _, n in ipairs(chord_notes) do pcs[n % 12] = true end
  local result = {}
  for p = state.mel_oct_min * 12, (state.mel_oct_max + 1) * 12 - 1 do
    if pcs[p % 12] then result[#result+1] = p end
  end
  return result
end

-- Find index of nearest note in a sorted list to a given pitch
local function nearest_idx(notes, pitch)
  local best, best_dist = 1, 999
  for i, n in ipairs(notes) do
    local d = math.abs(n - pitch)
    if d < best_dist then best, best_dist = i, d end
  end
  return best
end

-- ----------------------------------------------------------------
--  HARMONIC / VOICE-LEADING HELPERS (shared)
--
--  These are deliberately generator-agnostic so that the future bass
--  layer can reuse them: chord-tone identification, root/bass lookup,
--  voice-leading toward a chord, diatonic neighbour/leading-tone/
--  enclosure builders, phrase-arc tension state.
--
--  Convention:
--    chord_pcs   = set { [pc]=true } of chord pitch-classes
--    scale_pcs   = set { [pc]=true } of scale pitch-classes
--    scale_notes = sorted list of MIDI pitches in current melody range
--    chord_range = sorted list of chord-tone MIDI pitches in range
-- ----------------------------------------------------------------

-- Pitch-class set of the current scale.
local function scale_pc_set()
  local mode    = MODE_NAMES[state.mode_idx]
  local ivs     = SCALE_INTERVALS[mode]
  local root_pc = (state.root_idx - 1) % 12
  local pcs     = {}
  for _, iv in ipairs(ivs) do pcs[(root_pc + iv) % 12] = true end
  return pcs
end

-- Pitch-class set of a chord's notes.
local function chord_pc_set(chord_notes)
  local pcs = {}
  for _, n in ipairs(chord_notes) do pcs[n % 12] = true end
  return pcs
end

local function is_chord_tone(pitch, chord_pcs) return chord_pcs[pitch % 12] == true end
local function is_scale_tone(pitch, scale_pcs) return scale_pcs[pitch % 12] == true end

-- Snap a pitch to the nearest chord tone within a sorted chord_range.
local function nearest_chord_tone(pitch, chord_range)
  if #chord_range == 0 then return pitch end
  local best, best_d = chord_range[1], 999
  for _, n in ipairs(chord_range) do
    local d = math.abs(n - pitch)
    if d < best_d then best, best_d = n, d end
  end
  return best
end

-- Pick a chord tone that voice-leads from prev_pitch: prefers stepwise
-- (≤2 semitones), falls back to smallest leap. Used for chord-change landings
-- and for future bass landings on chord roots.
local function voice_lead_to_chord(prev_pitch, chord_range, max_leap)
  if #chord_range == 0 then return prev_pitch end
  max_leap = max_leap or 7
  local best, best_score = chord_range[1], math.huge
  for _, n in ipairs(chord_range) do
    local d = math.abs(n - prev_pitch)
    -- Stepwise heavily preferred; small leaps OK; large leaps penalised.
    local score
    if d == 0 then score = 0.5      -- common-tone retention is fine
    elseif d <= 2 then score = d    -- step
    elseif d <= max_leap then score = d * 1.5
    else score = d * 3 end
    if score < best_score then best, best_score = n, score end
  end
  return best
end

-- Find the index in scale_notes that maps to a given pitch (or nearest).
local function scale_index_of(scale_notes, pitch)
  return nearest_idx(scale_notes, pitch)
end

-- Diatonic step from a pitch by n scale steps (negative = down).
local function diatonic_step(scale_notes, pitch, n)
  local i = nearest_idx(scale_notes, pitch)
  local j = math.max(1, math.min(#scale_notes, i + n))
  return scale_notes[j]
end

-- Diatonic neighbour of pitch (dir = +1 upper, -1 lower).
local function diatonic_neighbor(scale_notes, pitch, dir)
  return diatonic_step(scale_notes, pitch, dir >= 0 and 1 or -1)
end

-- Leading-tone (semitone below) approach to a target.
local function leading_tone_to(target_pitch) return target_pitch - 1 end

-- Chromatic enclosure to a target: returns {upper_diatonic, lower_chromatic}
-- that resolve into the target by step.
local function chromatic_enclosure_to(scale_notes, target_pitch)
  local upper = diatonic_step(scale_notes, target_pitch, 1)
  local lower = target_pitch - 1
  return upper, lower
end

-- ----------------------------------------------------------------
--  PHRASE-ARC / TENSION SCAFFOLDING
--
--  Long-term goal: shape pitch and chord-tone bias across N bars so the
--  melody arcs (low tension at the start, peak in the middle, resolve
--  at the end). This is intentionally minimal for now — it stores the
--  arc on the generation context and exposes a single tension(0..1)
--  value at any absolute beat. Generators consult it as a soft bias on
--  chord-tone vs scale-tone selection. Rhythm is *not* affected (the
--  DAW owns groove); this is purely about pitch colour over time.
--
--  Future work:
--    - per-progression peak placement (e.g. golden-section)
--    - multi-arc nesting (4-bar antecedent, 4-bar consequent, …)
--    - cadence-aware drop at progression end
-- ----------------------------------------------------------------

local function phrase_arc_init(context, total_beats, cycle_offset)
  -- Re-initialised each cycle so the arc shape repeats per progression
  -- pass; cycle_offset rebases tension calc onto the current cycle.
  context.phrase_arc = {
    total_beats  = math.max(1, total_beats or 1),
    cycle_offset = cycle_offset or 0,
    peak_frac    = 0.6,
    peak_value   = 0.85,           -- max tension
    base_value   = 0.10,           -- tension at start/end
    shape        = "arch",
  }
end

-- Returns 0..1 tension at the given absolute beat. 0 = full repose
-- (chord-tone dominated), 1 = peak tension (more scale tones, larger
-- intervals, leading tones welcome).
local function phrase_arc_tension(context, abs_beat)
  local pa = context.phrase_arc
  if not pa then return 0.0 end
  local rel = abs_beat - (pa.cycle_offset or 0)
  local t = math.max(0, math.min(1, rel / pa.total_beats))
  local v
  if pa.shape == "arch" then
    -- Asymmetric arch with peak at peak_frac.
    if t < pa.peak_frac then
      v = t / pa.peak_frac
    else
      v = 1.0 - (t - pa.peak_frac) / math.max(0.01, 1.0 - pa.peak_frac)
    end
  else
    v = 0.5
  end
  return pa.base_value + (pa.peak_value - pa.base_value) * v
end

-- Returns 0..1 rhythmic density at the given absolute beat.
--  - At low busyness: nearly flat, low value (sparse, long-held notes).
--  - At mid busyness: a mild arch tracking the phrase arc.
--  - At high busyness: a pronounced arch — bursts cluster at the crest,
--    sparser at the edges so the line still breathes.
-- Density is consumed by the rest gate and by pick_dur_slots' duration
-- bias; clustering of short notes therefore emerges from the same arc
-- shape that drives pitch tension, rather than a parallel system.
local function phrase_arc_density(context, abs_beat)
  local busy = (state.mel_busyness or 50) / 100.0
  local pa = context.phrase_arc
  local arch = 0.5
  if pa then
    local rel = abs_beat - (pa.cycle_offset or 0)
    local t = math.max(0, math.min(1, rel / pa.total_beats))
    if t < pa.peak_frac then
      arch = t / math.max(0.01, pa.peak_frac)
    else
      arch = 1.0 - (t - pa.peak_frac) / math.max(0.01, 1.0 - pa.peak_frac)
    end
  end
  -- Amplitude grows with busyness so low values stay flat and high
  -- values swing strongly between trough and crest.
  local amplitude = 0.45 * busy
  local v = busy + amplitude * (arch - 0.5)
  return math.max(0, math.min(1, v))
end

-- ----------------------------------------------------------------
--  CHORD-TONE LANDING RULE
--
--  At chord-block starts and on strong beats, prefer (or require) the
--  pitch to be a chord tone. This is what gives a melody the sense
--  that it's being played *over the chords* rather than *despite* them.
--
--  Returns a probability in [0,1] that the next note should be a chord
--  tone, given:
--    - is_block_start: true if this is the first onset of a new chord
--    - metric_weight : 0..1 from metrical_weight()
--    - tension       : 0..1 from phrase_arc_tension()
--
--  At low tension the rule is strict; at high tension it relaxes so
--  the line can climb away from the harmony before resolving.
-- ----------------------------------------------------------------
local function chord_tone_landing_prob(is_block_start, metric_weight, tension)
  tension = tension or 0
  local p = 0
  if is_block_start         then p = math.max(p, 0.95) end
  if metric_weight >= 0.95  then p = math.max(p, 0.85) end   -- downbeat
  if metric_weight >= 0.55  then p = math.max(p, 0.55) end   -- mid-bar
  if metric_weight >= 0.30  then p = math.max(p, 0.30) end   -- whole beat
  -- Tension relaxes the rule by up to ~40%.
  p = p * (1.0 - 0.4 * tension)
  return p
end

-- ----------------------------------------------------------------
--  GRID-QUANTISED MELODY PLACEMENT
--
--  Core principle: every note onset and endpoint is expressed as
--  an integer number of grid steps. The grid step = min duration.
--  Floating point only appears when converting to beats for output.
--  Accumulation drift is impossible because all arithmetic is integer.
--
--  Metre controls which grid slots are eligible for note onsets:
--    0   = any slot (fully free)
--    50  = quarter-note beats and stronger preferred
--    100 = only the strongest beats (downbeat, mid-bar)
-- ----------------------------------------------------------------

-- Return the metrical weight of a grid slot position.
-- slot_abs = absolute position in grid steps from project start.
-- grid     = beats per grid step (min duration in beats).
local function metrical_weight(slot_abs, grid)
  local abs_beat    = slot_abs * grid
  local num         = state.timesig_num
  local beat_in_bar = abs_beat % num
  local tol         = grid * 0.01  -- 1% of grid step tolerance

  -- Downbeat
  if beat_in_bar < tol then return 1.0 end

  -- Whole beat
  local beat_frac = beat_in_bar % 1.0
  if beat_frac < tol or (1.0 - beat_frac) < tol then
    local beat_num = math.floor(beat_in_bar + 0.5) + 1
    if num >= 4 and beat_num == math.floor(num / 2) + 1 then
      return 0.6   -- mid-bar (beat 3 in 4/4)
    end
    return 0.35
  end

  -- Half-beat subdivision
  if math.abs(beat_frac - 0.5) < tol then return 0.2 end

  -- Off-beat subdivision
  return 0.1
end

-- Build a list of valid onset slots within a block, weighted by metre.
-- block_slots = block duration in grid steps.
-- abs_start_slot = absolute slot index of block start from project start.
-- Returns list of {slot, weight} sorted by slot ascending.
local function build_onset_candidates(block_slots, abs_start_slot, grid)
  local metre   = state.mel_metre / 100.0
  local candidates = {}

  for s = 0, block_slots - 1 do
    local mw = metrical_weight(abs_start_slot + s, grid)

    -- Gate: at metre=0 all slots pass; at metre=1 every whole beat passes
    -- and sub-beat positions are rejected. Threshold is capped at 0.35
    -- (the weight of a generic whole beat) so metre=1 doesn't degenerate
    -- to bar-downbeat-only. Sub-threshold slots admit probabilistically,
    -- with the probability scaled by (1 - metre) so it vanishes at the top.
    local include
    if metre < 0.01 then
      include = true
    elseif mw >= 1.0 - 0.01 then
      include = true   -- downbeats always pass
    else
      local pass_threshold = math.min(0.35, metre * 0.9)
      if mw >= pass_threshold then
        include = true
      else
        local admit_prob = (mw / pass_threshold) * (1 - metre)
        include = rng_float() < admit_prob
      end
    end

    if include then
      candidates[#candidates+1] = {slot=s, weight=mw}
    end
  end

  -- Always guarantee at least the first slot (downbeat) is a candidate
  if #candidates == 0 then
    candidates[1] = {slot=0, weight=1.0}
  end

  return candidates
end

-- Pick a duration in grid steps from the valid range.
-- Prefers longer durations on strong beats, shorter on weak beats.
-- All arithmetic stays integer (grid steps).
local function pick_dur_slots(onset_slot, abs_start_slot, grid,
                               min_slots, max_slots, remaining_slots)
  local cap    = math.min(max_slots, remaining_slots)
  if cap < min_slots then return min_slots end

  local mw     = metrical_weight(abs_start_slot + onset_slot, grid)
  local metre  = state.mel_metre / 100.0
  local busy   = (state.mel_busyness or 50) / 100.0

  -- Build list of candidate durations (integer multiples of min_slots
  -- that correspond to valid MEL_DURATIONS grid values)
  local valid = {}
  for _, d in ipairs(MEL_DURATIONS) do
    local slots = math.floor(d.beats / grid + 0.5)
    if slots >= min_slots and slots <= cap then
      -- Avoid duplicates
      local dup = false
      for _, v in ipairs(valid) do if v == slots then dup=true; break end end
      if not dup then valid[#valid+1] = slots end
    end
  end
  if #valid == 0 then return math.min(min_slots, remaining_slots) end
  table.sort(valid)

  -- Duration bias: strong onset → prefer longer; weak onset → prefer shorter.
  -- Busyness then shears the bias: low busy → push toward longer regardless
  -- of metric weight; high busy → push toward shorter so subdivision bursts
  -- become the default. The two terms are blended, so metre still matters.
  local weights = {}
  local total   = 0
  for i, _ in ipairs(valid) do
    local norm = i / #valid  -- 0..1, short→long
    local bias
    if mw >= 0.9 then
      bias = norm                          -- downbeat: longer preferred
    elseif mw >= 0.5 then
      bias = 1.0 - math.abs(norm - 0.5)   -- mid-beat: medium preferred
    else
      bias = 1.0 - norm                   -- weak: shorter preferred
    end
    bias = math.max(0.05, bias)
    -- Busy bias: 0→favour long (norm), 1→favour short (1-norm).
    local busy_bias = math.max(0.05, (1.0 - busy) * norm + busy * (1.0 - norm))
    local metric_term = (1.0 - metre) * (1.0 / #valid) + metre * bias
    -- Busyness influence grows toward the extremes (|busy-0.5|), so a
    -- mid setting leaves the metric/metre logic mostly untouched.
    local busy_strength = math.abs(busy - 0.5) * 2.0 * 0.7
    local w = (1.0 - busy_strength) * metric_term + busy_strength * busy_bias
    weights[i] = w
    total = total + w
  end

  local r = rng_float() * total
  local acc = 0
  for i, w in ipairs(weights) do
    acc = acc + w
    if r <= acc then
      -- Endpoint snap: at high metre OR high busyness, extend a sub-beat
      -- duration to the next quarter so subdivision bursts begin and end
      -- on quarter-note boundaries rather than drifting across them.
      local chosen = valid[i]
      local snap_drive = math.max(metre, busy)
      if snap_drive >= 0.5 then
        local endpoint_slot = onset_slot + chosen
        local endpoint_abs  = (abs_start_slot + endpoint_slot) * grid
        local beat_frac     = endpoint_abs % 1.0
        local tol           = grid * 0.02
        -- If endpoint is not on a beat, try snapping forward to next beat
        if beat_frac > tol and (1.0 - beat_frac) > tol then
          local beats_to_next = 1.0 - beat_frac
          local snap_slots    = math.floor(beats_to_next / grid + 0.5)
          local snapped       = chosen + snap_slots
          if snapped >= min_slots and snapped <= cap then
            local snap_prob = (snap_drive - 0.5) * 2.0
            if rng_float() < snap_prob then chosen = snapped end
          end
        end
        -- Phrase-end hold: absorb tiny gap to barline
        local abs_onset_beat = (abs_start_slot + onset_slot) * grid
        local bar_remain     = state.timesig_num - (abs_onset_beat % state.timesig_num)
        if bar_remain < 0.001 then bar_remain = state.timesig_num end
        local bar_remain_slots = math.floor(bar_remain / grid + 0.5)
        local gap = bar_remain_slots - chosen
        if gap > 0 and gap <= min_slots and chosen + gap <= cap then
          chosen = chosen + gap
        end
      end
      -- Low-busyness stretch: bias toward filling the chord block with a
      -- single sustained note when we're already on a strong beat.
      if busy <= 0.2 and mw >= 0.55 then
        local stretch_prob = (0.2 - busy) * 5.0  -- 0..1 across busy 0..0.2
        if rng_float() < stretch_prob then
          chosen = math.min(cap, valid[#valid])
        end
      end
      return math.max(min_slots, math.min(cap, chosen))
    end
  end
  return valid[#valid]
end

-- Plain duration picker for seed-time use (no metre influence)
local function pick_duration(min_beats, max_beats)
  local valid = {}
  for _, d in ipairs(MEL_DURATIONS) do
    if d.beats >= min_beats - 0.001 and d.beats <= max_beats + 0.001 then
      valid[#valid+1] = d.beats
    end
  end
  if #valid == 0 then return min_beats end
  return valid[rng_int(1, #valid)]
end

-- Apply rigidity post-filter: if note is not a chord tone and
-- rng < (1 - rigidity/100), snap to nearest chord tone.
-- (Kept as the final safety net; generators now compose with chord
-- tones up-front, so this fires far less often.)
local function apply_rigidity(pitch, chord_notes_range)
  if state.mel_rigidity >= 100 then return pitch end
  if #chord_notes_range == 0 then return pitch end
  if is_chord_tone(pitch, chord_pc_set(chord_notes_range)) then return pitch end
  local snap_prob = 1.0 - (state.mel_rigidity / 100.0)
  if rng_float() < snap_prob then
    return nearest_chord_tone(pitch, chord_notes_range)
  end
  return pitch
end

-- ----------------------------------------------------------------
--  COLOUR-TONE LIBRARY
--
--  A small palette of musical embellishments inserted between a
--  previous pitch and the upcoming pitch. All gated by mel_colour;
--  individual figures additionally require a structural condition
--  (e.g. leading tones only resolve into a chord tone). Each call
--  consumes at most one min-grid step of duration from the upcoming
--  note.
--
--  Returns a colour pitch (number) or nil if no figure is appropriate.
-- ----------------------------------------------------------------
local function maybe_insert_colour(from_pitch, to_pitch, scale_notes,
                                    scale_pcs, chord_pcs, target_is_strong)
  if state.mel_colour == 0 then return nil end
  local colour_prob = state.mel_colour / 100.0
  if rng_float() > colour_prob then return nil end

  local diff = to_pitch - from_pitch

  -- 1. Leading-tone approach into a chord tone on a strong position.
  if target_is_strong and is_chord_tone(to_pitch, chord_pcs) then
    -- Only if approach by step from below is musical (avoid huge backtrack).
    if math.abs(diff) <= 4 and rng_float() < 0.5 then
      local lt = leading_tone_to(to_pitch)
      if math.abs(lt - from_pitch) <= 5 then return lt end
    end
  end

  -- 2. Diatonic upper-neighbour into a chord tone (returning to same pitch).
  if diff == 0 and is_chord_tone(to_pitch, chord_pcs) then
    if rng_float() < 0.5 then
      return diatonic_neighbor(scale_notes, to_pitch, 1)
    else
      return diatonic_neighbor(scale_notes, to_pitch, -1)
    end
  end

  -- 3. Chromatic passing tone between scale notes a whole step apart.
  if math.abs(diff) == 2 then
    return from_pitch + (diff > 0 and 1 or -1)
  end

  -- 4. Diatonic passing run when notes are a third apart.
  if math.abs(diff) == 3 or math.abs(diff) == 4 then
    return diatonic_step(scale_notes, from_pitch, diff > 0 and 1 or -1)
  end

  return nil
end

-- ----------------------------------------------------------------
--  MELODY GENERATORS
--  Each returns a flat list of {pitch, pos, dur, vel, is_rest}
--  for a single chord block. pos is relative to block start.
-- ----------------------------------------------------------------

local function mel_pick_vel()
  local v = state.mel_velocity + math.floor((rng_float()*2-1) * state.mel_vel_human)
  return math.max(1, math.min(127, v))
end

local function mel_min_beats() return MEL_DURATIONS[state.mel_min_dur_idx].beats end
local function mel_max_beats() return MEL_DURATIONS[state.mel_max_dur_idx].beats end

-- Shared fill function: works entirely in integer grid steps.
-- grid = min duration in beats = 1 grid step.
-- All positions are integer multiples of grid — no floating point drift.
--
-- pitch_fn contract:
--   pitch_fn(pos_beats, block_dur, chord_notes, scale_notes, prev_pitch, ctx)
--   may return:
--     - a number             : pitch only; rhythm decided by metric grid
--     - a table { pitch=p, dur_slots=n, vel=v }
--                             : caller-supplied rhythm (e.g. motif/fractal)
--                               n is in min-grid steps; vel optional
--     - nil                  : skip this onset (treated as a rest)
--
-- Context keys set per onset (read-only for pitch_fn):
--   ctx.is_block_start_slot     true on the very first onset of the block
--   ctx.metric_weight_here      0..1 metrical weight at this onset
--   ctx.land_chord_tone_p       0..1 desired chord-tone landing probability
--   ctx.tension_here            0..1 phrase-arc tension at this onset
--   ctx.scale_pcs / chord_pcs   pitch-class sets (cached for convenience)
local function mel_fill_block(block_dur, chord_notes, scale_notes, chord_range,
                               pitch_fn, context)
  local grid      = mel_min_beats()
  local abs_start = context.abs_block_start or 0

  -- Convert everything to integer slots
  local abs_start_slot = math.floor(abs_start / grid + 0.5)
  local block_slots    = math.floor(block_dur  / grid + 0.5)
  local min_slots      = 1  -- 1 grid step = min duration by definition
  local max_slots      = math.floor(mel_max_beats() / grid + 0.5)

  -- Cache PC sets for the duration of this block
  local scale_pcs = scale_pc_set()
  local chord_pcs = chord_pc_set(chord_notes)
  context.scale_pcs = scale_pcs
  context.chord_pcs = chord_pcs

  local events       = {}
  local prev         = context.prev_pitch or scale_notes[1] or 60
  local slot         = 0          -- current slot within block (integer)
  local first_onset  = true       -- true until the first non-rest onset

  while slot < block_slots do
    local remaining_slots = block_slots - slot

    -- Build onset candidates from current slot to end of block
    local sub_slots    = remaining_slots
    local sub_abs_slot = abs_start_slot + slot
    local candidates   = build_onset_candidates(sub_slots, sub_abs_slot, grid)

    if #candidates == 0 then break end

    -- Pick the next onset: take the first candidate slot (already filtered
    -- by metre) — advance slot to that position
    local next_candidate = candidates[1]
    local onset_slot     = slot + next_candidate.slot

    -- Fill the gap before this onset as silence (rest/advance)
    slot = onset_slot
    if slot >= block_slots then break end
    remaining_slots = block_slots - slot

    -- Metric / phrase context for this onset
    local mw       = metrical_weight(abs_start_slot + slot, grid)
    local abs_beat = (abs_start_slot + slot) * grid
    local tension  = phrase_arc_tension(context, abs_beat)
    local landing_p = chord_tone_landing_prob(first_onset, mw, tension)

    context.metric_weight_here  = mw
    context.tension_here        = tension
    context.land_chord_tone_p   = landing_p
    context.is_block_start_slot = first_onset

    -- Default: metric-driven duration
    local dur_slots = pick_dur_slots(
      slot, abs_start_slot, grid,
      min_slots, max_slots, remaining_slots
    )

    -- Rest probability — derived from busyness via the phrase-arc density
    -- envelope. Sparse settings rest more (and only between phrases);
    -- dense settings rest rarely. Block-start is never a rest (we want
    -- the chord to be defined on attack), and strong beats rest less.
    -- For caller-dur presets (Fractal/Motif) the rhythm is structural,
    -- so we soften busyness's pull on the rest gate to avoid breaking
    -- the cell.
    local density = phrase_arc_density(context, abs_beat)
    local soft = (state.mel_preset_idx == 7 or state.mel_preset_idx == 8)
                 and 0.5 or 1.0
    local rest_p = (1.0 - density) * 35.0 * soft
    if first_onset    then rest_p = 0 end
    if mw >= 0.95     then rest_p = rest_p * 0.25 end

    if rng_float() * 100 < rest_p then
      slot = slot + dur_slots
    else
      local pos_beats = slot * grid
      local result    = pitch_fn(pos_beats, block_dur, chord_notes,
                                 scale_notes, prev, context)

      local pitch, caller_dur, caller_vel
      if type(result) == "table" then
        pitch      = result.pitch
        caller_dur = result.dur_slots
        caller_vel = result.vel
      else
        pitch = result
      end

      if pitch then
        -- Caller-supplied rhythm overrides metric grid (motif/fractal).
        if caller_dur and caller_dur > 0 then
          dur_slots = math.max(min_slots, math.min(max_slots,
                                                   math.min(caller_dur, remaining_slots)))
        end

        -- Cross-block voice leading: at the first onset of a non-first
        -- block, prefer the pre-staged voice-led chord tone unless the
        -- generator already returned a chord tone close to it.
        if first_onset and context.voice_led_target then
          local vt = context.voice_led_target
          if not is_chord_tone(pitch, chord_pcs) or math.abs(pitch - vt) > 4 then
            -- Honour the voice-led target on strong landings.
            if rng_float() < math.max(0.7, landing_p) then
              pitch = vt
            end
          end
        end

        -- Chord-tone landing enforcement: with probability landing_p, snap
        -- a non-chord-tone result to the nearest chord tone. This is an
        -- additional gate on top of apply_rigidity.
        if landing_p > 0 and not is_chord_tone(pitch, chord_pcs)
           and rng_float() < landing_p then
          pitch = nearest_chord_tone(pitch, chord_range)
        end

        pitch = apply_rigidity(pitch, chord_range)
        pitch = math.max(state.mel_oct_min * 12,
                math.min((state.mel_oct_max + 1) * 12 - 1, pitch))

        -- Colour tone (passing/neighbour/leading-tone). Only when there's
        -- room and we're not at the very first onset (would obscure the
        -- chord-tone landing).
        local target_is_strong = mw >= 0.55 or first_onset
        local colour = nil
        if not first_onset and dur_slots > min_slots then
          colour = maybe_insert_colour(prev, pitch, scale_notes,
                                       scale_pcs, chord_pcs, target_is_strong)
        end
        if colour then
          local cd = grid  -- exactly 1 grid step
          events[#events+1] = {
            pitch=colour, pos=pos_beats, dur=cd,
            vel=(caller_vel or mel_pick_vel()), is_rest=false
          }
          pos_beats = pos_beats + cd
          dur_slots = dur_slots - 1
          prev = colour
        end

        if dur_slots > 0 then
          events[#events+1] = {
            pitch=pitch, pos=pos_beats,
            dur=dur_slots * grid,
            vel=(caller_vel or mel_pick_vel()), is_rest=false
          }
          prev = pitch
          first_onset = false
        end
      end
      slot = slot + dur_slots
    end
  end

  context.prev_pitch = prev
  return events
end

-- ── 1. FREE ─────────────────────────────────────────────────────
-- Weighted random walk biased toward chord tones; gap fill after leaps
local function mel_free(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local pcs = {}
    for _, n in ipairs(cn) do pcs[n % 12] = true end
    -- After a large leap, bias back toward prev (gap fill)
    local last_leap = c.last_leap or 0
    local weights = {}
    local total = 0
    for i, n in ipairs(sn) do
      local dist = math.abs(n - prev)
      local w = 1.0
      -- Chord tone bonus
      if pcs[n % 12] then w = w * 3 end
      -- Stepwise preference
      if dist <= 2 then w = w * 2 end
      -- Gap fill: if last move was a big leap, prefer filling back
      if math.abs(last_leap) > 4 then
        local fill_dir = last_leap > 0 and (n < prev) or (n > prev)
        if fill_dir then w = w * 2.5 end
      end
      weights[i] = w
      total = total + w
    end
    local r = rng_float() * total
    local acc = 0
    for i, w in ipairs(weights) do
      acc = acc + w
      if r <= acc then
        c.last_leap = sn[i] - prev
        return sn[i]
      end
    end
    return sn[#sn]
  end
  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 2. FLOWING ──────────────────────────────────────────────────
-- Smooth noise-driven pitch selection — positions map to a sine curve
-- offset by the seed, giving a naturally arching contour
local function mel_flowing(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local phase = ctx_tbl.flow_phase or (rng_float() * math.pi * 2)
  local freq  = ctx_tbl.flow_freq  or (0.3 + rng_float() * 0.7)
  ctx_tbl.flow_phase = phase
  ctx_tbl.flow_freq  = freq

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local t = pos / bdur
    -- Smooth value 0..1 following a sine wave
    local smooth = (math.sin(t * math.pi * 2 * freq + phase) + 1) * 0.5
    local target_idx = 1 + math.floor(smooth * (#sn - 1))
    target_idx = math.max(1, math.min(#sn, target_idx))
    -- Allow ±1 scale step of variation via rng
    local variation = rng_int(-1, 1)
    local idx = math.max(1, math.min(#sn, target_idx + variation))
    return sn[idx]
  end
  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 3. STRUCTURED ───────────────────────────────────────────────
-- Follows a seed-chosen contour (arch, valley, ascending, descending, wave)
-- and generates a repeating rhythmic motif
local CONTOURS = {"arch","valley","ascending","descending","wave"}
local function mel_structured(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  if not ctx_tbl.contour then
    ctx_tbl.contour = CONTOURS[rng_int(1, #CONTOURS)]
  end
  if not ctx_tbl.motif_rhythm then
    -- Generate a short rhythmic motif of 2-4 durations
    local motif = {}
    local motif_len = rng_int(2, 4)
    for _ = 1, motif_len do
      local d = pick_duration(mel_min_beats(), mel_max_beats())
      -- At high metre, snap motif durations to the melody's min-note grid
      -- so onsets always land on the user-selected rhythmic resolution.
      -- Previously this forced durations to ≥1 beat, which silently
      -- overrode a finer Min selection (e.g. 1/16) at metre ≥ 60.
      if state.mel_metre >= 60 then
        local grid = mel_min_beats()
        d = math.max(grid, math.floor(d / grid + 0.5) * grid)
      end
      motif[#motif+1] = d
    end
    ctx_tbl.motif_rhythm = motif
    ctx_tbl.motif_pos    = 1
  end

  local contour = ctx_tbl.contour
  local function contour_target(t)
    if contour == "arch" then
      return math.sin(t * math.pi)
    elseif contour == "valley" then
      return 1 - math.sin(t * math.pi)
    elseif contour == "ascending" then
      return t
    elseif contour == "descending" then
      return 1 - t
    elseif contour == "wave" then
      return (math.sin(t * math.pi * 4) + 1) * 0.5
    end
    return 0.5
  end

  local events    = {}
  local pos       = 0
  local prev      = ctx_tbl.prev_pitch or scale_notes[math.ceil(#scale_notes * 0.5)] or 60
  local motif     = ctx_tbl.motif_rhythm
  local mi        = ctx_tbl.motif_pos or 1
  local scale_pcs = scale_pc_set()
  local chord_pcs = chord_pc_set(chord_notes)
  local first     = true

  while pos < block_dur - 0.001 do
    local remaining = block_dur - pos
    local dur = math.min(motif[mi], remaining)
    if dur < 0.001 then break end
    mi = (mi % #motif) + 1

    -- First onset of the block: never a rest; force a chord-tone landing
    -- (voice-led from prev_pitch when possible) so chord changes feel
    -- intentional rather than incidental. Otherwise rest probability is
    -- driven by the busyness-modulated phrase-arc density.
    local abs_beat = (ctx_tbl.abs_block_start or 0) + pos
    local density  = phrase_arc_density(ctx_tbl, abs_beat)
    local rest_p   = (first and 0) or ((1.0 - density) * 35.0)

    if rng_float() * 100 >= rest_p then
      local pitch
      if first then
        if ctx_tbl.voice_led_target then
          pitch = ctx_tbl.voice_led_target
        elseif #chord_range > 0 then
          local t      = pos / block_dur
          local cv     = contour_target(t)
          local ti     = 1 + math.floor(cv * (#scale_notes - 1))
          ti = math.max(1, math.min(#scale_notes, ti))
          pitch = nearest_chord_tone(scale_notes[ti], chord_range)
        else
          pitch = scale_notes[math.ceil(#scale_notes/2)]
        end
      else
        local t      = pos / block_dur
        local cv     = contour_target(t)
        local ti     = 1 + math.floor(cv * (#scale_notes - 1))
        ti = math.max(1, math.min(#scale_notes, ti + rng_int(-1, 1)))
        pitch = apply_rigidity(scale_notes[ti], chord_range)
      end
      pitch = math.max(state.mel_oct_min*12, math.min((state.mel_oct_max+1)*12-1, pitch))

      local colour = nil
      if not first then
        colour = maybe_insert_colour(prev, pitch, scale_notes,
                                     scale_pcs, chord_pcs, false)
      end
      if colour then
        local cd = math.min(mel_min_beats(), dur * 0.5)
        events[#events+1] = {pitch=colour, pos=pos, dur=cd, vel=mel_pick_vel()}
        pos = pos + cd; dur = dur - cd
      end
      if dur > 0.001 then
        events[#events+1] = {pitch=pitch, pos=pos, dur=dur, vel=mel_pick_vel()}
        prev = pitch
        first = false
      end
    end
    pos = pos + dur
  end

  ctx_tbl.motif_pos  = mi
  ctx_tbl.prev_pitch = prev
  return events
end

-- ── 4. CONVERSATIONAL ───────────────────────────────────────────
-- Markov-chain style: transition weights based on interval from last note.
-- Tension tracking: rises away from tonic/chord, resolves toward them.
local function mel_conversational(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local tension = ctx_tbl.tension or 0.0
  local pcs = {}
  for _, n in ipairs(chord_notes) do pcs[n % 12] = true end
  local root_pc = (state.root_idx - 1) % 12

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local weights = {}
    local total   = 0
    for i, n in ipairs(sn) do
      local interval = math.abs(n - prev)
      local w = 1.0
      -- Markov: prefer steps and small leaps
      if interval == 0 then w = 0.1          -- avoid repeating same note too much
      elseif interval <= 2 then w = 3.0      -- stepwise strongly preferred
      elseif interval <= 4 then w = 1.5      -- small leap ok
      elseif interval <= 7 then w = 0.7      -- larger leap less likely
      else w = 0.2 end                        -- big leap rare

      -- Tension resolution: high tension strongly prefers tonic/chord tones
      local is_chord = pcs[n % 12]
      local is_tonic = (n % 12) == root_pc
      if tension > 0.6 then
        if is_tonic  then w = w * 4 end
        if is_chord  then w = w * 2 end
      elseif tension > 0.3 then
        if is_chord  then w = w * 1.5 end
      end

      weights[i] = w
      total = total + w
    end

    local r = rng_float() * total
    local acc = 0
    local chosen = sn[1]
    for i, w in ipairs(weights) do
      acc = acc + w
      if r <= acc then chosen = sn[i]; break end
    end

    -- Update tension: non-chord tones raise it, chord tones lower it
    if pcs[chosen % 12] then
      c.tension = math.max(0, (c.tension or 0) - 0.2)
    else
      c.tension = math.min(1, (c.tension or 0) + 0.15)
    end

    return chosen
  end

  local evs = mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
  return evs
end

-- ── 5. MECHANICAL ───────────────────────────────────────────────
-- Strict intervallic rule: alternates between a fixed interval up and down.
-- The interval is seed-chosen (3rd, 4th, 5th). Very rhythmically regular.
local function mel_mechanical(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  if not ctx_tbl.mech_interval then
    local intervals = {2, 3, 4, 5}  -- scale steps
    ctx_tbl.mech_interval  = intervals[rng_int(1, #intervals)]
    ctx_tbl.mech_direction = 1
  end

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local idx    = nearest_idx(sn, prev)
    local step   = c.mech_interval * c.mech_direction
    local new_idx = idx + step
    -- Bounce at edges
    if new_idx > #sn then
      c.mech_direction = -1
      new_idx = math.max(1, idx - c.mech_interval)
    elseif new_idx < 1 then
      c.mech_direction = 1
      new_idx = math.min(#sn, idx + c.mech_interval)
    end
    return sn[math.max(1, math.min(#sn, new_idx))]
  end
  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 6. PHRASE & ANSWER ──────────────────────────────────────────
local function mel_phrase_answer(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local grid = mel_min_beats()
  -- Snap split to bar boundary at high metre, otherwise seed-driven fraction
  local split = block_dur * (0.4 + rng_float() * 0.25)
  if state.mel_metre >= 60 then
    local num     = state.timesig_num
    local snapped = math.floor(split / num + 0.5) * num
    snapped = math.max(num, math.min(block_dur - num, snapped))
    if snapped > 0 and snapped < block_dur then split = snapped end
  end
  -- Snap split to grid
  split = math.floor(split / grid + 0.5) * grid

  local pcs      = {}
  for _, n in ipairs(chord_notes) do pcs[n % 12] = true end
  local root_pc  = (state.root_idx - 1) % 12
  local phase    = ctx_tbl.pa_phase or 0
  ctx_tbl.pa_phase = 1 - phase
  local is_call  = (phase == 0)

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local near_end = (bdur - pos) <= grid * 2
    local weights  = {}
    local total    = 0
    for i, n in ipairs(sn) do
      local w    = 1.0
      local dist = math.abs(n - prev)
      if dist <= 2 then w = w * 2 end
      if near_end then
        if is_call then
          if (n % 12) == root_pc then w = w * 0.1 end
        else
          if (n % 12) == root_pc then w = w * 5 end
          if pcs[n % 12]         then w = w * 2 end
        end
      end
      weights[i] = w; total = total + w
    end
    local r = rng_float() * total; local acc = 0
    for i, w in ipairs(weights) do
      acc = acc + w
      if r <= acc then return sn[i] end
    end
    return sn[#sn]
  end

  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 7. FRACTAL ──────────────────────────────────────────────────
-- Proper L-system / Schenkerian-style diminution: an axiom of
-- structural tones (chord tones of the home chord) is iteratively
-- rewritten by replacing each note with a small figure (passing,
-- neighbour, anticipation, leap-fill). Each iteration halves the
-- per-note duration, so the final stream is rhythmically self-similar.
--
-- The structural skeleton is composed of chord tones, so chord-tone
-- landings on strong beats are baked in by construction rather than
-- imposed after the fact. Per chord block the sequence is diatonically
-- transposed onto a chord tone of the current chord.
local function mel_fractal(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local grid      = mel_min_beats()
  local min_slots = 1
  local max_slots = math.floor(mel_max_beats() / grid + 0.5)

  -- L-system productions on a (idx, dur_slots) note. Each rule expands
  -- a single note into N notes with rhythm subdivided. Rules deliberately
  -- bias toward stepwise motion and return-to-tone shapes.
  local function expand_note(entry, sn_len)
    local idx = entry.idx
    local d   = entry.d
    if d <= min_slots then return { entry } end       -- can't subdivide further
    local half = math.max(min_slots, math.floor(d / 2))
    local r = rng_float()
    if r < 0.30 then
      -- Upper neighbour: idx, idx+1, idx
      return {
        { idx = idx, d = half },
        { idx = math.min(sn_len, idx + 1), d = math.max(min_slots, d - 2*half) > 0 and (d - 2*half) or half },
        { idx = idx, d = half },
      }
    elseif r < 0.55 then
      -- Lower neighbour: idx, idx-1, idx
      return {
        { idx = idx, d = half },
        { idx = math.max(1, idx - 1), d = math.max(min_slots, d - 2*half) > 0 and (d - 2*half) or half },
        { idx = idx, d = half },
      }
    elseif r < 0.80 then
      -- Passing toward next structural tone: idx, idx+1 (or idx-1)
      local dir = (rng_float() < 0.5) and 1 or -1
      return {
        { idx = idx, d = half },
        { idx = math.max(1, math.min(sn_len, idx + dir)), d = d - half },
      }
    else
      -- Anticipation: idx, idx (repeat with shorter onset)
      return {
        { idx = idx, d = half },
        { idx = idx, d = d - half },
      }
    end
  end

  if not ctx_tbl.fractal_seq then
    -- Axiom: a small chain of chord tones (3–4) of the *first* chord,
    -- spanning a gentle arch. These become the structural tones.
    local skeleton = {}
    if #chord_range >= 2 then
      local lo_i = math.max(1, math.floor(#chord_range * 0.3))
      local hi_i = math.min(#chord_range, math.floor(#chord_range * 0.7) + 1)
      skeleton = { chord_range[lo_i], chord_range[hi_i], chord_range[lo_i] }
    elseif #chord_range == 1 then
      skeleton = { chord_range[1] }
    else
      skeleton = { scale_notes[math.ceil(#scale_notes/2)] }
    end
    -- Convert pitches to (scale-step idx, full-beat duration) entries.
    local one_beat_slots = math.max(min_slots, math.floor(1.0 / grid + 0.5))
    local axiom = {}
    for _, p in ipairs(skeleton) do
      axiom[#axiom+1] = { idx = nearest_idx(scale_notes, p), d = one_beat_slots }
    end

    -- Apply 1–2 iterations of L-system expansion.
    local depth = rng_int(1, 2)
    local seq   = axiom
    for _ = 1, depth do
      local next_seq = {}
      for _, e in ipairs(seq) do
        for _, n in ipairs(expand_note(e, #scale_notes)) do
          next_seq[#next_seq+1] = n
        end
      end
      seq = next_seq
    end

    ctx_tbl.fractal_seq      = seq
    ctx_tbl.fractal_seed_idx = axiom[1].idx
    ctx_tbl.fractal_ei       = 1
  end

  -- Per-block diatonic transposition onto a chord tone of this chord.
  if ctx_tbl.fractal_block_transp_for ~= ctx_tbl.abs_block_start then
    local target
    if ctx_tbl.voice_led_target then
      target = ctx_tbl.voice_led_target
    elseif #chord_range > 0 then
      target = nearest_chord_tone(scale_notes[ctx_tbl.fractal_seed_idx], chord_range)
    else
      target = scale_notes[ctx_tbl.fractal_seed_idx]
    end
    ctx_tbl.fractal_block_transp = nearest_idx(scale_notes, target)
                                 - ctx_tbl.fractal_seed_idx
    ctx_tbl.fractal_block_transp_for = ctx_tbl.abs_block_start
  end

  local seq = ctx_tbl.fractal_seq
  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local ei = c.fractal_ei or 1
    local entry = seq[ei]
    local idx = math.max(1, math.min(#sn, entry.idx + c.fractal_block_transp))
    c.fractal_ei = (ei % #seq) + 1
    return { pitch = sn[idx], dur_slots = entry.d }
  end

  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 8. MOTIF ────────────────────────────────────────────────────
-- A short cell (3–5 notes) with its own rhythm and a deliberately
-- singable interval profile (mostly steps, at most one third). On
-- every chord change the cell is *diatonically transposed* so that
-- its first (or strongest) note lands on a chord tone of the new
-- chord — this is the technique behind every melodic sequence in
-- common-practice writing.
--
-- The cell stores (scale_idx, dur_slots) so its rhythm survives
-- `mel_fill_block`'s metric grid. Periodic variation: occasional
-- inversion or retrograde of the cell, keeping the rhythm intact.
local function mel_motif(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local grid       = mel_min_beats()
  local min_slots  = 1
  local max_slots  = math.floor(mel_max_beats() / grid + 0.5)

  -- Build the seed cell once per progression.
  if not ctx_tbl.motif_cell then
    local cell_len = rng_int(3, 5)
    local cell     = {}
    -- Start the cell on a chord tone of the *first* chord, mid-range.
    local start_p  = chord_range[math.max(1, math.floor(#chord_range/2))]
                  or scale_notes[math.ceil(#scale_notes/2)]
    local idx      = nearest_idx(scale_notes, start_p)
    -- Interval shape: mostly ±1 steps, occasional ±2 (a third), with
    -- a small chance of a return to the previous note.
    local interval_pool = { -2, -1, -1, -1, 0, 1, 1, 1, 2 }
    -- Reasonable rhythmic palette in min-grid steps. Skews to ≤ a beat
    -- so the motif feels phrasal rather than ponderous.
    local rhythm_pool = {}
    do
      local one_beat_slots = math.floor(1.0 / grid + 0.5)
      local cands = { 1, 1, 2, 2, one_beat_slots, math.max(1, math.floor(one_beat_slots/2)) }
      for _, v in ipairs(cands) do
        if v >= min_slots and v <= max_slots then rhythm_pool[#rhythm_pool+1] = v end
      end
      if #rhythm_pool == 0 then rhythm_pool = { min_slots } end
    end
    for i = 1, cell_len do
      local d = rhythm_pool[rng_int(1, #rhythm_pool)]
      cell[#cell+1] = { idx_offset = idx - nearest_idx(scale_notes, start_p),
                        dur_slots  = d }
      local step = interval_pool[rng_int(1, #interval_pool)]
      idx = math.max(1, math.min(#scale_notes, idx + step))
    end
    ctx_tbl.motif_cell      = cell
    ctx_tbl.motif_seed_idx  = nearest_idx(scale_notes, start_p)
    ctx_tbl.motif_ci        = 1
    ctx_tbl.motif_block_n   = 0      -- counts blocks consumed (for variation)
    ctx_tbl.motif_invert    = false
    ctx_tbl.motif_retro     = false
  end

  -- Per-chord-block: compute a diatonic transposition that lands the
  -- cell's first note on a chord tone of *this* chord, voice-led from
  -- prev_pitch when possible. Fires exactly once per chord block.
  if ctx_tbl.motif_block_transp_for ~= ctx_tbl.abs_block_start then
    -- Restart the cell at its first note for each new chord block so the
    -- diatonic transposition aligns with the cell's strongest moment.
    ctx_tbl.motif_ci = 1
    local prev = ctx_tbl.prev_pitch
    local target
    if prev and ctx_tbl.voice_led_target then
      target = ctx_tbl.voice_led_target
    elseif #chord_range > 0 then
      -- Pick the chord tone closest to the cell's seed pitch.
      local seed_pitch = scale_notes[ctx_tbl.motif_seed_idx]
                      or scale_notes[math.ceil(#scale_notes/2)]
      target = nearest_chord_tone(seed_pitch, chord_range)
    else
      target = scale_notes[ctx_tbl.motif_seed_idx]
    end
    local target_idx = nearest_idx(scale_notes, target)
    ctx_tbl.motif_block_transp = target_idx - ctx_tbl.motif_seed_idx
    ctx_tbl.motif_block_transp_for = ctx_tbl.abs_block_start
    ctx_tbl.motif_block_n  = (ctx_tbl.motif_block_n or 0) + 1
    -- Light variation every 4 blocks: invert intervals or retrograde.
    if ctx_tbl.motif_block_n % 4 == 0 then
      if rng_float() < 0.5 then
        ctx_tbl.motif_invert = not ctx_tbl.motif_invert
      else
        ctx_tbl.motif_retro = not ctx_tbl.motif_retro
      end
    end
  end

  local cell   = ctx_tbl.motif_cell
  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local ci   = c.motif_ci or 1
    local len  = #cell
    local read_i = c.motif_retro and (len - ci + 1) or ci
    local entry = cell[read_i]
    local off   = entry.idx_offset
    if c.motif_invert then off = -off end
    local idx   = math.max(1, math.min(#sn,
                          c.motif_seed_idx + c.motif_block_transp + off))
    local pitch = sn[idx]
    c.motif_ci  = (ci % len) + 1
    return { pitch = pitch, dur_slots = entry.dur_slots }
  end

  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- Dispatcher
local MEL_GEN_FNS = {
  mel_free, mel_flowing, mel_structured, mel_conversational,
  mel_mechanical, mel_phrase_answer, mel_fractal, mel_motif,
}

-- Build one cycle of the progression, appending to `events` and mutating
-- `context`. `cycle_offset` is the absolute beat where this cycle starts;
-- subsequent cycles re-use the same context (preserving prev_pitch, motif
-- cell etc.) so the RNG stream and musical state continue smoothly.
-- Returns the absolute beat where this cycle ended.
local function build_melody_cycle(progression, context, events, cycle_offset)
  local gen_fn = MEL_GEN_FNS[state.mel_preset_idx] or mel_free
  local abs_pos = cycle_offset

  -- Phrase-arc tension repeats per cycle: each progression pass arcs from
  -- repose → peak → repose, so cycle 2 isn't stuck at "end of arc" tension.
  local total_beats = 0
  for _, ch in ipairs(progression) do total_beats = total_beats + ch.duration end
  phrase_arc_init(context, total_beats, cycle_offset)

  for ci, ch in ipairs(progression) do
    local scale_notes  = scale_notes_in_range()
    local chord_range  = chord_notes_in_range(ch.notes)
    if #scale_notes == 0 then
      abs_pos = abs_pos + ch.duration
    else
      context.abs_block_start = abs_pos
      context.chord_meta      = ch
      -- "First block" gates voice-leading: only true on the very first
      -- block of the very first cycle, when there's no prior pitch to
      -- lead from. Cycle 2's first chord must voice-lead from cycle 1's
      -- last pitch.
      context.is_first_block  = (cycle_offset == 0 and ci == 1)

      if context.prev_pitch and not context.is_first_block then
        context.voice_led_target = voice_lead_to_chord(context.prev_pitch, chord_range)
      else
        context.voice_led_target = nil
      end

      local block_evs = gen_fn(ch.duration, ch.notes, scale_notes, chord_range, context)
      for _, ev in ipairs(block_evs) do
        events[#events+1] = {
          pitch = ev.pitch,
          pos   = abs_pos + ev.pos,
          dur   = ev.dur,
          vel   = ev.vel or mel_pick_vel(),
        }
      end
      abs_pos = abs_pos + ch.duration
    end
  end

  return abs_pos
end

-- Single-cycle melody for offline render (write_all). Live preview uses
-- build_melody_cycle directly so it can extend indefinitely.
local function build_melody_events(progression)
  local context = {}
  local events  = {}
  local abs_end = build_melody_cycle(progression, context, events, 0)
  return events, abs_end
end

-- ----------------------------------------------------------------
--  ARP SCALE HELPERS  (unchanged from phase 2)
-- ----------------------------------------------------------------
local function scale_pitch_classes()
  local mode    = MODE_NAMES[state.mode_idx]
  local ivs     = SCALE_INTERVALS[mode]
  local root_pc = (state.root_idx - 1) % 12
  local pcs     = {}
  for _, iv in ipairs(ivs) do pcs[(root_pc + iv) % 12] = true end
  return pcs
end

local function build_arp_pool(chord_notes, octaves, rigidity_pct)
  if #chord_notes == 0 then return {} end
  local scale_pcs = scale_pitch_classes()
  local chord_set = {}
  for _, n in ipairs(chord_notes) do chord_set[n % 12] = true end
  local bass_note  = chord_notes[1]
  local anchor_oct = math.floor(bass_note / 12) - 1
  local scale_prob = rigidity_pct / 100.0
  local pool_set   = {}
  for oct = 0, octaves - 1 do
    for pc = 0, 11 do
      local pitch = (anchor_oct + oct + 1) * 12 + pc
      if pitch >= bass_note and pitch >= 0 then
        if chord_set[pc] then
          pool_set[pitch] = true
        elseif scale_pcs[pc] and scale_prob > 0 then
          if rng_float() < scale_prob then pool_set[pitch] = true end
        end
      end
    end
  end
  local pool = {}
  for pitch, _ in pairs(pool_set) do pool[#pool+1] = pitch end
  table.sort(pool)
  return pool
end

local function apply_arp_pattern(pool, pattern_name, rng_seq)
  if pattern_name == "Up" then return pool
  elseif pattern_name == "Down" then
    local r = {}
    for i = #pool, 1, -1 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Up-Down" then
    local r = {}
    for _, n in ipairs(pool) do r[#r+1] = n end
    for i = #pool-1, 2, -1 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Down-Up" then
    local r = {}
    for i = #pool, 1, -1 do r[#r+1] = pool[i] end
    for i = 2, #pool-1 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Random" then
    local r = {}
    for _, n in ipairs(pool) do r[#r+1] = n end
    for i = #r, 2, -1 do
      local j = math.max(1, math.floor(rng_seq[i] * i) + 1)
      r[i], r[j] = r[j], r[i]
    end
    return r
  elseif pattern_name == "Weave" then
    -- two forward, one back: 1,3,2,4,3,5,4,6...
    local r = {}
    for i = 1, #pool - 2 do
      r[#r+1] = pool[i]
      r[#r+1] = pool[i + 2]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Pedal" then
    -- root pedal between each upper note: 1,2,1,3,1,4,1,5...
    local r = {}
    for i = 2, #pool do
      r[#r+1] = pool[1]
      r[#r+1] = pool[i]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Skip" then
    -- odd indices then even: 1,3,5..., 2,4,6... (diatonic thirds)
    local r = {}
    for i = 1, #pool, 2 do r[#r+1] = pool[i] end
    for i = 2, #pool, 2 do r[#r+1] = pool[i] end
    return r
  end
  return pool
end

local BEAT_TOL = 0.001
local function resolve_step_prob(abs_beat_pos)
  local num        = state.timesig_num
  local bar_phase  = abs_beat_pos % num
  if bar_phase < BEAT_TOL or (num - bar_phase) < BEAT_TOL then
    return state.arp_beat1_prob / 100.0
  end
  local grid_beats = ACCENT_GRID[state.arp_beatn_idx].beats
  local grid_phase = abs_beat_pos % grid_beats
  if grid_phase < BEAT_TOL or (grid_beats - grid_phase) < BEAT_TOL then
    return state.arp_beatn_prob / 100.0
  end
  return state.arp_note_prob / 100.0
end

local function build_arp_events(chord_notes, chord_dur_beats, chord_abs_beat)
  local rate_beats = ARP_RATES[state.arp_rate_idx].beats
  local pattern    = ARP_PATTERNS[state.arp_pattern_idx]
  local gate_frac  = state.arp_gate / 100.0
  local base_vel   = state.arp_velocity
  local human      = state.arp_vel_human
  local pool = build_arp_pool(chord_notes, state.arp_octaves, state.arp_rigidity)
  if #pool == 0 then return {} end
  local n_steps = math.ceil(chord_dur_beats / rate_beats)
  local rng_seq = {}
  for i = 1, #pool + n_steps * 2 do rng_seq[i] = rng_float() end
  local seq = apply_arp_pattern(pool, pattern, rng_seq)
  if #seq == 0 then return {} end
  local events = {}
  if pattern == "Chord" then
    local chord_voiced = {}
    for oct = 0, state.arp_octaves - 1 do
      for _, p in ipairs(chord_notes) do chord_voiced[#chord_voiced+1] = p + oct * 12 end
    end
    local pos      = 0
    local step_idx = #chord_voiced + 1
    while #rng_seq < step_idx + n_steps * 2 do rng_seq[#rng_seq+1] = rng_float() end
    while pos < chord_dur_beats - 0.001 do
      local actual_dur = math.min(rate_beats * gate_frac, chord_dur_beats - pos)
      local prob = resolve_step_prob(chord_abs_beat + pos)
      if rng_seq[step_idx] <= prob then
        local vel_offset = math.floor((rng_seq[step_idx+1] * 2 - 1) * human)
        local vel = math.max(1, math.min(127, base_vel + vel_offset))
        for _, p in ipairs(chord_voiced) do
          events[#events+1] = {pitch=p, pos=pos, dur=actual_dur, vel=vel}
        end
      end
      pos = pos + rate_beats; step_idx = step_idx + 2
    end
  else
    local pos = 0; local seq_pos = 1
    local rng_offset = #pool + 1; local step_num = 0
    while pos < chord_dur_beats - 0.001 do
      local actual_dur   = math.min(rate_beats * gate_frac, chord_dur_beats - pos)
      local rng_idx_prob = rng_offset + step_num * 2
      local rng_idx_vel  = rng_idx_prob + 1
      while #rng_seq < rng_idx_vel do rng_seq[#rng_seq+1] = rng_float() end
      local prob = resolve_step_prob(chord_abs_beat + pos)
      if rng_seq[rng_idx_prob] <= prob then
        local vel_offset = math.floor((rng_seq[rng_idx_vel] * 2 - 1) * human)
        local vel = math.max(1, math.min(127, base_vel + vel_offset))
        events[#events+1] = {pitch=seq[seq_pos], pos=pos, dur=actual_dur, vel=vel}
      end
      pos = pos + rate_beats
      seq_pos = (seq_pos % #seq) + 1
      step_num = step_num + 1
    end
  end
  return events
end

-- ----------------------------------------------------------------
--  BASS GENERATOR
-- ----------------------------------------------------------------

-- Resolve which MIDI pitch-class to anchor the bass line on for a given chord.
-- When bass_follow_inv is true the actual bass note after inversion is used
-- (slash-chord semantics); otherwise the harmonic root is always used.
local function bass_landing_pitch(chord)
  local pc = state.bass_follow_inv and (chord.bass_midi % 12) or (chord.root_midi % 12)
  return (state.bass_oct + 1) * 12 + pc
end

local function bass_pick_vel()
  local v = state.bass_velocity + math.floor((rng_float()*2-1) * state.bass_vel_human)
  return math.max(1, math.min(127, v))
end

-- Build a list of {pitch, pos, dur, vel} events for one chord slot.
-- next_chord is the following slot (used by Walking for approach notes); nil = last chord.
local function build_bass_events(chord, chord_dur, next_chord)
  local events = {}
  local gate   = state.bass_gate / 100.0
  local style  = BASS_STYLES[state.bass_style_idx]
  local land   = bass_landing_pitch(chord)

  -- ── Root ────────────────────────────────────────────────────
  if style == "Root" then
    events[#events+1] = {pitch=land, pos=0, dur=chord_dur * gate, vel=bass_pick_vel()}

  -- ── Root-Fifth ──────────────────────────────────────────────
  elseif style == "Root-Fifth" then
    if chord_dur < 2.0 then
      events[#events+1] = {pitch=land, pos=0, dur=chord_dur * gate, vel=bass_pick_vel()}
    else
      local half     = chord_dur / 2
      local fifth_pc = (land % 12 + 7) % 12
      local fifth    = (state.bass_oct + 1) * 12 + fifth_pc
      if fifth < land then fifth = fifth + 12 end   -- keep fifth above root
      events[#events+1] = {pitch=land,  pos=0,    dur=half * gate, vel=bass_pick_vel()}
      events[#events+1] = {pitch=fifth, pos=half,  dur=half * gate, vel=bass_pick_vel()}
    end

  -- ── Walking ─────────────────────────────────────────────────
  elseif style == "Walking" then
    local mode      = MODE_NAMES[state.mode_idx]
    local ivs       = SCALE_INTERVALS[mode]
    local root_pc   = (state.root_idx - 1) % 12
    -- Two octaves of scale tones centred on bass_oct for walking room.
    local scale_bass = {}
    for oct = state.bass_oct, state.bass_oct + 1 do
      for _, iv in ipairs(ivs) do
        scale_bass[#scale_bass+1] = (oct + 1) * 12 + (root_pc + iv) % 12
      end
    end
    table.sort(scale_bass)
    local n_beats   = math.max(1, math.floor(chord_dur + 0.5))
    local next_land = next_chord and bass_landing_pitch(next_chord) or land
    local prev_pitch = land
    for b = 0, n_beats - 1 do
      local pos  = b * 1.0
      local dur  = math.min(gate, chord_dur - pos)
      local pitch
      if b == 0 then
        -- Always land on the chord anchor.
        pitch = land
      elseif b == n_beats - 1 and next_chord then
        -- Last beat: directed approach toward next chord's root.
        if rng_float() < state.bass_approach_prob / 100.0 then
          local diff = next_land - prev_pitch
          if diff > 0 then
            pitch = next_land - 1   -- semitone below (approach from below)
          elseif diff < 0 then
            pitch = next_land + 1   -- semitone above (approach from above)
          else
            pitch = land
          end
          pitch = math.max(state.bass_oct * 12,
                           math.min((state.bass_oct + 2) * 12 - 1, pitch))
        else
          pitch = voice_lead_to_chord(prev_pitch, scale_bass, 5)
        end
      else
        -- Middle beats: diatonic step in the direction of next_land.
        local dir   = (next_land >= prev_pitch) and 1 or -1
        local best, best_d = nil, math.huge
        for _, sp in ipairs(scale_bass) do
          local d = sp - prev_pitch
          if dir > 0 and d > 0 and d < best_d then
            best, best_d = sp, d
          elseif dir < 0 and d < 0 and math.abs(d) < best_d then
            best, best_d = sp, math.abs(d)
          end
        end
        pitch = best or voice_lead_to_chord(prev_pitch, scale_bass, 5)
      end
      events[#events+1] = {pitch=pitch, pos=pos, dur=dur, vel=bass_pick_vel()}
      prev_pitch = pitch
    end

  -- ── Boogie ──────────────────────────────────────────────────
  elseif style == "Boogie" then
    local half_beat = 0.5
    local n_steps   = math.floor(chord_dur / half_beat + 0.5)
    local fifth_pc  = (land % 12 + 7) % 12
    local fifth     = (state.bass_oct + 1) * 12 + fifth_pc
    if fifth < land then fifth = fifth + 12 end
    -- Upper note: major 6th (+9) for major/dominant, minor 7th (+10) for minor chords.
    local ivs_chord = CHORD_INTERVALS[chord.quality] or CHORD_INTERVALS["maj"]
    local is_minor  = false
    for _, iv in ipairs(ivs_chord) do if iv == 3 then is_minor = true; break end end
    local upper_pc  = (land % 12 + (is_minor and 10 or 9)) % 12
    local upper     = (state.bass_oct + 1) * 12 + upper_pc
    if upper < land then upper = upper + 12 end
    local pattern = {land, fifth, upper, fifth}
    for s = 0, n_steps - 1 do
      local pos = s * half_beat
      local dur = math.min(half_beat * gate, chord_dur - pos)
      events[#events+1] = {pitch=pattern[(s % 4)+1], pos=pos, dur=dur, vel=bass_pick_vel()}
    end
  -- ── Pattern ─────────────────────────────────────────────────
  elseif style == "Pattern" then
    local grid    = ARP_RATES[state.bass_pattern_grid_idx].beats
    local steps   = state.bass_pattern_steps
    local fifth_pc = (land % 12 + 7) % 12
    local fifth    = (state.bass_oct + 1) * 12 + fifth_pc
    if fifth < land then fifth = fifth + 12 end
    local oct_up   = land + 12
    local pitches  = {land, fifth, oct_up}   -- indexed by note value 1/2/3
    local step_idx = 0
    local pos      = 0
    while pos < chord_dur - 0.001 do
      local nv  = state.bass_pattern_notes[(step_idx % steps) + 1]
      local dur = math.min(grid * gate, chord_dur - pos)
      if nv > 0 then
        events[#events+1] = {pitch=pitches[nv], pos=pos, dur=dur, vel=bass_pick_vel()}
      end
      pos      = pos + grid
      step_idx = step_idx + 1
    end
  end

  return events
end

-- ----------------------------------------------------------------
--  LIVE CHORD PREVIEW
-- ----------------------------------------------------------------
local function live_notes_off()
  local ch = state.chord_channel
  for _, n in ipairs(state.last_notes_on) do
    reaper.StuffMIDIMessage(0, 0x80 | ch, n, 0)
  end
  state.last_notes_on = {}
end

local function live_notes_on(notes)
  local ch = state.chord_channel
  for _, n in ipairs(notes) do
    reaper.StuffMIDIMessage(0, 0x90 | ch, n, 90)
    state.last_notes_on[#state.last_notes_on+1] = n
  end
end

local function live_preview_tick(progression)
  local play_state = reaper.GetPlayState()
  if play_state == 0 or play_state == 2 then
    if #state.last_notes_on > 0 then live_notes_off() end
    state.last_chord_idx = -1; state.chord_wait_boundary = false; return
  end
  local total_beats = 0
  for _, ch in ipairs(progression) do total_beats = total_beats + ch.duration end
  if total_beats == 0 then return end
  local pos_beats = reaper.GetPlayPosition() * reaper.Master_GetTempo() / 60.0
  local loop_pos  = pos_beats % total_beats
  local chord_idx, acc = 1, 0
  for i, ch in ipairs(progression) do
    acc = acc + ch.duration
    if loop_pos < acc then chord_idx = i; break end
  end
  if reaper.ImGui_IsAnyItemActive(ctx) then
    if #state.last_notes_on > 0 then live_notes_off() end
    state.chord_wait_boundary = true; state.last_chord_idx = chord_idx; return
  end
  if state.chord_wait_boundary then
    if chord_idx == state.last_chord_idx then return end
    state.chord_wait_boundary = false
  end
  if chord_idx == state.last_chord_idx then return end
  live_notes_off()
  live_notes_on(progression[chord_idx].notes)
  state.last_chord_idx = chord_idx
end

-- ----------------------------------------------------------------
--  LIVE ARP PREVIEW
-- ----------------------------------------------------------------
local function arp_live_note_off()
  local ch = state.arp_channel
  for _, n in ipairs(state.arp_live_notes_on) do
    reaper.StuffMIDIMessage(0, 0x80 | ch, n, 0)
  end
  state.arp_live_notes_on = {}
  state.arp_live_note_end = -1
end

local function arp_live_rebuild(progression)
  rng_seed(state.seed)
  local events = {}
  local pos_beats = 0
  local cursor_abs = reaper.GetCursorPosition() * reaper.Master_GetTempo() / 60.0
  for _, ch in ipairs(progression) do
    local arp_evs = build_arp_events(ch.notes, ch.duration, cursor_abs + pos_beats)
    for _, ev in ipairs(arp_evs) do
      events[#events+1] = {pitch=ev.pitch, pos=pos_beats+ev.pos, dur=ev.dur, vel=ev.vel}
    end
    pos_beats = pos_beats + ch.duration
  end
  state.arp_live_events      = events
  state.arp_live_total_beats = pos_beats
  state.arp_live_last_idx    = -1
  arp_live_note_off()
end

local function arp_live_tick(progression)
  local play_state = reaper.GetPlayState()
  if play_state == 0 or play_state == 2 then
    arp_live_note_off(); state.arp_live_last_idx=-1; state.arp_wait_boundary=false; return
  end
  if not state.arp_live_events then
    arp_live_rebuild(progression)
    state.arp_live_last_idx = -1; state.arp_wait_boundary = true
  end
  local events      = state.arp_live_events
  local total_beats = state.arp_live_total_beats
  if not events or #events == 0 or total_beats == 0 then return end
  local pos_beats  = reaper.GetPlayPosition() * reaper.Master_GetTempo() / 60.0
  local loop_beats = pos_beats % total_beats
  local cur_idx = -1
  for i, ev in ipairs(events) do
    if ev.pos <= loop_beats then cur_idx = i else break end
  end
  if reaper.ImGui_IsAnyItemActive(ctx) then
    arp_live_note_off(); state.arp_wait_boundary=true; state.arp_live_last_idx=cur_idx; return
  end
  if state.arp_wait_boundary then
    if cur_idx == state.arp_live_last_idx then return end
    state.arp_wait_boundary = false
    state.arp_live_last_idx = cur_idx - 1
  end
  if cur_idx < 1 then
    arp_live_note_off(); state.arp_live_last_idx=-1; return
  end
  if cur_idx ~= state.arp_live_last_idx then
    arp_live_note_off()
    local cur_pos = events[cur_idx].pos
    local cur_end = cur_pos + events[cur_idx].dur
    local ch      = state.arp_channel
    if loop_beats < cur_end then
      local first = cur_idx
      while first > 1 and events[first-1].pos == cur_pos do first = first - 1 end
      local i = first
      while i <= #events and events[i].pos == cur_pos do
        reaper.StuffMIDIMessage(0, 0x90 | ch, events[i].pitch, events[i].vel)
        state.arp_live_notes_on[#state.arp_live_notes_on+1] = events[i].pitch
        i = i + 1
      end
      state.arp_live_note_end = cur_end
    end
    state.arp_live_last_idx = cur_idx
  else
    if #state.arp_live_notes_on > 0 and loop_beats >= state.arp_live_note_end then
      arp_live_note_off()
    end
  end
end

-- ----------------------------------------------------------------
--  LIVE MELODY PREVIEW
-- ----------------------------------------------------------------
local function mel_live_note_off()
  if state.mel_live_note >= 0 then
    reaper.StuffMIDIMessage(0, 0x80 | state.mel_channel, state.mel_live_note, 0)
    state.mel_live_note     = -1
    state.mel_live_note_end = -1
  end
end

local function mel_live_rebuild(progression)
  rng_seed(state.seed)
  -- Consume arp RNG stream first (same order as write_all) so melody is
  -- consistent with the rendered version's first cycle.
  local cursor_abs = reaper.GetCursorPosition() * reaper.Master_GetTempo() / 60.0
  local pos = 0
  for _, ch in ipairs(progression) do
    build_arp_events(ch.notes, ch.duration, cursor_abs + pos)
    pos = pos + ch.duration
  end
  -- Live preview generates lazily one progression cycle at a time, keeping
  -- RNG state and generator context across cycles so the melody continues
  -- forward instead of repeating. Edits clear this state and restart from
  -- the same seed; the randomise button picks a new seed first.
  local cycle_beats = 0
  for _, ch in ipairs(progression) do cycle_beats = cycle_beats + ch.duration end
  state.mel_live_events       = {}
  state.mel_live_context      = {}
  state.mel_live_cycle_beats  = cycle_beats
  state.mel_live_total_beats  = 0
  state.mel_live_last_idx     = -1
  if cycle_beats > 0 then
    state.mel_live_total_beats = build_melody_cycle(
      progression, state.mel_live_context, state.mel_live_events, 0)
  end
  mel_live_note_off()
end

-- Extend the live event list with additional cycles until it reaches at
-- least `target_beats` of generated content. RNG state and context persist
-- across cycles, so each extension is a deterministic continuation.
local function mel_live_extend_to(progression, target_beats)
  local cycle_beats = state.mel_live_cycle_beats or 0
  if cycle_beats <= 0 then return end
  while state.mel_live_total_beats < target_beats do
    state.mel_live_total_beats = build_melody_cycle(
      progression,
      state.mel_live_context,
      state.mel_live_events,
      state.mel_live_total_beats)
  end
end

local function mel_live_tick(progression)
  local play_state = reaper.GetPlayState()
  if play_state == 0 or play_state == 2 then
    mel_live_note_off(); state.mel_live_last_idx=-1; state.mel_wait_boundary=false; return
  end
  if not state.mel_live_events then
    mel_live_rebuild(progression)
    state.mel_live_last_idx = -1; state.mel_wait_boundary = true
  end
  local events      = state.mel_live_events
  local cycle_beats = state.mel_live_cycle_beats or 0
  if not events or cycle_beats == 0 then return end
  local pos_beats = reaper.GetPlayPosition() * reaper.Master_GetTempo() / 60.0
  -- Keep at least one full cycle of events ahead of the playhead so the
  -- lookup loop below always lands on a valid event when one exists.
  mel_live_extend_to(progression, pos_beats + cycle_beats)
  if #events == 0 then return end
  local cur_idx = -1
  for i, ev in ipairs(events) do
    if ev.pos <= pos_beats then cur_idx = i else break end
  end
  if reaper.ImGui_IsAnyItemActive(ctx) then
    mel_live_note_off(); state.mel_wait_boundary=true; state.mel_live_last_idx=cur_idx; return
  end
  if state.mel_wait_boundary then
    if cur_idx == state.mel_live_last_idx then return end
    state.mel_wait_boundary = false
    state.mel_live_last_idx = cur_idx - 1
  end
  if cur_idx < 1 then
    mel_live_note_off(); state.mel_live_last_idx=-1; return
  end
  if cur_idx ~= state.mel_live_last_idx then
    mel_live_note_off()
    local ev = events[cur_idx]
    if pos_beats < ev.pos + ev.dur then
      reaper.StuffMIDIMessage(0, 0x90 | state.mel_channel, ev.pitch, ev.vel)
      state.mel_live_note     = ev.pitch
      state.mel_live_note_end = ev.pos + ev.dur
    end
    state.mel_live_last_idx = cur_idx
  else
    if state.mel_live_note >= 0 and pos_beats >= state.mel_live_note_end then
      mel_live_note_off()
    end
  end
end

-- ----------------------------------------------------------------
--  LIVE BASS PREVIEW
-- ----------------------------------------------------------------
local function bass_live_note_off()
  if state.bass_live_note >= 0 then
    reaper.StuffMIDIMessage(0, 0x80 | state.bass_channel, state.bass_live_note, 0)
    state.bass_live_note     = -1
    state.bass_live_note_end = -1
  end
end

local function bass_live_rebuild(progression)
  bass_rng_reseed()
  local events = {}
  local pos    = 0
  for i, ch in ipairs(progression) do
    local next_ch  = progression[(i % #progression) + 1]
    local bass_evs = build_bass_events(ch, ch.duration, next_ch)
    for _, ev in ipairs(bass_evs) do
      events[#events+1] = {pitch=ev.pitch, pos=pos+ev.pos, dur=ev.dur, vel=ev.vel}
    end
    pos = pos + ch.duration
  end
  state.bass_live_events      = events
  state.bass_live_total_beats = pos
  state.bass_live_last_idx    = -1
  bass_live_note_off()
end

local function bass_live_tick(progression)
  local play_state = reaper.GetPlayState()
  if play_state == 0 or play_state == 2 then
    bass_live_note_off(); state.bass_live_last_idx=-1; state.bass_wait_boundary=false; return
  end
  if not state.bass_live_events then
    bass_live_rebuild(progression)
    state.bass_live_last_idx = -1; state.bass_wait_boundary = true
  end
  local events      = state.bass_live_events
  local total_beats = state.bass_live_total_beats
  if not events or #events == 0 or total_beats == 0 then return end
  local pos_beats  = reaper.GetPlayPosition() * reaper.Master_GetTempo() / 60.0
  local loop_beats = pos_beats % total_beats
  local cur_idx = -1
  for i, ev in ipairs(events) do
    if ev.pos <= loop_beats then cur_idx = i else break end
  end
  if reaper.ImGui_IsAnyItemActive(ctx) then
    bass_live_note_off(); state.bass_wait_boundary=true; state.bass_live_last_idx=cur_idx; return
  end
  if state.bass_wait_boundary then
    if cur_idx == state.bass_live_last_idx then return end
    state.bass_wait_boundary = false
    state.bass_live_last_idx = cur_idx - 1
  end
  if cur_idx < 1 then
    bass_live_note_off(); state.bass_live_last_idx=-1; return
  end
  if cur_idx ~= state.bass_live_last_idx then
    bass_live_note_off()
    local ev = events[cur_idx]
    if loop_beats < ev.pos + ev.dur then
      reaper.StuffMIDIMessage(0, 0x90 | state.bass_channel, ev.pitch, ev.vel)
      state.bass_live_note     = ev.pitch
      state.bass_live_note_end = ev.pos + ev.dur
    end
    state.bass_live_last_idx = cur_idx
  else
    if state.bass_live_note >= 0 and loop_beats >= state.bass_live_note_end then
      bass_live_note_off()
    end
  end
end

-- ----------------------------------------------------------------
--  RESET LIVE  (all layers)
-- ----------------------------------------------------------------
local function reset_live()
  live_notes_off()
  state.last_chord_idx      = -1
  state.chord_wait_boundary = true
  state.arp_live_events     = nil
  state.arp_wait_boundary   = true
  arp_live_note_off()
  state.mel_live_events     = nil
  state.mel_wait_boundary   = true
  mel_live_note_off()
  state.bass_live_events    = nil
  state.bass_wait_boundary  = true
  bass_live_note_off()
end

-- ----------------------------------------------------------------
--  MIDI ITEM WRITER
-- ----------------------------------------------------------------
local function get_or_create_track(name)
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local _, tn = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if tn == name then return tr end
  end
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  local tr = reaper.GetTrack(0, reaper.CountTracks(0)-1)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local function write_midi_item(track, item_start, item_len, note_events, ppq)
  local item = reaper.CreateNewMIDIItemInProj(track, item_start, item_start+item_len, false)
  if not item then return nil, "could not create MIDI item" end
  local take = reaper.GetActiveTake(item)
  if not take then return nil, "could not get active take" end
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
  for _, ev in ipairs(note_events) do
    reaper.MIDI_InsertNote(take, false, false,
      ev.pos * ppq, (ev.pos + ev.dur) * ppq - 2,
      ev.channel or 0, ev.pitch, ev.vel or 90, false)
  end
  reaper.MIDI_Sort(take)
  reaper.UpdateItemInProject(item)
  return item, nil
end

-- ----------------------------------------------------------------
--  WRITE ALL LAYERS
-- ----------------------------------------------------------------
local function write_all()
  reaper.Undo_BeginBlock()
  rng_seed(state.seed)

  local progression = build_progression()
  if #progression == 0 then
    state.status_msg = "Error: empty progression."
    reaper.Undo_EndBlock("Chord Generator: write (empty)", -1)
    return
  end

  local cycle_beats = 0
  for _, ch in ipairs(progression) do cycle_beats = cycle_beats + ch.duration end
  local cycles      = math.max(1, math.floor(state.mel_render_cycles or 1))
  local total_beats = cycle_beats * cycles

  local ppq        = state.ppq_per_beat
  local tempo      = reaper.Master_GetTempo()
  local item_start = reaper.GetCursorPosition()
  local item_len   = total_beats * 60.0 / tempo
  local cursor_abs = item_start * tempo / 60.0
  local written    = {}

  -- Chord layer: chord progression repeats verbatim each cycle.
  if state.chord_enabled then
    local track  = get_or_create_track(state.chord_track_name)
    local events = {}
    for cyc = 0, cycles - 1 do
      local cyc_off = cyc * cycle_beats
      local pos = 0
      for _, ch in ipairs(progression) do
        for _, note in ipairs(ch.notes) do
          events[#events+1] = {
            pitch=note, pos=cyc_off+pos, dur=ch.duration-(1/ppq),
            vel=state.chord_velocity, channel=state.chord_channel,
          }
        end
        pos = pos + ch.duration
      end
    end
    local _, err = write_midi_item(track, item_start, item_len, events, ppq)
    if err then
      state.status_msg="Chord write error: "..err
      reaper.Undo_EndBlock("Chord Generator: write (failed)", -1); return
    end
    written[#written+1] = state.chord_track_name
  end

  -- Arp layer: consume exactly one cycle of arp RNG (so the melody RNG
  -- stream stays aligned with the live preview), then repeat the resulting
  -- pattern verbatim for each subsequent cycle.
  if state.arp_enabled then
    local track  = get_or_create_track(state.arp_track_name)
    local cycle_evs = {}
    local pos = 0
    for _, ch in ipairs(progression) do
      local arp_evs = build_arp_events(ch.notes, ch.duration, cursor_abs + pos)
      for _, ev in ipairs(arp_evs) do
        cycle_evs[#cycle_evs+1] = {pitch=ev.pitch, pos=pos+ev.pos, dur=ev.dur, vel=ev.vel}
      end
      pos = pos + ch.duration
    end
    local events = {}
    for cyc = 0, cycles - 1 do
      local cyc_off = cyc * cycle_beats
      for _, ev in ipairs(cycle_evs) do
        events[#events+1] = {
          pitch=ev.pitch, pos=cyc_off+ev.pos, dur=ev.dur,
          vel=ev.vel, channel=state.arp_channel,
        }
      end
    end
    local _, err = write_midi_item(track, item_start, item_len, events, ppq)
    if err then
      state.status_msg="Arp write error: "..err
      reaper.Undo_EndBlock("Chord Generator: write (failed)", -1); return
    end
    written[#written+1] = state.arp_track_name
  end

  -- Melody layer: continuously generated across cycles using shared context
  -- and the live RNG stream. Same seed + same inputs + same cycle count =
  -- identical output, and the first N cycles match live preview cycles 1..N.
  if state.mel_enabled then
    local track   = get_or_create_track(state.mel_track_name)
    local context = {}
    local mel_evs = {}
    local abs_pos = 0
    for _ = 1, cycles do
      abs_pos = build_melody_cycle(progression, context, mel_evs, abs_pos)
    end
    local events = {}
    for _, ev in ipairs(mel_evs) do
      events[#events+1] = {
        pitch=ev.pitch, pos=ev.pos, dur=ev.dur,
        vel=ev.vel, channel=state.mel_channel,
      }
    end
    local _, err = write_midi_item(track, item_start, item_len, events, ppq)
    if err then
      state.status_msg="Melody write error: "..err
      reaper.Undo_EndBlock("Chord Generator: write (failed)", -1); return
    end
    written[#written+1] = state.mel_track_name
  end

  -- Bass layer: one cycle generated with isolated RNG; pattern repeated verbatim.
  if state.bass_enabled then
    local track = get_or_create_track(state.bass_track_name)
    bass_rng_reseed()
    local cycle_evs = {}
    local pos = 0
    for i, ch in ipairs(progression) do
      local next_ch  = progression[(i % #progression) + 1]
      local bass_evs = build_bass_events(ch, ch.duration, next_ch)
      for _, ev in ipairs(bass_evs) do
        cycle_evs[#cycle_evs+1] = {pitch=ev.pitch, pos=pos+ev.pos, dur=ev.dur, vel=ev.vel}
      end
      pos = pos + ch.duration
    end
    local events = {}
    for cyc = 0, cycles - 1 do
      local cyc_off = cyc * cycle_beats
      for _, ev in ipairs(cycle_evs) do
        events[#events+1] = {
          pitch=ev.pitch, pos=cyc_off+ev.pos, dur=ev.dur,
          vel=ev.vel, channel=state.bass_channel,
        }
      end
    end
    local _, err = write_midi_item(track, item_start, item_len, events, ppq)
    if err then
      state.status_msg="Bass write error: "..err
      reaper.Undo_EndBlock("Chord Generator: write (failed)", -1); return
    end
    written[#written+1] = state.bass_track_name
  end

  local total_bars = 0
  for _, ch in ipairs(progression) do total_bars = total_bars + ch.dur_bars end
  total_bars = total_bars * cycles
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Chord Generator: write all layers", -1)
  state.status_msg = string.format(
    "Written to [%s]  |  seed %d  |  %d bars (%d×%d/%d) @ cursor.",
    table.concat(written, ", "), state.seed,
    total_bars, cycles, state.timesig_num, state.timesig_denom
  )
end

-- ----------------------------------------------------------------
--  SEED HELPERS
-- ----------------------------------------------------------------
local function randomise_seed()
  if state.seed_locked then return end
  state.seed     = math.floor(reaper.time_precise() * 100000) % 99999
  state.seed_str = tostring(state.seed)
  rng_seed(state.seed)
  reset_live()
  state.arp_live_events  = nil
  state.mel_live_events  = nil
  state.bass_live_events = nil
end

local function apply_seed_str()
  local n = tonumber(state.seed_str)
  if n and n >= 0 then
    state.seed     = math.floor(n) % 99999
    state.seed_str = tostring(state.seed)
    rng_seed(state.seed)
    reset_live()
    state.arp_live_events  = nil
    state.mel_live_events  = nil
    state.bass_live_events = nil
  end
end

-- ----------------------------------------------------------------
--  UI HELPERS
-- ----------------------------------------------------------------
local function combo(label, items, current_idx)
  local preview = items[current_idx] or "?"
  local changed, new_idx = false, current_idx
  if reaper.ImGui_BeginCombo(ctx, label, preview) then
    for i, v in ipairs(items) do
      local sel = (i == current_idx)
      -- Append "##i" so items sharing a visible label still get unique IDs.
      if reaper.ImGui_Selectable(ctx, v.."##"..i, sel) then new_idx, changed = i, true end
      if sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  return changed, new_idx
end

-- Grouped combo: items is a list of {label, group} or plain strings.
-- Renders non-selectable separator rows between groups.
-- Returns changed, new_idx (1-based index into selectable items only).
--
-- items format: { {label="name", group="GroupName"}, ... }
-- A new group header is drawn whenever group changes.
-- current_idx and returned idx count only selectable items.
local function combo_grouped(label, items, current_idx)
  local preview = (items[current_idx] and items[current_idx].label) or "?"
  local changed, new_idx = false, current_idx
  if reaper.ImGui_BeginCombo(ctx, label, preview) then
    local last_group = nil
    for i, item in ipairs(items) do
      -- Draw group separator header if group changed
      if item.group and item.group ~= last_group then
        if last_group then
          reaper.ImGui_Separator(ctx)
        end
        -- Non-selectable, styled header
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFAA44FF)
        reaper.ImGui_Text(ctx, "  "..item.group)
        reaper.ImGui_PopStyleColor(ctx)
        last_group = item.group
      end
      local sel = (i == current_idx)
      -- Append "##i" so items sharing a visible label still get unique IDs.
      if reaper.ImGui_Selectable(ctx, "  "..item.label.."##"..i, sel) then
        new_idx, changed = i, true
      end
      if sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  return changed, new_idx
end

local function sslider(label, val, lo, hi, w)
  reaper.ImGui_SetNextItemWidth(ctx, w or 80)
  return reaper.ImGui_SliderInt(ctx, label, val, lo, hi)
end

-- ----------------------------------------------------------------
--  GROUPED COMBO ITEM TABLES
--  Built once; used by combo_grouped() in draw_ui.
-- ----------------------------------------------------------------

-- Mode items grouped into Bright / Dark
local MODE_ITEMS = {
  {label="Major",          group="Bright"},
  {label="Lydian",         group="Bright"},
  {label="Lydian Dom",     group="Bright"},
  {label="Mixolydian",     group="Bright"},
  {label="Minor (nat.)",   group="Dark"},
  {label="Dorian",         group="Dark"},
  {label="Phrygian",       group="Dark"},
  {label="Locrian",        group="Dark"},
  {label="Harmonic Minor", group="Dark"},
}

-- Progression items built from PROGRESSIONS table (uses existing cat field)
local PROG_ITEMS = {}
for _, p in ipairs(PROGRESSIONS) do
  PROG_ITEMS[#PROG_ITEMS+1] = {label=p.name, group=p.cat or "Other"}
end

-- Melody preset items grouped
local MEL_PRESET_ITEMS = {
  {label="Free",            group="Organic"},
  {label="Flowing",         group="Organic"},
  {label="Structured",      group="Organic"},
  {label="Conversational",  group="Organic"},
  {label="Mechanical",      group="Rule-based"},
  {label="Phrase & Answer", group="Compositional"},
  {label="Fractal",         group="Compositional"},
  {label="Motif",           group="Compositional"},
}

-- Chord quality items grouped
local QUALITY_ITEMS = {
  {label="auto (mode)",  group="Default"},
  {label="maj",          group="Triads"},
  {label="min",          group="Triads"},
  {label="dim",          group="Triads"},
  {label="aug",          group="Triads"},
  {label="5 (power)",    group="Triads"},
  {label="sus2",         group="Suspended"},
  {label="sus4",         group="Suspended"},
  {label="maj7",         group="Seventh"},
  {label="min7",         group="Seventh"},
  {label="dom7",         group="Seventh"},
  {label="dim7",         group="Seventh"},
  {label="m7b5",         group="Seventh"},
  {label="6",            group="Sixth"},
  {label="min6",         group="Sixth"},
  {label="add9",         group="Extended"},
  {label="maj9",         group="Extended"},
  {label="min9",         group="Extended"},
  {label="dom9",         group="Extended"},
  {label="7b9",          group="Extended"},
}
-- Internal quality values parallel to QUALITY_ITEMS
local QUALITY_ITEM_VALUES = {
  "auto","maj","min","dim","aug","5",
  "sus2","sus4",
  "maj7","min7","dom7","dim7","m7b5",
  "6","min6",
  "add9","maj9","min9","dom9","7b9",
}

-- ----------------------------------------------------------------
--  DRAW UI
-- ----------------------------------------------------------------
local function draw_ui()
  local progression = build_progression()

  if reaper.GetPlayState() == 1 then
    state.timesig_num, state.timesig_denom = get_timesig_at_playpos()
  else
    state.timesig_num, state.timesig_denom = get_timesig_at_cursor()
  end

  -- ── Key / Mode ──────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, string.format("Key & Mode          [ %d/%d ]",
    state.timesig_num, state.timesig_denom))
  reaper.ImGui_SetNextItemWidth(ctx, 80)
  local ch, ni = combo("Root##root", NOTE_NAMES, state.root_idx)
  if ch then state.root_idx = ni; reset_live() end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 155)
  local cm, mi = combo_grouped("Mode##mode", MODE_ITEMS, state.mode_idx)
  if cm then state.mode_idx = mi; reset_live() end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 80)
  local co, ov = reaper.ImGui_SliderInt(ctx, "Octave##oct", state.octave, 2, 6)
  if co then state.octave = ov; reset_live() end

  -- ── Progression ──────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Progression")

  reaper.ImGui_SetNextItemWidth(ctx, 280)
  local cp, pi = combo_grouped("Preset##prog", PROG_ITEMS, state.prog_idx)
  if cp then
    state.prog_idx = pi
    local p = PROGRESSIONS[pi]
    if p.mode then
      local mi = mode_idx_by_name(p.mode)
      if mi then state.mode_idx = mi end
    end
    local n = (p.name=="Custom") and #state.custom_degrees or #p.degrees
    init_chord_arrays(n)
    load_preset_qualities(p, n)
    reset_live()
  end

  if PROGRESSIONS[state.prog_idx].name == "Custom" then
    reaper.ImGui_Text(ctx, "Degrees (1-7):")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local deg_str = table.concat(state.custom_degrees, " ")
    local ce, ns  = reaper.ImGui_InputText(ctx, "##cust", deg_str)
    if ce then
      local nd = {}
      for d in ns:gmatch("%d") do
        local di = tonumber(d)
        if di and di>=1 and di<=7 then nd[#nd+1]=di end
      end
      if #nd>0 then state.custom_degrees=nd; init_chord_arrays(#nd); reset_live() end
    end
  end

  -- ── Chord Settings ───────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Chord Settings")
  local degrees   = current_degrees()
  local mode      = MODE_NAMES[state.mode_idx]
  local qualities = MODE_CHORDS[mode]

  -- Column header
  reaper.ImGui_TextDisabled(ctx,
    string.format("%-18s %-8s %-6s %-10s %-6s", "Chord", "Quality", "Bars", "Inversion", ""))
  reaper.ImGui_Separator(ctx)

  for i, deg in ipairs(degrees) do
    local mode_quality = qualities[deg] or "maj"
    local override     = state.chord_quality_overrides[i]
    local quality      = override or mode_quality
    local root_m       = degree_root_midi(state.root_idx, mode, deg, state.octave)
    local root_name    = NOTE_NAMES[(root_m%12)+1]

    -- Chord root name
    reaper.ImGui_Text(ctx, string.format("%d. %-6s", i, root_name))
    reaper.ImGui_SameLine(ctx)

    -- Quality combo — highlighted if overridden
    if override then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x2244AAFF)
    end
    reaper.ImGui_SetNextItemWidth(ctx, 100)
    local cur_q_idx = 1  -- default = "auto"
    for qi, qv in ipairs(QUALITY_ITEM_VALUES) do
      if qv == (override or "auto") then cur_q_idx = qi; break end
    end
    local qc, qv = combo_grouped("##q"..i, QUALITY_ITEMS, cur_q_idx)
    if qc then
      local chosen = QUALITY_ITEM_VALUES[qv]
      state.chord_quality_overrides[i] = (chosen == "auto") and nil or chosen
      reset_live()
    end
    if override then reaper.ImGui_PopStyleColor(ctx) end

    reaper.ImGui_SameLine(ctx)

    -- Duration slider
    local cd, dv = sslider("##dur"..i, state.chord_durations[i] or 1, 1, 8, 55)
    if cd then state.chord_durations[i]=dv; reset_live() end
    reaper.ImGui_SameLine(ctx); reaper.ImGui_TextDisabled(ctx, "bars")
    reaper.ImGui_SameLine(ctx)

    -- Inversion slider
    local max_inv = math.min(3, #(CHORD_INTERVALS[quality] or {0})-1)
    local ci2, iv = sslider("inv##inv"..i, state.chord_inversions[i] or 0, 0, max_inv, 65)
    if ci2 then state.chord_inversions[i]=iv; reset_live() end

    -- Override indicator
    if override then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_TextDisabled(ctx, "* overriding "..mode_quality)
    end
  end

  -- Reset all overrides button
  local any_override = false
  for _, q in ipairs(state.chord_quality_overrides) do
    if q then any_override = true; break end
  end
  if any_override then
    if reaper.ImGui_SmallButton(ctx, "Reset all quality overrides") then
      for i = 1, #state.chord_quality_overrides do
        state.chord_quality_overrides[i] = nil
      end
      reset_live()
    end
  end

  local parts = {}; local total_bars = 0
  for _, c in ipairs(progression) do
    local lbl = c.label
    parts[#parts+1] = lbl.." ("..c.dur_bars..")"
    total_bars = total_bars + c.dur_bars
  end
  reaper.ImGui_TextDisabled(ctx,
    table.concat(parts, "  ->  ").."   ["..total_bars.." bars]"
    ..(any_override and "  (* = quality override)" or "")
  )

  -- ── Chord Layer ──────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Chord Layer")
  local lcc, lcv = reaper.ImGui_Checkbox(ctx, "Enabled##chenabled", state.chord_enabled)
  if lcc then state.chord_enabled = lcv end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local _, ctn = reaper.ImGui_InputText(ctx, "Track##ctrk", state.chord_track_name)
  state.chord_track_name = ctn
  reaper.ImGui_SameLine(ctx)
  local cchc, cchv = sslider("Ch##cch", state.chord_channel+1, 1, 16, 55)
  if cchc then state.chord_channel = cchv-1 end
  reaper.ImGui_SameLine(ctx)
  local cvc, cvv = sslider("Vel##cvel", state.chord_velocity, 1, 127, 65)
  if cvc then state.chord_velocity = cvv end

  -- ── Arp Layer ────────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Arp Layer")
  local lac, lav = reaper.ImGui_Checkbox(ctx, "Enabled##arp", state.arp_enabled)
  if lac then state.arp_enabled = lav end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local _, atn = reaper.ImGui_InputText(ctx, "Track##atrk", state.arp_track_name)
  state.arp_track_name = atn
  reaper.ImGui_SameLine(ctx)
  local achc, achv = sslider("Ch##ach", state.arp_channel+1, 1, 16, 55)
  if achc then state.arp_channel = achv-1 end

  reaper.ImGui_SetNextItemWidth(ctx, 110)
  local apc, apv = combo("Pattern##apatt", ARP_PATTERNS, state.arp_pattern_idx)
  if apc then state.arp_pattern_idx = apv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 90)
  local arc, arv = combo("Rate##arate", ARP_RATE_NAMES, state.arp_rate_idx)
  if arc then state.arp_rate_idx = arv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local aocc, aocv = sslider("Octaves##aoct", state.arp_octaves, 1, 4, 75)
  if aocc then state.arp_octaves = aocv; state.arp_live_events = nil end

  local agc, agv = sslider("Gate%%##gate", state.arp_gate, 5, 100, 75)
  if agc then state.arp_gate = agv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local avc, avv = sslider("Vel##avel", state.arp_velocity, 1, 127, 65)
  if avc then state.arp_velocity = avv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local ahc, ahv = sslider("+/-##human", state.arp_vel_human, 0, 40, 55)
  if ahc then state.arp_vel_human = ahv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local anpc, anpv = sslider("Prob%%##prob", state.arp_note_prob, 0, 100, 65)
  if anpc then state.arp_note_prob = anpv; state.arp_live_events = nil end

  local arc2, arv2 = sslider("Rigidity##rigid", state.arp_rigidity, 0, 100, 220)
  if arc2 then state.arp_rigidity = arv2; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local rlabels = {"chord tones only","mostly chord, hint of scale","chord-leaning blend",
                   "scale-leaning blend","mostly scale, anchored by chord",
                   "full scale (key/"..MODE_DISPLAY[state.mode_idx]..")"}
  local ri = state.arp_rigidity == 0 and 1 or state.arp_rigidity < 25 and 2
    or state.arp_rigidity < 50 and 3 or state.arp_rigidity < 75 and 4
    or state.arp_rigidity < 100 and 5 or 6
  reaper.ImGui_TextDisabled(ctx, rlabels[ri])

  local ab1c, ab1v = sslider("Beat 1 Prob%%##b1p", state.arp_beat1_prob, 0, 100, 110)
  if ab1c then state.arp_beat1_prob = ab1v; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 75)
  local agrc, agrv = combo("##accentgrid", ACCENT_GRID_NAMES, state.arp_beatn_idx)
  if agrc then state.arp_beatn_idx = agrv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local abnc, abnv = sslider("Prob%%##bnp", state.arp_beatn_prob, 0, 100, 90)
  if abnc then state.arp_beatn_prob = abnv; state.arp_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "  global: "..state.arp_note_prob.."%")

  -- ── Melody Layer ─────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Melody Layer")

  local mlc, mlv = reaper.ImGui_Checkbox(ctx, "Enabled##melenabled", state.mel_enabled)
  if mlc then state.mel_enabled = mlv end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local _, mtn = reaper.ImGui_InputText(ctx, "Track##mtrk", state.mel_track_name)
  state.mel_track_name = mtn
  reaper.ImGui_SameLine(ctx)
  local mchc, mchv = sslider("Ch##mch", state.mel_channel+1, 1, 16, 55)
  if mchc then state.mel_channel = mchv-1; state.mel_live_events=nil end

  -- Preset
  reaper.ImGui_SetNextItemWidth(ctx, 170)
  local mpc, mpv = combo_grouped("Preset##melpre", MEL_PRESET_ITEMS, state.mel_preset_idx)
  if mpc then state.mel_preset_idx = mpv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  local mbusyc, mbusyv = sslider("Busy##mbusy", state.mel_busyness, 0, 100, 70)
  if mbusyc then state.mel_busyness = mbusyv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  local mvc, mvv = sslider("Vel##mvel", state.mel_velocity, 1, 127, 65)
  if mvc then state.mel_velocity = mvv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  local mhc, mhv = sslider("+/-##mhuman", state.mel_vel_human, 0, 40, 55)
  if mhc then state.mel_vel_human = mhv; state.mel_live_events=nil end

  -- Duration range
  reaper.ImGui_SetNextItemWidth(ctx, 75)
  local mmnic, mmniv = combo("Min##mmin", MEL_DUR_NAMES, state.mel_min_dur_idx)
  if mmnic then
    state.mel_min_dur_idx = math.min(mmniv, state.mel_max_dur_idx)
    state.mel_live_events = nil
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 75)
  local mmxc, mmxv = combo("Max##mmax", MEL_DUR_NAMES, state.mel_max_dur_idx)
  if mmxc then
    state.mel_max_dur_idx = math.max(mmxv, state.mel_min_dur_idx)
    state.mel_live_events = nil
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "note duration range  ("
    ..MEL_DUR_NAMES[state.mel_min_dur_idx].." – "..MEL_DUR_NAMES[state.mel_max_dur_idx]..")")

  -- Octave range
  local mominc, ominv = sslider("Oct Min##momin", state.mel_oct_min, 2, 7, 80)
  if mominc then
    state.mel_oct_min = math.min(ominv, state.mel_oct_max)
    state.mel_live_events = nil
  end
  reaper.ImGui_SameLine(ctx)
  local momaxc, omaxv = sslider("Oct Max##momax", state.mel_oct_max, 2, 7, 80)
  if momaxc then
    state.mel_oct_max = math.max(omaxv, state.mel_oct_min)
    state.mel_live_events = nil
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "octave range")

  -- Rigidity + Colour + Metre
  local mrigc, mrigv = sslider("Rigidity##mrig", state.mel_rigidity, 0, 100, 130)
  if mrigc then state.mel_rigidity = mrigv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  -- apply_rigidity snaps non-chord tones with prob (1 - rigidity/100), and
  -- stops snapping entirely only at 100. Label the slider accordingly.
  local mrlabels = {"chord tones only","mostly chord, hint of scale","chord-leaning blend",
                    "scale-leaning blend","mostly scale, anchored by chord",
                    "full scale (key/"..MODE_DISPLAY[state.mode_idx]..")"}
  local mri = state.mel_rigidity == 0 and 1 or state.mel_rigidity < 25 and 2
    or state.mel_rigidity < 50 and 3 or state.mel_rigidity < 75 and 4
    or state.mel_rigidity < 100 and 5 or 6
  reaper.ImGui_TextDisabled(ctx, mrlabels[mri])
  reaper.ImGui_SameLine(ctx)
  local mcolc, mcolv = sslider("Colour##mcol", state.mel_colour, 0, 100, 100)
  if mcolc then state.mel_colour = mcolv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, state.mel_colour==0 and "no chromatic"
    or state.mel_colour < 40 and "hint of colour"
    or state.mel_colour < 75 and "passing tones"
    or "chromatic")

  local mmetc, mmetv = sslider("Metre##mmet", state.mel_metre, 0, 100, 130)
  if mmetc then state.mel_metre = mmetv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx,
    state.mel_metre == 0  and "free — any onset, any length" or
    state.mel_metre < 25  and "loose — slight beat preference" or
    state.mel_metre < 50  and "moderate — favours beats" or
    state.mel_metre < 75  and "strong — snaps to beat grid" or
    state.mel_metre < 90  and "strict — beats only, sub-beats rare" or
    "locked — onsets on whole beats (min-grid: "..MEL_DUR_NAMES[state.mel_min_dur_idx]..")")

  reaper.ImGui_TextDisabled(ctx, "Busy "..state.mel_busyness.." — "..(
    state.mel_busyness == 0  and "very sparse — long held notes, occasional rests" or
    state.mel_busyness < 25  and "sparse — mostly long notes, gentle activity" or
    state.mel_busyness < 50  and "balanced — mixed lengths, mild ebb & flow" or
    state.mel_busyness < 75  and "active — shorter notes prevail, arc-shaped clustering" or
    state.mel_busyness < 100 and "busy — bursts of subdivision around bar/half-bar landmarks" or
    "very busy — dense subdivision bursts, snapped to quarter-note boundaries"))

  -- ── Bass Layer ───────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Bass Layer")
  local blc, blv = reaper.ImGui_Checkbox(ctx, "Enabled##bass", state.bass_enabled)
  if blc then state.bass_enabled = blv; state.bass_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local _, btn = reaper.ImGui_InputText(ctx, "Track##btrk", state.bass_track_name)
  state.bass_track_name = btn
  reaper.ImGui_SameLine(ctx)
  local bchc, bchv = sslider("Ch##bch", state.bass_channel+1, 1, 16, 55)
  if bchc then state.bass_channel = bchv-1; state.bass_live_events = nil end

  reaper.ImGui_SetNextItemWidth(ctx, 120)
  local bsc, bsv = combo("Style##bstyle", BASS_STYLES, state.bass_style_idx)
  if bsc then state.bass_style_idx = bsv; state.bass_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local bocc, bocv = sslider("Oct##boct", state.bass_oct, 1, 4, 65)
  if bocc then state.bass_oct = bocv; state.bass_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local bfic, bfiv = reaper.ImGui_Checkbox(ctx, "Follow inv##bfinv", state.bass_follow_inv)
  if bfic then state.bass_follow_inv = bfiv; state.bass_live_events = nil end

  local bvc, bvv = sslider("Vel##bvel", state.bass_velocity, 1, 127, 65)
  if bvc then state.bass_velocity = bvv; state.bass_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local bhc, bhv = sslider("+/-##bhuman", state.bass_vel_human, 0, 40, 55)
  if bhc then state.bass_vel_human = bhv; state.bass_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local bgc, bgv = sslider("Gate%%##bgate", state.bass_gate, 5, 100, 75)
  if bgc then state.bass_gate = bgv; state.bass_live_events = nil end
  if BASS_STYLES[state.bass_style_idx] == "Walking" then
    reaper.ImGui_SameLine(ctx)
    local bac, bav = sslider("Approach%%##bapp", state.bass_approach_prob, 0, 100, 95)
    if bac then state.bass_approach_prob = bav; state.bass_live_events = nil end
  end
  if BASS_STYLES[state.bass_style_idx] == "Pattern" then
    reaper.ImGui_SetNextItemWidth(ctx, 80)
    local bgrc, bgrv = combo("Grid##bpgrid", ARP_RATE_NAMES, state.bass_pattern_grid_idx)
    if bgrc then state.bass_pattern_grid_idx = bgrv; state.bass_live_events = nil end
    reaper.ImGui_SameLine(ctx)
    local bstc, bstv = sslider("Steps##bpsteps", state.bass_pattern_steps, 1, 8, 60)
    if bstc then state.bass_pattern_steps = bstv; state.bass_live_events = nil end
    for i = 1, state.bass_pattern_steps do
      if i > 1 then reaper.ImGui_SameLine(ctx) end
      local nv = state.bass_pattern_notes[i]
      if reaper.ImGui_Button(ctx, BASS_PAT_LABELS[nv+1].."##bpn"..i, 30, 0) then
        state.bass_pattern_notes[i] = (nv + 1) % 4
        state.bass_live_events = nil
      end
    end
  end

  -- ── Live Preview ─────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Live Preview")

  local lec, lev = reaper.ImGui_Checkbox(ctx, "Chords##livecheck", state.live_enabled)
  if lec then
    state.live_enabled = lev
    if not lev then live_notes_off(); state.last_chord_idx=-1 end
  end
  if state.live_enabled then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, "Chord Ch")
    live_preview_tick(progression)
  end

  local alec, alev = reaper.ImGui_Checkbox(ctx, "Arp##arplivecheck", state.arp_live_enabled)
  if alec then
    state.arp_live_enabled = alev
    if not alev then arp_live_note_off(); state.arp_live_last_idx=-1 end
  end
  if state.arp_live_enabled then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, "Arp Ch")
    arp_live_tick(progression)
  end

  local mlec, mlev = reaper.ImGui_Checkbox(ctx, "Melody##mellivecheck", state.mel_live_enabled)
  if mlec then
    state.mel_live_enabled = mlev
    if not mlev then mel_live_note_off(); state.mel_live_last_idx=-1 end
  end
  if state.mel_live_enabled then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, "Melody Ch")
    mel_live_tick(progression)
  end

  local blec, blev = reaper.ImGui_Checkbox(ctx, "Bass##basslivecheck", state.bass_live_enabled)
  if blec then
    state.bass_live_enabled = blev
    if not blev then bass_live_note_off(); state.bass_live_last_idx=-1 end
  end
  if state.bass_live_enabled then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, "Bass Ch")
    bass_live_tick(progression)
  end

  if state.live_enabled or state.arp_live_enabled or state.mel_live_enabled
      or state.bass_live_enabled then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, "  Press Play to hear")
  end

  -- ── Seed & Keep ──────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Seed & Keep")
  reaper.ImGui_SetNextItemWidth(ctx, 100)
  local sec, sev = reaper.ImGui_InputText(ctx, "##seed", state.seed_str)
  if sec then state.seed_str = sev; apply_seed_str() end
  reaper.ImGui_SameLine(ctx)
  local slc, slv = reaper.ImGui_Checkbox(ctx, "Lock##seedlock", state.seed_locked)
  if slc then state.seed_locked = slv end
  reaper.ImGui_SameLine(ctx)
  if state.seed_locked then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "Randomise##randseed", 90, 0) then randomise_seed() end
  if state.seed_locked then reaper.ImGui_EndDisabled(ctx) end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format("seed: %d", state.seed))

  reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_Button(ctx, "Write to Tracks  (at edit cursor)", 240, 28) then
    write_all()
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "  KEEP this take  ", 160, 28) then
    state.seed_locked = true
    write_all()
    state.status_msg = "[KEPT]  "..state.status_msg
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 90)
  local rcc, rcv = reaper.ImGui_SliderInt(ctx, "cycles##rendercycles",
                                          state.mel_render_cycles, 1, 32)
  if rcc then state.mel_render_cycles = rcv end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextDisabled(ctx, state.status_msg)
end

-- ----------------------------------------------------------------
--  KEYBOARD PASSTHROUGH
-- ----------------------------------------------------------------
local function get_key(name)
  local fn = reaper["ImGui_Key_"..name]
  return fn and fn() or nil
end
local KEY_SPACE = get_key("Space") or 32
local KEY_HOME  = get_key("Home")  or 268
local KEY_END   = get_key("End")   or 269

local function handle_keys()
  if reaper.ImGui_IsAnyItemActive(ctx) then return end
  local function pressed(k)
    return k and reaper.ImGui_IsKeyPressed(ctx, k, false)
  end
  if pressed(KEY_SPACE) then reaper.Main_OnCommand(40044, 0) end
  if pressed(KEY_HOME)  then reaper.Main_OnCommand(40042, 0) end
  if pressed(KEY_END)   then reaper.Main_OnCommand(40043, 0) end
end

-- ----------------------------------------------------------------
--  MAIN LOOP
-- ----------------------------------------------------------------
local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 600, 920, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, "Chord Generator  –  Phase 3", true)
  if visible then
    local ok, err = pcall(draw_ui)
    if not ok then
      reaper.ImGui_TextColored(ctx, 0xFF4444FF, "Error: "..tostring(err))
    end
    handle_keys()
    reaper.ImGui_End(ctx)
  end
  if not open then
    live_notes_off(); arp_live_note_off(); mel_live_note_off(); bass_live_note_off()
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
