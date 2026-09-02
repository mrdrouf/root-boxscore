#!/usr/bin/env python3
"""Optional clipboard helper for the Root Box Score COPY button.

TTS scripts cannot touch the OS clipboard, so the COPY button silently
POSTs the JSON record to http://127.0.0.1:8790/clip - if this helper is
running, the record lands on the clipboard by itself; if not, the button's
selectable box (Ctrl+A / Ctrl+C) still works. Localhost only, nothing else.

Run it via "Start Clipboard Helper.cmd" (or install it to autostart with
"Install Clipboard Helper Autostart.cmd").
"""
import ctypes
import http.server
import socketserver
import time

PORT = 8790


def set_clipboard(text):
    CF_UNICODETEXT, GMEM_MOVEABLE = 13, 2
    k32, u32 = ctypes.windll.kernel32, ctypes.windll.user32
    # 64-bit safety: without explicit signatures ctypes truncates the
    # HGLOBAL handle and pointers to 32 bits and the copy dies silently
    k32.GlobalAlloc.restype = ctypes.c_void_p
    k32.GlobalAlloc.argtypes = [ctypes.c_uint, ctypes.c_size_t]
    k32.GlobalLock.restype = ctypes.c_void_p
    k32.GlobalLock.argtypes = [ctypes.c_void_p]
    k32.GlobalUnlock.argtypes = [ctypes.c_void_p]
    k32.GlobalFree.argtypes = [ctypes.c_void_p]
    u32.OpenClipboard.argtypes = [ctypes.c_void_p]
    u32.SetClipboardData.restype = ctypes.c_void_p
    u32.SetClipboardData.argtypes = [ctypes.c_uint, ctypes.c_void_p]
    data = text.encode("utf-16-le") + b"\x00\x00"
    h = k32.GlobalAlloc(GMEM_MOVEABLE, len(data))
    p = k32.GlobalLock(h)
    ctypes.memmove(p, data, len(data))
    k32.GlobalUnlock(h)
    for _ in range(10):
        if u32.OpenClipboard(0):
            u32.EmptyClipboard()
            u32.SetClipboardData(CF_UNICODETEXT, h)
            u32.CloseClipboard()
            return True
        time.sleep(0.05)
    k32.GlobalFree(h)
    return False


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self, code, body):
        body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        text = self.rfile.read(n).decode("utf-8", "replace")
        ok = set_clipboard(text)
        self._reply(200 if ok else 500, "ok" if ok else "clipboard busy")

    def do_GET(self):
        self._reply(200, "clipboard helper alive")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    socketserver.ThreadingTCPServer.daemon_threads = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler) as srv:
        srv.serve_forever()
