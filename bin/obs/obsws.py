#!/usr/bin/env python3
"""Talk to OBS over its built-in obs-websocket (protocol v5), stdlib only.

usage: obsws.py enable                      turn the server on, keeping or making a password
       obsws.py <RequestType> [json] [field] send one request, print its responseData
                                             (or that one field of it)
"""
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import sys

CONF = os.path.expanduser(
    "~/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json"
)


def enable():
    try:
        with open(CONF) as f:
            c = json.load(f)
    except FileNotFoundError:
        c = {}
    c.update(server_enabled=True, auth_required=True, alerts_enabled=False, first_load=False)
    c.setdefault("server_port", 4455)
    if not c.get("server_password"):
        c["server_password"] = secrets.token_urlsafe(24)
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF, "w") as f:
        json.dump(c, f, indent=2)


def send(s, obj):
    data = json.dumps(obj).encode()
    n, mask = len(data), os.urandom(4)
    if n < 126:
        head = struct.pack(">BB", 0x81, 0x80 | n)
    elif n < 65536:
        head = struct.pack(">BBH", 0x81, 0x80 | 126, n)
    else:
        head = struct.pack(">BBQ", 0x81, 0x80 | 127, n)
    s.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            sys.exit("obsws: OBS closed the connection")
        buf += chunk
    return buf


def recv(s):
    while True:
        b0, b1 = exact(s, 2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", exact(s, 2))[0]
        elif n == 127:
            n = struct.unpack(">Q", exact(s, 8))[0]
        payload, op = exact(s, n), b0 & 0x0F
        if op == 8:
            sys.exit("obsws: OBS refused: " + payload[2:].decode(errors="replace"))
        if op == 1:
            return json.loads(payload)


def request(rtype, data):
    with open(CONF) as f:
        c = json.load(f)
    port = c.get("server_port", 4455)
    s = socket.create_connection(("127.0.0.1", port), timeout=15)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(
        f"GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
        "Sec-WebSocket-Protocol: obswebsocket.json\r\n\r\n".encode()
    )
    head = b""
    while not head.endswith(b"\r\n\r\n"):  # byte by byte, so no frame gets eaten
        head += exact(s, 1)
    if b" 101 " not in head.split(b"\r\n")[0]:
        sys.exit("obsws: no websocket upgrade: " + head.split(b"\r\n")[0].decode())

    hello = recv(s)["d"]
    ident = {"rpcVersion": 1, "eventSubscriptions": 0}
    if "authentication" in hello:
        a = hello["authentication"]
        secret = base64.b64encode(hashlib.sha256((c["server_password"] + a["salt"]).encode()).digest())
        ident["authentication"] = base64.b64encode(
            hashlib.sha256(secret + a["challenge"].encode()).digest()
        ).decode()
    send(s, {"op": 1, "d": ident})
    recv(s)  # Identified

    send(s, {"op": 6, "d": {"requestType": rtype, "requestId": "1", "requestData": data}})
    while True:
        msg = recv(s)
        if msg["op"] == 7:
            break
    st = msg["d"]["requestStatus"]
    if not st["result"]:
        sys.exit(f"obsws: {rtype} failed ({st['code']}): {st.get('comment', '')}")
    return msg["d"].get("responseData", {})


if __name__ == "__main__":
    if sys.argv[1:] == ["enable"]:
        enable()
    else:
        out = request(sys.argv[1], json.loads(sys.argv[2]) if len(sys.argv) > 2 else {})
        print(out.get(sys.argv[3], "") if len(sys.argv) > 3 else json.dumps(out))
