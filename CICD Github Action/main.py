import http.server
import socketserver

PORT = 80  # Use 8000 if not running with sudo

Handler = http.server.SimpleHTTPRequestHandler

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Serving HTTP on port {PORT}...")
    httpd.serve_forever()
