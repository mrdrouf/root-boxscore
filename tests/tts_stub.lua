-- Minimal TTS stand-in: enough of the API for the box score's turn logic to run for real.
local H = { objects = {}, seated = {}, log = {} }
_G.__H = H

local function obj(name, guid, pos)
  local o = { _name = name, _guid = guid, _pos = pos or {x=0,y=0,z=0}, _tags = {}, _lock = false, _rot={x=0,y=0,z=0} }
  function o.getName() return o._name end
  function o.getGUID() return o._guid end
  function o.getPosition() return o._pos end
  function o.getRotation() return o._rot end
  function o.getDescription() return "" end
  function o.getTags() return o._tags end
  function o.setTags(t) o._tags = t end
  function o.addTag(t) table.insert(o._tags, t) end
  function o.removeTag(t) end
  function o.hasTag(t) for _,x in ipairs(o._tags) do if x==t then return true end end return false end
  function o.getLock() return o._lock end
  function o.setLock(v) o._lock = v end
  function o.setPositionSmooth() end
  function o.setRotationSmooth() end
  function o.getSnapPoints() return o._snaps or {} end
  function o.positionToLocal(p) return { x = p.x - o._pos.x, y = 0, z = p.z - o._pos.z } end
  function o.getData() return { CardID = o._cardid } end
  function o.getObjects() return {} end
  function o.getCustomObject() return {} end
  o.name = name
  H.objects[#H.objects+1] = o
  return o
end
H.obj = obj

_G.getAllObjects = function() return H.objects end
_G.getObjects    = function() return H.objects end
_G.getObjectFromGUID = function(g) for _,o in ipairs(H.objects) do if o._guid==g then return o end end return nil end
_G.getObjectsWithTag = function(t)
  local r={} for _,o in ipairs(H.objects) do if o.hasTag and o.hasTag(t) then r[#r+1]=o end end return r end
_G.spawnObjectJSON = function(p) if p.callback_function then p.callback_function(obj("spawned","xxxxxx",p.position)) end end
_G.broadcastToAll = function(...) end
_G.broadcastToColor = function(...) end
_G.printToAll = function(...) end
_G.log = function(...) end

_G.Wait = { time = function(f, s) H.pending = H.pending or {}; table.insert(H.pending, f) end,
            frames = function(f, n) H.pending = H.pending or {}; table.insert(H.pending, f) end,
            stop = function() end }
function H.flush(n)
  for _=1,(n or 12) do
    local q = H.pending or {}; H.pending = {}
    for _,f in ipairs(q) do pcall(f) end
  end
end

_G.Turns = { enable=false, order={}, turn_color="", type=1, reverse_order=false, skip_empty_hands=false }
_G.Player = setmetatable({}, { __index = function(t,k)
  if k == "getPlayers" then return function() return H.seated end end
  local HP = { Red={x=-50,y=0,z=-50}, Yellow={x=50,y=0,z=-50}, Orange={x=-50,y=0,z=50},
               Teal={x=50,y=0,z=50}, Green={x=0,y=0,z=-70}, Brown={x=0,y=0,z=70},
               Blue={x=-70,y=0,z=0}, Purple={x=70,y=0,z=0}, Pink={x=-70,y=0,z=40}, White={x=70,y=0,z=-40} }
  return { color=k, seated=true, steam_name="P_"..tostring(k),
           getHandTransform=function() return { position=HP[k] or {x=999,y=0,z=999}, rotation={x=0,y=0,z=0}, scale={x=1,y=1,z=1} } end,
           setHandTransform=function() end, changeColor=function() end }
end })
_G.Global = { getVar=function(k) return H.globals and H.globals[k] end,
              setVar=function(k,v) H.globals = H.globals or {}; H.globals[k]=v end,
              call=function() end }
-- A real encoder, because the export tests read the JSON back in Python. Arrays vs objects the way
-- TTS decides it: a table with a [1] and no other keys is an array.
local function _isarr(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end
local function _enc(v)
  local ty = type(v)
  if ty == "nil" then return "null" end
  if ty == "boolean" then return tostring(v) end
  if ty == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return tostring(v)
  end
  if ty == "string" then
    return '"' .. v:gsub('[\\"]', '\\%0'):gsub("\n", "\\n") .. '"'
  end
  if ty == "table" then
    local out = {}
    if _isarr(v) then
      for _, x in ipairs(v) do out[#out+1] = _enc(x) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out+1] = _enc(k) .. ":" .. _enc(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end
_G.JSON = { encode=_enc, decode=function(s) return nil end }
_G.WebRequest = { post=function() end, get=function() end }
-- A working notebook, so the export/copy paths can be read back
local _tabs = {}
_G.Notes = {
  getNotebookTabs = function() return _tabs end,
  setNotebookTabs = function(t) _tabs = t or {} end,
  addNotebookTab  = function(t)
    _tabs[#_tabs+1] = { index = #_tabs, title = t.title, body = t.body }
    return #_tabs - 1
  end,
  editNotebookTab = function(t)
    for _, e in ipairs(_tabs) do
      if e.index == t.index then
        if t.title then e.title = t.title end
        if t.body  then e.body  = t.body  end
        return true
      end
    end
    return false
  end,
}
_G.UI = { setAttribute=function() end, getAttribute=function() return "" end, setXml=function() end }
_G.self = obj("Root Box Score","bs0001",{x=0,y=0,z=0})
_G.self.UI = { setAttribute=function() end, setXml=function() end, getAttribute=function() return "" end }
_G.self.getGMNotes = function() return "" end
_G.self.setName = function() end
_G.self.getScale = function() return {x=1,y=1,z=1} end
_G.self.setScale = function() end
_G.self.getBounds = function() return { center={x=0,y=0,z=0}, size={x=10,y=1,z=10} } end
_G.self.positionToWorld = function(p) return p end
_G.self.addContextMenuItem = function() end
_G.self.clearContextMenu = function() end
_G.self.createButton = function() end
_G.self.clearButtons = function() end
_G.self.getButtons = function() return {} end
_G.self.editButton = function() end
_G.self.removeButton = function() end
_G.self.getName = function() return "Root Box Score" end
_G.self.getDescription = function() return "" end
_G.self.setDescription = function() end
_G.self.getPosition = function() return {x=0,y=0,z=0} end
_G.self.getRotation = function() return {x=0,y=0,z=270} end
_G.self.setGMNotes = function() end
_G.self.getColorTint = function() return {r=0,g=0,b=0} end
_G.self.setColorTint = function() end
_G.self.getSnapPoints = function() return {} end
_G.self.getCustomObject = function() return {} end
_G.self.getTags = function() return {} end
_G.self.hasTag = function() return false end
_G.Time = { time = 0 }
_G.os = os
_G.self.setCustomAssets = function() end
_G.self.getCustomAssets = function() return {} end
_G.self.UI.setCustomAssets = function() end
_G.self.UI.getCustomAssets = function() return {} end
-- TTS runs Lua 5.2 where math.atan2 exists; this runtime is 5.5 where it was removed.
if math.atan2 == nil then math.atan2 = function(y, x) return math.atan(y, x) end end
