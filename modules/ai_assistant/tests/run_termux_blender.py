"""Run real Blender integration in isolated folders, through the Godot client.

Requires existing Termux Python/PRoot/Blender and a Linux Godot ARM64 executable.
Does not install packages, modify existing containers or exercise Android Intents.
"""
import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

from test_termux_blender import worker, ROOT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", default=".ai-qa/blender-connector")
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="godot-blender-e2e-") as scratch:
        root = Path(scratch)
        backend = worker.Backend(root / "termux")
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), worker.Handler)
        server.daemon_threads = True
        server.backend, server.token = backend, "b" * 64
        threading.Thread(target=server.serve_forever, daemon=True).start()
        project = root / "project"
        project.mkdir()
        (project / "project.godot").write_text('[application]\nconfig/name="Blender Connector QA"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        report = output / "report.json"
        command = ["proot-distro", "login", "debian", "--shared-home", "--", "env",
                   "XDG_DATA_HOME=" + str(root / "data"), "XDG_CONFIG_HOME=" + str(root / "config"),
                   args.godot, "--headless", "--path", str(project), "--script",
                   str(ROOT / "modules/ai_assistant/tests/test_termux_blender.gd"), "--",
                   "--source=" + str(ROOT / "modules/ai_assistant"),
                   f"--url=http://127.0.0.1:{server.server_port}", "--report=" + str(report)]
        try:
            with (output / "godot.log").open("w") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
            jobs = [worker.read_json(p) for p in (backend.root / "jobs").glob("*/state.json")]
            for path in (backend.root / "jobs").glob("*/activity.log"):
                (output / (path.parent.name + ".log")).write_bytes(path.read_bytes())
            (output / "jobs.json").write_text(json.dumps(jobs, indent=2))
            print(report.read_text() if report.exists() else (output / "godot.log").read_text())
            return result.returncode
        finally:
            if backend.active:
                backend.cancel(backend.active)
                for _ in range(50):
                    if backend.active is None:
                        break
                    threading.Event().wait(.1)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    raise SystemExit(main())
