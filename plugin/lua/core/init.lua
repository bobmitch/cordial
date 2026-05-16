-- ----------------------------------------------------------------
--  core/init.lua  —  public surface of the host-agnostic music engine
--
--  Convenience aggregator: `local core = require 'core'` gives you
--  everything in one table. Inside the bundled REAPER cordial.lua each
--  module is already in scope as a top-level local from the bundler's
--  IIFE chain, so this file is mostly for non-REAPER hosts (VST plugin,
--  standalone testing). The `X or require 'core.X'` pattern lets it
--  work in both contexts.
-- ----------------------------------------------------------------

local M = {}

M.theory       = theory       or require 'core.theory'
M.progressions = progressions or require 'core.progressions'
M.rng          = rng          or require 'core.rng'
M.chord        = chord        or require 'core.chord'
M.arp          = arp          or require 'core.arp'
M.voicing      = voicing      or require 'core.voicing'
M.bass         = bass         or require 'core.bass'
M.melody       = melody       or require 'core.melody'

return M
