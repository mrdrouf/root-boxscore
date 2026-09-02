# Root Box Score

An automatic in-game box score for **Root – Ultimate Collection** in Tabletop
Simulator. It's one piece of walnut cardboard that reads the real victory-point
markers on the real board — no computer vision — and keeps a per-round score
table that follows the TTS turn system. Silent, self-contained, no companion
program.

## Install

Drop the two files from [`out/`](out/) — `Root Box Score.json` and
`Root Box Score.png` — into your Saved Objects folder:

    Documents\My Games\Tabletop Simulator\Saves\Saved Objects

Then spawn it from **Objects → Saved Objects → Root Box Score**. It arrives at
the RTT tournament table's default spot (left of the map); drag it anywhere.

## How it reads the board (no vision)

- **Markers by name.** Every faction's VP token is named `"<Faction> VP"`
  (`Marquise VP`, `Vagabond VP`, …). The sheet finds them by name — works for
  any faction, fan factions included.
- **Track by geometry.** Each map embeds the printed 0–30 track as snap points
  (31 columns × 3 sub-rows). The sheet finds them in the map's *local*
  coordinates, so the board can sit anywhere at any rotation. A marker's score
  is the nearest column; 0 is fixed at the track's max local coordinate
  (bottom-left as displayed). Held or off-track markers keep their last score.
- **Rows appear automatically.** A faction joins the sheet the moment its
  marker stands on the track; its row icon is the marker's own artwork.
- **Seat pairing.** Each faction is paired to the nearest seated player by
  distance from hand zone to the faction's *anchor* — its supply bag (with the
  mod's quirks handled: Rats→"Hundreds Supply", Crows→"Corvid", Badgers→
  "Keeper"), or, for the supply-less Vagabond, his faction board (found by
  artwork — the board never moves; his pawn does). Typed names always win.

## Turns and locking

- **The TTS turn system is the authority.** With turns running and every row
  seated, each turn pass locks the finishing faction's score by itself. Without
  full coverage, a manual **END TURN** button appears instead — never both.
- **The first turn is always the first player.** Until a turn is recorded, the
  active pointer is pinned to the turn order's first player (`Turns.order[1]`),
  no matter how late that faction's row joined the sheet; after that it follows
  the live current player, so every later round opens on the first player too.
- **The highlighted round column is the single truth.** A lock always writes
  that column, overwriting whatever it holds. The sheet never skips to another
  column. If the count is off, click the correct column number in EDIT — the
  highlight moves and locks follow it.
- **Reaching 30 ends the game.** The 30 prints into the current column and
  everything stops — the turn does not pass, nothing more locks, exactly once.
  Move that marker back below 30 and the cell restores to exactly what it held;
  play resumes.
- **+ / −** move the faction's real marker along the track. Placement always
  keeps every marker visible (centre, then up, then down) — never stacked.

## The sheet

- **One grabbable slab.** The object sizes itself to the rendered sheet plus a
  walnut rim; the rim and all non-buttons let clicks through, so you can drag
  from anywhere that isn't a control. **±10%** size buttons; the footprint is
  stable (a set number of rows and 10 columns) and only grows past round 10.
- **EDIT face** — everything editable in place, with a real cursor: player
  names, any score cell, the round (click a column number), whose turn (click a
  portrait), faction order (▲), game name, map, deck, per-row character (▼:
  Eyrie commander / Knaves captains / Vagabond character, auto-filled from the
  nearby card), the Discord webhook, the CRAFT toggle, and the **unpicked
  faction** (13-faction roster picker — never auto-detected, the draft leaves no
  trace). Handles **dominance** (a faction on a dominance card keeps its frozen
  score).
- **Silent.** Nothing hits the chat in play. Right-click → *diagnose* is the
  only thing that speaks.

## Export

- **EXPORT → Discord**, straight from the object. Paste a webhook once into
  EDIT → **DISCORD** (saved with the object). The footer confirms once Discord
  acknowledges. Long tables are split across messages, never truncated.
- **Notebook mirror.** Every export also writes the full JSON record (meta,
  rows, players, characters, locks, edits, crafts, unpicked, event log) to the
  Notebook tab `BoxScore`.
- **COPY** opens that same record as selectable JSON — click, Ctrl+A, Ctrl+C.
  (TTS scripts can't touch the OS clipboard, and the sheet needs no external
  program, so this is the in-game equivalent.)

## Craft tracking (experimental)

Toggle **CRAFT** in EDIT. The sheet watches the map's item supply; an item taken
from it and set beside a faction's board is recorded as crafted that round, its
picture shown on the round's score cell and an indented `Coins (T3, +1)` line in
the export. Items are identified by artwork (they're unnamed in the mod).
Returning an item to the supply cancels the craft. The **ITEMS** button opens an
editor per faction: **T#** picks the round, **×** removes, **+** adds a missed
item. Turning CRAFT off hides all of it, exports included (the data is kept).

## Development

- `boxscore.lua` — the whole object script; state persists via onSave/onLoad.
- `build.py` — builds `out/Root Box Score.json` + thumbnail and installs them.
  A webhook in `tools/discord_webhook.txt` (gitignored — it's a credential) is
  baked only into the *local* install; the published `out/` artifact never
  carries it.
- `tools/tts_exec.py script.lua` — run Lua in a live TTS instance (External
  Editor API, port 39999; data back via `WebRequest.post`). Never `print()`.
- UI geometry: the canvas lies in the object's top face; rotation `0 0 0` is
  flat; **100 px per world unit**; InputFields ignore `alignment` but honour
  `textAlignment`.

## Ideas not built yet

- A Discord bot that answers with the current box score (the Notebook JSON is
  ready fuel).
- An ingester that feeds the exported JSON into game-analysis pipelines.
