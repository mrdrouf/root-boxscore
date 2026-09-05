# Root box score export — fields

One JSON per game, written to the TTS Notebook tab "BoxScore" (and posted to Discord if a webhook is
set). See `EXPORT_EXAMPLE.json`. Every key is always present; anything unknown is `null` or `[]`,
never omitted. Key order is not significant.

## Top level

| field | meaning |
|---|---|
| `board_map` | map slug: `autumn`, `winter`, `lake`, `mountain`, `marsh`, `gorge` |
| `deck` | deck slug: `base-deck`, `exiles-partisans`, `squires-disciples` |
| `undrafted_faction` | faction slug left undrafted, or `null` |
| `undrafted_vagabond` | its vagabond character, or `null` |
| `undrafted_captains` | `[]` — not tracked |
| `participants` | one entry per faction, below |

## Participant

| field | meaning |
|---|---|
| `player` | in-game name |
| `player_steam_id` | Steam id — stable, unlike the name; `null` if that seat was empty at export |
| `faction` | slug: `marquise-de-cat`, `eyrie-dynasties`, `woodland-alliance`, `lizard-cult`, `riverfolk-company`, `underground-duchy`, `corvid-conspiracy`, `lord-of-the-hundreds`, `keepers-in-iron`, `knaves-of-the-deepwood`, `twilight-council`, `lilypad-diaspora`, `vagabond` |
| `vagabond` | character slug for Vagabond/Knaves, else `null` |
| `starting_leader` | Eyrie leader (`Commander`, `Despot`, `Builder`, `Charismatic`), else `null` |
| `dominance` | suit of the dominance card taken: `Fox`, `Rabbit`, `Mouse`, `Bird`; else `null` |
| `brazen_demagogue` | `true` if the dominance was played as Brazen Demagogue |
| `coalition` | `null` — not tracked |
| `captains` | `[]` — not tracked |
| `discarded_captain` | `null` — not tracked |
| `tournament_score` | `1` winner, `0` loser; `null` if the game is unfinished |
| `turn_order` | seat order, 1-based |
| `turns` | one entry per completed round |

## Turn

| field | meaning |
|---|---|
| `turn` | round number |
| `score` | running total at the end of that round, not points gained |
| `dominance` | `true` from the round the dominance card was activated onward; absent otherwise |

## Notes

* **`tournament_score`** is decided by the sheet: a marker reaching 30, or a declared dominance win.
  `0.5` (a shared win, i.e. a coalition) is never emitted, since coalitions are not tracked.
* **`player_steam_id`** is the only field not in the original spec. It solves the name-matching
  problem; drop it if unwanted, nothing depends on it.
