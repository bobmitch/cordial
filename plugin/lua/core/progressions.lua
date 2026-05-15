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
