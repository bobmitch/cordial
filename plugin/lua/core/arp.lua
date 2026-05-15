-- ----------------------------------------------------------------
--  core/arp.lua  —  arpeggiator pool and pattern transforms
--
--  Two host-agnostic primitives:
--    * build_arp_pool — gathers playable pitches for an arp across an
--      octave range, biased by rigidity toward chord tones vs. the
--      surrounding scale.
--    * apply_arp_pattern — transforms a pitch pool into the order the
--      arp plays it (Up / Down / Up-Down / Random / Pedal / Skip /
--      Alberti / Random Walk / etc.).
--
--  The host-stateful surrounding logic (`build_arp_events`,
--  `resolve_step_prob`) stays in host_reaper.lua until Phase 3
--  defines the params struct.
-- ----------------------------------------------------------------

local rng = rng or require 'core.rng'

local M = {}

-- Build the pool of pitches the arp draws from. Chord tones are always
-- included; non-chord scale tones are added with probability
-- `rigidity_pct/100` (so rigidity=100 → chord tones only).
--
-- Caller MUST supply `chord_scale_pcs` — a set keyed by pitch class
-- (0..11) of the scale to consider. In Cordial that's typically the
-- chord-aware scale (chord tones + global mode, conflicts resolved).
function M.build_arp_pool(chord_notes, oct_low, oct_high, rigidity_pct,
                          chord_scale_pcs)
  if #chord_notes == 0 then return {} end
  local chord_set = {}
  for _, n in ipairs(chord_notes) do chord_set[n % 12] = true end
  local scale_prob = rigidity_pct / 100.0
  local pool_set   = {}
  for oct = oct_low, oct_high do
    for pc = 0, 11 do
      local pitch = oct * 12 + pc
      if pitch >= 0 and pitch <= 127 then
        if chord_set[pc] then
          pool_set[pitch] = true
        elseif chord_scale_pcs[pc] and scale_prob > 0 then
          if rng.rng_float() < scale_prob then pool_set[pitch] = true end
        end
      end
    end
  end
  local pool = {}
  for pitch, _ in pairs(pool_set) do pool[#pool+1] = pitch end
  table.sort(pool)
  return pool
end

-- Transform a sorted pitch pool into the play sequence. Patterns that
-- need randomness consume entries from `rng_seq` (pre-generated floats
-- in [0, 1)) so the same seed produces the same shuffle.
function M.apply_arp_pattern(pool, pattern_name, rng_seq)
  if pattern_name == "Up" then return pool
  elseif pattern_name == "Down" then
    local r = {}
    for i = #pool, 1, -1 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Up-Down" then
    local r = {}
    for _, n in ipairs(pool) do r[#r+1] = n end
    for i = #pool-1, 2, -1 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Down-Up" then
    local r = {}
    for i = #pool, 1, -1 do r[#r+1] = pool[i] end
    for i = 2, #pool-1 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Random" then
    local r = {}
    for _, n in ipairs(pool) do r[#r+1] = n end
    for i = #r, 2, -1 do
      local j = math.max(1, math.floor(rng_seq[i] * i) + 1)
      r[i], r[j] = r[j], r[i]
    end
    return r
  elseif pattern_name == "Weave" then
    -- two forward, one back: 1,3,2,4,3,5,4,6...
    local r = {}
    for i = 1, #pool - 2 do
      r[#r+1] = pool[i]
      r[#r+1] = pool[i + 2]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Down-Weave" then
    -- mirror of Weave from the top: N, N-2, N-1, N-3, N-2, N-4...
    local r = {}
    for i = #pool, 3, -1 do
      r[#r+1] = pool[i]
      r[#r+1] = pool[i - 2]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Pedal" then
    -- root pedal between each upper note: 1,2,1,3,1,4,1,5...
    local r = {}
    for i = 2, #pool do
      r[#r+1] = pool[1]
      r[#r+1] = pool[i]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Top Pedal" then
    -- top note pedal between each lower note: N,N-1,N,N-2,N,N-3...
    local r = {}
    for i = #pool - 1, 1, -1 do
      r[#r+1] = pool[#pool]
      r[#r+1] = pool[i]
    end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Converge" then
    -- outside-in: 1,N,2,N-1,3,N-2...
    local r = {}
    local lo, hi = 1, #pool
    while lo < hi do
      r[#r+1] = pool[lo]
      r[#r+1] = pool[hi]
      lo = lo + 1
      hi = hi - 1
    end
    if lo == hi then r[#r+1] = pool[lo] end
    if #r == 0 then return pool end
    return r
  elseif pattern_name == "Skip" then
    -- odd indices then even: 1,3,5..., 2,4,6... (diatonic thirds)
    local r = {}
    for i = 1, #pool, 2 do r[#r+1] = pool[i] end
    for i = 2, #pool, 2 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Skip-Reverse" then
    -- descending broken thirds: N,N-2,N-4..., N-1,N-3,N-5...
    local r = {}
    for i = #pool, 1, -2 do r[#r+1] = pool[i] end
    for i = #pool - 1, 1, -2 do r[#r+1] = pool[i] end
    return r
  elseif pattern_name == "Diverge" then
    -- inside-out: middle outward (mirror of Converge)
    if #pool == 0 then return pool end
    local r = {}
    local n = #pool
    local lo, hi
    if n % 2 == 1 then
      local m = math.floor(n / 2) + 1
      r[#r+1] = pool[m]
      lo, hi = m - 1, m + 1
    else
      lo = n / 2; hi = lo + 1
      r[#r+1] = pool[lo]; r[#r+1] = pool[hi]
      lo = lo - 1; hi = hi + 1
    end
    while lo >= 1 do
      r[#r+1] = pool[lo]; r[#r+1] = pool[hi]
      lo = lo - 1; hi = hi + 1
    end
    return r
  elseif pattern_name == "Alberti" then
    -- Classical keyboard figure (root, fifth, third, fifth), confined to a
    -- single octave above pool[1] so the figure reads as Alberti rather than
    -- wide multi-octave leaps. Falls back to a root-top alternation when the
    -- pool doesn't have three distinct notes inside that window.
    if #pool < 2 then return pool end
    local lo = pool[1]
    local window = {}
    for _, p in ipairs(pool) do
      if p < lo + 12 then window[#window+1] = p else break end
    end
    if #window < 3 then
      local top = window[#window] or pool[#pool]
      return {lo, top, lo, top}
    end
    local top = window[#window]
    local mid = window[math.ceil(#window / 2)]
    return {lo, top, mid, top}
  elseif pattern_name == "Random Walk" then
    -- stepwise random motion through pool; smoother than pure Random
    if #pool == 0 then return pool end
    local r = {}
    local idx = math.floor((#pool + 1) / 2)
    if idx < 1 then idx = 1 end
    for i = 1, #rng_seq do
      r[#r+1] = pool[idx]
      local u = rng_seq[i]
      local step
      if u < 0.45 then step = 1
      elseif u < 0.9 then step = -1
      else step = 0
      end
      local nx = idx + step
      if nx < 1 or nx > #pool then nx = idx - step end
      idx = nx
    end
    return r
  end
  return pool
end

return M
