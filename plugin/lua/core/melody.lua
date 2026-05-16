-- ----------------------------------------------------------------
--  core/melody.lua  —  melody generation
--
--  Top-level entry point: M.build_events(progression, params).
--  Live preview / multi-cycle render: M.build_cycle(progression,
--  context, events, cycle_offset, params).
--
--  The full melody pipeline (phrase planner → skeleton builder →
--  surface walker → eight strategy generators → mel_fill_block)
--  lives in this module. Sub-functions read parameters from the
--  module-local `p` upvalue rather than threading params through
--  every signature; M.build_events / M.build_cycle set `p = params`
--  before any sub-function runs. Single-threaded by design — Phase 4
--  will own concurrency on the C++ side.
--
--  params (see host_reaper.lua build_melody_events wrapper for the
--  state→params translation):
--    anchor_mode (1=Fixed, 2=Chord root, 3=Scale root)
--    anchor_oct, range_down, range_up        - pitch window
--    min_dur_beats, max_dur_beats            - duration bounds (resolved)
--    velocity, vel_human                     - dynamics
--    busyness, cadence, metre, space         - rhythmic shaping
--    rhythm_rigidity, colour                 - grid alignment, chromatic
--    preset_idx, phrasing_idx                - strategy + scale subset
--    root_idx, mode, octave                  - key
--    timesig_num                             - time signature numerator
--    seed                                    - for shuffled_contours' LCG
-- ----------------------------------------------------------------

local theory  = theory  or require 'core.theory'
local rng     = rng     or require 'core.rng'
local chord   = chord   or require 'core.chord'
local voicing = voicing or require 'core.voicing'

local M = {}

-- Module-local params, set by M.build_events / M.build_cycle.
local p

-- Melody duration grid. The host keeps its own copy of this table for UI
-- labels; the values must stay in sync. Source of truth could move either
-- way later — for Phase 2 we accept the small duplication.
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

-- Compute the melody pitch window [lo, hi] (MIDI) for the current
-- block. The anchor depends on mel_anchor_mode; the span is
-- mel_range_down semitones below and mel_range_up above. Clamped to
-- valid MIDI (0..127). chord_root_midi may be nil when not available
-- (e.g. live preview before a chord has been picked); we fall back to
-- the scale-root anchor.
local function mel_window(chord_root_midi)
  local anchor
  local mode = p.anchor_mode or 2
  if mode == 2 and chord_root_midi then
    anchor = chord_root_midi
  elseif mode == 3 then
    anchor = chord.midi_note(p.root_idx, p.octave)
  else
    anchor = chord.midi_note(p.root_idx, p.anchor_oct or 4)
  end
  local lo = anchor - (p.range_down or 7)
  local hi = anchor + (p.range_up   or 14)
  if lo < 0   then lo = 0   end
  if hi > 127 then hi = 127 end
  if hi < lo  then hi = lo  end
  return lo, hi
end

