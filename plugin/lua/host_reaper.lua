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

-- scale_pc_set / chord_scale_pc_set wrappers live further down,
-- AFTER the `state` table is declared. They reference state.* and
-- Lua resolves upvalues at function-definition time, so defining them
-- here would bind `state` to a global lookup (nil) instead of the
-- host-side local. Tripped over by a real error in REAPER.


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

-- Host-side wrappers around voicing.scale_pc_set / chord_scale_pc_set.
-- Must be defined AFTER `state` is in scope (see note in the import
-- block at the top of this file) — Lua resolves upvalues lexically at
-- function-definition time.
local function scale_pc_set()
  return voicing.scale_pc_set(MODE_NAMES[state.mode_idx], state.root_idx)
end
local function chord_scale_pc_set(chord_notes, chord_root_midi)
  return voicing.chord_scale_pc_set(chord_notes, chord_root_midi, scale_pc_set())
end

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

-- ----------------------------------------------------------------
--  MELODY — host wrapper around core/melody.lua
-- ----------------------------------------------------------------
local function mel_params()
  return {
    anchor_mode      = state.mel_anchor_mode or 2,
    anchor_oct       = state.mel_anchor_oct or 4,
    range_down       = state.mel_range_down or 7,
    range_up         = state.mel_range_up or 14,
    min_dur_beats    = MEL_DURATIONS[state.mel_min_dur_idx].beats,
    max_dur_beats    = MEL_DURATIONS[state.mel_max_dur_idx].beats,
    velocity         = state.mel_velocity,
    vel_human        = state.mel_vel_human,
    busyness         = state.mel_busyness or 50,
    cadence          = state.mel_cadence or 60,
    metre            = state.mel_metre,
    space            = state.mel_space or 0,
    rhythm_rigidity  = state.mel_rhythm_rigidity or 0,
    colour           = state.mel_colour or 30,
    preset_idx       = state.mel_preset_idx,
    phrasing_idx     = state.mel_phrasing_idx or 1,
    root_idx         = state.root_idx,
    mode             = MODE_NAMES[state.mode_idx],
    octave           = state.octave,
    timesig_num      = state.timesig_num,
    seed             = state.seed,
  }
end

local function build_melody_events(progression)
  return melody.build_events(progression, mel_params())
end


-- ----------------------------------------------------------------
--  ARP — host wrapper around core/arp.lua
--  (build_arp_pool, apply_arp_pattern, build_events all live in core)
-- ----------------------------------------------------------------
local function build_arp_events(chord_notes, chord_dur_beats, chord_abs_beat,
                                chord_root_midi)
  return arp.build_events(chord_notes, chord_dur_beats, chord_abs_beat,
                          chord_root_midi, {
    rate_beats        = ARP_RATES[state.arp_rate_idx].beats,
    pattern           = ARP_PATTERNS[state.arp_pattern_idx],
    gate              = state.arp_gate,
    velocity          = state.arp_velocity,
    vel_human         = state.arp_vel_human,
    oct_low           = state.arp_oct_low,
    oct_high          = state.arp_oct_high,
    rigidity          = state.arp_rigidity,
    chord_scale_pcs   = chord_scale_pc_set(chord_notes, chord_root_midi),
    timesig_num       = state.timesig_num,
    accent_grid_beats = ACCENT_GRID[state.arp_beatn_idx].beats,
    beat1_prob        = state.arp_beat1_prob,
    beatn_prob        = state.arp_beatn_prob,
    note_prob         = state.arp_note_prob,
  })
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
    state.mel_live_total_beats = melody.build_cycle(
      progression, state.mel_live_context, state.mel_live_events, 0, mel_params())
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
    state.mel_live_total_beats = melody.build_cycle(
      progression,
      state.mel_live_context,
      state.mel_live_events,
      state.mel_live_total_beats,
      mel_params())
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
    local mp = mel_params()
    for _ = 1, cycles do
      abs_pos = melody.build_cycle(progression, context, mel_evs, abs_pos, mp)
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
