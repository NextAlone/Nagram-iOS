"""Run the compiled provider checks against a loopback-only multipart test server."""
import email.parser
import email.policy
import http.server
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

audio = Path(sys.argv[2]).read_bytes()
failures = []


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        try:
            assert self.headers["Authorization"] == "Bearer fictional-test-key"
            message = email.parser.BytesParser(policy=email.policy.default).parsebytes(
                b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + body
            )
            parts = {part.get_param("name", header="Content-Disposition"): part for part in message.iter_parts()}
            assert parts["file"].get_filename() == "audio.m4a"
            assert parts["file"].get_content_type() == "audio/mp4"
            assert parts["file"].get_payload(decode=True) == audio
            assert parts["response_format"].get_payload(decode=True) == b"json"
            assert parts["prompt"].get_payload(decode=True).decode() == "Nagram 测试"
            if self.path == "/automatic":
                assert "languages[]" not in parts and "language" not in parts
                assert parts["model"].get_payload(decode=True) == b"whisper-1"
            else:
                assert "language" not in parts
                assert parts["languages[]"].get_payload(decode=True) == b"zh"
                assert parts["model"].get_payload(decode=True) == b"gpt-transcribe"
        except Exception as error:
            failures.append(f"{self.path}: {error!r}")
            self.send_error(400)
            return
        if self.path == "/slow":
            time.sleep(2)
        status = 200
        response = json.dumps({"text": " 识别成功 \n", "usage": {}}).encode()
        if self.path == "/quota":
            status, response = 429, json.dumps({"error": {"message": "Quota: fictional-test-key"}}).encode()
        elif self.path == "/empty":
            response = b'{"text":"  "}'
        elif self.path == "/invalid":
            response = b'{"wrong":"field"}'
        elif self.path == "/redirect":
            status = 302
        self.send_response(status)
        if status == 302:
            self.send_header("Location", "/must-not-follow")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        try:
            self.wfile.write(response)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        failures.append("Unexpected redirected GET")
        self.send_error(400)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    result = subprocess.run([sys.argv[1], f"http://127.0.0.1:{server.server_port}", sys.argv[2]], check=False)
finally:
    server.shutdown()
assert not failures, failures
sys.exit(result.returncode)
