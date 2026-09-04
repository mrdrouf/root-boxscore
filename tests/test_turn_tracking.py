"""Execute the box score against a stubbed TTS API and assert turn tracking works.

The maintainer plays solo and cannot test turn passing in game, so this runs the real
boxscore.lua under a Lua interpreter with enough of the TTS API faked to drive it:
a score track (3 row-bands x 31 evenly spaced snaps), VP markers parked on printed 0,
faction supply anchors beside each colour's hand zone, then turn passes.

    pip3 install lupa && python3 tests/test_turn_tracking.py

Regression guarded: before 2026-09-04, fullTurnCoverage() additionally required >= 2
seated players and every row's colour seated, so a SOLO game silently fell back to
manual mode -- the turn system recorded nothing and there was no end score. Passing
--old runs the pre-fix source from git for comparison.
"""
import os, subprocess, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

PROBE = '''
function __probe()
  local n = 0; for _ in pairs(S.rows) do n = n + 1 end
  return { turns = S.turns, rows = n,
           coverage = fullTurnCoverage() and 1 or 0,
           winner = tostring(S.winner) }
end
function __row(i)
  local r = S.rows[i]; if r == nil then return nil end
  local n = 0; for _ in pairs(r.locks or {}) do n = n + 1 end
  return { fac = r.fac, locks = n }
end
function __poll() poll() end
'''

# Four factions, four seated players -- but one faction's supply sits nearest an UNSEATED
# colour's hand zone, so that row binds to a colour nobody occupies. This is the multiplayer
# failure the maintainer reported: colorSeatPositions() hands back a position for EVERY colour,
# seated or not, and the pre-fix gate then refused coverage for the WHOLE table because one row's
# colour was not seated. (His save showed exactly this: rows bound to White and Pink.)
SETUP4 = '''
local map = __H.obj("Marsh Map","map001",{x=0,y=0,z=0})
local sp = {}
for _, z in ipairs({-0.05, 0.0, 0.05}) do
  for i = 0, 30 do sp[#sp+1] = { position = { x = i*0.03, y = 0, z = z } } end
end
map._snaps = sp
for _, fac in ipairs({"Marquise","Eyrie","Alliance","Duchy"}) do
  local o = __H.obj(fac.." VP","vp_"..fac,{x=0.90,y=0,z=0.0})
  o.held_by_color = nil
  o.isSmoothMoving = function() return false end
end
__H.obj("Marquise Supply","sup_M",{x=-50,y=0,z=-50})   -- Red   (seated)
__H.obj("Eyrie Supply",   "sup_E",{x= 50,y=0,z=-50})   -- Yellow(seated)
__H.obj("Alliance Supply","sup_A",{x=-50,y=0,z= 50})   -- Orange(seated)
__H.obj("Duchy Supply",   "sup_D",{x=-70,y=0,z= 40})   -- Pink  (NOT seated)
__H.seated = { {color="Red",seated=true,steam_name="A"}, {color="Yellow",seated=true,steam_name="B"},
               {color="Orange",seated=true,steam_name="C"}, {color="Teal",seated=true,steam_name="D"} }
'''

SETUP = '''
local map = __H.obj("Marsh Map","map001",{x=0,y=0,z=0})
local sp = {}
for _, z in ipairs({-0.05, 0.0, 0.05}) do
  for i = 0, 30 do sp[#sp+1] = { position = { x = i*0.03, y = 0, z = z } } end
end
map._snaps = sp
for _, fac in ipairs({"Marquise","Eyrie"}) do
  -- printed 0 sits at the track's MAXIMUM local coordinate
  local o = __H.obj(fac.." VP","vp_"..fac,{x=0.90,y=0,z=0.0})
  o.held_by_color = nil
  o.isSmoothMoving = function() return false end
end
__H.obj("Marquise Supply","sup_M",{x=-50,y=0,z=-50})   -- beside Red
__H.obj("Eyrie Supply","sup_E",{x=50,y=0,z=-50})       -- beside Yellow
'''


def run(lua_src, players, setup=None):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(lua_src + PROBE)
    L, H = rt.globals(), rt.globals().__H
    seats = '{color="Red",seated=true,steam_name="A"}'
    if players == 2:
        seats += ', {color="Yellow",seated=true,steam_name="B"}'
    if setup is not None:
        rt.execute(setup)
    else:
        rt.execute(SETUP + '\n__H.seated = { %s }\n' % seats)
    L.onLoad("")
    H.flush(20)
    for _ in range(6):
        L.__poll(); H.flush(3)
    rt.execute('Turns.enable = true; Turns.order = {"Red","Yellow"}; Turns.turn_color = "Red"')
    for _ in range(4):
        L.__poll(); H.flush(3)
    for a, b in (("Yellow", "Red"), ("Red", "Yellow"), ("Yellow", "Red")):
        L.onPlayerTurn(rt.table(color=a, seated=True), rt.table(color=b, seated=True))
        H.flush(3); L.__poll(); H.flush(3)
    st = dict(L.__probe())
    st["locks"] = sum(dict(L.__row(i))["locks"] for i in (1, 2) if L.__row(i))
    return st


def main():
    if "--old" in sys.argv:
        src = subprocess.run(["git", "-C", REPO, "show", "0da0200:boxscore.lua"],
                             capture_output=True, text=True).stdout
        label = "PRE-FIX (0da0200)"
    else:
        src = open(os.path.join(REPO, "boxscore.lua"), encoding="utf-8").read()
        label = "current boxscore.lua"

    failed = False
    for players in (2, 1):
        st = run(src, players)
        ok = st["coverage"] == 1 and st["turns"] == 3 and st["locks"] == 3
        print("%-22s players=%d  coverage=%d turns=%d locks=%d  %s"
              % (label, players, st["coverage"], st["turns"], st["locks"],
                 "OK" if ok else "FAIL"))
        if not ok and "--old" not in sys.argv:
            failed = True

    # 4 players, one faction bound to an unseated colour
    st = run(src, 4, setup=SETUP4)
    ok = st["coverage"] == 1 and st["turns"] == 3
    print("%-22s players=4 (one row on an unseated colour)  coverage=%d turns=%d  %s"
          % (label, st["coverage"], st["turns"], "OK" if ok else "FAIL"))
    if not ok and "--old" not in sys.argv:
        failed = True
    if failed:
        raise SystemExit("turn tracking regressed: three passes must record three locks "
                         "at BOTH player counts")
    print("turn tracking OK" if "--old" not in sys.argv else "(pre-fix run, failures expected solo)")


if __name__ == "__main__":
    main()
