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
function __round() return S.round end
function __locks(i)
  local r = S.rows[i]; if r == nil then return "" end
  local out = {}
  for k = 1, 12 do out[#out+1] = tostring(r.locks[k] == nil and "." or r.locks[k]) end
  return table.concat(out, ",")
end
function __colorof(fac)
  for _, r in ipairs(S.rows) do if r.fac == fac then return tostring(r.color) end end
  return "?"
end
function __locksby(c)
  for i, r in ipairs(S.rows) do if tostring(r.color) == c then return __locks(i) end end
  return "?"
end
function __save() return onSave() end
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


def _export_fixture(src, extra=""):
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(src + """
function __fixture()
  S.meta.map = "Autumn"; S.meta.deck = "Squires and Disciples"
  S.unpicked = { Badgers = true }
  S.rows = {
    { fac = "Alliance", player = "mrdrouf", variant = "", locks = {3, 8, 14}, edits = {}, score = 14 },
    { fac = "Rats", player = "mrmirz", variant = "", edits = {}, score = 8,
      locks = {1, 4, 8}, dom = { suit = "bird", round = 2, kind = "brazen_demagogue" } },
    { fac = "Vagabond", player = "bw", variant = "Tinker", locks = {1, 4}, edits = {}, score = 4 },
    { fac = "Eyrie", player = "bob", variant = "Commander", locks = {3, 8, 14, 19}, edits = {}, score = 19 },
  }
""" + extra + """
  return exportJson()
end
""")
    return rt


def t_export_emits_the_full_schema(src):
    """EXPORT produces the site's schema with EVERY field present.

    The maintainer asked for all the fields from the developer's example, so the shape is constant:
    what this object cannot know comes out as null, not as a missing key -- absent and unknown are
    different things to whoever ingests it. Only Lua-side placeholders make that possible, since
    JSON.encode drops a nil and writes {} for an empty table.
    """
    import json as _json
    p = _json.loads(_export_fixture(src).globals().__fixture())

    assert p["board_map"] == "autumn" and p["deck"] == "squires-disciples"
    assert p["undrafted_faction"] == "keepers-in-iron"
    assert p["undrafted_vagabond"] is None, "unknown must be null, not missing"
    assert p["undrafted_captains"] == [], "an empty list must be [], not {}"

    got = {e["faction"]: e for e in p["participants"]}
    assert set(got) == {"woodland-alliance", "lord-of-the-hundreds", "vagabond", "eyrie-dynasties"}

    FIELDS = {"player", "player_steam_id", "coalition", "faction", "dominance", "vagabond",
              "captains", "discarded_captain", "starting_leader", "brazen_demagogue",
              "tournament_score", "turn_order", "turns"}
    for fac, e in got.items():
        assert set(e) == FIELDS, "%s has %s" % (fac, sorted(set(e) ^ FIELDS))
        assert e["captains"] == [], "captains must be [] for %s" % fac
        # nobody is seated in the fixture, so the id must be null rather than absent or ""
        assert e["player_steam_id"] is None, "%s: %r" % (fac, e["player_steam_id"])

    a = got["woodland-alliance"]
    assert a["player"] == "mrdrouf" and a["turn_order"] == 1
    assert a["turns"] == [{"turn": 1, "score": 3}, {"turn": 2, "score": 8}, {"turn": 3, "score": 14}]
    assert a["starting_leader"] is None and a["vagabond"] is None

    r = got["lord-of-the-hundreds"]
    assert r["dominance"] == "Bird" and r["brazen_demagogue"] is True
    assert r["turns"][0] == {"turn": 1, "score": 1}, "turn 1 predates the dominance"
    assert r["turns"][1].get("dominance") is True

    assert got["vagabond"]["vagabond"] == "tinker"
    assert got["vagabond"]["starting_leader"] is None, "only the Eyrie has a leader"
    assert got["eyrie-dynasties"]["starting_leader"] == "Commander"


def t_export_is_one_record_to_one_tab(src):
    """One JSON, one notebook tab. EXPORT used to write its own record to a second tab."""
    # this case is about the notebook, not the sheet; the UI rebuild wants a fuller row shape
    rt = _export_fixture(src, "  rebuildUI = function() end  uiExport(nil)")
    rt.execute("__fixture()")
    tabs = rt.eval("Notes.getNotebookTabs()")
    titles = [tabs[i].title for i in range(1, len(tabs) + 1)]
    assert titles == ["BoxScore"], "expected exactly one tab, got %s" % titles
    import json as _json
    body = _json.loads(tabs[1].body)
    assert body["board_map"] == "autumn", "the tab holds the internal record, not the site schema"
    assert "participants" in body


def t_no_copy_button_or_overlay(src):
    """COPY is gone: one export path, one button.

    An InputField here cannot be filled from script -- measured over five rounds, in every container,
    by attribute, inner text, setAttribute and setValue -- so the panel it opened was a dead box.
    """
    assert 'onClick="uiCopy"' not in src, "the COPY button is back"
    assert "function uiCopy" not in src, "uiCopy is back"
    assert 'S.overlay == "copy"' not in src, "the copy overlay is back"
    for dead in ("copyFieldText", "fillCopyField", "wrapJson", "escInner", "copyFieldXmlEscape"):
        assert dead not in src, "%s survived the cleanup" % dead


def t_tournament_score_marks_the_winner(src):
    """1 for the winner, 0 for the rest, null while the game is unfinished.

    The site reads this as the result: 1 or 0.5 is a win, 0 a loss. The object already knows the
    winner both ways Root ends -- a marker reaching 30, or the DOM WIN button -- so it fills it
    rather than leaving the site to infer it. An unfinished game must NOT report losses.
    """
    import json as _json

    p = _json.loads(_export_fixture(src).globals().__fixture())          # no winner recorded yet
    assert all(e["tournament_score"] is None for e in p["participants"]), \
        "an unfinished game claimed a result"

    p = _json.loads(_export_fixture(src, '  S.winner = "Alliance"').globals().__fixture())
    got = {e["faction"]: e["tournament_score"] for e in p["participants"]}
    assert got["woodland-alliance"] == 1, got
    assert all(v == 0 for f, v in got.items() if f != "woodland-alliance"), got

    # a dominance win is recorded the same way, just with a different reason
    p = _json.loads(_export_fixture(
        src, '  S.winner = "Rats"  S.winnerReason = "dominance"').globals().__fixture())
    got = {e["faction"]: e["tournament_score"] for e in p["participants"]}
    assert got["lord-of-the-hundreds"] == 1 and got["woodland-alliance"] == 0, got


def t_coalition_shares_the_win(src):
    """A vagabond allied to the winner wins with them: 0.5 each, not 1 and 0.

    Root, Vagabond, 4+ players: a vagabond cannot rule, so its dominance card buys a coalition
    instead. Its marker leaves the track and it wins if the ally wins. The ally must not have
    activated a dominance card, which is why the candidate list excludes them.
    """
    import json as _json
    fixture = '  S.rows[3].coalition = "Alliance"  S.winner = "Alliance"'
    p = _json.loads(_export_fixture(src, fixture).globals().__fixture())
    got = {e["faction"]: e for e in p["participants"]}
    assert got["vagabond"]["coalition"] == "woodland-alliance", got["vagabond"]["coalition"]
    assert got["vagabond"]["tournament_score"] == 0.5, "the ally must share the win"
    assert got["woodland-alliance"]["tournament_score"] == 0.5, "a shared win is 0.5 each, not 1"
    assert got["lord-of-the-hundreds"]["tournament_score"] == 0
    assert got["eyrie-dynasties"]["tournament_score"] == 0

    # allied to someone who did NOT win: the vagabond loses with them
    p = _json.loads(_export_fixture(
        src, '  S.rows[3].coalition = "Rats"  S.winner = "Alliance"').globals().__fixture())
    got = {e["faction"]: e for e in p["participants"]}
    assert got["woodland-alliance"]["tournament_score"] == 1, "an unshared win is still 1"
    assert got["vagabond"]["tournament_score"] == 0


def t_coalition_candidates_follow_the_rule(src):
    """Only a non-vagabond who has not activated dominance can be allied with."""
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(src + """
function __cands()
  S.rows = {
    { fac="Alliance", locks={}, edits={} },
    { fac="Rats",     locks={}, edits={}, dom={ suit="bird", round=2, kind="standard" } },
    { fac="Vagabond", locks={}, edits={}, dom={ suit="fox",  round=3, kind="standard" } },
    { fac="Eyrie",    locks={}, edits={} },
  }
  local out = {}
  for _, f in ipairs(coalitionCandidates(S.rows[3])) do out[#out+1] = f end
  return table.concat(out, ",")
end
""")
    got = rt.globals().__cands()
    assert got == "Alliance,Eyrie", \
        "the Rats activated dominance and must be excluded; got %r" % got


def t_steam_id_is_read_from_the_seat(src):
    """A seated player's Steam id lands on their row; an unseated colour gives null.

    The name is what the site cannot resolve -- people rename, and it will not match a Discord
    handle -- so the stable id travels alongside it rather than replacing it.
    """
    import json as _json
    rt = _export_fixture(src, """
  S.rows[1].color = "Red"
  S.rows[2].color = "Yellow"
  __H.seated = { {color="Red", seated=true, steam_name="MrDrouf", steam_id="76561198000000001"} }
""")
    p = _json.loads(rt.globals().__fixture())
    got = {e["faction"]: e for e in p["participants"]}
    assert got["woodland-alliance"]["player_steam_id"] == "76561198000000001", \
        got["woodland-alliance"]["player_steam_id"]
    assert got["lord-of-the-hundreds"]["player_steam_id"] is None, "an unseated colour must be null"


def t_export_is_pure_ascii(src):
    """The payload must be ASCII: a real export carried a raw TM in a player name."""
    rt = _export_fixture(src, '  S.rows[1].player = "KRT\\u{2122}McArthur"')
    got = rt.globals().__fixture()
    assert all(ord(c) < 128 for c in got), "non-ASCII survived"
    import json as _json
    assert _json.loads(got)["participants"][0]["player"] == "KRT\u2122McArthur"


def t_turns_enabled_after_the_sheet_is_already_up(src):
    """RTT now leaves turns OFF at setup and switches them on when the first player sits.

    The sheet therefore meets a table with Turns.enable false, falls back to manual mode, and must
    pick the turn system up when it appears -- without losing rows, colours or scores. Before this
    change the mod enabled turns during setup, so the sheet never saw that transition.
    """
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(src + PROBE)
    L, H = rt.globals(), rt.globals().__H
    order = ["Red", "Yellow", "Orange", "Teal"]
    rt.execute(build_setup(FACTIONS, order))
    # turns configured but NOT enabled -- exactly what 4-Player Setup now leaves behind
    rt.execute('Turns.type = 2; Turns.skip_empty_hands = false; '
               'Turns.order = {"Red","Yellow","Orange","Teal"}; Turns.enable = false')
    L.onLoad("")
    H.flush(20)
    for _ in range(6):
        L.__poll(); H.flush(3)
    before = dict(L.__probe())
    assert before["rows"] == 4, "rows were lost while turns were off: %s" % before
    assert before["coverage"] == 0, "coverage claimed with the turn system off"

    # first player sits: RTT switches turns on with the order already in place
    rt.execute('Turns.turn_color = "Red"; Turns.enable = true')
    for _ in range(4):
        L.__poll(); H.flush(3)
    mid = dict(L.__probe())
    assert mid["rows"] == 4, "rows lost when turns came on: %s" % mid
    assert mid["coverage"] == 1, "the sheet did not pick the turn system up: %s" % mid

    # and a full round now locks one score per faction
    for nxt, prev in cycle(order, 4):
        L.onPlayerTurn(rt.table(color=nxt, seated=True), rt.table(color=prev, seated=True))
        H.flush(3); L.__poll(); H.flush(3)
    locks = sum(dict(L.__row(i))["locks"] for i in range(1, 5) if L.__row(i))
    assert dict(L.__probe())["turns"] == 4, "turn passes were not counted"
    assert locks == 4, "a full round locked %d scores, expected 4" % locks


def _table(src, factions, seated_colors, order):
    """A live sheet with the turn system running, ready to be poked at."""
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt.execute(src + PROBE)
    rt.execute(build_setup(factions, seated_colors))
    rt.globals().onLoad("")
    rt.globals().__H.flush(20)
    for _ in range(6):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    rt.execute('Turns.type = 2; Turns.skip_empty_hands = false; Turns.order = {%s}; '
               'Turns.turn_color = "%s"; Turns.enable = true'
               % (", ".join('"%s"' % c for c in order), order[0]))
    for _ in range(4):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    return rt


def _pass(rt, nxt, prev, seated):
    rt.globals().onPlayerTurn(rt.table(color=nxt, seated=nxt in seated),
                              rt.table(color=prev, seated=prev in seated))
    rt.globals().__H.flush(3); rt.globals().__poll(); rt.globals().__H.flush(3)


def _lua_str(x):
    return "[==[" + x + "]==]"


def _setscore(rt, fac, score):
    """Move a faction's VP marker to `score`.

    Every score in this fixture used to be 0, which made a lock landing in the WRONG column
    invisible: overwriting a 0 with a 0 looks like nothing happened. Distinct scores per round are
    what let these tests see a misplaced lock at all.
    Printed 0 sits at the track's maximum local x, and the 31 snaps are 0.03 apart.
    """
    rt.execute('local o = getObjectFromGUID("vp_%s") o._pos = {x=%.4f, y=0, z=0.0}'
               % (fac, (30 - score) * 0.03))
    rt.globals().__poll(); rt.globals().__H.flush(3)


def t_a_row_appearing_midgame_does_not_remap_columns(src):
    """The round must not be a division by the CURRENT row count.

    It was `floor(S.turns / #S.rows) + 1`, which makes the live row count a divisor of the whole
    history: a faction joining the table mid-game retroactively re-maps every future lock. After two
    rounds of three (6 turns) a fourth row appears, and the old formula gives floor(6/4)+1 = 2 -- so
    round three's locks landed back in round TWO's column, overwriting it. That is the tester's
    "it skipped or omitted a number".
    """
    facs, seated = list(FACTIONS[:3]), ["Red", "Yellow", "Orange"]
    order = ["Red", "Yellow", "Orange"]
    rt = _table(src, facs, seated, order)
    for nxt, prev in cycle(order, 6):                     # two clean rounds of three
        _pass(rt, nxt, prev, seated)
    for i in (1, 2, 3):
        cols = rt.eval("__locks(%d)" % i).split(",")
        assert cols[0] != "." and cols[1] != ".", "row %d did not fill rounds 1-2: %s" % (i, cols[:3])

    # a fourth faction lands on the table and gets a row
    rt.execute('local o = __H.obj("Duchy VP","vp_Duchy",{x=0.90,y=0,z=0.0}) '
               'o.held_by_color = nil o.isSmoothMoving = function() return false end '
               '__H.obj("Duchy Supply","sup_Duchy",{x=50,y=0,z=50})')
    for _ in range(6):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    assert dict(rt.eval("__probe()"))["rows"] == 4, "the fourth row never appeared"

    before = [rt.eval("__locks(%d)" % i) for i in (1, 2, 3)]
    for nxt, prev in cycle(order, 3):                     # round three, for the original three
        _pass(rt, nxt, prev, seated)
    after = [rt.eval("__locks(%d)" % i) for i in (1, 2, 3)]
    for i, (b, a) in enumerate(zip(before, after)):
        assert b.split(",")[:2] == a.split(",")[:2], (
            "row %d: the fourth row joining rewrote rounds 1-2, %s -> %s"
            % (i + 1, b.split(",")[:3], a.split(",")[:3]))
        assert a.split(",")[2] != ".", (
            "row %d never locked round 3 -- its turn landed back in an earlier column: %s"
            % (i + 1, a.split(",")[:4]))


def t_declaring_the_round_does_not_shift_half_the_table(src):
    """EDIT's round-number button declares the round, and that is ALL it does.

    The sheet's stated contract is that the highlighted column is the single truth for where a lock
    lands, so declaring round i means the next go-round fills column i -- deliberately overwriting it.
    What must NOT happen is the declaration leaving the table in two states at once, with some rows
    a round ahead of others.

    It used to say "we are in round i" by writing a FABRICATED turn count, (i-1) * #S.rows. That
    made the declaration depend on the live row count and silently reset the within-round position,
    and it corrupted S.turns, which the first-player latch and the export both read. The round is now
    a stored field and the turn count is left alone.
    """
    facs, seated = list(FACTIONS), ["Red", "Yellow", "Orange", "Teal"]
    order = ["Red", "Yellow", "Orange", "Teal"]
    rt = _table(src, facs, seated, order)
    _setscore(rt, "Marquise", 1)
    for nxt, prev in cycle(order, 4):                     # round 1
        _pass(rt, nxt, prev, seated)
    turns_before = dict(rt.eval("__probe()"))["turns"]
    rt.execute('uiRowBtn(nil, nil, "colh_2")')            # declare round 2

    _setscore(rt, "Marquise", 5)
    for nxt, prev in cycle(order, 4):                     # the whole table plays round 2
        _pass(rt, nxt, prev, seated)
    red = rt.eval('__locksby("Red")').split(",")
    assert red[0] == "1", "declaring the round corrupted round 1: %s" % red[:4]
    assert red[1] == "5", "round 2 did not land in column 2: %s" % red[:4]
    assert red[2] == ".", "a row ran a round ahead of the declaration: %s" % red[:4]

    _setscore(rt, "Marquise", 9)
    for nxt, prev in cycle(order, 4):                     # and the next cycle advances by exactly one
        _pass(rt, nxt, prev, seated)
    red = rt.eval('__locksby("Red")').split(",")
    assert red[:4] == ["1", "5", "9", "."], "the round did not advance by exactly one: %s" % red[:4]
    # every row is in the same round: no half-table split
    for c in ("Red", "Yellow", "Orange", "Teal"):
        cols = rt.eval('__locksby("%s")' % c).split(",")
        filled = len([x for x in cols[:6] if x != "."])
        assert filled == 3, "%s has %d rounds recorded, the rest have 3: %s" % (c, filled, cols[:5])
    assert dict(rt.eval("__probe()"))["turns"] > turns_before, \
        "declaring a round rewound the turn count, which the first-player latch and the export read"


def t_the_pushed_seat_record_wins_and_survives_a_reload(src):
    """RTT pushes the seat record; the sheet keeps it, and keeps it through a reload.

    It used to re-read three TTS Globals every six seconds. Globals are WIPED on load, so a resumed
    game silently fell back to guessing each row's colour from the nearest hand zone -- rows re-tinted
    to colours nobody occupies, and turns attributed to the wrong row.
    """
    facs, seated = list(FACTIONS), ["Red", "Yellow", "Orange", "Teal"]
    want = [("Purple", "Marquise de Cat"), ("Blue", "Eyrie Dynasties"),
            ("White", "Woodland Alliance"), ("Pink", "Underground Duchy")]
    rt = _table(src, facs, seated, ["Red", "Yellow", "Orange", "Teal"])
    rec = '{"run":7,"seats":[' + ",".join(
        '{"pos":[0,0],"color":"%s","faction":"%s","owner":"H%d"}' % (c, f, i)
        for i, (c, f) in enumerate(want)) + ']}'
    rt.execute("rttSeatPush(%s)" % _lua_str(rec))
    for _ in range(3):
        rt.globals().__poll(); rt.globals().__H.flush(3)
    for fac, w in zip(("Marquise", "Eyrie", "Alliance", "Duchy"), [c for c, _ in want]):
        got = rt.eval('__colorof("%s")' % fac)
        assert got == w, "%s bound to %s, RTT said %s" % (fac, got, w)

    saved = rt.eval("__save()")
    assert saved and saved != "", "onSave produced nothing"
    rt2 = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt2.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt2.execute(src + PROBE)
    rt2.execute(build_setup(facs, seated))               # a fresh table: the Globals are gone
    rt2.globals().onLoad(saved)
    rt2.globals().__H.flush(20)
    for _ in range(8):
        rt2.globals().__poll(); rt2.globals().__H.flush(3)
    for fac, w in (("Marquise", "Purple"), ("Duchy", "Pink")):
        got = rt2.eval('__colorof("%s")' % fac)
        assert got == w, "after reload %s came back as %s, not %s" % (fac, got, w)


def t_old_save_migrates_to_the_explicit_round(src):
    """A game saved before the round became explicit must resume where its locks say it is.

    This one guards the MIGRATION, not an old bug: the previous code happened to get a resumed game
    right whenever the row count had not changed, and this keeps that true now that the round is a
    stored field rather than a division. Strip the field, reload, and the next turn must still land
    in round 3.
    """
    facs, seated = list(FACTIONS[:3]), ["Red", "Yellow", "Orange"]
    order = ["Red", "Yellow", "Orange"]
    rt = _table(src, facs, seated, order)
    for nxt, prev in cycle(order, 6):
        _pass(rt, nxt, prev, seated)
    saved = rt.eval("__save()")
    saved_old = saved.replace('"round":2,', "").replace(',"round":2', "")
    assert '"round"' not in saved_old, "the fixture did not actually strip the round"

    rt2 = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt2.execute(open(os.path.join(HERE, "tts_stub.lua"), encoding="utf-8").read())
    rt2.execute(src + PROBE)
    rt2.execute(build_setup(facs, seated))
    rt2.globals().onLoad(saved_old)
    rt2.globals().__H.flush(20)
    for _ in range(6):
        rt2.globals().__poll(); rt2.globals().__H.flush(3)
    rt2.execute('Turns.type = 2; Turns.skip_empty_hands = false; '
                'Turns.order = {"Red","Yellow","Orange"}; Turns.turn_color = "Red"; Turns.enable = true')
    for _ in range(4):
        rt2.globals().__poll(); rt2.globals().__H.flush(3)
    _pass(rt2, "Yellow", "Red", seated)                   # the resumed game's next turn
    cols = rt2.eval('__locksby("Red")').split(",")
    assert cols[0] != "." and cols[1] != ".", "the resumed game lost its first two rounds: %s" % cols[:4]
    assert cols[2] != ".", (
        "a resumed game locked into a finished column instead of round 3: %s" % cols[:4])


DIRECT += [("turns switched on after setup",  t_turns_enabled_after_the_sheet_is_already_up),
           ("export emits the full schema",   t_export_emits_the_full_schema),
           ("one record, one notebook tab",    t_export_is_one_record_to_one_tab),
           ("no COPY button or overlay",       t_no_copy_button_or_overlay),
           ("tournament score marks winner",   t_tournament_score_marks_the_winner),
           ("coalition shares the win",        t_coalition_shares_the_win),
           ("coalition candidates by rule",    t_coalition_candidates_follow_the_rule),
           ("steam id read from the seat",     t_steam_id_is_read_from_the_seat),
           ("export payload is pure ascii",    t_export_is_pure_ascii),
           ("row joining does not remap",      t_a_row_appearing_midgame_does_not_remap_columns),
           ("declaring a round shifts nobody", t_declaring_the_round_does_not_shift_half_the_table),
           ("pushed record wins and persists", t_the_pushed_seat_record_wins_and_survives_a_reload),
           ("old save migrates its round",     t_old_save_migrates_to_the_explicit_round)]


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
