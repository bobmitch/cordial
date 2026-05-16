-- ---------------------------------------------------------------------------
-- host_vst.lua  —  the VST plugin's adapter onto core/
--
-- This is the *only* Lua file the C++ shim talks to directly. Any pure
-- music logic belongs in core/. Anything specific to how the VST plugin
-- shapes parameters or surfaces events to JUCE belongs here.
--
-- Phase 3: generate(params) is the main entry point. It accepts a flat
-- params table (same field names as core.chord.build_progression) and
-- returns an array of {pos_beats, note, vel, dur_beats, channel} events.
-- ---------------------------------------------------------------------------

local core = require 'core'

local M = {}

-- Phase 3 entry point. `params` is a flat table; all fields optional with
-- musically sensible defaults. Returns an array of event records that the
-- C++ side converts to sample-accurate MIDI in processBlock.
--
-- Event record: { pos_beats, note, vel, dur_beats, channel }
--   pos_beats  — beat position relative to generation start (0 = first note)
--   note       — MIDI pitch 0..127
--   vel        — MIDI velocity 1..127
--   dur_beats  — sounding length in beats (note-off sent at pos_beats + dur_beats)
--   channel    — MIDI channel 1..16
function M.generate(params)
    local prog = core.chord.build_progression {
        mode              = params.mode or "major",
        root_idx          = params.root_idx or 1,
        octave            = params.octave or 4,
        timesig_num       = params.timesig_num or 4,
        degrees           = params.degrees or {1, 4, 5, 1},
        quality_overrides = params.quality_overrides,
        inversions        = params.inversions,
        bass_overrides    = params.bass_overrides,
        durations         = params.durations,
        smart_voicing     = params.smart_voicing ~= false,
    }

    local events = {}
    local pos    = 0.0

    for _, slot in ipairs(prog) do
        -- `slot.voicing` includes the slash bass note when present.
        -- For basic degrees without slash bass, voicing == notes.
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

-- Diagnostic for the editor. Reports Lua version + a couple of facts
-- about the loaded core so a regression in the preload wiring is
-- visible at a glance.
function M.ping()
    return string.format("pong from Lua %s (core: %d progressions, NOTE_NAMES[1]=%s)",
                         _VERSION,
                         #core.progressions.PROGRESSIONS,
                         core.theory.NOTE_NAMES[1])
end

return M
