-- ---------------------------------------------------------------------------
-- host_vst.lua  —  Phase 1 stub
--
-- This module is the *only* surface the C++ shim talks to. In phase 1 it
-- just returns a hardcoded C-major chord so we can prove the
-- JUCE -> sol2 -> Lua roundtrip works inside the plugin.
--
-- Phase 2 will:
--   * pull in the host-agnostic `core/` extracted from `cordial.lua`
--     (music theory tables, PROGRESSIONS, build_progression, MEL_GEN_FNS, ...)
--   * accept a parameter struct from the host
--   * return a full timeline of `{tick, note, vel, len, channel}` events
--     for the C++ side to dispatch.
--
-- Keep this file *host-only*. Pure-music logic belongs in `core/`.
-- ---------------------------------------------------------------------------

local M = {}

-- Phase 1 sanity check: returns C major (C4, E4, G4) with full velocity
-- and a one-bar duration expressed in beats. The C++ side converts beats
-- to samples using the live playhead BPM.
function M.phase1_chord()
    return {
        notes        = { 60, 64, 67 },   -- C4 E4 G4
        velocity     = 100,
        length_beats = 4.0,              -- one bar at 4/4
    }
end

-- Hook for the C++ shim to verify Lua is alive without doing real work.
function M.ping()
    return "pong from Lua " .. _VERSION
end

return M
