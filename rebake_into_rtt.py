"""Re-bake boxscore.lua into RTT's saved-object JSON without losing RTT UI tweaks."""

from __future__ import annotations

import json
import re
from pathlib import Path


HERE = Path(__file__).resolve().parent
SOURCE = HERE / "boxscore.lua"
LOGIC = HERE.parent / "root_tabletop_tournament" / "gen" / "src" / "logic.lua"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one source match, found {count}")
    return text.replace(old, new, 1)


def existing_line(lua: str, pattern: str, label: str) -> str:
    match = re.search(pattern, lua, re.MULTILINE)
    if not match:
        raise RuntimeError(f"could not recover RTT's {label} from baked Lua")
    return match.group(0)


def apply_rtt_additions(source: str, existing: str) -> str:
    """Apply the small, audited RTT fork on top of the standalone source."""

    # Preserve RTT's release label and larger base scale from the current bake.
    source = re.sub(
        r"^local BUILD = .*?$",
        existing_line(existing, r"^local BUILD = .*?$", "BUILD line"),
        source,
        count=1,
        flags=re.MULTILINE,
    )
    source = re.sub(
        r"^local BASE_SCALE\s*=.*?$",
        existing_line(existing, r"^local BASE_SCALE\s*=.*?$", "BASE_SCALE line"),
        source,
        count=1,
        flags=re.MULTILINE,
    )

    helper = '''local function renderMinRows()
  local n = tonumber(Global.getVar("RTT_BOXSCORE_MIN"))
  if not n then
    local dn = tonumber(Global.getVar("RTT_DN"))
    if dn then n = dn - 1 end
  end
  return math.max(1, n or 4)
end

'''
    source = replace_once(
        source,
        "function rebuildUI()\n",
        helper + "function rebuildUI()\n",
        "renderMinRows insertion",
    )
    source = replace_once(
        source,
        "  local showR = math.min(math.max((S.cols or 10) + 1, maxLocks + 2), 41)\n",
        "  local showR = math.min((S.cols or 10) + 1, 41)   -- FIXED: no maxLocks growth\n",
        "fixed RTT round columns",
    )
    source = replace_once(
        source,
        "  local H = 56 + headH + math.max(1, #S.rows) * (rowH + 3) + 42\n",
        "  local nMin = renderMinRows()\n"
        "  local H = 56 + headH + math.max(nMin, #S.rows) * (rowH + 3) + 42\n",
        "minimum RTT row height",
    )
    source = replace_once(
        source,
        "  local wh = (H + 2 * FRAME) * k\n",
        "  local wh = (H + 2 * FRAME) * k\n"
        "  ww = 31.80 wh = 10.42  -- FIXED to the maintainer 4-card box-score rectangle\n",
        "fixed RTT slab size",
    )
    source = replace_once(
        source,
        '''  -- faction rows
  for i, row in ipairs(S.rows) do
    local isActive = (i == S.active) and (fullTurnCoverage() or not turnsRunning())
''',
        '''  -- faction rows
  local EMPTY_ROW = { fac="", player="", tintHex="3A2A1A", iconUrl="", variant="", score=-1, locks={}, edits={}, crafts=nil }
  for i = 1, math.max(nMin, #S.rows) do
    local row = S.rows[i] or EMPTY_ROW
    local placeholder = (S.rows[i] == nil)
    local isActive = (not placeholder) and (i == S.active) and (fullTurnCoverage() or not turnsRunning())
''',
        "RTT placeholder row loop",
    )
    source = replace_once(
        source,
        '''    if S.setup then
      add('<Button id="act_' .. i .. '" preferredWidth="' .. iconW
''',
        '''    if S.setup and not placeholder then
      add('<Button id="act_' .. i .. '" preferredWidth="' .. iconW
''',
        "placeholder portrait guard",
    )
    source = replace_once(
        source,
        "    if S.setup and variantOptions(row.fac) then\n",
        "    if S.setup and not placeholder and variantOptions(row.fac) then\n",
        "placeholder variant guard",
    )
    source = replace_once(
        source,
        '''    if S.setup then
      add('<InputField id="nm_' .. i .. '" fontSize="15" textAlignment="MiddleCenter"'
''',
        '''    if S.setup and not placeholder then
      add('<InputField id="nm_' .. i .. '" fontSize="15" textAlignment="MiddleCenter"'
''',
        "placeholder name guard",
    )
    source = replace_once(
        source,
        '''      if S.setup then
        add('<InputField id="cl_' .. i .. '_' .. r .. '" fontSize="15" textAlignment="MiddleCenter"'
''',
        '''      if S.setup and not placeholder then
        add('<InputField id="cl_' .. i .. '_' .. r .. '" fontSize="15" textAlignment="MiddleCenter"'
''',
        "placeholder cell guard",
    )
    source = replace_once(
        source,
        "    if row.dom ~= nil then\n"
        "      add('<Text preferredWidth=\"28\"' .. NOClick .. '> </Text>')\n",
        "    if placeholder or row.dom ~= nil then\n"
        "      add('<Text preferredWidth=\"28\"' .. NOClick .. '> </Text>')\n",
        "placeholder score-button guard",
    )
    source = replace_once(
        source,
        "    if S.setup and i > 1 then\n",
        "    if S.setup and i > 1 and not placeholder then\n",
        "placeholder move guard",
    )
    source = replace_once(
        source,
        '''    if S.setup then
      chip("del_" .. i, "uiRowBtn", BTN_SOFT, 26, 11, RUST, "&#215;")
''',
        '''    if S.setup and not placeholder then
      chip("del_" .. i, "uiRowBtn", BTN_SOFT, 26, 11, RUST, "&#215;")
''',
        "placeholder delete guard",
    )
    return source


def main() -> None:
    logic = LOGIC.read_text(encoding="utf-8")
    match = re.search(
        r"^RTT_BOXSCORE_JSON = \[====\[(.*?)\]====\]$",
        logic,
        re.MULTILINE,
    )
    if not match:
        raise RuntimeError("RTT_BOXSCORE_JSON long-bracket line not found")

    obj = json.loads(match.group(1))
    if not isinstance(obj, dict) or not isinstance(obj.get("LuaScript"), str):
        raise RuntimeError("RTT_BOXSCORE_JSON does not contain a LuaScript string")

    source = SOURCE.read_text(encoding="utf-8")
    baked = apply_rtt_additions(source, obj["LuaScript"])
    for needle in (
        'Global.getVar("RTT_BOXSCORE_MIN")',
        "local EMPTY_ROW =",
        "ww = 31.80 wh = 10.42",
        "local function dominanceCardSuit",
        "if seatOrder() then dirty = true end",
        "dominance = row.dom",
    ):
        if needle not in baked:
            raise RuntimeError(f"post-bake validation failed: missing {needle!r}")

    obj["LuaScript"] = baked
    payload = json.dumps(obj, ensure_ascii=True, separators=(",", ":"))
    replacement = f"RTT_BOXSCORE_JSON = [====[{payload}]====]"
    updated = logic[: match.start()] + replacement + logic[match.end() :]
    LOGIC.write_text(updated, encoding="utf-8", newline="\n")
    print(f"rebaked {len(baked.splitlines())} Lua lines into {LOGIC}")


if __name__ == "__main__":
    main()
