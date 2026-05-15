#!/usr/bin/env lua
-- ----------------------------------------------------------------
--  bundle-cordial.lua  —  build script for the REAPER product
--
--  Concatenates plugin/lua/core/*.lua (in dependency order) with
--  plugin/lua/host_reaper.lua into repo-root cordial.lua. Each core
--  module is wrapped in an IIFE so its `return M` becomes the value
--  of a top-level local; host_reaper.lua then aliases the relevant
--  exports back to bare locals so the bulk of the REAPER code reads
--  unchanged.
--
--  cordial.lua is a GENERATED ARTIFACT. The bundler stamps a
--  "do not edit by hand" header on every run.
--
--  Usage (run from repo root):
--    lua plugin/scripts/bundle-cordial.lua
-- ----------------------------------------------------------------

-- Dependency order: theory has no deps, everything below assumes
-- theory is already in scope. Append new modules as Phase 2 progresses.
local CORE_MODULES = {
  "theory",
  "progressions",
  "rng",
}

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then error("bundle-cordial: cannot read " .. path .. ": " .. tostring(err)) end
  local body = f:read("*a")
  f:close()
  return body
end

local function emit_iife(name, body)
  return string.format(
    "-- ================================================================\n" ..
    "--  bundled from plugin/lua/core/%s.lua\n" ..
    "-- ================================================================\n" ..
    "local %s = (function()\n%send)()\n\n",
    name, name, body
  )
end

local parts = {}

table.insert(parts,
  "-- ================================================================\n" ..
  "--  cordial.lua  —  AUTO-GENERATED, DO NOT EDIT BY HAND\n" ..
  "--\n" ..
  "--  Run `lua plugin/scripts/bundle-cordial.lua` from the repo root\n" ..
  "--  to regenerate. Source modules:\n" ..
  "--    plugin/lua/core/*.lua    (host-agnostic music engine)\n" ..
  "--    plugin/lua/host_reaper.lua  (REAPER glue: UI, MIDI, persist)\n" ..
  "-- ================================================================\n\n"
)

for _, name in ipairs(CORE_MODULES) do
  local body = read_file(string.format("plugin/lua/core/%s.lua", name))
  table.insert(parts, emit_iife(name, body))
end

table.insert(parts, read_file("plugin/lua/host_reaper.lua"))

local out, err = io.open("cordial.lua", "w")
if not out then error("bundle-cordial: cannot write cordial.lua: " .. tostring(err)) end
out:write(table.concat(parts))
out:close()

io.write(string.format(
  "Bundled cordial.lua (%d core module(s) + host_reaper.lua)\n",
  #CORE_MODULES
))
