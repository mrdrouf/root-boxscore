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


def t_removing_a_faction_drops_its_row(src):
    """Taking a faction off the table must drop its box-score row.

    The prune used to key only on the cached marker guid. A faction can leave by other routes -- put in
    a bag, or removed while a spare same-named marker still sits somewhere, which findMarker then
    re-points row.guid at, so the guid kept resolving and the row never left.
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
      function REMOVE(guid)
        for i,o in ipairs(__H.objects) do
          if o._guid == guid then table.remove(__H.objects, i) return true end
        end
        return false
      end
    """)
    rt.execute(src + PROBE)
    rt.execute(build_setup(["Marquise", "Eyrie"], ["Red", "Yellow"]))
    rt.globals().onLoad("")
    rt.globals().__H.flush(20)
    for _ in range(4):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    assert dict(rt.eval("__probe()"))["rows"] == 2, "fixture: expected two rows"

    rt.execute('REMOVE("vp_Marquise") REMOVE("sup_Marquise")')
    for _ in range(8):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    left = dict(rt.eval("__probe()"))["rows"]
    assert left == 1, "removed faction still has a row (%d rows left)" % left

    # ...and a table nobody touched must keep both rows
    rt2 = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt2.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt2.execute(src + PROBE)
    rt2.execute(build_setup(["Marquise", "Eyrie"], ["Red", "Yellow"]))
    rt2.globals().onLoad("")
    rt2.globals().__H.flush(20)
    for _ in range(8):
        rt2.globals().__poll(); rt2.globals().__H.flush(3)
    assert dict(rt2.eval("__probe()"))["rows"] == 2, "pruned a row that was still on the table"


DIRECT = [("vagabond anchor vs plain objects", t_vagabond_anchor_survives_plain_objects),
          ("removing a faction drops its row", t_removing_a_faction_drops_its_row)]


def t_copy_emits_the_tournament_schema(src):
    """COPY must produce the tournament site's JSON, and produce it at all.

    Two separate bugs. The box came up EMPTY: the JSON was baked into an XML attribute, and a whole
    internal record is long enough that one stray character or the sheer length makes TTS drop the
    panel without a word. And the payload was the mod's own record, not the schema the site ingests
    (root_boxscore/EXPORT_SCHEMA.md). The field is now emitted empty and filled by fillCopyField,
    with the compact tournament payload.
    """
    import json as _json
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    # S is a local of boxscore.lua, so the fixture is compiled INTO the same chunk to reach it
    rt.execute(src + """
function __export_fixture()
  S.meta.map = "Autumn"; S.meta.deck = "Squires and Disciples"
  S.unpicked = { Badgers = true }
  S.rows = {
    { fac = "Alliance", player = "mrdrouf", variant = "", locks = {3, 8, 14} },
    { fac = "Rats", player = "mrmirz", variant = "",
      locks = {1, 4, 8}, dom = { suit = "bird", round = 2, kind = "brazen_demagogue" } },
    { fac = "Vagabond", player = "bw", variant = "Tinker", locks = {1, 4} },
    { fac = "Eyrie", player = "bob", variant = "Commander", locks = {3, 8, 14, 19} },
  }
  return JSON.encode(tournamentPayload())
end
""")
    p = _json.loads(rt.globals().__export_fixture())

    assert p["board_map"] == "autumn", p.get("board_map")
    assert p["deck"] == "squires-disciples", p.get("deck")
    assert p["undrafted_faction"] == "keepers-in-iron", p.get("undrafted_faction")

    got = {e["faction"]: e for e in p["participants"]}
    assert set(got) == {"woodland-alliance", "lord-of-the-hundreds", "vagabond",
                        "eyrie-dynasties"}, sorted(got)

    a = got["woodland-alliance"]
    assert a["player"] == "mrdrouf" and a["turn_order"] == 1
    assert a["turns"] == [{"turn": 1, "score": 3}, {"turn": 2, "score": 8},
                          {"turn": 3, "score": 14}], a["turns"]

    r = got["lord-of-the-hundreds"]
    assert r["dominance"] == "Bird", r.get("dominance")
    assert r["brazen_demagogue"] is True
    assert r["turns"][0] == {"turn": 1, "score": 1}, "turn 1 predates the dominance"
    assert r["turns"][1].get("dominance") is True, "turn 2 onward carries the dominance flag"

    assert got["vagabond"]["vagabond"] == "tinker", got["vagabond"].get("vagabond")
    assert got["eyrie-dynasties"]["starting_leader"] == "Commander"
    assert "starting_leader" not in got["vagabond"], "only the Eyrie has a leader"

    for e in p["participants"]:          # unsourced fields are omitted, never guessed
        for absent in ("coalition", "captains", "discarded_captain", "tournament_score"):
            assert absent not in e, "%s was invented for %s" % (absent, e["faction"])


def t_copy_field_uses_every_mechanism(src):
    """The box has come up empty three ways, so it no longer relies on any one of them.

    Inline-only, one async setAttribute, and setAttribute on timers have each been tried and each
    left it blank. All of them now run, writing the same string, plus setValue.
    """
    assert "fillCopyField()" in src, "the copy overlay no longer fills the field"
    i = src.index("id='cpyfld'")
    decl = src[i:src.index("/>", i)]
    assert "copyFieldXmlEscape(copyFieldText())" in decl, "the JSON is no longer inline: %s" % decl[:140]
    assert 'setAttribute("cpyfld", "text", text)' in src, "nothing pushes via setAttribute"
    assert 'setValue("cpyfld", text)' in src, "nothing pushes via setValue"


def t_copy_also_reaches_the_notebook(src):
    """Whatever the InputField does, the JSON must be reachable by a route known to work.

    uiExport has always written its record to a notebook tab and that has never been reported broken,
    so COPY writes the tournament payload the same way. The box coming up empty then costs the
    maintainer nothing.
    """
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(src + """
function __notebook_fixture()
  S.meta.map = "Autumn"
  S.rows = { { fac = "Marquise", player = "p", variant = "", locks = {2, 5} } }
  fillCopyField()
  for _, t in ipairs(Notes.getNotebookTabs()) do
    if t.title == "BoxScore JSON" then return t.body end
  end
  return ""
end
""")
    body = rt.globals().__notebook_fixture()
    assert body and body != "", "COPY wrote nothing to the notebook"
    import json as _json
    p = _json.loads(body)
    assert p["board_map"] == "autumn"
    assert p["participants"][0]["faction"] == "marquise-de-cat"


def t_copy_field_escapes_every_xml_breaker(src):
    """Every character that can break TTS's XmlUI is escaped, as a NUMERIC entity.

    The double quote is the one that was missing: legal XML inside a single-quoted attribute, which
    is why it was left alone, but every value in a JSON string is wrapped in one.
    """
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(src)
    got = rt.globals().copyFieldXmlEscape("""{"a":"x&y<z>1'2"}""")
    assert "&#34;" in got and "&#38;" in got and "&#60;" in got and "&#62;" in got and "&#39;" in got, got
    for raw in ('"', "&", "<", ">", "'"):
        assert raw not in got.replace("&#34;", "").replace("&#38;", "").replace(
            "&#60;", "").replace("&#62;", "").replace("&#39;", ""), "%r survived: %s" % (raw, got)


DIRECT += [("copy emits the tournament schema", t_copy_emits_the_tournament_schema),
           ("copy field uses every mechanism",  t_copy_field_uses_every_mechanism),
           ("copy field escapes xml breakers",  t_copy_field_escapes_every_xml_breaker),
           ("copy also reaches the notebook",   t_copy_also_reaches_the_notebook)]


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
