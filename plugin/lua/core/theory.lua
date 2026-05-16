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
