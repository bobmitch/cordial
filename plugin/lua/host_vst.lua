-- ---------------------------------------------------------------------------
-- host_vst.lua  —  VST plugin adapter onto core/
--
-- The only Lua file the C++ shim talks to. All music logic lives in core/.
-- Phase 5: generate() resolves a PROGRESSIONS catalog preset by index so the
-- user's root/preset/octave/seed parameters flow end-to-end from DAW → Lua.
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
--   progression_idx  int   1-based index into PROGRESSIONS; 0 = use params.degrees
--   root_idx         int   1=C … 12=B (key root, always honoured)
--   octave           int   voicing octave for the lowest chord tone
--   timesig_num      int   beats per bar
--   smart_voicing    bool  voice-leading inversion picker
--   seed             int   RNG seed (stored, used by arp/melody in later phases)
--   mode             str   fallback mode when progression_idx == 0
--   degrees          array fallback degrees when progression_idx == 0
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

    local prog = core.chord.build_progression {
        mode              = mode,
        root_idx          = params.root_idx or 1,
        octave            = params.octave or 4,
        timesig_num       = params.timesig_num or 4,
        degrees           = degrees,
        quality_overrides = quality_overrides,
        durations         = durations,
        smart_voicing     = params.smart_voicing ~= false,
    }

    local events = {}
    local pos    = 0.0

    for _, slot in ipairs(prog) do
        for _, note in ipairs(slot.voicing) do
            events[#events + 1] = {
                pos_beats = pos,
                note      = note,
                vel       = 100,
                dur_beats = slot.duration,
                channel   = 1,
            }
        end
        pos = pos + slot.duration
    end

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
