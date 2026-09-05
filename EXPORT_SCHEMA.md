# Box-score export schema

The target format for COPY, given by the tournament-site developer (2026-09-05). The point is that a
user can copy this out of the box score and paste it into Discord, so the site can ingest a finished
game without an API on either side.

Almost every field is optional. **`board_map`, `deck` and the per-participant `turns` are the useful
core.** `tournament_score` of `1` or `0.5` counts as a win, `0` is a loss. `player` only resolves if
it matches the Discord username -- unlikely coming from TTS, and not a problem: players can be
attached on the site instead.

```json
{
  "board_map": "autumn",
  "deck": "squires-disciples",
  "undrafted_faction": "keepers-in-iron",
  "undrafted_vagabond": null,
  "undrafted_captains": [],

  "participants": [
    {
      "player": "mrdrouf",
      "coalition": null,
      "faction": "woodland-alliance",
      "dominance": null,
      "vagabond": null,
      "captains": [],
      "discarded_captain": null,
      "starting_leader": null,
      "brazen_demagogue": false,
      "tournament_score": 0.5,
      "turn_order": 1,
      "turns": [
        {"turn": 1, "score": 3},
        {"turn": 2, "score": 8},
        {"turn": 3, "score": 14},
        {"turn": 4, "score": 19},
        {"turn": 5, "score": 25},
        {"turn": 6, "score": 28},
        {"turn": 7, "score": 30}
      ]
    },
    {
      "player": "mrmirz",
      "coalition": null,
      "faction": "lord-of-the-hundreds",
      "dominance": "Bird",
      "vagabond": null,
      "captains": [],
      "discarded_captain": null,
      "starting_leader": null,
      "brazen_demagogue": true,
      "tournament_score": 0,
      "turn_order": 2,
      "turns": [
        {"turn": 1, "score": 1},
        {"turn": 2, "score": 4},
        {"turn": 3, "score": 8},
        {"turn": 4, "score": 14, "dominance": true},
        {"turn": 5, "score": 17, "dominance": true},
        {"turn": 6, "score": 19, "dominance": true}
      ]
    },
    {
      "player": "bw",
      "faction": "vagabond",
      "vagabond": "tinker",
      "coalition": "woodland-alliance",
      "tournament_score": 0.5,
      "turn_order": 3,
      "turns": [
        {"turn": 1, "score": 1},
        {"turn": 2, "score": 4},
        {"turn": 3, "score": 8},
        {"turn": 4, "score": 10},
        {"turn": 5, "score": 10, "dominance": true},
        {"turn": 6, "score": 10, "dominance": true}
      ]
    },
    {
      "player": "bob-tester",
      "faction": "eyrie-dynasties",
      "starting_leader": "Commander",
      "dominance": "Fox",
      "tournament_score": 0,
      "turn_order": 4,
      "turns": [
        {"turn": 1, "score": 3},
        {"turn": 2, "score": 8},
        {"turn": 3, "score": 14},
        {"turn": 4, "score": 19},
        {"turn": 5, "score": 25},
        {"turn": 6, "score": 29, "dominance": true}
      ]
    }
  ]
}
```

## What the box score fills, and what it does not

**Implemented.** `tournamentPayload()` builds this and `exportJson()` serialises it; EXPORT writes it
to the notebook tab **"BoxScore"** and, if a webhook is set, posts it to Discord. One record either
way -- there is no second copy and no second tab.

EVERY field in the example is emitted. What the object cannot know comes out as `null` (or `[]`),
never as a missing key: absent and unknown are not the same thing to whoever ingests this. Lua needs
placeholders for that, since `JSON.encode` drops a nil and writes `{}` for an empty table.

| schema field | source | note |
|---|---|---|
| `board_map` | `S.meta.map` | auto-detected from the map's image URL (`MAP_NAMES`), slugified |
| `deck` | `S.meta.deck` | auto-detected from the card-back art (`DECK_BACKS`); "and" is dropped, so "Squires and Disciples" -> `squires-disciples` |
| `faction` | `row.fac` via `FACTION_SLUG` | the roster's short names map to the site's slugs (`Rats` -> `lord-of-the-hundreds`) |
| `player` | `row.player` | the in-game/Steam display name; `null` when blank |
| `player_steam_id` | `Player.steam_id` for the row's seat colour | stable and unique, so the site can map it to an account once; `null` unless that colour is seated at export time |
| `turn_order` | row index | rows are ordered by physical seat |
| `turns[]` | `row.locks` | one entry per locked round; `-1` (no score yet) is skipped |
| `turns[].dominance` | `row.dom.round` | set from the round the dominance was taken onward |
| `dominance` | `row.dom.suit` | capitalised for the site: `bird` -> `Bird` |
| `brazen_demagogue` | `row.dom.kind` | already distinguished, for the frozen-score rule |
| `vagabond` | `row.variant` | the variant auto-detect resolves the character for Vagabond and Knaves |
| `starting_leader` | `row.variant` | the SAME field: for the Eyrie it holds a leader, not a character |
| `undrafted_faction` / `undrafted_vagabond` | `S.unpicked`, `S.unpickedVar` | first unpicked faction |
| `coalition` | not tracked | always `null` |
| `captains` / `discarded_captain` | not tracked | always `[]` / `null` |
| `tournament_score` | not tracked | an outcome, not a game fact; always `null` |

Non-ASCII is `\uXXXX`-escaped so the payload survives being pasted through Discord, a web form or a
terminal. It is the same JSON either way.

## A generated, always-current template

`EXPORT_TEMPLATE.json` (a four-player game, every feature exercised) and
`EXPORT_EXAMPLE_2P.json` (a plain two-player game) beside this file are produced BY the exporter, not written by hand, so it is
what the mod actually emits. Two notes for whoever consumes it:

* **Key order is not significant.** Lua tables are unordered and `JSON.encode` emits them in
  arbitrary order; the template is sorted into a readable order for humans only.
* **Every key is always present.** Anything the mod cannot know is `null` (or `[]`), never omitted,
  so the shape does not change between games.

## Why the notebook, and not a text box on the sheet

TTS has no clipboard API. An InputField on this object renders its placeholder but never text set
from script -- measured over five rounds in the maintainer's game, in every container, via the `text`
attribute, via inner text, via `setAttribute` and via `setValue`, with and without an id. A control
field cloned byte-for-byte from the working one, carrying the word `HELLO`, showed neither the word
nor its own placeholder.

The notebook body is a native text area that never touches the XML layer. It worked first time and
every time since, so it is the mechanism rather than a fallback: **Notebook -> "BoxScore" -> Ctrl+A,
Ctrl+C.**
