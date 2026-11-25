#!/usr/bin/env python3
"""Talk to a running dedicated server's admin socket (AdminLink, 127.0.0.1 only).

Run on the server machine (or through ssh). Python standard library only.

  admin_cli.py status                      one status as JSON
  admin_cli.py watch                       status + log lines as they come (Ctrl-C stops)
  admin_cli.py config                      the settings file's values and the choices
  admin_cli.py set team_size=6 weather=fog scenarios=vidingsjo_koth,campus_koth
  admin_cli.py map vidingsjo_thunder_red   load that scenario now
  admin_cli.py end                         end the match (result, then the vote)
  admin_cli.py vote                        skip the result / close the vote now
  admin_cli.py kick 1234567 [reason...]    disconnect a player (peer id from status)
  admin_cli.py say Server restarts in 5 minutes
  admin_cli.py quit                        stop the server (systemd restarts it)
  admin_cli.py raw '{"cmd": "status"}'

Options: --port N (default 24681), --host H (default 127.0.0.1).
Exit code 1 when the server answers ok: false.
"""
import json
import socket
import sys

DEFAULT_PORT = 24681


class AdminClient:
    def __init__(self, host="127.0.0.1", port=DEFAULT_PORT, timeout=5.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.file = self.sock.makefile("rb")
        self._next_id = 1

    def close(self):
        self.sock.close()

    def send(self, msg):
        self.sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))

    def read(self):
        line = self.file.readline()
        if not line:
            raise ConnectionError("server closed the connection")
        return json.loads(line)

    def call(self, cmd, **args):
        """One request; pushed events that arrive before the reply are skipped."""
        rid = self._next_id
        self._next_id += 1
        self.send(dict(args, cmd=cmd, id=rid))
        while True:
            msg = self.read()
            if msg.get("id") == rid:
                return msg


def parse_value(text):
    try:
        return json.loads(text)
    except ValueError:
        return text


def main(argv):
    host, port = "127.0.0.1", DEFAULT_PORT
    args = []
    i = 0
    while i < len(argv):
        if argv[i] == "--port":
            port = int(argv[i + 1]); i += 2
        elif argv[i] == "--host":
            host = argv[i + 1]; i += 2
        else:
            args.append(argv[i]); i += 1
    if not args:
        print(__doc__)
        return 2
    cmd, rest = args[0], args[1:]
    try:
        c = AdminClient(host, port)
    except OSError as e:
        print(f"can't reach the server's admin port {host}:{port}: {e}", file=sys.stderr)
        return 3
    try:
        if cmd == "watch":
            c.sock.settimeout(None)
            c.send({"cmd": "subscribe", "id": 0})
            while True:
                print(json.dumps(c.read(), ensure_ascii=False), flush=True)
        if cmd == "status":
            r = c.call("status")
        elif cmd == "config":
            r = c.call("config_get")
        elif cmd == "set":
            values = {}
            for kv in rest:
                k, _, v = kv.partition("=")
                values[k] = v.split(",") if k == "scenarios" and v else parse_value(v)
            r = c.call("config_set", values=values)
        elif cmd == "map":
            r = c.call("change_map", scenario=rest[0])
        elif cmd == "end":
            r = c.call("end_match")
        elif cmd == "vote":
            r = c.call("close_vote")
        elif cmd == "kick":
            r = c.call("kick", peer=int(rest[0]), reason=" ".join(rest[1:]))
        elif cmd == "say":
            r = c.call("say", text=" ".join(rest))
        elif cmd == "quit":
            r = c.call("quit")
        elif cmd == "raw":
            msg = json.loads(rest[0])
            msg.setdefault("id", 0)
            c.send(msg)
            r = c.read()
            while r.get("id") != msg["id"]:
                r = c.read()
        else:
            print(f"unknown command {cmd}\n{__doc__}", file=sys.stderr)
            return 2
    except KeyboardInterrupt:
        return 0
    finally:
        c.close()
    print(json.dumps(r, indent=2, ensure_ascii=False))
    return 0 if r.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
