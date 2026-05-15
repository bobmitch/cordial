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
