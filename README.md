# Root Box Score

Automatic in-game box score for **Root – Ultimate Collection** in Tabletop
Simulator: a walnut cardboard sheet that watches the real score markers on the
real board and records a per-turn box score, following the TTS turn system.

## Install

Download the two files in [`out/`](out/) (`Root Box Score.json` and
`Root Box Score.png`) into your Saved Objects folder:

    Documents\My Games\Tabletop Simulator\Saves\Saved Objects

then spawn it in-game from **Objects → Saved Objects → Root Box Score**. To
export to Discord, paste a webhook URL once into **EDIT → DISCORD** (see
below); it is saved with the object.

## Mechanics — exactly how it works

### Where is each victory-point token? (no vision, no guessing)

1. **Identifying the markers.** In this mod every faction's VP token is a
   named object: `Marquise VP`, `Eyrie VP`, `Vagabond VP`, … The tool scans
   all objects for names matching `"<Faction> VP"`. That is the entire
   identification step — names, not positions or images, so it works for any
   faction including fan factions. GUIDs are only cached; if a marker is
   replaced, it is re-found by name.

2. **Finding the score track.** Every map token in the mod carries snap
   points (the invisible anchors pieces snap to). The printed 0–30 score
   track exists in those snap points as a long row of ~31 evenly spaced
   columns × 3 parallel sub-rows. The tool takes the object with the most
   snap points (≥40 — faction boards have ≤25, so only the map qualifies),
   groups its snaps into straight bands, and keeps bands that contain ≥25
   points at even spacing. Parallel bands with the same spacing and start are
   merged as the track's sub-rows. This is pure geometry on the mod's own
   data — all 28 maps work, and a future map works too as long as its track
   has snaps.

3. **Reading a score.** Everything happens in the map's *local* coordinate
   system (`map.positionToLocal(marker.getPosition())`), so the map can sit
   anywhere on the table at any rotation. A marker is "on the track" when it
   lies within tolerance of one of the sub-rows; its score is the nearest
   track column. Markers that are held, gliding, or off the track read as
   "no reading" and keep their last known score.

4. **Which end is 0?** Fixed by convention, never inferred: on every map in
   this mod the printed 0 sits at the track's *maximum* local coordinate
   (bottom-left of the board as displayed, per the table's rule), so scores
   descend along the local axis. Established three ways: markers parked on
   the printed 0 cell read at local max; the world view shows 0 bottom-left
   under the token's standard rotation; and the map artwork of every cached
   map places 0 on the corresponding image edge. Right-click → *flip track*
   exists only for exotic future maps.

### How factions and players get their rows

5. **A faction joins the sheet** the first time its VP marker is seen
   standing on the score track. So: set the markers on 0 during setup and
   all playing factions appear immediately; unpicked factions' markers are
   never on the track, so they never appear. Each row's icon is the marker's
   own artwork (`getCustomObject().image`), which every client has already
   loaded because the marker is on the table.

6. **Which player plays which faction?** By board position, as at a real
   table: each faction's *anchor* sits with the faction board in front of a
   seat. The anchor is the faction's supply bag (`"<Faction> Supply"`, a mod
   convention) — with the mod's naming quirks handled: the Rats' bag is the
   "Hundreds Supply", the Crows' the "Corvid Supply", the Badgers' the
   "Keeper Supply" — and the Vagabond, who has no supply at all, is anchored
   by his named character figurine ("Vagabond - Thief", …). The tool
   measures the distance from every seated player's hand zone to every
   playing faction's anchor and pairs them nearest-first, one-to-one. That pairing gives
   each row its player color and Steam name (typed names always win over
   auto-filled ones).

7. **Turn order.** The TTS turn system is the *single authority*. While it
   runs, row order mirrors `Turns.order`, and the ► row follows
   `Turns.turn_color`. Before it starts, rows order themselves clockwise
   around the table by seat position (Root's convention); ▲ in setup
   overrides.

### Turns, locking, corrections

8. **Locking.** While the TTS turn system runs *and* every faction row has
   its seated player, the turn system is the single lock source: each turn
   pass re-reads the finishing faction's marker at that instant (never a
   stale value) and writes the score into the first visibly-empty round
   column. A manual END TURN button appears only when that coverage is
   missing (solo, hotseat, observers) — never both at once, no double
   emploi.
9. **Declaring the round.** In EDIT, clicking a round-column number declares
   "we are in round N", and that declaration is authoritative: every
   faction's next lock lands exactly in column N, overwriting whatever the
   cell holds (a wrong turn count must never derail the sheet). From the
   following round on, the normal first-empty-column rule resumes. Any cell
   can also be edited directly in EDIT; hand edits are stored separately
   and win over the locked value in display and export.
10. **+ / −** move the faction's *actual marker* along the track (fast
    glide, small hop), so the board itself stays the single source of truth;
    clicks accumulate. Placement keeps every marker visible: an empty cell
    takes the marker dead centre; an occupied cell pushes the newcomer one
    step up, then down, then two up — never on top of another marker.

