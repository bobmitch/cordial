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
