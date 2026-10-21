"""Render and exercise the AI panel in isolated desktop and narrow editor projects."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--proot", action="store_true")
    parser.add_argument("--output", default=".ai-qa/rendered")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    for name, resolution in (("desktop", "1280x900"), ("narrow", "480x900")):
        destination = output / name
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="godot-ai-render-") as directory:
            fixture = Path(directory) / "project"
            shutil.copytree(source / "tests/fixture", fixture,
                            ignore=shutil.ignore_patterns(".godot", "ai_test_*"))
            environment = {
                "GODOT_AI_QA_SOURCE": str(source),
                "GODOT_AI_QA_OUTPUT": str(destination),
                "XDG_CONFIG_HOME": str(Path(directory) / "config"),
                "XDG_DATA_HOME": str(Path(directory) / "data"),
            }
            command = ["xvfb-run", "-a", "-s", f"-screen 0 {resolution}x24 -ac",
                       args.godot, "--editor", "--rendering-method", "gl_compatibility",
                       "--audio-driver", "Dummy", "--resolution", resolution,
                       "--path", str(fixture)]
            if args.proot:
                command = ["proot-distro", "login", "debian", "--shared-home", "--", "env",
                           *(f"{key}={value}" for key, value in environment.items()), *command]
            report_path = destination / "editor-report.json"
            report_path.unlink(missing_ok=True)
            result = subprocess.run(command, env={**os.environ, **environment},
                                    capture_output=True, text=True, timeout=90)
            (destination / "editor.log").write_text(result.stdout + result.stderr)
            if result.returncode or not report_path.exists():
                print(result.stdout + result.stderr)
                raise SystemExit(f"{name}: editor verification failed ({result.returncode})")
            report = json.loads(report_path.read_text())
            print(f"{name}: {report['checks']} checks, {len(report['failures'])} failures")
            if not report["checks"] or report["failures"]:
                raise SystemExit(1)


if __name__ == "__main__":
    main()
