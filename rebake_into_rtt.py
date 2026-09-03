"""Re-bake boxscore.lua into RTT's saved-object JSON without losing RTT UI tweaks."""

from __future__ import annotations

import json
import re
import sys
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
    """Apply the RTT fork on top of the standalone source.

    The fork used to be 13 transforms. On 2026-09-02 the placeholder-row work
    (renderMinRows, EMPTY_ROW, the `not placeholder` guards) was merged UPSTREAM
    into boxscore.lua, so those steps stopped matching and this script aborted
    with "minimum RTT row height: expected one source match, found 0" -- which
    silently blocked every box-score fix from reaching the mod.

    What genuinely still differs is exactly FOUR lines, verified by diffing the
    source against the live bake: BUILD, BASE_SCALE, showR and the ww/wh slab.
    Two are recovered from the current bake (so they survive), two are applied
    here. `python rebake_into_rtt.py --check` asserts a rebake of the unmodified
    source reproduces the current bake byte-for-byte.
    """

    # Preserved from the current bake: RTT's release label and larger base scale.
    source = re.sub(
        r"^local BUILD = .*?$",
        lambda _m: existing_line(existing, r"^local BUILD = .*?$", "BUILD line"),
        source,
        count=1,
        flags=re.MULTILINE,
    )
    source = re.sub(
        r"^local BASE_SCALE\s*=.*?$",
        lambda _m: existing_line(existing, r"^local BASE_SCALE\s*=.*?$", "BASE_SCALE line"),
        source,
        count=1,
        flags=re.MULTILINE,
    )

    # Applied here: RTT pins the round-column count and the slab rectangle.
    source = replace_once(
        source,
        "  local showR = math.min(math.max((S.cols or 10) + 1, maxLocks + 2), 41)\n",
        "  local showR = math.min((S.cols or 10) + 1, 41)   -- FIXED: no maxLocks growth\n",
        "fixed RTT round columns",
    )
    source = replace_once(
        source,
        "  local wh = (H + 2 * FRAME) * k\n",
        "  local wh = (H + 2 * FRAME) * k\n"
        "  ww = 31.80 wh = 10.42  -- FIXED to the maintainer 4-card box-score rectangle\n",
        "fixed RTT slab size",
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
        "no maxLocks growth",
        "local function dominanceCardSuit",
        "if seatOrder() then dirty = true end",
        "if pinFirstSeat() then dirty = true end",
        "dominance = row.dom",
    ):
        if needle not in baked:
            raise RuntimeError(f"post-bake validation failed: missing {needle!r}")

    if "--check" in sys.argv:
        if baked == obj["LuaScript"]:
            print("CHECK OK: rebaking the current source reproduces the current bake byte-for-byte")
            return
        import difflib
        a, b = obj["LuaScript"].split("\n"), baked.split("\n")
        diff = [l for l in difflib.unified_diff(a, b, "shipped", "rebaked", n=0, lineterm="")]
        raise SystemExit("CHECK FAILED: rebake would change %d diff lines:\n%s"
                         % (len(diff), "\n".join(diff[:40])))

    obj["LuaScript"] = baked
    payload = json.dumps(obj, ensure_ascii=True, separators=(",", ":"))
    replacement = f"RTT_BOXSCORE_JSON = [====[{payload}]====]"
    updated = logic[: match.start()] + replacement + logic[match.end() :]
    # Path.write_text(newline=...) is 3.10+; this repo is built on macOS system
    # python 3.9, so open() explicitly. newline="\n" keeps logic.lua LF -- a CRLF
    # flip here would rewrite every line of the file as a spurious diff.
    with open(LOGIC, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)
    print(f"rebaked {len(baked.splitlines())} Lua lines into {LOGIC}")


if __name__ == "__main__":
    main()
