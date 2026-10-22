"""Run the real Godot HTTP adapters against deterministic local protocol fixtures."""
import argparse
import base64
import http.server
import json
from pathlib import Path
import os
import struct
import subprocess
import tempfile
import threading
import time
import urllib.parse
import zlib


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress((b"\x00" + b"\xff\x30\x20\xff" * 2) * 2)) + chunk(b"IEND", b"")


def glb():
    binary = struct.pack("<9f3H", -1, 0, 0, 1, 0, 0, 0, 2, 0, 0, 1, 2) + b"\x00\x00"
    document = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binary)}], "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 6}], "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, 0, 0], "max": [1, 2, 0]}, {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}], "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}], "nodes": [{"mesh": 0}], "scenes": [{"nodes": [0]}], "scene": 0}
    encoded = json.dumps(document).encode()
    encoded += b" " * (-len(encoded) % 4)
    return b"glTF" + struct.pack("<II", 2, 12 + 8 + len(encoded) + 8 + len(binary)) + struct.pack("<II", len(encoded), 0x4e4f534a) + encoded + struct.pack("<II", len(binary), 0x004e4942) + binary


class Fixtures(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, value, status=200, content_type="application/json", headers=None):
        body = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        location = urllib.parse.urlparse(self.path)
        if location.path == "/store/search/query/":
            valid = urllib.parse.parse_qs(location.query).get("query") == ["fixture"]
            self.reply({"count": 1, "hits": [{"asset": {"slug": "fixture-addon", "name": "Fixture addon", "publisher": {"name": "Fixture publisher", "slug": "fixture"}, "license_type": "MIT"}}]} if valid else {"error": "query missing"}, 200 if valid else 400)
            return
        if location.path == "/store/assets/fixture-addon":
            self.reply({"slug": "fixture-addon", "name": "Fixture addon", "publisher": {"name": "Fixture publisher", "slug": "fixture"}, "license_type": "MIT"})
            return
        if location.path == "/store/releases/fixture/fixture-addon/":
            self.reply([{"version": "1.0", "stable": True, "min_godot_version": "4.0", "max_godot_version": "4.99", "download_url": f"http://127.0.0.1:{self.server.server_port}/store/redirect"}, {"version": "2.0", "stable": True, "min_godot_version": "9.0"}])
            return
        if location.path in ["/store/redirect", "/store/loop"]:
            self.reply(b"", 302, headers={"Location": "/artifact/image.png" if location.path.endswith("redirect") else "/store/loop"})
            return
        if location.path.startswith(("/meshy/", "/tripo/", "/openai_image/")):
            if self.headers.get("Authorization") != "Bearer generation-fixture-key":
                self.reply({"error": "missing fixture authorization"}, 401)
                return
            if location.path.endswith("/balance"):
                self.reply({"code": 0, "data": {"balance": 100}} if location.path.startswith("/tripo/") else {"balance": 100})
            elif location.path.endswith("/models"):
                self.reply({"data": [{"id": "gpt-image-2.5-flare"}, {"id": "fixture-code"}]})
            else:
                task = location.path.rsplit("/", 1)[-1]
                output_url = f"http://127.0.0.1:{self.server.server_port}/artifact/" + ("image.png" if task == "image-task" else "model.glb")
                if task == "foreign-task": output_url = "https://attacker.example/model.glb"
                status = "failed" if task == "failed-task" else "success"
                data = {"status": status, "progress": 100, "output": {"model_url": output_url, "generated_image_url": output_url}, "credits_consumed": 4}
                self.reply({"code": 0, "data": data} if location.path.startswith("/tripo/") else {"status": "FAILED" if status == "failed" else "SUCCEEDED", "progress": 100, "model_urls": {"glb": output_url}})
            return
        if location.path.startswith("/artifact/"):
            if self.headers.get("Authorization"):
                self.reply({"error": "credentials sent to CDN"}, 403)
            else:
                mesh = location.path.endswith(".glb")
                self.reply(glb() if mesh else png(), content_type="model/gltf-binary" if mesh else "image/png")
        elif location.path == "/repos/fixture/project":
            self.reply({"full_name": "fixture/project", "default_branch": "main", "private": False})
        elif location.path == "/repos/fixture/project/contents/script.gd":
            self.reply({"type": "file", "path": "script.gd", "size": 13, "sha": "fixture-sha", "encoding": "base64", "content": base64.b64encode(b"extends Node\n").decode()})
        elif location.path in ["/repos/fixture/project/issues", "/repos/fixture/project/pulls", "/repos/fixture/project/branches"]:
            self.reply([{"name": "main", "number": 3, "title": "Fixture issue", "state": "open", "body": "not copied into list"}])
        elif location.path.endswith("/models"):
            self.reply({"data": [{"id": "fixture-code", "name": "Fixture coding model", "context_window": 8192, "effort": {"supported_levels": ["high", "max"]}}]})
        elif location.path == "/object_info":
            self.reply({"FixturePrompt": {}, "SaveImage": {}, "SaveGLB": {}})
        elif location.path.startswith("/history/"):
            self.reply({"fixture-job": {"status": {"status_str": "success"}, "outputs": {"1": {"images": [{"filename": "image.png", "type": "output"}], "3d": [{"filename": "mesh.glb", "type": "output"}]}}}})
        elif location.path == "/view":
            mesh = urllib.parse.parse_qs(location.query).get("filename") == ["mesh.glb"]
            self.reply(glb() if mesh else png(), content_type="model/gltf-binary" if mesh else "image/png")
        elif location.path == "/truncated.glb":
            self.reply(glb()[:-4], content_type="model/gltf-binary")
        else:
            self.reply({"error": "not found"}, 404)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/tripo/files":
            valid = self.headers.get("Authorization") == "Bearer generation-fixture-key" and b'name="file"' in raw and png() in raw
            self.reply({"code": 0, "data": {"file_token": "file_fixture"}} if valid else {"code": 1004, "message": "invalid multipart upload"})
            return
        payload = json.loads(raw or b"{}")
        location = urllib.parse.urlparse(self.path)
        if location.path.startswith(("/meshy/", "/tripo/", "/openai_image/")):
            if self.headers.get("Authorization") != "Bearer generation-fixture-key":
                self.reply({"error": "missing fixture authorization"}, 401)
                return
            task = "failed-task" if payload.get("prompt") == "fail" else ("foreign-task" if payload.get("prompt") == "foreign" else "mesh-task")
            if location.path.startswith("/openai_image/"):
                valid = payload.get("output_format") == "png" and "response_format" not in payload and payload.get("n") == 1
                image = b"invalid" if payload.get("prompt") == "invalid" else png()
                self.reply({"data": [{"b64_json": base64.b64encode(image).decode()}]} if valid else {"error": "wrong image schema"}, 200 if valid else 400)
            elif location.path.startswith("/meshy/"):
                valid = payload.get("target_formats") == ["glb"] and (payload.get("mode") == "preview" if "text-to-3d" in location.path else payload.get("image_url", "").startswith("data:image/png;base64,"))
                self.reply({"result": task} if valid else {"error": "wrong mesh schema"}, 200 if valid else 400)
            else:
                if location.path.endswith("text-to-image"): task = "image-task"
                valid = payload.get("input") == "file_fixture" if location.path.endswith("image-to-model") else bool(payload.get("prompt"))
                self.reply({"code": 0, "data": {"task_id": task}} if valid else {"code": 1004, "message": "wrong tripo schema"})
        elif location.path == "/repos/fixture/project/issues":
            self.reply({"number": 4, "title": payload["title"], "state": "open", "html_url": "https://github.com/fixture/project/issues/4"}, 201)
        elif location.path == "/mcp":
            method = payload.get("method")
            if method == "notifications/initialized":
                self.reply(b"", 202)
                return
            if method == "initialize":
                result = {"protocolVersion": "2025-11-25", "capabilities": {"tools": {}}, "serverInfo": {"name": "fixture", "version": "1"}}
            elif method == "tools/list":
                name = "second" if payload.get("params", {}).get("cursor") else "first"
                result = {"tools": [{"name": name, "description": "Fixture", "inputSchema": {"type": "object", "properties": {}}, "annotations": {"readOnlyHint": True}}]}
                if name == "first": result["nextCursor"] = "next-page"
            else:
                failed = payload.get("params", {}).get("arguments", {}).get("fail", False)
                result = {"content": [{"type": "text", "text": "fixture tool execution failed" if failed else "real fixture tool result"}], "isError": failed}
            self.reply({"jsonrpc": "2.0", "id": payload["id"], "result": result}, headers={"Mcp-Session-Id": "fixture-session"})
        elif location.path == "/prompt":
            self.reply({"prompt_id": "fixture-job", "number": 0})
        elif location.path.endswith("/chat/completions"):
            has_result = any(message.get("role") == "tool" for message in payload.get("messages", []))
            if location.path.startswith("/json/"):
                message = {"role": "assistant", "content": "JSON verified"} if has_result else {"role": "assistant", "content": None, "tool_calls": [{"id": "json-call-a", "function": {"name": "godot_project", "arguments": "{}"}}, {"id": "json-call-b", "function": {"name": "godot_files", "arguments": "{}"}}]}
                self.reply({"choices": [{"message": message, "finish_reason": "stop" if has_result else "tool_calls"}]})
                return
            if has_result:
                events = [{"choices": [{"delta": {"content": "Verificat: română 🐦"}, "finish_reason": None}]}, {"choices": [{"delta": {}, "finish_reason": "stop"}]}]
            else:
                events = [{"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "fixture-call", "function": {"name": "godot_project", "arguments": "{"}}]}, "finish_reason": None}]}, {"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "}"}}]}, "finish_reason": "tool_calls"}]}]
            if location.path.startswith("/incomplete/"): events = events[:1]
            if location.path.startswith("/slow/"): time.sleep(0.3)
            self.sse(events)
        elif location.path == "/v1/responses":
            self.sse([{"type": "response.output_text.delta", "delta": "Responses verified"}, {"type": "response.completed", "response": {"output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Responses verified"}]}]}}])
        elif location.path == "/v1/messages":
            self.sse([{"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}, {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Anthropic verified"}}, {"type": "content_block_stop", "index": 0}, {"type": "message_stop"}])
        elif ":streamGenerateContent" in location.path:
            self.sse([{"candidates": [{"content": {"parts": [{"text": "Gemini verified"}]}, "finishReason": "STOP"}]}])
        else:
            self.reply({"error": "not found"}, 404)

    def sse(self, events):
        data = "".join("data: " + json.dumps(event, ensure_ascii=False) + "\n\n" for event in events) + "data: [DONE]\n\n"
        self.reply(data.encode(), content_type="text/event-stream")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--proot", action="store_true")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixtures)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    command = [args.godot, "--headless", "--path", str(source / "tests/fixture"), "--script", str(source / "tests/test_runtime.gd"), "--", "--source=" + str(source), f"--mock-url=http://127.0.0.1:{server.server_port}"]
    if args.proot:
        command = ["proot-distro", "login", "debian", "--shared-home", "--"] + command
    try:
        with tempfile.TemporaryDirectory(prefix="godot-ai-qa-") as scratch:
            env = dict(os.environ, XDG_CONFIG_HOME=scratch, XDG_DATA_HOME=scratch, XDG_CACHE_HOME=scratch)
            return subprocess.run(command, env=env, check=False).returncode
    finally:
        server.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
