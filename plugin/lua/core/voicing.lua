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
