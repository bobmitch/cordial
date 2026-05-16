-- ---------------------------------------------------------------------------
-- host_vst.lua  —  VST plugin adapter onto core/
--
-- The only Lua file the C++ shim talks to. All music logic lives in core/.
-- Phase 6: generate() drives both the chord layer (channel 1) and the arp
-- layer (channel 2); each is gated by params.chord_enabled / params.arp_enabled.
-- ---------------------------------------------------------------------------

local core = require 'core'

local M = {}

-- ---------------------------------------------------------------------------
-- get_presets() → array of {name, cat}
--
-- Called once at plugin construction (main thread, before worker starts) so
-- the C++ side can build the AudioParameterChoice list without touching Lua
-- again. Array is 1-based; index i maps to PROGRESSIONS[i].
-- ---------------------------------------------------------------------------
function M.get_presets()
    local result = {}
    for _, p in ipairs(core.progressions.PROGRESSIONS) do
        result[#result + 1] = { name = p.name or "", cat = p.cat or "" }
    end
    return result
end

-- ---------------------------------------------------------------------------
-- generate(params) → array of {pos_beats, note, vel, dur_beats, channel}
--
-- params fields (all optional with defaults):
--   progression_idx  int    1-based index into PROGRESSIONS; 0 = use params.degrees
--   root_idx         int    1=C … 12=B (key root, always honoured)
--   octave           int    voicing octave for the lowest chord tone
--   timesig_num      int    beats per bar
--   smart_voicing    bool   voice-leading inversion picker
--   seed             int    RNG seed (re-seeded before stochastic layers)
--   mode             str    fallback mode when progression_idx == 0
--   degrees          array  fallback degrees when progression_idx == 0
--   chord_enabled    bool   emit chord layer on channel 1 (default true)
--   arp_enabled      bool   emit arp layer on channel 2 (default false)
--   arp_pattern      str    pattern name ("Up", "Down", …)
--   arp_rate_beats   number step rate in beats (e.g. 0.25 = 1/16)
--   arp_octaves      int    number of octaves in arp pool (1..3)
--   arp_rigidity     int    0..100 — 0 = chord tones only passed to build_arp_pool
--   mel_enabled      bool   reserved (melody generation — later phase)
-- ---------------------------------------------------------------------------
function M.generate(params)
    local mode            = params.mode or "major"
    local degrees         = params.degrees or {1, 4, 5, 1}
    local quality_overrides = params.quality_overrides
    local durations       = params.durations

    -- When a preset index is given, pull mode/degrees/qualities from the
    -- PROGRESSIONS catalog. Root note (root_idx) is still the user's choice.
    local idx = params.progression_idx or 0
    if idx > 0 then
        local preset = core.progressions.PROGRESSIONS[idx]
        if preset then
            mode             = preset.mode     or mode
            degrees          = preset.degrees  or degrees
            quality_overrides = preset.qualities
            durations        = nil  -- preset doesn't encode durations; use default 1-bar each
        end
    end

    -- Seed RNG before any stochastic layers (arp, melody).
    core.rng.rng_seed(params.seed or 1)

    local prog = core.chord.build_progression {
        mode              = mode,
        root_idx          = params.root_idx or 1,
        octave            = params.chord_octave or 4,
        timesig_num       = params.timesig_num or 4,
        degrees           = degrees,
        quality_overrides = quality_overrides,
        durations         = durations,
        smart_voicing     = params.smart_voicing ~= false,
    }

    local events = {}
    local pos    = 0.0

    for _, slot in ipairs(prog) do
        -- Chord layer (channel 1)
        if params.chord_enabled ~= false then
            for _, note in ipairs(slot.voicing) do
                events[#events + 1] = {
                    pos_beats = pos, note = note, vel = 100,
                    dur_beats = slot.duration, channel = 1,
                }
            end
        end

        -- Arp layer (channel 2)
        if params.arp_enabled then
            local global_pcs = core.voicing.scale_pc_set(mode, params.root_idx or 1)
            local chord_scale_pcs = core.voicing.chord_scale_pc_set(
                slot.notes, slot.root_midi, global_pcs)
            local oct_low  = params.arp_oct_low  or 4
            local oct_high = params.arp_oct_high or 5
            -- Invert: UI arp_rigidity 100 (chord-tones only) → Lua rigidity 0.
            -- UI arp_rigidity 0 (all scale tones) → Lua rigidity 100.
            local rigidity_pct = 100 - (params.arp_rigidity or 0)
            local slot_evs = core.arp.build_events(
                slot.notes, slot.duration, pos, slot.root_midi, {
                    rate_beats        = params.arp_rate_beats or 0.25,
                    pattern           = params.arp_pattern or "Up",
                    gate              = 80,
                    velocity          = 90,
                    vel_human         = 10,
                    oct_low           = math.min(oct_low, oct_high),
                    oct_high          = math.max(oct_low, oct_high),
                    rigidity          = rigidity_pct,
                    chord_scale_pcs   = chord_scale_pcs,
                    timesig_num       = params.timesig_num or 4,
                    accent_grid_beats = 1.0,
                    beat1_prob        = 100,
                    beatn_prob        = 100,
                    note_prob         = 100,
                })
            for _, ev in ipairs(slot_evs) do
                events[#events + 1] = {
                    pos_beats = pos + ev.pos, note = ev.pitch,
                    vel = ev.vel, dur_beats = ev.dur, channel = 2,
                }
            end
        end

        pos = pos + slot.duration
    end

    -- Melody layer (channel 3)
    if params.mel_enabled then
        local mel_oct = params.mel_octave or 4
        local mel_params = {
            preset_idx      = params.mel_preset    or 1,
            phrasing_idx    = 1,        -- Normal (diatonic)
            -- anchor_mode = 1 (key root) so melody honours its own octave;
            -- mode 2 (chord root) would tie melody to the chord layer's register.
            anchor_mode     = 1,
            anchor_oct      = mel_oct,
            range_down      = 7,
            range_up        = 14,
            min_dur_beats   = 0.25,
            max_dur_beats   = 2.0,
            velocity        = 80,
            vel_human       = 12,
            busyness        = params.mel_busyness or 50,
            cadence         = params.mel_cadence  or 60,
            space           = 0,
            rhythm_rigidity = 0,
            root_idx        = params.root_idx or 1,
            mode            = mode,
            octave          = mel_oct,
            timesig_num     = params.timesig_num or 4,
            seed            = params.seed or 1,
        }
        local mel_evs = core.melody.build_events(prog, mel_params)
        for _, ev in ipairs(mel_evs) do
            events[#events + 1] = {
                pos_beats = ev.pos, note = ev.pitch,
                vel = ev.vel, dur_beats = ev.dur, channel = 3,
            }
        end
    end

    -- Sort by beat position so the C++ drain-loop scans forward correctly.
    table.sort(events, function(a, b)
        if a.pos_beats ~= b.pos_beats then return a.pos_beats < b.pos_beats end
        return a.channel < b.channel
    end)

    return events
end

-- Diagnostic — reports Lua version + core vitals. Safe for main thread only.
function M.ping()
    return string.format("pong from Lua %s (core: %d progressions, NOTE_NAMES[1]=%s)",
                         _VERSION,
                         #core.progressions.PROGRESSIONS,
                         core.theory.NOTE_NAMES[1])
end

return M
