# Root box score export — fields

One JSON per game, written to the TTS Notebook tab "BoxScore" (and posted to Discord if a webhook is
set). See `EXPORT_EXAMPLE.json`. Every key is always present; anything unknown is `null` or `[]`,
never omitted. Key order is not significant.

## Top level

| field | meaning |
|---|---|
| `board_map` | `autumn`, `winter`, `lake`, `mountain`, `marsh`, `gorge` |
| `deck` | `base-deck`, `exiles-partisans`, `squires-disciples` |
| `undrafted_faction` | the faction left undrafted, or `null` |
| `undrafted_vagabond` | its vagabond character, or `null` |
| `undrafted_captains` | `[]` — not tracked |
| `participants` | one entry per faction, below |

## Participant

| field | meaning |
|---|---|
| `player` | in-game name |
| `player_steam_id` | Steam id — stable, unlike the name; `null` if that seat was empty at export |
| `faction` | one of `marquise-de-cat`, `eyrie-dynasties`, `woodland-alliance`, `lizard-cult`, `riverfolk-company`, `underground-duchy`, `corvid-conspiracy`, `lord-of-the-hundreds`, `keepers-in-iron`, `knaves-of-the-deepwood`, `twilight-council`, `lilypad-diaspora`, `vagabond` |
| `vagabond` | the character, for Vagabond/Knaves; else `null` |
| `starting_leader` | Eyrie leader (`Commander`, `Despot`, `Builder`, `Charismatic`), else `null` |
| `dominance` | suit of the dominance card taken: `Fox`, `Rabbit`, `Mouse`, `Bird`; else `null` |
| `brazen_demagogue` | `true` if the dominance was played as Brazen Demagogue |
| `coalition` | the faction this Vagabond allied with, else `null` |
| `captains` | `[]` — not tracked |
| `discarded_captain` | `null` — not tracked |
| `tournament_score` | `1` winner, `0` loser, `0.5` each when a coalition shares the win; `null` if unfinished |
| `turn_order` | seat order, 1-based |
| `turns` | one entry per completed round |

## Turn

| field | meaning |
|---|---|
| `turn` | round number |
| `score` | running total at the end of that round, not points gained |
| `dominance` | `true` from the round the dominance card was activated onward; absent otherwise |

## Notes

* **Identifiers** are lower-case with hyphens. Six of them (`autumn`, `squires-disciples`,
  `woodland-alliance`, `eyrie-dynasties`, `lord-of-the-hundreds`, `keepers-in-iron`) are taken
  verbatim from your example; the rest follow the same pattern. Say if you would rather have
  different ones.
* **`tournament_score`** is decided by the sheet: a marker reaching 30, or a declared dominance win.
  A coalition makes it `0.5` for both the winner and the allied Vagabond.
* **Coalition** (Root, Vagabond, 4+ players): the Vagabond cannot rule, so its dominance card buys
  an alliance instead — its marker leaves the track and it wins if the ally wins.
* **`player_steam_id`** is the only field not in the original spec. It solves the name-matching
  problem; drop it if unwanted, nothing depends on it.
