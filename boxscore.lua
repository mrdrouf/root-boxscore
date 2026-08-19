-- Root Box Score
-- Automated per-turn scorekeeping for Root - Ultimate Collection (workshop 2516434159).
--
-- Score reading (no vision): every faction's VP marker is a named object
-- ("Marquise VP", ...). The map token carries the printed 0-30 track as snap
-- points (31 columns x 3 sub-rows on every map checked), found geometrically
-- in the map's LOCAL coordinates - any map, anywhere, any rotation. A marker's
-- score is the nearest track column to positionToLocal(marker position).
--
-- Turn integration: with the TTS turn system running, row order mirrors the
-- turn order, the active faction follows Turns.turn_color, and every turn pass
-- locks the score of the faction whose turn just ended. Seats are matched to
-- factions by hand zone <-> "<Faction> Supply" distance (the supply bag sits
-- with the faction board in front of its player), which also fills in player
-- names. Without the turn system, rows order themselves clockwise by seat and
-- END TURN cycles them manually.
--
-- The object IS the sheet: the walnut slab resizes itself to exactly match
-- the rendered scoresheet (TTS object UI renders at 250 px per world unit),
-- and every non-interactive element lets clicks through, so grabbing anywhere
-- that is not a button drags the cardboard.
--
-- Silent by design: nothing is written to chat in normal play. DIAGNOSE
-- (right-click menu) is the only thing that ever broadcasts.

------------------------------------------------------------------ constants --
local BUILD = "dev"
local POLL_SECONDS   = 1.2
local SNAP_MIN       = 40
local ROW_TOL        = 0.13
local COL_TOL        = 0.45
local MIN_CELLS      = 28
local MAX_CELLS      = 60
local PX_PER_UNIT    = 100    -- TTS object-UI render density (measured on a
                              -- live table: the sheet drew 2.5x larger than a
                              -- slab sized with the documented 250)
local BASE_SCALE     = 3.85    -- sheet size multiplier at size 1.0

-- palette: walnut board, parchment sheet, ink, rust and wax-seal gold
local WALNUT  = "#2B1A0C"
local PARCH   = "#F1E5C8"
local PARCH2  = "#E7D8B4"
local GOLD    = "#C9A05C"
local GOLDHI  = "#E4C88E"
local INKTXT  = "#26170B"
local RUST    = "#7E4A1E"

local DECKS = { "Base Deck", "Exiles and Partisans", "Squires and Disciples" }

-- the group's map pool, offered as one-click chips in setup
local MAPS = { "Summer", "Winter", "Lake", "Mountain", "Marsh", "Gorge" }

