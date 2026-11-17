# Test client for the phone server: WSS (self-signed) as cyclic, HTTP POST as collective.
import ssl, socket, base64, os, time, struct, threading, urllib.request, math, sys
host = "127.0.0.1"
def ws_frame(text):
    p = text.encode(); mask = os.urandom(4)
    hdr = bytes([0x81]) + (bytes([0x80 | len(p)]) if len(p) < 126 else bytes([0x80 | 126]) + struct.pack(">H", len(p)))
    return hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(p))
def run_ws():
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    s = ctx.wrap_socket(socket.create_connection((host, 8206)), server_hostname=host)
    # page first
    s.sendall(b"GET / HTTP/1.1\r\nHost: x\r\n\r\n"); time.sleep(0.5); page = s.recv(100000)
    print("PAGE", page[:60], len(page))
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
    print("HANDSHAKE", s.recv(4096).split(b"\r\n")[0])
    s.settimeout(0.01)
    s.sendall(ws_frame("h,cyclic"))
    t0 = time.time(); got = []
    while time.time() - t0 < 6:
        t = time.time() - t0
        beta = 0.0 if t < 1 else -10.0 * min((t - 1) / 2, 1)   # top edge away 10 deg (beta negative)
        gamma = 0.0 if t < 3 else 5.0
        s.sendall(ws_frame("o,cyclic,%.2f,%.2f,0" % (beta, gamma)))
        try:
            d = s.recv(4096); got.append(d)
        except Exception: pass
        time.sleep(1 / 60)
    print("WS RX sample", got[-1][:60] if got else None, "frames", len(got))
    s.sendall(bytes([0x88, 0x80]) + os.urandom(4)); s.close()
def run_post():
    t0 = time.time(); n = 0; last = ""
    while time.time() - t0 < 6:
        t = time.time() - t0
        beta = 0.0 if t < 1.5 else 12.0 * min((t - 1.5) / 2, 1)   # raise front edge 12 deg
        r = urllib.request.urlopen(urllib.request.Request("http://%s:8207/m" % host, data=("o,collective,%.2f,0,0" % beta).encode(), method="POST"))
        last = r.read(); n += 1
    print("POST n", n, "last reply", last)
th = [threading.Thread(target=run_ws), threading.Thread(target=run_post)]
[x.start() for x in th]; [x.join() for x in th]
