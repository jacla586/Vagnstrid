#!/usr/bin/env python3
"""Vagnstrid server panel: a web page on the LAN to watch and run the dedicated server.

Runs beside the game server on the same machine (its own systemd user service,
vagnstrid-panel.service) and talks to it through the server's admin socket
(AdminLink, 127.0.0.1). It also reads the server's log (server_log.jsonl) for the
statistics, follows its console through journalctl, and starts/stops/restarts the
game server's systemd unit, so it works when the game is down too.

  python3 panel.py --log-dir ~/vagnstrid-log [--port 8080] [--admin-port 24681]
                   [--unit vagnstrid-server] [--console-log FILE] [--listen 0.0.0.0]

Access: only from private addresses (LAN, this machine; --allow to change), and only
with the token in <log dir>/panel_token.txt (made on first start, printed once). Python
standard library only.
"""
import argparse
import hmac
import ipaddress
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stats  # noqa: E402

COOKIE = "vagnstrid_panel"
DEFAULT_ALLOW = "127.0.0.0/8,::1/128,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fe80::/10,100.64.0.0/10"
# Admin commands the page may send (status/config have their own routes).
COMMANDS = {"change_map", "end_match", "close_vote", "kick", "say", "quit"}
SERVICE_ACTIONS = {"start", "stop", "restart"}

ARGS = None
TOKEN = ""
NETS = []


# --- Admin socket ----------------------------------------------------------------------

def admin_call(msg, timeout=3.0):
    """One request to the game server's AdminLink; None when it isn't running."""
    try:
        with socket.create_connection(("127.0.0.1", ARGS.admin_port), timeout=timeout) as s:
            msg = dict(msg, id=1)
            s.sendall((json.dumps(msg) + "\n").encode())
            f = s.makefile("rb")
            while True:
                line = f.readline()
                if not line:
                    return None
                reply = json.loads(line)
                if reply.get("id") == 1:
                    return reply
    except (OSError, ValueError):
        return None


# --- systemd / journal -----------------------------------------------------------------

def systemctl(*args):
    if not shutil.which("systemctl"):
        return 127, "systemctl not found"
    p = subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True, timeout=20)
    return p.returncode, (p.stdout + p.stderr).strip()


def service_state():
    code, out = systemctl("show", ARGS.unit, "--property=ActiveState,SubState,ActiveEnterTimestamp,NRestarts,MainPID")
    if code != 0:
        return {"available": False, "error": out}
    info = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
    return {"available": True, "unit": ARGS.unit, "active": info.get("ActiveState"), "sub": info.get("SubState"),
            "since": info.get("ActiveEnterTimestamp"), "restarts": info.get("NRestarts"),
            "pid": info.get("MainPID")}


def console_command(lines):
    if ARGS.console_log:
        return ["tail", "-n", str(lines), "-F", ARGS.console_log]
    if shutil.which("journalctl"):
        return ["journalctl", "--user", "-u", ARGS.unit, "-f", "-n", str(lines), "-o", "short-iso", "--no-pager"]
    return None


# --- Stats cache (the log is re-read only when it changed) ---------------------------------

_stats_lock = threading.Lock()
_stats_cache = {"mtime": None, "size": None, "events": []}


def log_path():
    return os.path.join(ARGS.log_dir, "server_log.jsonl")


def events():
    path = log_path()
    try:
        st = os.stat(path)
        sig = (st.st_mtime, st.st_size)
    except FileNotFoundError:
        return []
    with _stats_lock:
        if (_stats_cache["mtime"], _stats_cache["size"]) != sig:
            _stats_cache["events"] = stats.read_events(path)
            _stats_cache["mtime"], _stats_cache["size"] = sig
        return _stats_cache["events"]


def tail_log(limit):
    out = []
    for e in events()[-limit:]:
        out.append({k: v for k, v in e.items() if k != "_t"})
    return out


# --- HTTP ----------------------------------------------------------------------------

