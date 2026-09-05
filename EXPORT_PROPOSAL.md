# Root box score → tournament site: proposed export

Your schema, unchanged, with **one addition**. Everything else follows your example exactly, so
nothing on your side needs to change to read it.

Attached: `EXPORT_EXAMPLE_2P.json` (a plain two-player game) and `EXPORT_TEMPLATE.json` (four
players, exercising dominance, Brazen Demagogue, a Vagabond and an undrafted faction). Both are
generated **by the exporter itself**, so they cannot drift from what the mod actually sends.

## The one addition: `player_steam_id`

```json
"player": "mrdrouf",
"player_steam_id": "76561198012345678",
```

You wrote that `player` would only resolve if it matched a Discord username, and that coming from
TTS this is unlikely. TTS does expose the account's Steam id, which is stable and unique — so you can
map it to an account once and every later export resolves itself, with no renaming problem.

It sits **alongside** `player`, never replacing it, so your existing fallback still works. It is
`null` unless that colour was seated when EXPORT was pressed.

Drop the key if you don't want it; nothing else depends on it.

## Confirmations, so you don't have to re-check

* **`dominance`** — per your answer, turn-level `"dominance": true` means the dominance card has been
  activated. That is what we emit: every turn from the activation round onward. Participant-level
  `dominance` carries the suit (`"Bird"`, `"Fox"`) or `null`.
* **`turn`** is the round number; **`score`** is the running total at the end of that round, not the
  points gained.
* **`tournament_score`** is filled: `1` for the winner, `0` for the others. Root ends two ways and
  the sheet detects both — a marker reaching 30, and a declared dominance win.
* **Key order is not significant.** Lua tables are unordered; the attached files are sorted for
  reading only.

## Two things you should decide

1. **`0.5` (shared win).** In Root that means a coalition, and the sheet does not track coalitions,
   so `coalition` is always `null` and a shared win comes through as `1`/`0`. If you want it, say how
   you'd like a coalition represented and we'll detect it.
2. **Unfinished games.** If no winner is recorded, every `tournament_score` is `null` rather than
   `0`, so an abandoned or in-progress game does not arrive looking like a table of losses. Tell us
   if you would rather it were omitted entirely.

## Always present, never guessed

Every key appears in every export. Anything the sheet cannot know is `null` (or `[]`), never a
missing key, so the shape is identical between games and your parser never has to branch on absence.
Currently always `null`: `coalition`, `captains`, `discarded_captain` — the sheet has no source for
them, and we would rather send nothing than invent it.
