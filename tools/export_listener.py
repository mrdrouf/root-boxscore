#!/usr/bin/env python3
"""Receive Root Box Score exports from Tabletop Simulator.

The in-game object POSTs JSON to http://127.0.0.1:8790/boxscore
  - on every locked turn  (type = "lock")
  - on every EXPORT press (type = "export", includes the full event log)

Everything lands in the exports/ folder next to this script:
  exports/latest.json            always the most recent payload
  exports/feed.jsonl             one line per event (the API/bot feed)
  exports/boxscore_<stamp>.json  a full snapshot per EXPORT press

Discord (optional): put a webhook URL in tools/discord_webhook.txt and lock /
export events are forwarded there as short messages. No other dependencies.
"""
import datetime
import http.server
import json
import os
import socketserver
import subprocess
import urllib.parse
import urllib.request

PORT = 8790
HERE = os.path.dirname(os.path.abspath(__file__))
EXPORTS = os.path.join(os.path.dirname(HERE), "exports")
WEBHOOK_FILE = os.path.join(HERE, "discord_webhook.txt")


def webhook_url():
    try:
        with open(WEBHOOK_FILE, encoding="utf-8") as f:
            u = f.read().strip()
        return u if u.startswith("http") else None
    except OSError:
        return None


def to_discord(payload):
    url = webhook_url()
    if not url:
        return
    if payload.get("type") == "lock":
        lk = payload.get("locked", {})
        msg = "**{}** locked at **{}** (turn {})".format(
            lk.get("faction", "?"), lk.get("score", "?"), lk.get("turn", "?"))
    else:
        rows = payload.get("rows", [])
        board = ", ".join("{} {}".format(r.get("faction"), r.get("score"))
                          for r in rows)
        msg = "Box score exported - " + board
    body = json.dumps({"content": msg}).encode("utf-8")
    req = urllib.request.Request(url, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        print("  discord forward failed:", e)


def box_text(payload):
    """Render the payload as a paste-ready plain-text box score."""
    meta = payload.get("meta", {})
    bits = [b for b in (meta.get("map", ""), meta.get("deck", "")) if b]
    unp = payload.get("unpicked") or []
    if unp:
        bits.append("unpicked: " + ", ".join(unp))
    rows = payload.get("rows", [])
    rounds = max([len(r.get("locks", [])) for r in rows] + [0])
    lines = ["ROOT BOX SCORE - " + "  ".join(bits),
             "turn %s - %s" % (payload.get("turns", 0),
                               datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))]
    head = "%-11s %-14s" % ("faction", "player")
    head += "".join("%4d" % r for r in range(1, rounds + 1)) + "   now"
    lines.append(head)
    for r in rows:
        edits = r.get("edits") or {}
        cells = ""
        for k in range(1, rounds + 1):
            v = edits.get(str(k))
            if v is None:
                locks = r.get("locks", [])
                v = locks[k - 1] if k <= len(locks) and locks[k - 1] >= 0 else ""
            cells += "%4s" % v
        sc = r.get("score", -1)
        lines.append("%-11s %-14s%s   %3s" % (r.get("faction", "?"),
                     (r.get("player") or "")[:14], cells, sc if sc >= 0 else "-"))
    return "```\n" + "\n".join(lines) + "\n```"


def to_clipboard(text):
    try:
        subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "$input | Set-Clipboard"],
            input=text.encode("utf-8"), timeout=10, check=False)
        return True
    except Exception as e:
        print("  clipboard failed:", e)
        return False


def parse_body(raw):
    """TTS WebRequest.post form-encodes the body; accept that or raw JSON."""
    text = raw.decode("utf-8", "replace")
    if text.startswith("%"):
        text = urllib.parse.unquote(text)
    # a form-encoded lone string can also arrive as "payload=" style; strip key
    if text and text[0] not in "{[" and "=" in text.split("&")[0]:
        text = urllib.parse.unquote(text.split("=", 1)[1])
    return json.loads(text)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        try:
            payload = parse_body(raw)
        except Exception as e:
            print("bad payload:", e)
            self._ok()
            return
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        os.makedirs(EXPORTS, exist_ok=True)
        with open(os.path.join(EXPORTS, "latest.json"), "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=1)
        with open(os.path.join(EXPORTS, "feed.jsonl"), "a", encoding="utf-8") as f:
            f.write(json.dumps(payload) + "\n")
        kind = payload.get("type", "?")
        clipped = ""
        if kind == "export":
            with open(os.path.join(EXPORTS, "boxscore_%s.json" % stamp),
                      "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=1)
            if to_clipboard(box_text(payload)):
                clipped = "  -> box score copied to clipboard"
        print("[%s] %s  (%d rows)%s" % (stamp, kind, len(payload.get("rows", [])),
                                        clipped))
        to_discord(payload)
        self._ok()

    def _ok(self):
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


def main():
    socketserver.ThreadingTCPServer.daemon_threads = True
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler)
    print("Root Box Score listener on http://127.0.0.1:%d" % PORT)
    print("exports ->", EXPORTS)
    print("discord webhook:", "configured" if webhook_url() else
          "not set (create tools/discord_webhook.txt to enable)")
    srv.serve_forever()


if __name__ == "__main__":
    main()
