# A greetd that speaks the howdy sequence, on a real unix socket, so the
# greeter QML + greetd-proxy + protocol can be driven end to end.
import json, os, socket, struct, sys, threading

path = sys.argv[1]
face_ok = sys.argv[2] == "ok"
password = "hunter2"

def read_framed(c):
    head = b""
    while len(head) < 4:
        b = c.recv(4 - len(head))
        if not b: return None
        head += b
    n = struct.unpack("=I", head)[0]
    body = b""
    while len(body) < n:
        b = c.recv(n - len(body))
        if not b: return None
        body += b
    return json.loads(body)

def write_framed(c, obj):
    payload = json.dumps(obj).encode()
    c.sendall(struct.pack("=I", len(payload)) + payload)

srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path); srv.listen(1)
print("READY", flush=True)

conn, _ = srv.accept()
stage = "idle"
log = []
while True:
    req = read_framed(conn)
    if req is None: break
    log.append(req)
    kind = req.get("type")
    if kind == "create_session":
        stage = "howdy"
        write_framed(conn, {"type": "auth_message", "auth_message_type": "info",
                            "auth_message": "Scanning face..."})
    elif kind == "post_auth_message_response":
        if stage == "howdy":
            if face_ok:
                stage = "done"
                write_framed(conn, {"type": "success"})
            else:
                stage = "rejected"
                write_framed(conn, {"type": "auth_message", "auth_message_type": "error",
                                    "auth_message": "Face not recognised"})
        elif stage == "rejected":
            stage = "secret"
            write_framed(conn, {"type": "auth_message", "auth_message_type": "secret",
                                "auth_message": "Password: "})
        elif stage == "secret":
            stage = "done"
            if req.get("response") == password:
                write_framed(conn, {"type": "success"})
            else:
                write_framed(conn, {"type": "error", "error_type": "auth_error",
                                    "description": "authentication failed"})
    elif kind in ("start_session", "cancel_session"):
        write_framed(conn, {"type": "success"})
        print("LOG " + json.dumps(log), flush=True)
        break
