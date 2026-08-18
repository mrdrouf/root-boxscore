#!/usr/bin/env python3
"""Execute Lua in the running TTS instance and capture what comes back.

Channel in : TCP localhost:39999, messageID 3 (execute Lua in Global).
Channel out: WebRequest.post from Lua to our local HTTP server (the one path
             proven reliable in root_engine/tts/probe_channels.py), with
             log()/39998 capture as a bonus listener.

Usage: python tts_exec.py script.lua [timeout_seconds]
The Lua may call POST(string) - a helper is prepended that WebRequest.posts to us.
"""
import http.server
import json
import socket
import socketserver
import sys
import threading
import time

PORT = 8799
posts = []
listener_msgs = []

HELPER = """
local function POST(s)
  WebRequest.post("http://127.0.0.1:%d/", tostring(s), function() end)
end
""" % PORT


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n).decode("utf-8", "replace")
        posts.append(body)
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


def editor_listener(stop):
    """Capture TTS -> editor pushes on 39998 (print/log/error messages)."""
    try:
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", 39998))
        srv.listen(5)
        srv.settimeout(0.5)
    except OSError as e:
        listener_msgs.append({"listener_error": str(e)})
        return
    while not stop.is_set():
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        buf = b""
        conn.settimeout(0.5)
        try:
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
        except socket.timeout:
            pass
        conn.close()
        if buf:
            try:
                listener_msgs.append(json.loads(buf.decode("utf-8", "replace")))
            except Exception:
                listener_msgs.append({"raw": buf[:500].decode("utf-8", "replace")})
    srv.close()


def main():
    lua_path = sys.argv[1]
    timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0
    lua = HELPER + open(lua_path, encoding="utf-8").read()

    socketserver.ThreadingTCPServer.daemon_threads = True
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    httpd = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    stop = threading.Event()
    threading.Thread(target=editor_listener, args=(stop,), daemon=True).start()
    time.sleep(0.3)

    msg = json.dumps({"messageID": 3, "guid": "-1", "script": lua})
    s = socket.create_connection(("127.0.0.1", 39999), timeout=5)
    s.sendall(msg.encode("utf-8"))
    s.close()

    t0 = time.time()
    last_n = 0
    while time.time() - t0 < timeout:
        time.sleep(0.25)
        if posts and len(posts) == last_n and time.time() - t0 > 2.0:
            break  # got something and it stopped growing
        last_n = len(posts)

    stop.set()
    httpd.shutdown()
    print("== POSTS ==")
    for p in posts:
        print(p)
    print("== EDITOR MSGS ==")
    for m in listener_msgs[-10:]:
        s = json.dumps(m)
        print(s[:1000])


if __name__ == "__main__":
    main()
