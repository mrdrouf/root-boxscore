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

**Implemented.** `tournamentPayload()` in boxscore.lua builds exactly this, and COPY shows it.
`exportPayload()` still builds the mod's own internal record for the Discord/notebook export -- the
two are deliberately separate.

Mapping, checked against the source. An earlier draft of this table called `board_map`, `deck` and
`starting_leader` gaps; they are not -- the object already detects all three.

| schema field | source | note |
|---|---|---|
| `board_map` | `S.meta.map` | auto-detected from the map's image URL (`MAP_NAMES`), slugified |
| `deck` | `S.meta.deck` | auto-detected from the card-back art (`DECK_BACKS`); "and" is dropped, so "Squires and Disciples" -> `squires-disciples` |
| `faction` | `row.fac` via `FACTION_SLUG` | the roster's short names map to the site's full slugs (`Rats` -> `lord-of-the-hundreds`) |
| `player` | `row.player` | omitted when blank |
| `turn_order` | row index | rows are already ordered by physical seat |
| `turns[]` | `row.locks` | one entry per locked round; `-1` (no score yet) is skipped |
| `turns[].dominance` | `row.dom.round` | set from the round the dominance was taken onward |
| `dominance` | `row.dom.suit` | capitalised for the site: `bird` -> `Bird` |
| `brazen_demagogue` | `row.dom.kind` | already distinguished, for the frozen-score rule |
| `vagabond` | `row.variant` | the variant auto-detect resolves the character for Vagabond and Knaves |
| `starting_leader` | `row.variant` | the SAME field: for the Eyrie it holds a leader, not a character |
| `undrafted_faction` / `undrafted_vagabond` | `S.unpicked`, `S.unpickedVar` | first unpicked faction |
| `coalition` | **not tracked** | omitted |
| `captains` / `discarded_captain` | **not tracked** | omitted |
| `tournament_score` | **not tracked** | a tournament outcome, not a game fact -- omitted |

Nothing unsourced is guessed: those four keys are simply absent, which the schema allows.
