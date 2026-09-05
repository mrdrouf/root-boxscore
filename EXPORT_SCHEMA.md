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

## What the box score can already fill, and what it cannot

`exportPayload()` (boxscore.lua) is the current shape and is NOT this schema -- it is the mod's own
internal record. Mapping, checked against the source rather than assumed:

| schema field | source today | note |
|---|---|---|
| `turns[]` | `S.turns`, `row.locks` | the object's whole purpose; per-turn locked scores already exist |
| `turn_order` | `Turns.order`, row order by seat | rows are already ordered by physical seat |
| `faction` | `row.fac` | needs slugifying (`Woodland Alliance` -> `woodland-alliance`) |
| `player` | `row.player` | |
| `vagabond` | `row.variant` | the per-row variant auto-detect already resolves vagabond characters |
| `dominance` | `row.dom` | schema wants the SUIT name (`"Bird"`); `row.dom` carries suit + turn + kind |
| `brazen_demagogue` | `row.dom.kind == "brazen_demagogue"` | already distinguished, for the frozen-score rule |
| `undrafted_faction` / `undrafted_captains` | `S.unpicked`, `S.unpickedVar` | `unpickedList()` already builds this |
| `board_map` | **gap** | RTT publishes `RTT_CURRENT_MAP` on board `bab7e1`; the standalone has no map NAME, only the score-track geometry |
| `deck` | **gap** | nothing reads which deck was chosen |
| `coalition` | **gap** | vagabond coalitions are not tracked |
| `captains` / `discarded_captain` | **gap** | Knaves captains are not tracked per row |
| `starting_leader` | **gap** | the Eyrie leader is not tracked |
| `tournament_score` | **gap** | a tournament outcome, not a game fact -- probably manual entry |

The gaps are all optional fields, so a first version can emit the core and omit them.