-- Return sorted, deduped MIDI pitches of the current scale that fall
-- inside [lo_p, hi_p].
local function scale_notes_in_range(lo_p, hi_p)
  local mode     = p.mode
  local ivs      = theory.SCALE_INTERVALS[mode]
  local root_pc  = (p.root_idx - 1) % 12
  local pcs      = {}
  for _, iv in ipairs(ivs) do pcs[(root_pc + iv) % 12] = true end
  local notes    = {}
  for p = lo_p, hi_p do
    if pcs[p % 12] then notes[#notes+1] = p end
  end
  return notes
end



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
  local busy = (p.busyness or 50) / 100.0
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
  local cadence = (p.cadence or 60) / 100.0
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
  local num         = p.timesig_num
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
  local metre   = p.metre / 100.0
  local space   = (p.space or 0) / 100.0
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
        include = rng.rng_float() < admit_prob
      end
    end

    -- Space gate: pin onsets to quarter-note boundaries. Sub-beat slots
    -- are rejected with probability proportional to space, independent of
    -- metre. At space=1 every onset lands on a beat; at space=0, no-op.
    if include and space > 0 then
      local abs_beat  = (abs_start_slot + s) * grid
      local beat_frac = abs_beat - math.floor(abs_beat)
      local on_beat   = beat_frac < 0.01 or (1.0 - beat_frac) < 0.01
      if not on_beat and rng.rng_float() < space then
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
  local metre  = p.metre / 100.0
  local busy   = (p.busyness or 50) / 100.0
  local rrig   = (p.rhythm_rigidity or 0) / 100.0
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

  local r = rng.rng_float() * total
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
            if rng.rng_float() < snap_prob then chosen = snapped end
          end
        end
        -- Phrase-end hold: absorb tiny gap to barline
        local abs_onset_beat = (abs_start_slot + onset_slot) * grid
        local bar_remain     = p.timesig_num - (abs_onset_beat % p.timesig_num)
        if bar_remain < 0.001 then bar_remain = p.timesig_num end
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
        if rng.rng_float() < stretch_prob then
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
  return valid[rng.rng_int(1, #valid)]
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
--  Strength scales with p.cadence (0 = free wander, 100 =
--  textbook cadences). Random choices flow through rng.rng_float() to
--  preserve the seed contract.
-- ============================================================

-- 1. PHRASE PLANNER ──────────────────────────────────────────────
-- Group the progression into ~4-bar phrases (absorbing any remainder
-- into the final phrase). Each phrase carries a contour shape used by
-- skeleton selection. The contour cycle is shuffled deterministically
-- from p.seed so phrase 1 isn't always an "arch" (which made the
-- middle of every short progression peak high in the same way). Same
-- seed → same shuffle → same line.
local PHRASE_CONTOURS = {"arch", "descend", "ascend", "valley"}

-- Deterministic shuffle driven by p.seed via a local LCG, so we
-- don't perturb the global math.random stream the rest of the melody
-- pipeline is consuming.
local function shuffled_contours()
  local out = { table.unpack(PHRASE_CONTOURS) }
  local s = ((p.seed or 0) * 2654435761 + 2246822519) % 2^31
  for i = #out, 2, -1 do
    s = (s * 1103515245 + 12345) % 2^31
    local j = (s % i) + 1
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function plan_phrases(progression, bar_beats)
  local target_phrase_beats = 4 * (bar_beats or p.timesig_num)
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
      local chord_range = chord.chord_notes_in_range(ch.notes, lo_p, hi_p)
      if #chord_range == 0 then
        skeleton[bi] = prev or 60
      else
        local t        = (n_blocks > 1) and (offs / (n_blocks - 1)) or 0.5
        local h        = contour_height(ph.contour, t)
        local lo, hi   = chord_range[1], chord_range[#chord_range]
        local height_p = lo + h * (hi - lo)
        local pick     = voicing.nearest_chord_tone(height_p, chord_range)
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
  local cadence = (p.cadence or 60) / 100.0
  if #scale_notes == 0 then return prev_pitch end

  -- Leap recovery: if the previous onset took a consonant leap, this
  -- onset balances it with a diatonic step in the opposite direction
  -- (the classical leap-then-step rule that keeps wide intervals from
  -- sounding jarring). Recovery is forced even on a final-onset slot
  -- since the leap that caused it was itself non-final.
  if ctx and ctx.leap_recover_dir then
    local rdir = ctx.leap_recover_dir
    ctx.leap_recover_dir = nil
    return voicing.diatonic_step(scale_notes, prev_pitch, rdir)
  end

  -- Consonant leap: small chance, only on non-final onsets so it
  -- doesn't fight the cadence approach figure. Jumps to a chord tone
  -- a 4th–6th away from prev in the contour direction; the next
  -- onset will step back via the recovery branch above. This is the
  -- only path through which the surface line can traverse register
  -- — without it the walker is bounded to ±3 scale steps per onset.
  if not is_final_onset and ctx and ctx.chord_range
     and #ctx.chord_range > 0 and rng.rng_float() < 0.10 then
    local dir
    if target_pitch and target_pitch ~= prev_pitch then
      dir = (target_pitch > prev_pitch) and 1 or -1
    else
      dir = (rng.rng_float() < 0.5) and 1 or -1
    end
    local candidates = {}
    for _, n in ipairs(ctx.chord_range) do
      local d = (n - prev_pitch) * dir
      if d >= 5 and d <= 9 then candidates[#candidates+1] = n end
    end
    if #candidates > 0 then
      local leap = candidates[rng.rng_int(1, #candidates)]
      ctx.leap_recover_dir = -dir
      return leap
    end
  end

  if is_final_onset and target_pitch then
    local approach_prob = is_phrase_end and (0.4 + 0.6 * cadence)
                                        or (0.2 + 0.5 * cadence)
    if rng.rng_float() < approach_prob then
      local up   = voicing.diatonic_step(scale_notes, target_pitch, 1)
      local down = voicing.diatonic_step(scale_notes, target_pitch, -1)
      -- Semitone leading-tone only when that pitch is actually in the scale
      -- (e.g. B→C in C major). Blind target-1 produces out-of-key notes
      -- on every other scale degree, so we gate it here.
      if is_phrase_end and cadence > 0.5
         and rng.rng_float() < (cadence - 0.3) then
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
  local idx_prev = chord.nearest_idx(scale_notes, prev_pitch)
  local idx_targ = target_pitch and chord.nearest_idx(scale_notes, target_pitch) or idx_prev
  local dir
  if idx_targ == idx_prev then
    dir = (rng.rng_float() < 0.5) and 1 or -1   -- neighbour figure
  else
    dir = (idx_targ > idx_prev) and 1 or -1
  end
  -- Step size: mostly 1, occasional 2 (third), very occasional 3.
  local r = rng.rng_float()
  local step = (r < 0.75) and 1 or (r < 0.95) and 2 or 3
  -- Small chance of reverse step for a passing/neighbour shape.
  if rng.rng_float() < 0.15 then dir = -dir end
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
  local c = (p.cadence or 60) / 100.0
  p.metre  = math.floor(c * 80)
  p.colour = math.floor(c * 70)
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
  if (p.phrasing_idx or 1) == 2 and chord_root_pc
     and rng.rng_float() < 0.55 then
    local blue = bluesy_blue_note(from_pitch, to_pitch, chord_root_pc)
    if blue then return blue end
  end

  if p.colour == 0 then return nil end
  local colour_prob = p.colour / 100.0
  if rng.rng_float() > colour_prob then return nil end

  local diff = to_pitch - from_pitch

  -- 1. Leading-tone approach into a chord tone on a strong position.
  -- Only when target - 1 is actually a scale degree (e.g. B→C in major);
  -- a blind semitone-below produces out-of-key notes on most scale degrees.
  if target_is_strong and voicing.is_chord_tone(to_pitch, chord_pcs) then
    if math.abs(diff) <= 4 and rng.rng_float() < 0.5 then
      local lt = voicing.leading_tone_to(to_pitch)
      if scale_pcs[lt % 12] and math.abs(lt - from_pitch) <= 5 then return lt end
    end
  end

  -- 2. Diatonic upper-neighbour into a chord tone (returning to same pitch).
  if diff == 0 and voicing.is_chord_tone(to_pitch, chord_pcs) then
    if rng.rng_float() < 0.5 then
      return voicing.diatonic_neighbor(scale_notes, to_pitch, 1)
    else
      return voicing.diatonic_neighbor(scale_notes, to_pitch, -1)
    end
  end

  -- 3. Diatonic passing tone when notes are a whole step apart.
  -- (A chromatic semitone between diatonic whole-step pairs is always
  -- out of key, so we use a diatonic step toward the target instead.)
  if math.abs(diff) == 2 then
    local passing = voicing.diatonic_step(scale_notes, from_pitch, diff > 0 and 1 or -1)
    if passing ~= from_pitch and passing ~= to_pitch then return passing end
  end

  -- 4. Diatonic passing run when notes are a third apart.
  if math.abs(diff) == 3 or math.abs(diff) == 4 then
    return voicing.diatonic_step(scale_notes, from_pitch, diff > 0 and 1 or -1)
  end

  return nil
end

-- ----------------------------------------------------------------
--  MELODY GENERATORS
--  Each returns a flat list of {pitch, pos, dur, vel, is_rest}
--  for a single chord block. pos is relative to block start.
-- ----------------------------------------------------------------

local function mel_pick_vel()
  local v = p.velocity + math.floor((rng.rng_float()*2-1) * p.vel_human)
  return math.max(1, math.min(127, v))
end

local function mel_min_beats() return p.min_dur_beats end
local function mel_max_beats() return p.max_dur_beats end

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
  local scale_pcs = context.scale_pcs_chord or voicing.scale_pc_set(p.mode, p.root_idx)
  local chord_pcs = voicing.chord_pc_set(chord_notes)
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
    local space = (p.space or 0) / 100.0
    rest_p = rest_p + space * 75.0 * (1.0 - 0.5 * mw)
    if first_onset    then rest_p = 0 end
    if mw >= 0.95     then rest_p = rest_p * 0.25 end

    if rng.rng_float() * 100 < rest_p then
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
           and (snap_p >= 1.0 or rng.rng_float() < snap_p) then
          local sk = context.block_skeleton
          if not voicing.is_chord_tone(pitch, chord_pcs) or math.abs(pitch - sk) > 4 then
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
           and not voicing.is_chord_tone(pitch, chord_pcs)
           and rng.rng_float() < landing_p * landing_scale then
          pitch = voicing.nearest_chord_tone(pitch, chord_range)
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
      local cadence = (p.cadence or 60) / 100.0
      if cadence > 0.5 and rng.rng_float() < (cadence - 0.5) * 0.8 then
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
    local cell_len      = rng.rng_int(3, 5)
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
    cell[1] = { idx_offset = 0, dur_slots = rh[rng.rng_int(1, #rh)] }
    for i = 2, cell_len do
      idx_off = idx_off + interval_pool[rng.rng_int(1, #interval_pool)]
      cell[i] = { idx_offset = idx_off, dur_slots = rh[rng.rng_int(1, #rh)] }
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
    ctx_tbl.motif_anchor_idx = chord.nearest_idx(scale_notes,
      ctx_tbl.block_skeleton or scale_notes[math.ceil(#scale_notes/2)])
    ctx_tbl.motif_block_n   = (ctx_tbl.motif_block_n or 0) + 1
    -- Light variation every 4 blocks: invert intervals OR retrograde.
    if ctx_tbl.motif_block_n % 4 == 0 then
      if rng.rng_float() < 0.5 then
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
    local anchor    = c.motif_anchor_idx or chord.nearest_idx(sn, prev)
    local natural_i = math.max(1, math.min(#sn, anchor + off))
    local idx       = natural_i

    -- Cadential bend: at high cadence, pull the very last cell note
    -- toward next_skeleton by up to ±2 scale steps — *preserving the
    -- cell's rhythm* — instead of overwriting it with surface_step.
    -- The motif keeps its profile; only the final interval bends.
    if c.is_final_onset_of_block and c.is_phrase_end and c.next_skeleton then
      local cadence = (p.cadence or 60) / 100.0
      if cadence > 0.5 then
        local target_i = chord.nearest_idx(sn, c.next_skeleton)
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
    ctx_tbl.mech_interval  = intervals[rng.rng_int(1, #intervals)]
    ctx_tbl.mech_direction = 1
  end
  local cadence = (p.cadence or 60) / 100.0
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
      if rng.rng_float() < cadence then return c.block_skeleton or prev end
      -- fall through to alternation
    end
    -- Cadence-softened final approach into the next chord — kept,
    -- because this is the audible cadence figure even at mid cadence.
    if c.is_final_onset_of_block and c.next_skeleton then
      if rng.rng_float() < cadence then
        return surface_step(prev, c.next_skeleton, sn, true, c.is_phrase_end, c)
      end
    end
    local idx  = chord.nearest_idx(sn, prev)
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
  local pedal_pc = (p.root_idx - 1) % 12

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

  local busy = (p.busyness or 50) / 100.0

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
    local up = voicing.diatonic_step(sn, pedal,  1)
    local dn = voicing.diatonic_step(sn, pedal, -1)
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
      local outward = voicing.diatonic_step(sn, prev_pitch,  out_dir)
      local inward  = voicing.diatonic_step(sn, prev_pitch, -out_dir)
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
    if total <= 0 then return cands[rng.rng_int(1, #cands)].p end
    local r = rng.rng_float() * total
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

    if rng.rng_float() > depart_p then
      -- Hold / return to the pedal — but on a weak beat, occasionally
      -- lift it an octave so the anchor breathes across registers
      -- without losing its identity.
      local p = pedal
      if mw < 0.6 and rng.rng_float() < 0.08 then
        local cand = p + ((rng.rng_float() < 0.5) and 12 or -12)
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
      local dir = (rng.rng_float() < 0.5) and 1 or -1
      return voicing.diatonic_step(sn, pedal, dir)
    elseif c.chord_range and #c.chord_range > 0 then
      return voicing.nearest_chord_tone(pedal, c.chord_range)
    else
      local dir = (rng.rng_float() < 0.5) and 1 or -1
      return voicing.diatonic_step(sn, pedal, dir)
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
        local sk_idx    = chord.nearest_idx(sn, rec.skeleton or p)
        local pitch_idx = chord.nearest_idx(sn, p)
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
  local busy    = (p.busyness or 50) / 100.0
  local cadence = (p.cadence or 60) / 100.0

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

    local sk_idx = chord.nearest_idx(sn, c.block_skeleton or prev)
    local off    = entry.idx_offset
    -- Subtle interior variation: with prob ∝ busyness, displace by ±1.
    if cursor > 1 and cursor < #entries and rng.rng_float() < busy * 0.20 then
      off = off + ((rng.rng_float() < 0.5) and 1 or -1)
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
  local gen_fn = MEL_GEN_FNS[p.preset_idx] or MEL_GEN_FNS[1]
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
  local phrases  = plan_phrases(progression, p.timesig_num)
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
        voicing.chord_scale_pc_set(ch.notes, ch.root_midi, voicing.scale_pc_set(p.mode, p.root_idx))
    local lo_p, hi_p   = mel_window(ch.root_midi)

    -- Phrasing reshapes the per-chord scale pool. Bluesy adds the b3/b7
    -- so the walker can land on them (not just slide through); Pentatonic
    -- restricts the pool to a 5-note subset unioned with the chord's tones
    -- so chord-tone landings on 3rds/7ths still work even when those
    -- aren't in the pentatonic.
    local chord_root_pc = (ch.root_midi or 0) % 12
    local phrasing      = p.phrasing_idx or 1
    if phrasing == 2 then  -- Bluesy
      chord_scale_pcs[(chord_root_pc + 3)  % 12] = true   -- b3 (blue 3rd)
      chord_scale_pcs[(chord_root_pc + 10) % 12] = true   -- b7 (dom 7)
    elseif phrasing == 3 then  -- Pentatonic
      local pent_pcs = voicing.pentatonic_pcs_for(
        (p.root_idx - 1) % 12, p.mode)
      local chord_pcs_local = voicing.chord_pc_set(ch.notes)
      local kept = {}
      for pc in pairs(chord_scale_pcs) do
        if pent_pcs[pc] or chord_pcs_local[pc] then kept[pc] = true end
      end
      if next(kept) then chord_scale_pcs = kept end
    end

    local scale_notes  = voicing.pcs_to_notes_in_range(chord_scale_pcs, lo_p, hi_p)
    local chord_range  = chord.chord_notes_in_range(ch.notes, lo_p, hi_p)
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
function M.build_events(progression, params)
  p = params
  local context = {}
  local events  = {}
  local abs_end = build_melody_cycle(progression, context, events, 0)
  return events, abs_end
end

-- Live preview / multi-cycle render entry point. The host passes its own
-- persistent `context` and `events` tables so RNG state and phrase-arc
-- bookkeeping survive across cycles.
function M.build_cycle(progression, context, events, cycle_offset, params)
  p = params
  return build_melody_cycle(progression, context, events, cycle_offset)
end

return M