-- card-back artwork -> deck (extracted from the mod's own deck definitions)
local DECK_BACKS = {
  ["CAF7209CF51CE857"] = "Base Deck",
  ["2EEC952526C7E80D"] = "Exiles and Partisans",
  ["CD47EFAA7F885F2A"] = "Squires and Disciples",
}

-- vagabond characters / captains, for the per-row variant auto-detect
local CHARS = { "Thief", "Tinker", "Ranger", "Vagrant", "Arbiter", "Scoundrel",
  "Adventurer", "Ronin", "Harrier", "Jailor", "Cheat", "Gladiator" }

-- which factions carry a pickable detail, and its options
local LEADERS = { "Builder", "Charismatic", "Commander", "Despot" }
local function variantOptions(fac)
  if fac == "Eyrie" then return LEADERS end
  if fac == "Vagabond" or fac == "Knaves" then return CHARS end
  return nil
end

-- toggle one item inside a comma-joined selection, keeping the list's order
local function toggleCSV(csv, item, order)
  local set = {}
  for w in (csv or ""):gmatch("[^,]+") do
    set[w:match("^%s*(.-)%s*$")] = true
  end
  if set[item] then set[item] = nil else set[item] = true end
  local out = {}
  for _, c in ipairs(order) do
    if set[c] then table.insert(out, c) end
  end
  return table.concat(out, ", ")
end

-- the full faction roster (short names = VP marker names in the mod)
local ROSTER = { "Marquise", "Eyrie", "Alliance", "Vagabond", "Riverfolk",
  "Lizard", "Duchy", "Crows", "Rats", "Badgers", "Knaves", "Council", "Diaspora" }

-- image-URL tail -> map name (extracted from the mod's own content registry)
local MAP_NAMES = {
  ["gurcomPgXS0oWpng"] = "Tidal Flats",   ["BC18C7488CACA234"] = "Blighted City",
  ["gurcombfYkkjcpng"] = "Mountainside",  ["FEDD130951792687"] = "River Town",
  ["05CCC6DAE105DB80"] = "Taiga",         ["F09464EE61C0DEF8"] = "Gloom",
  ["3FE895F51EC40B24"] = "Autumn",        ["7210583BE261317B"] = "Summer",
  ["06452B5C93B62E68"] = "Winter",        ["4CFA846E1B68EB75"] = "Lake",
  ["93D8213D360FBA8F"] = "Mountain",      ["5F33E4FEEE8089AB"] = "The Deep Woods",
  ["664D1C3ABA5F3913"] = "The Wastelands",["9BE9CA5E53B4C887"] = "Gorge",
  ["D75950B3E5643325"] = "Gorge",         ["2D67B5C0F7D82E46"] = "Treasure Island",
  ["3BBF750AB82C04EE"] = "Narrows and Islets", ["C2F717CB7259B659"] = "Australia",
  ["27FB3B5790E593C9"] = "Tunnel Unraveled",   ["3AFD6922B0E9466F"] = "Tropics",
  ["E183A0B6769D4C69"] = "Marsh",         ["7C8340140D11A8F2"] = "Lost Woodland",
  ["D17AC01A7B9FA8C4"] = "Legends",       ["EF774E3AECED67F1"] = "Urban",
  ["6A1B83F0415249F8"] = "Inferno",       ["A21F7344C4FEF62D"] = "Spaceballs",
  ["78DE2047BA1B663E"] = "Blighted Grove",
}

-- Whether attached UI inherits the object's scale is machine-dependent; both
-- interpretations ship (right-click "panel scale mode" toggles). Mode 1
-- (inherit) is the default and self-cancels so the sheet always matches the
-- slab the script sizes for itself.
local UI_POSES = {
  { pos = "0 0 -60", rot = "0 0 0" },
  { pos = "0 0 -60", rot = "0 0 180" },
  { pos = "0 0 -60", rot = "180 180 0" },
  { pos = "0 0 -60", rot = "180 180 180" },
}
local SIZE_MULS = { 0.55, 0.7, 0.85, 1.05, 1.3, 1.6 }

----------------------------------------------------------------------- state --
local S = {
  rows      = {},   -- { fac, player, nameAuto, color, tintHex, iconUrl, guid,
                    --   score, locks={}, edits={} }
  active    = 1,
  turns     = 0,
  cols      = 10,   -- round columns always shown: fixed size during the game,
                    -- growing only past round 10 (setup-editable)
  flip      = false,
  hidden    = false,
  setup     = false,
  pose      = 1,
  scaleMode = 1,
  sizeIdx   = 2,
  meta      = { map = "", deck = "", hook = "", thread = "", game = "" },
  unpicked  = {},   -- fac -> true (picked by hand from the roster)
  unpickedVar = {}, -- fac -> "cap1, cap2" (captains available in the draft)
  varRow    = 1,
  experimental = false,
  lastExport = "",
  log       = {},
  undo      = {},   -- faction NAMES (row order can change underneath)
}

local TRACK = nil
local pollCount = 0

------------------------------------------------------------------- utilities --
local function now() return os.time() end

local function logev(ev, fac, a, b)
  table.insert(S.log, { t = now(), ev = ev, fac = fac, a = a, b = b })
  if #S.log > 3000 then table.remove(S.log, 1) end
end

local function esc(s)
  -- No ampersand survives TTS's XML pipeline (&amp; and &#38; both render as
  -- literal "&amp;", raw & is a parse error) - substitute "+" and be done
  s = tostring(s or "")
  s = s:gsub("&", "+"):gsub("<", "&#60;"):gsub(">", "&#62;"):gsub('"', "&#34;")
  return s
end

local function spaced(s)
  return (s:gsub("(.)", "%1 "):gsub(" $", ""))
end

local function tintHex(o)
  local ok, c = pcall(function() return o.getColorTint() end)
  if not ok or c == nil then return "888888" end
  return string.format("%02X%02X%02X",
    math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function markerImage(o)
  local ok, co = pcall(function() return o.getCustomObject() end)
  if not ok or co == nil then return nil end
  return co.image or co.face or co.diffuse
end

local function urlTail(u)
  if u == nil then return "" end
  u = u:gsub("[^A-Za-z0-9]", "")
  return u:sub(-16)
end

local function turnsRunning()
  return Turns.enable and Turns.order ~= nil and #Turns.order > 0
end

local function assetName(fac)
  return "vp" .. fac:gsub("%W", "")
end

--------------------------------------------------------------- track finding --
local function detectTrackOn(obj)
  local ok, sp = pcall(function() return obj.getSnapPoints() end)
  if not ok or sp == nil or #sp < SNAP_MIN then return nil end
  local bandsFound = {}
  for _, axis in ipairs({ "x", "z" }) do
    local other = (axis == "x") and "z" or "x"
    local pts = {}
    for _, s in ipairs(sp) do
      table.insert(pts, { a = s.position[axis], b = s.position[other] })
    end
    table.sort(pts, function(p, q) return p.b < q.b end)
    local bands, cur = {}, {}
    for _, p in ipairs(pts) do
      if #cur > 0 and (p.b - cur[#cur].b) > 0.03 then table.insert(bands, cur); cur = {} end
      table.insert(cur, p)
    end
    if #cur > 0 then table.insert(bands, cur) end
    for _, band in ipairs(bands) do
      if #band >= 25 then
        local xs = {}
        for _, p in ipairs(band) do table.insert(xs, p.a) end
        table.sort(xs)
        local diffs = {}
        for i = 2, #xs do table.insert(diffs, xs[i] - xs[i - 1]) end
        table.sort(diffs)
        local s = diffs[math.ceil(#diffs / 2)]
        local even = s > 0.01
        if even then
          for _, d in ipairs(diffs) do
            local m = math.floor(d / s + 0.5)
            if m < 1 or m > 2 or math.abs(d - m * s) > 0.25 * s then even = false end
          end
        end
        if even then
          local n = math.floor((xs[#xs] - xs[1]) / s + 0.5) + 1
          if n >= MIN_CELLS and n <= MAX_CELLS and #xs >= 0.85 * n then
            table.insert(bandsFound, { axis = axis, other = other,
              a0 = xs[1], s = s, n = n, b = band[1].b })
          end
        end
      end
    end
  end
  if #bandsFound == 0 then return nil end
  local best = nil
  for _, band in ipairs(bandsFound) do
    if best == nil then
      best = { axis = band.axis, other = band.other, a0 = band.a0, s = band.s,
               n = band.n, rows = { band.b } }
    elseif band.axis == best.axis
      and math.abs(band.s - best.s) < 0.1 * best.s
      and math.abs(band.a0 - best.a0) < 0.5 * best.s then
      table.insert(best.rows, band.b)
      if band.n > best.n then best.n = band.n end
    end
  end
  table.sort(best.rows)
  -- keep the raw snap coordinates belonging to the track: markers are placed
  -- exactly ON the mod's own snap points, so centering matches TTS snapping
  best.pts = {}
  local bmin, bmax = best.rows[1] - 0.05, best.rows[#best.rows] + 0.05
  for _, s2 in ipairs(sp) do
    local a = (best.axis == "x") and s2.position.x or s2.position.z
    local b = (best.axis == "x") and s2.position.z or s2.position.x
    if b >= bmin and b <= bmax then
      table.insert(best.pts, { a = a, b = b })
    end
  end
  best.guid = obj.getGUID()
  return best
end

local function findTrack()
  local best, bestSnaps = nil, 0
  for _, o in ipairs(getAllObjects()) do
    local ok, sp = pcall(function() return o.getSnapPoints() end)
    if ok and sp and #sp >= SNAP_MIN and #sp > bestSnaps then
      local t = detectTrackOn(o)
      if t then best, bestSnaps = t, #sp end
    end
  end
  TRACK = best
  if TRACK then
    local mapObj = getObjectFromGUID(TRACK.guid)
    if mapObj and S.mapAuto ~= false then
      -- read the board's identity from its artwork; a manual chip click
      -- (uiRowBtn "map") turns this off for the session
      local okc, co = pcall(function() return mapObj.getCustomObject() end)
      local img = okc and co and (co.image or co.diffuse) or nil
      local auto = MAP_NAMES[urlTail(img)]
      if auto and auto ~= "" then S.meta.map = auto end
    end
    log("BoxScore: track on " .. TRACK.guid .. " axis=" .. TRACK.axis
      .. " cells=" .. TRACK.n .. " rows=" .. #TRACK.rows)
  else
    log("BoxScore: no score track found on any snap holder")
  end
end

---------------------------------------------------------------- score reads --
local function readCell(markerObj)
  if TRACK == nil then return nil end
  local mapObj = getObjectFromGUID(TRACK.guid)
  if mapObj == nil then TRACK = nil; return nil end
  if markerObj.held_by_color ~= nil then return nil end
  local okm, moving = pcall(function() return markerObj.isSmoothMoving() end)
  if okm and moving then return nil end
  local lp = mapObj.positionToLocal(markerObj.getPosition())
  local a, b = lp[TRACK.axis], lp[TRACK.other]
  local nearRow = false
  for _, rb in ipairs(TRACK.rows) do
    if math.abs(b - rb) <= ROW_TOL + 0.12 then nearRow = true end
  end
  if not nearRow then return nil end
  local idx = math.floor((a - TRACK.a0) / TRACK.s + 0.5)
  if idx < 0 or idx > TRACK.n - 1 then return nil end
  if math.abs(a - (TRACK.a0 + idx * TRACK.s)) > COL_TOL * TRACK.s then return nil end
  return idx
end

-- Printed 0 sits at the track's MAXIMUM local coordinate (established three
-- ways: markers parked on the printed 0 cell sit at local max; the on-table
-- world view shows 0 bottom-left with the token's usual 180 rotation; and the
-- map artwork places 0 at the image edge that maps to local max). So scores
-- DESCEND along the local axis. S.flip reverses this for exotic maps only.
local function cellToScore(idx)
  if S.flip then return idx end
  return TRACK.n - 1 - idx
end

local function scoreToCell(score)
  if S.flip then return score end
  return TRACK.n - 1 - score
end

local function findMarker(row)
  local o = row.guid and getObjectFromGUID(row.guid) or nil
  if o ~= nil and (o.getName() or "") == (row.fac .. " VP") then return o end
  -- cached marker gone: re-find by name. Some kits spawn a spare copy (the
  -- Vagabond's does), so prefer the one standing on the score track.
  local loose = nil
  for _, c in ipairs(getAllObjects()) do
    if (c.getName() or "") == (row.fac .. " VP") then
      if readCell(c) ~= nil then
        row.guid = c.getGUID()
        return c
      end
      if loose == nil then loose = c end
    end
  end
  if loose ~= nil then row.guid = loose.getGUID() end
  return loose
end

-- Track orientation is NOT inferred: on every map in this mod the printed 0
-- sits at the track's minimum local coordinate and 30 at the maximum
-- (verified against the artwork of all cached maps - the mod's authoring is
-- uniform, matching the table rule "bottom-left is 0, bottom-right is 30").
-- S.flip stays false unless manually toggled for some exotic future map.

------------------------------------------------------- players and factions --
local function rowByFac(fac)
  for i, r in ipairs(S.rows) do
    if r.fac == fac then return i end
  end
  return nil
end

local function rowByColor(color)
  for i, r in ipairs(S.rows) do
    if r.color == color then return i end
  end
  return nil
end

local function addRow(fac, obj)
  table.insert(S.rows, { fac = fac, player = "", nameAuto = false, color = nil,
    variant = "", variantAuto = true,
    tintHex = tintHex(obj), iconUrl = markerImage(obj), guid = obj.getGUID(),
    score = -1, locks = {}, edits = {} })
  logev("join", fac)
  S.unpicked[fac] = nil   -- a playing faction cannot be the unpicked one
end

-- The point that marks a faction's play area: its supply bag when one
-- exists. Some kits name theirs differently (the Rats play from the
-- "Hundreds Supply", the Crows from the "Corvid Supply", the Badgers from
-- the "Keeper Supply" - verified against the mod's own spawn data), and the
-- Vagabond has no supply at all: his named character figurine
-- ("Vagabond - Thief", ...) anchors his area instead.
local SUPPLY_ALIAS = { Rats = "Hundreds", Crows = "Corvid", Badgers = "Keeper" }

local function facAnchor(fac, byName)
  local o = byName[fac .. " Supply"]
  if o == nil and SUPPLY_ALIAS[fac] ~= nil then
    o = byName[SUPPLY_ALIAS[fac] .. " Supply"]
  end
  if o == nil then
    local pre = fac .. " - "
    for _, c in ipairs(getAllObjects()) do
      local n = c.getName() or ""
      if n:sub(1, #pre) == pre or n:sub(1, #pre - 1) == (fac .. " -") then
        o = c
        break
      end
    end
  end
  return o
end

-- Best effort: find the chosen vagabond character / captain card standing
-- near the faction's supply. Fills the variant only while it is auto-managed;
-- a hand-typed variant always wins.
local function refreshVariants(byName)
  local changed = false
  for _, row in ipairs(S.rows) do
    if row.variantAuto ~= false then
      local bag = facAnchor(row.fac, byName)
      if bag then
        local bp = bag.getPosition()
        local best, bestD = nil, 18 * 18
        for _, ch in ipairs(CHARS) do
          local o = byName[ch] or byName["Vagabond - " .. ch]
            or byName["Vagabond -" .. ch]
          if o then
            local op = o.getPosition()
            local dx, dz = op.x - bp.x, op.z - bp.z
            local d = dx * dx + dz * dz
            if d < bestD then best, bestD = ch, d end
          end
        end
        if row.fac == "Knaves" then
          local caps = {}
          for _, ch in ipairs(CHARS) do
            local o = byName["Captain - " .. ch] or byName["Captain -" .. ch]
            if o then
              local op = o.getPosition()
              local dx, dz = op.x - bp.x, op.z - bp.z
              if dx * dx + dz * dz < 18 * 18 then table.insert(caps, ch) end
            end
          end
          best = (#caps > 0 and #caps <= 4) and table.concat(caps, ", ") or nil
        end
        if best and row.variant ~= best then
          row.variant = best
          changed = true
        end
      end
    end
  end
  return changed
end

-- read the deck in play from the draw pile's card back; a manual chip click
-- (uiRowBtn "deck") turns the automation off
local function refreshDeck()
  if S.deckAuto == false then return false end
  -- several decks can sit on the table (draft leftovers, spares): trust the
  -- one closest to the map, which is where the draw pile lives
  local mapObj = TRACK and getObjectFromGUID(TRACK.guid) or nil
  if mapObj == nil then return false end
  local mp = mapObj.getPosition()
  local best, bestD = nil, math.huge
  for _, o in ipairs(getAllObjects()) do
    if o.type == "Deck" then
      local q = 0
      pcall(function() q = o.getQuantity() end)
      if q >= 15 then
        local ok, data = pcall(function() return o.getData() end)
        if ok and data and data.CustomDeck then
          for _, cd in pairs(data.CustomDeck) do
            local name = DECK_BACKS[urlTail(cd.BackURL)]
            if name then
              local op = o.getPosition()
              local dx, dz = op.x - mp.x, op.z - mp.z
              local d = dx * dx + dz * dz
              if d < bestD then best, bestD = name, d end
            end
          end
        end
      end
    end
  end
  if best and S.meta.deck ~= best then
    S.meta.deck = best
    return true
  end
  return false
end

local function seatedHands()
  local hands = {}
  for _, p in ipairs(Player.getPlayers()) do
    if p.seated and p.color ~= "Black" and p.color ~= "Grey" then
      local ok, ht = pcall(function() return p.getHandTransform() end)
      if ok and ht then
        table.insert(hands, { color = p.color, name = p.steam_name, pos = ht.position })
      end
    end
  end
  return hands
end

-- Seat -> faction: nearest hand zone to the faction's supply bag (the supply
-- sits with the faction board in front of its player), greedily one-to-one.
local function refreshSeats(byName)
  local hands = seatedHands()
  if #hands == 0 then return false end
  local cand = {}
  for _, row in ipairs(S.rows) do
    local bag = facAnchor(row.fac, byName)
    if bag then
      local bp = bag.getPosition()
      for _, h in ipairs(hands) do
        local dx, dz = h.pos.x - bp.x, h.pos.z - bp.z
        table.insert(cand, { d = dx * dx + dz * dz, fac = row.fac,
                             color = h.color, name = h.name })
      end
    end
  end
  table.sort(cand, function(x, y) return x.d < y.d end)
  local usedC, usedF, changed = {}, {}, false
  for _, c in ipairs(cand) do
    if not usedC[c.color] and not usedF[c.fac] then
      usedC[c.color], usedF[c.fac] = true, true
      local row = S.rows[rowByFac(c.fac)]
      if row.color ~= c.color then row.color = c.color; changed = true end
      if row.player == "" or row.nameAuto then
        if row.player ~= c.name then row.player = c.name; changed = true end
        row.nameAuto = true
      end
    end
  end
  return changed
end

local function resort(cmp)
  local activeRow = S.rows[S.active]
  table.sort(S.rows, cmp)
  for i, r in ipairs(S.rows) do
    if r == activeRow then S.active = i end
  end
end

-- The turn system can only drive the sheet when every faction row belongs to
-- a seated color. Solo and hotseat games (one player running several
-- factions) fall back to the manual END TURN button.
local function fullTurnCoverage()
  if not turnsRunning() or #S.rows == 0 then return false end
  -- The turn system can drive the sheet only when >= 2 real seats exist AND
  -- every faction row's player is seated RIGHT NOW. Stale colors (saved
  -- games, disconnects) collapse to manual mode so END TURN reappears.
  local seatedSet, seats = {}, 0
  for _, p in ipairs(Player.getPlayers()) do
    if p.seated and p.color ~= "Black" and p.color ~= "Grey" then
      seatedSet[p.color] = true
      seats = seats + 1
    end
  end
  if seats < 2 then return false end
  for _, r in ipairs(S.rows) do
    if r.color == nil or not seatedSet[r.color] then return false end
  end
  return true
end

local function followTurns()
  if not fullTurnCoverage() then return false end
  local changed = false
  if not S.manualOrder then
    local pos = {}
    for i, c in ipairs(Turns.order) do pos[c] = i end
    local before = {}
    for i, r in ipairs(S.rows) do before[i] = r end
    resort(function(x, y)
      local kx = (x.color and pos[x.color]) or 999
      local ky = (y.color and pos[y.color]) or 999
      return kx < ky
    end)
    for i, r in ipairs(S.rows) do
      if before[i] ~= r then changed = true end
    end
  end
  local tc = Turns.turn_color
  if tc and tc ~= "" then
    local i = rowByColor(tc)
    if i and i ~= S.active then S.active = i; changed = true end
  end
  return changed
end

-- Without the turn system and before anything is locked, order rows clockwise
-- around the table by seat position - Root's usual turn order convention.
local function seatOrder()
  if S.manualOrder or turnsRunning() or S.turns > 0 then return false end
  for _, row in ipairs(S.rows) do
    if #row.locks > 0 then return false end
  end
  local hands = {}
  for _, h in ipairs(seatedHands()) do hands[h.color] = h.pos end
  local before = {}
  for i, r in ipairs(S.rows) do before[i] = r end
  resort(function(x, y)
    local px, py = x.color and hands[x.color], y.color and hands[y.color]
    if px == nil or py == nil then return (px ~= nil) and py == nil end
    return math.atan2(px.z, px.x) > math.atan2(py.z, py.x)
  end)
  for i, r in ipairs(S.rows) do
    if before[i] ~= r then return true end
  end
  return false
end

--------------------------------------------------------------------- export --
local function unpickedList()
  local out = {}
  for _, fac in ipairs(ROSTER) do
    if S.unpicked[fac] == true then
      local v = S.unpickedVar and S.unpickedVar[fac] or ""
      table.insert(out, v ~= "" and (fac .. " (" .. v .. ")") or fac)
    end
  end
  return out
end

local function exportPayload(kind, extra)
  local p = { type = kind, t = now(), meta = S.meta, turns = S.turns,
              turnOrder = Turns.order, unpicked = unpickedList(),
              unpickedVariants = S.unpickedVar, rows = {} }
  for _, row in ipairs(S.rows) do
    table.insert(p.rows, { faction = row.fac, player = row.player,
      variant = row.variant, color = row.color, score = row.score,
      locks = row.locks, edits = row.edits, crafts = row.crafts })
  end
  if extra ~= nil then
    for k, v in pairs(extra) do p[k] = v end
  end
  return p
end

-- Post straight to a Discord webhook - no companion program needed. The URL
-- is pasted once into EDIT's DISCORD field (or baked into GMNotes) and
-- then travels with the object inside every save.
local function postDiscord(chunks)
  local hook = S.meta.hook or ""
  if hook == "" or #chunks == 0 then return false end
  local thread = (S.meta.thread or ""):match("(%d%d%d%d%d%d+)%s*$")
  hook = hook .. (hook:find("%?") and "&" or "?") .. "wait=true"
  if thread then hook = hook .. "&thread_id=" .. thread end
  local idx = 0
  local function sendNext()
    idx = idx + 1
    local text = chunks[idx]
    if text == nil then
      S.lastExport = os.date("%H:%M") .. " &#183; confirmed with Discord"
        .. (#chunks > 1 and (" (" .. #chunks .. " msgs)") or "")
      rebuildUI()
      return
    end
    local body = JSON.encode({ content = text })
    local function report(req)
      if req and (req.is_error or (req.response_code or 0) >= 300) then
        S.lastExport = os.date("%H:%M") .. " &#183; Discord failed (msg " .. idx .. ")"
        log("BoxScore discord error: " .. tostring(req.error) .. " code="
          .. tostring(req.response_code) .. " body=" .. tostring(req.text):sub(1, 200))
        rebuildUI()
      else
        sendNext()
      end
    end
    local ok = pcall(function()
      WebRequest.custom(hook, "POST", false, body,
        { ["Content-Type"] = "application/json" }, report)
    end)
    if not ok then
      pcall(function() WebRequest.post(hook, { content = text }, report) end)
    end
  end
  sendNext()
  return true
end

-- split lines into fenced messages under Discord's 2000-char limit
local function fencedChunks(lines)
  local chunks, cur, len = {}, {}, 0
  for _, l in ipairs(lines) do
    if len + #l + 10 > 1800 and #cur > 0 then
      table.insert(chunks, "```\n" .. table.concat(cur, "\n") .. "\n```")
      cur, len = {}, 0
    end
    table.insert(cur, l)
    len = len + #l + 1
  end
  if #cur > 0 then
    table.insert(chunks, "```\n" .. table.concat(cur, "\n") .. "\n```")
  end
  return chunks
end

--------------------------------------------------- experimental: crafting --
-- Watch the craftable-item supply on the map (the edge opposite the score
-- track). An item leaving the map = a craft: attributed to whoever carried
-- it (or the active faction), with the VP taken from that faction's next
-- score change within 30 seconds.
-- craftable-item artwork -> item name (the tokens are unnamed in this mod)
local ITEMS = {
  ["4C4E490133888321E24E3F77DC20E1A4A7369B6E"] = "Coins",
  ["FF9D60BC2A7E6A38BE74773188B30F57C14E9FB5"] = "Tea",
  ["366FF0B1EDD8B091B881287CF72CFBAA584B742B"] = "Sword",
  ["0BEAA5BC0CC9AA3ADB7BEB4A59C124603DA73CD7"] = "Hammer",
  ["639F7EE379C0EBF83B49BF9BE165BBD7345E7F5C"] = "Crossbow",
  ["81AC7B7422C963CCFB711E0134FF957117DC1528"] = "Boot",
  ["459F031CFC2B05BFD5597460610B20DD58D14843"] = "Bag",
}
local ITEM_NAMES = { "Coins", "Tea", "Sword", "Hammer", "Crossbow", "Boot", "Bag" }
local function itemTail(u)
  if u == nil then return "" end
  return (u:gsub("[^A-Za-z0-9]", "")):sub(-40)
end

local ITEMWATCH = nil     -- guid -> { name, holder, img }
local INFLIGHT = {}       -- guid -> { name, img, holder, tLeft }
local SUPPLYPOS = {}      -- fac -> world position of its supply bag
local CATCHUP = false     -- one adopt-existing-crafts sweep after (re)arming

local function initItemWatch()
  ITEMWATCH = {}
  if TRACK == nil then return end
  local mapObj = getObjectFromGUID(TRACK.guid)
  if mapObj == nil then return end
  local trackB = TRACK.rows[math.ceil(#TRACK.rows / 2)]
  local count = 0
  for _, o in ipairs(getAllObjects()) do
    if o ~= self and o.getGUID() ~= TRACK.guid then
      local n = o.getName() or ""
      -- the item tokens are UNNAMED small tiles; named map furniture (VP
      -- markers, ruins, landmarks) is excluded, everything else small in the
      -- supply region is an item
      local excluded = n:match(" VP$") or n:match("Supply$") or n:match("Board$")
        or n == "RUIN" or o.type == "Deck" or o.type == "Card"
      local sc = o.getScale()
      if not excluded and sc.x < 1.0 then
        local ok, lp = pcall(function() return mapObj.positionToLocal(o.getPosition()) end)
        if ok and lp and math.abs(lp.x) < 1.95 and math.abs(lp.z) < 1.95 then
          local b = (TRACK.axis == "x") and lp.z or lp.x
          if b * trackB < 0 and math.abs(b) > 0.85 then
            local img = markerImage(o)
            local nm = ITEMS[itemTail(img)] or ((n ~= "") and n or "Item")
            if ITEMS[itemTail(img)] and img ~= "" then S.itemImgs[nm] = img end
            ITEMWATCH[o.getGUID()] = { name = nm, holder = nil, img = img }
            count = count + 1
          end
        end
      end
    end
  end
  log("BoxScore experimental: watching " .. count .. " supply items")
end

-- the item's crafting VP: the faction's first score increase since the item
-- left the supply (the marker usually moves at craft time even when the item
-- is moved to the board later)
local function inferCraftVP(fac, tLeft)
  for k = #S.log, 1, -1 do
    local e = S.log[k]
    if e.t ~= nil and e.t < tLeft then break end
    if e.ev == "score" and e.fac == fac and type(e.a) == "number"
      and type(e.b) == "number" and e.b > e.a and e.a >= 0 then
      return e.b - e.a
    end
  end
  return 0
end

local function inferRound(fac, t, activeFac)
  local n = 0
  for _, e in ipairs(S.log) do
    if e.ev == "lock" and e.fac == fac and (e.t or 0) <= t then n = n + 1 end
  end
  if activeFac ~= nil and activeFac ~= fac then
    -- the item moved while another faction was playing: it belongs to the
    -- crafting faction's last noted turn, not their upcoming one
    return math.max(1, n)
  end
  return n + 1
end

-- is this object back in the map's item-supply region?
local function inSupplyRegion(mapObj, o)
  if TRACK == nil then return false end
  local ok, lp = pcall(function() return mapObj.positionToLocal(o.getPosition()) end)
  if not (ok and lp) then return false end
  if math.abs(lp.x) >= 1.95 or math.abs(lp.z) >= 1.95 then return false end
  local trackB = TRACK.rows[math.ceil(#TRACK.rows / 2)]
  local b = (TRACK.axis == "x") and lp.z or lp.x
  return b * trackB < 0 and math.abs(b) > 0.85
end

local function attributeCraft(i, entry, guid)
  local row = S.rows[i]
  if row == nil then return end
  row.crafts = row.crafts or {}
  table.insert(row.crafts, { item = entry.name, img = entry.img, guid = guid,
    vp = inferCraftVP(row.fac, entry.tLeft),
    r = inferRound(row.fac, entry.tLeft, entry.activeFac) })
  if entry.img and entry.img ~= "" then S.itemImgs[entry.name] = entry.img end
  logev("craft", row.fac, entry.name)
  refreshAssets()
end

-- items already sitting beside a faction board when the watch (re)starts are
-- adopted as crafts, so late activation or missed flights still count
local function catchUpCrafts(mapObj)
  local counted = {}
  for _, row in ipairs(S.rows) do
    for _, c in ipairs(row.crafts or {}) do
      if c.guid then counted[c.guid] = true end
    end
  end
  for _, o in ipairs(getAllObjects()) do
    local guid = o.getGUID()
    if not counted[guid] and ITEMWATCH[guid] == nil and o.type == "Tile" then
      local img = markerImage(o)
      local nm = ITEMS[itemTail(img)]
      if nm then
        local okl, lp = pcall(function() return mapObj.positionToLocal(o.getPosition()) end)
        local offMap = not (okl and lp and math.abs(lp.x) < 2.0 and math.abs(lp.z) < 2.0)
        if offMap then
          local op = o.getPosition()
          local bestFac, bestD = nil, 30 * 30
          for fac, sp2 in pairs(SUPPLYPOS) do
            local dx, dz = op.x - sp2.x, op.z - sp2.z
            local d = dx * dx + dz * dz
            if d < bestD then bestFac, bestD = fac, d end
          end
          local i2 = bestFac and rowByFac(bestFac) or nil
          if i2 then
            attributeCraft(i2, { name = nm, img = img, tLeft = now(),
              activeFac = S.rows[S.active] and S.rows[S.active].fac or nil }, guid)
          end
        end
      end
    end
  end
end

function uiCraftMenu()
  S.overlay = (S.overlay == "craft") and nil or "craft"
  S.craftAdd = nil
  S.craftPick = nil
  rebuildUI()
end

function uiCraftBtn(player, _, id)
  local i, k = id:match("^cfr_(%d+)_(%d+)$")
  if i then
    -- clicking a craft's T# opens the round row below; clicking again closes
    if S.craftPick ~= nil and S.craftPick.i == tonumber(i)
      and S.craftPick.k == tonumber(k) then
      S.craftPick = nil
    else
      S.craftPick = { i = tonumber(i), k = tonumber(k) }
      S.craftAdd = nil
    end
    rebuildUI()
    return
  end
  local pr = id:match("^cfpick_(%d+)$")
  if pr then
    if S.craftPick ~= nil then
      local row = S.rows[S.craftPick.i]
      local c = row and (row.crafts or {})[S.craftPick.k] or nil
      if c then c.r = tonumber(pr) end
      S.craftPick = nil
    end
    rebuildUI()
    return
  end
  i, k = id:match("^cfx_(%d+)_(%d+)$")
  if i then
    local row = S.rows[tonumber(i)]
    if row and row.crafts then
      table.remove(row.crafts, tonumber(k))
      refreshAssets()
    end
    rebuildUI()
    return
  end
  i = id:match("^cfadd_(%d+)$")
  if i then
    S.craftAdd = (S.craftAdd == tonumber(i)) and nil or tonumber(i)
    S.craftPick = nil
    rebuildUI()
    return
  end
  k = id:match("^cfnew_(%d+)$")
  if k then
    local row = S.rows[S.craftAdd or 0]
    local nm = ITEM_NAMES[tonumber(k)]
    if row and nm then
      row.crafts = row.crafts or {}
      table.insert(row.crafts, { item = nm, img = S.itemImgs[nm] or "",
        vp = 0, r = math.floor(S.turns / math.max(1, #S.rows)) + 1 })
      logev("craft", row.fac, nm)
      S.craftAdd = nil
      refreshAssets()
    end
    rebuildUI()
  end
end

function uiExperimental()
  S.experimental = not S.experimental
  ITEMWATCH = nil
  INFLIGHT = {}
  if S.overlay == "craft" then S.overlay = nil end
  rebuildUI()
end

------------------------------------------------------------------- the poll --
local dirty = false

local function poll()
  pollCount = pollCount + 1
  if TRACK == nil or (pollCount % 25 == 0) then
    local old = TRACK and TRACK.guid or "?"
    findTrack()
    if TRACK and TRACK.guid ~= old then dirty = true end
  end
  if TRACK == nil then return end

  for _, o in ipairs(getAllObjects()) do
    local n = o.getName() or ""
    local fac = n:match("^(.+) VP$")
    if fac and rowByFac(fac) == nil and readCell(o) ~= nil then
      addRow(fac, o)
      refreshAssets()
      dirty = true
    end
  end

  for _, row in ipairs(S.rows) do
    local m = findMarker(row)
    local idx = m and readCell(m) or nil
    if idx ~= nil then
      local sc = cellToScore(idx)
      if sc ~= row.score then
        logev("score", row.fac, row.score, sc)
        row.score = sc
        dirty = true
      end
    end
  end

  if S.experimental and TRACK ~= nil then
    if ITEMWATCH == nil then
      initItemWatch()
      CATCHUP = true
    end
    local mapObj = getObjectFromGUID(TRACK.guid)
    -- the catch-up sweep needs the supply anchors, which fill on the first
    -- fifth-poll scan; run it once they exist
    if CATCHUP and mapObj and ITEMWATCH and next(SUPPLYPOS) ~= nil then
      catchUpCrafts(mapObj)
      CATCHUP = false
      dirty = true
    end
    if mapObj and ITEMWATCH then
      for guid, w in pairs(ITEMWATCH) do
        local o = getObjectFromGUID(guid)
        if o ~= nil and o.held_by_color ~= nil then w.holder = o.held_by_color end
        local gone = (o == nil)
        if not gone then
          local okl, lp = pcall(function() return mapObj.positionToLocal(o.getPosition()) end)
          if okl and lp and (math.abs(lp.x) > 2.1 or math.abs(lp.z) > 2.1) then gone = true end
        end
        if gone then
          ITEMWATCH[guid] = nil
          INFLIGHT[guid] = { name = w.name, img = w.img, holder = w.holder,
            tLeft = now(),
            activeFac = S.rows[S.active] and S.rows[S.active].fac or nil }
          log("EXP leave: " .. w.name .. " " .. guid)
        end
      end
      -- a crafted item put BACK in the supply was a mistake: undo the craft
      -- and watch the item again as if it had never been taken
      for _, row in ipairs(S.rows) do
        if row.crafts then
          for ci3 = #row.crafts, 1, -1 do
            local c = row.crafts[ci3]
            if c.guid then
              local o2 = getObjectFromGUID(c.guid)
              if o2 and o2.held_by_color == nil and inSupplyRegion(mapObj, o2) then
                logev("uncraft", row.fac, c.item)
                table.remove(row.crafts, ci3)
                ITEMWATCH[c.guid] = { name = c.item, holder = nil, img = c.img }
                dirty = true
              end
            end
          end
        end
      end
      -- items in flight settle where they were crafted: the faction board
      -- whose supply they end up beside claims them
      for guid, fl in pairs(INFLIGHT) do
        local o = getObjectFromGUID(guid)
        if o ~= nil then
          if o.held_by_color ~= nil then fl.holder = o.held_by_color end
          if o.held_by_color == nil and inSupplyRegion(mapObj, o) then
            -- returned to the supply: never crafted
            INFLIGHT[guid] = nil
            ITEMWATCH[guid] = { name = fl.name, holder = nil, img = fl.img }
          elseif o.held_by_color == nil then
            local op = o.getPosition()
            local bestFac, bestD = nil, 30 * 30
            for fac, sp2 in pairs(SUPPLYPOS) do
              local dx, dz = op.x - sp2.x, op.z - sp2.z
              local d = dx * dx + dz * dz
              if d < bestD then bestFac, bestD = fac, d end
            end
            log("EXP inflight " .. guid .. " bestFac=" .. tostring(bestFac)
              .. " supplies=" .. tostring((function() local c = 0
                for _ in pairs(SUPPLYPOS) do c = c + 1 end
                return c end)()))
            if bestFac then
              local i2 = rowByFac(bestFac)
              if i2 then
                INFLIGHT[guid] = nil
                attributeCraft(i2, fl, guid)
                dirty = true
              end
            elseif now() - fl.tLeft > 300 then
              INFLIGHT[guid] = nil
            end
          end
        else
          -- object vanished (bagged): fall back to whoever carried it last
          INFLIGHT[guid] = nil
          local i2 = fl.holder and rowByColor(fl.holder) or nil
          if i2 then
            attributeCraft(i2, fl, guid)
            dirty = true
          end
        end
      end
    end
  end

  if pollCount % 5 == 1 then
    local byName = {}
    for _, o in ipairs(getAllObjects()) do
      byName[o.getName() or ""] = o
    end
    SUPPLYPOS = {}
    for _, row in ipairs(S.rows) do
      local bag = facAnchor(row.fac, byName)
      if bag then SUPPLYPOS[row.fac] = bag.getPosition() end
    end
    if refreshSeats(byName) then dirty = true end
    if refreshDeck() then dirty = true end
    if refreshVariants(byName) then dirty = true end
    if followTurns() then dirty = true end
  end

  if dirty then
    dirty = false
    rebuildUI()
  end
end

------------------------------------------------------------------ turn flow --
local function lockRow(i)
  local row = S.rows[i]
  if row == nil then return end
  -- re-read the marker right now: the polled score can be a beat stale, and a
  -- lock is forever (it is what gets exported)
  local m = findMarker(row)
  local idx = m and readCell(m) or nil
  if idx ~= nil then
    local sc = cellToScore(idx)
    if sc ~= row.score then
      logev("score", row.fac, row.score, sc)
      row.score = sc
    end
  end
  -- the lock lands in the first visibly-empty column at or after the
  -- declared round: padding blanks count as empty and are overwritten, so a
  -- lock can never skip past cells that look empty
  local declared = math.floor(S.turns / math.max(1, #S.rows)) + 1
  local r = math.max(1, declared)
  if S.hardRound == declared then
    -- the round was declared by hand (column number clicked in EDIT): the
    -- lock lands exactly there, overwriting whatever the cell holds
    row.edits[tostring(r)] = nil
  else
    while (row.locks[r] ~= nil and row.locks[r] ~= -1)
      or (row.edits[tostring(r)] ~= nil and row.edits[tostring(r)] ~= "") do
      r = r + 1
    end
  end
  while #row.locks < r - 1 do
    table.insert(row.locks, -1)
  end
  row.locks[r] = row.score
  table.insert(S.undo, { fac = row.fac, r = r })
  logev("lock", row.fac, r, row.score)
  S.turns = S.turns + 1
  if S.hardRound ~= nil
    and math.floor(S.turns / math.max(1, #S.rows)) + 1 > S.hardRound then
    S.hardRound = nil
  end
  rebuildUI()
end

-- With full coverage the TTS turn system locks turns; otherwise END TURN.
local function lockActive()
  if #S.rows == 0 or fullTurnCoverage() then return end
  if S.active > #S.rows then S.active = 1 end
  local i = S.active
  S.active = (S.active % #S.rows) + 1
  lockRow(i)
end

function uiEndTurn() lockActive() end

function onPlayerTurn(player, previous)
  log("BoxScore onPlayerTurn: now=" .. tostring(player and player.color)
    .. " prev=" .. tostring(previous and previous.color)
    .. " coverage=" .. tostring(fullTurnCoverage()))
  -- ONE lock source per mode: with full coverage the event locks; in every
  -- other situation the END TURN button is visible and is the only source.
  if not fullTurnCoverage() then return end
  -- Only a REAL turn pass counts (previous player seated): toggling the turn
  -- system bursts through unseated colors and none of those may lock.
  if previous == nil or previous.seated ~= true then return end
  -- A pass by a seated color with no faction row (an observer) locks nothing.
  local i = rowByColor(previous.color)
  if i then lockRow(i) end
  -- sync the pointer immediately instead of waiting for the next poll
  local j = player and player.color and rowByColor(player.color) or nil
  if j then S.active = j end
end

------------------------------------------------------------ marker movement --
-- +/- moves the faction's marker along the track: a fast glide with a small
-- hop, so rapid clicks load several points in a couple of seconds. Sub-row
-- rule so every marker stays visible: an empty cell takes the marker dead
-- centre; an occupied cell pushes the newcomer one step up, then down, then
-- two up - never on top of another marker.
local function subRowSequence()
  local byB = {}
  for _, b in ipairs(TRACK.rows) do table.insert(byB, b) end
  table.sort(byB)
  local mid = byB[math.ceil(#byB / 2)]
  local step = 0.11
  if #byB >= 2 then step = (byB[#byB] - byB[1]) / (#byB - 1) end
  return { mid, mid - step, mid + step, mid - 2 * step, mid + 2 * step }
end

local function nudge(i, delta)
  local row = S.rows[i]
  if row == nil or TRACK == nil then return end
  local m = findMarker(row)
  if m == nil then log("BoxScore: cannot find " .. row.fac .. " VP") return end
  if m.held_by_color ~= nil then return end
  local base = row.score >= 0 and row.score or 0
  local target = row.score >= 0 and (base + delta) or 0
  target = math.max(0, math.min(TRACK.n - 1, target))
  if target == row.score then return end
  local mapObj = getObjectFromGUID(TRACK.guid)
  if mapObj == nil then return end
  local cellA = TRACK.a0 + scoreToCell(target) * TRACK.s

  -- candidate positions = the map's own snap points in this column, tried
  -- centre-first so a lone marker sits exactly on the printed number
  local mid = TRACK.rows[math.ceil(#TRACK.rows / 2)]
  local cands = {}
  for _, p in ipairs(TRACK.pts or {}) do
    if math.abs(p.a - cellA) < 0.45 * TRACK.s then
      table.insert(cands, p)
    end
  end
  table.sort(cands, function(p, q)
    return math.abs(p.b - mid) < math.abs(q.b - mid)
  end)
  -- extrapolated overflow spots keep every marker visible past 3 stacked
  local seq = subRowSequence()
  table.insert(cands, { a = cellA, b = seq[4] })
  table.insert(cands, { a = cellA, b = seq[5] })

  local chosen = cands[#cands]
  for _, c in ipairs(cands) do
    local free = true
    for _, other in ipairs(S.rows) do
      if other ~= row then
        local om = other.guid and getObjectFromGUID(other.guid) or nil
        if om then
          local lp2 = mapObj.positionToLocal(om.getPosition())
          if math.abs(lp2[TRACK.axis] - c.a) < 0.5 * TRACK.s
            and math.abs(lp2[TRACK.other] - c.b) < 0.09 then free = false end
        end
      end
    end
    if free then chosen = c break end
  end

  local lp = { x = 0, y = 2.0, z = 0 }
  lp[TRACK.axis] = chosen.a
  lp[TRACK.other] = chosen.b
  local wp = mapObj.positionToWorld(lp)
  m.setPositionSmooth({ wp.x, wp.y + 0.12, wp.z }, false, true)
  logev("score", row.fac, row.score, target)
  row.score = target
  rebuildUI()
end

-------------------------------------------------------------------- buttons --
function uiUndo()
  if #S.undo == 0 then return end
  local entry = table.remove(S.undo)
  local fac = type(entry) == "table" and entry.fac or entry
  local col = type(entry) == "table" and entry.r or nil
  local i = rowByFac(fac)
  local row = i and S.rows[i] or nil
  if row and #row.locks > 0 then
    col = col or #row.locks
    logev("undo", row.fac, col, row.locks[col])
    row.locks[col] = -1
    while #row.locks > 0 and (row.locks[#row.locks] == -1 or row.locks[#row.locks] == nil) do
      table.remove(row.locks)
    end
    S.turns = math.max(0, S.turns - 1)
    if not fullTurnCoverage() then S.active = i end
    rebuildUI()
  end
end

function uiInfo()
  S.overlay = (S.overlay == "info") and nil or "info"
  rebuildUI()
end

function uiSetup()
  S.setup = not S.setup
  S.overlay = nil
  rebuildUI()
end

function uiReset()
  logev("reset")
  S.rows = {}
  S.active = 1
  S.turns = 0
  S.hardRound = nil
  S.undo = {}
  S.log = {}
  S.unpicked = {}
  S.unpickedVar = {}
  S.meta.map = ""
  S.meta.deck = ""
  S.mapAuto = nil
  S.deckAuto = nil
  S.flip = false
  S.manualOrder = nil
  S.lastExport = ""
  TRACK = nil
  findTrack()
  refreshAssets()
  rebuildUI()
end

function uiPicker()
  S.overlay = "picker"
  rebuildUI()
end

function uiMapMenu()
  S.overlay = "map"
  rebuildUI()
end

function uiGameMenu()
  S.overlay = "game"
  rebuildUI()
end

function uiDeckMenu()
  S.overlay = "deck"
  rebuildUI()
end

function uiDiscord()
  S.overlay = "discord"
  rebuildUI()
end

function uiOverlayClose()
  S.overlay = nil
  rebuildUI()
end

function uiExport(player)
  local by = player and player.steam_name or ""
  S.exportBy = by
  local payload = exportPayload("export", { log = S.log, exportedBy = by })
  local toDiscord = postDiscord(fencedChunks(boxText()))
  local body = JSON.encode(payload)
  local title = "BoxScore"
  local done = false
  for _, t in ipairs(Notes.getNotebookTabs()) do
    if t.title == title then
      Notes.editNotebookTab({ index = t.index, title = title, body = body })
      done = true
    end
  end
  if not done then Notes.addNotebookTab({ title = title, body = body }) end
  S.lastExport = os.date("%H:%M")
    .. (toDiscord and " &#183; discord&#8230;" or " (no webhook set)")
  log("BoxScore: exported" .. (toDiscord and " (discord)" or ""))
  rebuildUI()
end

function uiFlip()
  S.flip = not S.flip
  for _, row in ipairs(S.rows) do row.score = -1 end
  rebuildUI()
end

function uiSpin()
  S.pose = (S.pose % #UI_POSES) + 1
  rebuildUI()
end

function uiScaleMode()
  S.scaleMode = (S.scaleMode % 2) + 1
  rebuildUI()
end

function uiSize()
  S.sizeIdx = (S.sizeIdx % #SIZE_MULS) + 1
  rebuildUI()
end

function uiHide()
  S.hidden = not S.hidden
  rebuildUI()
end

function uiDiag()
  local lines = {}
  if TRACK then
    lines[1] = "map=" .. TRACK.guid .. " (" .. (S.meta.map ~= "" and S.meta.map or "?")
      .. ") cells 0-" .. (TRACK.n - 1) .. ", " .. #TRACK.rows .. " sub-rows, flip=" .. tostring(S.flip)
  else
    lines[1] = "NO TRACK FOUND - is a map on the table?"
  end
  table.insert(lines, "turn system: " .. (turnsRunning() and "following" or "manual"))
  table.insert(lines, "unpicked: " .. table.concat(unpickedList(), ", "))
  for _, row in ipairs(S.rows) do
    local m = findMarker(row)
    local idx = m and readCell(m) or nil
    table.insert(lines, row.fac .. " [" .. tostring(row.color) .. "/" .. row.player
      .. "]: score=" .. tostring(row.score) .. " cell=" .. tostring(idx)
      .. " locks=" .. #row.locks)
  end
  broadcastToAll("Box Score diagnose:\n" .. table.concat(lines, "\n"), { 0.91, 0.86, 0.74 })
  log("BoxScore diagnose: " .. JSON.encode({ track = TRACK, state = S }))
end

function uiRowBtn(player, _, id)
  local uvF, uvC = id:match("^uv_(%d+)_(%d+)$")
  if uvF then
    local fac = ROSTER[tonumber(uvF)]
    local opts = fac and variantOptions(fac) or nil
    if opts and opts[tonumber(uvC)] then
      S.unpickedVar[fac] = toggleCSV(S.unpickedVar[fac], opts[tonumber(uvC)], opts)
      rebuildUI()
    end
    return
  end
  local kind, i = id:match("^(%a+)_(%d+)$")
  i = tonumber(i)
  if kind == "plus" then nudge(i, 1)
  elseif kind == "minus" then nudge(i, -1)
  elseif kind == "up" then
    if i > 1 then
      S.rows[i], S.rows[i - 1] = S.rows[i - 1], S.rows[i]
      if S.active == i then S.active = i - 1 elseif S.active == i - 1 then S.active = i end
      S.manualOrder = true
      rebuildUI()
    end
  elseif kind == "del" then
    local row = S.rows[i]
    if row then
      logev("leave", row.fac)
      table.remove(S.rows, i)
      if i < S.active then S.active = S.active - 1 end
      if S.active > #S.rows or S.active < 1 then S.active = 1 end
      refreshAssets()
      rebuildUI()
    end
  elseif kind == "pick" then
    local fac = ROSTER[i]
    if fac then
      S.unpicked[fac] = (S.unpicked[fac] ~= true) and true or nil
      rebuildUI()
    end
  elseif kind == "act" then
    if S.rows[i] then
      S.active = i
      rebuildUI()
    end
  elseif kind == "fv" then
    S.varRow = i
    S.overlay = "var"
    rebuildUI()
  elseif kind == "vc" then
    local row = S.rows[S.varRow]
    if row then
      local opts = variantOptions(row.fac)
      if opts and opts[i] then
        row.variant = toggleCSV(row.variant, opts[i], opts)
        row.variantAuto = false
        rebuildUI()
      end
    end
  elseif kind == "deck" then
    local d = DECKS[i]
    S.meta.deck = (S.meta.deck == d) and "" or d
    S.deckAuto = false
    S.overlay = nil
    rebuildUI()
  elseif kind == "map" then
    local m = MAPS[i]
    S.meta.map = (S.meta.map == m) and "" or m
    S.mapAuto = false
    S.overlay = nil
    rebuildUI()
  elseif kind == "colh" then
    -- clicking a round-column number in setup declares "we are in round i";
    -- every faction's next lock lands in that very column, overwriting
    S.turns = (i - 1) * math.max(1, #S.rows)
    S.hardRound = i
    logev("setturn", nil, S.turns)
    rebuildUI()
  end
end

--------------------------------------------------------------- text editing --
function uiCellEdit(player, value, id)
  local i, r = id:match("^cl_(%d+)_(%d+)$")
  i, r = tonumber(i), tonumber(r)
  local row = S.rows[i]
  if row == nil then return end
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  -- an emptied cell stays empty: "" is an explicit blank that overrides the
  -- locked value (it would otherwise reappear on the next rebuild)
  if value == "" and row.locks[r] == nil then
    row.edits[tostring(r)] = nil
  else
    row.edits[tostring(r)] = value
    logev("edit", row.fac, r, value)
  end
end

function uiLiveEdit(player, value, id)
  value = tostring(value or "")
  local ni = id:match("^nm_(%d+)$")
  if ni then
    local row = S.rows[tonumber(ni)]
    if row then row.player = value; row.nameAuto = false end
  else
    local ci, r = id:match("^cl_(%d+)_(%d+)$")
    if ci then
      local row = S.rows[tonumber(ci)]
      if row then row.edits[tostring(tonumber(r))] = value end
    elseif id == "mt_hook" then S.meta.hook = value
    elseif id == "mt_thread" then S.meta.thread = value
    elseif id == "mt_game" then
      S.meta.game = value:gsub("^%s+", ""):gsub("%s+$", "")
    end
  end
  -- push the keystroke to every client without rebuilding the sheet
  pcall(function() self.UI.setAttribute(id, "text", value) end)
end

function uiNameEdit(player, value, id)
  local i = tonumber(id:match("^nm_(%d+)$"))
  if S.rows[i] then
    S.rows[i].player = tostring(value or "")
    S.rows[i].nameAuto = false
  end
end


function uiMetaEdit(player, value, id)
  local key = id:match("^mt_(%a+)$")
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if key == "turns" then
    S.turns = math.max(0, math.floor(tonumber(value) or S.turns))
    rebuildUI()
  elseif key and S.meta[key] ~= nil then
    S.meta[key] = value
  end
end

--------------------------------------------------------------------- the UI --
function refreshAssets()
  local assets = {}
  local seen = {}
  for _, row in ipairs(S.rows) do
    if row.iconUrl and row.iconUrl ~= "" then
      table.insert(assets, { name = assetName(row.fac), url = row.iconUrl })
    end
    for _, c in ipairs(row.crafts or {}) do
      if c.img and c.img ~= "" then
        local nm = "it" .. urlTail(c.img)
        if not seen[nm] then
          seen[nm] = true
          table.insert(assets, { name = nm, url = c.img })
        end
      end
    end
  end
  for _, url in pairs(S.itemImgs or {}) do
    if url ~= "" then
      local an = "it" .. urlTail(url)
      if not seen[an] then
        seen[an] = true
        table.insert(assets, { name = an, url = url })
      end
    end
  end
  self.UI.setCustomAssets(assets)
end

local function fieldText(v)
  if v == nil or v == "" then return " " end
  return esc(v)
end

local function cellText(row, r)
  local e = row.edits[tostring(r)]
  if e ~= nil then return e end
  local v = row.locks[r]
  if v == nil or v < 0 then return "" end
  return tostring(v)
end

-- fenced plain-text box score, as posted to Discord (global on purpose:
-- uiExport is defined above and resolves it at call time)
function boxText()
  local bits = {}
  if S.meta.map ~= "" then table.insert(bits, S.meta.map) end
  if S.meta.deck ~= "" then table.insert(bits, S.meta.deck) end
  local unp = unpickedList()
  if #unp > 0 then table.insert(bits, "Unpicked: " .. table.concat(unp, ", ")) end
  local R = 0
  for _, row in ipairs(S.rows) do
    R = math.max(R, #row.locks)
    for k, v in pairs(row.edits or {}) do
      local rn = tonumber(k)
      if rn and v ~= "" and rn > R then R = rn end
    end
  end
  local round = math.floor(S.turns / math.max(1, #S.rows)) + 1
  local title = "ROOT BOX SCORE"
  if S.meta.game ~= nil and S.meta.game ~= "" then
    title = title .. " - " .. S.meta.game
  end
  local stamp = "round " .. round .. " - " .. os.date("%Y-%m-%d %H:%M")
  if S.exportBy ~= nil and S.exportBy ~= "" then
    stamp = stamp .. " - by " .. S.exportBy
  end
  local lines = { title .. " - " .. table.concat(bits, " / "), stamp }
  local head = string.format("%-11s %-17s", "faction", "player")
  for r = 1, R do head = head .. string.format("%4d", r) end
  table.insert(lines, head)
  for _, row in ipairs(S.rows) do
    local line = string.format("%-11s %-17s", row.fac:sub(1, 11),
      (row.player or ""):sub(1, 17))
    for r = 1, R do line = line .. string.format("%4s", cellText(row, r)) end
    table.insert(lines, line)
    if row.variant ~= nil and row.variant ~= "" then
      table.insert(lines, "  > " .. row.variant)
    end
    if S.experimental and row.crafts ~= nil and #row.crafts > 0 then
      local cs = {}
      for _, c in ipairs(row.crafts) do
        local tags = {}
        if c.r then table.insert(tags, "T" .. c.r) end
        if c.vp and c.vp > 0 then table.insert(tags, "+" .. c.vp) end
        table.insert(cs, c.item
          .. (#tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or ""))
      end
      table.insert(lines, "  > crafted: " .. table.concat(cs, ", "))
    end
  end
  return lines
end

-- fields are invisible until touched: transparent at rest, white while hovered
-- or being edited, so SETUP reads exactly like the printed sheet
local IF_COLORS = 'placeholder=" " colors="#00000000|#FFFFFFC0|#FFFFFF|#00000000"'
local BTN_DARK = 'colors="' .. WALNUT .. '|' .. RUST .. '|' .. GOLD .. '|#00000000" textColor="' .. PARCH .. '"'
local BTN_GOLD = 'colors="' .. GOLD .. '|' .. GOLDHI .. '|' .. RUST .. '|#00000000" textColor="' .. INKTXT .. '"'
local BTN_SOFT = 'colors="' .. PARCH2 .. '|' .. GOLDHI .. '|' .. GOLD .. '|#00000000" textColor="' .. RUST .. '"'
local NOClick = ' raycastTarget="false"' 

local lastScaleKey = ""

function rebuildUI()
  if S.hidden then
    self.UI.setXml("")
    return
  end
  local maxLocks = 0
  for _, row in ipairs(S.rows) do maxLocks = math.max(maxLocks, #row.locks) end
  local showR = math.min(math.max((S.cols or 10) + 1, maxLocks + 2), 41)
  local cellW = showR > 14 and 36 or 44
  local iconW, facW, nameW, liveW = 30, 118, 130, 48
  local btnW = 117
  local W = 54 + iconW + facW + nameW + (showR - 1) * cellW + liveW + btnW
  local rowH, headH = 40, 26
  local H = 56 + headH + math.max(1, #S.rows) * (rowH + 3) + 42
  local mul = SIZE_MULS[S.sizeIdx]

  -- The walnut cardboard extends FRAME px beyond the sheet on every side.
  -- That rim is bare object surface - outside the UI canvas entirely - so it
  -- is grabbable by construction, no matter how the UI treats clicks. The
  -- parchment area additionally lets clicks through via raycastTarget.
  local FRAME = 5
  local k = BASE_SCALE * mul / PX_PER_UNIT
  local ww = (W + 2 * FRAME) * k
  local wh = (H + 2 * FRAME) * k
  local key = string.format("%.2f|%.2f", ww, wh)
  if key ~= lastScaleKey and self.held_by_color == nil then
    lastScaleKey = key
    self.setScale({ ww, 0.18, wh })
  end
  local sx, sy
  if S.scaleMode == 1 then
    sx, sy = PX_PER_UNIT / (W + 2 * FRAME), PX_PER_UNIT / (H + 2 * FRAME)
  else
    sx, sy = BASE_SCALE * mul, BASE_SCALE * mul
  end
  local pose = UI_POSES[S.pose]

  local seatedNow = {}
  for _, p in ipairs(Player.getPlayers()) do
    if p.seated then seatedNow[p.color] = true end
  end

  local x = {}
  local function add(s) table.insert(x, s) end

  -- a Button whose label lives in a child Text: entities render correctly
  -- there (attribute strings do not decode them), and the label can be bold
  local function chip(id, handler, style, w, fs, textColor, label)
    local wattr = (w == 0) and 'flexibleWidth="1"' or ('preferredWidth="' .. w .. '"')
    add('<Button id="' .. id .. '" ' .. wattr .. ' ' .. style .. ' onClick="' .. handler .. '">'
      .. '<Text fontSize="' .. fs .. '" fontStyle="Bold" color="' .. textColor
      .. '" raycastTarget="false">' .. label .. '</Text></Button>')
  end

  add(string.format(
    '<Panel position="%s" rotation="%s" scale="%.4f %.4f 1" width="%d" height="%d" color="%s"%s>',
    pose.pos, pose.rot, sx, sy, W, H, PARCH, NOClick))
  add('<VerticalLayout padding="12 12 8 8" spacing="4">')

  -- header band: the printed title and game facts in play; the map / deck /
  -- unpicked / discord choices in setup - same height either way
  add('<HorizontalLayout preferredHeight="34" spacing="6">')
  local unp = unpickedList()
  if S.setup then
    add('<Text fontSize="15" fontStyle="Bold" color="' .. RUST .. '" alignment="MiddleLeft"'
      .. ' preferredWidth="44"' .. NOClick .. '>EDIT</Text>')
    add('<InputField id="mt_game" fontSize="13" preferredWidth="130" preferredHeight="20"'
      .. ' placeholder="GAME NAME" colors="' .. WALNUT .. '|#52381E|#52381E|#00000000"'
      .. ' textColor="' .. PARCH .. '" onValueChanged="uiLiveEdit" text="' .. esc(S.meta.game)
      .. '" onEndEdit="uiMetaEdit"/>')
    chip("mpbtn", "uiMapMenu", (S.overlay == "map") and BTN_GOLD or BTN_DARK, 84, 11,
      (S.overlay == "map") and INKTXT or PARCH,
      S.meta.map ~= "" and esc(S.meta.map) or "MAP")
    add('<Button id="dkbtn" preferredWidth="112" '
      .. ((S.overlay == "deck") and BTN_GOLD or BTN_DARK) .. ' onClick="uiDeckMenu">'
      .. '<Text fontSize="11" resizeTextForBestFit="true" resizeTextMinSize="8"'
      .. ' resizeTextMaxSize="11" fontStyle="Bold" color="'
      .. ((S.overlay == "deck") and INKTXT or PARCH) .. '" raycastTarget="false">'
      .. (S.meta.deck ~= "" and esc(S.meta.deck) or "DECK") .. '</Text></Button>')
    chip("pkbtn", "uiPicker", (S.overlay == "picker") and BTN_GOLD or BTN_DARK, 92, 11,
      (S.overlay == "picker") and INKTXT or PARCH, "UNPICKED")
    chip("dcbtn", "uiDiscord", (S.overlay == "discord") and BTN_GOLD or BTN_DARK, 70, 10,
      (S.overlay == "discord") and INKTXT or PARCH, "DISCORD")
    chip("xpbtn", "uiExperimental", S.experimental and BTN_GOLD or BTN_DARK, 62, 10,
      S.experimental and INKTXT or PARCH, "CRAFT")
    if S.experimental then
      chip("cebtn", "uiCraftMenu", (S.overlay == "craft") and BTN_GOLD or BTN_DARK, 58, 10,
        (S.overlay == "craft") and INKTXT or PARCH, "ITEMS")
    end
    chip("rsbtn", "uiReset", BTN_DARK, 56, 10, PARCH, "RESET")
  else
    add('<Text fontSize="18" fontStyle="Bold" color="' .. INKTXT .. '" alignment="MiddleLeft"'
      .. ' preferredWidth="330"' .. NOClick .. '>' .. spaced("ROOT") .. '&#160;&#160;&#183;&#160;&#160;'
      .. spaced("BOX SCORE") .. '</Text>')
    local bits = {}
    if S.meta.game ~= "" then table.insert(bits, esc(S.meta.game)) end
    if S.meta.map ~= "" then table.insert(bits, esc(S.meta.map)) end
    if S.meta.deck ~= "" then table.insert(bits, esc(S.meta.deck)) end
    if #unp > 0 then table.insert(bits, "Unpicked: " .. esc(table.concat(unp, ", "))) end
    add('<Text fontSize="15" fontStyle="Italic" color="' .. RUST .. '" alignment="MiddleRight"'
      .. ' flexibleWidth="1"' .. NOClick .. '>' .. table.concat(bits, "&#160;&#160;&#183;&#160;&#160;") .. '</Text>')
  end
  add('</HorizontalLayout>')

  add('<Panel preferredHeight="2" color="' .. GOLD .. '"' .. NOClick .. '/>')

  -- column headers; in setup the round numbers are buttons that set the turn
  add('<HorizontalLayout preferredHeight="' .. headH .. '" spacing="3">')
  add('<Text preferredWidth="' .. iconW .. '"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="' .. facW .. '"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="' .. nameW .. '"' .. NOClick .. '> </Text>')
  local curRound = math.floor(S.turns / math.max(1, #S.rows)) + 1
  for r = 1, showR - 1 do
    local isCur = (r == curRound)
    if S.setup then
      add('<Button id="colh_' .. r .. '" fontSize="15" fontStyle="Bold" preferredWidth="' .. cellW
        .. '" colors="' .. (isCur and GOLD or "#00000000") .. '|#FFFFFFC0|' .. GOLDHI
        .. '|#00000000" textColor="' .. (isCur and INKTXT or RUST)
        .. '" text="' .. r .. '" onClick="uiRowBtn"/>')
    elseif isCur then
      add('<Panel preferredWidth="' .. cellW .. '" color="' .. GOLD .. '"' .. NOClick
        .. '><Text fontSize="15" fontStyle="Bold" color="' .. INKTXT
        .. '" alignment="MiddleCenter"' .. NOClick .. '>' .. r .. '</Text></Panel>')
    else
      add('<Text fontSize="15" fontStyle="Bold" color="' .. RUST .. '" alignment="MiddleCenter" preferredWidth="'
        .. cellW .. '"' .. NOClick .. '>' .. r .. '</Text>')
    end
  end
  add('<Text preferredWidth="10"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="' .. liveW .. '"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="28"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="28"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="26"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="26"' .. NOClick .. '> </Text>')
  add('</HorizontalLayout>')

  -- faction rows
  for i, row in ipairs(S.rows) do
    local isActive = (i == S.active) and (fullTurnCoverage() or not turnsRunning())
    if #S.rows == 0 then isActive = false end
    local bg = isActive and GOLDHI or ((i % 2 == 1) and "#00000000" or PARCH2)
    add('<HorizontalLayout preferredHeight="' .. rowH .. '" spacing="3" color="' .. bg .. '"' .. NOClick .. '>')
    if S.setup then
      add('<Button id="act_' .. i .. '" preferredWidth="' .. iconW
        .. '" colors="#00000000|#FFFFFFC0|' .. GOLDHI .. '|#00000000" onClick="uiRowBtn">')
      if row.iconUrl and row.iconUrl ~= "" then
        add('<Image image="' .. assetName(row.fac) .. '" width="26" height="26"' .. NOClick .. '/>')
      else
        add('<Panel width="16" height="16" color="#' .. row.tintHex .. '"' .. NOClick .. '/>')
      end
      add('</Button>')
    elseif row.iconUrl and row.iconUrl ~= "" then
      add('<Panel preferredWidth="' .. iconW .. '"' .. NOClick .. '><Image image="' .. assetName(row.fac)
        .. '" width="26" height="26"' .. NOClick .. '/></Panel>')
    else
      add('<Panel preferredWidth="' .. iconW .. '"' .. NOClick .. '><Panel width="20" height="20" color="'
        .. WALNUT .. '"' .. NOClick .. '><Panel width="16" height="16" color="#' .. row.tintHex .. '"' .. NOClick .. '/></Panel></Panel>')
    end
    add('<VerticalLayout preferredWidth="' .. facW .. '" spacing="0">')
    local facName = esc(row.fac)
    add('<HorizontalLayout preferredHeight="22" spacing="2" childForceExpandWidth="false">')
    add('<Text fontSize="15" fontStyle="Bold" color="' .. INKTXT .. '" preferredWidth="'
      .. (facW - 30) .. '" alignment="MiddleLeft"' .. NOClick .. '>' .. facName .. '</Text>')
    if S.setup and variantOptions(row.fac) then
      chip("fv_" .. i, "uiRowBtn", 'colors="#00000000|#FFFFFFC0|' .. GOLDHI .. '|#00000000"',
        26, 18, "#8A7A64", "&#9660;")
    else
      add('<Text preferredWidth="26"' .. NOClick .. '> </Text>')
    end
    add('</HorizontalLayout>')
    if row.variant ~= nil and row.variant ~= "" then
      add('<Text fontSize="11" resizeTextForBestFit="true" resizeTextMinSize="6"'
        .. ' resizeTextMaxSize="11" fontStyle="Italic" color="' .. RUST .. '" preferredHeight="14"'
        .. ' alignment="UpperLeft"' .. NOClick .. '>' .. esc(row.variant) .. '</Text>')
    end
    add('</VerticalLayout>')
    if S.setup then
      add('<InputField id="nm_' .. i .. '" fontSize="15" textAlignment="MiddleCenter"'
        .. ' preferredWidth="' .. nameW
        .. '" ' .. IF_COLORS .. ' textColor="' .. RUST
        .. '" text="' .. fieldText(row.player) .. '" onValueChanged="uiLiveEdit" onEndEdit="uiNameEdit"/>')
    else
      add('<Text fontSize="15" color="' .. RUST .. '" alignment="MiddleCenter" preferredWidth="' .. nameW
        .. '"' .. NOClick .. '>' .. esc(row.player) .. '</Text>')
    end
    local craftIcons = {}
    if S.experimental then
      for _, c in ipairs(row.crafts or {}) do
        if c.r and c.img and c.img ~= "" then
          craftIcons[c.r] = craftIcons[c.r] or {}
          table.insert(craftIcons[c.r], c.img)
        end
      end
    end
    for r = 1, showR - 1 do
      add('<Panel preferredWidth="' .. cellW .. '"' .. NOClick .. '>')
      if S.setup then
        add('<InputField id="cl_' .. i .. '_' .. r .. '" fontSize="15" textAlignment="MiddleCenter"'
          .. ' width="' .. cellW .. '" height="' .. (rowH - 6)
          .. '" characterLimit="3" ' .. IF_COLORS .. ' textColor="' .. INKTXT
          .. '" text="' .. fieldText(cellText(row, r)) .. '" onValueChanged="uiLiveEdit" onEndEdit="uiCellEdit"/>')
      else
        add('<Text fontSize="15" color="' .. INKTXT
          .. '" alignment="MiddleCenter" width="' .. cellW .. '" height="' .. rowH .. '"' .. NOClick .. '>'
          .. esc(cellText(row, r)) .. '</Text>')
      end
      -- crafted-item figures climb the cell's right edge, clear of the number
      local ic = craftIcons[r]
      if ic then
        for k = 1, math.min(#ic, 6) do
          local col = math.floor((k - 1) / 3)
          local rw = (k - 1) % 3
          add('<Image image="it' .. urlTail(ic[k]) .. '" width="13" height="13"'
            .. ' rectAlignment="LowerRight" offsetXY="' .. (-1 - col * 13) .. ' ' .. (1 + rw * 13)
            .. '"' .. NOClick .. '/>')
        end
      end
      add('</Panel>')
    end
    local live = row.score >= 0 and tostring(row.score) or "&#8211;"
    add('<Text preferredWidth="10"' .. NOClick .. '> </Text>')
    add('<Panel preferredWidth="' .. liveW .. '" color="' .. GOLD .. '"' .. NOClick .. '>'
      .. '<Text fontSize="16" fontStyle="Bold" color="' .. INKTXT .. '" alignment="MiddleCenter"' .. NOClick .. '>'
      .. live .. '</Text></Panel>')
    chip("minus_" .. i, "uiRowBtn", BTN_SOFT, 28, 14, RUST, "&#8722;")
    chip("plus_" .. i, "uiRowBtn", BTN_SOFT, 28, 14, RUST, "+")
    if S.setup and i > 1 then
      chip("up_" .. i, "uiRowBtn", BTN_SOFT, 26, 11, RUST, "&#9650;")
    else
      add('<Text preferredWidth="26"' .. NOClick .. '> </Text>')
    end
    if S.setup then
      chip("del_" .. i, "uiRowBtn", BTN_SOFT, 26, 11, RUST, "&#215;")
    else
      add('<Text preferredWidth="26"' .. NOClick .. '> </Text>')
    end
    add('</HorizontalLayout>')
  end

  -- footer
  add('<HorizontalLayout preferredHeight="30" spacing="6" childForceExpandWidth="false">')
  if #S.rows > 0 and not fullTurnCoverage() then
    add('<Button fontSize="12" fontStyle="Bold" preferredWidth="84" ' .. BTN_GOLD
      .. ' text="END TURN" onClick="uiEndTurn"/>')
  end
  add('<Button fontSize="12" fontStyle="Bold" preferredWidth="66" ' .. BTN_SOFT .. ' text="EXPORT" onClick="uiExport"/>')
  add('<Button fontSize="12" fontStyle="Bold" preferredWidth="56" ' .. (S.setup and BTN_GOLD or BTN_SOFT)
    .. ' text="' .. (S.setup and "DONE" or "EDIT") .. '" onClick="uiSetup"/>')
  add('<Button fontSize="12" fontStyle="Bold" preferredWidth="52" '
    .. ((S.overlay == "info") and BTN_GOLD or BTN_SOFT) .. ' text="INFO" onClick="uiInfo"/>')
  local right = "made by MrDrouf&#160;&#160;&#183;&#160;&#160;" .. BUILD
  if S.lastExport ~= "" then
    right = "exported " .. S.lastExport .. "&#160;&#160;&#183;&#160;&#160;" .. right
  end
  add('<Text fontSize="12" fontStyle="Italic" color="' .. RUST .. '" alignment="MiddleRight" flexibleWidth="1"' .. NOClick .. '>'
    .. right .. '</Text>')
  add('</HorizontalLayout>')

  add('</VerticalLayout>')

  -- overlays float over the rows, so the sheet never changes size
  local PICK_DARK = 'colors="#57402A|' .. RUST .. '|' .. GOLD .. '|#00000000"'
  if S.setup and S.overlay == "picker" then
    local extraRows = 0
    for _, fac in ipairs(ROSTER) do
      if S.unpicked[fac] == true and variantOptions(fac) then extraRows = extraRows + 1 end
    end
    add('<Panel width="' .. (W - 100) .. '" height="' .. (128 + extraRows * 34) .. '" color="' .. WALNUT .. '">')
    add('<VerticalLayout padding="10 10 10 10" spacing="6">')
    for half = 1, 2 do
      add('<HorizontalLayout preferredHeight="46" spacing="5">')
      local from = (half - 1) * 7 + 1
      for ri = from, math.min(from + 6, #ROSTER) do
        local fac = ROSTER[ri]
        local sel = (S.unpicked[fac] == true)
        chip("pick_" .. ri, "uiRowBtn", sel and BTN_GOLD or PICK_DARK,
          0, 12, sel and INKTXT or PARCH, esc(fac))
      end
      if half == 2 then
        chip("pkdone", "uiOverlayClose", BTN_GOLD, 0, 12, INKTXT, "DONE")
      end
      add('</HorizontalLayout>')
    end
    for fi, fac in ipairs(ROSTER) do
      local opts = variantOptions(fac)
      if S.unpicked[fac] == true and opts then
        add('<HorizontalLayout preferredHeight="30" spacing="4">')
        add('<Text fontSize="12" fontStyle="Bold" color="' .. PARCH .. '" preferredWidth="64"'
          .. ' alignment="MiddleRight"' .. NOClick .. '>' .. esc(fac) .. ':</Text>')
        local chosen = {}
        for w in (S.unpickedVar[fac] or ""):gmatch("[^,]+") do
          chosen[w:match("^%s*(.-)%s*$")] = true
        end
        for ci2, ch in ipairs(opts) do
          chip("uv_" .. fi .. "_" .. ci2, "uiRowBtn",
            chosen[ch] and BTN_GOLD or PICK_DARK, 0, 9,
            chosen[ch] and INKTXT or PARCH, esc(ch))
        end
        add('</HorizontalLayout>')
      end
    end
    add('</VerticalLayout></Panel>')
  elseif S.overlay == "info" then
    add('<Panel width="' .. (W - 110) .. '" height="406" color="' .. WALNUT .. '">')
    add('<VerticalLayout padding="20 20 14 10" spacing="3">')
    local function section(t, h, b, last)
      add('<Text fontSize="12" fontStyle="Bold" color="' .. GOLD .. '" preferredHeight="17"'
        .. ' alignment="MiddleLeft"' .. NOClick .. '>' .. t .. '</Text>')
      add('<Text fontSize="11" color="' .. PARCH .. '" preferredHeight="' .. h .. '"'
        .. ' alignment="UpperLeft"' .. NOClick .. '>' .. b .. '</Text>')
      if not last then
        add('<Panel preferredHeight="1" color="#C9A05C50"' .. NOClick .. '/>')
      end
    end
    section("SCORES", 16,
      "Read automatically from the VP markers on the score track. The + and &#8722; buttons move the marker itself.")
    section("TURNS", 44,
      "Everything runs automatically once the TTS turn order is set and every faction has its seated player: each turn pass records the finishing faction by itself. Without that, END TURN records the highlighted faction. Each turn fills the first empty round column.")
    section("EDIT", 44,
      "Correct anything: scores (click a cell), the round (click a column number), whose turn it is (click a portrait), faction order (&#9650;), player names, the Eyrie commander / Knaves captains / vagabond character (&#9660;), map, deck, game name and the unpicked faction.")
    section("EXPORT", 30,
      "Posts the box score to Discord (set the webhook under DISCORD) and to the notebook. The footer reads confirmed with Discord once Discord has acknowledged the message.")
    section("CRAFT", 44,
      "Watches the map's item supply. An item taken from it and placed by a faction's board is recorded as crafted that round, with its picture on the round's score cell. Returning an item to the supply cancels the craft. In EDIT, the ITEMS button corrects or adds crafts: click T# to pick the round, &#215; removes, + adds. Turning CRAFT off hides all crafts, exports included.")
    section("RESET", 16,
      "Clears the sheet for a new game and re-detects map, deck, seats and markers.", true)
    add('<HorizontalLayout preferredHeight="30" spacing="6" childForceExpandWidth="false">')
    add('<Text flexibleWidth="1"' .. NOClick .. '> </Text>')
    add('<Button fontSize="13" fontStyle="Bold" preferredWidth="80" ' .. BTN_GOLD
      .. ' text="DONE" onClick="uiOverlayClose"/>')
    add('</HorizontalLayout>')
    add('</VerticalLayout></Panel>')
  elseif S.setup and S.overlay == "game" then
    add('<Panel width="' .. (W - 420) .. '" height="66" color="' .. WALNUT .. '">')
    add('<HorizontalLayout padding="12 12 12 12" spacing="6">')
    add('<Text fontSize="13" fontStyle="Bold" color="' .. PARCH .. '" preferredWidth="90"'
      .. ' alignment="MiddleRight"' .. NOClick .. '>game name</Text>')
    add('<InputField id="mt_game" fontSize="13" flexibleWidth="1"'
      .. ' colors="#F1E5C8|#FFFFFF|#FFFFFF|#00000000" textColor="' .. INKTXT
      .. '" onValueChanged="uiLiveEdit" text="' .. fieldText(S.meta.game)
      .. '" onEndEdit="uiMetaEdit"/>')
    add('<Button fontSize="13" fontStyle="Bold" preferredWidth="70" ' .. BTN_GOLD
      .. ' text="DONE" onClick="uiOverlayClose"/>')
    add('</HorizontalLayout></Panel>')
  elseif S.setup and S.overlay == "map" then
    add('<Panel width="' .. (W - 200) .. '" height="64" color="' .. WALNUT .. '">')
    add('<HorizontalLayout padding="10 10 10 10" spacing="5">')
    for mi, m in ipairs(MAPS) do
      local sel = (S.meta.map == m)
      chip("map_" .. mi, "uiRowBtn", sel and BTN_GOLD or PICK_DARK, 0, 12,
        sel and INKTXT or PARCH, esc(m))
    end
    chip("mpdone", "uiOverlayClose", BTN_GOLD, 0, 12, INKTXT, "DONE")
    add('</HorizontalLayout></Panel>')
  elseif S.setup and S.overlay == "deck" then
    add('<Panel width="' .. (W - 200) .. '" height="64" color="' .. WALNUT .. '">')
    add('<HorizontalLayout padding="10 10 10 10" spacing="5">')
    for di, d in ipairs(DECKS) do
      local sel = (S.meta.deck == d)
      chip("deck_" .. di, "uiRowBtn", sel and BTN_GOLD or PICK_DARK, 0, 12,
        sel and INKTXT or PARCH, esc(d))
    end
    chip("dkdone", "uiOverlayClose", BTN_GOLD, 0, 12, INKTXT, "DONE")
    add('</HorizontalLayout></Panel>')
  elseif S.setup and S.overlay == "var" then
    local row = S.rows[S.varRow]
    local opts = row and variantOptions(row.fac) or nil
    if row and opts then
      local chosen = {}
      for w in (row.variant or ""):gmatch("[^,]+") do
        chosen[w:match("^%s*(.-)%s*$")] = true
      end
      add('<Panel width="' .. (W - 140) .. '" height="118" color="' .. WALNUT .. '">')
      add('<VerticalLayout padding="10 10 10 10" spacing="6">')
      add('<Text fontSize="14" fontStyle="Bold" color="' .. PARCH .. '" preferredHeight="18"' .. NOClick .. '>'
        .. esc(row.fac) .. ' &#8211; pick the character(s)</Text>')
      for half = 1, 2 do
        add('<HorizontalLayout preferredHeight="34" spacing="4">')
        local from = (half - 1) * 6 + 1
        for oi = from, math.min(from + 5, #opts) do
          chip("vc_" .. oi, "uiRowBtn", chosen[opts[oi]] and BTN_GOLD or PICK_DARK,
            0, 10, chosen[opts[oi]] and INKTXT or PARCH, esc(opts[oi]))
        end
        if half == 2 then
          chip("vcdone", "uiOverlayClose", BTN_GOLD, 0, 11, INKTXT, "DONE")
        end
        add('</HorizontalLayout>')
      end
      add('</VerticalLayout></Panel>')
    end
  elseif S.setup and S.experimental and S.overlay == "craft" then
    local hh = 74 + #S.rows * 32 + ((S.craftAdd or S.craftPick) and 30 or 0)
    add('<Panel width="' .. (W - 120) .. '" height="' .. hh .. '" color="' .. WALNUT .. '">')
    add('<VerticalLayout padding="10 10 8 8" spacing="4">')
    add('<Text fontSize="12" fontStyle="Bold" color="' .. PARCH .. '" preferredHeight="16"'
      .. ' alignment="MiddleLeft"' .. NOClick
      .. '>CRAFTED ITEMS &#8211; click T# to set the round, &#215; removes, + adds</Text>')
    for ci3, row in ipairs(S.rows) do
      add('<HorizontalLayout preferredHeight="28" spacing="4" childForceExpandWidth="false">')
      add('<Text fontSize="12" fontStyle="Bold" color="' .. PARCH .. '" preferredWidth="90"'
        .. ' alignment="MiddleRight"' .. NOClick .. '>' .. esc(row.fac) .. '</Text>')
      for k, c in ipairs(row.crafts or {}) do
        if c.img and c.img ~= "" then
          add('<Panel preferredWidth="20"' .. NOClick .. '><Image image="it' .. urlTail(c.img)
            .. '" width="18" height="18"' .. NOClick .. '/></Panel>')
        end
        add('<Text fontSize="11" color="' .. PARCH .. '" preferredWidth="56" alignment="MiddleLeft"'
          .. NOClick .. '>' .. esc(c.item) .. '</Text>')
        local selT = S.craftPick ~= nil and S.craftPick.i == ci3 and S.craftPick.k == k
        chip("cfr_" .. ci3 .. "_" .. k, "uiCraftBtn", selT and BTN_GOLD or PICK_DARK, 32, 10,
          selT and INKTXT or PARCH, "T" .. tostring(c.r or "?"))
        chip("cfx_" .. ci3 .. "_" .. k, "uiCraftBtn", PICK_DARK, 24, 10, PARCH, "&#215;")
        add('<Text preferredWidth="4"' .. NOClick .. '> </Text>')
      end
      chip("cfadd_" .. ci3, "uiCraftBtn", (S.craftAdd == ci3) and BTN_GOLD or PICK_DARK, 26, 12,
        (S.craftAdd == ci3) and INKTXT or PARCH, "+")
      add('</HorizontalLayout>')
    end
    if S.craftPick ~= nil then
      add('<HorizontalLayout preferredHeight="26" spacing="4" childForceExpandWidth="false">')
      add('<Text fontSize="11" fontStyle="Bold" color="' .. GOLD .. '" preferredWidth="90"'
        .. ' alignment="MiddleRight"' .. NOClick .. '>round:</Text>')
      for r2 = 1, math.max(1, S.cols or 10) do
        chip("cfpick_" .. r2, "uiCraftBtn", PICK_DARK, 34, 10, PARCH, "T" .. r2)
      end
      add('</HorizontalLayout>')
    end
    if S.craftAdd ~= nil and S.rows[S.craftAdd] ~= nil then
      add('<HorizontalLayout preferredHeight="26" spacing="4" childForceExpandWidth="false">')
      add('<Text fontSize="11" fontStyle="Bold" color="' .. GOLD .. '" preferredWidth="90"'
        .. ' alignment="MiddleRight"' .. NOClick .. '>add:</Text>')
      for k, nm in ipairs(ITEM_NAMES) do
        chip("cfnew_" .. k, "uiCraftBtn", PICK_DARK, 74, 10, PARCH, esc(nm))
      end
      add('</HorizontalLayout>')
    end
    add('<HorizontalLayout preferredHeight="26" spacing="6" childForceExpandWidth="false">')
    add('<Text flexibleWidth="1"' .. NOClick .. '> </Text>')
    add('<Button fontSize="12" fontStyle="Bold" preferredWidth="70" ' .. BTN_GOLD
      .. ' text="DONE" onClick="uiOverlayClose"/>')
    add('</HorizontalLayout>')
    add('</VerticalLayout></Panel>')
  elseif S.setup and S.overlay == "discord" then
    add('<Panel width="' .. (W - 160) .. '" height="118" color="' .. WALNUT .. '">')
    add('<VerticalLayout padding="12 12 10 10" spacing="6">')
    add('<HorizontalLayout preferredHeight="30" spacing="6">')
    add('<Text fontSize="14" fontStyle="Bold" color="' .. PARCH .. '" preferredWidth="72" alignment="MiddleRight"' .. NOClick .. '>webhook</Text>')
    add('<InputField id="mt_hook" fontSize="13" flexibleWidth="1" colors="#F1E5C8|#FFFFFF|#FFFFFF|#00000000"'
      .. ' textColor="' .. INKTXT .. '" placeholder="Discord webhook URL"'
      .. ' text="' .. fieldText(S.meta.hook) .. '" onEndEdit="uiMetaEdit"/>')
    add('</HorizontalLayout>')
    add('<HorizontalLayout preferredHeight="30" spacing="6">')
    add('<Text fontSize="14" fontStyle="Bold" color="' .. PARCH .. '" preferredWidth="72" alignment="MiddleRight"' .. NOClick .. '>thread</Text>')
    add('<InputField id="mt_thread" fontSize="13" flexibleWidth="1" colors="#F1E5C8|#FFFFFF|#FFFFFF|#00000000"'
      .. ' textColor="' .. INKTXT .. '" placeholder="thread link (optional)"'
      .. ' text="' .. fieldText(S.meta.thread) .. '" onEndEdit="uiMetaEdit"/>')
    add('<Button fontSize="13" fontStyle="Bold" preferredWidth="70" ' .. BTN_GOLD
      .. ' text="DONE" onClick="uiOverlayClose"/>')
    add('</HorizontalLayout>')
    add('</VerticalLayout></Panel>')
  end

  add('</Panel>')
  self.UI.setXml(table.concat(x))
end

---------------------------------------------------------------- persistence --
function onSave()
  return JSON.encode(S)
end

function onLoad(saved)
  if saved ~= nil and saved ~= "" then
    local ok, d = pcall(function() return JSON.decode(saved) end)
    if ok and d ~= nil and d.rows ~= nil then S = d end
  end
  S.meta = S.meta or { map = "", deck = "", hook = "", thread = "" }
  S.meta.deck = S.meta.deck or ""
  -- old builds stored pre-escaped text; normalize once so it can never
  -- round-trip into the display again
  S.meta.deck = S.meta.deck:gsub("&amp;", "+"):gsub("&#38;", "+"):gsub("&", "+")
  S.meta.map = (S.meta.map or ""):gsub("&amp;", "&"):gsub("&#38;", "&")
  S.meta.hook = S.meta.hook or ""
  S.meta.thread = S.meta.thread or ""
  S.meta.game = S.meta.game or ""
  -- a webhook baked into GMNotes (by build.py) is the default
  if S.meta.hook == "" then
    local gm = self.getGMNotes() or ""
    if gm:match("^https?://") then S.meta.hook = gm:gsub("%s+$", "") end
  end
  S.undo = S.undo or {}
  S.log = S.log or {}
  S.unpicked = S.unpicked or {}
  S.unpickedVar = S.unpickedVar or {}
  S.varRow = S.varRow or 1
  S.experimental = S.experimental or false
  S.itemImgs = S.itemImgs or {}
  S.turns = S.turns or 0
  S.active = S.active or 1
  if S.active > math.max(1, #S.rows) then S.active = 1 end
  for _, row in ipairs(S.rows) do
    row.locks = row.locks or {}
    row.edits = row.edits or {}
    row.crafts = row.crafts or nil
    row.score = row.score or -1
    row.player = row.player or ""
  end
  S.cols = S.cols or 10
  S.scaleMode = S.scaleMode or 1
  S.sizeIdx = S.sizeIdx or 2
  S.setup = S.setup or false
  S.overlay = nil
  S.lastExport = S.lastExport or ""

  self.addContextMenuItem("setup / done", uiSetup, false)
  self.addContextMenuItem("reset box score", uiReset, false)
  self.addContextMenuItem("hide / show", uiHide, false)
  self.addContextMenuItem("export", uiExport, false)
  self.addContextMenuItem("flip track", uiFlip, false)
  self.addContextMenuItem("spin panel", uiSpin, false)
  self.addContextMenuItem("panel size", uiSize, false)
  self.addContextMenuItem("panel scale mode", uiScaleMode, false)
  self.addContextMenuItem("diagnose", uiDiag, false)

  Wait.time(function()
    findTrack()
    for _, row in ipairs(S.rows) do
      local m = findMarker(row)
      if m then row.iconUrl = markerImage(m) end
    end
    refreshAssets()
    rebuildUI()
    Wait.time(poll, POLL_SECONDS, -1)
  end, 2)
end
