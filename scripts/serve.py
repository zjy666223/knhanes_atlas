"""Preview the exported files with the same path prefix as GitHub Pages."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import errno
from urllib.request import urlopen
import webbrowser

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "/knhanes_atlas"


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", PREFIX):
            self.send_response(302)
            self.send_header("Location", PREFIX + "/")
            self.end_headers()
            return
        if not self.path.startswith(PREFIX + "/"):
            self.send_error(404)
            return
        self.path = self.path[len(PREFIX):]
        super().do_GET()

    def do_HEAD(self):
        if not self.path.startswith(PREFIX + "/"):
            self.send_error(404)
            return
        self.path = self.path[len(PREFIX):]
        super().do_HEAD()


if __name__ == "__main__":
    address = "http://127.0.0.1:8848/knhanes_atlas/"
    try:
        server = ThreadingHTTPServer(("127.0.0.1", 8848), partial(Handler, directory=str(ROOT / "site")))
    except OSError as error:
        if error.errno != errno.EADDRINUSE:
            raise
        with urlopen(address, timeout=3) as response:
            existing = response.read().decode("utf-8")
        if "knhanesSiteRoot" not in existing:
            raise SystemExit("Port 8848 is occupied by another application.")
        print(address, flush=True)
        if "--open" in sys.argv:
            webbrowser.open(address)
        raise SystemExit(0)
    print("http://127.0.0.1:8848/knhanes_atlas/", flush=True)
    if "--open" in sys.argv:
        webbrowser.open("http://127.0.0.1:8848/knhanes_atlas/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