### The sheet itself

11. **One piece of cardboard.** TTS renders object UI at 100 px per world
    unit (measured, not the documented 250). The script sizes its own slab to the sheet's pixel dimensions plus
    a walnut frame on every rebuild. The frame is bare cardboard *outside*
    the UI canvas, so it is grabbable by construction on all four sides, no
    matter how the UI treats clicks; the parchment area additionally lets
    clicks through (`raycastTarget=false` on everything non-interactive), so
    in practice you can drag from anywhere that is not a button or field.
12. **Fixed footprint.** Ten round columns are always shown, so the sheet
    keeps one size for a whole normal game; it only grows automatically
    when a game runs past round 10.
13. **EDIT face** — the same sheet with everything editable in place, with a
    real cursor (fields are true input fields, centered like the printed
    text so nothing shifts when EDIT opens): player names, every score cell,
    the round (click a column number), whose turn it is (click a portrait),
    faction order (▲, manual order is final truth), the game name, the map
    (six chips: Summer, Winter, Lake, Mountain, Marsh, Gorge), the deck
    (Base Deck / Exiles and Partisans / Squires and Disciples), a per-row
    **character** picker (▼) for the Eyrie commander, Knaves captains or
    vagabond character (auto-filled when a known character card stands near
    the faction's supply; picked values always win), the Discord webhook,
    the CRAFT toggle with its ITEMS editor (see the craft chapter below),
    and the unpicked faction: a picker over the full 13-faction roster, one
    click per faction, gold = unpicked. Unpicked cannot be auto-detected —
    in the group's draft, five cards are drawn and one is thrown away,
    usually leaving no trace on the table — so it is always a human choice.
14. **Silent.** Nothing is written to chat in play. Right-click → *diagnose*
    is the only thing that broadcasts (what map/track/markers it sees).

### Export

15. **Discord, straight from the object — no companion program.** Paste a
    Discord webhook URL into EDIT → *DISCORD* (or drop it in
    `tools/discord_webhook.txt` — gitignored, it is a posting credential —
    before running `build.py`, which bakes it into your locally installed
    copy; the published `out/` artifact never contains it). EXPORT then
    posts the formatted box score directly to the channel via `WebRequest`;
    the URL is part of the object's saved state, so it travels inside every
    save file — share table saves only with people who may post to your
    channel.
16. **Notebook mirror.** Every EXPORT also writes the full JSON record
    (metadata, rows, players, variants, locks, edits, crafts, unpicked,
    event log) to the Notebook tab `BoxScore` — machine-readable fuel for
    any external analysis.

## Development

- `boxscore.lua` — the whole object script; state persists via onSave/onLoad.
- `build.py` — builds `out/Root Box Score.json` + thumbnail and installs both
  into the TTS Saved Objects folder.
- `tools/tts_exec.py script.lua` — run Lua inside a *running* TTS instance
  (External Editor API, port 39999). Data out: `WebRequest.post` to the
  bundled HTTP server (body arrives URL-encoded) or `log()` → editor port
  39998 (messageID 2). Never `print()` (chat spam).
- Attached-UI geometry: the canvas lies in the object's top-face plane;
  position x/y move within the plane, position z floats it above (negative =
  up); rotation `0 0 0` is flat, `270 0 0` stands it up; 100 px per unit.
  InputFields ignore `alignment` but honour `textAlignment`.

## Experimental: craft detection

EDIT has a **CRAFT** toggle. While on, the sheet memorizes every item tile
sitting in the map's craftable-item supply (the edge opposite the score
track; the tiles are unnamed in this mod, so they are identified by their
artwork). An item leaving the supply goes "in flight"; it is attributed the
moment it settles beside a faction's board (nearest faction anchor within
30 units — the supply bag, or the Vagabond's character figurine) — the
destination is final, later movement is never revisited.
Returning an item to the map supply cancels the craft. A catch-up sweep on
arming adopts items already sitting beside boards. The craft's round is the
round in play when the item left the supply (the crafting faction's last
noted round if it moved during someone else's turn); the craft VP is looked
up backwards: the faction's first score increase since the item left.
Crafted items appear as small pictures climbing the right edge of the
round's score cell (bottom-right, then up, then a second column — the
score number stays clear) and as indented `Coins (T3, +1)` lines in the
export. In EDIT, the **ITEMS** button opens an editor listing every
faction's crafts: click **T#** then pick the round directly from a T1–T10
row, **×** to remove, **+** to add a missed item by name (points are dealt
by the scorekeeper and are not edited here). Turning CRAFT
off hides all craft pictures and drops the craft lines from the export
(the data is kept and returns when toggled back on). Name- and
map-agnostic by design; it is experimental — expect rough edges and report
them.

## Ideas not built yet

- Discord bot answering with the current box score (the Notebook JSON
  mirror is ready fuel).
- Dominance state per row (today: type `D` into a cell in SETUP).
- hoot3_video_analysis ingester for the exported JSON.
