#main.py
from http.server import SimpleHTTPRequestHandler, HTTPServer

PORT = 80
handler = SimpleHTTPRequestHandler

httpd = HTTPServer(("", PORT), handler)
print(f"Serving on port {PORT}")
httpd.serve_forever()
