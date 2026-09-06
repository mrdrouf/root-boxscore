-- Root Box Score
-- Automated per-turn scorekeeping for Root - Ultimate Collection (workshop 2516434159).
--
-- Score reading (no vision): every faction's VP marker is a named object
-- ("Marquise VP", ...). The map token carries the printed 0-30 track as snap
-- points (31 columns x 3 sub-rows on every map checked), found geometrically
-- in the map's LOCAL coordinates - any map, anywhere, any rotation. A marker's
-- score is the nearest track column to positionToLocal(marker position).
--
-- Turn integration: row order follows each faction's physical seat position, the
-- active faction follows Turns.turn_color, and every turn pass locks the score
-- of the faction whose turn just ended. RTT publishes faction-keyed seats; other
-- tables fall back to the faction supply/board anchor itself. Hand zones are used
-- only to associate factions with player colors and live display names. Without
-- the turn system, END TURN cycles the rows manually.
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
-- log() is NOT editor-only: it also lands in the in-game chat log, so every
-- debug message must stay behind this gate (the sheet is silent by contract).
-- Flip at runtime with boxDebug(true) over the External Editor API.
local DEBUG = false
local function dbg(m) if DEBUG then log(m) end end
function boxDebug(v)
  if type(v) == "table" then v = v[1] end
  DEBUG = (v == true)
end
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

-- NO custom font here. TTS's setCustomAssets only accepts image formats -- a .ttf is rejected with
-- "Load image failed unsupported format: UNKNOWN" and the error repeats on every rebuild. A custom UI
-- font has to be registered through the Custom UI Assets PANEL, which a script cannot do, so the sheet
-- stays on TTS's default face.

-- palette: walnut board, parchment sheet, ink, rust and wax-seal gold
-- the single notebook tab the export writes; declared here so uiExport can see it
local NOTEBOOK_TAB = "BoxScore"

local WALNUT  = "#2B1A0C"
local PARCH   = "#F1E5C8"
local PARCH2  = "#E7D8B4"
local GOLD    = "#C9A05C"
local GOLDHI  = "#E4C88E"
local INKTXT  = "#26170B"
local RUST    = "#7E4A1E"

local DECKS = { "Base Deck", "Exiles and Partisans", "Squires and Disciples" }

-- Every standard dominance card in the mod is a Card named "Dominance" whose
-- description is its suit. Frog dominance cards also exist, but Root's normal
-- VP-marker dominance play uses only these four suits.
local DOM_SUITS = { fox = true, mouse = true, rabbit = true, bird = true }

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

-- TWO VAGABONDS ARE TWO ROWS. Root allows two, and the faction ships two score markers -- a white one
-- and a black one -- for exactly that. A box-score row IS its marker's name, so the second vagabond's
-- marker is named "Vagabond 2 VP" and its row is "Vagabond 2"; anything else and both players collapse
-- onto one row, with the second showing no score at all and both markers reading into the first.
-- Every rule that asks "is this a vagabond?" therefore has to ask about the BASE faction.
local function baseFac(fac)
  if type(fac) ~= "string" then return fac end
  return (fac:gsub("%s+%d+$", ""))
end

-- which factions carry a pickable detail, and its options
local LEADERS = { "Builder", "Charismatic", "Commander", "Despot" }
local function variantOptions(fac)
  fac = baseFac(fac)
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
-- 100% preserves the sheet's historical default footprint (the old size index
-- used 0.7).  The legacy values remain only to migrate existing saved sheets.
local LEGACY_SIZE_MULS = { 0.55, 0.7, 0.85, 1.05, 1.3, 1.6 }
local LEGACY_BASE_MUL = 0.7
local SIZE_MIN_PCT, SIZE_MAX_PCT = 50, 200