# The game's menu look (MenuTheme): dark see-through field, warm text, orange button.
LOGIN_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Vagnstrid server</title>
<style>:root{color-scheme:dark}*{box-sizing:border-box}html{background:#141214}
body{font:15px system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;color:#ede8db;
background:linear-gradient(90deg,rgba(5,5,8,.92),rgba(5,5,8,.7)),url("/bg.jpg") center/cover fixed no-repeat,#141214}
form{display:grid;gap:12px;width:min(340px,90vw);padding:24px;background:rgba(15,15,18,.72);
border:1px solid rgba(255,255,255,.14);border-radius:4px;backdrop-filter:blur(6px)}
h1{margin:0 0 4px;font-size:18px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;padding-bottom:6px;
position:relative}h1::after{content:"";position:absolute;left:0;bottom:0;width:44px;height:3px;background:#db8c38}
label{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:#b3ad9e;display:grid;gap:4px}
input{font:inherit;font-size:15px;padding:8px 10px;border-radius:3px;border:1px solid rgba(255,255,255,.14);
background:rgba(15,15,18,.72);color:#ede8db}input:focus{outline:1px solid #db8c38}
button{font:inherit;font-weight:700;letter-spacing:.06em;text-transform:uppercase;padding:9px;border:0;border-radius:3px;
background:#db8c38;color:#140f0a;cursor:pointer}button:hover{background:#f2a34d}
p{color:#ef6a64;margin:0}small{color:#b3ad9e}</style></head><body><form method="post" action="/login">
<h1>Vagnstrid server</h1>
<label>Token<input name="token" type="password" autofocus required></label>
%ERR%<button>Sign in</button><small>The token is in panel_token.txt in the server's log folder.</small>
</form></body></html>"""

# The main menu's picture as the page backdrop, when the game's files are beside the panel.
BACKGROUND = os.path.normpath(os.path.join(HERE, "..", "..", "..", "assets", "ui", "menu_background.jpg"))


class Handler(BaseHTTPRequestHandler):
    server_version = "VagnstridPanel/1"

    def log_message(self, fmt, *args):
        if ARGS.verbose:
            sys.stderr.write("panel: %s %s\n" % (self.address_string(), fmt % args))

    # --- access ---
    def _allowed_ip(self):
        try:
            ip = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            return False
        if ip.version == 6 and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        return any(ip in n for n in NETS)

    def _token_ok(self):
        if ARGS.trust_localhost and ipaddress.ip_address(self.client_address[0]).is_loopback:
            return True
        given = self.headers.get("X-Token", "")
        for part in self.headers.get("Cookie", "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == COOKIE:
                given = v
        return bool(given) and hmac.compare_digest(given.encode(), TOKEN.encode())

    def _gate(self, page=False):
        if not self._allowed_ip():
            self._send(HTTPStatus.FORBIDDEN, b"not from the LAN\n", "text/plain")
            return False
        if not self._token_ok():
            if page:
                self.send_response(HTTPStatus.SEE_OTHER)
                self.send_header("Location", "/login")
                self.end_headers()
            else:
                self._json({"ok": False, "error": "sign in"}, HTTPStatus.UNAUTHORIZED)
            return False
        return True

    # --- replies ---
    def _send(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=HTTPStatus.OK):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode(), "application/json; charset=utf-8")

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(min(n, 1 << 20)) if n > 0 else b""

    def _sse_start(self):
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

    def _sse(self, event, data):
        self.wfile.write(("event: %s\ndata: %s\n\n" % (event, json.dumps(data, ensure_ascii=False))).encode())
        self.wfile.flush()

    # --- routes ---
    def do_GET(self):
        url = urlparse(self.path)
        q = parse_qs(url.query)
        if url.path == "/login":
            if not self._allowed_ip():
                return self._send(HTTPStatus.FORBIDDEN, b"not from the LAN\n", "text/plain")
            return self._send(HTTPStatus.OK, LOGIN_PAGE.replace("%ERR%", "").encode(), "text/html; charset=utf-8")
        if url.path == "/bg.jpg":   # no token needed: the login page shows it too
            if not self._allowed_ip():
                return self._send(HTTPStatus.FORBIDDEN, b"not from the LAN\n", "text/plain")
            try:
                with open(BACKGROUND, "rb") as f:
                    return self._send(HTTPStatus.OK, f.read(), "image/jpeg", {"Cache-Control": "max-age=86400"})
            except OSError:
                return self._send(HTTPStatus.NOT_FOUND, b"", "image/jpeg")
        if url.path in ("/", "/index.html"):
            if not self._gate(page=True):
                return
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                return self._send(HTTPStatus.OK, f.read(), "text/html; charset=utf-8")
        if not self._gate():
            return
        if url.path == "/api/status":
            r = admin_call({"cmd": "status"})
            return self._json(r if r else {"ok": False, "offline": True})
        if url.path == "/api/config":
            r = admin_call({"cmd": "config_get"})
            return self._json(r if r else {"ok": False, "offline": True})
        if url.path == "/api/service":
            return self._json(dict(service_state(), ok=True))
        if url.path == "/api/log":
            limit = max(1, min(2000, int((q.get("limit") or ["300"])[0])))
            return self._json({"ok": True, "events": tail_log(limit)})
        if url.path == "/api/stats":
            try:
                since = stats.parse_time((q.get("since") or [""])[0])
                until = stats.parse_time((q.get("until") or [""])[0])
            except ValueError:
                return self._json({"ok": False, "error": "bad time"}, HTTPStatus.BAD_REQUEST)
            return self._json(stats.compute(events(), since, until))
        if url.path == "/api/stream":
            return self._stream()
        if url.path == "/api/console":
            return self._console()
        self._json({"ok": False, "error": "not found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self):
        url = urlparse(self.path)
        if url.path == "/login":
            if not self._allowed_ip():
                return self._send(HTTPStatus.FORBIDDEN, b"not from the LAN\n", "text/plain")
            token = (parse_qs(self._body().decode(errors="replace")).get("token") or [""])[0].strip()
            if token and hmac.compare_digest(token.encode(), TOKEN.encode()):
                self.send_response(HTTPStatus.SEE_OTHER)
                self.send_header("Set-Cookie", "%s=%s; HttpOnly; SameSite=Strict; Path=/; Max-Age=31536000" % (COOKIE, TOKEN))
                self.send_header("Location", "/")
                self.end_headers()
                return
            time.sleep(1.0)   # slows guessing
            page = LOGIN_PAGE.replace("%ERR%", "<p>Wrong token.</p>")
            return self._send(HTTPStatus.UNAUTHORIZED, page.encode(), "text/html; charset=utf-8")
        if not self._gate():
            return
        if self.headers.get("X-Requested-With") != "panel":   # no plain cross-site form posts
            return self._json({"ok": False, "error": "missing header"}, HTTPStatus.FORBIDDEN)
        try:
            body = json.loads(self._body() or b"{}")
        except ValueError:
            return self._json({"ok": False, "error": "bad JSON"}, HTTPStatus.BAD_REQUEST)
        if url.path == "/api/cmd":
            if body.get("cmd") not in COMMANDS:
                return self._json({"ok": False, "error": "unknown command"}, HTTPStatus.BAD_REQUEST)
            r = admin_call(body)
            return self._json(r if r else {"ok": False, "error": "game server not running"})
        if url.path == "/api/config":
            r = admin_call({"cmd": "config_set", "values": body.get("values") or {}})
            return self._json(r if r else {"ok": False, "error": "game server not running"})
        if url.path == "/api/service":
            action = body.get("action")
            if action not in SERVICE_ACTIONS:
                return self._json({"ok": False, "error": "unknown action"}, HTTPStatus.BAD_REQUEST)
            code, out = systemctl(action, ARGS.unit)
            return self._json({"ok": code == 0, "output": out, "state": service_state()})
        self._json({"ok": False, "error": "not found"}, HTTPStatus.NOT_FOUND)

    # --- streams ---
    def _stream(self):
        """Server status every second and log lines as they happen (AdminLink subscribe)."""
        self._sse_start()
        try:
            while True:
                try:
                    with socket.create_connection(("127.0.0.1", ARGS.admin_port), timeout=5) as s:
                        s.sendall(b'{"cmd":"subscribe","id":0}\n')
                        s.settimeout(10)
                        f = s.makefile("rb")
                        while True:
                            line = f.readline()
                            if not line:
                                break
                            msg = json.loads(line)
                            if msg.get("ev") == "log":
                                self._sse("log", msg["event"])
                            elif "phase" in msg:
                                self._sse("status", msg)
                except (OSError, ValueError):
                    pass
                self._sse("offline", {"service": service_state()})
                time.sleep(3)
        except (BrokenPipeError, ConnectionResetError):
            return

    def _console(self):
        """The game server's console output (journalctl -f, or --console-log)."""
        cmd = console_command(300)
        self._sse_start()
        if cmd is None:
            self._sse("line", "no journalctl here: start the panel with --console-log FILE")
            return
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        try:
            for line in p.stdout:
                self._sse("line", line.rstrip("\n"))
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            p.kill()


def load_token():
    path = os.path.join(ARGS.log_dir, "panel_token.txt")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return f.read().strip(), path, False
    token = secrets.token_urlsafe(18)
    os.makedirs(ARGS.log_dir, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(token + "\n")
    return token, path, True


def main():
    global ARGS, TOKEN, NETS
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--log-dir", required=True, help="the game server's --log-dir (server_log.jsonl, server.cfg)")
    ap.add_argument("--listen", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--admin-port", type=int, default=24681)
    ap.add_argument("--unit", default="vagnstrid-server", help="the game server's systemd user unit")
    ap.add_argument("--console-log", default="", help="follow this file instead of journalctl")
    ap.add_argument("--allow", default=DEFAULT_ALLOW, help="comma-separated networks allowed in")
    ap.add_argument("--trust-localhost", action="store_true",
                    help="no token for requests from this machine (an ssh tunnel, tests)")
    ap.add_argument("--verbose", action="store_true")
    ARGS = ap.parse_args()
    ARGS.log_dir = os.path.expanduser(ARGS.log_dir)
    NETS = [ipaddress.ip_network(n.strip()) for n in ARGS.allow.split(",") if n.strip()]
    TOKEN, path, new = load_token()
    if new:
        print("panel: new token %s (saved in %s)" % (TOKEN, path), flush=True)
    family = socket.AF_INET6 if ":" in ARGS.listen else socket.AF_INET
    ThreadingHTTPServer.address_family = family
    ThreadingHTTPServer.daemon_threads = True
    httpd = ThreadingHTTPServer((ARGS.listen, ARGS.port), Handler)
    print("panel: http://%s:%d/ (log %s, admin port %d, unit %s)" % (
        ARGS.listen, ARGS.port, log_path(), ARGS.admin_port, ARGS.unit), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
