"""Execute the box score against a stubbed TTS API and assert turn tracking works.

The maintainer plays solo and cannot test turn passing with other people, so this runs the
real boxscore.lua under a Lua interpreter with enough of the TTS API faked to drive it:
a score track (3 row-bands x 31 evenly spaced snaps), VP markers parked on printed 0,
faction supply anchors beside each colour's hand zone, then real turn passes.

    pip3 install lupa && python3 tests/test_turn_tracking.py
    python3 tests/test_turn_tracking.py --old      # pre-fix source, for comparison

Regressions guarded (all three were live bugs, reported from the table):
  * solo fell back to manual mode -- fullTurnCoverage() demanded >= 2 seated players;
  * a single row bound to an UNSEATED colour disabled turn tracking for the whole table,
    because the gate demanded every row's colour be currently seated;
  * an unoccupied seat's turn recorded nothing, so solo a full round locked only one score.
"""
import os, subprocess, sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
FACTIONS = ("Marquise", "Eyrie", "Alliance", "Duchy")
SEATCOLOR = {"Marquise": "Red", "Eyrie": "Yellow", "Alliance": "Orange", "Duchy": "Teal"}
HANDPOS = {"Red": (-50, -50), "Yellow": (50, -50), "Orange": (-50, 50), "Teal": (50, 50)}

PROBE = '''
function __probe()
  local n = 0; for _ in pairs(S.rows) do n = n + 1 end
  return { turns = S.turns, rows = n, coverage = fullTurnCoverage() and 1 or 0 }
end
function __row(i)
  local r = S.rows[i]; if r == nil then return nil end
  local n = 0; for _ in pairs(r.locks or {}) do n = n + 1 end
  return { fac = r.fac, color = tostring(r.color), locks = n }
end
function __poll() poll() end
'''


def build_setup(factions, seated_colors):
    lines = ['local map = __H.obj("Marsh Map","map001",{x=0,y=0,z=0})',
             'local sp = {}',
             'for _, z in ipairs({-0.05, 0.0, 0.05}) do',
             '  for i = 0, 30 do sp[#sp+1] = { position = { x = i*0.03, y = 0, z = z } } end',
             'end',
             'map._snaps = sp']
    for f in factions:
        # printed 0 sits at the track's MAXIMUM local coordinate
        lines.append('local o = __H.obj("%s VP","vp_%s",{x=0.90,y=0,z=0.0})' % (f, f))
        lines.append('o.held_by_color = nil; o.isSmoothMoving = function() return false end')
        x, z = HANDPOS[SEATCOLOR[f]]
        lines.append('__H.obj("%s Supply","sup_%s",{x=%d,y=0,z=%d})' % (f, f, x, z))
    seats = ", ".join('{color="%s",seated=true,steam_name="P%d"}' % (c, i)
                      for i, c in enumerate(seated_colors))
    lines.append('__H.seated = { %s }' % seats)
    return "\n".join(lines)


def run(lua_src, factions, seated_colors, order, passes):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(lua_src + PROBE)
    L, H = rt.globals(), rt.globals().__H
    rt.execute(build_setup(factions, seated_colors))
    L.onLoad("")
    H.flush(20)
    for _ in range(6):
        L.__poll(); H.flush(3)
    rt.execute('Turns.type = 2; Turns.skip_empty_hands = false; Turns.order = {%s}; '
               'Turns.turn_color = "%s"; Turns.enable = true'
               % (", ".join('"%s"' % c for c in order), order[0]))
    for _ in range(4):
        L.__poll(); H.flush(3)
    for nxt, prev in passes:
        L.onPlayerTurn(rt.table(color=nxt, seated=nxt in seated_colors),
                       rt.table(color=prev, seated=prev in seated_colors))
        H.flush(3); L.__poll(); H.flush(3)
    st = dict(L.__probe())
    st["locks"] = sum(dict(L.__row(i))["locks"]
                      for i in range(1, len(factions) + 1) if L.__row(i))
    return st


def cycle(order, n):
    """n turn passes around `order`, as (next, previous) pairs."""
    return [(order[(i + 1) % len(order)], order[i % len(order)]) for i in range(n)]


