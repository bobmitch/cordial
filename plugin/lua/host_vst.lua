-- ---------------------------------------------------------------------------
-- host_vst.lua  —  the VST plugin's adapter onto core/
--
-- This is the *only* Lua file the C++ shim talks to directly. Any pure
-- music logic belongs in core/. Anything specific to how the VST plugin
-- shape parameters or surfaces events to JUCE belongs here.
--
-- Phase 2k status: core modules wired in. phase1_chord() still returns
-- the demo C-major chord (so the audio output is unchanged from Phase 1),
-- but the chord notes now come from core.chord.build_progression rather
-- than a hardcoded literal. Phase 3 will replace this with a full
-- parameter struct binding and event-list return.
-- ---------------------------------------------------------------------------

local core = require 'core'

local M = {}

-- Phase 1/2 sanity check. Same C-E-G output as Phase 1, now sourced from
-- core.chord.build_progression so the round-trip C++ → preload → require
-- → core.chord → build_progression → table-return → C++ is exercised.
function M.phase1_chord()
    local prog = core.chord.build_progression {
        mode = "major", root_idx = 1, octave = 4,
        timesig_num = 4, smart_voicing = false,
        degrees = {1}, durations = {1},
    }
    return {
        notes        = prog[1].notes,    -- C4 E4 G4
        velocity     = 100,
        length_beats = 4.0,              -- one bar at 4/4
    }
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
