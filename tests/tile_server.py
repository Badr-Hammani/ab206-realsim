"""Local stand-in for the HD imagery server, used by tests/map_tests.gd ([M11], [M12], [M14]).
Serves one small JPEG for any /tile.jpg?z/y/x request. GET /quit stops it (offline test).
Run: python3 tests/tile_server.py   (port 8765)"""
import base64, http.server, io, sys, threading

# 256x256 grey JPEG made once with Pillow if available, else a tiny built-in JPEG (Godot resizes it)
try:
    from PIL import Image
    b = io.BytesIO()
    Image.new("RGB", (256, 256), (120, 140, 110)).save(b, "JPEG", quality=80)
    JPG = b.getvalue()
except Exception:
    JPG = base64.b64decode(
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")
COUNT = [0]

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/quit"):
            self.send_response(200); self.end_headers(); self.wfile.write(b"bye")
            threading.Thread(target=self.server.shutdown).start()
            return
        if self.path.startswith("/count"):
            self.send_response(200); self.end_headers(); self.wfile.write(str(COUNT[0]).encode()); return
        COUNT[0] += 1
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(JPG)))
        self.end_headers()
        self.wfile.write(JPG)
    def log_message(self, *a):
        pass

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
s = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
s.serve_forever()
