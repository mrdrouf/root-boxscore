#!/usr/bin/env python3
"""Build 'Root Box Score.json' (a TTS Saved Object) from boxscore.lua.

Outputs:
  out/Root Box Score.json   the spawnable object (BlockSquare + script)
  out/Root Box Score.png    gallery thumbnail
and installs copies into the TTS Saved Objects folder so it appears in-game
under Objects -> Saved Objects.

Run:  python build.py            (build + install)
      python build.py --no-install
"""
import json
import os
import random
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
SAVED_OBJECTS = os.path.join(
    os.path.expanduser("~"), "Documents", "My Games", "Tabletop Simulator",
    "Saves", "Saved Objects")

NAME = "Root Box Score"

PARCHMENT = {"r": 0.17, "g": 0.10, "b": 0.05}  # dark walnut board


def default_webhook():
    """A URL in tools/discord_webhook.txt (gitignored - it is a posting
    credential) gets baked into the LOCALLY INSTALLED object only, so the
    group's own Saved Object ships preconfigured. The out/ artifact that is
    committed and published never contains it."""
    path = os.path.join(HERE, "tools", "discord_webhook.txt")
    try:
        with open(path, encoding="utf-8") as f:
            u = f.read().strip()
        return u if u.startswith("http") else ""
    except OSError:
        return ""


def block(lua, webhook=""):
    return {
        "GUID": "%06x" % random.randrange(16 ** 6),
        "Name": "BlockSquare",
        "Transform": {
            # the RTT mod's default spot: centre of the maintainer's
            # box-score rectangle, left of the map, on the table surface
            # (this mod's table top is at y ~ 11.65 - lower spawns land
            # INSIDE the table). Menu drops follow the cursor, but pastes
            # and scripted spawns land exactly here, and the 270 rotation
            # applies either way.
            "posX": -58.36, "posY": 11.652, "posZ": -0.05,
            "rotX": 0.0, "rotY": 270.0, "rotZ": 0.0,
            "scaleX": 33.18, "scaleY": 0.18, "scaleZ": 9.07,
        },
        "Nickname": NAME,
        "Description": (
            "Automatic box score for Root - Ultimate Collection.\n"
            "Reads each faction's VP marker on the map's score track and "
            "records a per-round box score, following the TTS turn system. "
            "The INFO button on the sheet is the manual."),
        "GMNotes": webhook,
        "ColorDiffuse": PARCHMENT,
        "Locked": False,
        "Grid": True,
        "Snap": True,
        "IgnoreFoW": False,
        "MeasureMovement": False,
        "DragSelectable": True,
        "Autoraise": True,
        "Sticky": True,
        "Tooltip": False,
        "GridProjection": False,
        "HideWhenFaceDown": False,
        "Hands": False,
        "LuaScript": lua,
        "LuaScriptState": "",
        "XmlUI": "",
    }


def wrapper(obj):
    return {
        "SaveName": "",
        "Date": "",
        "VersionNumber": "",
        "GameMode": "",
        "GameType": "",
        "GameComplexity": "",
        "Tags": [],
        "Gravity": 0.5,
        "PlayArea": 0.5,
        "Table": "",
        "Sky": "",
        "Note": "",
        "TabStates": {},
        "LuaScript": "",
        "LuaScriptState": "",
        "XmlUI": "",
        "ObjectStates": [obj],
    }


def thumbnail(path):
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new("RGB", (256, 256), (232, 219, 189))
    d = ImageDraw.Draw(im)
    d.rectangle([8, 8, 247, 247], outline=(38, 23, 13), width=4)
    try:
        big = ImageFont.truetype("georgiab.ttf", 40)
        small = ImageFont.truetype("georgia.ttf", 22)
    except OSError:
        big = small = ImageFont.load_default()
    d.text((128, 52), "ROOT", font=big, fill=(38, 23, 13), anchor="mm")
    d.text((128, 96), "BOX SCORE", font=small, fill=(122, 74, 22), anchor="mm")
    # tiny score grid motif
    x0, y0, cw, ch = 36, 130, 26, 24
    for r in range(3):
        for c in range(7):
            d.rectangle([x0 + c * cw, y0 + r * ch, x0 + (c + 1) * cw, y0 + (r + 1) * ch],
                        outline=(38, 23, 13), width=2)
    for (r, c, v) in [(0, 0, "3"), (0, 1, "5"), (0, 2, "8"), (1, 0, "2"),
                      (1, 1, "2"), (1, 2, "6"), (2, 0, "1"), (2, 1, "4"), (2, 2, "9")]:
        d.text((x0 + c * cw + cw / 2, y0 + r * ch + ch / 2), v,
               font=small, fill=(122, 74, 22), anchor="mm")
    im.save(path)


def main():
    import datetime
    build_id = "b" + datetime.datetime.now().strftime("%d.%H%M")
    lua = open(os.path.join(HERE, "boxscore.lua"), encoding="utf-8").read()
    lua = lua.replace('local BUILD = "dev"', 'local BUILD = "%s"' % build_id)
    print("BUILD_ID", build_id)
    os.makedirs(OUT, exist_ok=True)
    # the public artifact: never carries the webhook credential
    out_json = os.path.join(OUT, NAME + ".json")
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(wrapper(block(lua)), f, indent=2)
    out_png = os.path.join(OUT, NAME + ".png")
    thumbnail(out_png)
    print("built", out_json)

    if "--no-install" not in sys.argv:
        if os.path.isdir(SAVED_OBJECTS):
            # the local install gets the group webhook baked in
            with open(os.path.join(SAVED_OBJECTS, NAME + ".json"), "w",
                      encoding="utf-8") as f:
                json.dump(wrapper(block(lua, default_webhook())), f, indent=2)
            shutil.copy(out_png, SAVED_OBJECTS)
            print("installed to", SAVED_OBJECTS,
                  "(webhook baked)" if default_webhook() else "(no webhook)")
        else:
            print("Saved Objects folder not found:", SAVED_OBJECTS)


if __name__ == "__main__":
    main()