----------------------------------------------------------------------- state --
local S = {
  rows      = {},   -- { fac, player, nameAuto, color, tintHex, iconUrl, guid,
                    --   score, locks={}, edits={},
                    --   dom={turn,round,suit,score,won,kind,frozen,markerGuid} }
  active    = 1,
  turns     = 0,
  -- THE ROUND, declared rather than divided out. It used to be computed everywhere as
  -- floor(S.turns / #S.rows) + 1, which makes the CURRENT row count a divisor of the WHOLE history:
  -- a row appearing or disappearing mid-game retroactively re-maps every past and future lock, so a
  -- column comes out blank or two rounds show the same numbers. The same formula also assumes
  -- "locks per round == #S.rows", which is false the moment one seat's colour never gets a turn --
  -- then every round after it lags a column behind for the rest of the game. Both of the reported
  -- box-score symptoms ("it skipped or omitted a number", "it tracked things weirdly") come out of
  -- that one expression. The round now only ever moves when a row that has ALREADY locked this round
  -- locks again, which is the actual definition of the table having come round.
  round     = 1,
  -- One-shot latch: until a turn is actually recorded the pointer is held on
  -- the FIRST SEAT. Cleared by the first lock or by any explicit pointer move
  -- (row select / undo), never re-armed mid-game. Persisted with the rest of S,
  -- so a pre-first-turn save reloads still pinned and an older save reads nil
  -- (falsy) and is correctly left alone.
  pinFirst  = true,
  cols      = 10,   -- round columns always shown: fixed size during the game,
                    -- growing only past round 10 (setup-editable)
  flip      = false,
  hidden    = false,
  setup     = false,
  pose      = 1,
  scaleMode = 1,
  sizePct   = 100,
  meta      = { map = "", deck = "", hook = "", thread = "", game = "" },
  unpicked  = {},   -- fac -> true (picked by hand from the roster)
  unpickedVar = {}, -- fac -> "cap1, cap2" (captains available in the draft)
  varRow    = 1,
  experimental = false,
  lastExport = "",
  log       = {},
  undo      = {},   -- faction NAMES (row order can change underneath)
}

-- ONE reader for the round, so no caller can invent its own definition again.
local function currentRound()
  local r = math.floor(tonumber(S.round) or 1)
  if r < 1 then r = 1 end
  return r
end

local TRACK = nil
local lastTrackLogged = nil
local pollCount = 0

------------------------------------------------------------------- utilities --
local function now() return os.time() end

local function clampSizePct(value)
  return math.max(SIZE_MIN_PCT, math.min(SIZE_MAX_PCT,
    math.floor((tonumber(value) or 100) + 0.5)))
end

-- RTT destroys and recreates the sheet when its map/ranked/tool buttons spawn
-- one.  The saved S.sizePct handles normal reloads; this Global is only the
-- in-session hand-off between the old object and its freshly spawned copy.
local function rememberSizePct()
  pcall(function() Global.setVar("RTT_BOXSCORE_SIZE_PCT", S.sizePct) end)
end

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

-- TTS exposes the active color but no monotonic turn number. S.turns is the
-- persisted count of completed turns, so the turn in progress is the next one.
local function currentTurnNumber()
  return math.max(1, math.floor(tonumber(S.turns) or 0) + 1)
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
    if TRACK.guid ~= lastTrackLogged then
      lastTrackLogged = TRACK.guid
      dbg("BoxScore: track on " .. TRACK.guid .. " axis=" .. TRACK.axis
        .. " cells=" .. TRACK.n .. " rows=" .. #TRACK.rows)
    end
  else
    dbg("BoxScore: no score track found on any snap holder")
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

local function dominanceCardSuit(o)
  if o == nil or (o.type ~= "Card" and o.tag ~= "Card") then return nil end
  local okn, name = pcall(function() return o.getName() end)
  if not okn or tostring(name or ""):lower() ~= "dominance" then return nil end
  local okd, desc = pcall(function() return o.getDescription() end)
  if not okd then return nil end
  local suit = tostring(desc or ""):match("^%s*(.-)%s*$"):lower()
  return DOM_SUITS[suit] and suit or nil
end

-- Dominance is declared by physically putting the VP marker on the card. Use
-- the card's live bounds (rather than CardIDs, which differ among deck copies)
-- and require both objects to have settled before accepting the placement.
local function objectSettled(o)
  if o == nil or o.held_by_color ~= nil then return false end
  local okm, moving = pcall(function() return o.isSmoothMoving() end)
  if okm and moving then return false end
  local okr, resting = pcall(function() return o.resting end)
  if okr and resting == false then return false end
  return true
end

local function markerSitsOnCard(marker, card)
  if not objectSettled(marker) or not objectSettled(card) then return false end
  local okb, b = pcall(function() return card.getBounds() end)
  if not okb or b == nil or b.center == nil or b.size == nil then return false end
  local mp = marker.getPosition()
  local cx, cy, cz = b.center.x or b.center[1], b.center.y or b.center[2],
    b.center.z or b.center[3]
  local sx, sy, sz = b.size.x or b.size[1], b.size.y or b.size[2],
    b.size.z or b.size[3]
  if not cx or not cy or not cz or not sx or not sy or not sz then return false end
  local dy = mp.y - cy
  return math.abs(mp.x - cx) <= sx * 0.5 + 0.2
    and math.abs(mp.z - cz) <= sz * 0.5 + 0.2
    and dy >= -0.25 and dy <= math.max(3.0, sy + 2.0)
end

local function dominanceAt(marker, cards)
  for _, c in ipairs(cards) do
    if markerSitsOnCard(marker, c.obj) then return c.suit end
  end
  return nil
end

-- Count every copy of this faction's VP marker by settled location. This is
-- deliberately independent of row.guid: Brazen Demagogue leaves the cached
-- original on the score track and puts a copied marker on a dominance card.
local function dominanceMarkerState(row, cards, objects)
  local state = { domCount = 0, trackCount = 0, looseCount = 0,
    unsettledCount = 0, suit = nil, domMarker = nil,
    trackMarker = nil, trackIdx = nil }
  if row == nil then return state end
  local markerName = row.fac .. " VP"
  for _, marker in ipairs(objects or getAllObjects()) do
    if (marker.getName() or "") == markerName then
      if not objectSettled(marker) then
        state.unsettledCount = state.unsettledCount + 1
      else
        local suit = dominanceAt(marker, cards)
        if suit ~= nil then
          state.domCount = state.domCount + 1
          if state.domMarker == nil then
            state.domMarker, state.suit = marker, suit
          end
        else
          local idx = readCell(marker)
          if idx ~= nil then
            state.trackCount = state.trackCount + 1
            -- Prefer the already-cached original if more than one marker has
            -- somehow been left on the track.
            if state.trackMarker == nil or marker.getGUID() == row.guid then
              state.trackMarker, state.trackIdx = marker, idx
            end
          else
            state.looseCount = state.looseCount + 1
          end
        end
      end
    end
  end
  if state.trackMarker ~= nil then row.guid = state.trackMarker.getGUID() end
  return state
end

-- Coalition (Root, Vagabond, 4+ players): a Vagabond cannot rule, so instead of activating a
-- dominance card for dominance it forms a coalition -- its score marker leaves the track onto an
-- ally's board, it stops scoring, and it wins if that ally wins. The ally must be the player with
-- the FEWEST points (choose among ties) and must not have activated a dominance card themselves.
-- The fewest-points part is a judgement at the moment of play, so the button offers the eligible
-- rows rather than picking for you; ineligible ones are simply not offered.
local COALITION_FACTIONS = { Vagabond = true, Knaves = true }

local function canCoalition(row)
  return row ~= nil and COALITION_FACTIONS[baseFac(row.fac)] == true
end

local function coalitionCandidates(row)
  local out = {}
  for _, other in ipairs(S.rows) do
    -- not yourself, not another vagabond, and not someone who has already activated dominance
    if other.fac ~= row.fac and not COALITION_FACTIONS[other.fac] and other.dom == nil then
      table.insert(out, other.fac)
    end
  end
  return out
end

local function dominanceFrozen(row)
  return row ~= nil and row.dom ~= nil and row.dom.frozen ~= false
end

local function dominanceKindLabel(dom)
  if dom ~= nil and dom.kind == "brazen_demagogue" then
    return "Brazen Demagogue (still scoring)"
  end
  return "standard (frozen)"
end

local function registerDominance(row, state)
  local suit = state and state.suit or nil
  if row == nil or row.dom ~= nil or not DOM_SUITS[suit] then return false end
  local brazen = (state.trackCount or 0) > 0
  row.dom = { turn = currentTurnNumber(),
    round = currentRound(),
    suit = suit, score = row.score, won = false,
    kind = brazen and "brazen_demagogue" or "standard",
    frozen = not brazen,
    markerGuid = state.domMarker and state.domMarker.getGUID() or nil }
  logev("dominance", row.fac, row.dom.turn, suit)
  return true
end

local function cancelDominance(row)
  if row == nil or row.dom == nil then return false end
  local dom = row.dom
  -- Standard dominance restores its declaration-time score. Brazen has kept
  -- reading the original track marker, so rewinding here would discard VP.
  if dom.frozen ~= false then row.score = tonumber(dom.score) or row.score end
  row.dom = nil
  if S.winner == row.fac and S.winnerReason == "dominance" then
    S.winner = nil
    S.winnerReason = nil
    S.winnerLock = nil
  end
  logev("dominance-undo", row.fac, dom.turn, dom.suit)
  return true
end

-- true = the declaration marker is still on a card; false = it settled away;
-- nil = it is currently held/moving, so do not make a transient state change.
local function dominanceMarkerActive(row, state, cards)
  if row == nil or row.dom == nil then return false end
  local guid = row.dom.markerGuid
  if guid ~= nil and guid ~= "" then
    local marker = getObjectFromGUID(guid)
    if marker == nil or (marker.getName() or "") ~= (row.fac .. " VP") then
      return false
    end
    if not objectSettled(marker) then return nil end
    return dominanceAt(marker, cards) ~= nil
  end
  -- Migrate an already-active declaration saved by a pre-markerGuid build.
  if state.domMarker ~= nil then
    row.dom.markerGuid = state.domMarker.getGUID()
    return true
  end
  if state.unsettledCount > 0 then return nil end
  return false
end

local function syncDominance(row, cards, objects)
  local state = dominanceMarkerState(row, cards, objects)
  local changed = false
  if row.dom ~= nil and dominanceMarkerActive(row, state, cards) == false then
    changed = cancelDominance(row) or changed
  end
  if row.dom == nil and state.domCount > 0 then
    changed = registerDominance(row, state) or changed
  end
  -- Re-classify a STILL-ACTIVE declaration when the track copy changes. Brazen Demagogue needs a marker
  -- on the track AND one on a dominance card. If the maintainer copied a marker onto the card (registered
  -- brazen, still scoring) and then ERASED the original track marker, it is now a STANDARD dominance play:
  -- freeze the score and show the hyphen. The reverse (a standard play that later gains a track copy)
  -- becomes brazen and resumes scoring.
  if row.dom ~= nil and dominanceMarkerActive(row, state, cards) == true then
    local wantBrazen = (state.trackCount or 0) > 0
    if wantBrazen and row.dom.kind ~= "brazen_demagogue" then
      row.dom.kind = "brazen_demagogue"; row.dom.frozen = false
      changed = true; logev("dominance-reclass", row.fac, "brazen")
    elseif (not wantBrazen) and row.dom.kind == "brazen_demagogue" then
      row.dom.score = row.score; row.dom.kind = "standard"; row.dom.frozen = true
      changed = true; logev("dominance-reclass", row.fac, "standard")
    end
  end
  return state, changed
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
-- the "Keeper Supply" - verified against the mod's own spawn data). The
-- Vagabond has no supply at all: his FACTION BOARD anchors him, identified
-- by its artwork since boards carry no usable name - the board never moves
-- once set up, unlike his pawn, which wanders the map (and can do so before
-- the VP marker ever reaches the track). The named pawn figurine
-- ("Vagabond - Thief", ...) is only a last resort.
local SUPPLY_ALIAS = { Rats = "Hundreds", Crows = "Corvid", Badgers = "Keeper" }
local BOARD_ART = {
  Vagabond = "E9FFF39312426A1A13695C984510BB94B663436F",
}

local function facAnchor(fac, byName)
  byName = byName or {}   -- defensive: never index a nil table (audit: seat-box crash)
  fac = baseFac(fac)      -- "Vagabond 2" has no pieces of its own; it uses the vagabond's
  local o = byName[fac .. " Supply"]
  if o == nil and SUPPLY_ALIAS[fac] ~= nil then
    o = byName[SUPPLY_ALIAS[fac] .. " Supply"]
  end
  if o == nil and BOARD_ART[fac] ~= nil then
    for _, c in ipairs(getAllObjects()) do
      -- markerImage returns NIL for anything with no custom object -- a die, a bag, a scripting zone,
      -- and for a custom object carrying none of image/face/diffuse. `nil ~= ""` is TRUE, so the old
      -- test fell straight through to img:find and crashed on the first such object on the table.
      -- Only the Vagabond reaches this branch (it is the one entry in BOARD_ART), which is why it
      -- showed up as an error the moment a Vagabond row was created.
      local img = markerImage(c)
      if img ~= nil and img ~= "" and img:find(BOARD_ART[fac], 1, true) then
        o = c
        break
      end
    end
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

-- Assigned further down, once rttFieldMap exists. Declared HERE because refreshVariants is above it
-- and a `local` referenced before its declaration compiles to a nil GLOBAL -- the "local declared
-- after use" trap this file has shipped twice.
local rttCharOf = nil

-- Best effort: find the chosen vagabond character / captain card standing
-- near the faction's supply. Fills the variant only while it is auto-managed;
-- a hand-typed variant always wins.
local function refreshVariants(byName)
  local changed = false
  for _, row in ipairs(S.rows) do
    if row.variantAuto ~= false then
      -- RTT knows exactly which character each seat is playing, so ask it before measuring anything.
      -- Geometry cannot separate two vagabonds: they share one board ART, so facAnchor hands BOTH
      -- rows the same object and the nearest-pawn search would give them the same character.
      local told = rttCharOf ~= nil and rttCharOf(row.fac) or nil
      if told ~= nil and told ~= "" and row.variant ~= told then
        row.variant = told; changed = true
      end
      local bag = (told == nil or told == "") and facAnchor(row.fac, byName) or nil
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

-- TTS's ten playable colors are stable even when nobody occupies them. Query
-- each color directly: getHandTransform returns its hand-zone geometry without
-- requiring a live Player entry. Some tables omit colors/hand zones, so every
-- lookup is guarded. If this API yields nothing at all, retain the old live-seat
-- behavior as a safe fallback.
local PLAYER_COLORS = {
  "White", "Brown", "Red", "Orange", "Yellow",
  "Green", "Teal", "Blue", "Purple", "Pink",
}

-- ==== RTT'S SEAT RECORD ====================================================
-- RTT keeps ONE record of who sits where, in what colour, playing what, and PUSHES it here whenever
-- it changes -- seating, a faction placed, a colour change. It arrives as a JSON string (raw Lua
-- tables do not cross object-script boundaries) and is kept in S, so onSave carries it through a
-- reload and a crash.
--
-- This replaces re-reading three TTS Globals every six seconds. Globals are WIPED on load, so after a
-- reload the sheet silently fell back to guessing each row's colour from the nearest hand zone --
-- rows re-tinted to colours nobody occupies, and turns attributed to the wrong row. The pushed record
-- survives, so there is nothing to fall back to.
--
-- The Globals are still read, but only as a fallback: an older RTT bake that does not push, or a
-- plain Root table with no RTT at all, where the geometric pass is the only thing there is.
-- Declared HERE, above its only writer and its only reader. `dirty` is a local several hundred lines
-- below; assigning to it from up here would silently compile to a GLOBAL and never reach the poll --
-- the same "local declared after use" trap that has already broken this file twice.
local seatPushPending = false

function rttSeatPush(enc)
  local ok, d = pcall(function() return JSON.decode(enc) end)
  if not ok or type(d) ~= "table" or type(d.seats) ~= "table" then return end
  S.rttSeats = d
  seatPushPending = true          -- picked up on the very next poll tick, not up to six seconds later
end

-- The record, from wherever it can be had: what was pushed to us first, then RTT's mirror Global.
local function rttRecord()
  if type(S.rttSeats) == "table" and type(S.rttSeats.seats) == "table"
     and #S.rttSeats.seats > 0 then return S.rttSeats end
  local ok, raw = pcall(function() return Global.getVar("RTT_SEAT_RECORD") end)
  if ok and type(raw) == "string" and raw ~= "" then
    local ok2, d = pcall(function() return JSON.decode(raw) end)
    if ok2 and type(d) == "table" and type(d.seats) == "table" and #d.seats > 0 then
      S.rttSeats = d
      return d
    end
  end
  return nil
end

-- ROW NAME -> field, straight off the record.
--
-- Keyed by the seat's `key`, NOT its `faction`. They differ for exactly the case this whole section
-- exists for: a vagabond seat's `faction` is the CHARACTER it is playing ("Ranger") while its `key`
-- is the row the sheet shows ("Vagabond", or "Vagabond 2" for the second). Keying by faction here
-- built a map nothing could look itself up in -- refreshSeats asks for rttCol["Vagabond"] and would
-- have found only rttCol["Ranger"], so a vagabond row silently lost its colour, its owner and its
-- position and fell back to the geometric guess. `faction` is still readable through this, which is
-- how the character reaches the variant column.
local function rttFieldMap(field)
  local rec = rttRecord()
  if rec == nil then return nil end
  local m, any = {}, false
  for _, e in ipairs(rec.seats) do
    local k = (type(e) == "table") and ((e.key ~= nil and e.key ~= "") and e.key or e.faction) or nil
    if k ~= nil and k ~= "" and e[field] ~= nil and e[field] ~= "" then
      m[k] = e[field]; any = true
    end
  end
  if not any then return nil end
  return m
end

-- The character RTT recorded for a seat -- "Thief", "Ranger" -- looked up by the row's name. Only a
-- vagabond (or the Knaves) has one; every other faction's `faction` field is its own name, which is
-- not a character, so it is filtered against the known list.
rttCharOf = function(fac)
  local m = rttFieldMap("faction")
  if m == nil then return nil end
  local v = m[fac]
  if v == nil then return nil end
  for _, c in ipairs(CHARS) do if c == v then return v end end
  return nil
end

-- RTT publishes each faction's exact seat position (faction id -> {x,z}) via
-- Global "RTT_SEAT_POS" as factions are placed. It stays a JSON string because
-- raw Lua tables cannot cross object-script boundaries.
local function rttSeatPosMap()
  -- The pushed record first; the Global is only RTT's mirror of it, and mirrors are wiped on load.
  local m = rttFieldMap("pos")
  if m ~= nil then return m end
  local ok, raw = pcall(function() return Global.getVar("RTT_SEAT_POS") end)
  if ok and type(raw) == "string" and raw ~= "" then
    local ok2, m = pcall(function() return JSON.decode(raw) end)
    if ok2 and type(m) == "table" then return m end
  end
  return nil
end

-- RTT also publishes each faction's real SEAT COLOUR (Global "RTT_SEAT_COLOR"), written only from its
-- draft path where the colour is the seat's own. This is authoritative and beats the hand-zone guess
-- below: Player[c].getHandTransform() returns a position for EVERY colour, seated or not, so the guess
-- happily binds rows to colours nobody occupies.
local function rttSeatColorMap()
  -- The pushed record first; the Global is only RTT's mirror of it, and mirrors are wiped on load.
  local m = rttFieldMap("color")
  if m ~= nil then return m end
  local ok, raw = pcall(function() return Global.getVar("RTT_SEAT_COLOR") end)
  if ok and type(raw) == "string" and raw ~= "" then
    local ok2, m = pcall(function() return JSON.decode(raw) end)
    if ok2 and type(m) == "table" then return m end
  end
  return nil
end

-- RTT also publishes WHO OWNS each faction (Global "RTT_SEAT_PLAYER", faction -> steam name),
-- separately from the seat colour. The two are not the same thing: on RTT's manual 4-board path
-- players keep the colour they joined with while the rows are coloured by SEAT, so matching a row's
-- colour against seated players finds nobody and the row shows no name. This is authoritative for the
-- NAME; the colour still drives the turn order.
local function rttSeatPlayerMap()
  -- The pushed record first; the Global is only RTT's mirror of it, and mirrors are wiped on load.
  local m = rttFieldMap("owner")
  if m ~= nil then return m end
  local ok, raw = pcall(function() return Global.getVar("RTT_SEAT_PLAYER") end)
  if ok and type(raw) == "string" and raw ~= "" then
    local ok2, m = pcall(function() return JSON.decode(raw) end)
    if ok2 and type(m) == "table" then return m end
  end
  return nil
end

-- These color positions are only for associating a row with TTS's turn/player
-- color. They are deliberately not an input to box-score row ordering.
local function colorSeatPositions()
  local positions, count = {}, 0
  for _, color in ipairs(PLAYER_COLORS) do
    local ok, ht = pcall(function() return Player[color].getHandTransform() end)
    local pos = ok and ht and ht.position or nil
    if pos ~= nil and pos.x ~= nil and pos.z ~= nil then
      positions[color] = pos
      count = count + 1
    end
  end
  if count == 0 then
    for _, h in ipairs(seatedHands()) do
      if h.pos ~= nil and h.pos.x ~= nil and h.pos.z ~= nil then
        positions[h.color] = h.pos
        count = count + 1
      end
    end
  end
  return positions, count
end

-- Color -> faction: the faction's supply/board game piece remains in its player
-- area after the VP marker moves to the score track. Match that physical anchor
-- to the nearest color hand zone, greedily one-to-one. Live occupancy is used
-- only to attach a Steam name; it never controls the row's color/seat.
-- RTT uses full placement ids while box-score rows use the short VP-marker ids.
-- Keep the direct row.fac lookup authoritative and bridge only those known names.
local RTT_FACTION_ID = {
  Marquise = "Marquise de Cat", Eyrie = "Eyrie Dynasties",
  Alliance = "Woodland Alliance", Riverfolk = "Riverfolk Company",
  Lizard = "The Lizard Cult", Duchy = "Underground Duchy",
  Crows = "Corvid Conspiracy", Rats = "Lord of the Hundreds",
  Badgers = "Keepers in Iron", Knaves = "Knaves of the Deepwood",
  Council = "Twilight Council", Diaspora = "Lilypad Diaspora",
}

-- (moved above refreshSeats: it is a `local`, so any use EARLIER in the file resolves to a nil
-- GLOBAL and throws 'attempt to index a nil value', killing the whole poll pass.)
local function refreshSeats(byName)
  local positions, seatCount = colorSeatPositions()
  if seatCount == 0 then return false end
  local liveNames = {}
  for _, p in ipairs(Player.getPlayers()) do
    if p.seated and p.color ~= "Black" and p.color ~= "Grey" then
      liveNames[p.color] = p.steam_name
    end
  end
  local cand, anchored = {}, {}
  for _, row in ipairs(S.rows) do
    local bag = facAnchor(row.fac, byName)
    if bag then
      anchored[row.fac] = true
      local bp = bag.getPosition()
      for ci, color in ipairs(PLAYER_COLORS) do
        local pos = positions[color]
        if pos ~= nil then
          local dx, dz = pos.x - bp.x, pos.z - bp.z
          table.insert(cand, { d = dx * dx + dz * dz, fac = row.fac,
                               color = color, ci = ci })
        end
      end
    end
  end
  table.sort(cand, function(x, y)
    if math.abs(x.d - y.d) > 0.000001 then return x.d < y.d end
    if x.fac ~= y.fac then return x.fac < y.fac end
    return x.ci < y.ci
  end)
  local usedC, usedF, assigned, changed = {}, {}, {}, false
  -- AUTHORITATIVE FIRST: any row RTT has named a seat colour for is bound directly, and both its colour
  -- and its faction are marked used so the greedy geometric pass cannot reassign either.
  local rttCol = rttSeatColorMap()
  local rttOwner = rttSeatPlayerMap()
  if rttCol ~= nil then
    for _, row in ipairs(S.rows) do
      local fid = RTT_FACTION_ID and RTT_FACTION_ID[row.fac] or nil
      local c = rttCol[row.fac] or (fid ~= nil and rttCol[fid] or nil)
      if c ~= nil and c ~= "" and not usedC[c] then
        usedC[c], usedF[row.fac] = true, true
        assigned[row.fac] = { fac = row.fac, color = c }
      end
    end
  end
  for _, c in ipairs(cand) do
    if not usedC[c.color] and not usedF[c.fac] then
      usedC[c.color], usedF[c.fac] = true, true
      assigned[c.fac] = c
    end
  end
  -- Clear a stale color only when this pass actually found the row's anchor but
  -- could not assign it. If an anchor is temporarily absent, keep the last
  -- known color instead of throwing away a valid physical-seat match.
  for _, row in ipairs(S.rows) do
    local c = assigned[row.fac]
    if c then
      -- colorAuto == false means a human set this row's colour deliberately; leave it alone, the same
      -- way nameAuto / mapAuto / deckAuto / variantAuto protect every other hand-set field. Until this
      -- existed, row.color was the ONE thing on the sheet that was rewritten every poll with no way to
      -- correct it -- and it was the thing that was wrong.
      if row.colorAuto ~= false and row.color ~= c.color then row.color = c.color; changed = true end
      local name = liveNames[c.color]
      local owned = rttOwner and (rttOwner[row.fac] or rttOwner[RTT_FACTION_ID[row.fac]])
      if owned ~= nil and owned ~= "" then name = owned end   -- RTT knows who picked it
      if name ~= nil and (row.player == "" or row.nameAuto) then
        if row.player ~= name then row.player = name; changed = true end
        row.nameAuto = true
      end
    elseif anchored[row.fac] and row.color ~= nil and row.colorAuto ~= false then
      row.color = nil
      changed = true
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
  -- ONE rule, identical at every player count: if the TTS turn system is running
  -- and the sheet has rows, the turn system drives the sheet. Otherwise the
  -- manual END TURN button does.
  --
  -- This used to additionally require >= 2 seated players AND every row's colour
  -- to be seated right now. Both made the behaviour depend on WHO happened to be
  -- sitting down: a solo game (and any hotseat game where one player runs several
  -- factions) silently fell back to manual mode, so the turn system could not be
  -- tested or used at all, and a single disconnect mid-game flipped a running
  -- table into a different mode. The maintainer asked for the same logic to work
  -- the same way regardless of player count, so those two conditions are gone.
  --
  -- Nothing downstream needs them: followTurns() looks the turn colour up with
  -- rowByColor and simply does nothing when there is no such row, and
  -- onPlayerTurn still refuses to lock unless the PREVIOUS colour was really
  -- seated -- so toggling the turn system, or TTS stepping through empty
  -- colours, still records nothing.
  return turnsRunning() and #S.rows > 0
end


-- Object-name index of each faction's supply anchor, refreshed by the poll (see ~line 1434) just
-- before seatOrder. Declared HERE, ABOVE factionSeatPosition, so the function captures this upvalue
-- rather than a nil GLOBAL -- otherwise the physical-anchor fallback threw 'index a nil value' on any
-- non-RTT / Vagabond row and aborted the whole poll pass (audit: seat-box).
local seatAnchorByName = {}
local function factionSeatPosition(row, rtt)
  local p = nil
  if rtt ~= nil then p = rtt[row.fac] or rtt[RTT_FACTION_ID[row.fac]] end
  if p ~= nil then
    local x, z = (p[1] or p.x), (p[2] or p.z)
    if x ~= nil and z ~= nil then return { x = x, z = z } end
  end
  local anchor = facAnchor(row.fac, seatAnchorByName)
  if anchor == nil then return nil end
  local ok, pos = pcall(function() return anchor.getPosition() end)
  if ok and pos ~= nil and pos.x ~= nil and pos.z ~= nil then return pos end
  return nil
end

-- (seatAnchorByName is declared above factionSeatPosition; the poll assigns it before seatOrder.)

-- Row order is always physical faction-seat order, even while RTT's TTS turn
-- system is running. The faction-keyed RTT map wins; a missing entry falls back
-- to that row's physical faction anchor. Unknown rows stay last. Original
-- indices make every pass stable, and the manual up-arrow disables this sorter.
local function seatOrder()
  if S.manualOrder then return false end
  local rtt = rttSeatPosMap()
  local before, original = {}, {}
  local positions, seatCount = {}, 0
  for i, r in ipairs(S.rows) do
    before[i], original[r] = r, i
    positions[r] = factionSeatPosition(r, rtt)
    if positions[r] ~= nil then seatCount = seatCount + 1 end
  end
  if seatCount == 0 then return false end
  resort(function(x, y)
    local px, py = positions[x], positions[y]
    if px == nil or py == nil then
      if px ~= nil then return true end
      if py ~= nil then return false end
      return original[x] < original[y]
    end
    -- clockwise from directly-right (+X): seat 1 is first, proceeding to the left
    local ax = math.atan2(-px.z, px.x); if ax < 0 then ax = ax + 2 * math.pi end
    local ay = math.atan2(-py.z, py.x); if ay < 0 then ay = ay + 2 * math.pi end
    if math.abs(ax - ay) > 0.000001 then return ax < ay end
    return original[x] < original[y]
  end)
  for i, r in ipairs(S.rows) do
    if before[i] ~= r then return true end
  end
  return false
end

-- Turns controls only the live pointer and automatic locks. It deliberately
-- does not control row order; physical seat geometry above is authoritative.
local function followTurns()
  if not fullTurnCoverage() then return false end
  local tc = Turns.turn_color
  -- The FIRST turn of the game is ALWAYS the first player. Until a turn has
  -- actually been recorded (S.turns == 0), pin the pointer to Turns.order[1]
  -- - the first player - regardless of how late that faction's row joined the
  -- sheet or whether turn_color was momentarily empty or nudged during setup.
  -- Once real turns start recording, follow the live turn_color normally, so
  -- every later round's first turn lands on the first player by itself too.
  if (S.turns or 0) == 0 then
    local first = Turns.order and Turns.order[1] or nil
    if first and first ~= "" then tc = first end
  end
  if tc and tc ~= "" then
    local i = rowByColor(tc)
    if i and i ~= S.active then S.active = i; return true end
  end
  return false
end

-- The FIRST turn of a game belongs to the FIRST SEAT. followTurns() already
-- says so, but its pin sits behind fullTurnCoverage() -> Turns.enable, and RTT
-- ships the TTS turn system off, so that path never runs there. This is the
-- manual-mode equivalent and it runs on every poll while the latch is set,
-- which also means it self-corrects as rows appear: resort() re-pins S.active
-- onto whichever row object it was on, and rows are appended in the order the
-- VP markers become readable, so without this the pointer settles on the
-- first faction DISCOVERED rather than seat 1.
-- Target: ROW 1, and deliberately NOT a colour lookup.
-- seatOrder() sorts rows clockwise from +X (angle = atan2(-z, x)), and RTT's
-- seat slots are RTT_POS = {(52,-46),(-52,-46),(52,46),(-52,46)} -> angles
-- 0.724 / 2.417 / 5.559 / 3.866, so the row order is seat 1, 2, 4, 3 and row 1
-- is ALWAYS seat 1.
-- An earlier version of this preferred rowByColor(Turns.order[1]) ("Red" =
-- RTT's seat-1 colour) and fell back to row 1. That was WRONG and shipped a
-- regression: row.color is assigned by refreshSeats() from the NEAREST HAND
-- ZONE, not from RTT's seating, and rttSeatPlayers only recolours SEATED
-- humans. With empty seats (a solo tester, or fewer humans than seats) "Red"
-- binds to an arbitrary faction -- in the maintainer's 4-faction solo test the
-- rows came out Marquise=White, Riverfolk=Red, Alliance=Orange, Duchy=Pink, so
-- the pin jumped to Riverfolk (row 2, seat 2) instead of Marquise (row 1,
-- seat 1). Geometry is authoritative here; colour is not.
local function pinFirstSeat()
  if not S.pinFirst or #S.rows == 0 then return false end
  -- MANUAL MODE ONLY. When the TTS turn system is actually driving the sheet,
  -- followTurns() owns the pointer and has its own first-player pin, and it runs
  -- immediately before this in the poll -- so without this guard we overwrote it
  -- every tick and the sheet stopped following turn order altogether (and
  -- onPlayerTurn's immediate S.active was clobbered 1.2s later too). Regression
  -- reported by the maintainer; this is the fix.
  if fullTurnCoverage() then return false end
  if S.active ~= 1 then S.active = 1; return true end
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

-- The tournament site's schema (root_boxscore/EXPORT_FIELDS.md). Every field in the developer's
-- example is emitted, so the shape is always the same: the ones this object cannot know come out as
-- null rather than being dropped, because a missing key and an unknown value are not the same thing
-- to whoever ingests this.
local FACTION_SLUG = {
  Marquise = "marquise-de-cat",   Eyrie    = "eyrie-dynasties",  Alliance = "woodland-alliance",
  Vagabond = "vagabond",          Riverfolk= "riverfolk-company", Lizard  = "lizard-cult",
  Duchy    = "underground-duchy", Crows    = "corvid-conspiracy", Rats    = "lord-of-the-hundreds",
  Badgers  = "keepers-in-iron",   Knaves   = "knaves-of-the-deepwood",
  Council  = "twilight-council",  Diaspora = "lilypad-diaspora",
}

-- JSON.encode drops a nil and writes {} for an empty table, so null and [] need placeholders that
-- are swapped back once the string exists.
local JNULL, JLIST = "@@null@@", "@@list@@"

local function slug(v)
  v = tostring(v or ""):lower()
  v = v:gsub("&", " "):gsub("%f[%w]and%f[%W]", " ")   -- "Squires and Disciples" -> squires-disciples
  v = v:gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return v
end

-- \uXXXX-escape anything outside ASCII so the payload survives being pasted through Discord, a web
-- form or a terminal. Still the same JSON: the observed export carried a raw U+2122 in a player name.
function asciiOnly(str)
  local out, i, n = {}, 1, #str
  while i <= n do
    local b = str:byte(i)
    if b < 128 then out[#out + 1] = str:sub(i, i); i = i + 1
    else
      local len, cp
      if     b >= 240 then len, cp = 4, b - 240
      elseif b >= 224 then len, cp = 3, b - 224
      elseif b >= 192 then len, cp = 2, b - 192
      else                 len, cp = 1, b end
      for k = 1, len - 1 do cp = cp * 64 + ((str:byte(i + k) or 0) % 64) end
      if cp < 0x10000 then
        out[#out + 1] = string.format("\\u%04X", cp)
      else
        cp = cp - 0x10000
        out[#out + 1] = string.format("\\u%04X\\u%04X",
          0xD800 + math.floor(cp / 0x400), 0xDC00 + (cp % 0x400))
      end
      i = i + len
    end
  end
  return table.concat(out)
end

-- A display name is a poor key: people rename themselves and it will not match a Discord handle.
-- The Steam id is stable and unique, so the site can map it to an account once. Only available while
-- that colour is actually seated, same as the name.
local function steamIdFor(color)
  if color == nil or color == "" then return nil end
  local id = nil
  pcall(function()
    for _, pl in ipairs(Player.getPlayers()) do
      if pl.seated and pl.color == color and pl.steam_id ~= nil then id = tostring(pl.steam_id) end
    end
  end)
  if id == "" then return nil end
  return id
end

function tournamentPayload()
  local p = {
    board_map          = S.meta.map  ~= "" and slug(S.meta.map)  or JNULL,
    deck               = S.meta.deck ~= "" and slug(S.meta.deck) or JNULL,
    undrafted_faction  = JNULL,
    undrafted_vagabond = JNULL,
    undrafted_captains = JLIST,
    participants       = {},
  }
  for _, fac in ipairs(ROSTER) do
    if S.unpicked[fac] == true then
      p.undrafted_faction = FACTION_SLUG[baseFac(fac)] or slug(baseFac(fac))
      local v = S.unpickedVar and S.unpickedVar[fac] or ""
      if v ~= "" and (baseFac(fac) == "Vagabond" or baseFac(fac) == "Knaves") then p.undrafted_vagabond = slug(v) end
      break
    end
  end
  -- The site reads tournament_score as the result: 1 or 0.5 is a win, 0 a loss. The object knows the
  -- winner both ways a game of Root ends -- S.winner is set when a marker reaches 30 (S.winnerReason
  -- "score") and by the DOM WIN button ("dominance"). While no winner is recorded the game is
  -- unfinished and every score stays null, rather than claiming a table of losses.
  --
  -- A coalition makes the win SHARED: a vagabond allied to the winner wins with them, so both take
  -- 0.5 rather than the winner taking 1 alone.
  local shared = false
  for _, row in ipairs(S.rows) do
    if S.winner ~= nil and row.coalition == S.winner then shared = true end
  end
  for i, row in ipairs(S.rows) do
    local won = JNULL
    if S.winner ~= nil then
      local isWinner = (row.fac == S.winner) or (row.coalition ~= nil and row.coalition == S.winner)
      won = isWinner and (shared and 0.5 or 1) or 0
    end
    local e = {
      player            = (row.player ~= nil and row.player ~= "") and row.player or JNULL,
      player_steam_id   = steamIdFor(row.color) or JNULL,
      coalition         = (row.coalition ~= nil) and (FACTION_SLUG[row.coalition] or slug(row.coalition)) or JNULL,
      -- baseFac: two vagabonds are two ROWS but ONE faction. The export must say "vagabond" for
      -- both -- the character and the player name are what distinguish them.
      faction           = FACTION_SLUG[baseFac(row.fac)] or slug(baseFac(row.fac)),
      dominance         = JNULL,
      vagabond          = JNULL,
      captains          = JLIST,              -- not tracked
      discarded_captain = JNULL,              -- not tracked
      starting_leader   = JNULL,
      brazen_demagogue  = false,
      tournament_score  = won,                -- 1 winner, 0 loser, null while the game is unfinished
      turn_order        = i,
      turns             = {},
    }
    if row.variant ~= nil and row.variant ~= "" then
      if row.fac == "Eyrie" then e.starting_leader = row.variant
      elseif baseFac(row.fac) == "Vagabond" or baseFac(row.fac) == "Knaves" then e.vagabond = slug(row.variant) end
    end
    if row.dom ~= nil then
      if row.dom.suit ~= nil then
        e.dominance = row.dom.suit:sub(1, 1):upper() .. row.dom.suit:sub(2)
      end
      e.brazen_demagogue = (row.dom.kind == "brazen_demagogue")
    end
    for r, sc in ipairs(row.locks or {}) do
      if type(sc) == "number" and sc >= 0 then
        local t = { turn = r, score = sc }
        if row.dom ~= nil and row.dom.round ~= nil and r >= row.dom.round then t.dominance = true end
        table.insert(e.turns, t)
      end
    end
    if #e.turns == 0 then e.turns = JLIST end
    table.insert(p.participants, e)
  end
  if #p.participants == 0 then p.participants = JLIST end
  return p
end

-- The one JSON this object produces.
function exportJson()
  local text = ""
  pcall(function()
    text = asciiOnly(JSON.encode(tournamentPayload()))
      :gsub('"' .. JNULL .. '"', "null")
      :gsub('"' .. JLIST .. '"', "[]")
  end)
  return text
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
        dbg("BoxScore discord error: " .. tostring(req.error) .. " code="
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
-- The same 1800-char split as fencedChunks, but for one long unbroken string, tagged ```json so
-- Discord highlights it and a bot can find it.
local function jsonChunks(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    out[#out + 1] = "```json\n" .. text:sub(i, i + 1749) .. "\n```"
    i = i + 1750
  end
  return out
end

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
  dbg("BoxScore experimental: watching " .. count .. " supply items")
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
        vp = 0, r = currentRound() })
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

-- forward declaration, so anything above lockRow's definition can call it
local lockRow

local function poll()
  pollCount = pollCount + 1
  -- Track detection does no steady-state work. The every-poll scan runs
  -- only until the first map is found; afterwards the sole periodic cost
  -- is one object lookup every 25th poll, and a full re-detection happens
  -- only when the mapped object has actually been deleted (a map swap).
  -- A stale map NAME is acceptable - the MAP chip in EDIT corrects it.
  if TRACK ~= nil and pollCount % 25 == 0
    and getObjectFromGUID(TRACK.guid) == nil then
    TRACK = nil
  end
  if TRACK == nil then
    findTrack()
    if TRACK ~= nil then dirty = true end
  end
  if TRACK == nil then return end

  local objects = getAllObjects()
  local domCards = {}
  local vpMarkers = {}
  for _, o in ipairs(objects) do
    local n = o.getName() or ""
    local fac = n:match("^(.+) VP$")
    if fac then
      vpMarkers[fac] = vpMarkers[fac] or {}
      table.insert(vpMarkers[fac], o)
      if rowByFac(fac) == nil and readCell(o) ~= nil then
        addRow(fac, o)
        refreshAssets()
        dirty = true
      end
    end
    local suit = dominanceCardSuit(o)
    if suit then table.insert(domCards, { obj = o, suit = suit }) end
  end

  -- PRUNE rows whose VP marker no longer exists. The sheet's memory must FOLLOW THE TABLE: rows were
  -- only ever added, never removed, and S is persisted whole (onSave encodes S, onLoad replaces it), so
  -- loading an old save re-imported every faction it had ever seen and a reset left the sheet still
  -- believing in markers that were gone -- which is also why VP positions came out in odd slots. The
  -- maintainer: "the only memory of which factions are present should be the vp score markers on the
  -- board". A row with no guid was added by hand in EDIT mode and is never pruned; a held or moving
  -- marker still resolves, so only a genuinely destroyed one prunes.
  -- A faction leaves the table in more ways than "its marker was destroyed". It can be dropped into a
  -- bag, or removed while a spare copy of the same marker still sits somewhere -- and findMarker
  -- re-points row.guid at that spare, so the guid keeps resolving and the row never left. Prune on
  -- whether the FACTION is still present at all: no marker by name, and no supply/board anchor.
  -- Two consecutive polls are required so a marker in hand or mid-throw never drops a row.
  local present, presentObj = {}, {}
  for _, o in ipairs(getAllObjects()) do
    local n = o.getName() or ""
    if n ~= "" then present[n] = true; if presentObj[n] == nil then presentObj[n] = o end end
  end
  for i = #S.rows, 1, -1 do
    local r = S.rows[i]
    local guidGone = r.guid ~= nil and r.guid ~= "" and getObjectFromGUID(r.guid) == nil
    local vpName   = (RTT_VP_SHORT and RTT_VP_SHORT[r.fac] or r.fac) .. " VP"
    local anchor   = facAnchor(r.fac, presentObj)   -- byName is not in scope this early; build our own
    local factionGone = (not present[vpName]) and anchor == nil
    if factionGone then r.gone = (r.gone or 0) + 1 else r.gone = 0 end
    if guidGone or (r.guid ~= nil and r.guid ~= "" and r.gone >= 2) then
      logev("leave", r.fac)
      table.remove(S.rows, i)
      if S.active > #S.rows then S.active = math.max(1, #S.rows) end
      dirty = true
    end
  end

  for _, row in ipairs(S.rows) do
    -- Count all same-faction copies. The declaration follows its specific
    -- settled card marker; held/moving markers cause no transient change.
    local markerState, domChanged = syncDominance(row, domCards,
      vpMarkers[row.fac] or {})
    if domChanged then dirty = true end
    -- Standard dominance freezes. Brazen keeps reading the separate settled
    -- marker on the VP track and locks ordinary numeric scores.
    local idx = (not dominanceFrozen(row)) and markerState.trackIdx or nil
    if idx ~= nil then
      local sc = cellToScore(idx)
      if sc ~= row.score then
        logev("score", row.fac, row.score, sc)
        row.score = sc
        dirty = true
      end
      -- Reaching 30 ends the game: the 30 is printed into the CURRENT
      -- round column and the world stops - the turn does NOT pass, the
      -- pointer does not move, nothing locks any more. Moving that marker
      -- off 30 to a lower score means it was a mistake: the cell returns
      -- to exactly what it held before and play resumes.
      if S.winner == nil and sc >= 30 then
        local r = currentRound()
        S.winnerLock = { fac = row.fac, r = r,
          prevLock = row.locks[r], prevEdit = row.edits[tostring(r)] }
        row.edits[tostring(r)] = nil
        while #row.locks < r - 1 do table.insert(row.locks, -1) end
        row.locks[r] = sc
        S.winner = row.fac
        S.winnerReason = "score"
        logev("gameover", row.fac, r, sc)
        dirty = true
      elseif S.winner == row.fac and S.winnerLock ~= nil and sc < 30 then
        local wl = S.winnerLock
        if wl ~= nil and wl.fac == row.fac then
          if wl.prevLock ~= nil then
            row.locks[wl.r] = wl.prevLock
          else
            row.locks[wl.r] = -1
            while #row.locks > 0
              and (row.locks[#row.locks] == -1 or row.locks[#row.locks] == nil) do
              table.remove(row.locks)
            end
          end
          if wl.prevEdit ~= nil then row.edits[tostring(wl.r)] = wl.prevEdit end
        end
        S.winner = nil
        S.winnerReason = nil
        S.winnerLock = nil
        logev("resume", row.fac)
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
          dbg("EXP leave: " .. w.name .. " " .. guid)
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
            dbg("EXP inflight " .. guid .. " bestFac=" .. tostring(bestFac)
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

  -- Normally the seat work is every 5th pass (~6s). A push from RTT is an EVENT, so it is taken on
  -- the very next tick instead of waiting for the cycle to come round.
  if pollCount % 5 == 1 or seatPushPending then
    seatPushPending = false
    local byName = {}
    for _, o in ipairs(getAllObjects()) do
      byName[o.getName() or ""] = o
    end
    SUPPLYPOS = {}
    for _, row in ipairs(S.rows) do
      local bag = facAnchor(row.fac, byName)
      if bag then SUPPLYPOS[row.fac] = bag.getPosition() end
    end
    seatAnchorByName = byName
    if refreshSeats(byName) then dirty = true end
    if seatOrder() then dirty = true end
    if refreshDeck() then dirty = true end
    if refreshVariants(byName) then dirty = true end
    if followTurns() then dirty = true end
    if pinFirstSeat() then dirty = true end
  end

  if dirty then
    dirty = false
    rebuildUI()
  end
end

------------------------------------------------------------------ turn flow --
function lockRow(i)
  local row = S.rows[i]
  if row == nil then return end
  S.pinFirst = false          -- a turn is being recorded: stop holding seat 1
  -- A quick turn pass can beat the poll in either direction, so count every
  -- settled copy here too before the turn number advances.
  local objects = getAllObjects()
  local domCards = {}
  local rowMarkers = {}
  for _, o in ipairs(objects) do
    local suit = dominanceCardSuit(o)
    if suit then table.insert(domCards, { obj = o, suit = suit }) end
    if (o.getName() or "") == (row.fac .. " VP") then
      table.insert(rowMarkers, o)
    end
  end
  local markerState = syncDominance(row, domCards, rowMarkers)
  -- the game is over once someone reached 30: nothing locks any more
  if S.winner ~= nil then return end
  -- re-read the marker right now: the polled score can be a beat stale, and a
  -- lock is forever (it is what gets exported)
  if not dominanceFrozen(row) then
    local idx = markerState.trackIdx
    if idx ~= nil then
      local sc = cellToScore(idx)
      if sc ~= row.score then
        logev("score", row.fac, row.score, sc)
        row.score = sc
      end
    end
  end
  -- The HIGHLIGHTED round column is the single truth for where a lock
  -- lands: the lock goes exactly there, overwriting whatever the cell
  -- holds (lock or hand edit). A wrong column is corrected by clicking
  -- the right column number in EDIT, never by the sheet second-guessing.
  -- THE WRAP, detected per row: being asked to lock a row that has already locked this round means
  -- the table has come round, so the round advances. Nothing divides by #S.rows any more, so a row
  -- joining or leaving mid-game cannot re-map anybody's columns, and a seat whose colour never gets a
  -- turn no longer drags every other row a column to the left.
  local prevRound, prevLast = currentRound(), row.lastRound
  if (row.lastRound or 0) >= currentRound() then S.round = currentRound() + 1 end
  local r = currentRound()
  row.edits[tostring(r)] = nil
  while #row.locks < r - 1 do
    table.insert(row.locks, -1)
  end
  row.locks[r] = row.score
  row.lastRound = r
  table.insert(S.undo, { fac = row.fac, r = r, prevRound = prevRound, prevLast = prevLast })
  logev("lock", row.fac, r, row.score)
  S.turns = S.turns + 1
  rebuildUI()
end

-- With full coverage the TTS turn system locks turns; otherwise END TURN.
local function lockActive()
  if S.winner ~= nil then return end
  if #S.rows == 0 or fullTurnCoverage() then return end
  if S.active > #S.rows then S.active = 1 end
  local i = S.active
  S.active = (S.active % #S.rows) + 1
  lockRow(i)
end

function uiEndTurn() lockActive() end

function onPlayerTurn(player, previous)
  dbg("BoxScore onPlayerTurn: now=" .. tostring(player and player.color)
    .. " prev=" .. tostring(previous and previous.color)
    .. " coverage=" .. tostring(fullTurnCoverage()))
  -- ONE lock source per mode: with full coverage the event locks; in every
  -- other situation the END TURN button is visible and is the only source.
  if not fullTurnCoverage() then return end
  -- A pass counts when the colour that just finished HAS A ROW -- i.e. it is one of the seats in play.
  -- This used to require previous.seated, so an unoccupied seat's turn recorded nothing: in a solo game
  -- every faction but one is on an empty seat, so ending a turn did nothing at all. Keying on "has a
  -- row" keeps the original protection (toggling the turn system bursts through colours that have no
  -- row, and those still lock nothing) while letting a seat's turn count whether or not a human sits
  -- in it. In a full game every seat is occupied, so nothing changes there.
  if previous == nil or previous.color == nil then return end
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
  if row == nil or dominanceFrozen(row) or TRACK == nil then return end
  local m = findMarker(row)
  if m == nil then dbg("BoxScore: cannot find " .. row.fac .. " VP") return end
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
    -- and the round bookkeeping this lock changed, so undoing the first lock of a round steps the
    -- round back with it instead of leaving the sheet a column ahead of itself.
    local u = S.undo[#S.undo]
    if u ~= nil and u.fac == row.fac and u.r == col then
      if u.prevRound ~= nil then S.round = u.prevRound end
      row.lastRound = u.prevLast
      table.remove(S.undo)
    end
    S.pinFirst = false        -- undo positions the pointer deliberately
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
  S.round = 1
  S.pinFirst = true
  S.winner = nil
  S.winnerReason = nil
  S.winnerLock = nil
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

-- COPY: TTS Lua has no OS-clipboard access, so the closest honest thing is
-- a selectable box holding the JSON - one Ctrl+A + Ctrl+C away. The text is
-- injected via setAttribute AFTER the rebuild because entities in XML
-- attributes never decode (a JSON quote would wreck the parse).
function uiExport(player)
  S.exportBy = player and player.steam_name or ""
  local json = exportJson()
  writeExportNotebook(json)
  -- The readable table first, then the SAME json in its own ```json fence. That answers the site's
  -- "how would an API work" directly: a Discord webhook needs no API and no callback, because the
  -- destination is baked into the URL -- the sheet POSTs out, nothing has to reach back in. A bot
  -- reading the channel gets a machine-readable record for free, beside the human one.
  local msgs = fencedChunks(boxText())
  for _, chunk in ipairs(jsonChunks(json)) do table.insert(msgs, chunk) end
  local toDiscord = postDiscord(msgs)
  S.lastExport = (toDiscord and "exported &#183; sent to Discord"
                             or ("exported &#183; JSON in TTS Notebook &#8220;" .. NOTEBOOK_TAB .. "&#8221;"))
  dbg("BoxScore: exported " .. #json .. " chars" .. (toDiscord and " (discord)" or " (notebook)"))
  rebuildUI()
end

function uiFlip()
  S.flip = not S.flip
  for _, row in ipairs(S.rows) do
    if row.dom == nil then row.score = -1 end
  end
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

local function changeSizePct(delta)
  S.sizePct = clampSizePct((S.sizePct or 100) + delta)
  rememberSizePct()
  rebuildUI()
end

function uiSizeDown() changeSizePct(-10) end
function uiSizeUp() changeSizePct(10) end

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
      S.pinFirst = false      -- deliberate row pick: do not snap it back
      S.active = i
      rebuildUI()
    end
  elseif kind == "coal" then
    local row = S.rows[i]
    if row and canCoalition(row) then
      local cands = coalitionCandidates(row)
      local at = 0
      for k, fac in ipairs(cands) do if fac == row.coalition then at = k end end
      row.coalition = cands[at + 1]          -- nil past the end: cycles back to no coalition
      logev("coalition", row.fac, row.coalition or "none")
      rebuildUI()
    end
  elseif kind == "domwin" then
    local row = S.rows[i]
    if row and row.dom then
      local won = row.dom.won == true
      for _, other in ipairs(S.rows) do
        if other.dom then other.dom.won = false end
      end
      if won then
        if S.winner == row.fac and S.winnerReason == "dominance" then
          S.winner = nil
          S.winnerReason = nil
        end
        logev("domwin-undo", row.fac, row.dom.turn, row.dom.suit)
      else
        row.dom.won = true
        S.winner = row.fac
        S.winnerReason = "dominance"
        S.winnerLock = nil
        logev("domwin", row.fac, row.dom.turn, row.dom.suit)
      end
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
    -- locks always land in the declared (highlighted) column.
    -- It used to say so by writing a FABRICATED turn count, (i-1) * #S.rows, which silently reset the
    -- within-round position to zero: every row that had already played round i was then treated as
    -- not having played it, so half the table's next lock landed in the round they had just finished.
    -- Declaring the round now says exactly that and nothing else.
    S.round = math.max(1, i)
    for _, r in ipairs(S.rows) do r.lastRound = nil end
    logev("setround", nil, S.round)
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
  -- Keep numeric locks internally so cancel can reveal the ordinary score
  -- history again, but never print a dominance-era score while dom is active.
  if dominanceFrozen(row) and r >= row.dom.round
    and (e ~= nil or r <= #row.locks) then return "-" end
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
  local round = currentRound()
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
    if row.dom ~= nil then
      table.insert(lines, "  > dominance: " .. dominanceKindLabel(row.dom)
        .. ", turn " .. tostring(row.dom.turn)
        .. ", " .. tostring(row.dom.suit)
        .. ", won: " .. ((row.dom.won == true) and "yes" or "no"))
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

local function renderMinRows()
  local n = tonumber(Global.getVar("RTT_BOXSCORE_MIN"))
  if not n then
    local dn = tonumber(Global.getVar("RTT_DN"))
    if dn then n = dn - 1 end
  end
  return math.max(1, n or 4)
end

-- One TTS Notebook tab, rewritten on every export. TTS has no clipboard API and an InputField here
-- cannot be filled from script (measured: it renders a placeholder but never text set by the
-- script, in any container, by any of attribute / inner text / setAttribute / setValue). The
-- notebook body is a native text area that never touches the XML layer, so that is where the JSON
-- goes -- and it is the SAME single payload that would go to Discord, never a second copy.
function writeExportNotebook(text)
  local done = false
  for _, t in ipairs(Notes.getNotebookTabs()) do
    if t.title == NOTEBOOK_TAB then
      Notes.editNotebookTab({ index = t.index, title = NOTEBOOK_TAB, body = text })
      done = true
    end
  end
  if not done then Notes.addNotebookTab({ title = NOTEBOOK_TAB, body = text }) end
end

function rebuildUI()
  if S.hidden then
    self.UI.setXml("")
    return
  end
  local maxLocks = 0
  for _, row in ipairs(S.rows) do maxLocks = math.max(maxLocks, #row.locks) end
  -- Width follows the card track only. Growing it with maxLocks made the
  -- sheet widen silently as the game went on.
  local showR = math.min((S.cols or 10) + 1, 41)
  local cellW = showR > 14 and 36 or 44
  local iconW, facW, domW, nameW, liveW = 30, 118, 70, 130, 48
  local btnW = 117
  local W = 54 + iconW + facW + domW + nameW + (showR - 1) * cellW + liveW + btnW
  local rowH, headH = 40, 26
  local nMin = renderMinRows()
  local H = 56 + headH + math.max(nMin, #S.rows) * (rowH + 3) + 42
  local mul = clampSizePct(S.sizePct) / 100

  -- The walnut cardboard extends FRAME px beyond the sheet on every side.
  -- That rim is bare object surface - outside the UI canvas entirely - so it
  -- is grabbable by construction, no matter how the UI treats clicks. The
  -- parchment area additionally lets clicks through via raycastTarget.
  local FRAME = 5
  local k = BASE_SCALE * LEGACY_BASE_MUL / PX_PER_UNIT
  local ww = (W + 2 * FRAME) * k
  local wh = (H + 2 * FRAME) * k
  ww, wh = ww * mul, wh * mul
  local key = string.format("%.2f|%.2f", ww, wh)
  if key ~= lastScaleKey and self.held_by_color == nil then
    lastScaleKey = key
    self.setScale({ ww, 0.18, wh })
  end
  local sx, sy
  if S.scaleMode == 1 then
    sx, sy = PX_PER_UNIT / (W + 2 * FRAME), PX_PER_UNIT / (H + 2 * FRAME)
  else
    sx, sy = BASE_SCALE * LEGACY_BASE_MUL * mul, BASE_SCALE * LEGACY_BASE_MUL * mul
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
    add('<Text fontSize="10" fontStyle="Bold" color="' .. RUST .. '" alignment="MiddleRight"'
      .. ' preferredWidth="62"' .. NOClick .. '>SIZE ' .. clampSizePct(S.sizePct) .. '%</Text>')
    chip("szdn", "uiSizeDown", BTN_DARK, 26, 13, PARCH, "&#8722;")
    chip("szup", "uiSizeUp", BTN_DARK, 26, 13, PARCH, "+")
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
  add('<Text preferredWidth="' .. domW .. '"' .. NOClick .. '> </Text>')
  add('<Text preferredWidth="' .. nameW .. '"' .. NOClick .. '> </Text>')
  local curRound = currentRound()
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
  local EMPTY_ROW = { fac="", player="", tintHex="3A2A1A", iconUrl="", variant="", score=-1, locks={}, edits={}, crafts=nil }
  for i = 1, math.max(nMin, #S.rows) do
    local row = S.rows[i] or EMPTY_ROW
    local placeholder = (S.rows[i] == nil)
    local isActive = (not placeholder) and (i == S.active) and (fullTurnCoverage() or not turnsRunning())
    if #S.rows == 0 then isActive = false end
    local bg = isActive and GOLDHI or ((i % 2 == 1) and "#00000000" or PARCH2)
    add('<HorizontalLayout preferredHeight="' .. rowH .. '" spacing="3" color="' .. bg .. '"' .. NOClick .. '>')
    if S.setup and not placeholder then
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
    if S.setup and not placeholder and variantOptions(row.fac) then
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
    if row.dom ~= nil then
      add('<VerticalLayout preferredWidth="' .. domW
        .. '" spacing="1" childForceExpandHeight="false">')
      add('<Text fontSize="9" fontStyle="Bold" color="' .. RUST
        .. '" preferredHeight="16" alignment="MiddleCenter"' .. NOClick .. '>dom '
        .. esc(row.dom.suit) .. ' T' .. tostring(row.dom.turn) .. '</Text>')
      if canCoalition(row) then
        -- a vagabond's dominance card buys a coalition, never a dominance win
        add('<Button id="coal_' .. i .. '" fontSize="10" fontStyle="Bold" preferredHeight="18" '
          .. ((row.coalition ~= nil) and BTN_GOLD or BTN_SOFT)
          .. ' text="' .. esc(row.coalition and ("+" .. row.coalition) or "coalition") .. '" onClick="uiRowBtn"/>')
      else
        add('<Button id="domwin_' .. i .. '" fontSize="10" fontStyle="Bold" preferredHeight="18" '
          .. ((row.dom.won == true) and BTN_GOLD or BTN_SOFT)
          .. ' text="dom win" onClick="uiRowBtn"/>')
      end
      add('</VerticalLayout>')
    else
      add('<Text preferredWidth="' .. domW .. '"' .. NOClick .. '> </Text>')
    end
    if S.setup and not placeholder then
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
      if S.setup and not placeholder then
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
    local liveFont = 16
    if dominanceFrozen(row) then
      live = (row.dom.won == true) and "dom win" or "-"
      liveFont = 10
    end
    add('<Text preferredWidth="10"' .. NOClick .. '> </Text>')
    add('<Panel preferredWidth="' .. liveW .. '" color="' .. GOLD .. '"' .. NOClick .. '>'
      .. '<Text fontSize="' .. liveFont .. '" fontStyle="Bold" color="' .. INKTXT .. '" alignment="MiddleCenter"' .. NOClick .. '>'
      .. live .. '</Text></Panel>')
    if placeholder or dominanceFrozen(row) then
      add('<Text preferredWidth="28"' .. NOClick .. '> </Text>')
      add('<Text preferredWidth="28"' .. NOClick .. '> </Text>')
    else
      chip("minus_" .. i, "uiRowBtn", BTN_SOFT, 28, 14, RUST, "&#8722;")
      chip("plus_" .. i, "uiRowBtn", BTN_SOFT, 28, 14, RUST, "+")
    end
    if S.setup and i > 1 and not placeholder then
      chip("up_" .. i, "uiRowBtn", BTN_SOFT, 26, 11, RUST, "&#9650;")
    else
      add('<Text preferredWidth="26"' .. NOClick .. '> </Text>')
    end
    if S.setup and not placeholder then
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
  -- The export result goes to the RIGHT of INFO, in bold. It sat on the left for one build and that
  -- shoved every button along when it appeared: this row is childForceExpandWidth="false", so a
  -- flexible element added BEFORE the buttons takes its width out of them. After INFO there is
  -- nothing but the credit to share with, so the buttons never move.
  if S.lastExport ~= "" then
    add('<Text fontSize="12" fontStyle="Bold" color="' .. RUST .. '" alignment="MiddleLeft"'
      .. ' flexibleWidth="1"' .. NOClick .. '>&#160;&#160;' .. S.lastExport .. '</Text>')
  end
  local right = "made by MrDrouf&#160;&#160;&#183;&#160;&#160;" .. BUILD
  add('<Text fontSize="12" fontStyle="Italic" color="' .. RUST .. '" alignment="MiddleRight" flexibleWidth="1"' .. NOClick .. '>'
    .. right .. '</Text>')
  add('</HorizontalLayout>')

  add('</VerticalLayout>')

  -- overlays float over the rows, so the sheet never changes size
  local PICK_DARK = 'colors="#57402A|' .. RUST .. '|' .. GOLD .. '|#00000000"'
  if S.setup and S.overlay == "picker" then
    -- character chips flow in rows of six so long names never wrap; the
    -- panel is pinned by its TOP edge, so selecting a faction only grows
    -- it downward - nothing shifts or recenters
    -- the Eyrie is excluded: its leader is chosen in play, never in the
    -- draft, so an unpicked Eyrie has no leader options to note (captains
    -- and vagabond characters ARE distinct unpicked cards)
    local extra = 0
    for _, fac in ipairs(ROSTER) do
      local opts = (S.unpicked[fac] == true and fac ~= "Eyrie")
        and variantOptions(fac) or nil
      if opts then extra = extra + math.ceil(#opts / 6) end
    end
    local baseH = 118
    local topY = math.max(8, math.floor((H - baseH) / 2))
    add('<Panel width="' .. (W - 80) .. '" height="' .. (baseH + extra * 30)
      .. '" rectAlignment="UpperCenter" offsetXY="0 -' .. topY .. '"'
      .. ' color="' .. WALNUT .. '">')
    add('<VerticalLayout padding="10 10 10 10" spacing="6" childForceExpandHeight="false">')
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
      if S.unpicked[fac] == true and fac ~= "Eyrie" and opts then
        local chosen = {}
        for w in (S.unpickedVar[fac] or ""):gmatch("[^,]+") do
          chosen[w:match("^%s*(.-)%s*$")] = true
        end
        for from = 1, #opts, 6 do
          add('<HorizontalLayout preferredHeight="24" spacing="4">')
          add('<Text fontSize="12" fontStyle="Bold" color="' .. PARCH .. '" preferredWidth="64"'
            .. ' alignment="MiddleRight"' .. NOClick .. '>'
            .. (from == 1 and (esc(fac) .. ':') or ' ') .. '</Text>')
          for ci2 = from, math.min(from + 5, #opts) do
            chip("uv_" .. fi .. "_" .. ci2, "uiRowBtn",
              chosen[opts[ci2]] and BTN_GOLD or PICK_DARK, 0, 10,
              chosen[opts[ci2]] and INKTXT or PARCH, esc(opts[ci2]))
          end
          add('</HorizontalLayout>')
        end
      end
    end
    add('</VerticalLayout></Panel>')
  elseif S.overlay == "info" then
    add('<Panel width="' .. (W - 110) .. '" height="430" color="' .. WALNUT .. '">')
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
    section("SCORES", 30,
      "Read automatically from VP markers. A settled marker on a fox, mouse, rabbit or bird Dominance card records turn and suit and offers dom win. With no same-faction marker on the score track this is standard dominance and freezes at -; with a second marker still on the track it is Brazen Demagogue and keeps scoring. Removing the card marker cancels either kind. A track marker reaching 30 ends the game.")
    section("TURNS", 44,
      "Everything runs automatically once the TTS turn order is set and every faction has its seated player: each turn pass records the finishing faction by itself. Without that, END TURN records the highlighted faction. A lock always writes the highlighted round column, overwriting whatever it holds.")
    section("EDIT", 44,
      "Correct anything: scores (click a cell), the round (click a column number), whose turn it is (click a portrait), faction order (&#9650;), player names, the Eyrie commander / Knaves captains / vagabond character (&#9660;), map, deck, game name and the unpicked faction.")
    section("EXPORT", 44,
      "Writes the game as JSON to the TTS Notebook, tab &#8220;" .. NOTEBOOK_TAB .. "&#8221; &#8211; open the Notebook at the top of the screen, click that tab, Ctrl+A, Ctrl+C. Set a webhook under EDIT &#8594; DISCORD and the same record is posted there too; the footer then reads sent to Discord. One record either way, never two.")
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
      add('<VerticalLayout padding="10 10 10 10" spacing="6" childForceExpandHeight="false">')
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
    -- pinned by the top edge like the picker: opening the round or add row
    -- grows the panel downward without shifting what is already there
    local baseH = 64 + #S.rows * 32
    local hh = baseH + ((S.craftAdd or S.craftPick) and 30 or 0)
    local topY = math.max(8, math.floor((H - baseH) / 2))
    add('<Panel width="' .. (W - 120) .. '" height="' .. hh
      .. '" rectAlignment="UpperCenter" offsetXY="0 -' .. topY .. '"'
      .. ' color="' .. WALNUT .. '">')
    add('<VerticalLayout padding="10 10 8 8" spacing="4" childForceExpandHeight="false">')
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

-- Throw away everything known about seats and start again: the record RTT pushed, and every row's
-- hand-set colour. The next poll re-reads RTT's record, or falls back to hand-zone geometry on a table
-- with no RTT. This is the escape hatch for a sheet that has somehow ended up with the wrong rows --
-- there is no per-row colour picker, because adding one costs 26px of sheet width and the slab size
-- is pinned by the RTT bake.
function uiReseat()
  S.rttSeats = nil
  for _, row in ipairs(S.rows) do row.colorAuto = nil; row.color = nil end
  logev("reseat")
  broadcastToAll("Box score: seats will be re-detected.", {0.9, 0.8, 0.5})
  rebuildUI()
end

function onLoad(saved)
  local loadedState = false
  if saved ~= nil and saved ~= "" then
    local ok, d = pcall(function() return JSON.decode(saved) end)
    if ok and d ~= nil and d.rows ~= nil then S = d; loadedState = true end
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
  -- A game saved before the round became explicit carries only S.turns and the locks. Recover the
  -- round from the locks themselves -- the highest column anybody actually filled -- rather than from
  -- the old division, which is the thing that was wrong. Each row's lastRound is seeded the same way,
  -- so a resumed game keeps locking exactly where it left off.
  if S.round == nil then
    local maxr = 0
    for _, row in ipairs(S.rows or {}) do
      local last = 0
      for r = 1, #(row.locks or {}) do
        if row.locks[r] ~= nil and row.locks[r] ~= -1 then last = r end
      end
      row.lastRound = (last > 0) and last or nil
      if last > maxr then maxr = last end
    end
    S.round = math.max(1, maxr)
  end
  S.active = S.active or 1
  if S.active > math.max(1, #S.rows) then S.active = 1 end
  local domWinner = nil
  for _, row in ipairs(S.rows) do
    row.locks = row.locks or {}
    row.edits = row.edits or {}
    row.crafts = row.crafts or nil
    row.score = row.score or -1
    row.player = row.player or ""
    if row.dom ~= nil then
      row.dom.turn = math.max(1, math.floor(tonumber(row.dom.turn) or 1))
      row.dom.round = math.max(1, math.floor(tonumber(row.dom.round) or 1))
      row.dom.suit = tostring(row.dom.suit or ""):lower()
      row.dom.score = tonumber(row.dom.score) or row.score
      row.dom.won = row.dom.won == true
      local brazen = row.dom.kind == "brazen_demagogue" or row.dom.frozen == false
      row.dom.kind = brazen and "brazen_demagogue" or "standard"
      row.dom.frozen = not brazen
      if row.dom.markerGuid == "" then row.dom.markerGuid = nil end
      if row.dom.won then domWinner = row.fac end
    end
  end
  if domWinner ~= nil then
    S.winner = domWinner
    S.winnerReason = "dominance"
    S.winnerLock = nil
  elseif S.winner ~= nil and S.winnerReason == nil then
    S.winnerReason = "score"
  end
  S.cols = S.cols or 10
  S.scaleMode = S.scaleMode or 1
  if S.sizePct == nil then
    local oldIdx = math.floor(tonumber(S.sizeIdx) or 2)
    local oldMul = LEGACY_SIZE_MULS[oldIdx] or LEGACY_BASE_MUL
    S.sizePct = math.floor(oldMul / LEGACY_BASE_MUL * 10 + 0.5) * 10
  end
  -- A brand-new RTT spawn has no LuaScriptState, so recover the percentage
  -- remembered by the prior copy.  A real saved state always wins.
  if not loadedState then
    local ok, remembered = pcall(function()
      return Global.getVar("RTT_BOXSCORE_SIZE_PCT")
    end)
    if ok and tonumber(remembered) ~= nil then S.sizePct = tonumber(remembered) end
  end
  S.sizePct = clampSizePct(S.sizePct)
  S.sizeIdx = nil
  rememberSizePct()
  S.setup = S.setup or false
  S.overlay = nil
  S.lastExport = S.lastExport or ""

  self.addContextMenuItem("setup / done", uiSetup, false)
  self.addContextMenuItem("reset box score", uiReset, false)
  self.addContextMenuItem("hide / show", uiHide, false)
  self.addContextMenuItem("export", uiExport, false)
  self.addContextMenuItem("flip track", uiFlip, false)
  self.addContextMenuItem("spin panel", uiSpin, false)
  self.addContextMenuItem("size +10%", uiSizeUp, false)
  self.addContextMenuItem("size -10%", uiSizeDown, false)
  self.addContextMenuItem("panel scale mode", uiScaleMode, false)
  self.addContextMenuItem("diagnose", uiDiag, false)
  self.addContextMenuItem("re-detect seats", uiReseat, false)

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
