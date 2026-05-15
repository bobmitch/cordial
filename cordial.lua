-- ================================================================
--  cordial.lua  —  AUTO-GENERATED, DO NOT EDIT BY HAND
--
--  Run `lua plugin/scripts/bundle-cordial.lua` from the repo root
--  to regenerate. Source modules:
--    plugin/lua/core/*.lua    (host-agnostic music engine)
--    plugin/lua/host_reaper.lua  (REAPER glue: UI, MIDI, persist)
-- ================================================================

-- ================================================================
--  bundled from plugin/lua/core/theory.lua
-- ================================================================
local theory = (function()
-- ----------------------------------------------------------------
--  core/theory.lua  —  scale and chord tables
--
--  Pure data + one helper. The whole catalog of pitch intervals,
--  mode-flavoured chord qualities, and scale degrees lives here so
--  every layer (chords, arp, melody, bass) shares the same source
--  of truth. Host-agnostic — no `reaper.*` calls, no UI references.
-- ----------------------------------------------------------------

local M = {}

M.NOTE_NAMES = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }

M.CHORD_INTERVALS = {
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

M.MODE_CHORDS = {
  -- I  II/ii  III/iii  IV/iv  V/v  VI/vi  VII/vii  (built diatonically)
  major          = {"maj","min","min","maj","maj","min","dim"},
  lydian         = {"maj","maj","min","dim","maj","min","min"},
  lydian_dom     = {"maj","maj","dim","dim","min","min","aug"},
  mixolydian     = {"maj","min","dim","maj","min","min","maj"},
  minor          = {"min","dim","maj","min","min","maj","maj"},
  dorian         = {"min","min","maj","maj","min","dim","maj"},
  phrygian       = {"min","maj","maj","min","dim","maj","min"},
  locrian        = {"dim","maj","min","min","maj","maj","min"},
  harmonic_minor = {"min","dim","aug","min","maj","maj","dim"},
}

M.MODE_NAMES = {
  "major","lydian","lydian_dom","mixolydian",
  "minor","dorian","phrygian","locrian","harmonic_minor"
}

M.MODE_DISPLAY = {
  "Major","Lydian","Lydian Dom","Mixolydian",
  "Minor (nat.)","Dorian","Phrygian","Locrian","Harmonic Minor"
}

function M.mode_idx_by_name(name)
  for i, n in ipairs(M.MODE_NAMES) do
    if n == name then return i end
  end
  return nil
end

M.SCALE_INTERVALS = {
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

return M
end)()

-- ================================================================
--  bundled from plugin/lua/core/progressions.lua
-- ================================================================
local progressions = (function()
-- ----------------------------------------------------------------
--  core/progressions.lua  —  preset progression catalog
--
--  The full flat array of progression presets used by the chord-layer
--  generator. Grouped by `cat` for the UI dropdown but consumed by the
--  generator in flat-array order. Each entry's `mode` field is the
--  single source of truth for borrowed-chord root resolution — never
--  collapse a preset's mode for "simplicity", chord roots resolve via
--  `theory.SCALE_INTERVALS[mode][deg]`.
-- ----------------------------------------------------------------

local M = {}

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
--    inversions = (optional) per-slot voicing override. Each entry is
--               nil    → root position
--               int N  → Nth rotation (1 = 1st inv, 2 = 2nd inv, …)
--               string → slash-bass on a key scale degree, e.g. "3",
--                        "b7", "#4". Slash bass is an *added* low
--                        note (handles non-chord-tone bass like
--                        IV/1 pedal), independent of rotation.
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
M.PROGRESSIONS = {
  -- ── Diatonic (Major-key staples) ─────────────────────────────
  {cat="Diatonic",  name="I  IV  V  I",                            degrees={1,4,5,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  V  vi  IV (Axis, desc bass)",         degrees={1,5,6,4},         qualities={nil,nil,nil,nil},                       mode="major", inversions={0,1,0,0}},
  {cat="Diatonic",  name="I  IV  vi  V (cadential)",               degrees={1,4,6,5},         qualities={nil,nil,nil,nil},                       mode="major", inversions={0,0,0,1}},
  {cat="Diatonic",  name="ii  V  I  I",                            degrees={2,5,1,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  vi  IV  V (50s)",                     degrees={1,6,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="vi  IV  I  V",                           degrees={6,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  iii  IV  V",                          degrees={1,3,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  IV  I  V",                            degrees={1,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  vi  ii  V",                           degrees={1,6,2,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  IV  ii  V",                           degrees={1,4,2,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="vi  ii  V  I (circle)",                  degrees={6,2,5,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Diatonic",  name="I  V  vi  iii  IV  I  IV  V (Pachelbel)",degrees={1,5,6,3,4,1,4,5}, qualities={nil,nil,nil,nil,nil,nil,nil,nil},       mode="major", inversions={0,1,0,1,0,1,0,0}},
  {cat="Diatonic",  name="I  IV  V  vi (deceptive)",               degrees={1,4,5,6},         qualities={nil,nil,nil,nil},                       mode="major"},

  -- ── Pop / Folk / Singer-Songwriter ───────────────────────────
  {cat="Pop/Folk",  name="I  V  IV  V",                            degrees={1,5,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  iii  vi  IV (stepwise desc bass)",    degrees={1,3,6,4},         qualities={nil,nil,nil,nil},                       mode="major", inversions={0,2,0,"5"}},
  {cat="Pop/Folk",  name="vi  V  IV  V (descending)",              degrees={6,5,4,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  V  vi  iii",                          degrees={1,5,6,3},         qualities={nil,nil,nil,nil},                       mode="major", inversions={0,1,0,1}},
  {cat="Pop/Folk",  name="I  IV  vi  iii",                         degrees={1,4,6,3},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  V/vi  vi  IV",                        degrees={1,3,6,4},         qualities={"maj","dom7","min","maj"},              mode="major"},
  {cat="Pop/Folk",  name="vi  IV  V  I (uplift, walking bass)",    degrees={6,4,5,1},         qualities={nil,nil,nil,nil},                       mode="major", inversions={0,0,1,0}},
  {cat="Pop/Folk",  name="vi  iii  IV  I (lo-fi)",                 degrees={6,3,4,1},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  V  vi  IV  I  V  IV  IV (8-bar)",     degrees={1,5,6,4,1,5,4,4}, qualities={nil,nil,nil,nil,nil,nil,nil,nil},       mode="major"},
  {cat="Pop/Folk",  name="I  IV  I  V (folk)",                     degrees={1,4,1,5},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Pop/Folk",  name="I  vi7 IVadd9 iii7 (so true)",           degrees={1,6,4,3},         qualities={"maj7","min7","add9","min7"},            mode="major", inversions={2,0,1,1}},
  {cat="Pop/Folk",  name="I  V  vi  I  IV (long descending bass)", degrees={1,5,6,1,4},       qualities={nil,nil,nil,nil,nil},                   mode="major", inversions={0,1,0,2,0}},
  {cat="Pop/Folk",  name="I  II  IV  V (Lydian lift, pedal)",      degrees={1,2,4,5},         qualities={"maj","maj","maj","maj"},               mode="major", inversions={0,"1",0,0}},
  {cat="Pop/Folk",  name="I  v  bVII  IV (Toto Africa)",           degrees={1,5,7,4},         qualities={"add9","min7","add9","maj"},            mode="mixolydian"},

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
  {cat="Ambient",   name="Imaj7  IVmaj7 (tonic pedal float)",      degrees={1,4},             qualities={"maj7","maj7"},                         mode="major", inversions={0,"1"}},

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
  -- 13sus4 voiced as IVmaj7/V (Fmaj7/G in C): R, 4, 5, b7, 9, 13.
  -- D'Angelo / Bill Evans / Stevie idioms — the V13sus4 substitute.
  {cat="Neo-Soul",  name="Imaj7  IVmaj7/V  Imaj7  IVmaj7/V (D'Angelo sus hang)", degrees={1,4,1,4}, qualities={"maj7","maj7","maj7","maj7"},     mode="major", inversions={0,"5",0,"5"}},
  {cat="Neo-Soul",  name="Imaj7  iii7  IVmaj7/V  Imaj7 (Bill Evans sus turn)",   degrees={1,3,4,1}, qualities={"maj7","min7","maj7","maj7"},     mode="major", inversions={0,0,"5",0}},
  {cat="Neo-Soul",  name="ii7  IVmaj7/V  Imaj7  Imaj7 (sus ii-V-I)",             degrees={2,4,1,1}, qualities={"min7","maj7","maj7","maj7"},     mode="major", inversions={0,"5",0,0}},
  {cat="Neo-Soul",  name="Imaj7  vi7  ii7  IVmaj7/V (Isn't She Lovely turn)",    degrees={1,6,2,4}, qualities={"maj7","min7","min7","maj7"},     mode="major", inversions={0,0,0,"5"}},
  {cat="Neo-Soul",  name="iii7  vi7  ii9  IVmaj7/V (Overjoyed flow)",            degrees={3,6,2,4}, qualities={"min7","min7","min9","maj7"},     mode="major", inversions={0,0,0,"5"}},

  -- ── Jazz ─────────────────────────────────────────────────────
  {cat="Jazz",      name="Imaj7  vi7  ii7  V7 (turnaround)",       degrees={1,6,2,5},         qualities={"maj7","min7","min7","dom7"},           mode="major", inversions={0,0,0,1}},
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
  {cat="Gospel",    name="I  I  IV  IV  V7 (walking bass up)",     degrees={1,1,4,4,5},       qualities={"maj","maj","maj","maj","dom7"},        mode="major", inversions={0,1,0,"5",0}},

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
  {cat="Funk",      name="im9  bVII7 (Funk tonic pedal)",          degrees={1,7},             qualities={"min9","dom7"},                         mode="dorian", inversions={0,"1"}},

  -- ── Disco / EWF ──────────────────────────────────────────────
  -- Major-key 9ths and the IVmaj7/V sus13 button on the build.
  {cat="Disco",     name="IVmaj7  iii7  ii7  IVmaj7/V (After the Love)",   degrees={4,3,2,4},  qualities={"maj7","min7","min7","maj7"},           mode="major", inversions={0,0,0,"5"}},
  {cat="Disco",     name="vi9  ii9  IVmaj7/V  Imaj9 (September lift)",     degrees={6,2,4,1},  qualities={"min9","min9","maj7","maj9"},           mode="major", inversions={0,0,"5",0}},
  {cat="Disco",     name="iii7  vi9  IVmaj7/V  iii7 (Reasons vamp)",       degrees={3,6,4,3},  qualities={"min7","min9","maj7","min7"},           mode="major", inversions={0,0,"5",0}},
  {cat="Disco",     name="Imaj9  vi9  IVmaj7/V  Imaj9 (Fantasy float)",    degrees={1,6,4,1},  qualities={"maj9","min9","maj7","maj9"},           mode="major", inversions={0,0,"5",0}},

  -- ── Rock ─────────────────────────────────────────────────────
  {cat="Rock",      name="I  bVII  IV  I (classic)",               degrees={1,7,4,1},         qualities={"maj","maj","maj","maj"},               mode="mixolydian"},
  {cat="Rock",      name="I  V  IV (3-chord)",                     degrees={1,5,4},           qualities={"maj","maj","maj"},                     mode="major"},
  {cat="Rock",      name="I  IV  V  I (anthem)",                   degrees={1,4,5,1},         qualities={"maj","maj","maj","maj"},               mode="major"},
  {cat="Rock",      name="vi  IV  V  I",                           degrees={6,4,5,1},         qualities={"min","maj","maj","maj"},               mode="major"},
  {cat="Rock",      name="I  IV  bVII  IV (Mixo riff)",            degrees={1,4,7,4},         qualities={"maj","maj","maj","maj"},               mode="mixolydian"},
  {cat="Rock",      name="i  bVI  bIII  bVII (epic)",              degrees={1,6,3,7},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="Rock",      name="I5  IV5  V5 (power chords)",             degrees={1,4,5},           qualities={"5","5","5"},                           mode="major"},
  {cat="Rock",      name="i5  bVII5  bVI5  bVII5",                 degrees={1,7,6,7},         qualities={"5","5","5","5"},                       mode="minor"},
  {cat="Rock",      name="I  V  vi  iii  IV  I  IV  V (rock Pachelbel)", degrees={1,5,6,3,4,1,4,5}, qualities={nil,nil,nil,nil,nil,nil,nil,nil}, mode="major", inversions={0,1,0,1,0,1,0,0}},

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
  {cat="Latin",     name="Imaj7  VI7  ii7  V7 (bossa turn)",       degrees={1,6,2,5},         qualities={"maj7","dom7","min7","dom7"},           mode="major", inversions={0,0,0,1}},
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
  {cat="Cinematic", name="i  bIII  iv  bVI (lament, walking)",     degrees={1,3,4,6},         qualities={"min","maj","min","maj"},               mode="minor", inversions={0,2,1,"5"}},
  {cat="Cinematic", name="i  V/iv  iv  V (trailer build)",         degrees={1,1,4,5},         qualities={"min","dom7","min","maj"},              mode="harmonic_minor"},
  {cat="Cinematic", name="i  i  i  IV (Stairway descent)",         degrees={1,1,1,4},         qualities={"min","min","min","maj"},               mode="minor", inversions={0,"#7","7",1}},

  -- ── Game / JRPG (Japanese jazzy) ─────────────────────────────
  -- Mitsuda, Uematsu, Shimomura, Meguro, Kanno, Sakamoto — all lean
  -- hard on the IVmaj7/V sus13 voicing as a non-functional V sub.
  {cat="Game/JRPG", name="Imaj7  IIIm7  IVmaj7  IVmaj7/V (Schala flow, Mitsuda)", degrees={1,3,4,4}, qualities={"maj7","min7","maj7","maj7"},     mode="major", inversions={0,0,0,"5"}},
  {cat="Game/JRPG", name="IVmaj7  iii7  IVmaj7/V  Imaj7 (Aerith cadence, Uematsu)", degrees={4,3,4,1}, qualities={"maj7","min7","maj7","maj7"},   mode="major", inversions={0,0,"5",0}},
  {cat="Game/JRPG", name="Imaj7  IImaj7  IVmaj7/V  Imaj7 (Lyd sus float)",        degrees={1,2,4,1}, qualities={"maj7","maj7","maj7","maj7"},     mode="lydian", inversions={0,0,"5",0}},
  {cat="Game/JRPG", name="iim7  V7  IIIm7  IVmaj7/V (Persona jazz turn, Meguro)", degrees={2,5,3,4}, qualities={"min7","dom7","min7","maj7"},     mode="major", inversions={0,0,0,"5"}},
  {cat="Game/JRPG", name="vi7  IVmaj7/V  Imaj7  IIIm7 (Bebop cool turn, Kanno)",  degrees={6,4,1,3}, qualities={"min7","maj7","maj7","min7"},     mode="major", inversions={0,"5",0,0}},
  {cat="Game/JRPG", name="IIIm7  vi9  IVmaj7/V  Imaj9 (Sakamoto resolve)",        degrees={3,6,4,1}, qualities={"min7","min9","maj7","maj9"},     mode="major", inversions={0,0,"5",0}},
  {cat="Game/JRPG", name="Imaj7  bVIImaj7  IVmaj7/V  Imaj7 (Mixo sus, Shimomura)",degrees={1,7,4,1}, qualities={"maj7","maj7","maj7","maj7"},     mode="mixolydian", inversions={0,0,"5",0}},

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
  {cat="Classical", name="I  V  vi  iii  IV  I  IV  V (Pachelbel)",degrees={1,5,6,3,4,1,4,5}, qualities={nil,nil,nil,nil,nil,nil,nil,nil},       mode="major", inversions={0,1,0,1,0,1,0,0}},
  {cat="Classical", name="I  IV  V  vi (deceptive)",               degrees={1,4,5,6},         qualities={nil,nil,nil,nil},                       mode="major"},
  {cat="Classical", name="I  IV  I (plagal/amen)",                 degrees={1,4,1},           qualities={nil,nil,nil},                           mode="major"},
  {cat="Classical", name="i  iv  V7  I (Picardy)",                 degrees={1,4,5,1},         qualities={"min","min","dom7","maj"},              mode="harmonic_minor"},
  {cat="Classical", name="i  bVII  bVI  V (lament bass)",          degrees={1,7,6,5},         qualities={"min","maj","maj","maj"},               mode="minor"},
  {cat="Classical", name="bII  V7  i (Neapolitan)",                degrees={2,5,1},           qualities={"maj","dom7","min"},                    mode="phrygian"},
  {cat="Classical", name="i  iv  V7  i (minor cadence)",           degrees={1,4,5,1},         qualities={"min","min","dom7","min"},              mode="harmonic_minor"},
  {cat="Classical", name="I  vi  IV  V  I (extended cadence)",     degrees={1,6,4,5,1},       qualities={nil,nil,nil,nil,nil},                   mode="major"},
  {cat="Classical", name="I  V/V  V  I (secondary dom)",           degrees={1,2,5,1},         qualities={"maj","dom7","maj","maj"},              mode="major"},
  {cat="Classical", name="i  V7  iv  V7 (voice-led lament)",       degrees={1,5,4,5},         qualities={"min","dom7","min","dom7"},             mode="harmonic_minor", inversions={0,"7",1,0}},

  -- ── Custom ───────────────────────────────────────────────────
  {cat="Custom",    name="Custom",                                 degrees={},                qualities={},                                      mode=nil},
}

return M
end)()

-- ================================================================
--  bundled from plugin/lua/core/rng.lua
-- ================================================================
local rng = (function()
-- ----------------------------------------------------------------
--  core/rng.lua  —  seeded random helpers
--
--  Thin wrappers over Lua's math.random so every generator in core/
--  threads through a single deterministic stream. The seed contract
--  for Cordial is non-negotiable: same seed + same params →
--  identical output. Do not introduce bare math.random() calls in
--  core/ that bypass these helpers.
-- ----------------------------------------------------------------

local M = {}

function M.rng_seed(s) math.randomseed(s) end
function M.rng_float() return math.random() end
function M.rng_int(a, b) return math.random(a, b) end

-- Derive an independent-but-deterministic seed from a base seed. Used to
-- give a layer (e.g. bass) its own RNG stream that depends on the user's
-- seed but doesn't share state with the chord/arp/melody stream.
function M.derive_seed(base)
  return (base * 1664525 + 1013904223) % 99991 + 1
end

return M
end)()

-- ================================================================
--  bundled from plugin/lua/core/chord.lua
-- ================================================================
local chord = (function()
-- ----------------------------------------------------------------
--  core/chord.lua  —  chord construction and pitch utilities
--
--  Host-agnostic: every function here takes its inputs as plain values
--  (root_midi, quality string, mode name, etc.) so the host owns its
--  own state and just hands the right fields in.
--
--  Depends on core.theory for the chord-quality and scale-degree
--  interval tables.
-- ----------------------------------------------------------------

-- `theory` resolves to the IIFE-outer local in the REAPER bundle, or to
-- the require'd module in the VST/standalone context.
local theory = theory or require 'core.theory'

local M = {}

-- Convert (note_idx, octave) to MIDI. note_idx is 1-based (1 = C).
function M.midi_note(note_idx, octave)
  return (octave + 1) * 12 + (note_idx - 1)
end

-- The MIDI pitch of scale degree `deg` (1..7) in mode `mode` rooted at
-- (root_idx, octave). Uses SCALE_INTERVALS[mode][deg] for the offset,
-- which is also why each PROGRESSION preset must declare the correct
-- `mode` for borrowed-chord labels to render at the right pitch.
function M.degree_root_midi(root_idx, mode, deg, octave)
  return M.midi_note(root_idx, octave) + theory.SCALE_INTERVALS[mode][deg]
end

-- Build a chord voicing as a list of MIDI pitches.
--   root_midi   : MIDI pitch of the chord root
--   quality     : key into theory.CHORD_INTERVALS ("maj", "min7", etc.)
--   inversion   : 0 = root, 1 = first inv, … (wraps modulo voice count)
function M.build_chord(root_midi, quality, inversion)
  local ivs = theory.CHORD_INTERVALS[quality] or theory.CHORD_INTERVALS["maj"]
  local notes = {}
  for _, iv in ipairs(ivs) do notes[#notes+1] = root_midi + iv end
  local inv = inversion % #notes
  for _ = 1, inv do
    local lo = table.remove(notes, 1)
    notes[#notes+1] = lo + 12
  end
  return notes
end

-- Parse a slash-bass spec like "3", "b7", "#4" against the current key.
-- Returns the MIDI pitch placed below the supplied chord_root_midi (within
-- one octave of it). Returns nil for invalid specs.
function M.slash_bass_midi(spec, root_idx, mode, octave, chord_root_midi)
  if type(spec) ~= "string" or spec == "" then return nil end
  local accidental, deg_str = spec:match("^([b#]?)([1-7])$")
  if not deg_str then return nil end
  local deg = tonumber(deg_str)
  local semis = theory.SCALE_INTERVALS[mode][deg]
  if not semis then return nil end
  if accidental == "b" then semis = semis - 1
  elseif accidental == "#" then semis = semis + 1 end
  local p = M.midi_note(root_idx, octave) + semis
  -- Sit the bass below the chord root (within one octave).
  while p >= chord_root_midi do p = p - 12 end
  while p < chord_root_midi - 12 do p = p + 12 end
  return p
end

-- Return chord-tone pitches (any octave matching the chord's pitch
-- classes) within the closed pitch range [lo_p, hi_p].
function M.chord_notes_in_range(chord_notes, lo_p, hi_p)
  local pcs = {}
  for _, n in ipairs(chord_notes) do pcs[n % 12] = true end
  local result = {}
  for p = lo_p, hi_p do
    if pcs[p % 12] then result[#result+1] = p end
  end
  return result
end

-- Index of the nearest entry in a list of MIDI pitches to `pitch`.
function M.nearest_idx(notes, pitch)
  local best, best_dist = 1, 999
  for i, n in ipairs(notes) do
    local d = math.abs(n - pitch)
    if d < best_dist then best, best_dist = i, d end
  end
  return best
end

-- ----------------------------------------------------------------
--  build_progression(params)  →  array of chord slot records
--
--  Top-level chord-layer entry point. `params` is the host-agnostic
--  parameter table; every state-coupled generator across core/ takes
--  the same flat-table-of-named-fields shape so the C++ side can build
--  one table per generator from its AudioProcessorValueTreeState.
--
--  params:
--    mode               (string)   diatonic mode name; key into MODE_CHORDS
--                                  and SCALE_INTERVALS
--    root_idx           (int 1..12) root note index (1=C, 13 wraps to C)
--    octave             (int)      voicing octave for the lowest chord tone
--    timesig_num        (int)      beats per bar (for bars→beats conversion)
--    degrees            (array)    scale degree 1..7 per chord slot
--    quality_overrides  (array)    string|nil per slot — nil = use mode default
--    inversions         (array)    int per slot — 0 = root, N = Nth rotation
--    bass_overrides     (array)    slash-bass spec per slot, e.g. "3", "b7"
--    durations          (array)    int per slot in bars
--    smart_voicing      (bool)     enable inversion picker that minimises voice motion
--
--  All array params may be sparse or shorter than `degrees`; missing
--  entries fall back to defaults (no override, no inversion, no slash, 1 bar).
--
--  Returns a list of chord slot records, each:
--    { notes, voicing, quality, degree, duration, dur_bars, inversion,
--      slash_bass, root_midi, bass_midi, is_override, label }
-- ----------------------------------------------------------------
function M.build_progression(p)
  local default_qualities = theory.MODE_CHORDS[p.mode]
  local quality_overrides = p.quality_overrides or {}
  local inversions        = p.inversions        or {}
  local bass_overrides    = p.bass_overrides    or {}
  local durations         = p.durations         or {}

  local result     = {}
  local prev_notes = nil   -- previous chord's full close-position voicing

  for i, deg in ipairs(p.degrees) do
    local override = quality_overrides[i]
    local quality  = override or default_qualities[deg] or "maj"
    local root_m   = M.degree_root_midi(p.root_idx, p.mode, deg, p.octave)
    local user_inv = inversions[i] or 0
    local slash    = bass_overrides[i]
    local slash_midi = M.slash_bass_midi(slash, p.root_idx, p.mode, p.octave, root_m)
    local dur_bars  = durations[i] or 1
    local dur_beats = dur_bars * p.timesig_num

    -- Smart voicing: pick rotation that minimises total voice motion from
    -- the previous chord, with extra weight on the top voice (the ear
    -- tracks it most) and a soft pull keeping the top inside a comfortable
    -- register. Skipped when the user/preset has set an explicit non-zero
    -- rotation OR a slash bass for this slot, and skipped on chord 1.
    local inv = user_inv
    if p.smart_voicing and i > 1 and user_inv == 0 and not slash_midi and prev_notes then
      local ivs_count = #(theory.CHORD_INTERVALS[quality] or {0})
      local best, best_d = 0, math.huge
      local prev_top = prev_notes[#prev_notes]
      for cand = 0, math.min(ivs_count - 1, 3) do
        local cand_notes = M.build_chord(root_m, quality, cand)
        local pairs_n    = math.min(#cand_notes, #prev_notes)
        -- Weighted sum of per-voice semitone motion. Voices paired in
        -- ascending order — close-position triads stay register-aligned.
        local d = 0
        for v = 1, pairs_n do
          local w = (v == pairs_n) and 1.5 or 1.0   -- emphasise soprano
          d = d + w * math.abs(cand_notes[v] - prev_notes[v])
        end
        -- Soft register penalty: discourage the top voice straying far
        -- from where it just was, beyond a tolerance built into the
        -- weighting above. Keeps voicings from crawling up the keyboard.
        local top = cand_notes[#cand_notes]
        local drift = math.abs(top - prev_top)
        if drift > 7 then d = d + 0.75 * (drift - 7) end
        if d < best_d then best, best_d = cand, d end
      end
      inv = best
    end

    local notes      = M.build_chord(root_m, quality, inv)
    local voicing    = notes
    local bass_midi  = notes[1]
    if slash_midi then
      voicing = {slash_midi}
      for _, n in ipairs(notes) do voicing[#voicing+1] = n end
      bass_midi = slash_midi
    end
    local root_name  = theory.NOTE_NAMES[(root_m % 12) + 1]
    local label = root_name.." "..quality
    if slash_midi then
      label = label.."/"..theory.NOTE_NAMES[(slash_midi % 12) + 1]
    elseif inv > 0 then
      label = label.." inv"..inv
    end
    if override then label = label.." *" end
    result[#result+1] = {
      notes      = notes,
      voicing    = voicing,
      quality    = quality,
      degree     = deg,
      duration   = dur_beats,
      dur_bars   = dur_bars,
      inversion  = inv,
      slash_bass = slash,
      root_midi  = root_m,
      bass_midi  = bass_midi,
      is_override = override ~= nil,
      label      = label,
    }
    prev_notes = notes   -- chord tones only; slash bass excluded from voice-leading metric
  end
  return result
end

return M
end)()

-- ================================================================
--  bundled from plugin/lua/core/arp.lua
-- ================================================================
local arp = (function()
-- ----------------------------------------------------------------
--  core/arp.lua  —  arpeggiator pool and pattern transforms
--
--  Two host-agnostic primitives:
--    * build_arp_pool — gathers playable pitches for an arp across an
--      octave range, biased by rigidity toward chord tones vs. the
--      surrounding scale.
--    * apply_arp_pattern — transforms a pitch pool into the order the
--      arp plays it (Up / Down / Up-Down / Random / Pedal / Skip /
--      Alberti / Random Walk / etc.).
--
--  The host-stateful surrounding logic (`build_arp_events`,
--  `resolve_step_prob`) stays in host_reaper.lua until Phase 3
--  defines the params struct.
-- ----------------------------------------------------------------

local rng = rng or require 'core.rng'

local M = {}

-- Build the pool of pitches the arp draws from. Chord tones are always
-- included; non-chord scale tones are added with probability
-- `rigidity_pct/100` (so rigidity=100 → chord tones only).
--
-- Caller MUST supply `chord_scale_pcs` — a set keyed by pitch class
-- (0..11) of the scale to consider. In Cordial that's typically the
-- chord-aware scale (chord tones + global mode, conflicts resolved).
function M.build_arp_pool(chord_notes, oct_low, oct_high, rigidity_pct,
                          chord_scale_pcs)
  if #chord_notes == 0 then return {} end
  local chord_set = {}
  for _, n in ipairs(chord_notes) do chord_set[n % 12] = true end
  local scale_prob = rigidity_pct / 100.0
  local pool_set   = {}
  for oct = oct_low, oct_high do
    for pc = 0, 11 do
      local pitch = oct * 12 + pc
      if pitch >= 0 and pitch <= 127 then
        if chord_set[pc] then
          pool_set[pitch] = true
        elseif chord_scale_pcs[pc] and scale_prob > 0 then
          if rng.rng_float() < scale_prob then pool_set[pitch] = true end
        end
      end
    end
  end
  local pool = {}
  for pitch, _ in pairs(pool_set) do pool[#pool+1] = pitch end
  table.sort(pool)
  return pool
end

-- Transform a sorted pitch pool into the play sequence. Patterns that
-- need randomness consume entries from `rng_seq` (pre-generated floats
-- in [0, 1)) so the same seed produces the same shuffle.
function M.apply_arp_pattern(pool, pattern_name, rng_seq)
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
  elseif pattern_name == "Down-Weave" then
    -- mirror of Weave from the top: N, N-2, N-1, N-3, N-2, N-4...
    local r = {}
    for i = #pool, 3, -1 do
      r[#r+1] = pool[i]
      r[#r+1] = pool[i - 2]
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
  elseif pattern_name == "Top Pedal" then
    -- top note pedal between each lower note: N,N-1,N,N-2,N,N-3...
    local r = {}
    for i = #pool - 1, 1, -1 do
      r[#r+1] = pool[#pool]
      r[#r+1] = pool[i]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Converge" then
    -- outside-in: 1,N,2,N-1,3,N-2...
    local r = {}
    local lo, hi = 1, #pool
    while lo < hi do
      r[#r+1] = pool[lo]
      r[#r+1] = pool[hi]
      lo = lo + 1
      hi = hi - 1
    end
    if lo == hi then r[#r+1] = pool[lo] end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Skip" then
    -- odd indices then even: 1,3,5..., 2,4,6... (diatonic thirds)
    local r = {}
    for i = 1, #pool, 2 do r[#r+1] = pool[i] end
    for i = 2, #pool, 2 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Skip-Reverse" then
    -- descending broken thirds: N,N-2,N-4..., N-1,N-3,N-5...
    local r = {}
    for i = #pool, 1, -2 do r[#r+1] = pool[i] end
    for i = #pool - 1, 1, -2 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Diverge" then
    -- inside-out: middle outward (mirror of Converge)
    if #pool == 0 then return pool end
    local r = {}
    local n = #pool
    local lo, hi
    if n % 2 == 1 then
      local m = math.floor(n / 2) + 1
      r[#r+1] = pool[m]
      lo, hi = m - 1, m + 1
    else
      lo = n / 2; hi = lo + 1
      r[#r+1] = pool[lo]; r[#r+1] = pool[hi]
      lo = lo - 1; hi = hi + 1
    end
    while lo >= 1 do
      r[#r+1] = pool[lo]; r[#r+1] = pool[hi]
      lo = lo - 1; hi = hi + 1
    end
    return r
  elseif pattern_name == "Alberti" then
    -- Classical keyboard figure (root, fifth, third, fifth), confined to a
    -- single octave above pool[1] so the figure reads as Alberti rather than
    -- wide multi-octave leaps. Falls back to a root-top alternation when the
    -- pool doesn't have three distinct notes inside that window.
    if #pool < 2 then return pool end
    local lo = pool[1]
    local window = {}
    for _, p in ipairs(pool) do
      if p < lo + 12 then window[#window+1] = p else break end
    end
    if #window < 3 then
      local top = window[#window] or pool[#pool]
      return {lo, top, lo, top}
    end
    local top = window[#window]
    local mid = window[math.ceil(#window / 2)]
    return {lo, top, mid, top}
  elseif pattern_name == "Random Walk" then
    -- stepwise random motion through pool; smoother than pure Random
    if #pool == 0 then return pool end
    local r = {}
    local idx = math.floor((#pool + 1) / 2)
    if idx < 1 then idx = 1 end
    for i = 1, #rng_seq do
      r[#r+1] = pool[idx]
      local u = rng_seq[i]
      local step
      if u < 0.45 then step = 1
      elseif u < 0.9 then step = -1
      else step = 0
      end
      local nx = idx + step
      if nx < 1 or nx > #pool then nx = idx - step end
      idx = nx
    end
    return r
  end
  return pool
end

return M
end)()

-- ================================================================
--  bundled from plugin/lua/core/voicing.lua
-- ================================================================
local voicing = (function()
-- ----------------------------------------------------------------
--  core/voicing.lua  —  pitch-class sets and voice-leading
--
--  Generator-agnostic helpers shared by the chord, arp, bass and
--  melody layers. Conventions used throughout:
--
--    chord_pcs   = set { [pc]=true } of chord pitch-classes
--    scale_pcs   = set { [pc]=true } of scale pitch-classes
--    scale_notes = sorted list of MIDI pitches in some pitch range
--    chord_range = sorted list of chord-tone MIDI pitches in some pitch range
--
--  None of these functions read host state — callers pass mode/root
--  through explicitly. The two functions that need a "global scale"
--  to start from (chord_scale_pc_set, anything else with that flavour)
--  accept the global pc set as a parameter, so host_reaper.lua wraps
--  them with state-aware shims.
-- ----------------------------------------------------------------

local theory = theory or require 'core.theory'
local chord  = chord  or require 'core.chord'

local M = {}

-- Pitch-class set of a diatonic scale rooted at (mode, root_idx).
function M.scale_pc_set(mode, root_idx)
  local ivs     = theory.SCALE_INTERVALS[mode]
  local root_pc = (root_idx - 1) % 12
  local pcs     = {}
  for _, iv in ipairs(ivs) do pcs[(root_pc + iv) % 12] = true end
  return pcs
end

-- Pentatonic pitch-class set for a given key root and mode. Major-flavoured
-- modes use major pentatonic (1,2,3,5,6); minor-flavoured modes use minor
-- pentatonic (1,b3,4,5,b7). Used by the Pentatonic phrasing to restrict
-- the melody's scale pool while leaving the harmony untouched.
local PENT_MAJOR_INTERVALS = {0, 2, 4, 7, 9}
local PENT_MINOR_INTERVALS = {0, 3, 5, 7, 10}
function M.pentatonic_pcs_for(root_pc, mode_name)
  local minor_modes = {
    minor=true, dorian=true, phrygian=true,
    locrian=true, harmonic_minor=true,
  }
  local ivs = minor_modes[mode_name] and PENT_MINOR_INTERVALS or PENT_MAJOR_INTERVALS
  local pcs = {}
  for _, iv in ipairs(ivs) do pcs[(root_pc + iv) % 12] = true end
  return pcs
end

-- Pitch-class set of a chord's notes.
function M.chord_pc_set(chord_notes)
  local pcs = {}
  for _, n in ipairs(chord_notes) do pcs[n % 12] = true end
  return pcs
end

function M.is_chord_tone(pitch, chord_pcs) return chord_pcs[pitch % 12] == true end
function M.is_scale_tone(pitch, scale_pcs) return scale_pcs[pitch % 12] == true end

-- Chord-aware scale pitch-class set: the line-walking and colour-tone
-- pool that's correct for THIS chord, not just the global key. We start
-- from `global_pcs` (the caller's global scale pc set) and merge in the
-- chord's pitch-classes, then — crucially — let the chord's 3rd and 7th
-- override any conflicting scale tone in the same slot. So on a `V7/vi`
-- (E7 in C major) the diatonic G is dropped in favour of the chord's
-- G#; on `Imaj7` in C lydian-dominant the scale's b7 (Bb) is dropped in
-- favour of the chord's maj7 (B). Other characteristic colour tones in
-- the global mode (#11, b9, etc.) are preserved. Returns the pc set
-- plus a `differs_from_global` flag.
function M.chord_scale_pc_set(chord_notes, chord_root_midi, global_pcs)
  local chord_pcs = M.chord_pc_set(chord_notes)
  local merged    = {}
  for pc in pairs(global_pcs) do merged[pc] = true end
  local differs = false
  if chord_root_midi then
    local r = chord_root_midi % 12
    local has_min3 = chord_pcs[(r + 3)  % 12] == true
    local has_maj3 = chord_pcs[(r + 4)  % 12] == true
    local has_b7   = chord_pcs[(r + 10) % 12] == true
    local has_maj7 = chord_pcs[(r + 11) % 12] == true
    local function drop(pc)
      if merged[pc] and not chord_pcs[pc] then
        merged[pc] = nil
        differs = true
      end
    end
    if has_maj3 and not has_min3 then drop((r + 3)  % 12) end
    if has_min3 and not has_maj3 then drop((r + 4)  % 12) end
    if has_b7   and not has_maj7 then drop((r + 11) % 12) end
    if has_maj7 and not has_b7   then drop((r + 10) % 12) end
  end
  for pc in pairs(chord_pcs) do
    if not merged[pc] then differs = true end
    merged[pc] = true
  end
  return merged, differs
end

-- Sorted MIDI pitches inside [lo_p, hi_p] for a given pitch-class set.
function M.pcs_to_notes_in_range(pcs, lo_p, hi_p)
  local notes = {}
  for p = lo_p, hi_p do
    if pcs[p % 12] then notes[#notes+1] = p end
  end
  return notes
end

-- Snap a pitch to the nearest chord tone within a sorted chord_range.
function M.nearest_chord_tone(pitch, chord_range)
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
-- and for bass landings on chord roots.
function M.voice_lead_to_chord(prev_pitch, chord_range, max_leap)
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

-- Diatonic step from a pitch by n scale steps (negative = down).
function M.diatonic_step(scale_notes, pitch, n)
  local i = chord.nearest_idx(scale_notes, pitch)
  local j = math.max(1, math.min(#scale_notes, i + n))
  return scale_notes[j]
end

-- Diatonic neighbour of pitch (dir = +1 upper, -1 lower).
function M.diatonic_neighbor(scale_notes, pitch, dir)
  return M.diatonic_step(scale_notes, pitch, dir >= 0 and 1 or -1)
end

-- Leading-tone (semitone below) approach to a target.
function M.leading_tone_to(target_pitch) return target_pitch - 1 end

return M
end)()

-- ================================================================
--  bundled from plugin/lua/core/bass.lua
-- ================================================================
local bass = (function()
-- ----------------------------------------------------------------
--  core/bass.lua  —  bass-line generator
--
--  Top-level entry point: build_events(chord, chord_dur, next_chord, params).
--  Five styles: Root, Root-Fifth, Walking, Boogie, Pattern.
--
--  Bass generation uses its own RNG stream — the host reseeds via
--  rng.derive_seed(state.seed) before calling so the chord/arp/melody
--  stream isn't disturbed. Inside core/ we just consume rng.rng_float()
--  in whatever order; the host owns the stream's identity.
-- ----------------------------------------------------------------

local theory  = theory  or require 'core.theory'
local rng     = rng     or require 'core.rng'
local voicing = voicing or require 'core.voicing'

local M = {}

-- Resolve which MIDI pitch-class to anchor the bass line on for a given chord.
-- When `follow_inv` is true the actual bass note after inversion is used
-- (slash-chord semantics); otherwise the harmonic root is always used.
local function landing_pitch(chord, oct, follow_inv)
  local pc = follow_inv and (chord.bass_midi % 12) or (chord.root_midi % 12)
  return (oct + 1) * 12 + pc
end

local function pick_vel(base, human)
  local v = base + math.floor((rng.rng_float() * 2 - 1) * human)
  return math.max(1, math.min(127, v))
end

-- ----------------------------------------------------------------
--  build_events(chord, chord_dur, next_chord, params)
--    chord      : one slot record (from chord.build_progression)
--    chord_dur  : duration of this slot in beats
--    next_chord : following slot (nil at the end) — drives Walking approach notes
--    params:
--      style              (string)   "Root" | "Root-Fifth" | "Walking" |
--                                    "Boogie" | "Pattern"
--      oct                (int)      bass octave (e.g. 2 = C2)
--      velocity           (int)      base velocity
--      vel_human          (int)      humanise ±N around base velocity
--      gate               (int 0..100)  note length as % of slot length
--      follow_inv         (bool)     follow chord's bass after inversion / slash bass
--      approach_prob      (int 0..100) chance Walking inserts a semitone
--                                    approach to the next chord on the last beat
--      mode               (string)   diatonic mode key (for Walking scale)
--      root_idx           (int 1..12) key root (for Walking scale)
--      pattern_grid_beats (number)   step grid for Pattern style (beats)
--      pattern_steps      (int)      number of slots in the Pattern sequence
--      pattern_notes      (array)    int per slot: 0 = rest, 1 = root,
--                                    2 = fifth, 3 = octave-up
-- ----------------------------------------------------------------
function M.build_events(this_chord, chord_dur, next_chord, p)
  local events = {}
  local gate   = p.gate / 100.0
  local land   = landing_pitch(this_chord, p.oct, p.follow_inv)

  -- ── Root ────────────────────────────────────────────────────
  if p.style == "Root" then
    events[#events+1] = {pitch=land, pos=0, dur=chord_dur * gate,
                         vel=pick_vel(p.velocity, p.vel_human)}

  -- ── Root-Fifth ──────────────────────────────────────────────
  elseif p.style == "Root-Fifth" then
    if chord_dur < 2.0 then
      events[#events+1] = {pitch=land, pos=0, dur=chord_dur * gate,
                           vel=pick_vel(p.velocity, p.vel_human)}
    else
      local half     = chord_dur / 2
      local fifth_pc = (land % 12 + 7) % 12
      local fifth    = (p.oct + 1) * 12 + fifth_pc
      if fifth < land then fifth = fifth + 12 end   -- keep fifth above root
      events[#events+1] = {pitch=land,  pos=0,    dur=half * gate,
                           vel=pick_vel(p.velocity, p.vel_human)}
      events[#events+1] = {pitch=fifth, pos=half, dur=half * gate,
                           vel=pick_vel(p.velocity, p.vel_human)}
    end

  -- ── Walking ─────────────────────────────────────────────────
  elseif p.style == "Walking" then
    local ivs       = theory.SCALE_INTERVALS[p.mode]
    local root_pc   = (p.root_idx - 1) % 12
    -- Two octaves of scale tones centred on `oct` for walking room.
    local scale_bass = {}
    for o = p.oct, p.oct + 1 do
      for _, iv in ipairs(ivs) do
        scale_bass[#scale_bass+1] = (o + 1) * 12 + (root_pc + iv) % 12
      end
    end
    table.sort(scale_bass)
    local n_beats   = math.max(1, math.floor(chord_dur + 0.5))
    local next_land = next_chord and landing_pitch(next_chord, p.oct, p.follow_inv) or land
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
        if rng.rng_float() < p.approach_prob / 100.0 then
          local diff = next_land - prev_pitch
          if diff > 0 then
            pitch = next_land - 1   -- semitone below (approach from below)
          elseif diff < 0 then
            pitch = next_land + 1   -- semitone above (approach from above)
          else
            pitch = land
          end
          -- Clamp to the same two-octave window the walking line uses.
          pitch = math.max((p.oct + 1) * 12,
                           math.min((p.oct + 2) * 12 - 1, pitch))
        else
          pitch = voicing.voice_lead_to_chord(prev_pitch, scale_bass, 5)
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
        pitch = best or voicing.voice_lead_to_chord(prev_pitch, scale_bass, 5)
      end
      events[#events+1] = {pitch=pitch, pos=pos, dur=dur,
                           vel=pick_vel(p.velocity, p.vel_human)}
      prev_pitch = pitch
    end

  -- ── Boogie ──────────────────────────────────────────────────
  -- Classic R-5-6-5 shuffle figure, one step per 8th-note (0.5 beats),
  -- pattern repeats every 4 steps. The pulse is intentionally in beat-
  -- relative 8ths regardless of time-signature denominator — boogie is
  -- fundamentally a 4/4 idiom; compound meters will cross pulse groups.
  elseif p.style == "Boogie" then
    local half_beat = 0.5
    local n_steps   = math.floor(chord_dur / half_beat + 0.5)
    local fifth_pc  = (land % 12 + 7) % 12
    local fifth     = (p.oct + 1) * 12 + fifth_pc
    if fifth < land then fifth = fifth + 12 end
    -- Upper note: major 6th (+9) for major/dominant, minor 7th (+10) for
    -- minor chords. Power chords have no 3rd in CHORD_INTERVALS so they
    -- read as "not minor" and get the major-6th boogie — the safer default.
    local ivs_chord = theory.CHORD_INTERVALS[this_chord.quality]
                      or theory.CHORD_INTERVALS["maj"]
    local is_minor  = false
    for _, iv in ipairs(ivs_chord) do if iv == 3 then is_minor = true; break end end
    local upper_pc  = (land % 12 + (is_minor and 10 or 9)) % 12
    local upper     = (p.oct + 1) * 12 + upper_pc
    if upper < land then upper = upper + 12 end
    local pattern = {land, fifth, upper, fifth}
    for s = 0, n_steps - 1 do
      local pos = s * half_beat
      local dur = math.min(half_beat * gate, chord_dur - pos)
      events[#events+1] = {pitch=pattern[(s % 4)+1], pos=pos, dur=dur,
                           vel=pick_vel(p.velocity, p.vel_human)}
    end

  -- ── Pattern ─────────────────────────────────────────────────
  elseif p.style == "Pattern" then
    local grid     = p.pattern_grid_beats
    local steps    = p.pattern_steps
    local fifth_pc = (land % 12 + 7) % 12
    local fifth    = (p.oct + 1) * 12 + fifth_pc
    if fifth < land then fifth = fifth + 12 end
    local oct_up   = land + 12
    local pitches  = {land, fifth, oct_up}   -- indexed by note value 1/2/3
    local step_idx = 0
    local pos      = 0
    while pos < chord_dur - 0.001 do
      local nv  = p.pattern_notes[(step_idx % steps) + 1]
      local dur = math.min(grid * gate, chord_dur - pos)
      if nv > 0 then
        events[#events+1] = {pitch=pitches[nv], pos=pos, dur=dur,
                             vel=pick_vel(p.velocity, p.vel_human)}
      end
      pos      = pos + grid
      step_idx = step_idx + 1
    end
  end

  return events
end

return M
end)()

-- ============================================================
--  cordial  –  REAPER chord / arp / melody generator
--
--  Generates MIDI items at the edit cursor for three independent
--  layers, each on its own auto-created track, all driven from a
--  single seeded RNG so a given seed + parameter set is reproducible.
--
--  Layers:
--    • Chords   – block chords from a large catalog of progression
--                 presets (diatonic, modal, borrowed, jazz, blues,
--                 cadential, etc.), grouped by category. Each preset
--                 carries its own mode so borrowed-chord labels
--                 (bVII, bII, …) render at the correct root.
--                 Per-slot chord-quality overrides are supported.
--    • Arp      – chord-tone pool across a configurable octave range,
--                 pattern (Up / Down / UpDown / Random / Chord),
--                 stepped at a selectable rate.
--    • Melody   – eight generation presets (free, flowing, structured,
--                 conversational, mechanical, phrase/answer, fractal,
--                 motif) sharing a phrase-arc tension/density envelope,
--                 metric-weight beat scoring, diatonic voice leading,
--                 chromatic colour (passing tones), rigidity (snap
--                 toward chord tones), min/max note duration, metre
--                 enforcement, and busyness (arc-shaped density /
--                 clustering around bar / half-bar landmarks).
--
--  Live MIDI preview for each layer updates as parameters change.
--  Time signature is read live at the cursor every frame; durations
--  flow as beats and convert to PPQ only at MIDI write time.
--  User-facing parameters persist per-project via SetProjExtState.
--
--  Requires: REAPER + ReaImGui extension (install via ReaPack).
-- ============================================================

local ctx = reaper.ImGui_CreateContext("Chord Generator")


-- ----------------------------------------------------------------
--  Module imports
--  (resolved by plugin/scripts/bundle-cordial.lua before this file)
-- ----------------------------------------------------------------
local NOTE_NAMES       = theory.NOTE_NAMES
local CHORD_INTERVALS  = theory.CHORD_INTERVALS
local MODE_CHORDS      = theory.MODE_CHORDS
local MODE_NAMES       = theory.MODE_NAMES
local MODE_DISPLAY     = theory.MODE_DISPLAY
local SCALE_INTERVALS  = theory.SCALE_INTERVALS
local mode_idx_by_name = theory.mode_idx_by_name
local PROGRESSIONS     = progressions.PROGRESSIONS
local rng_seed         = rng.rng_seed
local rng_float        = rng.rng_float
local rng_int          = rng.rng_int
local midi_note            = chord.midi_note
local degree_root_midi     = chord.degree_root_midi
local build_chord          = chord.build_chord
local slash_bass_midi      = chord.slash_bass_midi
local chord_notes_in_range = chord.chord_notes_in_range
local nearest_idx          = chord.nearest_idx
local build_arp_pool       = arp.build_arp_pool
local apply_arp_pattern    = arp.apply_arp_pattern
local pentatonic_pcs_for   = voicing.pentatonic_pcs_for
local chord_pc_set         = voicing.chord_pc_set
local is_chord_tone        = voicing.is_chord_tone
local is_scale_tone        = voicing.is_scale_tone
local pcs_to_notes_in_range = voicing.pcs_to_notes_in_range
local nearest_chord_tone   = voicing.nearest_chord_tone
local voice_lead_to_chord  = voicing.voice_lead_to_chord
local diatonic_step        = voicing.diatonic_step
local diatonic_neighbor    = voicing.diatonic_neighbor
local leading_tone_to      = voicing.leading_tone_to

-- Host-side wrappers around voicing.scale_pc_set / chord_scale_pc_set
-- that capture the current global key state so the bulk of the host
-- code reads unchanged.
local function scale_pc_set()
  return voicing.scale_pc_set(MODE_NAMES[state.mode_idx], state.root_idx)
end
local function chord_scale_pc_set(chord_notes, chord_root_midi)
  return voicing.chord_scale_pc_set(chord_notes, chord_root_midi, scale_pc_set())
end


-- (PROG_NAMES, QUALITY_LIST, QUALITY_DISPLAY replaced by grouped item tables below)

-- Arp rate / accent-grid options, sorted longest → shortest, with triplets
-- interleaved at their natural pulse.
local ARP_RATES = {
  {label="1/4",   beats=1.0},
  {label="1/4T",  beats=2/3},
  {label="1/8",   beats=0.5},
  {label="1/8T",  beats=1/3},
  {label="1/16",  beats=0.25},
  {label="1/16T", beats=1/6},
  {label="1/32",  beats=0.125},
}
local ARP_RATE_NAMES = {}
for _, r in ipairs(ARP_RATES) do ARP_RATE_NAMES[#ARP_RATE_NAMES+1] = r.label end

local ACCENT_GRID = ARP_RATES
local ACCENT_GRID_NAMES = ARP_RATE_NAMES

local ARP_PATTERNS = {"Up","Down","Up-Down","Down-Up","Random","Chord","Weave","Pedal","Skip","Down-Weave","Top Pedal","Converge","Skip-Reverse","Diverge","Alberti","Random Walk"}

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

-- Anchor modes for the melody pitch window. Index matches state.mel_anchor_mode.
local MEL_ANCHOR_NAMES = { "Fixed", "Chord root", "Scale root" }

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
  -- Per-slot slash-bass override: nil = none; string like "3", "b7", "#4"
  -- = scale-degree-of-the-key bass placed below the chord. Independent of
  -- chord_inversions (rotation): a slash bass is an *added* low note, not a
  -- rotation. Non-chord-tone slashes (e.g. F/G) are how pedal/inverted-bass
  -- moves are spelled.
  chord_bass_overrides = {},
  -- When true, build_progression auto-picks a rotation that minimises bass
  -- leap from the previous chord, for any slot the user/preset hasn't
  -- explicitly inverted or slashed. Non-destructive: state.chord_inversions
  -- is not mutated.
  smart_voicing    = false,

  -- Chord layer
  chord_track_name = "Chords",
  chord_channel    = 0,
  chord_enabled    = true,
  chord_velocity   = 80,

  -- Arp layer
  arp_enabled      = true,
  arp_track_name   = "Arp",
  arp_channel      = 1,
  arp_rate_idx     = 3,          -- 1/8
  arp_pattern_idx  = 1,
  arp_oct_low      = 3,
  arp_oct_high     = 4,
  arp_gate         = 80,
  arp_velocity     = 90,
  arp_vel_human    = 15,
  arp_note_prob    = 100,
  arp_beat1_prob   = 100,
  arp_beatn_prob   = 100,
  arp_beatn_idx    = 3,          -- 1/8 (offbeat accent grid)
  arp_rigidity     = 0,

  -- Melody layer
  mel_enabled      = true,
  mel_track_name   = "Melody",
  mel_channel      = 2,          -- 0-based (MIDI ch 3)
  mel_preset_idx   = 1,          -- index into MEL_PRESET_ITEMS
  -- Phrasing: genre-flavoured colouring layered over any preset/progression.
  -- 1 = None (diatonic, current behaviour)
  -- 2 = Bluesy    (b3/b7 added to the pool, b3→3 / b7→1 / b5→5 bends)
  -- 3 = Pentatonic (scale pool restricted to major or minor pentatonic
  --                 plus the current chord's tones)
  mel_phrasing_idx = 1,
  mel_min_dur_idx  = 2,          -- default min = 1/16
  mel_max_dur_idx  = 6,          -- default max = 1/2
  mel_velocity     = 85,
  mel_vel_human    = 20,
  -- Melody pitch window. The window is [anchor - mel_range_down,
  -- anchor + mel_range_up] in semitones; the anchor is selected per
  -- block by mel_anchor_mode:
  --   1 = Fixed       (tonic at mel_anchor_oct — register independent of chord)
  --   2 = Chord root  (ch.root_midi — window travels with the harmony)
  --   3 = Scale root  (tonic at state.octave — fixed key centre)
  -- Asymmetric defaults match real lead playing: ride above the chord,
  -- dip a fifth below.
  mel_anchor_mode  = 2,
  mel_anchor_oct   = 4,
  mel_range_up     = 14,
  mel_range_down   = 7,
  mel_busyness     = 45,         -- 0=sparse/long-held, 100=dense/clustered bursts
  mel_space        = 0,          -- 0=fill the bar, 100=lots of rests, onsets pinned to quarters
  mel_cadence      = 60,         -- 0=free wander, 100=textbook cadences w/ phrase grammar
  -- Internal: derived from mel_cadence each generation pass via
  -- apply_cadence_to_legacy(). Not user-facing; readers across
  -- mel_fill_block / build_onset_candidates / pick_dur_slots /
  -- maybe_insert_colour consume them as locals.
  mel_colour       = 0,
  mel_metre        = 50,
  -- Rhythmic rigidity: bias each note's duration to match the onset's grid
  -- alignment. 0 = current chaotic behaviour; 100 = a 1/4 only starts on a
  -- 1/4 boundary, an 1/8 only on an 1/8 boundary, etc.
  mel_rhythm_rigidity = 0,
  render_cycles = 4,         -- offline write: number of progression cycles to render

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
  bass_pattern_grid_idx = 3,       -- index into ARP_RATES; default 1/8
  bass_pattern_notes    = {1,0,1,2, 0,0,0,0},  -- 0=rest,1=root,2=fifth,3=oct

  -- Bass live preview
  bass_live_enabled   = false,
  bass_live_note      = -1,
  bass_live_note_end  = -1,
  bass_live_events    = nil,
  bass_live_total_beats = 0,
  bass_live_last_idx  = -1,
  bass_wait_boundary  = false,

  -- Section open/collapsed state
  arp_open  = true,
  mel_open  = true,
  bass_open = true,

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
  chord_live_enabled  = false,
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
  state.chord_bass_overrides  = {}
  for i = 1, n do
    state.chord_durations[i]        = 1
    state.chord_inversions[i]       = 0
    state.chord_quality_overrides[i] = nil  -- auto = follow mode
    state.chord_bass_overrides[i]    = nil  -- no slash bass
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

-- Load inversions / slash-bass overrides from a preset's `inversions` array.
-- Each entry is one of:
--   nil       → root position
--   integer N → rotate chord N times (Nth inversion)
--   string    → slash-bass spec like "3", "b7", "#4" (scale degree of key,
--               with optional accidental). Stored in chord_bass_overrides.
local function load_preset_inversions(preset, n)
  state.chord_inversions     = {}
  state.chord_bass_overrides = {}
  for i = 1, n do
    state.chord_inversions[i]     = 0
    state.chord_bass_overrides[i] = nil
    local v = preset.inversions and preset.inversions[i]
    if type(v) == "number" then
      state.chord_inversions[i] = math.max(0, math.floor(v))
    elseif type(v) == "string" and v ~= "" then
      state.chord_bass_overrides[i] = v
    end
  end
end
init_chord_arrays(4)
load_preset_qualities(PROGRESSIONS[state.prog_idx], 4)
load_preset_inversions(PROGRESSIONS[state.prog_idx], 4)
state.seed_str = tostring(state.seed)

-- ----------------------------------------------------------------
--  PROJECT STATE PERSISTENCE
-- ----------------------------------------------------------------
-- Scalar state fields that are saved/loaded per-project via SetProjExtState.
-- When adding a new persistent scalar to `state`, append its key here.
-- For new array fields, add explicit handling in save/load_proj_state below.
local PERSIST_KEYS = {
  "root_idx", "mode_idx", "octave",
  "prog_idx",
  -- Chord layer
  "chord_track_name", "chord_channel", "chord_enabled", "chord_velocity",
  -- Arp layer
  "arp_enabled", "arp_track_name", "arp_channel", "arp_rate_idx",
  "arp_pattern_idx", "arp_oct_low", "arp_oct_high", "arp_gate", "arp_velocity",
  "arp_vel_human", "arp_note_prob", "arp_beat1_prob", "arp_beatn_prob",
  "arp_beatn_idx", "arp_rigidity",
  -- Melody layer
  "mel_enabled", "mel_track_name", "mel_channel", "mel_preset_idx",
  "mel_phrasing_idx",
  "mel_min_dur_idx", "mel_max_dur_idx", "mel_velocity", "mel_vel_human",
  "mel_anchor_mode", "mel_anchor_oct", "mel_range_up", "mel_range_down",
  "mel_busyness", "mel_space", "mel_cadence",
  "mel_rhythm_rigidity", "render_cycles",
  -- Bass layer
  "bass_enabled", "bass_track_name", "bass_channel", "bass_style_idx",
  "bass_oct", "bass_follow_inv", "bass_velocity", "bass_vel_human",
  "bass_gate", "bass_approach_prob", "bass_pattern_steps", "bass_pattern_grid_idx",
  -- Section open state
  "arp_open", "mel_open", "bass_open",
  -- Seed / PPQ
  "seed", "seed_locked", "ppq_per_beat",
  -- Voicing
  "smart_voicing",
}

local EXT_NS = "cordial"  -- namespace for SetProjExtState

local function arr_to_str(t)
  local parts = {}
  for i = 1, #t do parts[i] = tostring(t[i] ~= nil and t[i] or "") end
  return table.concat(parts, ",")
end

local function str_to_num_arr(s, n)
  local t = {}
  local i = 0
  for tok in (s..","):gmatch("([^,]*),") do
    i = i + 1
    t[i] = tonumber(tok) or 0
    if i >= n then break end
  end
  return t
end

local function save_proj_state()
  -- Scalars
  for _, k in ipairs(PERSIST_KEYS) do
    reaper.SetProjExtState(0, EXT_NS, k, tostring(state[k]))
  end
  -- Arrays
  local nd = #state.chord_durations
  reaper.SetProjExtState(0, EXT_NS, "num_chords", tostring(nd))
  reaper.SetProjExtState(0, EXT_NS, "chord_durations",  arr_to_str(state.chord_durations))
  reaper.SetProjExtState(0, EXT_NS, "chord_inversions", arr_to_str(state.chord_inversions))
  -- quality overrides: nil entries serialised as ""
  local qparts = {}
  for i = 1, nd do qparts[i] = state.chord_quality_overrides[i] or "" end
  reaper.SetProjExtState(0, EXT_NS, "chord_quality_overrides", table.concat(qparts, ","))
  -- slash bass overrides: nil entries serialised as ""
  local bparts = {}
  for i = 1, nd do bparts[i] = state.chord_bass_overrides[i] or "" end
  reaper.SetProjExtState(0, EXT_NS, "chord_bass_overrides", table.concat(bparts, ","))
  -- custom degrees
  reaper.SetProjExtState(0, EXT_NS, "custom_degrees_n", tostring(#state.custom_degrees))
  reaper.SetProjExtState(0, EXT_NS, "custom_degrees",   arr_to_str(state.custom_degrees))
  -- bass pattern
  reaper.SetProjExtState(0, EXT_NS, "bass_pattern_notes", arr_to_str(state.bass_pattern_notes))
end

local function load_proj_state()
  local ok, val
  ok, val = reaper.GetProjExtState(0, EXT_NS, "root_idx")
  if not ok or val == "" then return end  -- nothing saved yet for this project

  -- Scalars
  for _, k in ipairs(PERSIST_KEYS) do
    ok, val = reaper.GetProjExtState(0, EXT_NS, k)
    if ok and val ~= "" then
      local def = state[k]
      if type(def) == "number" then
        state[k] = tonumber(val) or def
      elseif type(def) == "boolean" then
        state[k] = (val == "true")
      else
        state[k] = val
      end
    end
  end

  -- Arrays
  ok, val = reaper.GetProjExtState(0, EXT_NS, "num_chords")
  local nd = (ok and tonumber(val)) or #state.chord_durations

  ok, val = reaper.GetProjExtState(0, EXT_NS, "chord_durations")
  if ok and val ~= "" then state.chord_durations = str_to_num_arr(val, nd) end

  ok, val = reaper.GetProjExtState(0, EXT_NS, "chord_inversions")
  if ok and val ~= "" then state.chord_inversions = str_to_num_arr(val, nd) end

  ok, val = reaper.GetProjExtState(0, EXT_NS, "chord_quality_overrides")
  if ok and val ~= "" then
    state.chord_quality_overrides = {}
    local i = 0
    for tok in (val..","):gmatch("([^,]*),") do
      i = i + 1
      state.chord_quality_overrides[i] = (tok ~= "") and tok or nil
      if i >= nd then break end
    end
  end

  ok, val = reaper.GetProjExtState(0, EXT_NS, "chord_bass_overrides")
  if ok and val ~= "" then
    state.chord_bass_overrides = {}
    local i = 0
    for tok in (val..","):gmatch("([^,]*),") do
      i = i + 1
      state.chord_bass_overrides[i] = (tok ~= "") and tok or nil
      if i >= nd then break end
    end
  end

  ok, val = reaper.GetProjExtState(0, EXT_NS, "custom_degrees_n")
  local cdn = (ok and tonumber(val)) or #state.custom_degrees
  ok, val = reaper.GetProjExtState(0, EXT_NS, "custom_degrees")
  if ok and val ~= "" then state.custom_degrees = str_to_num_arr(val, cdn) end

  ok, val = reaper.GetProjExtState(0, EXT_NS, "bass_pattern_notes")
  if ok and val ~= "" then
    state.bass_pattern_notes = str_to_num_arr(val, 8)
  end

  state.seed_str = tostring(state.seed)
end

load_proj_state()
reaper.atexit(save_proj_state)

-- ----------------------------------------------------------------
--  SEEDED RNG (host orchestration)
--  The pure RNG primitives live in core/rng.lua and are imported at
--  the top of this file. This block only keeps the host-side wrapper
--  that derives the bass stream's seed from `state.seed`.
-- ----------------------------------------------------------------
local function bass_rng_reseed()
  rng_seed(rng.derive_seed(state.seed))
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
-- (bars_to_beats removed — its only caller, build_progression, now lives
--  in core/chord.lua where the multiplication is inlined.)

-- ----------------------------------------------------------------
--  Host-side chord orchestration (pulls chord construction from core/)
-- ----------------------------------------------------------------
local function current_degrees()
  local p = PROGRESSIONS[state.prog_idx]
  return (p.name == "Custom") and state.custom_degrees or p.degrees
end

-- Host wrapper: translates state.* into the host-agnostic params table
-- that core.chord.build_progression expects. Same call-signature as
-- before (zero args) so every caller in host_reaper.lua reads unchanged.
local function build_progression()
  return chord.build_progression {
    mode              = MODE_NAMES[state.mode_idx],
    root_idx          = state.root_idx,
    octave            = state.octave,
    timesig_num       = state.timesig_num,
    degrees           = current_degrees(),
    quality_overrides = state.chord_quality_overrides,
    inversions        = state.chord_inversions,
    bass_overrides    = state.chord_bass_overrides,
    durations         = state.chord_durations,
    smart_voicing     = state.smart_voicing,
  }
end

-- Compute the melody pitch window [lo, hi] (MIDI) for the current
-- block. The anchor depends on mel_anchor_mode; the span is
-- mel_range_down semitones below and mel_range_up above. Clamped to
-- valid MIDI (0..127). chord_root_midi may be nil when not available
-- (e.g. live preview before a chord has been picked); we fall back to
-- the scale-root anchor.
local function mel_window(chord_root_midi)
  local anchor
  local mode = state.mel_anchor_mode or 2
  if mode == 2 and chord_root_midi then
    anchor = chord_root_midi
  elseif mode == 3 then
    anchor = midi_note(state.root_idx, state.octave)
  else
    anchor = midi_note(state.root_idx, state.mel_anchor_oct or 4)
  end
  local lo = anchor - (state.mel_range_down or 7)
  local hi = anchor + (state.mel_range_up   or 14)
  if lo < 0   then lo = 0   end
  if hi > 127 then hi = 127 end
  if hi < lo  then hi = lo  end
  return lo, hi
end

-- Return sorted, deduped MIDI pitches of the current scale that fall
-- inside [lo_p, hi_p].
local function scale_notes_in_range(lo_p, hi_p)
  local mode     = MODE_NAMES[state.mode_idx]
  local ivs      = SCALE_INTERVALS[mode]
  local root_pc  = (state.root_idx - 1) % 12
  local pcs      = {}
  for _, iv in ipairs(ivs) do pcs[(root_pc + iv) % 12] = true end
  local notes    = {}
  for p = lo_p, hi_p do
    if pcs[p % 12] then notes[#notes+1] = p end
  end
  return notes
end

-- (chord_notes_in_range, nearest_idx moved to core/chord.lua)

-- (HARMONIC / VOICE-LEADING HELPERS moved to core/voicing.lua —
--  scale_pc_set / chord_scale_pc_set remain as host wrappers above)

-- ----------------------------------------------------------------
--  PHRASE-ARC / TENSION SCAFFOLDING
--
--  Long-term goal: shape pitch and chord-tone bias across N bars so the
--  melody arcs (low tension at the start, peak in the middle, resolve
--  at the end). It stores the arc on the generation context and exposes
--  a tension(0..1) value at any absolute beat. Generators consult it as
--  a soft bias on chord-tone vs scale-tone selection. Rhythm is *not*
--  affected directly (the DAW owns groove); density is shaped through
--  the same arc so onset clustering follows the tension curve.
--
--  The arc operates at two nested levels:
--    - Cycle-level arch (one peak per progression pass) shapes long form.
--    - Per-phrase sub-arches (~4-bar units) ride on top, blended with a
--      modest weight so each phrase feels like a gesture without
--      drowning out the long-form shape.
--
--  Peak placement and post-peak slope adapt to the progression:
--    - Short progressions use a symmetric peak.
--    - Longer non-cadential progressions use a golden-section peak.
--    - Progressions that end on the tonic (the catalogue's cadential
--      ones) pull the peak slightly earlier, steepen the descent, and
--      floor tension during the resolution chord.
-- ----------------------------------------------------------------

-- Locate the phrase containing within-cycle beat `rel`. Returns the
-- phrase table or nil if no phrases. Past-end falls back to the last
-- phrase so the final onset still has a valid sub-arc anchor.
local function phrase_at(phrases, rel)
  if not phrases or #phrases == 0 then return nil end
  for _, ph in ipairs(phrases) do
    if rel >= ph.abs_start and rel < ph.abs_end then return ph end
  end
  return phrases[#phrases]
end

local function phrase_arc_init(context, total_beats, cycle_offset,
                               progression, phrases)
  -- Re-initialised each cycle so the arc shape repeats per progression
  -- pass; cycle_offset rebases tension calc onto the current cycle.
  --
  -- Cadence detection: the catalogue's cadential presets (perfect,
  -- minor, Phrygian-dom, Andalusian, extended, …) all resolve to the
  -- tonic. `last.degree == 1` is the structural-resolution signal; a V
  -- or IV penultimate further marks a "strong" cadence (V→I, V7→I,
  -- IV→I) that warrants an even steeper descent.
  local n_chords      = progression and #progression or 0
  local last          = progression and progression[n_chords] or nil
  local penult        = (n_chords > 1) and progression[n_chords - 1] or nil
  local cadence_drop  = (last and last.degree == 1) and true or false
  local strong_cadence = cadence_drop and penult
                         and (penult.degree == 5 or penult.degree == 4)
                         and true or false

  -- Peak placement. STARTING POINTS — tune by ear:
  --   short_peak    = 0.50   (≤2 chord progressions, stays symmetric)
  --   golden_peak   = 0.618  (golden section, default for longer)
  --   cadence_peak  = 0.55   (pulled earlier to give the descent room)
  local peak_frac
  if n_chords <= 2 then
    peak_frac = 0.50
  elseif cadence_drop then
    peak_frac = 0.55
  else
    peak_frac = 0.618
  end

  -- Within-cycle beat where the final chord block starts; the cadence
  -- floor in phrase_arc_tension clamps tension below this point.
  local final_block_start_rel = total_beats or 0
  if last and last.duration then
    final_block_start_rel = math.max(0, (total_beats or 0) - last.duration)
  end

  context.phrase_arc = {
    total_beats           = math.max(1, total_beats or 1),
    cycle_offset          = cycle_offset or 0,
    peak_frac             = peak_frac,
    peak_value            = 0.85,   -- max tension
    base_value            = 0.10,   -- tension at start/end
    shape                 = "arch",
    cadence_drop          = cadence_drop,
    strong_cadence        = strong_cadence,
    final_block_start_rel = final_block_start_rel,
    phrases               = phrases,
  }
end

-- Cycle-level arch height (0..1) at relative position rel (in beats
-- from cycle start). Asymmetric peak at pa.peak_frac. Shared by
-- tension and density so they trace the same long-form shape.
local function phrase_arc_cycle_v(pa, rel)
  local t = math.max(0, math.min(1, rel / pa.total_beats))
  if pa.shape ~= "arch" then return 0.5, t end
  local v
  if t < pa.peak_frac then
    v = t / math.max(0.01, pa.peak_frac)
  else
    v = 1.0 - (t - pa.peak_frac) / math.max(0.01, 1.0 - pa.peak_frac)
  end
  return v, t
end

-- Per-phrase sub-arch height (0..1). Symmetric peak at the phrase
-- midpoint; phrase contours already shape pitch height so the sub-arc
-- only drives tension/density. Returns nil when there's a single phrase
-- (the cycle arc already covers it and a redundant sub-arc just
-- amplifies the same shape).
local function phrase_arc_phrase_v(pa, rel)
  if not pa.phrases or #pa.phrases <= 1 then return nil end
  local ph = phrase_at(pa.phrases, rel)
  if not ph then return nil end
  local pdur = math.max(0.001, ph.abs_end - ph.abs_start)
  local pt   = math.max(0, math.min(1, (rel - ph.abs_start) / pdur))
  return math.sin(pt * math.pi)
end

-- Returns 0..1 tension at the given absolute beat. 0 = full repose
-- (chord-tone dominated), 1 = peak tension (more scale tones, larger
-- intervals, leading tones welcome).
local function phrase_arc_tension(context, abs_beat)
  local pa = context.phrase_arc
  if not pa then return 0.0 end
  local rel = abs_beat - (pa.cycle_offset or 0)
  local cycle_v, t = phrase_arc_cycle_v(pa, rel)

  -- Cadence-aware steeper descent: raise the post-peak height to a
  -- power > 1 so the line settles harder into the resolution.
  -- STARTING POINTS — tune by ear:
  --   descent_pow        = 1.5  (plagal / borrowed → I)
  --   strong_descent_pow = 1.8  (V → I, V7 → I, IV → I)
  if pa.cadence_drop and t > pa.peak_frac then
    local pow = pa.strong_cadence and 1.8 or 1.5
    cycle_v = cycle_v ^ pow
  end

  -- Multi-arc nesting: per-phrase sub-arch added on top of the cycle
  -- arch. Additive (not multiplicative) so the long-form shape still
  -- dominates — too strong and you get HVAC-style pumping every 4 bars.
  -- STARTING POINTS — tune by ear:
  --   cycle_weight  = 0.70
  --   phrase_weight = 0.30
  local v = cycle_v
  local phrase_v = phrase_arc_phrase_v(pa, rel)
  if phrase_v then
    v = 0.70 * cycle_v + 0.30 * phrase_v
  end

  -- Cadence floor: during the resolution chord, clamp tension so the
  -- chord-tone landing rule dominates the close regardless of where
  -- the arch happens to sit.
  -- STARTING POINT — tune by ear:
  --   cadence_floor = 0.12
  if pa.cadence_drop and rel >= (pa.final_block_start_rel or pa.total_beats) then
    v = math.min(v, 0.12)
  end

  v = math.max(0, math.min(1, v))
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
  local arch, rel = 0.5, 0
  if pa then
    rel = abs_beat - (pa.cycle_offset or 0)
    arch = phrase_arc_cycle_v(pa, rel)

    -- Per-phrase sub-arch on density — same weighting as tension so the
    -- onset clustering tracks the same gesture per phrase.
    local phrase_v = phrase_arc_phrase_v(pa, rel)
    if phrase_v then
      arch = 0.70 * arch + 0.30 * phrase_v
    end
  end
  -- Amplitude grows with busyness so low values stay flat and high
  -- values swing strongly between trough and crest.
  local amplitude = 0.45 * busy
  local v = busy + amplitude * (arch - 0.5)

  -- Cadence-aware sparsity in the resolution chord: thin the surface so
  -- the landing breathes. Multiplicative so the effect scales with
  -- busyness — barely registers at low busyness, pulls hard at high.
  -- STARTING POINT — tune by ear:
  --   cadence_density_mult = 0.70
  if pa and pa.cadence_drop
     and rel >= (pa.final_block_start_rel or pa.total_beats) then
    v = v * 0.70
  end

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
  -- Cadence drives commitment to harmonic landings. At 0 the line is a
  -- free wander; at 100 every block start and downbeat strongly prefers
  -- a chord tone. Per-position probabilities interpolate from a low floor
  -- (cadence=0) to today's strong defaults (cadence=100).
  local cadence = (state.mel_cadence or 60) / 100.0
  local p = 0
  if is_block_start         then p = math.max(p, 0.20 + 0.75 * cadence) end
  if metric_weight >= 0.95  then p = math.max(p, 0.10 + 0.75 * cadence) end -- downbeat
  if metric_weight >= 0.55  then p = math.max(p, 0.05 + 0.50 * cadence) end -- mid-bar
  if metric_weight >= 0.30  then p = math.max(p,        0.30 * cadence) end -- whole beat
  -- Tension still relaxes the rule by up to ~40% so the arc can climb away.
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
  local space   = (state.mel_space or 0) / 100.0
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

    -- Space gate: pin onsets to quarter-note boundaries. Sub-beat slots
    -- are rejected with probability proportional to space, independent of
    -- metre. At space=1 every onset lands on a beat; at space=0, no-op.
    if include and space > 0 then
      local abs_beat  = (abs_start_slot + s) * grid
      local beat_frac = abs_beat - math.floor(abs_beat)
      local on_beat   = beat_frac < 0.01 or (1.0 - beat_frac) < 0.01
      if not on_beat and rng_float() < space then
        include = false
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
  local rrig   = (state.mel_rhythm_rigidity or 0) / 100.0
  local abs_onset_beat = (abs_start_slot + onset_slot) * grid

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
    -- Rhythmic rigidity: a duration of d_beats "fits" this onset when the
    -- onset sits on the d_beats grid (e.g. an 1/8 starting on an 1/8). Boost
    -- aligned durations and demote unaligned ones, scaled by the slider.
    if rrig > 0 then
      local d_beats = valid[i] * grid
      local q       = abs_onset_beat / d_beats
      local frac    = q - math.floor(q)
      local aligned = frac < 0.005 or (1.0 - frac) < 0.005
      if aligned then
        w = w * (1.0 + rrig * 3.0)
      else
        w = w * math.max(0.02, 1.0 - rrig * 0.95)
      end
    end
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

-- ============================================================
--  PHRASE PLANNER / SKELETON / SURFACE WALKER
--
--  Shared melody infrastructure consumed by the strategy generators.
--  The flow is:
--
--    plan_phrases   → groups the progression into musical phrases,
--                     each with a contour shape (arch / descend /
--                     ascend / valley, cycled across phrases).
--    build_skeleton → picks one structural tone per chord block,
--                     voice-led across the phrase and shaped by the
--                     contour. This is the line's spine; first onset
--                     of every block lands on it.
--    surface_step   → walks one onset toward the next structural tone,
--                     with target-aware approach figures (leading
--                     tone, scale step) on the final onset before a
--                     chord-change landing.
--
--  Strength scales with state.mel_cadence (0 = free wander, 100 =
--  textbook cadences). Random choices flow through rng_float() to
--  preserve the seed contract.
-- ============================================================

-- 1. PHRASE PLANNER ──────────────────────────────────────────────
-- Group the progression into ~4-bar phrases (absorbing any remainder
-- into the final phrase). Each phrase carries a contour shape used by
-- skeleton selection. The contour cycle is shuffled deterministically
-- from state.seed so phrase 1 isn't always an "arch" (which made the
-- middle of every short progression peak high in the same way). Same
-- seed → same shuffle → same line.
local PHRASE_CONTOURS = {"arch", "descend", "ascend", "valley"}

-- Deterministic shuffle driven by state.seed via a local LCG, so we
-- don't perturb the global math.random stream the rest of the melody
-- pipeline is consuming.
local function shuffled_contours()
  local out = { table.unpack(PHRASE_CONTOURS) }
  local s = ((state.seed or 0) * 2654435761 + 2246822519) % 2^31
  for i = #out, 2, -1 do
    s = (s * 1103515245 + 12345) % 2^31
    local j = (s % i) + 1
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function plan_phrases(progression, bar_beats)
  local target_phrase_beats = 4 * (bar_beats or state.timesig_num)
  local contours = shuffled_contours()
  local phrases = {}
  local cur = { start_block = 1, end_block = 0, beats = 0 }
  for i, ch in ipairs(progression) do
    cur.beats     = cur.beats + ch.duration
    cur.end_block = i
    if cur.beats >= target_phrase_beats - 0.001 then
      cur.contour = contours[((#phrases) % #contours) + 1]
      phrases[#phrases+1] = cur
      cur = { start_block = i+1, end_block = 0, beats = 0 }
    end
  end
  if cur.start_block <= #progression then
    cur.end_block = #progression
    cur.contour   = contours[((#phrases) % #contours) + 1]
    phrases[#phrases+1] = cur
  end
  -- Fill in absolute beat positions.
  local abs = 0
  for _, ph in ipairs(phrases) do
    ph.abs_start = abs
    for j = ph.start_block, ph.end_block do
      abs = abs + progression[j].duration
    end
    ph.abs_end = abs
  end
  return phrases
end

-- Phrase contour height at relative position t∈[0,1]. 0 = low, 1 = high.
local function contour_height(contour, t)
  if contour == "arch"    then return math.sin(t * math.pi) end
  if contour == "valley"  then return 1 - math.sin(t * math.pi) end
  if contour == "ascend"  then return t end
  if contour == "descend" then return 1 - t end
  return 0.5
end

-- 2. SKELETON BUILDER ────────────────────────────────────────────
-- One structural tone per chord block, voice-led across the whole
-- progression and shaped by each phrase's contour. Returns an array
-- indexed by block_idx.
local function build_skeleton(progression, phrases, prev_skeleton_pitch)
  local skeleton = {}
  local prev = prev_skeleton_pitch
  for _, ph in ipairs(phrases) do
    local n_blocks = ph.end_block - ph.start_block + 1
    for offs = 0, n_blocks - 1 do
      local bi          = ph.start_block + offs
      local ch          = progression[bi]
      local lo_p, hi_p  = mel_window(ch.root_midi)
      local chord_range = chord_notes_in_range(ch.notes, lo_p, hi_p)
      if #chord_range == 0 then
        skeleton[bi] = prev or 60
      else
        local t        = (n_blocks > 1) and (offs / (n_blocks - 1)) or 0.5
        local h        = contour_height(ph.contour, t)
        local lo, hi   = chord_range[1], chord_range[#chord_range]
        local height_p = lo + h * (hi - lo)
        local pick     = nearest_chord_tone(height_p, chord_range)
        if prev then
          -- Blend voice-leading distance with contour height. The
          -- weights slide with contour strength: at a contour extreme
          -- (top of an arch, bottom of a valley) the height target
          -- pulls hard, so the spine actually traverses the available
          -- mel-oct range; near the contour midpoint voice-leading
          -- wins, keeping the line singable. Without this slide the
          -- old fixed weighting (lead 1.0, height 0.5) trapped the
          -- skeleton near prev no matter how wide the octave range.
          local contour_strength = math.abs(h - 0.5) * 2  -- 0..1
          local lead_w   = 1.0 - 0.7 * contour_strength
          local height_w = 0.3 + 0.7 * contour_strength
          local best, best_score = pick, math.huge
          for _, n in ipairs(chord_range) do
            local lead_d   = math.abs(n - prev)
            local height_d = math.abs(n - height_p)
            local score    = lead_d * lead_w + height_d * height_w
            if score < best_score then best, best_score = n, score end
          end
          pick = best
        end
        skeleton[bi] = pick
        prev = pick
      end
    end
  end
  return skeleton
end

-- 3. SURFACE WALKER ──────────────────────────────────────────────
-- Walk one onset from prev_pitch toward target_pitch. Stepwise by
-- default. On the *final* onset before a chord-change landing an
-- idiomatic figure (leading tone, scale-step from above/below) takes
-- over with strength scaled by cadence and amplified at phrase ends.
--
--   is_final_onset = the next onset will be on the new chord (target)
--   is_phrase_end  = that next onset is also the start of a new phrase
local function surface_step(prev_pitch, target_pitch, scale_notes,
                            is_final_onset, is_phrase_end, ctx)
  local cadence = (state.mel_cadence or 60) / 100.0
  if #scale_notes == 0 then return prev_pitch end

  -- Leap recovery: if the previous onset took a consonant leap, this
  -- onset balances it with a diatonic step in the opposite direction
  -- (the classical leap-then-step rule that keeps wide intervals from
  -- sounding jarring). Recovery is forced even on a final-onset slot
  -- since the leap that caused it was itself non-final.
  if ctx and ctx.leap_recover_dir then
    local rdir = ctx.leap_recover_dir
    ctx.leap_recover_dir = nil
    return diatonic_step(scale_notes, prev_pitch, rdir)
  end

  -- Consonant leap: small chance, only on non-final onsets so it
  -- doesn't fight the cadence approach figure. Jumps to a chord tone
  -- a 4th–6th away from prev in the contour direction; the next
  -- onset will step back via the recovery branch above. This is the
  -- only path through which the surface line can traverse register
  -- — without it the walker is bounded to ±3 scale steps per onset.
  if not is_final_onset and ctx and ctx.chord_range
     and #ctx.chord_range > 0 and rng_float() < 0.10 then
    local dir
    if target_pitch and target_pitch ~= prev_pitch then
      dir = (target_pitch > prev_pitch) and 1 or -1
    else
      dir = (rng_float() < 0.5) and 1 or -1
    end
    local candidates = {}
    for _, n in ipairs(ctx.chord_range) do
      local d = (n - prev_pitch) * dir
      if d >= 5 and d <= 9 then candidates[#candidates+1] = n end
    end
    if #candidates > 0 then
      local leap = candidates[rng_int(1, #candidates)]
      ctx.leap_recover_dir = -dir
      return leap
    end
  end

  if is_final_onset and target_pitch then
    local approach_prob = is_phrase_end and (0.4 + 0.6 * cadence)
                                        or (0.2 + 0.5 * cadence)
    if rng_float() < approach_prob then
      local up   = diatonic_step(scale_notes, target_pitch, 1)
      local down = diatonic_step(scale_notes, target_pitch, -1)
      -- Semitone leading-tone only when that pitch is actually in the scale
      -- (e.g. B→C in C major). Blind target-1 produces out-of-key notes
      -- on every other scale degree, so we gate it here.
      if is_phrase_end and cadence > 0.5
         and rng_float() < (cadence - 0.3) then
        local lt = target_pitch - 1
        local lt_in_scale = false
        for _, n in ipairs(scale_notes) do
          if n % 12 == lt % 12 then lt_in_scale = true; break end
        end
        if lt_in_scale then return lt end
        -- Not in scale: fall through to diatonic step below.
      end
      -- Diatonic step from whichever side is closer to prev.
      if math.abs(up - prev_pitch) <= math.abs(down - prev_pitch) then
        return up
      else
        return down
      end
    end
    -- Approach declined: fall through to general walk biased at target.
  end

  -- General walk: aim toward the target with mostly stepwise motion.
  local idx_prev = nearest_idx(scale_notes, prev_pitch)
  local idx_targ = target_pitch and nearest_idx(scale_notes, target_pitch) or idx_prev
  local dir
  if idx_targ == idx_prev then
    dir = (rng_float() < 0.5) and 1 or -1   -- neighbour figure
  else
    dir = (idx_targ > idx_prev) and 1 or -1
  end
  -- Step size: mostly 1, occasional 2 (third), very occasional 3.
  local r = rng_float()
  local step = (r < 0.75) and 1 or (r < 0.95) and 2 or 3
  -- Small chance of reverse step for a passing/neighbour shape.
  if rng_float() < 0.15 then dir = -dir end
  local idx = math.max(1, math.min(#scale_notes, idx_prev + dir * step))
  return scale_notes[idx]
end

-- 4. CADENCE → INTERNAL PARAMS ──────────────────────────────────
-- Several engine-internal helpers (build_onset_candidates,
-- pick_dur_slots, maybe_insert_colour) still read mel_metre and
-- mel_colour as scalars. Derive both from the single Cadence knob each
-- generation pass: cadence drives strong-beat preference (mel_metre)
-- and chromatic embellishment density (mel_colour) in lock-step, so
-- the UI keeps a single coherent musical control.
local function apply_cadence_to_legacy()
  local c = (state.mel_cadence or 60) / 100.0
  state.mel_metre  = math.floor(c * 80)
  state.mel_colour = math.floor(c * 70)
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

-- Bluesy phrasing helper: given a target chord-tone target_pc, return the
-- blue note that idiomatically slides into it (b3→3, b7→1, b5→5/4) at
-- the pitch closest to to_pitch. Returns nil if the target isn't one of
-- the blues bend targets, or if the resulting pitch would be too far from
-- from_pitch to read as an embellishment.
local function bluesy_blue_note(from_pitch, to_pitch, chord_root_pc)
  if not chord_root_pc then return nil end
  local r       = chord_root_pc
  local target  = to_pitch % 12
  local maj3_pc = (r + 4)  % 12
  local p4_pc   = (r + 5)  % 12
  local p5_pc   = (r + 7)  % 12
  local root_pc = r

  local blue_pc
  if     target == maj3_pc                  then blue_pc = (r + 3)  % 12  -- b3 → 3
  elseif target == root_pc                  then blue_pc = (r + 10) % 12  -- b7 → 1
  elseif target == p5_pc or target == p4_pc then blue_pc = (r + 6)  % 12  -- b5 → 5/4
  else return nil end

  -- Snap blue_pc to the pitch closest to to_pitch (so the slide is
  -- adjacent, not an octave displaced).
  local diff = (blue_pc - (to_pitch % 12)) % 12
  if diff > 6 then diff = diff - 12 end
  local blue = to_pitch + diff
  if math.abs(blue - from_pitch) > 5 then return nil end
  return blue
end

local function maybe_insert_colour(from_pitch, to_pitch, scale_notes,
                                    scale_pcs, chord_pcs, target_is_strong,
                                    chord_root_pc)
  -- Bluesy phrasing fires its own bend regardless of mel_colour: the blue
  -- note IS the phrasing identity, not a density-controlled embellishment.
  if (state.mel_phrasing_idx or 1) == 2 and chord_root_pc
     and rng_float() < 0.55 then
    local blue = bluesy_blue_note(from_pitch, to_pitch, chord_root_pc)
    if blue then return blue end
  end

  if state.mel_colour == 0 then return nil end
  local colour_prob = state.mel_colour / 100.0
  if rng_float() > colour_prob then return nil end

  local diff = to_pitch - from_pitch

  -- 1. Leading-tone approach into a chord tone on a strong position.
  -- Only when target - 1 is actually a scale degree (e.g. B→C in major);
  -- a blind semitone-below produces out-of-key notes on most scale degrees.
  if target_is_strong and is_chord_tone(to_pitch, chord_pcs) then
    if math.abs(diff) <= 4 and rng_float() < 0.5 then
      local lt = leading_tone_to(to_pitch)
      if scale_pcs[lt % 12] and math.abs(lt - from_pitch) <= 5 then return lt end
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

  -- 3. Diatonic passing tone when notes are a whole step apart.
  -- (A chromatic semitone between diatonic whole-step pairs is always
  -- out of key, so we use a diatonic step toward the target instead.)
  if math.abs(diff) == 2 then
    local passing = diatonic_step(scale_notes, from_pitch, diff > 0 and 1 or -1)
    if passing ~= from_pitch and passing ~= to_pitch then return passing end
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
--   ctx.is_block_start_slot       true on the very first onset of the block
--   ctx.is_final_onset_of_block   true if the next onset will land on the
--                                 next chord (i.e. this is the last note
--                                 inside the current chord block)
--   ctx.metric_weight_here        0..1 metrical weight at this onset
--   ctx.land_chord_tone_p         0..1 desired chord-tone landing probability
--   ctx.tension_here              0..1 phrase-arc tension at this onset
--   ctx.scale_pcs / chord_pcs     pitch-class sets (cached for convenience)
--
-- Context keys set per block (by build_melody_cycle, before this is called):
--   ctx.block_skeleton    structural pitch this block must land on (chord tone)
--   ctx.next_skeleton     structural pitch the next block will land on
--   ctx.is_phrase_end     true if the next block starts a new phrase
local function mel_fill_block(block_dur, chord_notes, scale_notes, chord_range,
                               pitch_fn, context)
  local grid      = mel_min_beats()
  local abs_start = context.abs_block_start or 0

  -- Convert everything to integer slots
  local abs_start_slot = math.floor(abs_start / grid + 0.5)
  local block_slots    = math.floor(block_dur  / grid + 0.5)
  local min_slots      = 1  -- 1 grid step = min duration by definition
  local max_slots      = math.floor(mel_max_beats() / grid + 0.5)

  -- Cache PC sets for the duration of this block. The melody cycle
  -- passes in a chord-aware scale pc set via context.scale_pcs_chord
  -- (chord tones merged with the global mode, 3rd/7th conflicts
  -- resolved in favour of the chord). Fall back to the raw global
  -- mode if no caller has provided one (e.g., future direct callers).
  local scale_pcs = context.scale_pcs_chord or scale_pc_set()
  local chord_pcs = chord_pc_set(chord_notes)
  context.scale_pcs   = scale_pcs
  context.chord_pcs   = chord_pcs
  context.chord_range = chord_range

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

    -- Walker context: this onset is the *last* one inside the block if
    -- placing it now exhausts the remaining slots. Generators consult
    -- this when choosing a final-approach figure toward next_skeleton.
    context.is_final_onset_of_block = (slot + dur_slots >= block_slots)

    -- Rest probability — derived from busyness via the phrase-arc density
    -- envelope. Sparse settings rest more (and only between phrases);
    -- dense settings rest rarely. Block-start is never a rest (we want
    -- the chord to be defined on attack), and strong beats rest less.
    -- Strategies whose rhythm is structural (Motif's cell, C&R's replay)
    -- set context.rest_soften to dampen busyness's pull on the rest gate
    -- so their patterns survive sparse settings.
    local density = phrase_arc_density(context, abs_beat)
    local soft = context.rest_soften or 1.0
    local rest_p = (1.0 - density) * 35.0 * soft
    -- Space adds an independent baseline rest probability orthogonal to
    -- busyness's arc. Strong beats stay less rest-prone (mw scaling), but
    -- at high space even mid-bar beats inside a block can rest, opening
    -- up the whitespace busyness alone can't reach.
    local space = (state.mel_space or 0) / 100.0
    rest_p = rest_p + space * 75.0 * (1.0 - 0.5 * mw)
    if first_onset    then rest_p = 0 end
    if mw >= 0.95     then rest_p = rest_p * 0.25 end

    if rng_float() * 100 < rest_p then
      slot = slot + dur_slots
    else
      local pos_beats = slot * grid
      -- Expose the metric-grid duration to pitch_fn so strategies (C&R)
      -- can record rhythm and replay it later.
      context.current_dur_slots = dur_slots
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

        -- First onset of every block lands on the structural skeleton
        -- pitch — voice-led across the whole progression by build_skeleton.
        -- Generators may opt out by returning a chord tone close to the
        -- skeleton themselves; otherwise the skeleton wins. Strategies
        -- can lower context.snap_block_start (probability 0..1) when the
        -- preset's identity depends on its OWN first note (Pedal Point's
        -- pedal, Mechanical at low cadence).
        local snap_p = context.snap_block_start
        if snap_p == nil then snap_p = 1.0 end
        if first_onset and context.block_skeleton and snap_p > 0
           and (snap_p >= 1.0 or rng_float() < snap_p) then
          local sk = context.block_skeleton
          if not is_chord_tone(pitch, chord_pcs) or math.abs(pitch - sk) > 4 then
            pitch = sk
          end
        end

        -- Chord-tone landing enforcement on strong beats inside the block:
        -- with probability landing_p (cadence-driven), snap a non-chord
        -- result to the nearest chord tone. Strategies can reduce the
        -- pull via context.chord_landing_strength (0..1). Altered chords
        -- (secondary dominants, modal-mixture, anything whose pcs differ
        -- from the global key) get a stronger pull: the chord-aware scale
        -- already steers the walker, but on jazz/fusion changes a firmer
        -- landing on strong beats is the difference between "knows the
        -- changes" and "fights the changes".
        local landing_scale = context.chord_landing_strength or 1.0
        if context.chord_is_altered then
          landing_scale = math.min(1.0, landing_scale * 1.4)
        end
        if not first_onset and landing_p > 0 and landing_scale > 0
           and not is_chord_tone(pitch, chord_pcs)
           and rng_float() < landing_p * landing_scale then
          pitch = nearest_chord_tone(pitch, chord_range)
        end

        local clamp_lo = context.mel_lo_p or 0
        local clamp_hi = context.mel_hi_p or 127
        pitch = math.max(clamp_lo, math.min(clamp_hi, pitch))

        -- Colour tone (passing/neighbour/leading-tone). Only when there's
        -- room and we're not at the very first onset (would obscure the
        -- chord-tone landing). Strategies whose voice is intentionally
        -- bare (Pedal Point) can disable via context.colour_enabled.
        local colour_enabled = context.colour_enabled
        if colour_enabled == nil then colour_enabled = true end
        local target_is_strong = mw >= 0.55 or first_onset
        local colour = nil
        if colour_enabled and not first_onset and dur_slots > min_slots then
          colour = maybe_insert_colour(prev, pitch, scale_notes,
                                       scale_pcs, chord_pcs, target_is_strong,
                                       context.chord_root_pc)
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

-- ============================================================
--  STRATEGY GENERATORS
--
--  Each preset is a thin pitch_fn on top of mel_fill_block + the
--  shared planner / skeleton / surface walker. The strategies set
--  context flags (snap_block_start, chord_landing_strength,
--  colour_enabled, rest_soften) to shape how aggressively the
--  shared safety rails apply, so each voice can keep its identity.
--
--  Identity per preset:
--
--    Free         – wandering line; surface walker aims at the next
--                   skeleton; at high cadence, occasionally rests on
--                   the final onset of a phrase-end block (the breath
--                   that used to be the separate "Phrase" preset).
--    Motif        – develops a 3–5 note cell with its own rhythm;
--                   diatonically transposed each block; periodic
--                   inversion / retrograde. The cell's last note is
--                   *bent* toward the next skeleton at high cadence
--                   instead of being replaced — preserves identity.
--    Mechanical   – fixed-interval alternation. Block-start snap and
--                   strong-beat chord-tone landing scale with cadence,
--                   so at low cadence the pattern grinds against the
--                   harmony (Reichian) and at high cadence it complies.
--    Pedal Point  – locks onto the tonic in-range; off-pedal notes are
--                   neighbours when the chord harmonises the pedal,
--                   resolutions to a chord tone when it doesn't.
--                   Bare (no colour tones); busyness drives departures.
--    Call&Response– alternating phrase pairs (adaptive: block pairs on
--                   short progressions). The call is generated freely
--                   and recorded as scale-step offsets + rhythm; the
--                   response replays it anchored to its own block's
--                   skeleton, with busyness-scaled displacements and a
--                   cadential pull toward next_skeleton on the final
--                   onset.
-- ============================================================

-- ── 1. FREE ────────────────────────────────────────────────────
-- Wandering line. The phrase-end breath that used to live in a separate
-- "Phrase" preset is folded in here, gated by cadence: at low cadence
-- there is no breath (the old Free behaviour); as cadence rises the
-- chance of a final-onset rest at a phrase end grows, capped well below
-- certainty so it punctuates rather than dominates.
local function mel_strat_free(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    if c.is_block_start_slot then return c.block_skeleton or prev end
    if c.is_final_onset_of_block and c.is_phrase_end then
      local cadence = (state.mel_cadence or 60) / 100.0
      if cadence > 0.5 and rng_float() < (cadence - 0.5) * 0.8 then
        return nil   -- rest
      end
    end
    return surface_step(prev, c.next_skeleton, sn,
                        c.is_final_onset_of_block, c.is_phrase_end, c)
  end
  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 2. MOTIF ───────────────────────────────────────────────────
-- A short cell (3–5 notes) with its own rhythm and a singable interval
-- profile. On every chord change the cell is diatonically transposed so
-- its first note lands on the skeleton pitch of the new chord — the
-- shared infrastructure already guarantees that lands at block start;
-- here we just make the rest of the cell follow. Periodic variation:
-- inversion, retrograde. The cell's last note is bent (not replaced)
-- toward next_skeleton at high cadence so the motivic identity survives
-- chord changes.
local function mel_strat_motif(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  -- The cell IS the voice — protect it from the shared safety rails.
  ctx_tbl.rest_soften             = 0.5
  ctx_tbl.chord_landing_strength  = 0.5

  local grid       = mel_min_beats()
  local min_slots  = 1
  local max_slots  = math.floor(mel_max_beats() / grid + 0.5)

  -- Build the seed cell once per progression.
  if not ctx_tbl.motif_cell then
    local cell_len      = rng_int(3, 5)
    local cell          = {}
    local interval_pool = { -2, -1, -1, -1, 0, 1, 1, 1, 2 }  -- mostly steps
    local one_beat_slots = math.max(min_slots, math.floor(1.0 / grid + 0.5))
    local rhythm_pool    = { 1, 1, 2, 2, one_beat_slots,
                             math.max(1, math.floor(one_beat_slots / 2)) }
    -- Filter rhythm_pool to valid range
    local rh = {}
    for _, v in ipairs(rhythm_pool) do
      if v >= min_slots and v <= max_slots then rh[#rh+1] = v end
    end
    if #rh == 0 then rh = { min_slots } end
    -- Cell stored as scale-step offsets from its first note + dur in slots.
    local idx_off = 0
    cell[1] = { idx_offset = 0, dur_slots = rh[rng_int(1, #rh)] }
    for i = 2, cell_len do
      idx_off = idx_off + interval_pool[rng_int(1, #interval_pool)]
      cell[i] = { idx_offset = idx_off, dur_slots = rh[rng_int(1, #rh)] }
    end
    ctx_tbl.motif_cell    = cell
    ctx_tbl.motif_ci      = 1
    ctx_tbl.motif_block_n = 0
    ctx_tbl.motif_invert  = false
    ctx_tbl.motif_retro   = false
  end

  -- Per chord-block: reset cursor, recompute the block's anchor index
  -- (the scale-step idx of the skeleton pitch).
  if ctx_tbl.motif_block_for ~= ctx_tbl.abs_block_start then
    ctx_tbl.motif_ci        = 1
    ctx_tbl.motif_block_for = ctx_tbl.abs_block_start
    ctx_tbl.motif_anchor_idx = nearest_idx(scale_notes,
      ctx_tbl.block_skeleton or scale_notes[math.ceil(#scale_notes/2)])
    ctx_tbl.motif_block_n   = (ctx_tbl.motif_block_n or 0) + 1
    -- Light variation every 4 blocks: invert intervals OR retrograde.
    if ctx_tbl.motif_block_n % 4 == 0 then
      if rng_float() < 0.5 then
        ctx_tbl.motif_invert = not ctx_tbl.motif_invert
      else
        ctx_tbl.motif_retro = not ctx_tbl.motif_retro
      end
    end
  end

  local cell = ctx_tbl.motif_cell
  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    local ci  = c.motif_ci or 1
    local len = #cell
    local read_i = c.motif_retro and (len - ci + 1) or ci
    local entry  = cell[read_i]
    local off    = entry.idx_offset
    if c.motif_invert then off = -off end
    local anchor    = c.motif_anchor_idx or nearest_idx(sn, prev)
    local natural_i = math.max(1, math.min(#sn, anchor + off))
    local idx       = natural_i

    -- Cadential bend: at high cadence, pull the very last cell note
    -- toward next_skeleton by up to ±2 scale steps — *preserving the
    -- cell's rhythm* — instead of overwriting it with surface_step.
    -- The motif keeps its profile; only the final interval bends.
    if c.is_final_onset_of_block and c.is_phrase_end and c.next_skeleton then
      local cadence = (state.mel_cadence or 60) / 100.0
      if cadence > 0.5 then
        local target_i = nearest_idx(sn, c.next_skeleton)
        local strength = (cadence - 0.5) * 2.0   -- 0..1
        local bend     = math.floor((target_i - natural_i) * strength + 0.5)
        if bend >  2 then bend =  2 end
        if bend < -2 then bend = -2 end
        idx = math.max(1, math.min(#sn, natural_i + bend))
      end
    end

    c.motif_ci = (ci % len) + 1
    return { pitch = sn[idx], dur_slots = entry.dur_slots }
  end

  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 3. MECHANICAL ──────────────────────────────────────────────
-- Strict alternating ±N scale-step pattern (interval seed-chosen,
-- seed-stable). Cadence is wired to "Compliance" here: at low cadence
-- the block-start skeleton snap and strong-beat chord-tone landing are
-- mostly off, so the alternation grinds against the harmony (Reichian);
-- at high cadence the pattern complies with the chord changes.
local function mel_strat_mechanical(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  if not ctx_tbl.mech_interval then
    local intervals = {2, 3, 4, 5}
    ctx_tbl.mech_interval  = intervals[rng_int(1, #intervals)]
    ctx_tbl.mech_direction = 1
  end
  local cadence = (state.mel_cadence or 60) / 100.0
  -- Block-start snap: probabilistic in cadence. At cadence=0 the pattern
  -- never bends to the new chord on attack; at cadence=1 it always does.
  ctx_tbl.snap_block_start        = cadence
  -- Strong-beat chord-tone landing: floor of 0.2 (some gravity always
  -- pulls back), rising linearly to full strength at cadence=1.
  ctx_tbl.chord_landing_strength  = 0.2 + 0.8 * cadence

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    -- Block-start: only emit the skeleton when snap_block_start fires
    -- as a hard floor; otherwise let the alternation keep walking. The
    -- shared snap (mel_fill_block) will probabilistically pull this
    -- back to the skeleton based on context.snap_block_start.
    if c.is_block_start_slot then
      if rng_float() < cadence then return c.block_skeleton or prev end
      -- fall through to alternation
    end
    -- Cadence-softened final approach into the next chord — kept,
    -- because this is the audible cadence figure even at mid cadence.
    if c.is_final_onset_of_block and c.next_skeleton then
      if rng_float() < cadence then
        return surface_step(prev, c.next_skeleton, sn, true, c.is_phrase_end, c)
      end
    end
    local idx  = nearest_idx(sn, prev)
    local step = c.mech_interval * c.mech_direction
    local new_idx = idx + step
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

-- ── 4. PEDAL POINT ─────────────────────────────────────────────
-- Locks onto the mode's tonic, placed inside the chord range. Off-pedal
-- onsets draw from a weighted palette around the pedal: diatonic
-- neighbours (heavy weight) plus nearby chord tones within a perfect
-- fifth (lighter weight, boosted on strong beats and on dissonant
-- blocks where the line wants to resolve). Busyness drives the rate of
-- departure; space drives rests (via the shared rest gate). Block-start
-- is the pedal itself — we explicitly opt out of the shared skeleton
-- snap. Colour tones are off so the texture stays austere. The pedal
-- itself can lift an octave on weak beats with low probability, so the
-- anchor breathes without losing its identity.
local function mel_strat_pedal_point(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  ctx_tbl.snap_block_start       = 0     -- pedal IS the block start
  ctx_tbl.chord_landing_strength = 0.2   -- let the pedal clash if it must
  ctx_tbl.colour_enabled         = false -- austere by design

  -- Pedal pitch class: tonic of the current mode/root. Ignores chord
  -- inversions on purpose — the pedal is anchored; the harmony moves
  -- around it.
  local pedal_pc = (state.root_idx - 1) % 12

  -- Pick a pedal pitch inside the melody range, near the centre of the
  -- chord's voicing on the FIRST block (so the pedal sits "inside the
  -- chord"). After that first selection, freeze it for the whole render
  -- so the pedal doesn't bounce octaves block-by-block.
  local lo_p = ctx_tbl.mel_lo_p or 0
  local hi_p = ctx_tbl.mel_hi_p or 127
  if not ctx_tbl.pedal_pitch then
    local target
    if #chord_range > 0 then
      target = (chord_range[1] + chord_range[#chord_range]) / 2
    else
      target = (lo_p + hi_p) / 2
    end
    local best, best_d = nil, math.huge
    for p = lo_p, hi_p do
      if p % 12 == pedal_pc then
        local d = math.abs(p - target)
        if d < best_d then best, best_d = p, d end
      end
    end
    ctx_tbl.pedal_pitch = best or scale_notes[math.ceil(#scale_notes/2)] or 60
  end
  local pedal = ctx_tbl.pedal_pitch

  -- Is the pedal a chord tone of the current block? Drives off-pedal
  -- behaviour (neighbour-decoration vs. resolution-toward-chord-tone).
  local pedal_in_chord = false
  for _, n in ipairs(chord_notes) do
    if n % 12 == pedal_pc then pedal_in_chord = true; break end
  end

  -- Override the block_skeleton so the structural-skeleton machinery
  -- aims at the pedal too. (Defensive: snap_block_start = 0 already
  -- suppresses the snap, but next_skeleton is also consumed by the
  -- shared cadence figure that we deliberately don't use here.)
  ctx_tbl.block_skeleton = pedal

  local busy = (state.mel_busyness or 50) / 100.0

  -- Build a weighted off-pedal candidate set. Anchored to the pedal
  -- (the home decoration is its diatonic neighbours) but, when the line
  -- is already off the pedal, also proposes diatonic continuations from
  -- `prev_pitch` — one step further out (extends the figure into a
  -- passing-tone run) and one step back in (resolution). Without this,
  -- every departure is a single-step neighbour that immediately snaps
  -- back; with it, the line forms little turns and runs that breathe.
  -- Window around the pedal stays a perfect fifth (octave variation of
  -- the pedal itself is handled by the weak-beat octave lift below).
  local function build_candidates(sn, cr, strong, prev_pitch)
    local cands = {}
    local up = diatonic_step(sn, pedal,  1)
    local dn = diatonic_step(sn, pedal, -1)
    -- Neighbours of the pedal: the home decoration. Lighter than before
    -- so chord tones and continuation steps can compete; lighter still
    -- on strong beats so downbeat departures reach the harmony.
    local neigh_w = strong and 1.3 or 2.0
    if up and up ~= pedal then cands[#cands+1] = {p=up, w=neigh_w} end
    if dn and dn ~= pedal then cands[#cands+1] = {p=dn, w=neigh_w} end

    -- Continuation from prev: only when we're already off the pedal.
    -- Outward = same direction as the current departure (the line keeps
    -- moving away); inward = step back toward the pedal (the figure
    -- resolves). Both candidates skip the pedal itself so "return to
    -- pedal" remains the depart_p gate's job, not a duplicate here.
    if prev_pitch and (prev_pitch % 12) ~= pedal_pc then
      local diff    = prev_pitch - pedal
      local out_dir = (diff > 0) and 1 or -1
      local outward = diatonic_step(sn, prev_pitch,  out_dir)
      local inward  = diatonic_step(sn, prev_pitch, -out_dir)
      if outward and (outward % 12) ~= pedal_pc and math.abs(outward - pedal) <= 7 then
        cands[#cands+1] = {p=outward, w = strong and 1.1 or 1.8}
      end
      if inward and (inward % 12) ~= pedal_pc then
        cands[#cands+1] = {p=inward, w = strong and 1.6 or 1.3}
      end
    end

    if cr and #cr > 0 then
      -- Chord-tone weight: low on consonant blocks (the line is mostly
      -- decoration), high on dissonant blocks (the line is resolving).
      -- Busyness lifts both — more activity, more decoration. Raised
      -- vs. the neighbours so departures actually reach 3rds/5ths.
      local ct_base = pedal_in_chord and (0.7 + 1.1 * busy)
                                     or  (1.9 + 0.7 * busy)
      for _, n in ipairs(cr) do
        local d = math.abs(n - pedal)
        if d > 0 and d <= 7 then
          local w = ct_base * (1.0 - (d - 1) / 9.0)   -- closer = heavier
          if d <= 2 then w = w * 1.4 end              -- stepwise bonus
          if strong then w = w * 1.5 end              -- strong beats prefer chord tones
          if w > 0 then cands[#cands+1] = {p=n, w=w} end
        end
      end
    end
    return cands
  end

  local function weighted_pick(cands)
    if #cands == 0 then return nil end
    local total = 0
    for _, c in ipairs(cands) do total = total + c.w end
    if total <= 0 then return cands[rng_int(1, #cands)].p end
    local r = rng_float() * total
    for _, c in ipairs(cands) do
      r = r - c.w
      if r <= 0 then return c.p end
    end
    return cands[#cands].p
  end

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    if c.is_block_start_slot then return pedal end

    local mw = c.metric_weight_here or 0

    -- Probability of departing from the pedal on this onset. On
    -- consonant blocks the pedal sustains freely (block-start is
    -- already forced to the pedal — that's the gravitational anchor);
    -- on dissonant blocks the line resolves more often. Busyness
    -- pushes both. A line already off the pedal stays off more
    -- readily — the decoration figure isn't done after one note.
    local off_pedal = (prev % 12) ~= pedal_pc
    local depart_p = pedal_in_chord and (0.25 + 0.55 * busy)
                                    or  (0.55 + 0.45 * busy)
    if off_pedal then depart_p = depart_p + 0.20 end
    -- Strong beats still favour the pedal but not so hard that
    -- downbeats become a pedal-only event.
    if mw >= 0.95 then depart_p = depart_p * 0.7 end

    if rng_float() > depart_p then
      -- Hold / return to the pedal — but on a weak beat, occasionally
      -- lift it an octave so the anchor breathes across registers
      -- without losing its identity.
      local p = pedal
      if mw < 0.6 and rng_float() < 0.08 then
        local cand = p + ((rng_float() < 0.5) and 12 or -12)
        if cand >= lo_p and cand <= hi_p then p = cand end
      end
      return p
    end

    local strong = mw >= 0.75
    local cands  = build_candidates(sn, c.chord_range, strong, prev)
    local pick   = weighted_pick(cands)
    if pick then return pick end

    -- Fallbacks mirror the original behaviour when the palette is empty.
    if pedal_in_chord then
      local dir = (rng_float() < 0.5) and 1 or -1
      return diatonic_step(sn, pedal, dir)
    elseif c.chord_range and #c.chord_range > 0 then
      return nearest_chord_tone(pedal, c.chord_range)
    else
      local dir = (rng_float() < 0.5) and 1 or -1
      return diatonic_step(sn, pedal, dir)
    end
  end

  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- ── 5. CALL & RESPONSE ─────────────────────────────────────────
-- Alternating pairs. The "call" unit is generated freely (Free's surface
-- walker) and recorded as { scale-step offset from block_skeleton, rhythm
-- in slots } per onset; the "response" unit replays those entries
-- anchored to its own block's skeleton — yielding a chord/key-aware
-- diatonic sequence of the call. Subtle variation: busyness-scaled
-- single-step displacement on interior onsets, cadence-driven pull
-- toward next_skeleton on the unit's last onset. Adaptive granularity:
-- phrase pairs when there are ≥ 2 phrases AND the progression is long
-- enough (> 4 blocks); otherwise block pairs.
local function mel_strat_call_response(block_dur, chord_notes, scale_notes, chord_range, ctx_tbl)
  ctx_tbl.rest_soften = 0.5   -- response inherits the call's rhythm;
                              -- don't let busy/space erase entries.

  local phrases    = ctx_tbl.phrases or {}
  local skeleton   = ctx_tbl.skeleton or {}
  local block_idx  = ctx_tbl.block_idx or 1
  local total_blks = #skeleton

  local use_phrase_pairs = (#phrases >= 2) and (total_blks > 4)

  -- Identify the (pair_id, block-offset-within-unit, role) for the
  -- current block. role: 0 = call, 1 = response.
  local pair_id, role, unit_block_offset
  if use_phrase_pairs then
    local my_pi = 1
    for pi, ph in ipairs(phrases) do
      if block_idx >= ph.start_block and block_idx <= ph.end_block then
        my_pi = pi; break
      end
    end
    pair_id           = math.floor((my_pi - 1) / 2)
    role              = (my_pi - 1) % 2
    unit_block_offset = block_idx - phrases[my_pi].start_block
  else
    pair_id           = math.floor((block_idx - 1) / 2)
    role              = (block_idx - 1) % 2
    unit_block_offset = 0   -- single-block units
  end

  ctx_tbl.cr_buffer = ctx_tbl.cr_buffer or {}
  local buf_key = pair_id .. ":" .. unit_block_offset
  local has_call = ctx_tbl.cr_buffer[buf_key] ~= nil

  if role == 0 or not has_call then
    -- ── CALL phase: generate freely, record entries ───────────
    local rec = { entries = {}, skeleton = ctx_tbl.block_skeleton }
    ctx_tbl.cr_buffer[buf_key] = rec

    local function pitch_fn(pos, bdur, cn, sn, prev, c)
      local p
      if c.is_block_start_slot then
        p = c.block_skeleton or prev
      else
        p = surface_step(prev, c.next_skeleton, sn,
                         c.is_final_onset_of_block, c.is_phrase_end, c)
      end
      if p then
        local sk_idx    = nearest_idx(sn, rec.skeleton or p)
        local pitch_idx = nearest_idx(sn, p)
        rec.entries[#rec.entries + 1] = {
          idx_offset = pitch_idx - sk_idx,
          dur_slots  = c.current_dur_slots or 1,
        }
      end
      return p
    end
    return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
  end

  -- ── RESPONSE phase: replay entries, anchored to this skeleton ──
  local rec     = ctx_tbl.cr_buffer[buf_key]
  local entries = rec.entries
  local cursor  = 0
  local busy    = (state.mel_busyness or 50) / 100.0
  local cadence = (state.mel_cadence or 60) / 100.0

  local function pitch_fn(pos, bdur, cn, sn, prev, c)
    cursor = cursor + 1
    local entry = entries[cursor]
    -- Response longer than the call: extras improvise via surface_step.
    if not entry then
      if c.is_block_start_slot then return c.block_skeleton or prev end
      return surface_step(prev, c.next_skeleton, sn,
                          c.is_final_onset_of_block, c.is_phrase_end, c)
    end

    -- Cadential pull toward next_skeleton on the very last onset of the
    -- response unit. In phrase-pair mode the response's last block is
    -- a phrase-end block (the phrase planner aligns to chord boundaries
    -- and we placed the response phrase here). In block-pair mode the
    -- response IS a single block, so its final onset is the unit end.
    local is_unit_end
    if use_phrase_pairs then
      is_unit_end = c.is_final_onset_of_block and c.is_phrase_end
    else
      is_unit_end = c.is_final_onset_of_block
    end
    if is_unit_end and c.next_skeleton and cadence > 0.4 then
      local p = surface_step(prev, c.next_skeleton, sn, true, c.is_phrase_end, c)
      return { pitch = p, dur_slots = entry.dur_slots }
    end

    local sk_idx = nearest_idx(sn, c.block_skeleton or prev)
    local off    = entry.idx_offset
    -- Subtle interior variation: with prob ∝ busyness, displace by ±1.
    if cursor > 1 and cursor < #entries and rng_float() < busy * 0.20 then
      off = off + ((rng_float() < 0.5) and 1 or -1)
    end
    local idx = math.max(1, math.min(#sn, sk_idx + off))
    return { pitch = sn[idx], dur_slots = entry.dur_slots }
  end

  return mel_fill_block(block_dur, chord_notes, scale_notes, chord_range, pitch_fn, ctx_tbl)
end

-- Dispatcher: presets in MEL_PRESET_ITEMS order.
local MEL_GEN_FNS = {
  mel_strat_free,             -- 1
  mel_strat_motif,            -- 2
  mel_strat_mechanical,       -- 3
  mel_strat_pedal_point,      -- 4
  mel_strat_call_response,    -- 5
}

-- Build one cycle of the progression, appending to `events` and mutating
-- `context`. `cycle_offset` is the absolute beat where this cycle starts;
-- subsequent cycles re-use the same context (preserving prev_pitch, motif
-- cell etc.) so the RNG stream and musical state continue smoothly.
-- Returns the absolute beat where this cycle ended.
local function build_melody_cycle(progression, context, events, cycle_offset)
  apply_cadence_to_legacy()
  local gen_fn = MEL_GEN_FNS[state.mel_preset_idx] or MEL_GEN_FNS[1]
  local abs_pos = cycle_offset

  -- Phrase-arc tension repeats per cycle: each progression pass arcs from
  -- repose → peak → repose, so cycle 2 isn't stuck at "end of arc" tension.
  -- Plan phrases first so the arc can nest per-phrase sub-arches inside
  -- the cycle-level shape (see phrase_arc_init).
  local total_beats = 0
  for _, ch in ipairs(progression) do total_beats = total_beats + ch.duration end

  -- Plan phrases for this cycle and build a structural skeleton: one
  -- voice-led chord tone per chord block, shaped by the per-phrase
  -- contour. The first onset of each block lands on its skeleton pitch;
  -- the surface walker aims at the *next* skeleton pitch through the
  -- block's interior.
  local phrases  = plan_phrases(progression, state.timesig_num)
  phrase_arc_init(context, total_beats, cycle_offset, progression, phrases)
  local skeleton = build_skeleton(progression, phrases,
                                  context.last_skeleton_pitch
                                  or context.prev_pitch)
  context.phrases  = phrases
  context.skeleton = skeleton
  -- Mark which block_idx is the LAST block of its phrase (= a phrase end).
  local phrase_end_block = {}
  for _, ph in ipairs(phrases) do phrase_end_block[ph.end_block] = true end

  for ci, ch in ipairs(progression) do
    -- Chord-aware scale: walk the line on a pc set that resolves the
    -- chord's 3rd/7th against the global mode. Without this, borrowed
    -- chords and secondary dominants leave the line walking the diatonic
    -- 3rd or 7th right when the chord wants the altered one.
    local chord_scale_pcs, chord_is_altered =
        chord_scale_pc_set(ch.notes, ch.root_midi)
    local lo_p, hi_p   = mel_window(ch.root_midi)

    -- Phrasing reshapes the per-chord scale pool. Bluesy adds the b3/b7
    -- so the walker can land on them (not just slide through); Pentatonic
    -- restricts the pool to a 5-note subset unioned with the chord's tones
    -- so chord-tone landings on 3rds/7ths still work even when those
    -- aren't in the pentatonic.
    local chord_root_pc = (ch.root_midi or 0) % 12
    local phrasing      = state.mel_phrasing_idx or 1
    if phrasing == 2 then  -- Bluesy
      chord_scale_pcs[(chord_root_pc + 3)  % 12] = true   -- b3 (blue 3rd)
      chord_scale_pcs[(chord_root_pc + 10) % 12] = true   -- b7 (dom 7)
    elseif phrasing == 3 then  -- Pentatonic
      local pent_pcs = pentatonic_pcs_for(
        (state.root_idx - 1) % 12, MODE_NAMES[state.mode_idx])
      local chord_pcs_local = chord_pc_set(ch.notes)
      local kept = {}
      for pc in pairs(chord_scale_pcs) do
        if pent_pcs[pc] or chord_pcs_local[pc] then kept[pc] = true end
      end
      if next(kept) then chord_scale_pcs = kept end
    end

    local scale_notes  = pcs_to_notes_in_range(chord_scale_pcs, lo_p, hi_p)
    local chord_range  = chord_notes_in_range(ch.notes, lo_p, hi_p)
    if #scale_notes == 0 then
      abs_pos = abs_pos + ch.duration
    else
      context.abs_block_start  = abs_pos
      context.chord_meta       = ch
      context.scale_pcs_chord  = chord_scale_pcs
      context.chord_is_altered = chord_is_altered
      context.chord_root_pc    = chord_root_pc
      context.is_first_block   = (cycle_offset == 0 and ci == 1)
      context.block_idx        = ci
      context.block_skeleton   = skeleton[ci]
      context.mel_lo_p         = lo_p
      context.mel_hi_p         = hi_p
      -- next_skeleton: target the surface walker aims at through this
      -- block. At progression end we resolve to the current skeleton
      -- (a settled close) — cycle wrap will pick up fresh next time.
      context.next_skeleton   = skeleton[ci + 1] or skeleton[ci]
      context.is_phrase_end   = phrase_end_block[ci] or false

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

  -- Save final skeleton pitch so the next cycle's skeleton voice-leads
  -- from where this one ended.
  context.last_skeleton_pitch = skeleton[#progression]

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

-- (build_arp_pool, apply_arp_pattern moved to core/arp.lua)

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

local function build_arp_events(chord_notes, chord_dur_beats, chord_abs_beat,
                                chord_root_midi)
  local rate_beats = ARP_RATES[state.arp_rate_idx].beats
  local pattern    = ARP_PATTERNS[state.arp_pattern_idx]
  local gate_frac  = state.arp_gate / 100.0
  local base_vel   = state.arp_velocity
  local human      = state.arp_vel_human
  local chord_scale_pcs = chord_scale_pc_set(chord_notes, chord_root_midi)
  local pool = build_arp_pool(chord_notes, state.arp_oct_low, state.arp_oct_high,
                              state.arp_rigidity, chord_scale_pcs)
  if #pool == 0 then return {} end
  local n_steps = math.ceil(chord_dur_beats / rate_beats)
  local rng_seq = {}
  for i = 1, #pool + n_steps * 2 do rng_seq[i] = rng_float() end
  local seq = apply_arp_pattern(pool, pattern, rng_seq)
  if #seq == 0 then return {} end
  local events = {}
  if pattern == "Chord" then
    local chord_voiced = {}
    local pcs = {}
    for _, p in ipairs(chord_notes) do pcs[#pcs+1] = p % 12 end
    for oct = state.arp_oct_low, state.arp_oct_high do
      for _, pc in ipairs(pcs) do
        local pitch = oct * 12 + pc
        if pitch >= 0 and pitch <= 127 then chord_voiced[#chord_voiced+1] = pitch end
      end
    end
    table.sort(chord_voiced)
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
--  BASS GENERATOR — host wrapper around core/bass.lua
-- ----------------------------------------------------------------
local function build_bass_events(this_chord, chord_dur, next_chord)
  return bass.build_events(this_chord, chord_dur, next_chord, {
    style              = BASS_STYLES[state.bass_style_idx],
    oct                = state.bass_oct,
    velocity           = state.bass_velocity,
    vel_human          = state.bass_vel_human,
    gate               = state.bass_gate,
    follow_inv         = state.bass_follow_inv,
    approach_prob      = state.bass_approach_prob,
    mode               = MODE_NAMES[state.mode_idx],
    root_idx           = state.root_idx,
    pattern_grid_beats = ARP_RATES[state.bass_pattern_grid_idx].beats,
    pattern_steps      = state.bass_pattern_steps,
    pattern_notes      = state.bass_pattern_notes,
  })
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
  local ch  = state.chord_channel
  local vel = math.max(1, math.min(127, state.chord_velocity or 90))
  for _, n in ipairs(notes) do
    reaper.StuffMIDIMessage(0, 0x90 | ch, n, vel)
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
  live_notes_on(progression[chord_idx].voicing)
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
    local arp_evs = build_arp_events(ch.notes, ch.duration, cursor_abs + pos_beats, ch.root_midi)
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
    build_arp_events(ch.notes, ch.duration, cursor_abs + pos, ch.root_midi)
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
--  SETTINGS FILE SAVE / LOAD
-- ----------------------------------------------------------------
local function get_script_dir()
  local _, p = reaper.get_action_context()
  return p:match("^(.+[\\/])") or ""
end

local function save_settings_to_file()
  local ok, inputs = reaper.GetUserInputs("Save Cordial Settings", 1,
    "Filename (no extension):", "my_settings")
  if not ok then return end
  local name = inputs:match("^%s*(.-)%s*$")
  if name == "" then name = "my_settings" end
  name = name:gsub("[\\/]", "_")
  local path = get_script_dir() .. name .. ".cordial"
  local f = io.open(path, "w")
  if not f then
    reaper.ShowMessageBox("Could not write to:\n" .. path, "Cordial", 0)
    return
  end
  for _, k in ipairs(PERSIST_KEYS) do
    f:write(k .. "=" .. tostring(state[k]) .. "\n")
  end
  local nd = #state.chord_durations
  f:write("num_chords=" .. nd .. "\n")
  f:write("chord_durations="  .. arr_to_str(state.chord_durations) .. "\n")
  f:write("chord_inversions=" .. arr_to_str(state.chord_inversions) .. "\n")
  local qparts = {}
  for i = 1, nd do qparts[i] = state.chord_quality_overrides[i] or "" end
  f:write("chord_quality_overrides=" .. table.concat(qparts, ",") .. "\n")
  local bparts = {}
  for i = 1, nd do bparts[i] = state.chord_bass_overrides[i] or "" end
  f:write("chord_bass_overrides=" .. table.concat(bparts, ",") .. "\n")
  f:write("custom_degrees_n=" .. #state.custom_degrees .. "\n")
  f:write("custom_degrees="   .. arr_to_str(state.custom_degrees) .. "\n")
  f:write("bass_pattern_notes=" .. arr_to_str(state.bass_pattern_notes) .. "\n")
  f:close()
  state.status_msg = "Saved: " .. path
end

local function load_settings_from_file()
  local ok, path = reaper.GetUserFileNameForRead(get_script_dir(),
    "Load Cordial Settings", "cordial")
  if not ok or path == "" then return end
  local f = io.open(path, "r")
  if not f then
    reaper.ShowMessageBox("Could not open:\n" .. path, "Cordial", 0)
    return
  end
  local data = {}
  for line in f:lines() do
    local k, v = line:match("^([^=]+)=(.*)")
    if k then data[k] = v end
  end
  f:close()
  for _, k in ipairs(PERSIST_KEYS) do
    local val = data[k]
    if val and val ~= "" then
      local def = state[k]
      if type(def) == "number" then
        state[k] = tonumber(val) or def
      elseif type(def) == "boolean" then
        state[k] = (val == "true")
      else
        state[k] = val
      end
    end
  end
  local nd = tonumber(data["num_chords"]) or #state.chord_durations
  local val = data["chord_durations"]
  if val and val ~= "" then state.chord_durations = str_to_num_arr(val, nd) end
  val = data["chord_inversions"]
  if val and val ~= "" then state.chord_inversions = str_to_num_arr(val, nd) end
  val = data["chord_quality_overrides"]
  if val and val ~= "" then
    state.chord_quality_overrides = {}
    local i = 0
    for tok in (val..","):gmatch("([^,]*),") do
      i = i + 1
      state.chord_quality_overrides[i] = (tok ~= "") and tok or nil
      if i >= nd then break end
    end
  end
  val = data["chord_bass_overrides"]
  if val and val ~= "" then
    state.chord_bass_overrides = {}
    local i = 0
    for tok in (val..","):gmatch("([^,]*),") do
      i = i + 1
      state.chord_bass_overrides[i] = (tok ~= "") and tok or nil
      if i >= nd then break end
    end
  end
  local cdn = tonumber(data["custom_degrees_n"]) or #state.custom_degrees
  val = data["custom_degrees"]
  if val and val ~= "" then state.custom_degrees = str_to_num_arr(val, cdn) end
  val = data["bass_pattern_notes"]
  if val and val ~= "" then state.bass_pattern_notes = str_to_num_arr(val, 8) end
  state.seed_str = tostring(state.seed)
  reset_live()
  state.status_msg = "Loaded: " .. path
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
  local cycles      = math.max(1, math.floor(state.render_cycles or 1))
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
        for _, note in ipairs(ch.voicing) do
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
      local arp_evs = build_arp_events(ch.notes, ch.duration, cursor_abs + pos, ch.root_midi)
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
  {label="Free",            group="Strategy"},
  {label="Motif",           group="Strategy"},
  {label="Mechanical",      group="Strategy"},
  {label="Pedal Point",     group="Texture"},
  {label="Call & Response", group="Texture"},
}

-- Phrasing options layered over any preset (mutually exclusive).
local MEL_PHRASING_ITEMS = { "None", "Bluesy", "Pentatonic" }

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
    load_preset_inversions(p, n)
    reset_live()
  end

  if PROGRESSIONS[state.prog_idx].name == "Custom" then
    reaper.ImGui_Text(ctx, "Degrees (1-7):")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local deg_str = table.concat(state.custom_degrees, " ")
    local ce, ns  = reaper.ImGui_InputText(ctx, "##cust", deg_str)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx,
        "Scale degrees 1–7 separated by spaces or commas.\n"..
        "Digits 0/8/9 are ignored. Multi-digit tokens (e.g. 12) are not split.")
    end
    if ce then
      local nd = {}
      for tok in ns:gmatch("[^%s,]+") do
        local di = tonumber(tok)
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

  -- Smart voicing: auto-pick rotations that minimise bass leap.
  local svc, svv = reaper.ImGui_Checkbox(ctx, "Smart voicing (auto-invert)##smartv", state.smart_voicing)
  if svc then state.smart_voicing = svv; reset_live() end
  if state.smart_voicing then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx,
      "— rotation auto-picked for slots with no manual inv / no slash")
  end

  -- Column header
  reaper.ImGui_TextDisabled(ctx,
    string.format("%-18s %-8s %-6s %-10s %-6s", "Chord", "Quality", "Bars", "Inv", "/Bass"))
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

    -- Slash-bass text input (scale-degree of key, with optional accidental)
    reaper.ImGui_SameLine(ctx); reaper.ImGui_TextDisabled(ctx, "/")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 40)
    local cur_bass = state.chord_bass_overrides[i] or ""
    local sbc, sbv = reaper.ImGui_InputText(ctx, "##sb"..i, cur_bass)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx,
        "Slash bass: scale degree 1–7 of the key, optional b/# accidental.\n"..
        "Examples: 3, b7, #4. Empty = no slash bass.")
    end
    if sbc then
      sbv = sbv:match("^%s*(.-)%s*$") or ""
      if sbv == "" then
        state.chord_bass_overrides[i] = nil
      elseif sbv:match("^[b#]?[1-7]$") then
        state.chord_bass_overrides[i] = sbv
      end
      reset_live()
    end

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
  local any_inversion = false
  for _, v in ipairs(state.chord_inversions) do
    if v and v ~= 0 then any_inversion = true; break end
  end
  local any_slash = false
  for _, v in ipairs(state.chord_bass_overrides) do
    if v then any_slash = true; break end
  end
  if any_override then
    if reaper.ImGui_SmallButton(ctx, "Reset qualities") then
      for i = 1, #state.chord_quality_overrides do
        state.chord_quality_overrides[i] = nil
      end
      reset_live()
    end
    reaper.ImGui_SameLine(ctx)
  end
  if any_inversion or any_slash then
    if reaper.ImGui_SmallButton(ctx, "Reset inversions & slashes") then
      for i = 1, #state.chord_inversions do
        state.chord_inversions[i] = 0
      end
      for i = 1, #state.chord_bass_overrides do
        state.chord_bass_overrides[i] = nil
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
  reaper.ImGui_SetNextItemOpen(ctx, state.arp_open, reaper.ImGui_Cond_Once())
  state.arp_open = reaper.ImGui_CollapsingHeader(ctx, "Arp Layer")
  if state.arp_open then
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
  local alc, alv = sslider("Oct Lo##aoctlo", state.arp_oct_low, 0, 8, 80)
  if alc then
    state.arp_oct_low = math.min(alv, state.arp_oct_high)
    state.arp_live_events = nil
  end
  reaper.ImGui_SameLine(ctx)
  local ahcc, ahv2 = sslider("Oct Hi##aocthi", state.arp_oct_high, 0, 8, 80)
  if ahcc then
    state.arp_oct_high = math.max(ahv2, state.arp_oct_low)
    state.arp_live_events = nil
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format("(C%d–B%d)",
    state.arp_oct_low, state.arp_oct_high))

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

  local arc2, arv2 = sslider("Scale blend##rigid", state.arp_rigidity, 0, 100, 220)
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
  end -- arp_open

  -- ── Melody Layer ─────────────────────────────────────────────
  reaper.ImGui_SetNextItemOpen(ctx, state.mel_open, reaper.ImGui_Cond_Once())
  state.mel_open = reaper.ImGui_CollapsingHeader(ctx, "Melody Layer")
  if state.mel_open then
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
  reaper.ImGui_SetNextItemWidth(ctx, 105)
  local mphc, mphv = combo("Phrasing##melphr", MEL_PHRASING_ITEMS, state.mel_phrasing_idx)
  if mphc then state.mel_phrasing_idx = mphv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  local mbusyc, mbusyv = sslider("Busy##mbusy", state.mel_busyness, 0, 100, 70)
  if mbusyc then state.mel_busyness = mbusyv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  local mspc, mspv = sslider("Space##mspace", state.mel_space, 0, 100, 70)
  if mspc then state.mel_space = mspv; state.mel_live_events=nil end
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

  -- Pitch window: anchor + asymmetric range.
  reaper.ImGui_SetNextItemWidth(ctx, 110)
  local manc, manv = combo("Anchor##manchor", MEL_ANCHOR_NAMES, state.mel_anchor_mode)
  if manc then state.mel_anchor_mode = manv; state.mel_live_events = nil end
  if state.mel_anchor_mode == 1 then
    reaper.ImGui_SameLine(ctx)
    local maoc, maov = sslider("Oct##manoct", state.mel_anchor_oct, 2, 7, 60)
    if maoc then state.mel_anchor_oct = maov; state.mel_live_events = nil end
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx,
    state.mel_anchor_mode == 1 and "fixed register" or
    state.mel_anchor_mode == 2 and "centred on each chord's root" or
    "centred on the key's tonic")

  local mrdc, mrdv = sslider("Down##mrdown", state.mel_range_down, 0, 36, 90)
  if mrdc then state.mel_range_down = mrdv; state.mel_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  local mruc, mruv = sslider("Up##mrup",   state.mel_range_up,   0, 36, 90)
  if mruc then state.mel_range_up = mruv; state.mel_live_events = nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "semitones below / above anchor")

  -- Cadence: single musical knob that drives chord-tone landings,
  -- strong-beat preference, leading-tone approaches and phrase-end
  -- cadential figures. Replaces the old Rigidity / Colour / Metre trio.
  local mcadc, mcadv = sslider("Cadence##mcad", state.mel_cadence, 0, 100, 130)
  if mcadc then state.mel_cadence = mcadv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx,
    state.mel_cadence == 0   and "free wander — no landings, ambient" or
    state.mel_cadence < 25   and "loose — chord tones at chord changes" or
    state.mel_cadence < 50   and "phrasal — soft 4-bar arcs, voice-led" or
    state.mel_cadence < 75   and "shaped — cadences at phrase ends" or
    state.mel_cadence < 100  and "idiomatic — leading tones, suspensions" or
    "textbook — antecedent / consequent, full cadences")

  local mrrc, mrrv = sslider("Rhythm##mrrig", state.mel_rhythm_rigidity, 0, 100, 130)
  if mrrc then state.mel_rhythm_rigidity = mrrv; state.mel_live_events=nil end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx,
    state.mel_rhythm_rigidity == 0   and "free — durations land anywhere on the grid" or
    state.mel_rhythm_rigidity < 25   and "loose — mild bias toward aligned starts" or
    state.mel_rhythm_rigidity < 50   and "phrased — 1/8s lean to 1/8 grid, 1/4s to 1/4 grid" or
    state.mel_rhythm_rigidity < 75   and "tight — durations strongly prefer their own grid" or
    state.mel_rhythm_rigidity < 100  and "metronomic — off-grid placements rare" or
    "locked — every duration on its matching grid")

  reaper.ImGui_TextDisabled(ctx, "Busy "..state.mel_busyness.." — "..(
    state.mel_busyness == 0  and "very sparse — long held notes, occasional rests" or
    state.mel_busyness < 25  and "sparse — mostly long notes, gentle activity" or
    state.mel_busyness < 50  and "balanced — mixed lengths, mild ebb & flow" or
    state.mel_busyness < 75  and "active — shorter notes prevail, arc-shaped clustering" or
    state.mel_busyness < 100 and "busy — bursts of subdivision around bar/half-bar landmarks" or
    "very busy — dense subdivision bursts, snapped to quarter-note boundaries"))

  reaper.ImGui_TextDisabled(ctx, "Space "..state.mel_space.." — "..(
    state.mel_space == 0   and "no extra rests — fills the bar" or
    state.mel_space < 25   and "occasional gaps between phrases" or
    state.mel_space < 50   and "breathing room — onsets pulled toward beats" or
    state.mel_space < 75   and "airy — frequent rests, onsets on quarters" or
    state.mel_space < 100  and "sparse — long silences, attacks only on beats" or
    "very sparse — pointillistic, every onset on a quarter boundary"))
  end -- mel_open

  -- ── Bass Layer ───────────────────────────────────────────────
  reaper.ImGui_SetNextItemOpen(ctx, state.bass_open, reaper.ImGui_Cond_Once())
  state.bass_open = reaper.ImGui_CollapsingHeader(ctx, "Bass Layer")
  if state.bass_open then
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
  end -- bass_open

  -- ── Live Preview ─────────────────────────────────────────────
  reaper.ImGui_SeparatorText(ctx, "Live Preview")

  local lec, lev = reaper.ImGui_Checkbox(ctx, "Chords##livecheck", state.chord_live_enabled)
  if lec then
    state.chord_live_enabled = lev
    if not lev then live_notes_off(); state.last_chord_idx=-1 end
  end
  if state.chord_live_enabled then
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

  if state.chord_live_enabled or state.arp_live_enabled or state.mel_live_enabled
      or state.bass_live_enabled then
    reaper.ImGui_TextDisabled(ctx, "Press Play to hear  ·  edits re-sync at the next cycle boundary")
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
    save_proj_state()
    write_all()
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "  KEEP this take  ", 160, 28) then
    state.seed_locked = true
    save_proj_state()
    write_all()
    state.status_msg = "[KEPT]  "..state.status_msg
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 90)
  local rcc, rcv = reaper.ImGui_SliderInt(ctx, "cycles##rendercycles",
                                          state.render_cycles, 1, 32)
  if rcc then state.render_cycles = rcv end

  reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_Button(ctx, "Save Settings...", 130, 0) then save_settings_to_file() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Load Settings...", 130, 0) then load_settings_from_file() end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextDisabled(ctx, state.status_msg)
  reaper.ImGui_TextDisabled(ctx,
    "Keys (passthrough): Space = play/stop  ·  Home = start  ·  End = end of project")
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
