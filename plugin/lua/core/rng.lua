-- ----------------------------------------------------------------
--  core/rng.lua  —  seeded random helpers
--
--  Thin wrappers over Lua's math.random so every generator in core/
--  threads through a single deterministic stream. The seed contract
--  for Cordial is non-negotiable: same seed + same params →
--  identical output. Do not introduce bare math.random() calls in
--  core/ that bypass these helpers.
-- ----------------------------------------------------------------

local M = {}

function M.rng_seed(s) math.randomseed(s) end
function M.rng_float() return math.random() end
function M.rng_int(a, b) return math.random(a, b) end

-- Derive an independent-but-deterministic seed from a base seed. Used to
-- give a layer (e.g. bass) its own RNG stream that depends on the user's
-- seed but doesn't share state with the chord/arp/melody stream.
function M.derive_seed(base)
  return (base * 1664525 + 1013904223) % 99991 + 1
end

return M
