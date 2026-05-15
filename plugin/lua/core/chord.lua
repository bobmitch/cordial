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

return M