def t_vagabond_anchor_survives_plain_objects(src):
    """A Vagabond row must not crash on objects that have no custom object.

    facAnchor scans every object for the Vagabond's board art, and markerImage returns nil for
    anything without a custom object (a die, a bag, a scripting zone) -- and for a custom object
    carrying none of image/face/diffuse. `nil ~= ""` is TRUE, so the scan fell through to
    img:find(...) and errored the moment a Vagabond row was created. Reported from the Ultimate
    mod: "error message printed when the first faction was selected".
    """
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute("""
      local _obj = __H.obj
      __H.obj = function(n,g,p)
        local o = _obj(n,g,p)
        o.getColorTint = function() return {r=.5,g=.4,b=.3} end
        o.getBoundsNormalized = function() return {size={x=1,y=.2,z=1.4}, center={x=0,y=0,z=0}} end
        o.getVar = function() return nil end
        o.call = function() return nil end
        o.isSmoothMoving = function() return false end
        return o
      end
      ERRS = {}
      local rp = pcall
      pcall = function(f, ...) local ok, e = rp(f, ...) if not ok then ERRS[#ERRS+1] = tostring(e) end return ok, e end
    """)
    rt.execute(src + PROBE)
    rt.execute("""
      local m = __H.obj("Marsh Map","map1",{x=0,y=0,z=0})
      local sp = {}
      for _, z in ipairs({-0.05, 0, 0.05}) do
        for i = 0, 30 do sp[#sp+1] = { position = { x = i*0.03, y = 0, z = z } } end
      end
      m._snaps = sp
      local v = __H.obj("Vagabond VP","vp1",{x=0.9,y=0,z=0})
      v.held_by_color = nil
      v.isSmoothMoving = function() return false end
      local plain = __H.obj("Battle Die","die1",{x=10,y=0,z=10})
      plain.getCustomObject = function() return nil end     -- a plain object: no custom object
      __H.seated = { {color="Red", seated=true, steam_name="P0"} }
    """)
    rt.globals().onLoad("")
    rt.globals().__H.flush(20)
    for _ in range(6):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    errs = [str(x) for x in (rt.eval("ERRS") or {}).values()]
    bad = [e for e in errs if "attempt to index a nil value" in e]
    assert not bad, "Vagabond anchor scan crashed: %s" % bad[0][:150]


DIRECT = [("vagabond anchor vs plain objects", t_vagabond_anchor_survives_plain_objects)]


CASES = [
    ("2 players",                      FACTIONS[:2], ["Red", "Yellow"],
     ["Red", "Yellow"], 2, 2),
    ("solo, 2 factions",               FACTIONS[:2], ["Red"],
     ["Red", "Yellow"], 2, 2),
    ("solo, full 4-seat round",        FACTIONS,     ["Red"],
     ["Red", "Yellow", "Orange", "Teal"], 4, 4),
    ("4 players, 4 factions",          FACTIONS,     ["Red", "Yellow", "Orange", "Teal"],
     ["Red", "Yellow", "Orange", "Teal"], 4, 4),
    # The screenshot bug: four boards and a live TTS turn order, but one seat has
    # emptied out, so one row is bound to a colour nobody occupies. Pre-fix,
    # fullTurnCoverage() demanded every row's colour be seated, so that single
    # stale row silently killed tracking for the whole table.
    ("4 players, one seat emptied",     FACTIONS,     ["Red", "Yellow", "Orange"],
     ["Red", "Yellow", "Orange", "Teal"], 4, 4),
]


def main():
    old = "--old" in sys.argv
    if old:
        src = subprocess.run(["git", "-C", REPO, "show", "0da0200:boxscore.lua"],
                             capture_output=True, text=True).stdout
        label = "PRE-FIX"
    else:
        src = open(os.path.join(REPO, "boxscore.lua"), encoding="utf-8").read()
        label = "current"

    failed = []
    for name, facs, seated, order, npass, want in CASES:
        st = run(src, facs, seated, order, cycle(order, npass))
        ok = st["coverage"] == 1 and st["turns"] == npass and st["locks"] == want
        print("  %-8s %-26s coverage=%d turns=%d locks=%d  %s"
              % (label, name, st["coverage"], st["turns"], st["locks"], "OK" if ok else "FAIL"))
        if not ok:
            failed.append(name)
    for name, fn in DIRECT:
        try:
            fn(src)
            print("  %-8s %-26s OK" % (label, name))
        except AssertionError as e:
            failed.append(name)
            print("  %-8s %-26s FAIL  %s" % (label, name, e))
        except Exception as e:                      # a hard Lua error IS the failure
            failed.append(name)
            print("  %-8s %-26s FAIL  %s" % (label, name, str(e).split(chr(10))[0][:110]))

    if failed and not old:
        raise SystemExit("turn tracking regressed: " + ", ".join(failed))
    print("all turn-tracking cases OK" if not old
          else "(pre-fix run: failures above are the bugs this suite guards)")


if __name__ == "__main__":
    main()
